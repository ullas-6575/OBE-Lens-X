-- Run against a disposable database after both migrations. Always rolls back fixtures.
begin;
insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000000001','admin@test.invalid'),
 ('00000000-0000-4000-8000-000000000002','teacher@test.invalid'),
 ('00000000-0000-4000-8000-000000000003','other@test.invalid'),
 ('00000000-0000-4000-8000-000000000004','pending@test.invalid');
update public.profiles set approved=true where id <> '00000000-0000-4000-8000-000000000004';

create function pg_temp.assert_true(value boolean, message text) returns void language plpgsql as $$
begin if value is distinct from true then raise exception 'FAILED: %', message; end if; end $$;
create function pg_temp.must_fail(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlerrm not ilike '%'||expected||'%' then raise exception 'Wrong error: % (expected %)',sqlerrm,expected; end if;
    return;
  end;
  raise exception 'FAILED: statement unexpectedly succeeded: %',statement;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"app_metadata":{"role":"admin"}}',true);
insert into public.courses(id,code,title,outcomes) values
 ('10000000-0000-4000-8000-000000000001','CSE3200','Software Engineering',
 '[{"code":"CO1","description":"Apply principles","pos":["PO1"]}]');
insert into public.offerings(id,course_id,academic_year,term) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','2026','1'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','2027','1');
insert into public.teaching_assignments(offering_id,teacher_id) values
 ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002'),
 ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"user_metadata":{"role":"admin"}}',true);
select pg_temp.assert_true(not private.is_admin(),'User metadata cannot grant admin');
select pg_temp.assert_true((select count(*)=1 from public.offerings),'Teacher sees only assigned offering');
select pg_temp.must_fail($q$insert into public.courses(code,title) values('FORGED','No')$q$,'row-level security');
with changed as (update public.profiles set approved=true where id='00000000-0000-4000-8000-000000000004' returning id)
select pg_temp.assert_true((select count(*)=0 from changed),'Teacher cannot approve another account');
insert into public.exams(id,offering_id,name,required_groups,questions) values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Final','["1-4"]',
 '[{"question":"1","part":"a","co":"CO1","max_mark":10,"optional":false}]');
select pg_temp.must_fail($q$insert into public.exams(offering_id,name) values
 ('20000000-0000-4000-8000-000000000002','Forbidden')$q$,'unavailable');

-- A complete 28-cell grid; inactive cells stay N/A.
create temporary table grid as select jsonb_object_agg(q::text,parts) marks from
 (select q,jsonb_object_agg(p,case when q=1 and p='a' then '5' else 'N/A' end) parts
 from generate_series(1,4) q cross join unnest(array['a','b','c','d','e','f','g']) p group by q) s;
select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000001','1-4',(select marks from grid),null,null,1);
select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000001','1-4',(select marks from grid),null,null,1);
select pg_temp.assert_true((select count(*)=1 and max(grand_total)=5 from public.results),'Retry is idempotent and total is computed');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000002','1-4',(select marks from grid),null,null,1)$q$,'duplicate key');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL002',
 '40000000-0000-4000-8000-000000000003','1-4',jsonb_set((select marks from grid),'{1,a}','"11"'),null,null,1)$q$,'excessive mark');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL002',
 '40000000-0000-4000-8000-000000000003','1-4',jsonb_set((select marks from grid),'{1,b}','"1"'),null,null,1)$q$,'Unmapped');
select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000004','1-4',jsonb_set((select marks from grid),'{1,a}','"7"'),
 (select id from public.results limit 1),1,1);
select pg_temp.assert_true((select revision=2 and grand_total=7 from public.results limit 1),'Correction updates revision and total');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000005','1-4',jsonb_set((select marks from grid),'{1,a}','"9"'),
 (select id from public.results limit 1),1,1)$q$,'Result changed');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL002',
 '40000000-0000-4000-8000-000000000006','1-4',(select marks from grid),null,null,0)$q$,'Exam changed');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true((select count(*)=0 from public.results),'Other teacher cannot read marks');
select pg_temp.assert_true((select count(*)=0 from public.exams),'Other teacher cannot read exam');
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL001',
 '40000000-0000-4000-8000-000000000007','1-4','{}',null,null,1)$q$,'access denied');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select pg_temp.assert_true(not private.is_teacher(),'New accounts await approval');
select pg_temp.assert_true((select count(*)=0 from public.courses),'Pending account sees no course data');

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"app_metadata":{"role":"admin"}}',true);
select pg_temp.assert_true((select count(*)=1 from public.results),'Admin can read course results');
select pg_temp.must_fail($q$update public.courses set outcomes='[]'$q$,'removed CO');
update public.courses set archived=true;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{}',true);
select pg_temp.must_fail($q$select public.save_verified_marks('30000000-0000-4000-8000-000000000001','ROLL002',
 '40000000-0000-4000-8000-000000000008','1-4',(select marks from grid),null,null,1)$q$,'archived');
select pg_temp.assert_true((select count(*)=1 from public.results),'Archive preserves history');
rollback;
