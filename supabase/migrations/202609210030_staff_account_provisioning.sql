begin;

insert into public.permissions(permission_code,permission_name,module_code,action_code,description,status)
values('staff.accounts.manage','Manage staff accounts','HUMAN_RESOURCES','STAFF_ACCOUNTS_MANAGE','Create or link authenticated staff identities, staff profiles and approved operational roles','ACTIVE')
on conflict(permission_code) do update set permission_name=excluded.permission_name,module_code=excluded.module_code,action_code=excluded.action_code,description=excluded.description,status='ACTIVE',updated_at=now();

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.role_code in('SUPER_ADMIN','ADMIN','HR_OFFICER') and p.permission_code='staff.accounts.manage'
on conflict do nothing;

commit;
