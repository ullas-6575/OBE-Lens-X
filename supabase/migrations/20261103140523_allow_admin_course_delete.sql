-- Allow administrators to delete courses with no offering history.
-- The existing foreign key from offerings intentionally blocks deletion when
-- a course has offerings, preserving exam and result history.
begin;

grant delete on public.courses to authenticated;

create policy courses_delete on public.courses
  for delete to authenticated
  using ((select private.is_admin()));

commit;
