-- Keep course outcomes to CO1-CO4 and make saved results read-only.
begin;

do $$
begin
  if exists (
    select 1
    from public.exams e
    join public.offerings o on o.id = e.offering_id
    cross join lateral jsonb_array_elements(e.questions) q
    where q->>'co' not in ('CO1', 'CO2', 'CO3', 'CO4')
  ) then
    raise exception 'Exam mappings use outcomes outside CO1-CO4; update those mappings before applying this migration';
  end if;
end $$;

with normalized as (
  select c.id,
    (
      select jsonb_agg(rows.outcome order by rows.number)
      from (
        select series.number,
          coalesce(
            (
              select existing.value
              from jsonb_array_elements(c.outcomes) as existing(value)
              where existing.value->>'code' = 'CO' || series.number::text
              limit 1
            ),
            jsonb_build_object(
              'code', 'CO' || series.number::text,
              'description', 'CO' || series.number::text,
              'pos', '[]'::jsonb
            )
          ) as outcome
        from generate_series(1, 4) as series(number)
      ) as rows
    ) as outcomes
  from public.courses as c
)
update public.courses as c
set outcomes = normalized.outcomes
from normalized
where c.id = normalized.id
  and c.outcomes is distinct from normalized.outcomes;

drop policy if exists results_update on public.results;
revoke update (marks, grand_total) on public.results from authenticated;

drop function public.save_verified_marks(uuid, text, uuid, text, jsonb, uuid, integer, integer);

create function public.save_verified_marks(
  p_exam_id uuid,
  p_roll_no text,
  p_submission_id uuid,
  p_table_type text,
  p_marks jsonb,
  p_exam_revision integer
) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  e public.exams;
  saved public.results;
  answer uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;

  select * into e from public.exams where id = p_exam_id for share;
  if e.id is null then raise exception 'Exam access denied'; end if;

  select * into saved
  from public.results
  where teacher_id = auth.uid() and submission_id = p_submission_id;
  if saved.id is not null then
    if saved.exam_id = p_exam_id
      and saved.roll_no = btrim(p_roll_no)
      and saved.table_type = p_table_type
      and saved.marks = p_marks then
      return saved.id;
    end if;
    raise exception 'Submission already saved with different values';
  end if;

  if e.revision is distinct from p_exam_revision then
    raise exception 'Exam changed. Reopen the exam before saving';
  end if;

  insert into public.results(exam_id, roll_no, submission_id, table_type, marks, grand_total)
  values (p_exam_id, btrim(p_roll_no), p_submission_id, p_table_type, p_marks, 0)
  returning id into answer;

  return answer;
end $$;

revoke all on function public.save_verified_marks(uuid, text, uuid, text, jsonb, integer) from public;
grant execute on function public.save_verified_marks(uuid, text, uuid, text, jsonb, integer) to authenticated;

commit;