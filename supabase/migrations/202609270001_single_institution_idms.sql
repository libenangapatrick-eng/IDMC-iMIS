begin;

do $$
declare
    primary_id uuid;
    item record;
begin
    select id into primary_id
    from public.institutions
    where upper(institution_code) = 'IDMS'
    order by created_at
    limit 1;

    if primary_id is null then
        insert into public.institutions (
            institution_code, institution_name, short_name, country, status
        ) values (
            'IDMS', 'Institute of Development and Medical Sciences',
            'IDMS', 'Tanzania', 'ACTIVE'
        ) returning id into primary_id;
    end if;

    update public.institutions
    set institution_code = 'IDMS',
        institution_name = 'Institute of Development and Medical Sciences',
        short_name = 'IDMS',
        country = coalesce(nullif(country, ''), 'Tanzania'),
        status = 'ACTIVE',
        updated_at = now()
    where id = primary_id;

    -- Preserve related records by moving every institution_id reference to IDMS.
    -- A uniqueness conflict aborts and rolls back the entire migration safely.
    for item in
        select c.table_schema, c.table_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema
         and t.table_name = c.table_name
        where c.table_schema = 'public'
          and c.column_name = 'institution_id'
          and t.table_type = 'BASE TABLE'
    loop
        execute format(
            'update %I.%I set institution_id = $1 where institution_id is distinct from $1',
            item.table_schema,
            item.table_name
        ) using primary_id;
    end loop;

    delete from public.institutions where id <> primary_id;
end $$;

create or replace function public.idmc_lock_primary_institution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'INSERT' and exists (select 1 from public.institutions) then
        raise exception 'IDMC iMIS supports one institution only (IDMS).';
    end if;

    new.institution_code := 'IDMS';
    new.institution_name := 'Institute of Development and Medical Sciences';
    new.short_name := 'IDMS';
    new.status := 'ACTIVE';
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists trg_idmc_lock_primary_institution on public.institutions;
create trigger trg_idmc_lock_primary_institution
before insert or update on public.institutions
for each row execute function public.idmc_lock_primary_institution();

create or replace function public.idmc_bind_primary_institution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    primary_id uuid;
begin
    select id into primary_id
    from public.institutions
    where institution_code = 'IDMS'
    limit 1;

    if primary_id is null then
        raise exception 'The primary IDMS institution record is missing.';
    end if;

    new.institution_id := primary_id;
    return new;
end;
$$;

do $$
declare
    item record;
    trigger_name text;
begin
    for item in
        select c.table_schema, c.table_name
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema
         and t.table_name = c.table_name
        where c.table_schema = 'public'
          and c.column_name = 'institution_id'
          and t.table_type = 'BASE TABLE'
    loop
        trigger_name := 'trg_idmc_bind_primary_institution';
        execute format('drop trigger if exists %I on %I.%I', trigger_name, item.table_schema, item.table_name);
        execute format(
            'create trigger %I before insert or update of institution_id on %I.%I for each row execute function public.idmc_bind_primary_institution()',
            trigger_name,
            item.table_schema,
            item.table_name
        );
    end loop;
end $$;

do $$
begin
    if (select count(*) from public.institutions) <> 1 then
        raise exception 'Single-institution verification failed.';
    end if;
    if not exists (
        select 1 from public.institutions
        where institution_code = 'IDMS'
          and institution_name = 'Institute of Development and Medical Sciences'
          and status = 'ACTIVE'
    ) then
        raise exception 'Canonical IDMS institution verification failed.';
    end if;
end $$;

commit;
