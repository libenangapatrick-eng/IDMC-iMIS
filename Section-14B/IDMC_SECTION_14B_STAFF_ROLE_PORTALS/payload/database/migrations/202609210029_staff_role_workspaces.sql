begin;

alter table public.course_results drop constraint if exists course_results_result_status_check;
alter table public.course_results add constraint course_results_result_status_check check (result_status in ('DRAFT','CALCULATED','SUBMITTED','UNDER_REVIEW','VERIFIED','APPROVED','PUBLISHED','LOCKED','WITHHELD','INCOMPLETE','CANCELLED'));

insert into public.roles (role_code, role_name, description, is_system_role, status)
values
  ('REGISTRAR','Registrar','Registry leadership, registration and academic record workflows',true,'ACTIVE'),
  ('ACCOUNTANT','Accountant','Student billing, receipts and account reconciliation',true,'ACTIVE'),
  ('FINANCE_MANAGER','Finance Manager','Finance supervision, approval and reporting',true,'ACTIVE')
on conflict (role_code) do update set role_name=excluded.role_name, description=excluded.description, status='ACTIVE', updated_at=now();

insert into public.permissions (permission_code, permission_name, module_code, action_code, description, status)
values
  ('portal.lecturer','Open lecturer portal','PORTAL','LECTURER','Access the role-scoped lecturer workspace','ACTIVE'),
  ('portal.finance','Open finance portal','PORTAL','FINANCE','Access the role-scoped finance workspace','ACTIVE'),
  ('portal.registry','Open registry portal','PORTAL','REGISTRY','Access the role-scoped registry workspace','ACTIVE'),
  ('lecturer.attendance.record','Record assigned attendance','LECTURER','ATTENDANCE_RECORD','Record attendance only for an assigned course','ACTIVE'),
  ('lecturer.marks.enter','Enter assigned assessment marks','LECTURER','MARKS_ENTER','Enter draft marks only for an assigned course','ACTIVE'),
  ('lecturer.marks.submit','Submit assigned assessment marks','LECTURER','MARKS_SUBMIT','Submit own assigned draft assessment marks','ACTIVE'),
  ('lecturer.results.submit','Submit assigned course results','LECTURER','RESULTS_SUBMIT','Submit calculated results only for an assigned course','ACTIVE'),
  ('finance.payments.record','Record student payment','FINANCE','RECORD_PAYMENT','Record and allocate a verified student payment','ACTIVE'),
  ('students.requests.decide','Decide student service request','STUDENTS','DECIDE_REQUEST','Approve, reject or complete student service requests','ACTIVE')
on conflict (permission_code) do update set permission_name=excluded.permission_name, module_code=excluded.module_code, action_code=excluded.action_code, description=excluded.description, status='ACTIVE', updated_at=now();

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.role_code='LECTURER' and p.permission_code in ('portal.lecturer','lecturer.attendance.record','lecturer.marks.enter','lecturer.marks.submit','lecturer.results.submit') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.role_code in ('FINANCE_OFFICER','ACCOUNTANT','FINANCE_MANAGER') and p.permission_code in ('portal.finance','finance.view','finance.manage','finance.charges.view','finance.invoices.view','finance.payments.view','finance.payments.record','finance.refunds.view','finance.scholarships.view','finance.adjustments.view','finance.transactions.view','students.view','reports.view') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.role_code in ('REGISTRAR','ACADEMIC_OFFICER') and p.permission_code in ('portal.registry','students.view','students.manage','students.activate','students.requests.decide','academics.view','registration.view','registration.manage','registration.approve','registration.submit','registration.register','registration.lock','registration.add_drop.decide','results.view','results.review','results.approve','results.publish','results.lock','transcripts.view','transcripts.manage','transcript.generate','transcript.review','transcript.approve','transcript.issue','graduation.view') on conflict do nothing;
delete from public.role_permissions rp using public.roles r, public.permissions p where rp.role_id=r.id and rp.permission_id=p.id and r.role_code='LECTURER' and p.permission_code in ('admissions.review','admissions.verify','admissions.eligibility','admissions.decide','admissions.offer','admissions.accept','students.activate','registration.approve','registration.register','registration.lock','registration.add_drop.decide','timetable.approve','timetable.publish','timetable.lock','assessment.approve','assessment.lock','assessment.marks.approve','assessment.marks.lock','assessment.correction.decide','examination.marks.approve','examination.marks.lock','results.review','results.approve','results.publish','results.lock','transcript.approve','transcript.issue','transcript.revoke','graduation.approve','graduation.graduate','certificate.issue','certificate.revoke','academics.view','academics.manage','registration.view','registration.manage','timetable.view','timetable.manage','attendance.view','attendance.manage','assessment.view','assessment.manage','assessment.marks.submit','results.view','results.manage','results.calculate','results.submit','students.view','students.manage');

