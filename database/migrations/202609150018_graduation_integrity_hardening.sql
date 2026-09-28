-- ============================================================
-- IDMC iMIS
-- Migration 018
-- Graduation Integrity Hardening
-- ============================================================

BEGIN;

-- ============================================================
-- 1. DEPENDENCY VALIDATION
-- ============================================================

DO $$
DECLARE
    v_required record;
BEGIN
    FOR v_required IN
        SELECT *
        FROM (
            VALUES
                ('graduation_periods', 'id'),
                ('graduation_candidates', 'id'),
                ('graduation_candidates', 'student_id'),
                ('graduation_candidates', 'candidate_status'),
                ('graduation_candidates', 'academic_completion_status'),
                ('graduation_candidates', 'eligibility_status'),
                ('graduation_candidates', 'final_cgpa'),

                ('graduation_clearances', 'id'),
                ('graduation_clearances', 'graduation_candidate_id'),
                ('graduation_clearances', 'clearance_type'),
                ('graduation_clearances', 'status'),
                ('graduation_clearances', 'cleared_by'),
                ('graduation_clearances', 'amount_due'),
                ('graduation_clearances', 'amount_cleared'),

                ('graduation_clearance_items', 'id'),
                ('graduation_clearance_items', 'graduation_clearance_id'),
                ('graduation_clearance_items', 'status'),

                ('graduation_approvals', 'id'),
                ('graduation_approvals', 'graduation_candidate_id'),
                ('graduation_approvals', 'approval_stage'),
                ('graduation_approvals', 'decision'),
                ('graduation_approvals', 'approved_by'),

                ('graduation_awards', 'id'),
                ('graduation_awards', 'graduation_candidate_id'),
                ('graduation_awards', 'final_cgpa'),

                ('certificates', 'id'),
                ('certificates', 'graduation_award_id'),
                ('certificates', 'student_id'),
                ('certificates', 'status'),
                ('certificates', 'issued_by'),
                ('certificates', 'verification_code'),
                ('certificates', 'revoked_by'),
                ('certificates', 'revocation_reason'),

                ('certificate_verifications', 'id'),
                ('certificate_verifications', 'certificate_id'),
                ('certificate_verifications', 'verification_code'),

                ('alumni_records', 'id'),
                ('alumni_records', 'student_id'),
                ('alumni_records', 'graduation_year'),

                ('students', 'id'),
                ('students', 'student_status')
        ) AS x(table_name, column_name)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = v_required.table_name
              AND column_name = v_required.column_name
        ) THEN
            RAISE EXCEPTION
                'Migration 018 dependency missing: public.%.% does not exist',
                v_required.table_name,
                v_required.column_name;
        END IF;
    END LOOP;
END $$;


-- ============================================================
-- 2. GRADUATION CLEARANCE INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_clearance_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    -- CLEARED must have an actor
    IF NEW.status = 'CLEARED'
       AND NEW.cleared_by IS NULL THEN
        RAISE EXCEPTION
            'A CLEARED graduation clearance requires cleared_by';
    END IF;

    -- WAIVED must have a reason
    IF NEW.status = 'WAIVED'
       AND NULLIF(trim(COALESCE(NEW.remarks, '')), '') IS NULL THEN
        RAISE EXCEPTION
            'A WAIVED graduation clearance requires remarks';
    END IF;

    -- Finance clearance cannot be cleared below amount due
    IF NEW.clearance_type = 'FINANCE'
       AND NEW.status = 'CLEARED'
       AND COALESCE(NEW.amount_cleared, 0)
           < COALESCE(NEW.amount_due, 0) THEN
        RAISE EXCEPTION
            'Finance clearance cannot be CLEARED until the required amount is cleared';
    END IF;

    IF NEW.status = 'CLEARED'
       AND NEW.cleared_at IS NULL THEN
        NEW.cleared_at := now();
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_clearance_integrity
ON public.graduation_clearances;

CREATE TRIGGER trg_validate_graduation_clearance_integrity
BEFORE INSERT OR UPDATE
ON public.graduation_clearances
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_clearance_integrity();


-- ============================================================
-- 3. CANDIDATE CLEARANCE COMPLETENESS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_candidate_clearance_completeness()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total integer;
    v_complete integer;
BEGIN

    IF NEW.candidate_status IN ('CLEARED', 'APPROVED', 'GRADUATED') THEN

        SELECT COUNT(*)
        INTO v_total
        FROM public.graduation_clearances
        WHERE graduation_candidate_id = NEW.id;

        SELECT COUNT(*)
        INTO v_complete
        FROM public.graduation_clearances
        WHERE graduation_candidate_id = NEW.id
          AND status IN ('CLEARED', 'WAIVED');

        IF v_total < 7 OR v_complete < 7 THEN
            RAISE EXCEPTION
                'Graduation candidate cannot become % until all required clearances are CLEARED or WAIVED',
                NEW.candidate_status;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_candidate_clearance_completeness
ON public.graduation_candidates;

CREATE TRIGGER trg_validate_graduation_candidate_clearance_completeness
BEFORE UPDATE
ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_candidate_clearance_completeness();


