-- Run after shared_marks.sql in the disposable database; fixtures roll back.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"app_metadata":{"role":"admin"}}',true);
insert into public.exams(id,offering_id,name,required_groups,questions) values
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001',
  'Choose three','["1-4"]',
  '[{"question":"1","part":"a","co":"CO1","max_mark":10},
    {"question":"2","part":"a","co":"CO1","max_mark":10},
    {"question":"3","part":"a","co":"CO1","max_mark":10},
    {"question":"4","part":"a","co":"CO1","max_mark":10}]');
create temporary table four_grid as select jsonb_object_agg(q::text,parts) marks from
 (select q,jsonb_object_agg(p,case when p='a' then
    (case when q=4 then 9 else q end)::text else 'N/A' end) parts
  from generate_series(1,4) q cross join unnest(array['a','b','c','d','e','f','g']) p group by q) s;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{}',true);
select pg_temp.must_fail($q$select public.save_question_group(
 '30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000001','1-4',(select marks from four_grid),1)$q$, 'Select exactly 3');
select pg_temp.must_fail($q$select private.counted_questions(
 '30000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),array['1','2'])$q$, 'Select exactly 3');
select pg_temp.must_fail($q$select private.counted_questions(
 '30000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),array['1','2','3','4'])$q$, 'Select exactly 3');
select pg_temp.must_fail($q$select private.counted_questions(
 '30000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),array['1','2','5'])$q$, 'Select exactly 3');
select pg_temp.must_fail($q$select private.counted_questions(
 '30000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),array['1','1','2'])$q$, 'distinct');
select public.save_question_group('30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000001','1-4',(select marks from four_grid),1,
 null,null,array['3','1','2']);
select public.save_question_group('30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000001','1-4',(select marks from four_grid),1,
 null,null,array['1','2','3']);
select pg_temp.assert_true((select grand_total=6 and marks->'4'->>'a'='9' and
 selected_questions=array['1','2','3'] and revision=1 from public.results where roll_no='CHOICE'),
 'Count only the teacher selection; preserve the higher unselected mark and canonicalize retries');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((public.save_question_group(
 '30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),1,
 null,null,array['2','3','4'])->>'status')='conflict','A changed selection also requires confirmation');
select public.save_question_group('30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),1,
 (select id from public.results where roll_no='CHOICE'),1,array['2','3','4']);
select public.save_question_group('30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000002','1-4',(select marks from four_grid),1,
 (select id from public.results where roll_no='CHOICE'),1,array['4','3','2']);
select pg_temp.assert_true((select grand_total=14 and revision=2 and marks->'1'->>'a'='1'
 from public.results where roll_no='CHOICE'),'Selection-only replacement updates totals once and preserves raw marks');
select pg_temp.assert_true((public.save_question_group(
 '30000000-0000-4000-8000-000000000002','CHOICE',
 '60000000-0000-4000-8000-000000000003','1-4',(select marks from four_grid),1,
 (select id from public.results where roll_no='CHOICE'),1,array['1','2','4'])->>'status')='conflict',
 'Stale selection confirmation cannot overwrite a newer selection');
-- Three or fewer answered questions are inferred, including explicit zero marks.
create temporary table automatic_grid as
select n, jsonb_object_agg(q::text, parts) marks from (
 select n,q,jsonb_object_agg(p,case when p='a' and q<=n then
   (case when q=1 then 0 else q end)::text else 'N/A' end) parts
 from unnest(array[0,2,3]) n cross join generate_series(1,4) q
 cross join unnest(array['a','b','c','d','e','f','g']) p group by n,q
) cells group by n;
select public.save_question_group('30000000-0000-4000-8000-000000000002','AUTO'||n,
 ('70000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'1-4',marks,1)
from automatic_grid;
select pg_temp.assert_true((select selected_questions=array['1','2','3'] and grand_total=5
 from public.results where roll_no='AUTO3'),'Exactly three answers are inferred; zero counts as answered');
select pg_temp.assert_true((select selected_questions=array['1','2'] and grand_total=2
 from public.results where roll_no='AUTO2'),'Two answers are kept; missing slots earn zero');
select pg_temp.assert_true((select selected_questions='{}'::text[] and grand_total=0
 from public.results where roll_no='AUTO0'),'A blank script saves zero without asking for a selection');
rollback;
