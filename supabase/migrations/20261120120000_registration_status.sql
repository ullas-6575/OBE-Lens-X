-- Registration review: an account is pending until an administrator approves it.
-- The tri-state status replaces the approved boolean so a rejected registration
-- is recorded explicitly instead of looking the same as a new one.
begin;

alter table public.profiles
  add column status text not null default 'pending'
  check (status in ('pending', 'approved', 'rejected'));

update public.profiles
set status = case when approved then 'approved' else 'pending' end;

alter table public.profiles drop column approved;

-- Row access is already limited to admins by profiles_approve; the column grant
-- keeps every other column read-only for the client.
grant update (status) on public.profiles to authenticated;

create or replace function private.is_teacher() returns boolean
language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and status = 'approved')
$$;

commit;
