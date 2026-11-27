-- Persist the teacher's counted questions; retain every raw mark.
begin;
alter table public.results add column selected_questions text[];
alter table public.results add constraint results_selected_question_count
  check (selected_questions is null or cardinality(selected_questions) between 0 and 3);

create function private.counted_questions(p_exam_id uuid, p_group text, p_marks jsonb, p_selected text[])
returns text[] language plpgsql security invoker set search_path = '' as $$
declare
  available text[];
  automatic text[];
  chosen text[];
begin
  select array_agg(question order by question) into available from (
    select distinct q->>'question' question
    from public.exams e cross join lateral jsonb_array_elements(e.questions) q
    where e.id=p_exam_id and
      (case when (q->>'question')::int <= 4 then '1-4' else '5-8' end)=p_group
  ) mapped;
  if coalesce(cardinality(available), 0)=0 then raise exception 'Exam group unavailable'; end if;
  if cardinality(available)<=3 then automatic:=available;
  else
    select coalesce(array_agg(q order by q), '{}'::text[]) into automatic
    from unnest(available) q where exists (
      select 1 from jsonb_each_text(p_marks->q) part
      where part.value ~ '^[0-9]{1,2}$');
  end if;
  if cardinality(automatic)<=3 then
    return automatic;
  elsif p_selected is null or cardinality(p_selected)<>3 or not (p_selected <@ available) then
    raise exception 'Select exactly 3 answered questions for group %', p_group;
  end if;
  if array_position(p_selected, null) is not null then raise exception 'Invalid selected question'; end if;
  select coalesce(array_agg(q order by q), '{}'::text[]) into chosen
  from (select distinct unnest(p_selected) q) distinct_questions;
  if cardinality(chosen)<>cardinality(p_selected) then raise exception 'Selected questions must be distinct'; end if;
  return chosen;
end $$;
revoke all on function private.counted_questions(uuid, text, jsonb, text[]) from public;
grant execute on function private.counted_questions(uuid, text, jsonb, text[]) to authenticated;

create or replace function private.validate_result() returns trigger
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
  new.selected_questions := private.counted_questions(new.exam_id, new.table_type, new.marks, new.selected_questions);
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
        if q = any(new.selected_questions) then total:=total+v::int; end if;
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

drop function public.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer);
drop function private.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer);

-- Keep one result per exam/student/group; replacement requires its current revision.

-- Only this checked function may update marks. Direct table updates stay revoked.
create function private.save_question_group(
  p_exam_id uuid,
  p_roll_no text,
  p_submission_id uuid,
  p_table_type text,
  p_marks jsonb,
  p_exam_revision integer,
  p_result_id uuid,
  p_result_revision integer,
  p_selected_questions text[]
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e public.exams;
  saved public.results;
  answer uuid;
  selected text[];
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

  selected := private.counted_questions(p_exam_id, p_table_type, p_marks, p_selected_questions);

  -- Serialize matching uploads even when no result row exists yet.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    p_exam_id::text || ':' || btrim(p_roll_no) || ':' || p_table_type, 0));

  select * into saved from public.results
  where teacher_id = auth.uid() and submission_id = p_submission_id;
  if saved.id is not null then
    if saved.exam_id = p_exam_id and saved.roll_no = btrim(p_roll_no)
      and saved.table_type = p_table_type and saved.marks = p_marks
      and saved.selected_questions is not distinct from selected then
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
      and saved.marks = p_marks
      and saved.selected_questions is not distinct from selected then
      return jsonb_build_object('status', 'saved', 'id', saved.id);
    end if;
    if saved.id is distinct from p_result_id
      or saved.revision is distinct from p_result_revision then
      return jsonb_build_object('status', 'conflict', 'previous', to_jsonb(saved));
    end if;
    update public.results set marks = p_marks, selected_questions = selected, grand_total = 0
    where id = saved.id returning id into answer;
  else
    if p_result_id is not null then
      raise exception 'Previous result no longer exists. Reload before saving';
    end if;
    insert into public.results(exam_id, teacher_id, roll_no, submission_id,
                               table_type, marks, selected_questions, grand_total)
    values (p_exam_id, auth.uid(), btrim(p_roll_no), p_submission_id,
            p_table_type, p_marks, selected, 0)
    returning id into answer;
  end if;
  return jsonb_build_object('status', 'saved', 'id', answer);
end $$;

revoke all on function private.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer, text[]) from public;
grant execute on function private.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer, text[]) to authenticated;

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
  p_result_revision integer default null,
  p_selected_questions text[] default null
) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.save_question_group(p_exam_id, p_roll_no, p_submission_id,
    p_table_type, p_marks, p_exam_revision, p_result_id, p_result_revision, p_selected_questions)
$$;

revoke all on function public.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer, text[]) from public;
grant execute on function public.save_question_group(uuid, text, uuid, text, jsonb, integer, uuid, integer, text[]) to authenticated;


commit;
