# IDMC iMIS Frontend API Contract
## RBAC - Roles & Permissions

Base URL:

/api/v1

Authentication:

Authorization: Bearer <SUPABASE_ACCESS_TOKEN>

Content-Type:

application/json


============================================================
1. LIST ROLES
============================================================

GET /roles

Permission:

roles.view

Response:

{
  "success": true,
  "data": []
}


============================================================
2. GET ROLE
============================================================

GET /roles/:id

Permission:

roles.view

Response:

{
  "success": true,
  "data": {}
}


============================================================
3. LIST PERMISSIONS
============================================================

GET /roles/permissions

Permission:

permissions.view

Response:

{
  "success": true,
  "data": []
}


============================================================
4. GET ROLE PERMISSIONS
============================================================

GET /roles/:id/permissions

Permission:

roles.view

Response:

{
  "success": true,
  "data": []
}


============================================================
5. CREATE ROLE
============================================================

POST /roles

Permission:

roles.manage

Request:

{
  "roleCode": "REGISTRAR",
  "roleName": "Registrar",
  "description": "Registrar role",
  "status": "ACTIVE"
}


============================================================
6. UPDATE ROLE
============================================================

PATCH /roles/:id

Permission:

roles.manage

Request:

{
  "roleName": "Registrar",
  "description": "Updated description",
  "status": "ACTIVE"
}


============================================================
7. ASSIGN PERMISSION
============================================================

POST /roles/:id/permissions

Permission:

roles.manage

Request:

{
  "permissionId": "UUID"
}


============================================================
8. REMOVE PERMISSION
============================================================

DELETE /roles/:id/permissions/:permissionId

Permission:

roles.manage


============================================================
FRONTEND RULES
============================================================

Never send:

SUPABASE_SERVICE_ROLE_KEY

Frontend may use:

SUPABASE_ANON_KEY / publishable key

Every protected API request must include:

Authorization: Bearer <access_token>

Roles control access through:

Role
  ->
Role Permission
  ->
Permission
  ->
API Endpoint


============================================================
AUDIT EVENTS
============================================================

ROLE_CREATE

ROLE_UPDATE

ROLE_PERMISSION_ASSIGN

ROLE_PERMISSION_REMOVE
