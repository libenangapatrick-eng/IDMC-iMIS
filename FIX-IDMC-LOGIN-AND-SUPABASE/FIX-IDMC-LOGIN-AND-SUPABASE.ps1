[CmdletBinding()]
param(
    [string]$OwnerEmail = "libenangapatrick@gmail.com",
    [ValidateSet("SUPER_ADMIN", "ADMIN")]
    [string]$OwnerRoleCode = "SUPER_ADMIN",
    [string]$ProjectRoot = "",
    [switch]$NoStartBackend,
    [switch]$SkipPermissionRepair
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Write-Step([string]$Text) {
    Write-Host "`n============================================================" -ForegroundColor DarkGray
    Write-Host $Text -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkGray
}

function Write-Ok([string]$Text) { Write-Host "[OK]   $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[WARN] $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "[FAIL] $Text" -ForegroundColor Red }

function Get-EnvValue([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^\s*$([regex]::Escape($Name))\s*="
    } | Select-Object -Last 1
    if (-not $line) { return $null }
    $value = ($line -split "=", 2)[1].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        if ($value.Length -ge 2) { $value = $value.Substring(1, $value.Length - 2) }
    }
    return $value
}

function Find-ProjectRoot([string]$ExplicitRoot) {
    $candidates = @()
    if ($ExplicitRoot) { $candidates += (Resolve-Path -LiteralPath $ExplicitRoot).Path }
    $candidates += (Get-Location).Path
    $candidates += $PSScriptRoot

    $seen = @{}
    foreach ($candidate in $candidates) {
        $current = $candidate
        while ($current) {
            if (-not $seen.ContainsKey($current)) {
                $seen[$current] = $true
                $envPath = Join-Path $current "apps\backend\.env"
                $backendPkg = Join-Path $current "apps\backend\package.json"
                $supabaseDir = Join-Path $current "supabase"
                if ((Test-Path $envPath) -and (Test-Path $backendPkg)) {
                    return $current
                }
                if (-not (Test-Path $supabaseDir) -and (Test-Path (Join-Path $current "apps"))) {
                    # Keep climbing; this branch only prevents noisy assumptions.
                }
            }
            $parent = Split-Path -Parent $current
            if (-not $parent -or $parent -eq $current) { break }
            $current = $parent
        }
    }
    throw "IDMC project root not found. Run this from C:\Users\liben\Documents\IDMC_iMIS or pass -ProjectRoot.`nExpected: <root>\apps\backend\.env"
}

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function First-NonEmpty([object[]]$Values, [string]$Default = "") {
    foreach ($v in $Values) {
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) {
            return [string]$v
        }
    }
    return $Default
}

function ConvertTo-PlainPassword([System.Security.SecureString]$SecurePassword) {
    if ($null -eq $SecurePassword) { return "" }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function New-Headers([string]$ApiKey) {
    return @{
        apikey        = $ApiKey
        Authorization = "Bearer $ApiKey"
        Accept        = "application/json"
        UserAgent     = "IDMC-iMIS-Login-Repair/1.0"
    }
}

function Get-HttpErrorBody($ErrorRecord) {
    try {
        $response = $ErrorRecord.Exception.Response
        if ($null -eq $response) { return $ErrorRecord.Exception.Message }
        $stream = $response.GetResponseStream()
        if ($null -eq $stream) { return $ErrorRecord.Exception.Message }
        $reader = New-Object System.IO.StreamReader($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
    } catch {
        return $ErrorRecord.Exception.Message
    }
}

function Invoke-SupabaseApi {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("GET","POST","PATCH")][string]$Method,
        [Parameter(Mandatory=$true)][string]$Path,
        $Body = $null,
        [string]$Prefer = ""
    )

    $headers = New-Headers $script:ServiceRoleKey
    if ($Prefer) { $headers.Prefer = $Prefer }

    $params = @{
        Method      = $Method
        Uri         = "$($script:SupabaseUrl)$Path"
        Headers     = $headers
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 30 -Compress)
    }

    try {
        return Invoke-RestMethod @params
    } catch {
        $detail = Get-HttpErrorBody $_
        throw "Supabase $Method $Path failed: $detail"
    }
}

function Escape-Q([string]$Value) {
    return [Uri]::EscapeDataString($Value)
}

function Get-Rows([string]$Table, [string]$Query) {
    return @(Invoke-SupabaseApi -Method GET -Path "/rest/v1/$Table`?$Query")
}

