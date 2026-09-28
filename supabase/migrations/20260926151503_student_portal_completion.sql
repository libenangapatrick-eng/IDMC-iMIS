BEGIN;

CREATE TABLE IF NOT EXISTS public.payment_provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), provider varchar(40) NOT NULL,
  event_reference varchar(150) NOT NULL, request_number varchar(80) NOT NULL,
  event_status varchar(30) NOT NULL, payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at timestamptz NOT NULL DEFAULT now(), processed_at timestamptz,
  processing_error text, UNIQUE(provider,event_reference)
);
CREATE INDEX IF NOT EXISTS idx_payment_provider_events_request ON public.payment_provider_events(request_number,received_at DESC);

CREATE OR REPLACE FUNCTION public.process_student_payment_provider_event(
  p_provider varchar,p_event_reference varchar,p_request_number varchar,p_status varchar,
  p_amount numeric DEFAULT NULL,p_control_number varchar DEFAULT NULL,
  p_provider_reference varchar DEFAULT NULL,p_message text DEFAULT NULL,p_payload jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_request public.student_payment_requests%ROWTYPE; v_invoice public.invoices%ROWTYPE;
  v_payment_id uuid; v_status varchar(30):=upper(trim(p_status)); v_inserted integer;
BEGIN
  IF coalesce(trim(p_provider),'')='' OR coalesce(trim(p_event_reference),'')='' OR coalesce(trim(p_request_number),'')='' THEN RAISE EXCEPTION 'Provider, event reference and request number are required.'; END IF;
  IF v_status NOT IN ('ISSUED','PAID','FAILED','EXPIRED','CANCELLED') THEN RAISE EXCEPTION 'Unsupported provider status: %',v_status; END IF;
  INSERT INTO public.payment_provider_events(provider,event_reference,request_number,event_status,payload)
  VALUES(upper(trim(p_provider)),trim(p_event_reference),trim(p_request_number),v_status,coalesce(p_payload,'{}'::jsonb)) ON CONFLICT(provider,event_reference) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO v_request FROM public.student_payment_requests WHERE request_number=trim(p_request_number) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment request was not found.'; END IF;
  IF v_inserted=0 THEN RETURN to_jsonb(v_request); END IF;

  IF v_status='PAID' THEN
    IF p_amount IS NULL OR round(p_amount,2)<>round(v_request.amount,2) THEN RAISE EXCEPTION 'Confirmed amount does not match the payment request amount.'; END IF;
    IF v_request.request_status='PAID' THEN RETURN to_jsonb(v_request); END IF;
    IF v_request.request_status NOT IN ('PENDING_PROVIDER','ISSUED') THEN RAISE EXCEPTION 'Payment request cannot be paid from status %.',v_request.request_status; END IF;
    IF v_request.invoice_id IS NOT NULL THEN
      SELECT * INTO v_invoice FROM public.invoices WHERE id=v_request.invoice_id AND student_id=v_request.student_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Linked invoice was not found.'; END IF;
      IF v_invoice.status IN ('CANCELLED','VOID','PAID') OR p_amount>v_invoice.balance_amount THEN RAISE EXCEPTION 'Linked invoice is not payable for this amount.'; END IF;
    END IF;
    INSERT INTO public.payments(student_id,payment_number,external_reference,control_number,payment_method,provider,amount,currency_code,payment_date,status,payer_phone,provider_transaction_id,receipt_number,metadata,confirmed_at)
    VALUES(v_request.student_id,'PAY/'||v_request.request_number,coalesce(p_provider_reference,p_event_reference),coalesce(p_control_number,v_request.control_number),'CONTROL_NUMBER',upper(trim(p_provider)),p_amount,v_request.currency_code,now(),'CONFIRMED',v_request.payer_phone,coalesce(p_provider_reference,p_event_reference),'RCT/'||v_request.request_number,jsonb_build_object('payment_request_id',v_request.id,'provider_event_reference',p_event_reference),now()) RETURNING id INTO v_payment_id;
    IF v_request.invoice_id IS NOT NULL THEN INSERT INTO public.payment_allocations(payment_id,invoice_id,allocated_amount,allocation_reference,status) VALUES(v_payment_id,v_request.invoice_id,p_amount,'ALLOC/'||v_request.request_number,'ACTIVE'); END IF;
    INSERT INTO public.financial_transactions(transaction_number,student_id,payment_id,invoice_id,transaction_type,credit_amount,transaction_date,reference_number,description,status,metadata)
    VALUES('FT/'||v_request.request_number,v_request.student_id,v_payment_id,v_request.invoice_id,'PAYMENT',p_amount,now(),coalesce(p_provider_reference,p_event_reference),'Confirmed provider payment','POSTED',jsonb_build_object('payment_request_id',v_request.id));
    UPDATE public.student_payment_requests SET request_status='PAID',control_number=coalesce(p_control_number,control_number),provider_reference=coalesce(p_provider_reference,provider_reference),provider_message=p_message,paid_at=now(),updated_at=now() WHERE id=v_request.id RETURNING * INTO v_request;
  ELSE
    UPDATE public.student_payment_requests SET request_status=v_status,control_number=coalesce(p_control_number,control_number),provider_reference=coalesce(p_provider_reference,provider_reference),provider_message=p_message,issued_at=CASE WHEN v_status='ISSUED' THEN coalesce(issued_at,now()) ELSE issued_at END,updated_at=now() WHERE id=v_request.id RETURNING * INTO v_request;
  END IF;
  UPDATE public.payment_provider_events SET processed_at=now() WHERE provider=upper(trim(p_provider)) AND event_reference=trim(p_event_reference);
  RETURN to_jsonb(v_request);
EXCEPTION WHEN OTHERS THEN
  UPDATE public.payment_provider_events SET processing_error=SQLERRM WHERE provider=upper(trim(p_provider)) AND event_reference=trim(p_event_reference); RAISE;
END; $$;

REVOKE ALL ON FUNCTION public.process_student_payment_provider_event(varchar,varchar,varchar,varchar,numeric,varchar,varchar,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_student_payment_provider_event(varchar,varchar,varchar,varchar,numeric,varchar,varchar,text,jsonb) TO service_role;
COMMIT;
