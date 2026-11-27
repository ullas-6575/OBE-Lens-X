-- Two assigned teachers share a student's marks without silent replacement.
begin;
create function pg_temp.assert_true(value boolean, message text) returns void
language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %', message; end if; end $$;
create function pg_temp.must_fail(statement text, expected text) returns void
language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlerrm not ilike '%' || expected || '%' then raise exception 'Wrong error: %', sqlerrm; end if;
    return;
  end;
  raise exception 'FAILED: statement unexpectedly succeeded';
end $$;
insert into auth.users(id, email) values
 ('00000000-0000-4000-8000-000000000001', 'admin@test.invalid'),
 ('00000000-0000-4000-8000-000000000002', 'first@test.invalid'),
 ('00000000-0000-4000-8000-000000000003', 'second@test.invalid'),
 ('00000000-0000-4000-8000-000000000004', 'outsider@test.invalid'),
 ('00000000-0000-4000-8000-000000000005', 'pending@test.invalid');
update public.profiles set status = 'approved'
where id <> '00000000-0000-4000-8000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"app_metadata":{"role":"admin"}}', true);
insert into public.courses(id, code, title, outcomes) values
 ('10000000-0000-4000-8000-000000000001', 'SHARED', 'Shared course',
  '[{"code":"CO1","description":"Apply principles","pos":["PO1"]}]');
insert into public.offerings(id, course_id, academic_year, term) values
 ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '2026', '1');
insert into public.teaching_assignments(offering_id, teacher_id)
select '20000000-0000-4000-8000-000000000001', id from public.profiles
where id in ('00000000-0000-4000-8000-000000000002',
             '00000000-0000-4000-8000-000000000003',
             '00000000-0000-4000-8000-000000000005');
insert into public.exams(id, offering_id, name, required_groups, questions) values
 ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001',
  'Final', '["1-4","5-8"]',
  '[{"question":"1","part":"a","co":"CO1","max_mark":10},
    {"question":"5","part":"a","co":"CO1","max_mark":10}]');
create temporary table grid as select jsonb_object_agg(q::text, parts) marks from
 (select q, jsonb_object_agg(p, case when q=1 and p='a' then '5' else 'N/A' end) parts
  from generate_series(1,4) q cross join unnest(array['a','b','c','d','e','f','g']) p group by q) s;
create temporary table responses(kind text primary key, payload jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{}', true);
insert into responses values ('first', public.save_question_group(
 '30000000-0000-4000-8000-000000000001', ' ROLL001 ',
 '40000000-0000-4000-8000-000000000001', '1-4', (select marks from grid), 1));
select pg_temp.assert_true((select payload->>'status'='saved' from responses where kind='first'), 'First group saved');
select public.save_question_group('30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000001', '1-4', (select marks from grid), 1);
select pg_temp.assert_true((select count(*)=1 from public.results), 'Initial retry is idempotent');

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
select public.save_question_group('30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000002', '5-8',
 (select jsonb_object_agg(q::text, parts) from
   (select q, jsonb_object_agg(p, case when q=5 and p='a' then '7' else 'N/A' end) parts
    from generate_series(5,8) q cross join unnest(array['a','b','c','d','e','f','g']) p group by q) s), 1);
select pg_temp.assert_true((select count(*)=2 and sum(grand_total)=12 from public.results), 'Both teachers groups are retained');
insert into responses values ('conflict', public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000003', '1-4',
 (select jsonb_set(marks, '{1,a}', '"9"') from grid), 1));
select pg_temp.assert_true((select payload->>'status'='conflict' and
 payload->'previous'->'marks'->'1'->>'a'='5' from responses where kind='conflict'), 'Duplicate returns previous marks for confirmation');
select pg_temp.assert_true((select grand_total=5 and revision=1 from public.results where table_type='1-4'), 'Keeping previous marks requires no write');

-- The first teacher changes the group while the second teacher's prompt is open.
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', true);
select public.save_question_group('30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000004', '1-4',
 (select jsonb_set(marks, '{1,a}', '"6"') from grid), 1,
 (select id from public.results where table_type='1-4'), 1);
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
insert into responses values ('stale', public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000003', '1-4',
 (select jsonb_set(marks, '{1,a}', '"9"') from grid), 1,
 (select (payload->'previous'->>'id')::uuid from responses where kind='conflict'), 1));
select pg_temp.assert_true((select payload->>'status'='conflict' and
 (payload->'previous'->>'revision')::int=2 from responses where kind='stale'), 'Stale confirmation asks again with latest revision');
select pg_temp.assert_true((select grand_total=6 and revision=2 from public.results where table_type='1-4'), 'Stale confirmation did not overwrite newer marks');
select public.save_question_group('30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000003', '1-4',
 (select jsonb_set(marks, '{1,a}', '"9"') from grid), 1,
 (select (payload->'previous'->>'id')::uuid from responses where kind='stale'), 2);
select public.save_question_group('30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000003', '1-4',
 (select jsonb_set(marks, '{1,a}', '"9"') from grid), 1,
 (select (payload->'previous'->>'id')::uuid from responses where kind='stale'), 2);
select pg_temp.assert_true((select grand_total=9 and revision=3 from public.results where table_type='1-4'), 'Confirmed replacement and retry add only one revision');
select pg_temp.assert_true((select grand_total=7 and revision=1 from public.results where table_type='5-8'), 'Replacement preserves the other group');
select pg_temp.must_fail($q$update public.results set marks='{}' where table_type='1-4'$q$, 'permission denied');
select pg_temp.must_fail($q$select public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000005', '1-4',
 (select jsonb_set(marks, '{1,a}', '"11"') from grid), 1,
 (select id from public.results where table_type='1-4'), 3)$q$, 'excessive mark');

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000004', true);
select pg_temp.must_fail($q$select public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000006', '1-4', '{}', 1)$q$, 'access denied');
select pg_temp.must_fail($q$select private.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000006', '1-4', '{}', 1, null, null, null)$q$, 'access denied');
select pg_temp.assert_true((select count(*)=0 from public.results), 'Unassigned teacher cannot read shared marks');
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000005', true);
select pg_temp.must_fail($q$select public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000006', '1-4', '{}', 1)$q$, 'access denied');
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.must_fail($q$select public.save_question_group(
 '30000000-0000-4000-8000-000000000001', 'ROLL001',
 '40000000-0000-4000-8000-000000000006', '1-4', '{}', 1)$q$, 'Sign in');
select pg_temp.assert_true(not has_function_privilege('anon',
 'public.save_question_group(uuid,text,uuid,text,jsonb,integer,uuid,integer,text[])', 'EXECUTE'), 'Anonymous callers cannot execute the save RPC');
-- Only the disposable test runner retains fixtures for its parallel-save test.
\if :{?keep_shared_fixtures}
commit;
\else
rollback;
\endif