-- ============================================================
-- 4. ACADEMIC ELIGIBILITY INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_academic_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.eligibility_status = 'ELIGIBLE'
       AND NEW.academic_completion_status <> 'COMPLETE' THEN
        RAISE EXCEPTION
            'A graduation candidate can only be ELIGIBLE when academic completion is COMPLETE';
    END IF;

    IF NEW.candidate_status IN ('APPROVED', 'GRADUATED')
       AND NEW.eligibility_status <> 'ELIGIBLE' THEN
        RAISE EXCEPTION
            'A graduation candidate cannot be APPROVED or GRADUATED unless ELIGIBLE';
    END IF;

    IF NEW.final_cgpa IS NOT NULL
       AND (NEW.final_cgpa < 0 OR NEW.final_cgpa > 5) THEN
        RAISE EXCEPTION
            'final_cgpa must be between 0 and 5';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_academic_integrity
ON public.graduation_candidates;

CREATE TRIGGER trg_validate_graduation_academic_integrity
BEFORE INSERT OR UPDATE
ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_academic_integrity();


-- ============================================================
-- 5. APPROVAL COMPLETENESS
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_approval_completeness()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_total integer;
    v_approved integer;
BEGIN

    IF NEW.candidate_status IN ('APPROVED', 'GRADUATED') THEN

        SELECT COUNT(*)
        INTO v_total
        FROM public.graduation_approvals
        WHERE graduation_candidate_id = NEW.id;

        SELECT COUNT(*)
        INTO v_approved
        FROM public.graduation_approvals
        WHERE graduation_candidate_id = NEW.id
          AND decision = 'APPROVED';

        IF v_total < 5 OR v_approved < 5 THEN
            RAISE EXCEPTION
                'Graduation candidate cannot become % until all required approval stages are APPROVED',
                NEW.candidate_status;
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_approval_completeness
ON public.graduation_candidates;

CREATE TRIGGER trg_validate_graduation_approval_completeness
BEFORE UPDATE
ON public.graduation_candidates
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_approval_completeness();


-- ============================================================
-- 6. APPROVAL ACTOR INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_approval_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.decision = 'APPROVED'
       AND NEW.approved_by IS NULL THEN
        RAISE EXCEPTION
            'An APPROVED graduation approval requires approved_by';
    END IF;

    IF NEW.decision = 'REJECTED'
       AND NEW.approved_by IS NULL THEN
        RAISE EXCEPTION
            'A REJECTED graduation approval requires an approving actor';
    END IF;

    IF NEW.decision = 'APPROVED'
       AND NEW.approved_at IS NULL THEN
        NEW.approved_at := now();
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_approval_integrity
ON public.graduation_approvals;

CREATE TRIGGER trg_validate_graduation_approval_integrity
BEFORE INSERT OR UPDATE
ON public.graduation_approvals
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_approval_integrity();


-- ============================================================
-- 7. GRADUATION AWARD INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_graduation_award_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
    v_cgpa numeric;
BEGIN

    SELECT
        candidate_status,
        final_cgpa
    INTO
        v_status,
        v_cgpa
    FROM public.graduation_candidates
    WHERE id = NEW.graduation_candidate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Graduation award requires a valid graduation candidate';
    END IF;

    IF v_status <> 'GRADUATED' THEN
        RAISE EXCEPTION
            'Graduation award can only be created for a GRADUATED candidate';
    END IF;

    IF NEW.final_cgpa IS NULL THEN
        RAISE EXCEPTION
            'Graduation award requires final_cgpa';
    END IF;

    IF NEW.final_cgpa < 0 OR NEW.final_cgpa > 5 THEN
        RAISE EXCEPTION
            'Graduation award final_cgpa must be between 0 and 5';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_graduation_award_integrity
ON public.graduation_awards;

CREATE TRIGGER trg_validate_graduation_award_integrity
BEFORE INSERT OR UPDATE
ON public.graduation_awards
FOR EACH ROW
EXECUTE FUNCTION public.validate_graduation_award_integrity();


-- ============================================================
-- 8. CERTIFICATE INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_certificate_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id uuid;
    v_student_id uuid;
    v_candidate_status varchar;
BEGIN

    SELECT
        ga.graduation_candidate_id,
        gc.student_id,
        gc.candidate_status
    INTO
        v_candidate_id,
        v_student_id,
        v_candidate_status
    FROM public.graduation_awards ga
    INNER JOIN public.graduation_candidates gc
        ON gc.id = ga.graduation_candidate_id
    WHERE ga.id = NEW.graduation_award_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Certificate requires a valid graduation award';
    END IF;

    IF NEW.student_id <> v_student_id THEN
        RAISE EXCEPTION
            'Certificate student does not match graduation award student';
    END IF;

    IF NEW.status = 'ISSUED' THEN

        IF v_candidate_status <> 'GRADUATED' THEN
            RAISE EXCEPTION
                'Certificate cannot be ISSUED before candidate is GRADUATED';
        END IF;

        IF NEW.issued_by IS NULL THEN
            RAISE EXCEPTION
                'Issued certificate requires issued_by';
        END IF;

        IF NEW.issue_date IS NULL THEN
            NEW.issue_date := CURRENT_DATE;
        END IF;

        IF NEW.issued_at IS NULL THEN
            NEW.issued_at := now();
        END IF;

    END IF;

    IF NEW.status = 'REVOKED' THEN

        IF NEW.revoked_by IS NULL THEN
            RAISE EXCEPTION
                'Revoked certificate requires revoked_by';
        END IF;

        IF NULLIF(trim(COALESCE(NEW.revocation_reason, '')), '') IS NULL THEN
            RAISE EXCEPTION
                'Revoked certificate requires revocation_reason';
        END IF;

        IF NEW.revoked_at IS NULL THEN
            NEW.revoked_at := now();
        END IF;

    END IF;

    IF NEW.status = 'REPLACED'
       AND NEW.replacement_of IS NULL THEN
        RAISE EXCEPTION
            'A REPLACED certificate must reference replacement_of';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_certificate_integrity
