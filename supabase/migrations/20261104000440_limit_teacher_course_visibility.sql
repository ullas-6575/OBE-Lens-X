-- Teachers may read only courses with at least one offering assigned to them.
-- Administrators retain access to every course.
begin;

drop policy courses_read on public.courses;

create policy courses_read on public.courses
  for select to authenticated
  using (
    (select private.is_admin())
    or exists (
      select 1
      from public.offerings as o
      where o.course_id = courses.id
        and (select private.can_access_offering(o.id))
    )
  );

commit;
