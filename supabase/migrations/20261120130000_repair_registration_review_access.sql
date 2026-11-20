-- Ensure administrators can list accounts and change registration status.
-- Apply after 20261120120000_registration_status.sql.
begin;

grant select on public.profiles to authenticated;
grant update (status) on public.profiles to authenticated;

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

drop policy if exists profiles_approve on public.profiles;
create policy profiles_approve on public.profiles
  for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

commit;
