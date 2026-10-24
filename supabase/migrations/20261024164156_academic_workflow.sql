-- Additive migration: old unscoped results and the OCR contract are preserved.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create function private.is_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select coalesce((select auth.jwt())->'app_metadata'->>'role' = 'admin', false)
$$;
revoke all on function private.is_admin() from public;
grant execute on function private.is_admin() to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  approved boolean not null default false
);
alter table public.profiles enable row level security;
grant select on public.profiles to authenticated;
grant update (approved) on public.profiles to authenticated;
create policy profiles_read on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));
create policy profiles_approve on public.profiles for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Auth owns creation. The trigger never accepts a user-provided role/approval.
create function private.create_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), coalesce(new.email, ''));
  return new;
end $$;
revoke all on function private.create_profile() from public;
create trigger create_profile after insert on auth.users
for each row execute function private.create_profile();
-- Existing accounts retain their ability to work; future accounts await approval.
insert into public.profiles(id, full_name, email, approved)
select id, coalesce(raw_user_meta_data->>'full_name',''), coalesce(email,''), true from auth.users;

create function private.is_teacher() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.profiles where id = (select auth.uid()) and approved)
$$;
revoke all on function private.is_teacher() from public;
grant execute on function private.is_teacher() to authenticated;

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (length(btrim(code)) > 0),
  title text not null check (length(btrim(title)) > 0),
  archived boolean not null default false,
  outcomes jsonb not null default '[]' check (jsonb_typeof(outcomes) = 'array'),
  revision integer not null default 1
);
create table public.offerings (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id),
  academic_year text not null check (length(btrim(academic_year)) > 0),
  term text not null check (length(btrim(term)) > 0),
  unique(course_id, academic_year, term)
);
create table public.teaching_assignments (
  offering_id uuid not null references public.offerings(id),
  teacher_id uuid not null references public.profiles(id),
  primary key(offering_id, teacher_id)
);
create index assignments_teacher_idx on public.teaching_assignments(teacher_id, offering_id);
create table public.exams (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings(id),
  name text not null check (length(btrim(name)) > 0),
  questions jsonb not null default '[]' check (jsonb_typeof(questions) = 'array'),
  required_groups jsonb not null default '["1-4","5-8"]',
  policy jsonb not null default '{"score_threshold":50,"target_percent":60,"exclude_incomplete":true,"exclude_na":false}',
  revision integer not null default 1,
  unique(offering_id, name)
);
alter table public.courses enable row level security;
alter table public.offerings enable row level security;
alter table public.teaching_assignments enable row level security;
alter table public.exams enable row level security;
grant select, insert, update on public.courses, public.offerings, public.exams to authenticated;
grant select, insert, delete on public.teaching_assignments to authenticated;

create policy assignments_read on public.teaching_assignments for select to authenticated
  using ((select private.is_admin()) or teacher_id = (select auth.uid()));
create policy assignments_insert on public.teaching_assignments for insert to authenticated
  with check ((select private.is_admin()));
create policy assignments_delete on public.teaching_assignments for delete to authenticated
  using ((select private.is_admin()));

