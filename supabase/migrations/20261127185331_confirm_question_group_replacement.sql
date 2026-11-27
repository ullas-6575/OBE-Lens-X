-- Keep one result per exam/student/group; replacement requires its current revision.
begin;

-- Only this checked function may update marks. Direct table updates stay revoked.
create function private.save_question_group(
  p_exam_id uuid,
  p_roll_no text,
  p_submission_id uuid,
  p_table_type text,
  p_marks jsonb,
  p_exam_revision integer,
  p_result_id uuid,
  p_result_revision integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.exams;
  saved public.results;
  answer uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not (private.is_admin() or private.is_teacher()) then
    raise exception 'Exam access denied';
  end if;
  select * into e from public.exams
  where id = p_exam_id and private.can_access_offering(offering_id)
  for share;
  if e.id is null then raise exception 'Exam access denied'; end if;
  if p_roll_no is null or length(btrim(p_roll_no)) = 0 then
    raise exception 'Student roll number is required';
  end if;
  if p_table_type is null or p_table_type not in ('1-4', '5-8') then
    raise exception 'Invalid question group';
  end if;

  -- Serialize matching uploads even when no result row exists yet.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_exam_id::text || ':' || btrim(p_roll_no) || ':' || p_table_type, 0));

  select * into saved from public.results
  where teacher_id = auth.uid() and submission_id = p_submission_id;
  if saved.id is not null then
    if saved.exam_id = p_exam_id and saved.roll_no = btrim(p_roll_no)
      and saved.table_type = p_table_type and saved.marks = p_marks then
      return jsonb_build_object('status', 'saved', 'id', saved.id);
    end if;
    raise exception 'Submission already saved with different values';
  end if;
  if e.revision is distinct from p_exam_revision then
    raise exception 'Exam changed. Reopen the exam before saving';
  end if;

  select * into saved from public.results
  where exam_id = p_exam_id and roll_no = btrim(p_roll_no)
    and table_type = p_table_type
  for update;
  if saved.id is not null then
    -- A retry after a lost replacement response must not add another revision.
    if saved.id = p_result_id and saved.revision = p_result_revision + 1
      and saved.marks = p_marks then
      return jsonb_build_object('status', 'saved', 'id', saved.id);
    end if;
    if saved.id is distinct from p_result_id
      or saved.revision is distinct from p_result_revision then
      return jsonb_build_object('status', 'conflict', 'previous', to_jsonb(saved));
    end if;
    update public.results set marks = p_marks, grand_total = 0
    where id = saved.id returning id into answer;
  else
    if p_result_id is not null then
      raise exception 'Previous result no longer exists. Reload before saving';
    end if;
    insert into public.results(exam_id, teacher_id, roll_no, submission_id,
                               table_type, marks, grand_total)
    values (p_exam_id, auth.uid(), btrim(p_roll_no), p_submission_id,
            p_table_type, p_marks, 0)
    returning id into answer;
  end if;
  return jsonb_build_object('status', 'saved', 'id', answer);
end $$;

revoke all on function private.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer) from public;
grant execute on function private.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer) to authenticated;

-- The exposed entry point keeps invoker security. The private function checks
-- approval and the exact offering before any read or write with owner privileges.
create function public.save_question_group(
  p_exam_id uuid,
  p_roll_no text,
  p_submission_id uuid,
  p_table_type text,
  p_marks jsonb,
  p_exam_revision integer,
  p_result_id uuid default null,
  p_result_revision integer default null
) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.save_question_group(p_exam_id, p_roll_no, p_submission_id,
    p_table_type, p_marks, p_exam_revision, p_result_id, p_result_revision)
$$;

revoke all on function public.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer) from public;
grant execute on function public.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer) to authenticated;

commit;