ON public.certificates;

CREATE TRIGGER trg_validate_certificate_integrity
BEFORE INSERT OR UPDATE
ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.validate_certificate_integrity();


-- ============================================================
-- 9. CERTIFICATE IMMUTABILITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.prevent_issued_certificate_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN

    IF OLD.status IN ('REVOKED', 'REPLACED') THEN
        IF NEW.status <> OLD.status THEN
            RAISE EXCEPTION
                'Final certificate status cannot be changed';
        END IF;
    END IF;

    IF OLD.status = 'ISSUED' THEN

        IF NEW.student_id <> OLD.student_id
           OR NEW.graduation_award_id <> OLD.graduation_award_id
           OR NEW.certificate_number <> OLD.certificate_number
           OR NEW.verification_code <> OLD.verification_code THEN
            RAISE EXCEPTION
                'Issued certificate identity fields are immutable';
        END IF;

    END IF;

    IF NEW.replacement_of = NEW.id THEN
        RAISE EXCEPTION
            'A certificate cannot replace itself';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_issued_certificate_change
ON public.certificates;

CREATE TRIGGER trg_prevent_issued_certificate_change
BEFORE UPDATE
ON public.certificates
FOR EACH ROW
EXECUTE FUNCTION public.prevent_issued_certificate_change();


-- ============================================================
-- 10. CERTIFICATE VERIFICATION INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_certificate_verification_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_code varchar(100);
BEGIN

    SELECT verification_code
    INTO v_code
    FROM public.certificates
    WHERE id = NEW.certificate_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Certificate verification requires a valid certificate';
    END IF;

    IF NEW.verification_code <> v_code THEN
        RAISE EXCEPTION
            'Certificate verification code does not match certificate';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_certificate_verification_integrity
ON public.certificate_verifications;

CREATE TRIGGER trg_validate_certificate_verification_integrity
BEFORE INSERT OR UPDATE
ON public.certificate_verifications
FOR EACH ROW
EXECUTE FUNCTION public.validate_certificate_verification_integrity();


-- ============================================================
-- 11. ALUMNI INTEGRITY
-- ============================================================

CREATE OR REPLACE FUNCTION public.validate_alumni_integrity()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
BEGIN

    SELECT student_status
    INTO v_status
    FROM public.students
    WHERE id = NEW.student_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Alumni record requires a valid student';
    END IF;

    IF v_status <> 'GRADUATED' THEN
        RAISE EXCEPTION
            'Only GRADUATED students can have alumni records';
    END IF;

    IF NEW.graduation_year < 2000
       OR NEW.graduation_year > EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1 THEN
        RAISE EXCEPTION
            'Invalid graduation year';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS trg_validate_alumni_integrity
ON public.alumni_records;

CREATE TRIGGER trg_validate_alumni_integrity
BEFORE INSERT OR UPDATE
ON public.alumni_records
FOR EACH ROW
EXECUTE FUNCTION public.validate_alumni_integrity();


-- ============================================================
-- 12. USEFUL INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_graduation_clearances_candidate_integrity
ON public.graduation_clearances(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_graduation_approvals_candidate_integrity
ON public.graduation_approvals(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_graduation_awards_candidate_integrity
ON public.graduation_awards(graduation_candidate_id);

CREATE INDEX IF NOT EXISTS idx_certificates_student_integrity
ON public.certificates(student_id);

CREATE INDEX IF NOT EXISTS idx_certificate_verifications_certificate_integrity
ON public.certificate_verifications(certificate_id);

CREATE INDEX IF NOT EXISTS idx_alumni_student_integrity
ON public.alumni_records(student_id);


-- ============================================================
-- 13. UNIQUE ACTIVE CERTIFICATE
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS ux_certificates_active_award
ON public.certificates(graduation_award_id)
WHERE status IN ('DRAFT', 'APPROVED', 'ISSUED');


-- ============================================================
-- 14. UNIQUE ALUMNI RELATIONSHIP
-- ============================================================

CREATE UNIQUE INDEX IF NOT EXISTS ux_alumni_graduation_candidate
ON public.alumni_records(graduation_candidate_id)
WHERE graduation_candidate_id IS NOT NULL;


COMMIT;
