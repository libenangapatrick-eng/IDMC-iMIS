# ============================================================
# IDMC iMIS
# STUDENT CORE - PHASE 2
# PowerShell Build
# ============================================================

$Root     = "C:\Users\liben\Documents\IDMC_iMIS"
$Backend  = Join-Path $Root "apps\backend"
$Frontend = Join-Path $Root "apps\frontend"
$Supabase = Join-Path $Root "supabase"

Set-Location $Root

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " IDMC iMIS - STUDENT CORE BUILD" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# 1. REQUIRED DIRECTORIES
# ------------------------------------------------------------

$Directories = @(
    "$Supabase\migrations",

    "$Backend\src\modules\student-management",
    "$Backend\src\modules\student-management\shared",
    "$Backend\src\modules\student-management\students",

    "$Frontend\assets\js"
)

foreach ($Directory in $Directories) {

    New-Item `
        -ItemType Directory `
        -Path $Directory `
        -Force |
        Out-Null

}

Write-Host "[1/8] Directories ready." -ForegroundColor Green

# ------------------------------------------------------------
# 2. MIGRATION 003
# ------------------------------------------------------------

$MigrationPath =
    Join-Path `
        $Supabase `
        "migrations\003_student_core.sql"

$Migration = @'
-- ============================================================
-- IDMC iMIS
-- MIGRATION 003
-- STUDENT CORE
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- STUDENT NUMBER SEQUENCE
-- ------------------------------------------------------------

create sequence if not exists public.student_number_seq
start with 1
increment by 1
no minvalue
no maxvalue
cache 1;

-- ------------------------------------------------------------
-- STUDENTS
-- ------------------------------------------------------------

create table if not exists public.students (

    id uuid primary key
        default gen_random_uuid(),

    institution_id uuid not null
        references public.institutions(id)
        on update cascade
        on delete restrict,

    user_id uuid null
        references public.users(id)
        on update cascade
        on delete set null,

    student_number varchar(50) not null
        unique
        default (
            'IDMC/STU/' ||
            extract(year from now())::integer ||
            '/' ||
            lpad(
                nextval('public.student_number_seq')::text,
                5,
                '0'
            )
        ),

    first_name varchar(100) not null,

    middle_name varchar(100),

    last_name varchar(100) not null,

    gender varchar(30),

    date_of_birth date,

    nationality varchar(100),

    national_id varchar(100),

    passport_number varchar(100),

    phone varchar(50),

    email varchar(255),

    physical_address text,

    postal_address text,

    emergency_contact_name varchar(200),

    emergency_contact_phone varchar(50),

    admission_year integer,

    entry_type varchar(50),

    student_status varchar(50)
        not null default 'ACTIVE',

    profile_photo_url text,

    notes text,

    created_at timestamptz
        not null default now(),

    updated_at timestamptz
        not null default now()
);

-- ------------------------------------------------------------
-- INDEXES
-- ------------------------------------------------------------

create index if not exists
    idx_students_institution_id
on public.students(institution_id);

create index if not exists
    idx_students_user_id
on public.students(user_id);

create index if not exists
    idx_students_student_number
on public.students(student_number);

create index if not exists
    idx_students_email
on public.students(email);

create index if not exists
    idx_students_status
on public.students(student_status);

create index if not exists
    idx_students_names
on public.students(last_name, first_name);

-- ------------------------------------------------------------
-- UPDATED AT
-- ------------------------------------------------------------

create or replace function
public.set_students_updated_at()
returns trigger
language plpgsql
as $$
begin

    new.updated_at = now();

    return new;

end;
$$;

drop trigger if exists
trg_students_updated_at
on public.students;

create trigger
trg_students_updated_at

before update
on public.students

for each row

execute function
public.set_students_updated_at();

-- ------------------------------------------------------------
-- RLS
-- Backend uses service-role access.
-- Client-side direct table access remains blocked.
-- ------------------------------------------------------------

alter table public.students enable row level security;

-- ------------------------------------------------------------
-- STUDENT PERMISSIONS
-- ------------------------------------------------------------

insert into public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
values

(
    'students.view',
    'View students',
    'students',
    'view'
),

(
    'students.manage',
    'Manage students',
    'students',
    'manage'
)

on conflict (permission_code)
do nothing;

-- ------------------------------------------------------------
-- STUDENT PORTAL PERMISSION
-- ------------------------------------------------------------

insert into public.permissions (
    permission_code,
    permission_name,
    module_code,
    action_code
)
values

(
    'portal.student',
    'Access student portal',
    'portal',
    'student'
)

on conflict (permission_code)
do nothing;

-- ------------------------------------------------------------
-- STUDENT ROLE
-- ------------------------------------------------------------

insert into public.roles (
    role_code,
    role_name,
    description,
    is_system_role,
    status
)
values

(
    'STUDENT',
    'Student',
    'Student self-service account',
    true,
    'ACTIVE'
)

on conflict (role_code)
do nothing;

-- ------------------------------------------------------------
-- GRANT STUDENT VIEW/MANAGE TO ADMIN
-- ------------------------------------------------------------

insert into public.role_permissions (
    role_id,
    permission_id,
    status
)

select
    r.id,
    p.id,
    'ACTIVE'

from public.roles r

cross join public.permissions p

where r.role_code = 'ADMIN'

and p.permission_code in (
    'students.view',
    'students.manage'
)

on conflict do nothing;

-- ------------------------------------------------------------
-- GRANT STUDENT PORTAL TO STUDENT ROLE
-- ------------------------------------------------------------

insert into public.role_permissions (
    role_id,
    permission_id,
    status
)

select
    r.id,
    p.id,
    'ACTIVE'

from public.roles r

cross join public.permissions p

where r.role_code = 'STUDENT'

and p.permission_code = 'portal.student'

on conflict do nothing;

'@

Set-Content `
    -Path $MigrationPath `
    -Value $Migration `
    -Encoding UTF8

Write-Host "[2/8] Migration 003 created." -ForegroundColor Green

# ------------------------------------------------------------
# 3. TYPES
# ------------------------------------------------------------

$TypesPath =
    Join-Path `
        $Backend `
        "src\modules\student-management\shared\student.types.ts"

$Types = @'
export interface CreateStudentInput {
    institutionId: string;

    userId?: string | null;

    firstName: string;

    middleName?: string | null;

    lastName: string;

    gender?: string | null;

    dateOfBirth?: string | null;

    nationality?: string | null;

    nationalId?: string | null;

    passportNumber?: string | null;

    phone?: string | null;

    email?: string | null;

    physicalAddress?: string | null;

    postalAddress?: string | null;

    emergencyContactName?: string | null;

    emergencyContactPhone?: string | null;

    admissionYear?: number | null;

    entryType?: string | null;

    studentStatus?: string;

    profilePhotoUrl?: string | null;

    notes?: string | null;
}

export interface UpdateStudentInput {
    institutionId?: string;

    userId?: string | null;

    firstName?: string;

    middleName?: string | null;

    lastName?: string;

    gender?: string | null;

    dateOfBirth?: string | null;

    nationality?: string | null;

    nationalId?: string | null;

    passportNumber?: string | null;

    phone?: string | null;

    email?: string | null;

    physicalAddress?: string | null;

    postalAddress?: string | null;

    emergencyContactName?: string | null;

    emergencyContactPhone?: string | null;

    admissionYear?: number | null;

    entryType?: string | null;

    studentStatus?: string;

    profilePhotoUrl?: string | null;

    notes?: string | null;
}

export interface StudentListOptions {
    page?: number;

    limit?: number;

    search?: string;

    status?: string;

    institutionId?: string;
}

export interface StudentActorContext {
    userId: string;

    ipAddress?: string | null;

    requestId?: string | null;
}
'@

Set-Content `
    -Path $TypesPath `
    -Value $Types `
    -Encoding UTF8

# ------------------------------------------------------------
# 4. STUDENT SERVICE
# ------------------------------------------------------------

$ServicePath =
    Join-Path `
        $Backend `
        "src\modules\student-management\students\students.service.ts"

$Service = @'
import {
    institutionDb,
} from "../../institution-management/shared/institution-db.js";

import type {
    CreateStudentInput,
    UpdateStudentInput,
    StudentListOptions,
    StudentActorContext,
} from "../shared/student.types.js";

function normalizeString(
    value?: string | null
): string | null {

    if (value === undefined || value === null) {
        return null;
    }

    const normalized =
        value.trim();

    return normalized || null;
}

function requireString(
    value: unknown,
    fieldName: string
): string {

    if (
        typeof value !== "string" ||
        !value.trim()
    ) {
        throw new Error(
            `${fieldName} is required.`
        );
    }

    return value.trim();
}

function isValidUuid(
    value?: string | null
): boolean {

    if (!value) {
        return false;
    }

    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value);
}

async function createAuditLog(
    context: StudentActorContext,
    actionCode: string,
    entityId: string | null,
    oldValues?: unknown,
    newValues?: unknown
): Promise<void> {

    const {
        error,
    } = await institutionDb
        .from("audit_logs")
        .insert({
            actor_user_id:
                context.userId,

            action_code:
                actionCode,

            module_code:
                "students",

            entity_type:
                "student",

            entity_id:
                entityId,

            old_values:
                oldValues ?? null,

            new_values:
                newValues ?? null,

            ip_address:
                context.ipAddress ?? null,

            request_id:
                context.requestId ?? null,
        });

    if (error) {
        console.error(
            "Student audit log failed:",
            error
        );
    }
}

async function ensureInstitution(
    institutionId: string
): Promise<void> {

    if (!isValidUuid(institutionId)) {
        throw new Error(
            "institutionId must be a valid UUID."
        );
    }

    const {
        data,
        error,
    } = await institutionDb
        .from("institutions")
        .select("id")
        .eq("id", institutionId)
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to validate institution: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "Institution not found."
        );
    }
}

async function ensureUser(
    userId?: string | null
): Promise<void> {

    if (!userId) {
        return;
    }

    if (!isValidUuid(userId)) {
        throw new Error(
            "userId must be a valid UUID."
        );
    }

    const {
        data,
        error,
    } = await institutionDb
        .from("users")
        .select("id")
        .eq("id", userId)
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to validate user: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "Linked user was not found."
        );
    }
}

export async function listStudents(
    options: StudentListOptions = {}
) {

    const page =
        Math.max(
            1,
            Number(options.page ?? 1)
        );

    const limit =
        Math.min(
            100,
            Math.max(
                1,
                Number(options.limit ?? 25)
            )
        );

    const from =
        (page - 1) * limit;

    const to =
        from + limit - 1;

    let query =
        institutionDb
            .from("students")
            .select(
                `
                id,
                institution_id,
                user_id,
                student_number,
                first_name,
                middle_name,
                last_name,
                gender,
                date_of_birth,
                nationality,
                national_id,
                passport_number,
                phone,
                email,
                physical_address,
                postal_address,
                emergency_contact_name,
                emergency_contact_phone,
                admission_year,
                entry_type,
                student_status,
                profile_photo_url,
                notes,
                created_at,
                updated_at
                `,
                {
                    count: "exact",
                }
            )
            .range(from, to)
            .order(
                "created_at",
                {
                    ascending: false,
                }
            );

    if (options.institutionId) {

        if (
            !isValidUuid(
                options.institutionId
            )
        ) {
            throw new Error(
                "institutionId must be a valid UUID."
            );
        }

        query =
            query.eq(
                "institution_id",
                options.institutionId
            );
    }

    if (options.status) {
        query =
            query.eq(
                "student_status",
                options.status
            );
    }

    if (options.search) {

        const search =
            options.search
                .trim()
                .replace(/[%_,]/g, " ");

        if (search) {

            query =
                query.or(
                    [
                        `student_number.ilike.%${search}%`,
                        `first_name.ilike.%${search}%`,
                        `middle_name.ilike.%${search}%`,
                        `last_name.ilike.%${search}%`,
                        `email.ilike.%${search}%`,
                        `phone.ilike.%${search}%`
                    ].join(",")
                );
        }
    }

    const {
        data,
        error,
        count,
    } = await query;

    if (error) {
        throw new Error(
            `Unable to load students: ${error.message}`
        );
    }

    return {
        items: data ?? [],

        pagination: {
            page,

            limit,

            total:
                count ?? 0,

            totalPages:
                Math.ceil(
                    (count ?? 0) / limit
                ),
        },
    };
}

export async function getStudentById(
    id: string
) {

    if (!isValidUuid(id)) {
        throw new Error(
            "Student id must be a valid UUID."
        );
    }

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .select(
            `
            id,
            institution_id,
            user_id,
            student_number,
            first_name,
            middle_name,
            last_name,
            gender,
            date_of_birth,
            nationality,
            national_id,
            passport_number,
            phone,
            email,
            physical_address,
            postal_address,
            emergency_contact_name,
            emergency_contact_phone,
            admission_year,
            entry_type,
            student_status,
            profile_photo_url,
            notes,
            created_at,
            updated_at
            `
        )
        .eq("id", id)
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to load student: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "Student not found."
        );
    }

    return data;
}

export async function getStudentByUserId(
    userId: string
) {

    if (!isValidUuid(userId)) {
        throw new Error(
            "User id must be a valid UUID."
        );
    }

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .select(
            `
            id,
            institution_id,
            user_id,
            student_number,
            first_name,
            middle_name,
            last_name,
            gender,
            date_of_birth,
            nationality,
            national_id,
            passport_number,
            phone,
            email,
            physical_address,
            postal_address,
            emergency_contact_name,
            emergency_contact_phone,
            admission_year,
            entry_type,
            student_status,
            profile_photo_url,
            notes,
            created_at,
            updated_at
            `
        )
        .eq("user_id", userId)
        .maybeSingle();

    if (error) {
        throw new Error(
            `Unable to load student account: ${error.message}`
        );
    }

    if (!data) {
        throw new Error(
            "No student record is linked to this account."
        );
    }

    return data;
}

export async function createStudent(
    input: CreateStudentInput,
    context: StudentActorContext
) {

    const institutionId =
        requireString(
            input.institutionId,
            "institutionId"
        );

    const firstName =
        requireString(
            input.firstName,
            "firstName"
        );

    const lastName =
        requireString(
            input.lastName,
            "lastName"
        );

    await ensureInstitution(
        institutionId
    );

    await ensureUser(
        input.userId
    );

    const payload = {

        institution_id:
            institutionId,

        user_id:
            normalizeString(
                input.userId
            ),

        first_name:
            firstName,

        middle_name:
            normalizeString(
                input.middleName
            ),

        last_name:
            lastName,

        gender:
            normalizeString(
                input.gender
            ),

        date_of_birth:
            normalizeString(
                input.dateOfBirth
            ),

        nationality:
            normalizeString(
                input.nationality
            ),

        national_id:
            normalizeString(
                input.nationalId
            ),

        passport_number:
            normalizeString(
                input.passportNumber
            ),

        phone:
            normalizeString(
                input.phone
            ),

        email:
            normalizeString(
                input.email
            ),

        physical_address:
            normalizeString(
                input.physicalAddress
            ),

        postal_address:
            normalizeString(
                input.postalAddress
            ),

        emergency_contact_name:
            normalizeString(
                input.emergencyContactName
            ),

        emergency_contact_phone:
            normalizeString(
                input.emergencyContactPhone
            ),

        admission_year:
            input.admissionYear ??
            null,

        entry_type:
            normalizeString(
                input.entryType
            ),

        student_status:
            input.studentStatus ??
            "ACTIVE",

        profile_photo_url:
            normalizeString(
                input.profilePhotoUrl
            ),

        notes:
            normalizeString(
                input.notes
            ),
    };

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .insert(payload)
        .select()
        .single();

    if (error || !data) {

        throw new Error(
            error?.message ||
            "Unable to create student."
        );
    }

    await createAuditLog(
        context,
        "STUDENT_CREATE",
        data.id,
        null,
        data
    );

    return data;
}

export async function updateStudent(
    id: string,
    input: UpdateStudentInput,
    context: StudentActorContext
) {

    const current =
        await getStudentById(id);

    if (
        input.institutionId !== undefined
    ) {

        await ensureInstitution(
            input.institutionId
        );
    }

    await ensureUser(
        input.userId
    );

    const updates: Record<
        string,
        unknown
    > = {};

    if (
        input.institutionId !== undefined
    ) {
        updates.institution_id =
            input.institutionId;
    }

    if (
        input.userId !== undefined
    ) {
        updates.user_id =
            normalizeString(
                input.userId
            );
    }

    if (
        input.firstName !== undefined
    ) {
        updates.first_name =
            requireString(
                input.firstName,
                "firstName"
            );
    }

    if (
        input.middleName !== undefined
    ) {
        updates.middle_name =
            normalizeString(
                input.middleName
            );
    }

    if (
        input.lastName !== undefined
    ) {
        updates.last_name =
            requireString(
                input.lastName,
                "lastName"
            );
    }

    if (
        input.gender !== undefined
    ) {
        updates.gender =
            normalizeString(
                input.gender
            );
    }

    if (
        input.dateOfBirth !== undefined
    ) {
        updates.date_of_birth =
            normalizeString(
                input.dateOfBirth
            );
    }

    if (
        input.nationality !== undefined
    ) {
        updates.nationality =
            normalizeString(
                input.nationality
            );
    }

    if (
        input.nationalId !== undefined
    ) {
        updates.national_id =
            normalizeString(
                input.nationalId
            );
    }

    if (
        input.passportNumber !== undefined
    ) {
        updates.passport_number =
            normalizeString(
                input.passportNumber
            );
    }

    if (
        input.phone !== undefined
    ) {
        updates.phone =
            normalizeString(
                input.phone
            );
    }

    if (
        input.email !== undefined
    ) {
        updates.email =
            normalizeString(
                input.email
            );
    }

    if (
        input.physicalAddress !== undefined
    ) {
        updates.physical_address =
            normalizeString(
                input.physicalAddress
            );
    }

    if (
        input.postalAddress !== undefined
    ) {
        updates.postal_address =
            normalizeString(
                input.postalAddress
            );
    }

    if (
        input.emergencyContactName !== undefined
    ) {
        updates.emergency_contact_name =
            normalizeString(
                input.emergencyContactName
            );
    }

    if (
        input.emergencyContactPhone !== undefined
    ) {
        updates.emergency_contact_phone =
            normalizeString(
                input.emergencyContactPhone
            );
    }

    if (
        input.admissionYear !== undefined
    ) {
        updates.admission_year =
            input.admissionYear;
    }

    if (
        input.entryType !== undefined
    ) {
        updates.entry_type =
            normalizeString(
                input.entryType
            );
    }

    if (
        input.studentStatus !== undefined
    ) {
        updates.student_status =
            input.studentStatus;
    }

    if (
        input.profilePhotoUrl !== undefined
    ) {
        updates.profile_photo_url =
            normalizeString(
                input.profilePhotoUrl
            );
    }

    if (
        input.notes !== undefined
    ) {
        updates.notes =
            normalizeString(
                input.notes
            );
    }

    if (!Object.keys(updates).length) {
        return current;
    }

    const {
        data,
        error,
    } = await institutionDb
        .from("students")
        .update(updates)
        .eq("id", id)
        .select()
        .single();

    if (error || !data) {

        throw new Error(
            error?.message ||
            "Unable to update student."
        );
    }

    await createAuditLog(
        context,
        "STUDENT_UPDATE",
        id,
        current,
        data
    );

    return data;
}
'@

Set-Content `
    -Path $ServicePath `
    -Value $Service `
    -Encoding UTF8

# ------------------------------------------------------------
# 5. CONTROLLER
# ------------------------------------------------------------

$ControllerPath =
    Join-Path `
        $Backend `
        "src\modules\student-management\students\students.controller.ts"

$Controller = @'
import type {
    Request,
    Response,
} from "express";

import {
    createStudent,
    getStudentById,
    getStudentByUserId,
    listStudents,
    updateStudent,
} from "./students.service.js";

function getActorUserId(
    request: Request
): string {

    const user =
        (request as any).user;

    const userId =
        user?.id ||
        user?.userId ||
        user?.user_id ||
        user?.publicUserId;

    if (
        typeof userId !== "string" ||
        !userId
    ) {
        throw new Error(
            "Authenticated public user id is unavailable."
        );
    }

    return userId;
}

function getContext(
    request: Request
) {

    return {
        userId:
            getActorUserId(
                request
            ),

        ipAddress:
            request.ip ||
            null,

        requestId:
            (request as any).requestId ||
            request.header(
                "x-request-id"
            ) ||
            null,
    };
}

function sendSuccess(
    response: Response,
    data: unknown
) {

    return response
        .status(200)
        .json({
            success: true,
            data,
        });
}

function sendCreated(
    response: Response,
    data: unknown
) {

    return response
        .status(201)
        .json({
            success: true,
            data,
        });
}

function sendError(
    response: Response,
    error: unknown
) {

    const message =
        error instanceof Error
            ? error.message
            : "Unexpected server error.";

    return response
        .status(400)
        .json({
            success: false,
            message,
        });
}

export async function listStudentsController(
    request: Request,
    response: Response
) {

    try {

        const result =
            await listStudents({
                page:
                    request.query.page
                        ? Number(
                            request.query.page
                        )
                        : 1,

                limit:
                    request.query.limit
                        ? Number(
                            request.query.limit
                        )
                        : 25,

                search:
                    typeof request.query.search === "string"
                        ? request.query.search
                        : undefined,

                status:
                    typeof request.query.status === "string"
                        ? request.query.status
                        : undefined,

                institutionId:
                    typeof request.query.institutionId === "string"
                        ? request.query.institutionId
                        : undefined,
            });

        return sendSuccess(
            response,
            result
        );

    } catch (error) {

        return sendError(
            response,
            error
        );
    }
}

export async function getStudentController(
    request: Request,
    response: Response
) {

    try {

        const student =
            await getStudentById(
                request.params.id
            );

        return sendSuccess(
            response,
            student
        );

    } catch (error) {

        return sendError(
            response,
            error
        );
    }
}

export async function getMyStudentController(
    request: Request,
    response: Response
) {

    try {

        const student =
            await getStudentByUserId(
                getActorUserId(
                    request
                )
            );

        return sendSuccess(
            response,
            student
        );

    } catch (error) {

        return sendError(
            response,
            error
        );
    }
}

export async function createStudentController(
    request: Request,
    response: Response
) {

    try {

        const student =
            await createStudent(
                request.body,
                getContext(request)
            );

        return sendCreated(
            response,
            student
        );

    } catch (error) {

        return sendError(
            response,
            error
        );
    }
}

export async function updateStudentController(
    request: Request,
    response: Response
) {

    try {

        const student =
            await updateStudent(
                request.params.id,
                request.body,
                getContext(request)
            );

        return sendSuccess(
            response,
            student
        );

    } catch (error) {

        return sendError(
            response,
            error
        );
    }
}
'@

Set-Content `
    -Path $ControllerPath `
    -Value $Controller `
    -Encoding UTF8

# ------------------------------------------------------------
# 6. ROUTES
# ------------------------------------------------------------

$RoutesPath =
    Join-Path `
        $Backend `
        "src\modules\student-management\students\students.routes.ts"

$Routes = @'
import {
    Router,
} from "express";

import {
    authenticate,
} from "../../../middleware/authenticate.js";

import {
    requirePermission,
} from "../../../middleware/rbac.js";

import {
    createStudentController,
    getMyStudentController,
    getStudentController,
    listStudentsController,
    updateStudentController,
} from "./students.controller.js";

const router =
    Router();

router.use(
    authenticate
);

router.get(
    "/students",
    requirePermission(
        "students.view"
    ),
    listStudentsController
);

router.get(
    "/students/me",
    requirePermission(
        "portal.student"
    ),
    getMyStudentController
);

router.get(
    "/students/:id",
    requirePermission(
        "students.view"
    ),
    getStudentController
);

router.post(
    "/students",
    requirePermission(
        "students.manage"
    ),
    createStudentController
);

router.patch(
    "/students/:id",
    requirePermission(
        "students.manage"
    ),
    updateStudentController
);

export default router;
'@

Set-Content `
    -Path $RoutesPath `
    -Value $Routes `
    -Encoding UTF8

# ------------------------------------------------------------
# 7. MODULE ROUTE
# ------------------------------------------------------------

$ModuleRoutesPath =
    Join-Path `
        $Backend `
        "src\modules\student-management\student-management.routes.ts"

$ModuleRoutes = @'
import {
    Router,
} from "express";

import studentRoutes
    from "./students/students.routes.js";

const router =
    Router();

router.use(
    studentRoutes
);

export default router;
'@

Set-Content `
    -Path $ModuleRoutesPath `
    -Value $ModuleRoutes `
    -Encoding UTF8

Write-Host "[3/8] Student backend files created." -ForegroundColor Green

# ------------------------------------------------------------
# 8. AUTO-MOUNT STUDENT ROUTE
# ------------------------------------------------------------

$EntryCandidates =
    Get-ChildItem `
        -Path "$Backend\src" `
        -Recurse `
        -File `
        -Include *.ts |
    Where-Object {

        $_.Name -notmatch '\.d\.ts$'

    }

$EntryFile = $null

foreach ($Candidate in $EntryCandidates) {

    $Content =
        Get-Content `
            -Path $Candidate.FullName `
            -Raw

    if (
        $Content -match "express\s*\(" -and
        $Content -match "app\.use" -and
        $Content -match "listen\s*\("
    ) {

        $EntryFile = $Candidate

        break
    }
}

if ($null -ne $EntryFile) {

    $EntryContent =
        Get-Content `
            -Path $EntryFile.FullName `
            -Raw

    $ModuleFile =
        Join-Path `
            $Backend `
            "src\modules\student-management\student-management.routes.ts"

    $RelativeImport =
        [System.IO.Path]::GetRelativePath(
            $EntryFile.Directory.FullName,
            $ModuleFile
        ).Replace("\","/")

    if (
        $RelativeImport.StartsWith("./") -eq $false
    ) {
        $RelativeImport =
            "./$RelativeImport"
    }

    $RelativeImport =
        $RelativeImport `
            -replace '\.ts$','.js'

    if (
        $EntryContent -notmatch
        "student-management/student-management.routes"
    ) {

        $ImportLine =
            "import studentManagementRoutes from `"$RelativeImport`";"

        $ImportMatches =
            [regex]::Matches(
                $EntryContent,
                '(?m)^\s*import .*?;\s*$'
            )

        if (
            $ImportMatches.Count -gt 0
        ) {

            $LastImport =
                $ImportMatches[
                    $ImportMatches.Count - 1
                ]

            $InsertAt =
                $LastImport.Index +
                $LastImport.Length

            $EntryContent =
                $EntryContent.Insert(
                    $InsertAt,
                    "`r`n$ImportLine"
                )

        }
        else {

            $EntryContent =
                "$ImportLine`r`n$EntryContent"

        }
    }

    if (
        $EntryContent -notmatch
        'app\.use\s*\(\s*["'']/api/v1["'']\s*,\s*studentManagementRoutes'
    ) {

        $RouteMount =
            'app.use("/api/v1", studentManagementRoutes);'

        $ListenMatch =
            [regex]::Match(
                $EntryContent,
                '(?m)^\s*(?:app|server)\.listen\s*\('
            )

        if (
            $ListenMatch.Success
        ) {

            $EntryContent =
                $EntryContent.Insert(
                    $ListenMatch.Index,
                    "`r`n$RouteMount`r`n`r`n"
                )

        }
        else {

            $EntryContent +=
                "`r`n`r`n$RouteMount`r`n"

        }
    }

    Set-Content `
        -Path $EntryFile.FullName `
        -Value $EntryContent `
        -Encoding UTF8

    Write-Host ""
    Write-Host "Student routes mounted into:" -ForegroundColor Green
    Write-Host "  $($EntryFile.FullName)" -ForegroundColor White

}
else {

    Write-Host ""
    Write-Host "WARNING: Backend entry point was not auto-detected." -ForegroundColor Yellow
    Write-Host "Student route files were created but NOT mounted automatically." -ForegroundColor Yellow

}

# ------------------------------------------------------------
# 9. STUDENTS FRONTEND JS
# ------------------------------------------------------------

$StudentsJsPath =
    Join-Path `
        $Frontend `
        "assets\js\students.js"

$StudentsJs = @'
(() => {

    "use strict";

    const REQUIRED_PERMISSION =
        "students.view";

    let students = [];

    const $ =
        (selector) =>
            document.querySelector(
                selector
            );

    function escapeHtml(
        value
    ) {

        return String(
            value ?? ""
        )
            .replace(
                /&/g,
                "&amp;"
            )
            .replace(
                /</g,
                "&lt;"
            )
            .replace(
                />/g,
                "&gt;"
            )
            .replace(
                /"/g,
                "&quot;"
            )
            .replace(
                /'/g,
                "&#039;"
            );

    }

    function setStatus(
        text
    ) {

        const element =
            $("#studentsStatus");

        if (element) {
            element.textContent =
                text;
        }

    }

    function getStudentName(
        student
    ) {

        return [
            student.first_name,
            student.middle_name,
            student.last_name
        ]
            .filter(Boolean)
            .join(" ");

    }

    function render(
        records
    ) {

        const body =
            $("#studentsBody");

        if (!body) {
            return;
        }

        if (!records.length) {

            body.innerHTML = `
                <tr>
                    <td
                        colspan="7"
                        class="empty-state"
                    >
                        No student records found.
                    </td>
                </tr>
            `;

            return;
        }

        body.innerHTML =
            records
                .map(
                    student => `
                        <tr>

                            <td>
                                ${escapeHtml(
                                    student.student_number
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    getStudentName(
                                        student
                                    )
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.gender ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.email ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.phone ||
                                    "—"
                                )}
                            </td>

                            <td>
                                ${escapeHtml(
                                    student.student_status ||
                                    "—"
                                )}
                            </td>

                            <td>

                                <a
                                    class="view-link"
                                    href="#"
                                    data-student-id="${
                                        escapeHtml(
                                            student.id
                                        )
                                    }"
                                >
                                    View
                                </a>

                            </td>

                        </tr>
                    `
                )
                .join("");

    }

    async function loadStudents() {

        setStatus(
            "Loading students..."
        );

        const body =
            $("#studentsBody");

        if (body) {

            body.innerHTML = `
                <tr>
                    <td
                        colspan="7"
                        class="loading-state"
                    >
                        Loading student records...
                    </td>
                </tr>
            `;

        }

        try {

            if (
                !window.IDMC_RBAC_API ||
                typeof
                    window.IDMC_RBAC_API.request !==
                    "function"
            ) {

                throw new Error(
                    "IDMC frontend RBAC API is not available."
                );

            }

            if (
                typeof
                    window.IDMC_RBAC_API.hasPermission ===
                    "function"
            ) {

                if (
                    !window.IDMC_RBAC_API.hasPermission(
                        REQUIRED_PERMISSION
                    )
                ) {

                    throw new Error(
                        "You do not have permission to view students."
                    );

                }

            }

            const search =
                $("#studentSearch")
                    ?.value
                    ?.trim() || "";

            const status =
                $("#studentStatus")
                    ?.value
                    ?.trim() || "";

            const params =
                new URLSearchParams();

            params.set(
                "page",
                "1"
            );

            params.set(
                "limit",
                "50"
            );

            if (search) {
                params.set(
                    "search",
                    search
                );
            }

            if (status) {
                params.set(
                    "status",
                    status
                );
            }

            const result =
                await window.IDMC_RBAC_API.request(
                    `/students?${params.toString()}`
                );

            students =
                Array.isArray(
                    result?.data?.items
                )
                    ? result.data.items
                    : [];

            render(
                students
            );

            setStatus(
                `${students.length} student(s)`
            );

        } catch (error) {

            console.error(
                "Students load failed:",
                error
            );

            students = [];

            if (body) {

                body.innerHTML = `
                    <tr>
                        <td
                            colspan="7"
                            class="error-state"
                        >
                            ${escapeHtml(
                                error?.message ||
                                "Unable to load students."
                            )}
                        </td>
                    </tr>
                `;

            }

            setStatus(
                "Unable to load"
            );

        }

    }

    async function viewStudent(
        id
    ) {

        if (!id) {
            return;
        }

        try {

            const result =
                await window.IDMC_RBAC_API.request(
                    `/students/${encodeURIComponent(id)}`
                );

            const student =
                result?.data;

            if (!student) {
                throw new Error(
                    "Student record not found."
                );
            }

            const name =
                getStudentName(
                    student
                );

            alert(
                [
                    `Student Number: ${
                        student.student_number ||
                        "—"
                    }`,
                    `Name: ${name || "—"}`,
                    `Status: ${
                        student.student_status ||
                        "—"
                    }`,
                    `Email: ${
                        student.email ||
                        "—"
                    }`,
                    `Phone: ${
                        student.phone ||
                        "—"
                    }`
                ].join("\n")
            );

        } catch (error) {

            console.error(
                "Student details failed:",
                error
            );

            alert(
                error?.message ||
                "Unable to load student details."
            );

        }

    }

    document.addEventListener(
        "click",
        event => {

            const link =
                event.target.closest(
                    "[data-student-id]"
                );

            if (!link) {
                return;
            }

            event.preventDefault();

            viewStudent(
                link.dataset.studentId
            );

        }
    );

    $("#studentSearch")
        ?.addEventListener(
            "input",
            () => {

                clearTimeout(
                    window.__idmcStudentSearchTimer
                );

                window.__idmcStudentSearchTimer =
                    setTimeout(
                        loadStudents,
                        300
                    );

            }
        );

    $("#studentStatus")
        ?.addEventListener(
            "change",
            loadStudents
        );

    $("#refreshStudents")
        ?.addEventListener(
            "click",
            loadStudents
        );

    async function initialize() {

        try {

            if (
                window.IDMCAuth &&
                typeof
                    window.IDMCAuth.requireAuth ===
                    "function"
            ) {

                await window.IDMCAuth.requireAuth();

            }

            await loadStudents();

        } catch (error) {

            console.error(
                "Student page initialization failed:",
                error
            );

        }

    }

    if (
        document.readyState ===
        "loading"
    ) {

        document.addEventListener(
            "DOMContentLoaded",
            initialize,
            {
                once: true
            }
        );

    } else {

        initialize();

    }

    window.IDMC_STUDENTS = {
        reload:
            loadStudents
    };

})();
'@

Set-Content `
    -Path $StudentsJsPath `
    -Value $StudentsJs `
    -Encoding UTF8

# ------------------------------------------------------------
# 10. STUDENTS.HTML
# ------------------------------------------------------------

$StudentsHtmlPath =
    Join-Path `
        $Frontend `
        "students.html"

$StudentsHtml = @'
<!DOCTYPE html>
<html lang="en">

<head>

    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1.0"
    >

    <meta
        name="description"
        content="IDMC iMIS Student Management"
    >

    <title>IDMC iMIS | Students</title>

    <link
        rel="preconnect"
        href="https://fonts.googleapis.com"
    >

    <link
        rel="preconnect"
        href="https://fonts.gstatic.com"
        crossorigin
    >

    <link
        href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Source+Serif+4:wght@400;500;600;700&display=swap"
        rel="stylesheet"
    >

    <link
        rel="stylesheet"
        href="assets/css/app.css"
    >

    <style>

        :root {
            --maroon-950: #330914;
            --maroon-900: #4a0d1c;
            --maroon-800: #631226;
            --maroon-100: #f5e8eb;
            --paper: #ffffff;
            --background: #faf7f7;
            --border: #e8dee1;
            --text: #2a1116;
            --muted: #7c6165;
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            background: var(--background);
            color: var(--text);
            font-family: "Inter", sans-serif;
        }

        .page {
            width: 100%;
            max-width: 1320px;
            margin: 0 auto;
            padding: 25px;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: flex-end;
            gap: 20px;
            margin-bottom: 20px;
        }

        .eyebrow {
            color: var(--maroon-800);
            font-size: 10px;
            font-weight: 700;
            letter-spacing: .12em;
            text-transform: uppercase;
            margin: 0 0 5px;
        }

        h1 {
            margin: 0;
            font-family: "Source Serif 4", Georgia, serif;
            color: var(--maroon-900);
            font-size: 30px;
        }

        .subtitle {
            margin: 7px 0 0;
            color: var(--muted);
            font-size: 12px;
        }

        .toolbar {
            display: grid;
            grid-template-columns: minmax(250px, 1fr) 180px 120px;
            gap: 10px;
            margin-bottom: 15px;
        }

        input,
        select,
        button {
            min-height: 42px;
            border: 1px solid var(--border);
            background: var(--paper);
            padding: 10px 12px;
            font: inherit;
            color: var(--text);
        }

        button {
            background: var(--maroon-900);
            color: #ffffff;
            cursor: pointer;
            border-color: var(--maroon-900);
            font-weight: 600;
        }

        .card {
            background: var(--paper);
            border: 1px solid var(--border);
        }

        .card-head {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px 17px;
            border-bottom: 1px solid var(--border);
        }

        .card-head h2 {
            margin: 0;
            font-family: "Source Serif 4", Georgia, serif;
            color: var(--maroon-900);
            font-size: 18px;
        }

        .status-text {
            color: var(--muted);
            font-size: 11px;
        }

        .table-wrap {
            width: 100%;
            overflow-x: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
        }

        th,
        td {
            padding: 11px 13px;
            text-align: left;
            border-bottom: 1px solid #f0e8ea;
            font-size: 12px;
            white-space: nowrap;
        }

        th {
            background: #fcf9fa;
            color: var(--maroon-800);
            font-size: 10px;
            letter-spacing: .08em;
            text-transform: uppercase;
        }

        .view-link {
            color: var(--maroon-800);
            font-weight: 700;
            text-decoration: none;
        }

        .loading-state,
        .empty-state,
        .error-state {
            text-align: center;
            padding: 30px;
        }

        .loading-state,
        .empty-state {
            color: var(--muted);
        }

        .error-state {
            color: var(--maroon-800);
        }

        @media (max-width: 800px) {

            .page {
                padding: 16px;
            }

            .header {
                flex-direction: column;
                align-items: flex-start;
            }

            .toolbar {
                grid-template-columns: 1fr;
            }

        }

    </style>

</head>

<body>

    <main class="page">

        <header class="header">

            <div>

                <p class="eyebrow">
                    Student Affairs
                </p>

                <h1>
                    Students
                </h1>

                <p class="subtitle">
                    Student master records and institutional profiles.
                </p>

            </div>

        </header>

        <section class="toolbar">

            <input
                id="studentSearch"
                type="search"
                placeholder="Search student number, name, email or phone..."
                autocomplete="off"
            >

            <select id="studentStatus">

                <option value="">
                    All statuses
                </option>

                <option value="ACTIVE">
                    ACTIVE
                </option>

                <option value="INACTIVE">
                    INACTIVE
                </option>

                <option value="SUSPENDED">
                    SUSPENDED
                </option>

                <option value="GRADUATED">
                    GRADUATED
                </option>

                <option value="WITHDRAWN">
                    WITHDRAWN
                </option>

            </select>

            <button
                id="refreshStudents"
                type="button"
            >
                Refresh
            </button>

        </section>

        <section class="card">

            <div class="card-head">

                <h2>
                    Student Records
                </h2>

                <span
                    id="studentsStatus"
                    class="status-text"
                >
                    Loading...
                </span>

            </div>

            <div class="table-wrap">

                <table>

                    <thead>

                        <tr>

                            <th>
                                Student Number
                            </th>

                            <th>
                                Student Name
                            </th>

                            <th>
                                Gender
                            </th>

                            <th>
                                Email
                            </th>

                            <th>
                                Phone
                            </th>

                            <th>
                                Status
                            </th>

                            <th>
                                Action
                            </th>

                        </tr>

                    </thead>

                    <tbody id="studentsBody">

                        <tr>

                            <td
                                colspan="7"
                                class="loading-state"
                            >
                                Loading student records...
                            </td>

                        </tr>

                    </tbody>

                </table>

            </div>

        </section>

    </main>

    <script src="assets/js/idmc-session.js"></script>
    <script src="assets/js/config.js"></script>
    <script src="assets/js/auth.js"></script>
    <script src="assets/js/rbac.js"></script>
    <script src="assets/js/students.js"></script>

</body>

</html>
'@

Set-Content `
    -Path $StudentsHtmlPath `
    -Value $StudentsHtml `
    -Encoding UTF8

# ------------------------------------------------------------
# 11. STUDENT PORTAL
# ------------------------------------------------------------

$StudentPortalPath =
    Join-Path `
        $Frontend `
        "student-portal.html"

$StudentPortal = @'
<!DOCTYPE html>
<html lang="en">

<head>

    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1.0"
    >

    <meta
        name="description"
        content="IDMC iMIS Student Portal"
    >

    <title>IDMC iMIS | Student Portal</title>

    <link
        rel="stylesheet"
        href="assets/css/app.css"
    >

    <style>

        :root {
            --maroon-950: #330914;
            --maroon-900: #4a0d1c;
            --maroon-800: #631226;
            --maroon-100: #f5e8eb;
            --paper: #ffffff;
            --bg: #faf7f7;
            --border: #e8dee1;
            --text: #2a1116;
            --muted: #7c6165;
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            background: var(--bg);
            color: var(--text);
            font-family: Inter, Arial, sans-serif;
        }

        .portal {
            min-height: 100vh;
            display: grid;
            grid-template-columns: 250px 1fr;
        }

        .sidebar {
            background:
                linear-gradient(
                    180deg,
                    var(--maroon-900),
                    var(--maroon-950)
                );
            color: #ffffff;
            padding: 22px 15px;
        }

        .brand {
            padding: 4px 10px 20px;
            border-bottom: 1px solid rgba(255,255,255,.13);
            margin-bottom: 15px;
        }

        .brand strong {
            display: block;
            font-family: Georgia, serif;
            font-size: 19px;
        }

        .brand span {
            display: block;
            margin-top: 4px;
            font-size: 10px;
            color: rgba(255,255,255,.56);
        }

        nav {
            display: grid;
            gap: 4px;
        }

        nav a {
            color: rgba(255,255,255,.8);
            text-decoration: none;
            padding: 11px 12px;
            font-size: 12px;
            border-left: 2px solid transparent;
        }

        nav a:hover,
        nav a.active {
            background: rgba(255,255,255,.07);
            color: #ffffff;
            border-left-color: #ffffff;
        }

        .main {
            min-width: 0;
        }

        .topbar {
            height: 70px;
            background: var(--paper);
            border-bottom: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0 25px;
        }

        .topbar h1 {
            margin: 0;
            font-family: Georgia, serif;
            font-size: 23px;
            color: var(--maroon-900);
        }

        .topbar p {
            margin: 4px 0 0;
            color: var(--muted);
            font-size: 10px;
        }

        .user-box {
            display: flex;
            align-items: center;
            gap: 9px;
        }

        .avatar {
            width: 38px;
            height: 38px;
            border-radius: 50%;
            display: grid;
            place-items: center;
            background: var(--maroon-800);
            color: #ffffff;
            font-size: 12px;
            font-weight: 700;
        }

        .user-box strong {
            display: block;
            font-size: 12px;
        }

        .user-box span {
            display: block;
            color: var(--muted);
            font-size: 10px;
            margin-top: 2px;
        }

        .content {
            max-width: 1250px;
            margin: 0 auto;
            padding: 25px;
        }

        .welcome {
            background:
                linear-gradient(
                    120deg,
                    var(--maroon-950),
                    var(--maroon-700)
                );
            color: #ffffff;
            padding: 24px;
            margin-bottom: 18px;
        }

        .welcome small {
            font-size: 10px;
            letter-spacing: .1em;
            text-transform: uppercase;
            color: rgba(255,255,255,.62);
        }

        .welcome h2 {
            margin: 6px 0 3px;
            font-family: Georgia, serif;
            font-size: 25px;
        }

        .welcome p {
            margin: 0;
            color: rgba(255,255,255,.72);
            font-size: 12px;
        }

        .cards {
            display: grid;
            grid-template-columns: repeat(4, minmax(0, 1fr));
            gap: 12px;
        }

        .card {
            background: var(--paper);
            border: 1px solid var(--border);
            padding: 17px;
            text-decoration: none;
            color: inherit;
        }

        .card:hover {
            border-color: var(--maroon-800);
        }

        .icon {
            width: 36px;
            height: 36px;
            display: grid;
            place-items: center;
            background: var(--maroon-100);
            color: var(--maroon-800);
            font-weight: 700;
            margin-bottom: 10px;
        }

        .card strong {
            display: block;
            font-family: Georgia, serif;
            color: var(--maroon-900);
            font-size: 15px;
        }

        .card span {
            display: block;
            margin-top: 4px;
            color: var(--muted);
            font-size: 11px;
            line-height: 1.45;
        }

        .profile {
            margin-top: 18px;
            background: var(--paper);
            border: 1px solid var(--border);
        }

        .profile-head {
            padding: 14px 17px;
            border-bottom: 1px solid var(--border);
        }

        .profile-head h3 {
            margin: 0;
            font-family: Georgia, serif;
            color: var(--maroon-900);
        }

        .profile-grid {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 12px;
            padding: 17px;
        }

        .field {
            border: 1px solid #f0e7e9;
            padding: 12px;
        }

        .field span {
            display: block;
            color: var(--muted);
            font-size: 10px;
        }

        .field strong {
            display: block;
            margin-top: 4px;
            font-size: 12px;
        }

        @media (max-width: 950px) {

            .portal {
                grid-template-columns: 1fr;
            }

            .sidebar {
                display: none;
            }

            .cards {
                grid-template-columns: repeat(2, minmax(0, 1fr));
            }

            .profile-grid {
                grid-template-columns: 1fr;
            }

        }

        @media (max-width: 600px) {

            .content {
                padding: 16px;
            }

            .cards {
                grid-template-columns: 1fr;
            }

        }

    </style>

</head>

<body>

<div class="portal">

    <aside class="sidebar">

        <div class="brand">

            <strong>
                IDMC iMIS
            </strong>

            <span>
                Student Self-Service
            </span>

        </div>

        <nav>

            <a
                class="active"
                href="student-portal.html"
            >
                Dashboard
            </a>

            <a href="student-profile.html">
                My Profile
            </a>

            <a href="registration.html">
                Registration
            </a>

            <a href="attendance.html">
                Attendance
            </a>

            <a href="results.html">
                Results & GPA
            </a>

            <a href="timetable.html">
                Timetable
            </a>

            <a href="fee-structures.html">
                Fees
            </a>

            <a href="documents.html">
                Documents
            </a>

            <a
                href="javascript:void(0)"
                data-logout
            >
                Sign out
            </a>

        </nav>

    </aside>

    <main class="main">

        <header class="topbar">

            <div>

                <h1>
                    Student Portal
                </h1>

                <p>
                    Institute of Development and Medical Sciences
                </p>

            </div>

            <div class="user-box">

                <div
                    class="avatar"
                    id="portalAvatar"
                >
                    ID
                </div>

                <div>

                    <strong id="portalUserName">
                        Student
                    </strong>

                    <span id="portalStudentNumber">
                        —
                    </span>

                </div>

            </div>

        </header>

        <section class="content">

            <section class="welcome">

                <small>
                    Student self-service
                </small>

                <h2 id="welcomeName">
                    Welcome
                </h2>

                <p>
                    Access your authorised academic and institutional records.
                </p>

            </section>

            <section class="cards">

                <a
                    href="student-profile.html"
                    class="card"
                >
                    <div class="icon">
                        P
                    </div>

                    <strong>
                        My Profile
                    </strong>

                    <span>
                        Personal and student master information.
                    </span>
                </a>

                <a
                    href="registration.html"
                    class="card"
                >
                    <div class="icon">
                        R
                    </div>

                    <strong>
                        Registration
                    </strong>

                    <span>
                        Academic registration records.
                    </span>
                </a>

                <a
                    href="attendance.html"
                    class="card"
                >
                    <div class="icon">
                        A
                    </div>

                    <strong>
                        Attendance
                    </strong>

                    <span>
                        Attendance information.
                    </span>
                </a>

                <a
                    href="results.html"
                    class="card"
                >
                    <div class="icon">
                        G
                    </div>

                    <strong>
                        Results & GPA
                    </strong>

                    <span>
                        Academic results and GPA.
                    </span>
                </a>

            </section>

            <section class="profile">

                <div class="profile-head">

                    <h3>
                        Student Record
                    </h3>

                </div>

                <div class="profile-grid">

                    <div class="field">

                        <span>
                            Student Number
                        </span>

                        <strong id="studentNumber">
                            —
                        </strong>

                    </div>

                    <div class="field">

                        <span>
                            Student Name
                        </span>

                        <strong id="studentName">
                            —
                        </strong>

                    </div>

                    <div class="field">

                        <span>
                            Status
                        </span>

                        <strong id="studentStatus">
                            —
                        </strong>

                    </div>

                </div>

            </section>

        </section>

    </main>

</div>

<script src="assets/js/idmc-session.js"></script>
<script src="assets/js/config.js"></script>
<script src="assets/js/auth.js"></script>
<script src="assets/js/rbac.js"></script>

<script>

(async () => {

    "use strict";

    function initials(
        name
    ) {

        return String(
            name || "ID"
        )
            .trim()
            .split(/\s+/)
            .slice(0, 2)
            .map(
                part =>
                    part.charAt(0)
                        .toUpperCase()
            )
            .join("");

    }

    function getAccessUserId() {

        const session =
            window.IDMCSession?.getSession?.();

        return (
            session?.user?.id ||
            session?.user_id ||
            session?.user?.user_id ||
            null
        );

    }

    function setText(
        id,
        value
    ) {

        const element =
            document.getElementById(id);

        if (element) {
            element.textContent =
                value || "—";
        }

    }

    try {

        await window.IDMCAuth.requireAuth();

        const result =
            await window.IDMC_RBAC_API.request(
                "/students/me"
            );

        const student =
            result?.data;

        if (!student) {

            throw new Error(
                "No student record is linked to this account."
            );

        }

        const name = [
            student.first_name,
            student.middle_name,
            student.last_name
        ]
            .filter(Boolean)
            .join(" ");

        setText(
            "welcomeName",
            `Welcome, ${name || "Student"}`
        );

        setText(
            "portalUserName",
            name || "Student"
        );

        setText(
            "portalStudentNumber",
            student.student_number
        );

        setText(
            "studentNumber",
            student.student_number
        );

        setText(
            "studentName",
            name
        );

        setText(
            "studentStatus",
            student.student_status
        );

        const avatar =
            document.getElementById(
                "portalAvatar"
            );

        if (avatar) {
            avatar.textContent =
                initials(name);
        }

    } catch (error) {

        console.error(
            "Student portal failed:",
            error
        );

        setText(
            "welcomeName",
            "Student Portal"
        );

    }

    document
        .querySelectorAll(
            "[data-logout]"
        )
        .forEach(
            button => {

                button.addEventListener(
                    "click",
                    async () => {

                        try {

                            if (
                                typeof
                                    window.IDMCAuth
                                        ?.logout ===
                                    "function"
                            ) {

                                await window.IDMCAuth.logout();

                            }

                        } finally {

                            window.location.href =
                                "login.html";

                        }

                    }
                );

            }
        );

})();

</script>

</body>

</html>
'@

Set-Content `
    -Path $StudentPortalPath `
    -Value $StudentPortal `
    -Encoding UTF8

# ------------------------------------------------------------
# 12. STUDENT PROFILE
# ------------------------------------------------------------

$StudentProfilePath =
    Join-Path `
        $Frontend `
        "student-profile.html"

$StudentProfile = @'
<!DOCTYPE html>
<html lang="en">

<head>

    <meta charset="UTF-8">

    <meta
        name="viewport"
        content="width=device-width, initial-scale=1.0"
    >

    <title>IDMC iMIS | Student Profile</title>

    <link
        rel="stylesheet"
        href="assets/css/app.css"
    >

    <style>

        body {
            margin: 0;
            background: #faf7f7;
            color: #2a1116;
            font-family: Inter, Arial, sans-serif;
        }

        .page {
            max-width: 1100px;
            margin: 0 auto;
            padding: 25px;
        }

        .header {
            margin-bottom: 18px;
        }

        .header span {
            display: block;
            color: #631226;
            font-size: 10px;
            font-weight: 700;
            letter-spacing: .1em;
            text-transform: uppercase;
        }

        h1 {
            margin: 5px 0;
            color: #4a0d1c;
            font-family: Georgia, serif;
        }

        .header p {
            margin: 0;
            color: #7c6165;
            font-size: 12px;
        }

        .card {
            background: #ffffff;
            border: 1px solid #e8dee1;
            padding: 20px;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 12px;
        }

        .field {
            border: 1px solid #f0e7e9;
            padding: 13px;
        }

        .field span {
            display: block;
            color: #7c6165;
            font-size: 10px;
        }

        .field strong {
            display: block;
            margin-top: 4px;
            font-size: 13px;
        }

        .loading {
            padding: 25px;
            text-align: center;
            color: #7c6165;
        }

        @media (max-width: 700px) {

            .page {
                padding: 16px;
            }

            .grid {
                grid-template-columns: 1fr;
            }

        }

    </style>

</head>

<body>

<main class="page">

    <header class="header">

        <span>
            Student Affairs
        </span>

        <h1>
            My Profile
        </h1>

        <p>
            Authorised student master information.
        </p>

    </header>

    <section class="card">

        <div
            id="profile"
            class="loading"
        >
            Loading student profile...
        </div>

    </section>

</main>

<script src="assets/js/idmc-session.js"></script>
<script src="assets/js/config.js"></script>
<script src="assets/js/auth.js"></script>
<script src="assets/js/rbac.js"></script>

<script>

(async () => {

    "use strict";

    function escapeHtml(
        value
    ) {

        return String(
            value ?? "—"
        )
            .replace(
                /&/g,
                "&amp;"
            )
            .replace(
                /</g,
                "&lt;"
            )
            .replace(
                />/g,
                "&gt;"
            )
            .replace(
                /"/g,
                "&quot;"
            )
            .replace(
                /'/g,
                "&#039;"
            );

    }

    function nameOf(
        student
    ) {

        return [
            student.first_name,
            student.middle_name,
            student.last_name
        ]
            .filter(Boolean)
            .join(" ");

    }

    try {

        await window.IDMCAuth.requireAuth();

        const result =
            await window.IDMC_RBAC_API.request(
                "/students/me"
            );

        const student =
            result?.data;

        if (!student) {
            throw new Error(
                "Student record not found."
            );
        }

        document.getElementById(
            "profile"
        ).outerHTML = `

            <div class="grid">

                <div class="field">
                    <span>Student Number</span>
                    <strong>
                        ${escapeHtml(
                            student.student_number
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Full Name</span>
                    <strong>
                        ${escapeHtml(
                            nameOf(student)
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Gender</span>
                    <strong>
                        ${escapeHtml(
                            student.gender
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Date of Birth</span>
                    <strong>
                        ${escapeHtml(
                            student.date_of_birth
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Nationality</span>
                    <strong>
                        ${escapeHtml(
                            student.nationality
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Phone</span>
                    <strong>
                        ${escapeHtml(
                            student.phone
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Email</span>
                    <strong>
                        ${escapeHtml(
                            student.email
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Admission Year</span>
                    <strong>
                        ${escapeHtml(
                            student.admission_year
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Entry Type</span>
                    <strong>
                        ${escapeHtml(
                            student.entry_type
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Status</span>
                    <strong>
                        ${escapeHtml(
                            student.student_status
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>National ID</span>
                    <strong>
                        ${escapeHtml(
                            student.national_id
                        )}
                    </strong>
                </div>

                <div class="field">
                    <span>Passport Number</span>
                    <strong>
                        ${escapeHtml(
                            student.passport_number
                        )}
                    </strong>
                </div>

            </div>

        `;

    } catch (error) {

        document.getElementById(
            "profile"
        ).textContent =
            error?.message ||
            "Unable to load student profile.";

    }

})();

</script>

</body>

</html>
'@

Set-Content `
    -Path $StudentProfilePath `
    -Value $StudentProfile `
    -Encoding UTF8

Write-Host "[4/8] Student HTML and portal created." -ForegroundColor Green

# ------------------------------------------------------------
# 13. FIX DOUBLE .JS EXTENSIONS IF ANY
# ------------------------------------------------------------

Get-ChildItem `
    -Path $Backend\src `
    -Recurse `
    -File `
    -Include *.ts,*.js |
    ForEach-Object {

        $Content =
            Get-Content `
                -Path $_.FullName `
                -Raw

        if (
            $Content -match '\.js\.js'
        ) {

            $Content =
                $Content -replace `
                    '\.js\.js',
                    '.js'

            Set-Content `
                -Path $_.FullName `
                -Value $Content `
                -Encoding UTF8

        }

    }

Write-Host "[5/8] Import-extension normalization completed." -ForegroundColor Green

# ------------------------------------------------------------
# 14. VALIDATE REQUIRED TOOLS
# ------------------------------------------------------------

Write-Host ""
Write-Host "Validating required tools..." -ForegroundColor Cyan

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

$MissingTools = @()

foreach ($Tool in @("node", "npm", "npx")) {
    if (-not (Test-CommandAvailable $Tool)) {
        $MissingTools += $Tool
    }
}

if ($MissingTools.Count -gt 0) {
    Write-Host ""
    Write-Host "REQUIRED TOOL(S) NOT FOUND:" -ForegroundColor Red
    $MissingTools | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Install Node.js LTS, restart VS Code, and run this script again." -ForegroundColor Yellow
    Set-Location $Root
    return
}

Write-Host "Node: $(node --version)" -ForegroundColor Green
Write-Host "NPM : $(npm --version)" -ForegroundColor Green

# ------------------------------------------------------------
# 15. NODE CHECK FRONTEND JS
# ------------------------------------------------------------

Write-Host ""
Write-Host "Checking students.js..." -ForegroundColor Cyan

node --check "$Frontend\assets\js\students.js"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "students.js syntax check FAILED." -ForegroundColor Red
    Write-Host "The script stopped at the JavaScript syntax check." -ForegroundColor Yellow
    Set-Location $Root
    return
}

Write-Host "students.js syntax check PASSED." -ForegroundColor Green

# ------------------------------------------------------------
# 16. BACKEND TYPECHECK
# ------------------------------------------------------------

Write-Host ""
Write-Host "Running backend TypeScript typecheck..." -ForegroundColor Cyan

if (-not (Test-Path "$Backend\package.json")) {
    Write-Host ""
    Write-Host "Backend package.json was not found:" -ForegroundColor Red
    Write-Host "  $Backend\package.json" -ForegroundColor Yellow
    Set-Location $Root
    return
}

Set-Location $Backend

npx tsc -p tsconfig.json --noEmit

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Backend TypeScript typecheck FAILED." -ForegroundColor Red
    Write-Host "Read the TypeScript errors printed immediately above this message." -ForegroundColor Yellow
    Set-Location $Root
    return
}

Write-Host "Backend typecheck PASSED." -ForegroundColor Green

# ------------------------------------------------------------
# 17. BACKEND BUILD
# ------------------------------------------------------------

Write-Host ""
Write-Host "Running backend build..." -ForegroundColor Cyan

npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Backend build FAILED." -ForegroundColor Red
    Write-Host "Read the npm build errors printed immediately above this message." -ForegroundColor Yellow
    Set-Location $Root
    return
}

Write-Host "Backend build PASSED." -ForegroundColor Green

# ------------------------------------------------------------
# 18. OPTIONAL SUPABASE MIGRATION PUSH
# ------------------------------------------------------------

Set-Location $Root

Write-Host ""
Write-Host "Checking Supabase CLI..." -ForegroundColor Cyan

if (Test-CommandAvailable "supabase") {

    Write-Host "Supabase CLI: $(supabase --version)" -ForegroundColor Green

    Write-Host ""
    $PushChoice = Read-Host "Push migration 003 to Supabase now? (Y/N)"

    if ($PushChoice -match '^(Y|y)$') {

        Write-Host ""
        Write-Host "Pushing Supabase Migration 003..." -ForegroundColor Cyan

        supabase db push

        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "Supabase migration push FAILED." -ForegroundColor Red
            Write-Host ""
            Write-Host "The files were created successfully, but Supabase did not accept the migration." -ForegroundColor Yellow
            Write-Host "Common causes: project not linked, authentication missing, or SQL/schema conflict." -ForegroundColor Yellow
            Set-Location $Root
            return
        }

        Write-Host "Supabase migration push PASSED." -ForegroundColor Green

    }
    else {
        Write-Host "Supabase migration push skipped by user." -ForegroundColor Yellow
    }

}
else {

    Write-Host ""
    Write-Host "Supabase CLI was not found." -ForegroundColor Yellow
    Write-Host "Migration file was created but was NOT pushed." -ForegroundColor Yellow
    Write-Host "Install/login/link Supabase CLI later, then run:" -ForegroundColor Yellow
    Write-Host "  supabase db push" -ForegroundColor White
}

# ------------------------------------------------------------
# 19. FINAL FILE STATUS
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " STUDENT CORE FILE STATUS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$CheckFiles = @(
    "$Supabase\migrations\003_student_core.sql",
    "$Backend\src\modules\student-management\shared\student.types.ts",
    "$Backend\src\modules\student-management\students\students.service.ts",
    "$Backend\src\modules\student-management\students\students.controller.ts",
    "$Backend\src\modules\student-management\students\students.routes.ts",
    "$Backend\src\modules\student-management\student-management.routes.ts",
    "$Frontend\students.html",
    "$Frontend\student-portal.html",
    "$Frontend\student-profile.html",
    "$Frontend\assets\js\students.js"
)

$MissingFiles = @()

foreach ($File in $CheckFiles) {

    if (Test-Path $File) {
        Write-Host "[OK] $File" -ForegroundColor Green
    }
    else {
        Write-Host "[MISSING] $File" -ForegroundColor Red
        $MissingFiles += $File
    }
}

Write-Host ""

if ($MissingFiles.Count -gt 0) {

    Write-Host "BUILD FINISHED WITH MISSING FILES." -ForegroundColor Yellow

}
else {

    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " STUDENT CORE COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green

}

Write-Host ""
Write-Host "API endpoints:" -ForegroundColor Yellow
Write-Host "GET    /api/v1/students"
Write-Host "GET    /api/v1/students/me"
Write-Host "GET    /api/v1/students/:id"
Write-Host "POST   /api/v1/students"
Write-Host "PATCH  /api/v1/students/:id"

Write-Host ""
Write-Host "Frontend:" -ForegroundColor Yellow
Write-Host "students.html"
Write-Host "student-portal.html"
Write-Host "student-profile.html"

Write-Host ""
Write-Host "Permissions:" -ForegroundColor Yellow
Write-Host "students.view"
Write-Host "students.manage"
Write-Host "portal.student"

Write-Host ""
Set-Location $Root

