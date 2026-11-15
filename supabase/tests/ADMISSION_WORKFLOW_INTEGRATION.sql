-- D03-T03 local SQL integration test (NOT RUN by assistant).
-- Run ONLY on a disposable LOCAL Supabase PostgreSQL after DB01, DB02,
-- DB02_WORKFLOW_SCHEMA, DB02_ADMISSION_OPERATIONS and fictional Auth users.
-- The entire test runs within a transaction and ROLLS BACK all school data.
-- Prepared local Auth emails:
--   sms-adm-owner@example.invalid
--   sms-adm-admin-a@example.invalid
--   sms-adm-principal-a@example.invalid
--   sms-adm-accountant-b@example.invalid
\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $test$
declare
 owner_id uuid;
 admin_id uuid;
 principal_id uuid;
 accountant_id uuid;
 s uuid:='11111111-1111-4111-8111-111111111111';
 campus_a uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 campus_b uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 y uuid:='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
 c uuid:='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 sec uuid:='33333333-3333-4333-8333-333333333333';
 a1 uuid;
 a2 uuid;
 a3 uuid;
 v_rev bigint;
 v_result jsonb;
 v_students integer;
 v_guardians jsonb:='[{"full_name":"Fictional Parent","relationship":"father",
                          "phone":"03001234567","is_primary":true}]'::jsonb;
