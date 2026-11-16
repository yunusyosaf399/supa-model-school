-- DB09 Dashboard Owner RLS + demo/live switching integration.
-- Host single-school preflight; fake student/year created only inside
-- transaction and ROLLED BACK. Real Owner/auth settings are not changed.

begin;
do $preflight$
begin
 if (select count(*) from public.schools)<>1
    or (select count(*) from public.academic_years)<>0
    or (select count(*) from public.students)<>0
    or (select count(*) from app_private.dashboard_demo_snapshots)<>1
 then raise exception 'Only run before first real school setup'; end if;
 if has_function_privilege('anon',
    'public.owner_dashboard_snapshot(uuid,uuid)','execute')
 then raise exception 'Anonymous access to dashboard snapshot'; end if;
 if has_table_privilege('authenticated',
    'app_private.dashboard_demo_snapshots','select')
 then raise exception 'Direct authenticated demo fixture read'; end if;
end $preflight$;

select set_config('request.jwt.claim.sub',
  (select user_id::text from public.user_roles
   where role='owner' and is_active limit 1),true);
set local role authenticated;

do $owner_demo$
declare v jsonb;
begin
 select public.owner_dashboard_snapshot(s.id,c.id) into v
 from public.schools s
 join public.campuses c on c.school_id=s.id
 limit 1;
 if v->>'source'<>'database_test_fixture'
    or v->>'is_demo'<>'true'
    or (v->>'active_students')::int<>1248
    or jsonb_array_length(v->'recent_admissions')<>4
 then raise exception 'Demo snapshot not properly scoped/marked'; end if;
end $owner_demo$;

reset role;
-- Simulate an Owner who completed initial setup and has a real student.
insert into public.academic_years(school_id,label,starts_on,ends_on,is_active)
select id,'TEST-2026–2027',date '2026-01-01',date '2027-12-31',true
from public.schools;
insert into public.classes(school_id,campus_id,academic_year_id,name)
select s.id,c.id,y.id,'TMP Grade 1'
from public.schools s join public.campuses c on c.school_id=s.id
join public.academic_years y on y.school_id=s.id;
insert into public.students(school_id,registration_no,full_name_en,date_of_birth)
select id,'TMP-DB09-001','Fixture Student',date '2016-01-01'
from public.schools;
insert into public.student_enrollments(
 student_id,school_id,campus_id,academic_year_id,class_id,admitted_on
)
select st.id,s.id,c.id,y.id,cl.id,date '2026-11-16'
from public.schools s
join public.campuses c on c.school_id=s.id
join public.academic_years y on y.school_id=s.id
join public.classes cl on cl.campus_id=c.id and cl.academic_year_id=y.id
join public.students st on st.school_id=s.id;
update public.school_settings
set setting_value=jsonb_set(setting_value,'{status}','"complete"'::jsonb)
where setting_key='initial_setup';

select set_config('request.jwt.claim.sub',
  (select user_id::text from public.user_roles
   where role='owner' and is_active limit 1),true);
set local role authenticated;
do $live$
declare v jsonb;
begin
 select public.owner_dashboard_snapshot(s.id,c.id) into v
 from public.schools s join public.campuses c on c.school_id=s.id
 limit 1;
 if v->>'is_demo'<>'false'
    or v->>'source'<>'live_db02_summary'
    or (v->>'active_students')::int<>1
    or v->'fee_collected'<>'null'::jsonb
    or v->'attendance_total'<>'null'::jsonb
 then raise exception 'Live snapshot should not include sample financial data: %',v;
 end if;
end $live$;

reset role;
select set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $unauthorized$
declare a uuid; b uuid;
begin
 select s.id,c.id into a,b
 from public.schools s join public.campuses c on c.school_id=s.id;
 begin
   perform public.owner_dashboard_snapshot(a,b);
   raise exception 'Unknown actor leaked dashboard';
 exception when insufficient_privilege then null;
 end;
end $unauthorized$;
reset role;

rollback;