function Get-One([string]$Table, [string]$Query, [string]$Description) {
    $rows = @(Get-Rows $Table $Query)
    if ($rows.Count -gt 1) {
        throw "$Description returned $($rows.Count) rows. Repair stopped to avoid touching the wrong identity."
    }
    if ($rows.Count -eq 0) { return $null }
    return $rows[0]
}

function Add-Row([string]$Table, $Body) {
    $result = Invoke-SupabaseApi -Method POST -Path "/rest/v1/$Table" -Body $Body -Prefer "return=representation"
    $rows = @($result)
    if ($rows.Count -ne 1) { throw "Insert into $Table did not return exactly one row." }
    return $rows[0]
}

function Update-Row([string]$Table, [string]$Filter, $Body) {
    return @(Invoke-SupabaseApi -Method PATCH -Path "/rest/v1/$Table`?$Filter" -Body $Body -Prefer "return=representation")
}

function Get-AuthUsers {
    $items = @()
    for ($page = 1; $page -le 100; $page++) {
        $response = Invoke-SupabaseApi -Method GET -Path "/auth/v1/admin/users?page=$page&per_page=1000"
        foreach ($user in @($response.users)) { $items += $user }
        if (@($response.users).Count -lt 1000) { break }
    }
    return $items
}

function Get-AuthUserByEmail([object[]]$AuthUsers, [string]$Email) {
    $matches = @($AuthUsers | Where-Object { [string]$_.email -ieq $Email })
    if ($matches.Count -gt 1) {
        throw "Supabase Auth contains more than one user with email $Email. Repair stopped."
    }
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Get-AuthUserById([string]$AuthId) {
    if ([string]::IsNullOrWhiteSpace($AuthId)) { return $null }
    try {
        return Invoke-SupabaseApi -Method GET -Path "/auth/v1/admin/users/$AuthId"
    } catch {
        if ($_.Exception.Message -match "404|not_found|user_not_found") { return $null }
        throw
    }
}

function Ensure-ActiveRole([string]$RoleCode) {
    $encoded = Escape-Q $RoleCode
    $role = Get-One "roles" "select=id,role_code,role_name,description,is_system_role,status&role_code=eq.$encoded" "Role $RoleCode"
    if ($null -eq $role) {
        $names = @{
            SUPER_ADMIN = @("Super Administrator", "Full system administration access")
            ADMIN = @("Administrator", "Institutional administration access")
        }
        $meta = $names[$RoleCode]
        $role = Add-Row "roles" @{
            role_code = $RoleCode
            role_name = $meta[0]
            description = $meta[1]
            is_system_role = $true
            status = "ACTIVE"
        }
        Write-Ok "Created missing role $RoleCode."
    } elseif ([string]$role.status -ne "ACTIVE") {
        $updated = @(Update-Row "roles" "id=eq.$($role.id)" @{ status = "ACTIVE" })
        if ($updated.Count -ne 1) { throw "Could not activate role $RoleCode." }
        $role = $updated[0]
        Write-Ok "Activated role $RoleCode."
    } else {
        Write-Ok "Role $RoleCode exists and is ACTIVE."
    }
    return $role
}

function Ensure-UserRole([string]$UserId, [string]$RoleId, [string]$RoleCode) {
    $assignment = Get-One "user_roles" "select=id,status,expires_at&user_id=eq.$UserId&role_id=eq.$RoleId" "User-role $RoleCode"
    if ($null -eq $assignment) {
        [void](Add-Row "user_roles" @{ user_id=$UserId; role_id=$RoleId; status="ACTIVE"; expires_at=$null })
        Write-Ok "Assigned $RoleCode to IDMC user $UserId."
        return
    }

    $expired = $false
    if ($assignment.expires_at) {
        try { $expired = ([DateTime]$assignment.expires_at) -le (Get-Date).ToUniversalTime() } catch { $expired = $true }
    }

    if ([string]$assignment.status -ne "ACTIVE" -or $expired) {
        $updated = @(Update-Row "user_roles" "id=eq.$($assignment.id)" @{ status="ACTIVE"; expires_at=$null })
        if ($updated.Count -ne 1) { throw "Could not reactivate role assignment $RoleCode." }
        Write-Ok "Reactivated $RoleCode assignment."
    } else {
        Write-Ok "$RoleCode assignment already ACTIVE."
    }
}

function Repair-SuperAdminPermissions([string]$RoleId) {
    $permissions = @(Get-Rows "permissions" "select=id,status&status=eq.ACTIVE&limit=1000")
    if ($permissions.Count -eq 0) {
        Write-Warn "No ACTIVE permissions found; skipping permission links."
        return
    }

    $links = @()
    foreach ($p in $permissions) {
        $links += [ordered]@{ role_id=$RoleId; permission_id=$p.id }
    }

    # PostgREST can insert multiple rows in one request and ignore unique duplicates.
    try {
        [void](Invoke-SupabaseApi -Method POST -Path "/rest/v1/role_permissions" -Body $links -Prefer "resolution=ignore-duplicates,return=minimal")
        Write-Ok "SUPER_ADMIN permission links reconciled ($($permissions.Count) active permissions checked)."
    } catch {
        Write-Warn "Bulk permission reconciliation could not complete: $($_.Exception.Message)"
    }
}

function Get-UniqueUserNumber {
    for ($i = 0; $i -lt 20; $i++) {
        $candidate = "ADM-{0:yyyyMMdd-HHmmss}-{1}" -f (Get-Date), (Get-Random -Minimum 100 -Maximum 999)
        $exists = Get-One "users" "select=id&user_number=eq.$(Escape-Q $candidate)" "User number $candidate"
        if ($null -eq $exists) { return $candidate }
        Start-Sleep -Milliseconds 100
    }
    throw "Could not generate a unique IDMC user_number after 20 attempts."
}

function Get-UniqueUsername([string]$BaseUsername) {
    $base = ($BaseUsername.ToLower() -replace "[^a-z0-9._-]", "")
    if ([string]::IsNullOrWhiteSpace($base)) { $base = "admin" }
    if ($base.Length -gt 90) { $base = $base.Substring(0,90) }

    $candidate = $base
    for ($i = 0; $i -lt 100; $i++) {
        $existing = Get-One "users" "select=id,email,auth_user_id&username=eq.$(Escape-Q $candidate)" "Username $candidate"
        if ($null -eq $existing -or [string]$existing.email -ieq $script:OwnerEmail) { return $candidate }
        $candidate = "$base$($i + 1)"
    }
    throw "Could not generate a unique username from $BaseUsername."
}

function Get-FirstLastFromAuth($AuthUser) {
    $meta = Get-PropertyValue $AuthUser "user_metadata" ([pscustomobject]@{})
    $first = First-NonEmpty @(
        (Get-PropertyValue $meta "first_name"),
        (Get-PropertyValue $meta "firstname")
    ) "Patrick"
    $last = First-NonEmpty @(
        (Get-PropertyValue $meta "last_name"),
        (Get-PropertyValue $meta "lastname")
    ) "Libenanga"

    $full = First-NonEmpty @(
        (Get-PropertyValue $meta "full_name"),
        (Get-PropertyValue $meta "name")
    ) ""
    if (($first -eq "Patrick" -and $last -eq "Libenanga") -and $full) {
        $parts = @($full -split "\s+" | Where-Object { $_ })
        if ($parts.Count -ge 2) {
            $first = $parts[0]
            $last = $parts[$parts.Count - 1]
        }
    }
    return @($first.Trim(), $last.Trim())
}

function Ensure-ApplicationUser($AuthUser) {
    $authId = [string]$AuthUser.id
    $email = $script:OwnerEmail.ToLower()
    $byAuth = Get-One "users" "select=id,auth_user_id,user_number,username,first_name,middle_name,last_name,display_name,email,phone,status,email_verified_at&auth_user_id=eq.$(Escape-Q $authId)" "IDMC user mapped to Auth ID $authId"
    $byEmail = Get-One "users" "select=id,auth_user_id,user_number,username,first_name,middle_name,last_name,display_name,email,phone,status,email_verified_at&email=eq.$(Escape-Q $email)" "IDMC user with email $email"

    if ($byAuth -and $byEmail -and [string]$byAuth.id -ne [string]$byEmail.id) {
        throw "CONFLICT: Auth ID maps to IDMC user $($byAuth.id), while the email maps to a different IDMC user $($byEmail.id). No automatic rebind was performed."
    }

    if ($byAuth) {
        $user = $byAuth
        Write-Ok "Found existing IDMC user by auth_user_id: $($user.id)"
    } elseif ($byEmail) {
        $oldAuthId = [string]$byEmail.auth_user_id
        $oldAuthUser = Get-AuthUserById $oldAuthId
        if ($null -ne $oldAuthUser) {
            $oldEmail = [string]$oldAuthUser.email
            throw "CONFLICT: IDMC user $($byEmail.id) already belongs to another existing Supabase Auth user ($oldEmail / $oldAuthId). No automatic reassignment was performed."
        }

        $updated = @(Update-Row "users" "id=eq.$($byEmail.id)" @{
            auth_user_id = $authId
            email = $email
            status = "ACTIVE"
            failed_login_attempts = 0
            locked_until = $null
            email_verified_at = $AuthUser.email_confirmed_at
        })
        if ($updated.Count -ne 1) { throw "Failed to rebind stale IDMC user $($byEmail.id) to Auth user $authId." }
        $user = $updated[0]
        Write-Ok "Rebound existing stale IDMC user $($user.id) to the current Auth user without creating a duplicate."
    } else {
        $names = Get-FirstLastFromAuth $AuthUser
        $usernameSeed = ([string]$email).Split('@')[0]
        $username = Get-UniqueUsername $usernameSeed
        $userNumber = Get-UniqueUserNumber
        $metadata = Get-PropertyValue $AuthUser "user_metadata" ([pscustomobject]@{})
        $phone = First-NonEmpty @(
            (Get-PropertyValue $metadata "phone"),
            (Get-PropertyValue $AuthUser "phone")
        ) ""
        $display = "$($names[0]) $($names[1])".Trim()

        $body = @{
            auth_user_id = $authId
            user_number = $userNumber
            username = $username
            first_name = $names[0]
            last_name = $names[1]
            display_name = $display
            email = $email
            phone = $(if ($phone) { $phone } else { $null })
            status = "ACTIVE"
            failed_login_attempts = 0
            locked_until = $null
            email_verified_at = $AuthUser.email_confirmed_at
        }
        $user = Add-Row "users" $body
        Write-Ok "Created one missing IDMC application user for the existing Auth account: $($user.id)"
        Write-Host "       user_number : $($user.user_number)" -ForegroundColor Gray
        Write-Host "       username    : $($user.username)" -ForegroundColor Gray
    }

    if ([string]$user.status -ne "ACTIVE" -or [string]$user.email -ine $email -or [string]$user.auth_user_id -ine $authId) {
        $updated = @(Update-Row "users" "id=eq.$($user.id)" @{
            auth_user_id = $authId
            email = $email
            status = "ACTIVE"
            failed_login_attempts = 0
            locked_until = $null
            email_verified_at = $AuthUser.email_confirmed_at
        })
        if ($updated.Count -ne 1) { throw "Could not normalize the IDMC application user $($user.id)." }
        $user = $updated[0]
    }

    return $user
}

function Test-HttpEndpoint([string]$Uri, [string]$Method = "GET", $Body = $null, [hashtable]$Headers = $null) {
    try {
        $params = @{ Uri=$Uri; Method=$Method; ErrorAction="Stop" }
        if ($Headers) { $params.Headers = $Headers }
        if ($null -ne $Body) {
            $params.ContentType = "application/json"
            $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
        }
        return @{ Success=$true; Response=(Invoke-RestMethod @params); Error=$null; Status=$null }
    } catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode.value__ } catch {}
        return @{ Success=$false; Response=$null; Error=(Get-HttpErrorBody $_); Status=$status }
    }
}