create function private.can_access_offering(offering uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
  select private.is_admin() or (private.is_teacher() and exists(
    select 1 from public.teaching_assignments
    where offering_id = offering and teacher_id = (select auth.uid())))
$$;
revoke all on function private.can_access_offering(uuid) from public;
grant execute on function private.can_access_offering(uuid) to authenticated;

create policy offerings_read on public.offerings for select to authenticated
  using (private.can_access_offering(id));
create policy offerings_insert on public.offerings for insert to authenticated
  with check ((select private.is_admin()));
create policy offerings_update on public.offerings for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy courses_read on public.courses for select to authenticated
  using ((select private.is_admin()) or exists(select 1 from public.offerings where course_id = courses.id));
create policy courses_insert on public.courses for insert to authenticated
  with check ((select private.is_admin()));
create policy courses_update on public.courses for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy exams_read on public.exams for select to authenticated
  using (private.can_access_offering(offering_id));
create policy exams_insert on public.exams for insert to authenticated
  with check (private.can_access_offering(offering_id));
create policy exams_update on public.exams for update to authenticated
  using (private.can_access_offering(offering_id)) with check (private.can_access_offering(offering_id));

create function private.validate_course() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare c jsonb; p jsonb; codes text[] := '{}';
begin
  for c in select value from jsonb_array_elements(new.outcomes) loop
    if coalesce(c->>'code','') !~ '^CO[1-9][0-9]*$' or c->>'code' = any(codes)
      or jsonb_typeof(c->'pos') is distinct from 'array'
      or coalesce(length(btrim(c->>'description')),0) = 0 then
      raise exception 'Outcomes need unique CO codes, descriptions and PO links';
    end if;
    codes := array_append(codes,c->>'code');
    for p in select value from jsonb_array_elements(c->'pos') loop
      if (p #>> '{}') !~ '^PO([1-9]|1[0-2])$' then raise exception 'Invalid PO code'; end if;
    end loop;
  end loop;
  if tg_op = 'UPDATE' then
    if new.id <> old.id then raise exception 'Course identity cannot change'; end if;
    if exists(select 1 from public.exams e join public.offerings o on o.id=e.offering_id,
      lateral jsonb_array_elements(e.questions) q
      where o.course_id=new.id and not (q->>'co' = any(codes))) then
      raise exception 'An exam uses a removed CO. Update its mappings first';
    end if;
    new.revision := old.revision + 1;
  end if;
  return new;
end $$;
revoke all on function private.validate_course() from public;
create trigger validate_course before insert or update on public.courses
for each row execute function private.validate_course();

create function private.validate_exam() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare q jsonb; c public.courses; keys text[] := '{}'; g text;
begin
  select courses.* into c from public.courses join public.offerings o on o.course_id=courses.id
    where o.id=new.offering_id;
  if c.id is null or c.archived then raise exception 'Course unavailable or archived'; end if;
  if tg_op='UPDATE' then
    if new.id <> old.id or new.offering_id <> old.offering_id then raise exception 'Exam identity cannot change'; end if;
    new.revision := old.revision + 1;
  end if;
  if jsonb_typeof(new.required_groups) <> 'array' or jsonb_array_length(new.required_groups) not between 1 and 2
    or not new.required_groups <@ '["1-4","5-8"]'::jsonb then raise exception 'Invalid required groups'; end if;
  if jsonb_typeof(new.policy->'score_threshold') is distinct from 'number'
    or jsonb_typeof(new.policy->'target_percent') is distinct from 'number'
    or (new.policy->>'score_threshold')::numeric not between 0 and 100
    or (new.policy->>'target_percent')::numeric not between 0 and 100
    or jsonb_typeof(new.policy->'exclude_na') is distinct from 'boolean'
    or jsonb_typeof(new.policy->'exclude_incomplete') is distinct from 'boolean' then
    raise exception 'Invalid attainment policy';
  end if;
  for q in select value from jsonb_array_elements(new.questions) loop
    if coalesce(q->>'question','') !~ '^[1-8]$' or coalesce(q->>'part','') !~ '^[a-g]$'
      or coalesce(q->>'max_mark','') !~ '^[1-9][0-9]?$'
      or jsonb_typeof(q->'optional') is distinct from 'boolean'
      or not exists(select 1 from jsonb_array_elements(c.outcomes) co where co->>'code'=q->>'co')
      or ((q->>'question')||':'||(q->>'part')) = any(keys) then
      raise exception 'Invalid or duplicate question / maximum / CO mapping';
    end if;
    keys := array_append(keys, (q->>'question')||':'||(q->>'part'));
    g := case when (q->>'question')::int <=4 then '1-4' else '5-8' end;
    if not new.required_groups ? g then raise exception 'Question group is disabled'; end if;
  end loop;
  return new;
end $$;
revoke all on function private.validate_exam() from public;
create trigger validate_exam before insert or update on public.exams
for each row execute function private.validate_exam();

alter table public.results add column exam_id uuid references public.exams(id),
  add column revision integer not null default 1,
  add column updated_at timestamptz not null default now();
create unique index results_exam_student_group_idx on public.results(exam_id, roll_no, table_type)
  where exam_id is not null;
grant update (marks, grand_total) on public.results to authenticated;
drop policy "Teachers can read their own results" on public.results;
drop policy "Teachers can insert their own results" on public.results;
create policy results_read on public.results for select to authenticated using (
  (exam_id is null and teacher_id=(select auth.uid())) or
  exists(select 1 from public.exams where id=exam_id));
create policy results_insert on public.results for insert to authenticated with check (
  teacher_id=(select auth.uid()) and ((select private.is_teacher()) or (select private.is_admin())) and
  (exam_id is null or exists(select 1 from public.exams where id=exam_id)));
create policy results_update on public.results for update to authenticated
  using (exam_id is not null and exists(select 1 from public.exams where id=exam_id))
  with check (exam_id is not null and exists(select 1 from public.exams where id=exam_id));

create function private.validate_result() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare e public.exams; q text; p text; v text; maximum integer; total integer:=0; first_q int;
begin
  if new.exam_id is null then return new; end if;
  select * into e from public.exams where id=new.exam_id for share;
  if e.id is null or not e.required_groups ? new.table_type or jsonb_array_length(e.questions)=0 then
    raise exception 'Exam unavailable or questions not configured';
  end if;
  if exists(select 1 from public.courses c join public.offerings o on o.course_id=c.id
    where o.id=e.offering_id and c.archived) then raise exception 'Course archived'; end if;
  first_q := case when new.table_type='1-4' then 1 else 5 end;
  if (select count(*) from jsonb_object_keys(new.marks)) <> 4 then raise exception 'Expected four columns'; end if;
  for i in first_q..first_q+3 loop
    q:=i::text;
    if jsonb_typeof(new.marks->q) is distinct from 'object' then raise exception 'Missing column'; end if;
    if (select count(*) from jsonb_object_keys(new.marks->q)) <> 7 then raise exception 'Expected seven parts'; end if;
    foreach p in array array['a','b','c','d','e','f','g'] loop
      v:=new.marks->q->>p;
      if v is null or (v <> 'N/A' and v !~ '^[0-9]{1,2}$') then raise exception 'Invalid mark'; end if;
      if v <> 'N/A' then
        select (x->>'max_mark')::int into maximum from jsonb_array_elements(e.questions) x
          where x->>'question'=q and x->>'part'=p;
        if maximum is null or v::int>maximum then raise exception 'Unmapped or excessive mark at Q% %',q,p; end if;
        total:=total+v::int;
      end if;
    end loop;
  end loop;
  new.grand_total:=total;
  new.roll_no:=btrim(new.roll_no);
  if tg_op='UPDATE' then new.revision:=old.revision+1; end if;
  new.updated_at:=now();
  return new;
end $$;
revoke all on function private.validate_result() from public;
create trigger validate_result before insert or update on public.results
for each row execute function private.validate_result();

-- Invoker RPC: RLS remains authoritative. Revision guards prevent lost updates.
create function public.save_verified_marks(p_exam_id uuid, p_roll_no text,
  p_submission_id uuid, p_table_type text, p_marks jsonb,
  p_result_id uuid default null, p_revision integer default null,
  p_exam_revision integer default null) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare e public.exams; saved public.results; answer uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into e from public.exams where id=p_exam_id for share;
  if e.id is null then raise exception 'Exam access denied'; end if;
  if p_result_id is null then
    select * into saved from public.results where teacher_id=auth.uid() and submission_id=p_submission_id;
    if saved.id is not null then
      if saved.exam_id=p_exam_id and saved.roll_no=btrim(p_roll_no) and saved.table_type=p_table_type and saved.marks=p_marks then
        return saved.id;
      end if;
      raise exception 'Submission already saved with different values. Open saved result to revise';
    end if;
  end if;
  if e.revision is distinct from p_exam_revision then raise exception 'Exam changed. Reopen the exam before saving'; end if;
  if p_result_id is null then
    insert into public.results(exam_id, roll_no, submission_id, table_type, marks, grand_total)
    values(p_exam_id,btrim(p_roll_no),p_submission_id,p_table_type,p_marks,0)
    returning id into answer;
  else
    -- A retry after a lost response must not create another revision.
    select * into saved from public.results where id=p_result_id and exam_id=p_exam_id
      and roll_no=btrim(p_roll_no) and table_type=p_table_type for update;
    if saved.id is null then raise exception 'Result access denied'; end if;
    if saved.revision=p_revision+1 and saved.marks=p_marks then return saved.id; end if;
    update public.results set marks=p_marks, grand_total=0
      where id=saved.id and revision=p_revision returning id into answer;
    if answer is null then raise exception 'Result changed. Reload before editing'; end if;
  end if;
  return answer;
end $$;
revoke all on function public.save_verified_marks(uuid,text,uuid,text,jsonb,uuid,integer,integer) from public;
grant execute on function public.save_verified_marks(uuid,text,uuid,text,jsonb,uuid,integer,integer) to authenticated;
commit;
