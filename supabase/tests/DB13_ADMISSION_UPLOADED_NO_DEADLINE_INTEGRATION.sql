-- DB13 rollback: supplied files do not need a due date. Principal verifies.
begin;
create temporary table db13_case (
 school_id uuid,campus_id uuid,owner_id uuid,principal_id uuid,
 application_id uuid,revision bigint,operation_id uuid,photo_id uuid
) on commit drop;
grant select,update on db13_case to authenticated;

do $setup$
declare v_school uuid;v_campus uuid;v_owner uuid;v_principal uuid:=gen_random_uuid();
begin
 select r.school_id,c.id,r.user_id
 into strict v_school,v_campus,v_owner from public.user_roles r
 join public.campuses c on c.school_id=r.school_id and c.is_active
 where r.role='owner' and r.is_active and r.campus_id is null limit 1;
 insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,
   encrypted_password,raw_app_meta_data,raw_user_meta_data,
   created_at,updated_at,is_anonymous)
 values(v_principal,'00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated',
 'db13-principal-'||v_principal::text||'@example.invalid',
 now(),'!fake-not-real-password!','{}'::jsonb,'{}'::jsonb,now(),now(),false);
 insert into public.user_profiles(user_id,display_name,is_active)
 values(v_principal,'TEST DB13 Principal',true);
 insert into public.user_roles(user_id,school_id,campus_id,role,is_active)
 values(v_principal,v_school,v_campus,'principal',true);
 insert into db13_case(school_id,campus_id,owner_id,principal_id)
 values(v_school,v_campus,v_owner,v_principal);
end $setup$;

select set_config('request.jwt.claim.sub',
 (select owner_id::text from db13_case limit 1),true);
set local role authenticated;
do $owner$
declare f db13_case%rowtype;v_class uuid;v_section uuid;v_year uuid;
 v_saved jsonb;v_photo jsonb;v_op uuid:=gen_random_uuid();
begin
 select * into strict f from db13_case;
 select id into strict v_year from public.academic_years
 where school_id=f.school_id and is_active limit 1;
 select id into strict v_class from public.classes
 where school_id=f.school_id and campus_id=f.campus_id
 and academic_year_id=v_year and name='Grade 1' limit 1;
 select id into strict v_section from public.sections
 where class_id=v_class and name='A' limit 1;
 v_saved:=public.owner_save_admission_draft(
 f.school_id,f.campus_id,v_year,null,null,gen_random_uuid(),
 'TEST DB13 Uploaded Child '||left(gen_random_uuid()::text,8),
 date '2018-03-20','TEST Previous School',v_class,v_section,
 '[{"full_name":"TEST Parent","relationship":"father","phone":"03001234567","is_primary":true,"is_legal_guardian":true}]'::jsonb);
 v_photo:=public.owner_prepare_admission_photo((v_saved->>'application_id')::uuid);
 if v_photo->>'kind'<>'photo' or v_photo->>'required'<>'false' then
  raise exception 'Private optional photo record not created';end if;
 update db13_case set application_id=(v_saved->>'application_id')::uuid,
  revision=(v_saved->>'revision')::bigint,operation_id=v_op,
  photo_id=(v_photo->>'id')::uuid;
end $owner$;
reset role;
-- Simulated Storage upload status: database admin, rollback only.
update public.student_documents set document_status='uploaded',
 storage_path='rollback-only-file-'||id::text,revision=revision+1
where application_id=(select application_id from db13_case)
 and document_kind in ('birth_certificate','transfer_certificate');
select set_config('request.jwt.claim.sub',
 (select owner_id::text from db13_case),true);
set local role authenticated;
do $submit$
declare f db13_case%rowtype;v_submitted jsonb;v_retry jsonb;
begin
 select * into strict f from db13_case;
 v_submitted:=public.owner_submit_admission(
  f.application_id,f.revision,f.operation_id,null,null);
 if v_submitted->>'status'<>'submitted'
   or v_submitted->>'document_state'<>'pending_verification'
   or v_submitted->>'approval_required'<>'true' then
   raise exception 'Uploaded certificates should not require deadline: %',v_submitted;
 end if;
 v_retry:=public.owner_submit_admission(
  f.application_id,f.revision,f.operation_id,null,null);
 if v_retry->>'status'<>'submitted'
    or v_retry->>'document_state'<>'pending_verification'
    or v_retry->>'approval_required'<>'true' then
    raise exception 'Repeated submission lost confirmation: %',v_retry;
 end if;
end $submit$;
reset role;

select set_config('request.jwt.claim.sub',
 (select principal_id::text from db13_case limit 1),true);
set local role authenticated;
do $principal_check$
declare f db13_case%rowtype;v_revision bigint;
begin
 select * into strict f from db13_case;
 v_revision:=f.revision+1;
 begin
  perform public.principal_review_admission(
    f.application_id,v_revision,gen_random_uuid(),'approve',null);
  raise exception 'Principal approved unverified required certificates';
 exception when check_violation then null;end;
end $principal_check$;
reset role;
update public.student_documents set
 document_status='verified',
 verified_by=(select principal_id from db13_case),
 verified_at=now(),revision=revision+1
where application_id=(select application_id from db13_case)
 and is_required and is_applicable;
select set_config('request.jwt.claim.sub',
 (select principal_id::text from db13_case),true);
set local role authenticated;
do $principal_approve$
declare f db13_case%rowtype;v_revision bigint;v_result jsonb;
begin
 select * into strict f from db13_case;
 v_revision:=f.revision+1;
 v_result:=public.principal_review_admission(
   f.application_id,v_revision,gen_random_uuid(),'approve',null);
 if v_result->>'status'<>'approved' or v_result->>'student_id' is null then
   raise exception 'Principal approval failed: %',v_result;end if;

end $principal_approve$;
reset role;
do $check_photo$
declare f db13_case%rowtype;
begin
 select * into strict f from db13_case;
 if not exists(select 1 from public.student_documents d
  join public.admission_applications a on a.id=d.application_id
  where d.id=f.photo_id and d.student_id=a.student_id
   and d.is_required=false and a.admission_status='approved')
 then raise exception 'Optional photo was not linked to enrolled student';end if;
end $check_photo$;
rollback;