function Ensure-Backend([string]$BackendRoot, [int]$Port) {
    $healthUri = "http://127.0.0.1:$Port/api/v1/health"
    $check = Test-HttpEndpoint $healthUri
    if ($check.Success) {
        Write-Ok "Backend is already running at http://127.0.0.1:$Port"
        return $null
    }

    if ($NoStartBackend) {
        Write-Warn "Backend is not running and -NoStartBackend was supplied. Login test will be skipped."
        return $null
    }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($null -eq $npm) {
        Write-Warn "npm was not found. Start the backend manually, then rerun the script."
        return $null
    }

    Write-Host "Starting IDMC backend in a separate PowerShell window..." -ForegroundColor Yellow
    $cmd = "Set-Location -LiteralPath '$BackendRoot'; npm run dev"
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit","-ExecutionPolicy","Bypass","-Command",$cmd) -PassThru

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $check = Test-HttpEndpoint $healthUri
        if ($check.Success) {
            Write-Ok "Backend is healthy at http://127.0.0.1:$Port"
            return $proc
        }
    }

    Write-Warn "Backend did not become healthy within 30 seconds. Check the new PowerShell window for startup errors."
    return $proc
}

function ConvertTo-SafeReport($AuthUser, $ApplicationUser, $Role, $ApiBase, $LoginResult, $MeResult) {
    return [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        email = $script:OwnerEmail
        auth = [ordered]@{
            id = Get-PropertyValue $AuthUser "id"
            email = Get-PropertyValue $AuthUser "email"
            email_confirmed_at = Get-PropertyValue $AuthUser "email_confirmed_at"
            created_at = Get-PropertyValue $AuthUser "created_at"
            last_sign_in_at = Get-PropertyValue $AuthUser "last_sign_in_at"
        }
        idmc_user = [ordered]@{
            id = Get-PropertyValue $ApplicationUser "id"
            auth_user_id = Get-PropertyValue $ApplicationUser "auth_user_id"
            user_number = Get-PropertyValue $ApplicationUser "user_number"
            username = Get-PropertyValue $ApplicationUser "username"
            email = Get-PropertyValue $ApplicationUser "email"
            status = Get-PropertyValue $ApplicationUser "status"
            first_name = Get-PropertyValue $ApplicationUser "first_name"
            last_name = Get-PropertyValue $ApplicationUser "last_name"
        }
        role = [ordered]@{
            id = Get-PropertyValue $Role "id"
            role_code = Get-PropertyValue $Role "role_code"
            status = Get-PropertyValue $Role "status"
        }
        api_base = $ApiBase
        login_test = [ordered]@{
            success = [bool]$LoginResult.Success
            status = $LoginResult.Status
            error = $LoginResult.Error
        }
        auth_me_test = [ordered]@{
            success = [bool]$MeResult.Success
            status = $MeResult.Status
            error = $MeResult.Error
        }
    }
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------
Write-Host ""; Write-Host "IDMC iMIS - LOGIN + SUPABASE IDENTITY RECONCILIATION" -ForegroundColor Green
Write-Host "This script repairs the existing account mapping; it does not delete Auth users." -ForegroundColor Gray
Write-Host ""

$script:ProjectRoot = Find-ProjectRoot $ProjectRoot
$backendRoot = Join-Path $script:ProjectRoot "apps\backend"
$backendEnv = Join-Path $backendRoot ".env"

Write-Step "1/7 - Loading IDMC configuration"
$script:SupabaseUrl = Get-EnvValue $backendEnv "SUPABASE_URL"
$script:ServiceRoleKey = Get-EnvValue $backendEnv "SUPABASE_SERVICE_ROLE_KEY"
$portText = Get-EnvValue $backendEnv "PORT"
$port = 4000
if ($portText) {
    try { $port = [int]$portText } catch { $port = 4000 }
}
if ([string]::IsNullOrWhiteSpace($script:SupabaseUrl)) { throw "SUPABASE_URL is missing from $backendEnv" }
if ([string]::IsNullOrWhiteSpace($script:ServiceRoleKey)) { throw "SUPABASE_SERVICE_ROLE_KEY is missing from $backendEnv" }
$script:SupabaseUrl = $script:SupabaseUrl.TrimEnd('/')
$apiBase = "http://127.0.0.1:$port/api/v1"
Write-Ok "Project root: $script:ProjectRoot"
Write-Ok "Supabase project: $script:SupabaseUrl"
Write-Ok "Target account: $OwnerEmail"

Write-Step "2/7 - Diagnosing Supabase Auth account"
$authUsers = @(Get-AuthUsers)
$authUser = Get-AuthUserByEmail $authUsers $OwnerEmail
if ($null -eq $authUser) {
    throw "Supabase Auth account $OwnerEmail was not found. No duplicate account will be created by this script."
}
Write-Ok "Auth account exists: $($authUser.id)"
Write-Host "       email confirmed: $($authUser.email_confirmed_at)" -ForegroundColor Gray
Write-Host "       created:         $($authUser.created_at)" -ForegroundColor Gray

Write-Step "3/7 - Diagnosing public.users mapping"
$applicationUser = Ensure-ApplicationUser $authUser
Write-Ok "IDMC user: $($applicationUser.id)"
Write-Ok "auth_user_id: $($applicationUser.auth_user_id)"
Write-Ok "status: $($applicationUser.status)"
Write-Ok "email: $($applicationUser.email)"

if ([string]$applicationUser.auth_user_id -ine [string]$authUser.id) {
    throw "Post-repair verification failed: public.users.auth_user_id does not equal the current auth.users id."
}
if ([string]$applicationUser.status -ne "ACTIVE") {
    throw "Post-repair verification failed: public.users.status is not ACTIVE."
}

Write-Step "4/7 - Activating role and assignment"
$role = Ensure-ActiveRole $OwnerRoleCode
Ensure-UserRole ([string]$applicationUser.id) ([string]$role.id) $OwnerRoleCode
if (-not $SkipPermissionRepair -and $OwnerRoleCode -eq "SUPER_ADMIN") {
    Repair-SuperAdminPermissions ([string]$role.id)
}

Write-Step "5/7 - Verifying final database identity"
$verify = Get-One "users" "select=id,auth_user_id,user_number,username,email,status&auth_user_id=eq.$(Escape-Q ([string]$authUser.id))" "Final IDMC identity check"
if ($null -eq $verify) { throw "Verification failed: no public.users row exists for auth_user_id $($authUser.id)." }
$roleVerify = Get-One "user_roles" "select=id,status,expires_at&user_id=eq.$($verify.id)&role_id=eq.$($role.id)" "Final role assignment check"
if ($null -eq $roleVerify -or [string]$roleVerify.status -ne "ACTIVE") { throw "Verification failed: $OwnerRoleCode is not ACTIVE for user $($verify.id)." }
Write-Ok "Identity mapping and active role verified."

Write-Step "6/7 - Testing /api/v1/auth/login and /api/v1/auth/me"
$backendProcess = Ensure-Backend $backendRoot $port
$loginResult = @{ Success=$false; Response=$null; Error="Backend login test not executed."; Status=$null }
$meResult = @{ Success=$false; Response=$null; Error="Backend /me test not executed."; Status=$null }

if ($null -ne $backendProcess -or (Test-HttpEndpoint "$apiBase/health").Success) {
    $health = Test-HttpEndpoint "$apiBase/auth/health"
    if ($health.Success) {
        Write-Ok "Auth health endpoint is online."
    } else {
        Write-Warn "Auth health endpoint failed: $($health.Error)"
    }

    Write-Host "Enter the EXISTING password for $OwnerEmail to perform the live login test." -ForegroundColor Yellow
    $securePassword = Read-Host "Password" -AsSecureString
    $password = ConvertTo-PlainPassword $securePassword
    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Warn "No password entered. Login test skipped."
    } else {
        $loginBody = @{ identifier=$OwnerEmail; password=$password }
        $loginResult = Test-HttpEndpoint "$apiBase/auth/login" "POST" $loginBody @{ Accept="application/json" }
        if (-not $loginResult.Success) {
            Write-Fail "Login test failed (HTTP $($loginResult.Status)): $($loginResult.Error)"
        } else {
            $session = Get-PropertyValue $loginResult.Response "data"
            $accessToken = Get-PropertyValue $session "access_token"
            if ([string]::IsNullOrWhiteSpace([string]$accessToken)) {
                Write-Fail "Login returned success but no access_token was returned."
            } else {
                Write-Ok "POST $apiBase/auth/login succeeded."
                $meHeaders = @{ Authorization="Bearer $accessToken"; Accept="application/json" }
                $meResult = Test-HttpEndpoint "$apiBase/auth/me" "GET" $null $meHeaders
                if ($meResult.Success) {
                    Write-Ok "GET $apiBase/auth/me succeeded — IDMC middleware accepted the Auth identity."
                } else {
                    Write-Fail "GET $apiBase/auth/me failed (HTTP $($meResult.Status)): $($meResult.Error)"
                }
            }
        }
    }
} else {
    Write-Warn "Backend is not available; database repair completed but live API login test could not run."
}

Write-Step "7/7 - Saving safe verification report"
$reportDir = Join-Path $script:ProjectRoot "storage\repair-reports"
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
$reportPath = Join-Path $reportDir ("FIX-IDMC-LOGIN-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
$report = ConvertTo-SafeReport $authUser $verify $role $apiBase $loginResult $meResult
$report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Ok "Report saved: $reportPath"

Write-Host ""
Write-Host "==================== FINAL RESULT ====================" -ForegroundColor Green
Write-Host "Supabase Auth account : EXISTS" -ForegroundColor Green
Write-Host "IDMC users mapping    : RECONCILED" -ForegroundColor Green
Write-Host "IDMC account status   : $($verify.status)" -ForegroundColor Green
Write-Host "Role                  : $OwnerRoleCode / $($roleVerify.status)" -ForegroundColor Green
if ($loginResult.Success) {
    Write-Host "API login             : PASS" -ForegroundColor Green
} else {
    Write-Host "API login             : NOT PASSED (see message above)" -ForegroundColor Yellow
}
if ($meResult.Success) {
    Write-Host "API /auth/me          : PASS" -ForegroundColor Green
} else {
    Write-Host "API /auth/me          : NOT PASSED (see message above)" -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Green
