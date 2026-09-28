-- ============================================================
-- IDMC iMIS
-- Migration 002 Verification
-- Identity, RBAC and Audit Logging
-- PostgreSQL / Supabase Cloud compatible
-- ============================================================

-- 1. TABLE EXISTENCE
SELECT
    'TABLE_EXISTS' AS check_name,
    table_name,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM information_schema.tables t
            WHERE t.table_schema = 'public'
              AND t.table_name = expected.table_name
        )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM (
    VALUES
        ('users'),
        ('roles'),
        ('permissions'),
        ('role_permissions'),
        ('user_roles'),
        ('user_scopes'),
        ('audit_logs'),
        ('security_logs')
) AS expected(table_name)
ORDER BY table_name;


-- 2. TOTAL EXPECTED TABLES
SELECT
    'EXPECTED_TABLE_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    8 AS expected_count,
    CASE
        WHEN COUNT(*) = 8 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  );


-- 3. REQUIRED COLUMNS
SELECT
    'REQUIRED_COLUMNS' AS check_name,
    COUNT(*) AS found_count,
    8 AS minimum_expected,
    CASE
        WHEN COUNT(*) >= 8 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
      (table_name = 'users' AND column_name IN ('id','auth_user_id','user_number','email','status'))
      OR
      (table_name = 'roles' AND column_name IN ('id','code','name'))
      OR
      (table_name = 'permissions' AND column_name IN ('id','code','name'))
      OR
      (table_name = 'role_permissions' AND column_name IN ('role_id','permission_id'))
      OR
      (table_name = 'user_roles' AND column_name IN ('user_id','role_id'))
      OR
      (table_name = 'user_scopes' AND column_name IN ('user_id','institution_id','campus_id','school_id','department_id'))
      OR
      (table_name = 'audit_logs' AND column_name IN ('id','user_id','action','entity_type','entity_id'))
      OR
      (table_name = 'security_logs' AND column_name IN ('id','user_id','event_type','ip_address'))
  );


-- 4. FOREIGN KEYS
SELECT
    'FOREIGN_KEY_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    12 AS minimum_expected,
    CASE
        WHEN COUNT(*) >= 12 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM information_schema.table_constraints
WHERE constraint_schema = 'public'
  AND constraint_type = 'FOREIGN KEY'
  AND table_name IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  );


-- 5. SEE FOREIGN KEY DETAILS
SELECT
    tc.table_name,
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS referenced_table,
    ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.constraint_schema = tc.table_schema
WHERE tc.constraint_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  )
ORDER BY tc.table_name, tc.constraint_name;


-- 6. SEEDED ROLES
SELECT
    'SEEDED_ROLE' AS check_name,
    code,
    name,
    CASE
        WHEN COUNT(*) OVER () >= 16 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM public.roles
WHERE code IN (
    'SUPER_ADMIN',
    'ADMIN',
    'ACADEMIC_OFFICER',
    'ADMISSIONS_OFFICER',
    'FINANCE_OFFICER',
    'EXAMINATION_OFFICER',
    'LECTURER',
    'STUDENT',
    'LIBRARIAN',
    'HR_OFFICER',
    'PROCUREMENT_OFFICER',
    'STORE_OFFICER',
    'QUALITY_ASSURANCE',
    'RESEARCH_OFFICER',
    'AUDITOR',
    'STAFF'
)
ORDER BY code;


-- 7. ROLE COUNT
SELECT
    'ROLE_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    16 AS minimum_expected,
    CASE
        WHEN COUNT(*) >= 16 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM public.roles;


-- 8. REQUIRED ROLE CODES
SELECT
    expected.code,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.roles r
            WHERE r.code = expected.code
        )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM (
    VALUES
        ('SUPER_ADMIN'),
        ('ADMIN'),
        ('ACADEMIC_OFFICER'),
        ('ADMISSIONS_OFFICER'),
        ('FINANCE_OFFICER'),
        ('EXAMINATION_OFFICER'),
        ('LECTURER'),
        ('STUDENT'),
        ('LIBRARIAN'),
        ('HR_OFFICER'),
        ('PROCUREMENT_OFFICER'),
        ('STORE_OFFICER'),
        ('QUALITY_ASSURANCE'),
        ('RESEARCH_OFFICER'),
        ('AUDITOR'),
        ('STAFF')
) AS expected(code)
ORDER BY code;


-- 9. SEEDED PERMISSIONS
SELECT
    'SEEDED_PERMISSION' AS check_name,
    code,
    name
