-- READ-ONLY production readiness diagnostics. This file is not a migration.
-- Run with a read-only database role and archive the results with the release.

-- Duplicate public identities and financial references.
SELECT 'duplicate_student_number' AS check_name, lower(student_number) AS key, count(*) AS occurrences
FROM public.students GROUP BY lower(student_number) HAVING count(*) > 1;

SELECT 'duplicate_application_number' AS check_name, lower(application_number) AS key, count(*) AS occurrences
FROM public.applications GROUP BY lower(application_number) HAVING count(*) > 1;

SELECT 'duplicate_payment_external_reference' AS check_name,
       provider || ':' || external_reference AS key, count(*) AS occurrences
FROM public.payments WHERE external_reference IS NOT NULL
GROUP BY provider, external_reference HAVING count(*) > 1;

-- Orphans that should be impossible when foreign keys and ingestion are correct.
SELECT 'student_without_programme' AS check_name, count(*) AS occurrences
FROM public.students s LEFT JOIN public.programmes p ON p.id=s.programme_id
WHERE s.programme_id IS NOT NULL AND p.id IS NULL;

SELECT 'course_registration_without_student' AS check_name, count(*) AS occurrences
FROM public.course_registrations cr LEFT JOIN public.students s ON s.id=cr.student_id
WHERE s.id IS NULL;

SELECT 'result_without_registration' AS check_name, count(*) AS occurrences
FROM public.course_results r LEFT JOIN public.course_registrations cr ON cr.id=r.course_registration_id
WHERE r.course_registration_id IS NOT NULL AND cr.id IS NULL;

SELECT 'allocation_without_confirmed_payment' AS check_name, count(*) AS occurrences
FROM public.payment_allocations pa JOIN public.payments p ON p.id=pa.payment_id
WHERE pa.status='ACTIVE' AND p.status<>'CONFIRMED';

-- Reconciliation: invoice amount paid versus active confirmed allocations.
SELECT i.id,i.invoice_number,i.amount_paid,
       coalesce(sum(pa.allocated_amount) FILTER (WHERE pa.status='ACTIVE' AND p.status='CONFIRMED'),0) AS confirmed_allocations
FROM public.invoices i
LEFT JOIN public.payment_allocations pa ON pa.invoice_id=i.id
LEFT JOIN public.payments p ON p.id=pa.payment_id
GROUP BY i.id,i.invoice_number,i.amount_paid
HAVING i.amount_paid <> coalesce(sum(pa.allocated_amount) FILTER (WHERE pa.status='ACTIVE' AND p.status='CONFIRMED'),0);

-- Published results must be internally complete.
SELECT id,student_id,course_offering_id,result_status,total_mark,grade_code,pass_status
FROM public.course_results
WHERE result_status IN ('PUBLISHED','LOCKED')
  AND (total_mark IS NULL OR grade_code IS NULL OR pass_status IS NULL);

-- Foreign-key columns without a leading-column index (review before adding indexes).
SELECT n.nspname AS schema_name,c.relname AS table_name,a.attname AS fk_column
FROM pg_constraint con
JOIN pg_class c ON c.oid=con.conrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN unnest(con.conkey) WITH ORDINALITY AS k(attnum,ord) ON true
JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum
WHERE con.contype='f' AND n.nspname='public' AND k.ord=1
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid=c.oid AND i.indisvalid AND (i.indkey::smallint[])[0]=a.attnum
  )
ORDER BY table_name,fk_column;