create or replace function public.idmc_record_staff_payment(p_student_id uuid,p_invoice_id uuid,p_amount numeric,p_payment_method varchar,p_reference varchar,p_payer_name varchar,p_actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_payment_id uuid; v_payment_number varchar(100); v_receipt_number varchar(100); v_invoice_balance numeric(18,2); v_invoice_student uuid; v_allocation_id uuid;
begin
  if p_student_id is null or not exists(select 1 from public.students where id=p_student_id) then raise exception 'Valid student is required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  if p_payment_method not in ('CASH','BANK','MOBILE_MONEY','CARD','CONTROL_NUMBER','ONLINE','OTHER') then raise exception 'Unsupported payment method'; end if;
  if p_invoice_id is not null then select student_id,balance_amount into v_invoice_student,v_invoice_balance from public.invoices where id=p_invoice_id for update; if v_invoice_student is null then raise exception 'Invoice was not found'; end if; if v_invoice_student <> p_student_id then raise exception 'Invoice does not belong to the selected student'; end if; if v_invoice_balance <= 0 then raise exception 'Invoice is already fully paid'; end if; if p_amount > v_invoice_balance then raise exception 'Payment exceeds the invoice balance of %',v_invoice_balance; end if; end if;
  v_payment_number:='PAY-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)); v_receipt_number:='RCT-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.payments(student_id,payment_number,external_reference,payment_method,provider,amount,currency_code,payment_date,status,payer_name,provider_transaction_id,receipt_number,confirmed_by,confirmed_at,created_by,updated_by) values(p_student_id,v_payment_number,nullif(trim(p_reference),''),p_payment_method,'STAFF_ENTRY',p_amount,'TZS',now(),'CONFIRMED',nullif(trim(p_payer_name),''),nullif(trim(p_reference),''),v_receipt_number,p_actor,now(),p_actor,p_actor) returning id into v_payment_id;
  if p_invoice_id is not null then insert into public.payment_allocations(payment_id,invoice_id,allocated_amount,allocation_reference,status) values(v_payment_id,p_invoice_id,p_amount,'ALLOC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'ACTIVE') returning id into v_allocation_id; end if;
  insert into public.financial_transactions(transaction_number,student_id,payment_id,invoice_id,transaction_type,debit_amount,credit_amount,transaction_date,reference_number,description,status,created_by) values('TXN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),p_student_id,v_payment_id,p_invoice_id,'PAYMENT',0,p_amount,now(),nullif(trim(p_reference),''),'Student payment '||v_receipt_number,'POSTED',p_actor);
  perform public.refresh_student_financial_account(p_student_id); return jsonb_build_object('payment_id',v_payment_id,'payment_number',v_payment_number,'receipt_number',v_receipt_number,'allocation_id',v_allocation_id);
end; $$;
revoke all on function public.idmc_record_staff_payment(uuid,uuid,numeric,varchar,varchar,varchar,uuid) from public,anon,authenticated;
grant execute on function public.idmc_record_staff_payment(uuid,uuid,numeric,varchar,varchar,varchar,uuid) to service_role;
commit;
