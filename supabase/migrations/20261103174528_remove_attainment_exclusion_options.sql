-- Fix report rules: incomplete scripts are always excluded, N/A marks count as
-- zero, and question mappings no longer have an optional flag.
begin;

alter table public.exams
  alter column policy set default '{"score_threshold":50,"target_percent":60}'::jsonb;

create or replace function private.validate_exam() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare q jsonb; c public.courses; keys text[] := '{}'; g text;
begin
  select courses.* into c from public.courses
    join public.offerings o on o.course_id = courses.id
    where o.id = new.offering_id;
  if c.id is null or c.archived then
    raise exception 'Course unavailable or archived';
  end if;
  if tg_op = 'UPDATE' then
    if new.id <> old.id or new.offering_id <> old.offering_id then
      raise exception 'Exam identity cannot change';
    end if;
    new.revision := old.revision + 1;
  end if;
  if jsonb_typeof(new.required_groups) <> 'array'
    or jsonb_array_length(new.required_groups) not between 1 and 2
    or not new.required_groups <@ '["1-4","5-8"]'::jsonb then
    raise exception 'Invalid required groups';
  end if;
  if jsonb_typeof(new.policy->'score_threshold') is distinct from 'number'
    or jsonb_typeof(new.policy->'target_percent') is distinct from 'number'
    or (new.policy->>'score_threshold')::numeric not between 0 and 100
    or (new.policy->>'target_percent')::numeric not between 0 and 100 then
    raise exception 'Invalid attainment policy';
  end if;
  for q in select value from jsonb_array_elements(new.questions) loop
    if coalesce(q->>'question', '') !~ '^[1-8]$'
      or coalesce(q->>'part', '') !~ '^[a-g]$'
      or coalesce(q->>'max_mark', '') !~ '^[1-9][0-9]?$'
      or not exists (
        select 1 from jsonb_array_elements(c.outcomes) co
        where co->>'code' = q->>'co'
      )
      or ((q->>'question') || ':' || (q->>'part')) = any(keys) then
      raise exception 'Invalid or duplicate question / maximum / CO mapping';
    end if;
    keys := array_append(keys, (q->>'question') || ':' || (q->>'part'));
    g := case when (q->>'question')::int <= 4 then '1-4' else '5-8' end;
    if not new.required_groups ? g then
      raise exception 'Question group is disabled';
    end if;
  end loop;
  return new;
end $$;

update public.exams as e
set policy = e.policy - 'exclude_incomplete' - 'exclude_na',
    questions = (
      select coalesce(jsonb_agg(item.question - 'optional' order by item.ordinality), '[]'::jsonb)
      from jsonb_array_elements(e.questions) with ordinality as item(question, ordinality)
    )
where e.policy ? 'exclude_incomplete'
   or e.policy ? 'exclude_na'
   or exists (
     select 1
     from jsonb_array_elements(e.questions) as item(question)
     where item.question ? 'optional'
   );

commit;
