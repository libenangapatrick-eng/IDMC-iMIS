-- ============================================================
-- FULL DATABASE SCHEMA & RELATIONSHIP INSPECTION
-- ============================================================

-- 1. ALL TABLES IN PUBLIC SCHEMA
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE' 
ORDER BY table_name;

-- 2. ALL COLUMNS & DATA TYPES
SELECT 
    table_name, 
    column_name, 
    data_type, 
    udt_name, 
    is_nullable, 
    column_default 
FROM information_schema.columns 
WHERE table_schema = 'public' 
ORDER BY table_name, ordinal_position;

-- 3. PRIMARY KEYS & FOREIGN KEYS (RELATIONSHIPS)
SELECT 
    tc.table_name AS source_table, 
    kcu.column_name AS source_column, 
    tc.constraint_type, 
    ccu.table_name AS target_table, 
    ccu.column_name AS target_column, 
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu 
    ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
LEFT JOIN information_schema.constraint_column_usage ccu 
    ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
WHERE tc.table_schema = 'public' AND tc.constraint_type IN ('PRIMARY KEY', 'FOREIGN KEY')
ORDER BY tc.table_name, tc.constraint_type;

-- 4. RLS POLICIES
SELECT tablename, policyname, roles, cmd, qual, with_check 
FROM pg_policies 
WHERE schemaname = 'public' 
ORDER BY tablename, policyname;

-- 5. ENUM TYPES
SELECT t.typname AS enum_name, e.enumlabel AS enum_value
FROM pg_type t 
JOIN pg_enum e ON t.oid = e.enumtypid 
JOIN pg_namespace n ON n.oid = t.typnamespace 
WHERE n.nspname = 'public' 
ORDER BY t.typname, e.enumsortorder;
