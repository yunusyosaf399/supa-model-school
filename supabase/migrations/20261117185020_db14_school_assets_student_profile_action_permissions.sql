
-- DB14: School branding, immediate admission-photo preview, live student edits,
-- and Owner-configurable action-level staff grants. All privileged operations
-- are server-authorized; no raw student/auth/storage table writes are granted.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sms-school-logos','sms-school-logos',false,2097152,
  array['image/png','image/jpeg','image/webp']::text[])
on conflict(id) do nothing;

create table if not exists app_private.sms_branding_events(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 actor_id uuid not null references auth.users(id),
 logo_path text not null,
 happened_at timestamptz not null default now()
);
alter table app_private.sms_branding_events enable row level security;
revoke all on app_private.sms_branding_events from public,anon,authenticated;

create or replace function app_private.sms_can_insert_school_logo(p_bucket text,p_path text)
returns boolean language plpgsql stable security definer set search_path=''
as $fn$
declare v_parts text[]:=string_to_array(p_path,'/');v_school uuid;
begin
 if p_bucket<>'sms-school-logos' or array_length(v_parts,1)<>3
   or v_parts[1] !~* '^[0-9a-f-]{36}$' or v_parts[2]<>'logos'
   or v_parts[3] !~* '^[0-9a-f]{32}\.(png|jpg|webp)$' then return false;end if;
 begin v_school:=v_parts[1]::uuid;
 exception when invalid_text_representation then return false;end;
 return app_private.is_verified_school_owner((select auth.uid()),v_school);
end;
$fn$;
revoke all on function app_private.sms_can_insert_school_logo(text,text) from public,anon,authenticated;
grant execute on function app_private.sms_can_insert_school_logo(text,text) to authenticated;

create or replace function app_private.sms_can_read_school_logo(p_bucket text,p_path text)
returns boolean language plpgsql stable security definer set search_path=''
as $fn$
declare v_parts text[]:=string_to_array(p_path,'/');v_school uuid;
begin
 if p_bucket<>'sms-school-logos' or array_length(v_parts,1)<>3
   or v_parts[1] !~* '^[0-9a-f-]{36}$' or v_parts[2]<>'logos'
   or v_parts[3] !~* '^[0-9a-f]{32}\.(png|jpg|webp)$' then return false;end if;
 begin v_school:=v_parts[1]::uuid;
 exception when invalid_text_representation then return false;end;
 return app_private.has_school_access(v_school);
end;
$fn$;
revoke all on function app_private.sms_can_read_school_logo(text,text) from public,anon,authenticated;
grant execute on function app_private.sms_can_read_school_logo(text,text) to authenticated;

create policy "sms_school_logo_insert_owner" on storage.objects for insert to authenticated
with check(bucket_id='sms-school-logos' and app_private.sms_can_insert_school_logo(bucket_id,name));
create policy "sms_school_logo_read_school_members" on storage.objects for select to authenticated
using(bucket_id='sms-school-logos' and app_private.sms_can_read_school_logo(bucket_id,name));