FROM public.permissions
WHERE code IN (
    'system.view',
    'system.manage',
    'users.view',
    'users.create',
    'users.update',
    'users.delete',
    'roles.view',
    'roles.manage',
    'permissions.view',
    'audit.view',
    'audit.export',
    'institutions.view',
    'institutions.manage',
    'campuses.view',
    'campuses.manage',
    'schools.view',
    'schools.manage',
    'departments.view',
    'departments.manage'
)
ORDER BY code;


-- 10. PERMISSION COUNT
SELECT
    'PERMISSION_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    19 AS minimum_expected,
    CASE
        WHEN COUNT(*) >= 19 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM public.permissions;


-- 11. ROLE-PERMISSION ASSIGNMENTS
SELECT
    'ROLE_PERMISSION_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM public.role_permissions;


-- 12. SUPER ADMIN PERMISSION COVERAGE
SELECT
    'SUPER_ADMIN_PERMISSION_COVERAGE' AS check_name,
    COUNT(DISTINCT rp.permission_id) AS assigned_permissions,
    (SELECT COUNT(*) FROM public.permissions) AS total_permissions,
    CASE
        WHEN COUNT(DISTINCT rp.permission_id) =
             (SELECT COUNT(*) FROM public.permissions)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM public.role_permissions rp
JOIN public.roles r
    ON r.id = rp.role_id
WHERE r.code = 'SUPER_ADMIN';


-- 13. INDEXES
SELECT
    schemaname,
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  )
ORDER BY tablename, indexname;


-- 14. INDEX COUNT
SELECT
    'INDEX_COUNT' AS check_name,
    COUNT(*) AS actual_count,
    23 AS expected_count,
    CASE
        WHEN COUNT(*) >= 23 THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  );


-- 15. RLS STATUS
SELECT
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    CASE
        WHEN c.relrowsecurity = true THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM pg_class c
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  )
ORDER BY c.relname;


-- 16. RLS ENABLED COUNT
SELECT
    'RLS_ENABLED_COUNT' AS check_name,
    COUNT(*) FILTER (WHERE c.relrowsecurity = true) AS enabled_count,
    8 AS expected_count,
    CASE
        WHEN COUNT(*) FILTER (WHERE c.relrowsecurity = true) = 8
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result
FROM pg_class c
JOIN pg_namespace n
    ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  );


-- 17. RLS POLICIES
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  )
ORDER BY tablename, policyname;


-- 18. UNIQUE CONSTRAINTS
SELECT
    tc.table_name,
    tc.constraint_name,
    kcu.column_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public'
  AND tc.constraint_type = 'UNIQUE'
  AND tc.table_name IN (
      'users',
      'roles',
      'permissions',
      'role_permissions',
      'user_roles',
      'user_scopes',
      'audit_logs',
      'security_logs'
  )
ORDER BY tc.table_name, tc.constraint_name;


-- 19. AUDIT JSONB VALIDATION
SELECT
    table_name,
    column_name,
    data_type,
    CASE
        WHEN data_type = 'jsonb' THEN 'PASS'
        ELSE 'CHECK'
    END AS result
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('audit_logs', 'security_logs')
  AND data_type = 'jsonb'
ORDER BY table_name, column_name;


-- 20. FINAL SUMMARY
SELECT
    'FINAL_SUMMARY' AS check_name,
    (SELECT COUNT(*)
     FROM information_schema.tables
     WHERE table_schema = 'public'
       AND table_name IN (
           'users',
           'roles',
           'permissions',
           'role_permissions',
           'user_roles',
           'user_scopes',
           'audit_logs',
           'security_logs'
       )) AS tables_found,

    (SELECT COUNT(*)
     FROM public.roles) AS roles_found,

    (SELECT COUNT(*)
     FROM public.permissions) AS permissions_found,

    (SELECT COUNT(*)
     FROM public.role_permissions) AS role_permissions_found,

    (SELECT COUNT(*)
     FROM pg_indexes
     WHERE schemaname = 'public'
       AND tablename IN (
           'users',
           'roles',
           'permissions',
           'role_permissions',
           'user_roles',
           'user_scopes',
           'audit_logs',
           'security_logs'
       )) AS indexes_found,

    (SELECT COUNT(*)
     FROM pg_class c
     JOIN pg_namespace n
       ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN (
           'users',
           'roles',
           'permissions',
           'role_permissions',
           'user_roles',
           'user_scopes',
           'audit_logs',
           'security_logs'
       )
       AND c.relrowsecurity = true) AS rls_enabled_tables;
