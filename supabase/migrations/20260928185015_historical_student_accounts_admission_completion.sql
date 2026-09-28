-- IDMC iMIS: historical import account + confirmed admission completion
-- Additive/idempotent. No existing student or user rows are deleted.
BEGIN;

CREATE TABLE IF NOT EXISTS public.historical_import_account_results (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id uuid NOT NULL REFERENCES public.historical_import_batches(id) ON DELETE RESTRICT,
    import_row_id uuid NOT NULL UNIQUE REFERENCES public.historical_import_rows(id) ON DELETE RESTRICT,
    student_id uuid REFERENCES public.students(id) ON DELETE RESTRICT,
    applicant_id uuid REFERENCES public.applicants(id) ON DELETE RESTRICT,
    application_id uuid REFERENCES public.applications(id) ON DELETE RESTRICT,
    admission_decision_id uuid REFERENCES public.admission_decisions(id) ON DELETE RESTRICT,
    admission_offer_id uuid REFERENCES public.admission_offers(id) ON DELETE RESTRICT,
    admission_acceptance_id uuid REFERENCES public.admission_acceptances(id) ON DELETE RESTRICT,
    user_id uuid REFERENCES public.users(id) ON DELETE RESTRICT,
    auth_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
    admission_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (admission_status IN ('PENDING','CONFIRMED','FAILED')),
    account_status varchar(30) NOT NULL DEFAULT 'PENDING'
        CHECK (account_status IN ('PENDING','CREATED','FAILED','EXISTING')),
    error_message text,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hist_account_results_batch
    ON public.historical_import_account_results(batch_id);
CREATE INDEX IF NOT EXISTS idx_hist_account_results_student
    ON public.historical_import_account_results(student_id);
CREATE INDEX IF NOT EXISTS idx_hist_account_results_user
    ON public.historical_import_account_results(user_id);

ALTER TABLE public.historical_import_account_results ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.historical_import_account_results IS
'Controlled audit/reconciliation record for historical student admission confirmation and account provisioning.';

COMMIT;