create or replace function app_private.owner_set_school_logo(p_school uuid,p_path text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
begin
 if p_school is null or p_path is null
 or not app_private.is_verified_school_owner(v_actor,p_school)
 or not app_private.sms_can_insert_school_logo('sms-school-logos',p_path)
 or not exists(select 1 from storage.objects o
   where o.bucket_id='sms-school-logos' and o.name=p_path
   and o.archived_at is null and coalesce(o.is_delete_marker,false)=false)
 then raise exception 'Owner school logo upload not authorized or missing'
   using errcode='42501';end if;
 update public.schools set logo_storage_path=p_path,revision=revision+1
 where id=p_school;
 insert into app_private.sms_branding_events(school_id,actor_id,logo_path)
 values(p_school,v_actor,p_path);
 return jsonb_build_object('logo_storage_path',p_path);
end;
$fn$;
create or replace function public.owner_set_school_logo(p_school uuid,p_path text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_set_school_logo(p_school,p_path); $fn$;
revoke all on function app_private.owner_set_school_logo(uuid,text) from public,anon,authenticated;
revoke all on function public.owner_set_school_logo(uuid,text) from public,anon,authenticated;
grant execute on function app_private.owner_set_school_logo(uuid,text) to authenticated;
grant execute on function public.owner_set_school_logo(uuid,text) to authenticated;

create or replace function app_private.owner_admission_photo_path(p_application uuid)
returns text language plpgsql stable security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_path text;
begin
 if p_application is null or not exists(
   select 1 from public.admission_applications a
    where a.id=p_application
    and app_private.is_verified_school_owner(v_actor,a.school_id)
 ) then raise exception 'Admission photo access denied' using errcode='42501';end if;
 select d.storage_path into v_path from public.student_documents d
 where d.application_id=p_application and d.document_kind='photo'
 and d.document_status in ('uploaded','verified')
 limit 1;
 return v_path;
end;
$fn$;
create or replace function public.owner_admission_photo_path(p_application uuid)
returns text language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_admission_photo_path(p_application); $fn$;
revoke all on function app_private.owner_admission_photo_path(uuid) from public,anon,authenticated;
revoke all on function public.owner_admission_photo_path(uuid) from public,anon,authenticated;
grant execute on function app_private.owner_admission_photo_path(uuid) to authenticated;
grant execute on function public.owner_admission_photo_path(uuid) to authenticated;

create or replace function app_private.sms_owner_can_read_admission_photo(p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select p_bucket='sms-admission-documents' and exists(
  select 1 from public.student_documents d
  join public.admission_applications a on a.id=d.application_id
    and a.school_id=d.school_id and a.campus_id=d.campus_id
  where d.document_kind='photo' and d.storage_path=p_path
    and d.document_status in ('uploaded','verified')
    and app_private.is_verified_school_owner((select auth.uid()),a.school_id)
 );
$fn$;
revoke all on function app_private.sms_owner_can_read_admission_photo(text,text) from public,anon,authenticated;
grant execute on function app_private.sms_owner_can_read_admission_photo(text,text) to authenticated;
create policy "sms_owner_read_own_school_admission_photos" on storage.objects for select to authenticated
using(bucket_id='sms-admission-documents'
  and app_private.sms_owner_can_read_admission_photo(bucket_id,name));

-- Catalog is forward-compatible. Planned modules can be assigned in advance,
-- but remain non-operational until a protected backend and UI exist.
create table if not exists app_private.sms_permission_catalog(
 code text primary key check(code~'^[a-z][a-z0-9_.]+$'),
 section text not null,
 title text not null,
 action text not null check(action in ('read','create','update','delete','review','manage')),
 is_implemented boolean not null default false
);
create table if not exists app_private.sms_staff_grants(
 role_id uuid not null references public.user_roles(id) on delete cascade,
 code text not null references app_private.sms_permission_catalog(code),
 allowed boolean not null,
 changed_by uuid not null references auth.users(id),
 changed_at timestamptz not null default now(),
 primary key(role_id,code)
);
create table if not exists app_private.sms_staff_grant_audit(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 role_id uuid not null references public.user_roles(id),
 code text not null references app_private.sms_permission_catalog(code),
 allowed boolean not null,
 actor_id uuid not null references auth.users(id),
 happened_at timestamptz not null default now()
);
alter table app_private.sms_permission_catalog enable row level security;
alter table app_private.sms_staff_grants enable row level security;
alter table app_private.sms_staff_grant_audit enable row level security;
revoke all on app_private.sms_permission_catalog,app_private.sms_staff_grants,
 app_private.sms_staff_grant_audit from public,anon,authenticated;

insert into app_private.sms_permission_catalog(code,section,title,action,is_implemented) values
 ('dashboard.read','Dashboard','View Dashboard','read',false),
 ('students.read','Students','View Student Records','read',false),
 ('students.create','Students','Add Students','create',false),
 ('students.update','Students','Edit Students','update',false),
 ('students.delete','Students','Delete Students','delete',false),
 ('admissions.read','Admissions','View Admissions','read',false),
 ('admissions.create','Admissions','Create Admission','create',false),
 ('admissions.update','Admissions','Edit Admission','update',false),
 ('admissions.review','Admissions','Review and Approve Admissions','review',true),
 ('exams.read','Examinations','View Exams','read',false),
 ('exams.create','Examinations','Create Exams','create',false),
 ('exams.update','Examinations','Edit Exams','update',false),
 ('analytics.read','Analytics','View Analytics','read',false),
 ('fees.read','Fees','View Fees','read',false),
 ('fees.update','Fees','Manage Fees','update',false),
 ('attendance.read','Attendance','View Attendance','read',false),
 ('attendance.update','Attendance','Record Attendance','update',false),
 ('employees.read','Employees','View Employees','read',false),
 ('employees.update','Employees','Manage Employees','update',false),
 ('payroll.read','Payroll','View Payroll','read',false),
 ('payroll.update','Payroll','Manage Payroll','update',false),
 ('expenses.read','Expenses','View Expenses','read',false),
 ('expenses.create','Expenses','Create Expenses','create',false),
 ('expenses.review','Expenses','Approve Expenses','review',false),
 ('reports.read','Reports','View Reports','read',false),
 ('school_settings.read','Settings','View School Settings','read',false),
 ('academic.read','Academics','View Academics','read',false),
 ('academic.update','Academics','Edit Academics','update',false),
 ('users.manage','Users','Manage Users','manage',false)
on conflict(code) do nothing;

create or replace function app_private.sms_permission_allowed(
 p_school uuid,p_campus uuid,p_code text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select (select auth.uid()) is not null and exists(
 select 1 from public.user_roles r
 join public.user_profiles up on up.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 join public.schools s on s.id=r.school_id
 join public.campuses c on c.id=r.campus_id and c.school_id=r.school_id
 left join app_private.sms_staff_grants g on g.role_id=r.id and g.code=p_code
 where r.user_id=(select auth.uid()) and r.school_id=p_school and
   r.campus_id=p_campus and r.is_active and r.role not in ('owner','super_admin')
   and up.is_active and u.email_confirmed_at is not null
   and u.deleted_at is null and u.is_anonymous is not true
   and s.status='active' and c.is_active
   and coalesce(g.allowed,(r.role='principal' and p_code='admissions.review'))
 );
$fn$;
revoke all on function app_private.sms_permission_allowed(uuid,uuid,text) from public,anon,authenticated;
grant execute on function app_private.sms_permission_allowed(uuid,uuid,text) to authenticated;

create or replace function app_private.owner_staff_permission_matrix(p_role_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_role public.user_roles%rowtype;v_data jsonb;
begin
 select * into v_role from public.user_roles where id=p_role_id;
 if not found or v_role.role in ('owner','super_admin')
  or not app_private.is_verified_school_owner((select auth.uid()),v_role.school_id)
 then raise exception 'Owner staff permissions access denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'code',c.code,'section',c.section,'title',c.title,'action',c.action,
  'implemented',c.is_implemented,
  'allowed',coalesce(g.allowed,(v_role.role='principal' and c.code='admissions.review'))
 ) order by c.section,c.action,c.code),'[]'::jsonb) into v_data
 from app_private.sms_permission_catalog c
 left join app_private.sms_staff_grants g on g.role_id=p_role_id and g.code=c.code;
 return v_data;
end;
$fn$;
create or replace function public.owner_staff_permission_matrix(p_role_id uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_staff_permission_matrix(p_role_id); $fn$;
revoke all on function app_private.owner_staff_permission_matrix(uuid) from public,anon,authenticated;
revoke all on function public.owner_staff_permission_matrix(uuid) from public,anon,authenticated;
grant execute on function app_private.owner_staff_permission_matrix(uuid) to authenticated;
grant execute on function public.owner_staff_permission_matrix(uuid) to authenticated;

create or replace function app_private.owner_set_staff_permission(
 p_role_id uuid,p_code text,p_allowed boolean)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_role public.user_roles%rowtype;
begin
 select * into v_role from public.user_roles where id=p_role_id for update;
 if not found or p_allowed is null or v_role.role in ('owner','super_admin')
 or not app_private.is_verified_school_owner(v_actor,v_role.school_id)
 or not exists(select 1 from app_private.sms_permission_catalog c where c.code=p_code)
 then raise exception 'Staff permission change denied' using errcode='42501';end if;
 insert into app_private.sms_staff_grants(role_id,code,allowed,changed_by)
 values(p_role_id,p_code,p_allowed,v_actor)
 on conflict(role_id,code) do update set allowed=excluded.allowed,
 changed_by=excluded.changed_by,changed_at=now();
 insert into app_private.sms_staff_grant_audit(school_id,role_id,code,allowed,actor_id)
 values(v_role.school_id,p_role_id,p_code,p_allowed,v_actor);
 return jsonb_build_object('role_id',p_role_id,'code',p_code,'allowed',p_allowed);
end;
$fn$;
create or replace function public.owner_set_staff_permission(
 p_role_id uuid,p_code text,p_allowed boolean)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_set_staff_permission(p_role_id,p_code,p_allowed); $fn$;
revoke all on function app_private.owner_set_staff_permission(uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.owner_set_staff_permission(uuid,text,boolean) from public,anon,authenticated;
grant execute on function app_private.owner_set_staff_permission(uuid,text,boolean) to authenticated;
grant execute on function public.owner_set_staff_permission(uuid,text,boolean) to authenticated;

create or replace function app_private.sms_my_permissions()
returns jsonb language sql stable security definer set search_path=''
as $fn$
 select coalesce(jsonb_agg(distinct c.code),'[]'::jsonb)
 from app_private.sms_permission_catalog c
 where exists (
 select 1 from public.user_roles r
 where r.user_id=(select auth.uid()) and r.is_active
 and r.campus_id is not null
 and app_private.sms_permission_allowed(r.school_id,r.campus_id,c.code)
 );
$fn$;
create or replace function public.sms_my_permissions()
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.sms_my_permissions(); $fn$;
revoke all on function app_private.sms_my_permissions() from public,anon,authenticated;
revoke all on function public.sms_my_permissions() from public,anon,authenticated;
grant execute on function app_private.sms_my_permissions() to authenticated;
grant execute on function public.sms_my_permissions() to authenticated;

create table if not exists app_private.sms_student_profile_audit(
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 student_id uuid not null references public.students(id),
 actor_id uuid not null references auth.users(id),
 previous_name text not null,new_name text not null,
 previous_status text not null,new_status text not null,
 happened_at timestamptz not null default now()
);
alter table app_private.sms_student_profile_audit enable row level security;
revoke all on app_private.sms_student_profile_audit from public,anon,authenticated;

create or replace function app_private.owner_update_student_profile(
 p_school uuid,p_campus uuid,p_student uuid,p_expected_revision bigint,
 p_full_name text,p_active_status text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_student public.students%rowtype;v_actor uuid:=(select auth.uid());
begin
 if p_school is null or p_campus is null or p_student is null
   or p_expected_revision is null or p_expected_revision<1
   or length(btrim(coalesce(p_full_name,''))) not between 2 and 200
   or p_active_status not in ('active','inactive')
   or not app_private.is_verified_school_owner(v_actor,p_school)
   or not exists (
    select 1 from public.student_enrollments e
    join public.academic_years y on y.id=e.academic_year_id and y.school_id=e.school_id
    where e.student_id=p_student and e.school_id=p_school
      and e.campus_id=p_campus and e.ended_on is null and y.is_active
   )
 then raise exception 'Student profile update not authorized' using errcode='42501';end if;
 select * into v_student from public.students where id=p_student and school_id=p_school for update;
 if not found or v_student.revision<>p_expected_revision
 then raise exception 'Student profile revision changed; refresh first'
   using errcode='40001';end if;
 update public.students set full_name_en=btrim(p_full_name),
 active_status=p_active_status,updated_by=v_actor,
 revision=revision+1,updated_at=now()
 where id=p_student and school_id=p_school;
 insert into app_private.sms_student_profile_audit(
 school_id,student_id,actor_id,previous_name,new_name,previous_status,new_status)
 values(p_school,p_student,v_actor,v_student.full_name_en,btrim(p_full_name),
   v_student.active_status,p_active_status);
 return jsonb_build_object('student_id',p_student,'revision',v_student.revision+1);
end;
$fn$;
create or replace function public.owner_update_student_profile(
 p_school uuid,p_campus uuid,p_student uuid,p_expected_revision bigint,
 p_full_name text,p_active_status text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_update_student_profile(
 p_school,p_campus,p_student,p_expected_revision,p_full_name,p_active_status); $fn$;
revoke all on function app_private.owner_update_student_profile(uuid,uuid,uuid,bigint,text,text) from public,anon,authenticated;
revoke all on function public.owner_update_student_profile(uuid,uuid,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function app_private.owner_update_student_profile(uuid,uuid,uuid,bigint,text,text) to authenticated;
grant execute on function public.owner_update_student_profile(uuid,uuid,uuid,bigint,text,text) to authenticated;

create or replace function app_private.owner_student_directory(
  p_school_id uuid, p_campus_id uuid, p_limit integer default 100, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_year uuid;
  v_total bigint;
  v_rows jsonb;
begin
  if v_actor is null or p_school_id is null or p_campus_id is null
     or p_limit is null or p_limit not between 1 and 200
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid student directory request' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.user_roles r
    join public.user_profiles pr on pr.user_id = r.user_id
    join auth.users u on u.id = r.user_id
    join public.schools sch on sch.id=r.school_id
    join public.campuses ca on ca.school_id=sch.id
    where r.user_id=v_actor and r.school_id=p_school_id
      and r.role='owner' and r.campus_id is null and r.is_active
      and pr.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
      and sch.status='active'
      and ca.id=p_campus_id and ca.is_active
  ) then
    raise exception 'Verified Owner access required' using errcode='42501';
  end if;
  select y.id into v_year
    from public.academic_years y
    where y.school_id=p_school_id and y.is_active
    order by y.starts_on desc, y.id limit 1;
  if v_year is null then
    return pg_catalog.jsonb_build_object('total',0,'students','[]'::jsonb);
  end if;

  select count(*) into v_total
  from public.student_enrollments e
  join public.students st on st.id=e.student_id and st.school_id=e.school_id
  where e.school_id=p_school_id and e.campus_id=p_campus_id
    and e.academic_year_id=v_year and e.ended_on is null;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id',q.student_id,'registration_no',q.registration_no,
    'full_name',q.full_name_en,'campus_id',q.campus_id,
    'campus_name',q.campus_name,
    'class_id',q.class_id,'class_name',q.class_name,
    'section_name',q.section_name,'academic_year',q.year_label,
    'status',q.active_status,'revision',q.revision
  ) order by q.full_name_en,q.registration_no),'[]'::jsonb)
  into v_rows
  from (
    select st.id student_id,st.registration_no,st.full_name_en,
      e.campus_id, ca.name campus_name,cl.id class_id,cl.name class_name,
      coalesce(sec.name,'Unassigned') section_name,y.label year_label,
      st.active_status,st.revision
    from public.student_enrollments e
    join public.students st on st.id=e.student_id and st.school_id=e.school_id
    join public.campuses ca on ca.id=e.campus_id and ca.school_id=e.school_id
    join public.academic_years y on y.id=e.academic_year_id and y.school_id=e.school_id
    join public.classes cl on cl.id=e.class_id
      and cl.school_id=e.school_id and cl.campus_id=e.campus_id
      and cl.academic_year_id=e.academic_year_id
    left join public.sections sec on sec.id=e.section_id and sec.class_id=e.class_id
    where e.school_id=p_school_id and e.campus_id=p_campus_id
      and e.academic_year_id=v_year and e.ended_on is null
    order by st.full_name_en,st.registration_no
    limit p_limit offset p_offset
  ) q;
  return pg_catalog.jsonb_build_object('total',v_total,'students',v_rows);
end
$fn$;
create or replace function app_private.principal_review_admission(
  p_application_id uuid, p_expected_revision bigint, p_operation_id uuid,
  p_decision text, p_reason text
) returns jsonb
language plpgsql security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_application public.admission_applications%rowtype;
begin
  if v_actor is null or p_application_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 1
     or p_decision not in ('approve','return','reject') then
    raise exception 'Invalid Principal decision' using errcode='22023';
  end if;
  select * into v_application from public.admission_applications
  where id=p_application_id;
  if not found then
    raise exception 'Application not found' using errcode='42501';
  end if;
  -- Separation of duties: submitter/creator never reviews their own intake.
  if v_application.created_by=v_actor
     or exists (select 1 from public.user_roles own
        where own.user_id=v_actor and own.school_id=v_application.school_id
          and own.role in ('owner','super_admin') and own.is_active)
     or not exists (
       select 1 from public.user_roles r
         join public.user_profiles up on up.user_id=r.user_id
         join auth.users u on u.id=r.user_id
         join public.schools s on s.id=r.school_id
         join public.campuses c on c.id=r.campus_id and c.school_id=s.id
       where r.user_id=v_actor and r.school_id=v_application.school_id
         and r.campus_id=v_application.campus_id
         and r.role='principal' and r.is_active
         and up.is_active and u.email_confirmed_at is not null
         and u.deleted_at is null and u.is_anonymous is not true
         and s.status='active' and c.is_active
     ) then
    raise exception 'Assigned verified Principal required'
      using errcode='42501';
  end if;
  if not app_private.sms_permission_allowed(v_application.school_id,v_application.campus_id,'admissions.review') then
    raise exception 'Approval permission denied' using errcode='42501';
  end if;
  return app_private.admission_review(v_actor,p_application_id,
     p_expected_revision,p_operation_id,p_decision,p_reason);
end;
$fn$;
create or replace function app_private.principal_admission_queue(
  p_school_id uuid, p_campus_id uuid,
  p_limit integer default 50,p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_total bigint;
  v_items jsonb;
begin
  if v_actor is null or p_school_id is null or p_campus_id is null
    or p_limit is null or p_limit not between 1 and 100
    or p_offset is null or p_offset<0 then
    raise exception 'Invalid approval queue request' using errcode='22023';
  end if;
  if exists(select 1 from public.user_roles r
      where r.user_id=v_actor and r.school_id=p_school_id
        and r.role in ('owner','super_admin') and r.is_active)
    or not exists (
      select 1 from public.user_roles r
       join public.user_profiles up on up.user_id=r.user_id
       join auth.users u on u.id=r.user_id
       join public.schools s on s.id=r.school_id
       join public.campuses c on c.id=r.campus_id and c.school_id=s.id
      where r.user_id=v_actor and r.school_id=p_school_id
       and r.campus_id=p_campus_id and r.role='principal' and r.is_active
       and up.is_active and u.email_confirmed_at is not null
       and u.deleted_at is null and u.is_anonymous is not true
       and s.status='active' and c.is_active
    ) then
      raise exception 'Assigned verified Principal required' using errcode='42501';
  end if;
  if not app_private.sms_permission_allowed(p_school_id,p_campus_id,'admissions.review') then
    raise exception 'Approval permission denied' using errcode='42501';
  end if;
  select count(*) into v_total from public.admission_applications a
    where a.school_id=p_school_id and a.campus_id=p_campus_id
      and a.admission_status='submitted' and a.approval_state='pending'
      and a.created_by is distinct from v_actor;
  select coalesce(jsonb_agg(jsonb_build_object(
       'id',a.id,'revision',a.revision,'name',a.applicant_name,
       'year_id',a.academic_year_id,
       'documents_state',a.documents_state,
       'conditional_due',a.missing_documents_due_on,
       'conditional_reason',a.conditional_reason,
       'submitted_at',a.submitted_at,
       'pending_documents',(
         select count(*) from public.student_documents d
         where d.application_id=a.id and d.is_required and d.is_applicable
           and d.document_status <> 'verified'
       )
     ) order by a.submitted_at,a.id),'[]'::jsonb)
     into v_items
  from (
    select a.* from public.admission_applications a
    where a.school_id=p_school_id and a.campus_id=p_campus_id
      and a.admission_status='submitted' and a.approval_state='pending'
      and a.created_by is distinct from v_actor
    order by a.submitted_at,a.id
    limit p_limit offset p_offset
  ) a;
  return jsonb_build_object('total',v_total,'applications',v_items);
end;
$fn$;
create or replace function app_private.principal_can_review_application(
  p_application uuid
) returns boolean language sql stable security definer set search_path=''
as $fn$
 select auth.uid() is not null and exists (
  select 1 from public.admission_applications a
    join public.user_roles r on r.school_id=a.school_id
      and r.campus_id=a.campus_id
    join public.user_profiles up on up.user_id=r.user_id
    join auth.users u on u.id=r.user_id
    join public.schools s on s.id=a.school_id
    join public.campuses c on c.id=a.campus_id and c.school_id=s.id
  where a.id=p_application
    and a.admission_status='submitted' and a.approval_state='pending'
    and a.created_by is distinct from auth.uid()
    and r.user_id=auth.uid() and r.role='principal' and r.is_active
    and up.is_active and u.email_confirmed_at is not null
    and u.deleted_at is null and u.is_anonymous is not true
    and s.status='active' and c.is_active
    and app_private.sms_permission_allowed(a.school_id,a.campus_id,'admissions.review')
    and not exists (
     select 1 from public.user_roles owner_role
     where owner_role.user_id=auth.uid()
       and owner_role.school_id=a.school_id
       and owner_role.role in ('owner','super_admin')
       and owner_role.is_active)
 );
$fn$;