begin
 select id into owner_id from auth.users where email='sms-adm-owner@example.invalid';
 select id into admin_id from auth.users where email='sms-adm-admin-a@example.invalid';
 select id into principal_id from auth.users where email='sms-adm-principal-a@example.invalid';
 select id into accountant_id from auth.users where email='sms-adm-accountant-b@example.invalid';
 if owner_id is null or admin_id is null or principal_id is null or accountant_id is null then
   raise exception 'Create the 4 fictional local Supabase Auth users first';
 end if;

 insert into public.schools(id,name,currency_code,timezone_name)
 values(s,'Fictional Admission Test School','PKR','Asia/Karachi');
 insert into public.campuses(id,school_id,code,name) values
 (campus_a,s,'A','Campus A'),(campus_b,s,'B','Campus B');
 insert into public.academic_years(id,school_id,label,starts_on,ends_on,is_active)
 values(y,s,'2026-27','2026-04-01','2027-03-31',true);
 insert into public.classes(id,school_id,campus_id,academic_year_id,name)
 values(c,s,campus_a,y,'Grade 5');
 insert into public.sections(id,class_id,name) values(sec,c,'Section A');
 insert into public.user_profiles(user_id,display_name)
 values(owner_id,'Test Owner'),(admin_id,'Test Admin'),
       (principal_id,'Test Principal'),(accountant_id,'Test Accountant');
 insert into public.user_roles(user_id,school_id,campus_id,role) values
 (owner_id,s,null,'owner'),
 (admin_id,s,campus_a,'admin'),
 (principal_id,s,campus_a,'principal'),
 (accountant_id,s,campus_b,'accountant');
 insert into public.school_settings(school_id,setting_key,setting_value)
 values(s,'admissions_principal_approval','true'::jsonb);

 -- Accountant on Campus B cannot create Campus A admission.
 begin
   perform app_private.admission_save_draft(accountant_id,s,campus_a,y,
      null,null,'aaaaaaaa-0000-4000-8000-000000000001',
      'Unauthorized Child','2015-02-03',null,c,sec,v_guardians);
   raise exception 'Unprivileged accountant could create an admission';
 exception when sqlstate '42501' then null;
 end;

 -- Principal approval enabled: conditional submission does not enroll yet.
 a1:=app_private.admission_save_draft(admin_id,s,campus_a,y,
   null,null,'aaaaaaaa-0000-4000-8000-000000000002',
   'Example Student One','2015-02-03','Previous School',c,sec,v_guardians);
 if a1 is null then raise exception 'Draft not created'; end if;
 if (select count(*) from public.student_documents d
      where d.application_id=a1 and d.is_required and d.is_applicable)<>2
 then raise exception 'Birth and transfer requirements not created'; end if;
 if app_private.admission_save_draft(admin_id,s,campus_a,y,
   null,null,'aaaaaaaa-0000-4000-8000-000000000002',
   'Example Student One','2015-02-03','Previous School',c,sec,v_guardians) <> a1
 then raise exception 'Create retry did not return same UUID'; end if;

 select revision into v_rev from public.admission_applications where id=a1;
 v_result:=app_private.admission_submit(admin_id,a1,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000003',
   (current_date+90),'Birth and transfer documents will be provided');
 if v_result->>'status'<>'submitted'
    or (select count(*) from public.students where school_id=s)<>0 then
   raise exception 'Principal-required admission prematurely finalized'; end if;

 -- Submission retry must not create a second application or student.
 v_result:=app_private.admission_submit(admin_id,a1,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000003',
   (current_date+90),'Birth and transfer documents will be provided');
 if v_result->>'status'<>'submitted' then
   raise exception 'Submit retry failed'; end if;

 select revision into v_rev from public.admission_applications where id=a1;
 begin
   perform app_private.admission_review(accountant_id,a1,v_rev,
      'aaaaaaaa-0000-4000-8000-000000000004','approve',null);
   raise exception 'Accountant could approve an admission';
 exception when sqlstate '42501' then null;
 end;
 v_result:=app_private.admission_review(principal_id,a1,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000005','approve',null);
 if v_result->>'status'<>'approved' then
   raise exception 'Principal approval did not finalize admission'; end if;
 if (select count(*) from public.students where school_id=s)<>1
   or (select count(*) from public.student_enrollments where school_id=s)<>1
   or (select count(*) from public.student_guardians where school_id=s)<>1
 then raise exception 'Student/guardian/enrollment finalization inconsistent'; end if;

 -- A repeated approval after a lost response must be idempotent.
 v_result:=app_private.admission_review(principal_id,a1,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000005','approve',null);
 if (select count(*) from public.students where school_id=s)<>1 then
   raise exception 'Repeated approval duplicated student'; end if;

 -- Principal return allows a corrected application; rejected submission
 -- must not create a student.
 a2:=app_private.admission_save_draft(admin_id,s,campus_a,y,
   null,null,'aaaaaaaa-0000-4000-8000-000000000006',
   'Example Student Two','2015-05-11',null,c,sec,v_guardians);
 select revision into v_rev from public.admission_applications where id=a2;
 perform app_private.admission_submit(admin_id,a2,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000007',
   (current_date+90),'Missing birth certificate');
 select revision into v_rev from public.admission_applications where id=a2;
 perform app_private.admission_review(principal_id,a2,v_rev,
   'aaaaaaaa-0000-4000-8000-000000000008','return','Correct guardian phone');
 if (select admission_status from public.admission_applications where id=a2)<>'returned'
 then raise exception 'Return transition failed'; end if;
 select revision into v_rev from public.admission_applications where id=a2;
 perform app_private.admission_save_draft(admin_id,s,campus_a,y,
   a2,v_rev,'aaaaaaaa-0000-4000-8000-000000000009',
   'Example Student Two','2015-05-11',null,c,sec,v_guardians);
 select revision into v_rev from public.admission_applications where id=a2;
 perform app_private.admission_submit(admin_id,a2,v_rev,
   'aaaaaaaa-0000-4000-8000-00000000000a',
   (current_date+90),'Awaiting birth certificate');
 select revision into v_rev from public.admission_applications where id=a2;
 perform app_private.admission_review(principal_id,a2,v_rev,
   'aaaaaaaa-0000-4000-8000-00000000000b','reject','Identity discrepancy');
 if (select count(*) from public.students where school_id=s)<>1
 then raise exception 'Rejected application created student'; end if;

 -- Owner turns approval off. Admin can admit conditionally in one atomic
 -- submission and registration is still globally unique.
 update public.school_settings set setting_value='false'::jsonb
  where school_id=s and setting_key='admissions_principal_approval';
 a3:=app_private.admission_save_draft(admin_id,s,campus_a,y,
   null,null,'aaaaaaaa-0000-4000-8000-00000000000c',
   'Example Student Three','2015-07-14',null,c,sec,v_guardians);
 select revision into v_rev from public.admission_applications where id=a3;
 v_result:=app_private.admission_submit(admin_id,a3,v_rev,
   'aaaaaaaa-0000-4000-8000-00000000000d',
   (current_date+90),'Birth certificate pending');
 if v_result->>'status'<>'approved' then
   raise exception 'Owner-disabled approval did not auto-finalize'; end if;
 if (select count(*) from public.students where school_id=s)<>2
    or (select count(distinct registration_no) from public.students where school_id=s)<>2
 then raise exception 'Registration numbering not unique'; end if;
 if (select count(*) from public.admission_action_events where school_id=s) < 9
 then raise exception 'Expected audit events missing'; end if;
end;
$test$;

\echo D03-T03 ADMISSION INTEGRATION ASSERTIONS PASSED — ROLLBACK ALL TEST DATA
rollback;
