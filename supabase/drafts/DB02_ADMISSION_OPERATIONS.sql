-- D03-T03 ADMISSION OPERATIONS — REVIEW DRAFT, NOT EXECUTED OR DEPLOYED.
-- Depends on DB01, DB02, DB02_WORKFLOW_SCHEMA.sql (in that order).
-- TRANSACTION CONTRACT: each function is called as one SQL statement by a
-- trusted server connection after verifying the caller's Supabase Auth token.
-- The server supplies p_actor from the VERIFIED token, never a client field.
-- DO NOT expose app_private in Supabase Data API schemas. Functions grant
-- EXECUTE ONLY to service_role (or trusted DB administrator), not clients.
-- Pending offline operations must be retried with the SAME operation UUID.

begin;

create or replace function app_private.admission_actor_allowed(
 p_actor uuid,p_school uuid,p_campus uuid,p_action text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select p_actor is not null and exists (
    select 1 from public.user_roles r
    join public.user_profiles up on up.user_id = r.user_id
    join public.campuses c on c.school_id=r.school_id
    where r.user_id=p_actor and up.is_active and r.is_active
      and r.school_id=p_school and c.id=p_campus and c.is_active
      and (
        r.role in ('owner','super_admin')
        or (r.campus_id=p_campus and
          ((p_action in ('draft','submit') and r.role='admin')
           or (p_action='review' and r.role='principal')))
      )
  )
$$;

create or replace function app_private.admission_requires_principal(p_school uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select case
      when pg_catalog.jsonb_typeof(s.setting_value)='boolean'
      then (s.setting_value #>> '{}')::boolean
      else true -- malformed owner settings must fail closed
    end
    from public.school_settings s
    where s.school_id=p_school and s.setting_key='admissions_principal_approval'
  ),false) -- Owner has not enabled approval yet
$$;

-- INTERNAL: caller already has a locked submitted admission and verified role.
-- Called ONLY from submit/review. Never granted to client roles.
create or replace function app_private.admission_finalize(
 p_application uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
 a public.admission_applications%rowtype;
 g record;
 v_guardian uuid;
 v_student uuid;
 v_number bigint;
 v_day date;
 v_primary_count integer;
begin
 select * into a from public.admission_applications
 where id=p_application for update;
 if not found or a.admission_status <> 'submitted'
    or a.student_id is not null
    or a.approval_state not in ('not_required','approved') then
   raise exception 'Admission not ready for finalization' using errcode='P0001';
 end if;
 -- Never trust a direct call to an internal function: revalidate actor
 -- even when a server function is already performing its own authorization.
 if not app_private.admission_actor_allowed(
      p_actor,a.school_id,a.campus_id,
      case when a.approval_state='approved' then 'review' else 'submit' end) then
   raise exception 'Unauthorized admission finalization' using errcode='42501';
 end if;
 if exists (
   select 1 from public.students s
   where s.school_id=a.school_id and s.date_of_birth=a.date_of_birth
     and pg_catalog.lower(pg_catalog.btrim(s.full_name_en))=
         pg_catalog.lower(pg_catalog.btrim(a.applicant_name))
 ) then
   raise exception 'A registered student may already exist; use existing student workflow'
     using errcode='23505';
 end if;
 if a.requested_class_id is null or a.date_of_birth is null then
   raise exception 'Class and birth date required' using errcode='23514';
 end if;
 select (pg_catalog.now() at time zone s.timezone_name)::date into v_day
 from public.schools s where s.id=a.school_id;
 select count(*) into v_primary_count
 from public.admission_application_guardians
 where application_id=a.id and is_primary;
 if v_primary_count<>1 or not exists (
   select 1 from public.admission_application_guardians ag
   where ag.application_id=a.id and ag.is_primary
     and pg_catalog.length(pg_catalog.btrim(coalesce(ag.phone,'')))>0
 ) then
   raise exception 'Exactly one primary guardian with phone required'
     using errcode='23514';
 end if;
 -- Re-check document completeness before final enrollment. Never rely only
 -- on a cached label set at submission time.
 if a.documents_state='complete' and exists (
   select 1 from public.student_documents d
   where d.application_id=a.id and d.is_required and d.is_applicable
     and d.document_status <> 'verified'
 ) then
   raise exception 'Required documents are not all verified';
 end if;
 if a.documents_state='conditional' and not exists (
   select 1 from public.student_documents d
   where d.application_id=a.id and d.is_required and d.is_applicable
     and d.document_status <> 'verified'
 ) then
   raise exception 'Conditional status stale; resubmit after document review';
 end if;
 if a.documents_state='conditional' then
   if a.missing_documents_due_on is null
      or pg_catalog.length(pg_catalog.btrim(coalesce(a.conditional_reason,'')))=0
   then raise exception 'Conditional admission requires due date and reason'; end if;
 elsif a.documents_state <> 'complete' then
   raise exception 'Documents are not cleared or conditionally accepted';
 end if;

 -- Assign a school-wide sequential number inside the SAME transaction.
 insert into public.school_registration_counters(school_id,next_serial)
 values(a.school_id,1) on conflict (school_id) do nothing;
 update public.school_registration_counters
   set next_serial=next_serial+1
 where school_id=a.school_id
 returning next_serial-1 into v_number;
 if v_number is null or v_number > 99999999 then
   raise exception 'School registration sequence exhausted';
 end if;
 insert into public.students(
   school_id,registration_no,full_name_en,date_of_birth,created_by)
 values(a.school_id,'SMS-'||pg_catalog.lpad(v_number::text,8,'0'),
        a.applicant_name,a.date_of_birth,p_actor)
 returning id into v_student;

 insert into public.student_enrollments(
    student_id,school_id,campus_id,academic_year_id,class_id,
    section_id,admitted_on)
 values(v_student,a.school_id,a.campus_id,a.academic_year_id,
        a.requested_class_id,a.requested_section_id,v_day);

 for g in select * from public.admission_application_guardians
          where application_id=a.id
 loop
   if g.existing_guardian_id is not null then
     select gd.id into v_guardian from public.guardians gd
      where gd.id=g.existing_guardian_id and gd.school_id=a.school_id;
     if v_guardian is null then
       raise exception 'Existing guardian belongs to a different school';
     end if;
   else
     insert into public.guardians(school_id,full_name,phone,created_by)
     values(a.school_id,g.full_name,g.phone,p_actor)
     returning id into v_guardian;
   end if;
   insert into public.student_guardians(
     student_id,guardian_id,school_id,relationship,is_primary,
     emergency_contact,is_legal_guardian)
   values(v_student,v_guardian,a.school_id,g.relationship,g.is_primary,
          g.is_primary,g.is_legal_guardian);
 end loop;

 update public.admission_applications
 set student_id=v_student,admission_status='approved',
     approved_at=pg_catalog.now(),
     approved_by=case when a.approval_state='approved' then p_actor else null end,
     updated_at=pg_catalog.now(),revision=revision+1
 where id=a.id;
 update public.student_documents
 set student_id=v_student,updated_at=pg_catalog.now(),revision=revision+1
 where application_id=a.id and student_id is null;
 return v_student;
end;
$$;

-- p_guardians is a JSON array of {full_name,relationship,phone,is_primary,
-- is_legal_guardian,existing_guardian_id}. The draft can be incomplete.
create or replace function app_private.admission_save_draft(
 p_actor uuid,p_school uuid,p_campus uuid,p_year uuid,
 p_application uuid,p_expected_revision bigint,p_operation uuid,
 p_name text,p_dob date,p_previous_school text,
 p_class uuid,p_section uuid,p_guardians jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
 a public.admission_applications%rowtype;
 v_id uuid;
 v_previous_status text;
 g record;
 v_count integer:=0;
 v_primary integer:=0;
begin
 if p_operation is null or p_school is null or p_campus is null
    or p_year is null or pg_catalog.length(pg_catalog.btrim(coalesce(p_name,'')))<2
    or pg_catalog.jsonb_typeof(p_guardians) <> 'array'
    or pg_catalog.jsonb_array_length(p_guardians)>8 then
   raise exception 'Invalid admission draft input' using errcode='22023';
 end if;
 if not app_private.admission_actor_allowed(p_actor,p_school,p_campus,'draft') then
   raise exception 'Unauthorized admission draft' using errcode='42501';
 end if;
 if not exists (select 1 from public.academic_years y
    where y.id=p_year and y.school_id=p_school) then
   raise exception 'Academic year does not belong to school' using errcode='23503';
 end if;
 -- Serialize exact potential duplicates. Different children with identical
 -- names and birth dates require a future audited override review, not an
 -- unsafe silent merge.
 if p_dob is not null then
   perform pg_catalog.pg_advisory_xact_lock(
     pg_catalog.hashtextextended(
       p_school::text||':'||pg_catalog.lower(pg_catalog.btrim(p_name))
       ||':'||p_dob::text,0));
 end if;

 if p_application is null then
   select id into v_id from public.admission_applications
   where school_id=p_school and client_operation_id=p_operation;
   if v_id is not null then return v_id; end if;
 else
   select * into a from public.admission_applications
      where id=p_application for update;
   if not found or a.school_id <> p_school or a.campus_id <> p_campus
      or a.admission_status not in ('draft','returned') then
     raise exception 'Draft not editable' using errcode='P0001';
   end if;
   if a.revision is distinct from p_expected_revision then
     raise exception 'Admission revision conflict' using errcode='40001';
   end if;
   -- A repeated operation can have been confirmed but acknowledged late.
   if exists (select 1 from public.admission_action_events e
              where e.school_id=p_school and e.operation_id=p_operation
                and e.application_id=p_application and e.action='draft_updated')
   then return p_application; end if;
   v_previous_status:=a.admission_status;
 end if;
 if exists (select 1 from public.admission_action_events e
             where e.school_id=p_school and e.operation_id=p_operation)
 then raise exception 'Operation ID already assigned to another action'; end if;

 if p_dob is not null and exists (
   select 1 from public.admission_applications other
   where other.school_id=p_school
     and (p_application is null or other.id <> p_application)
     and other.date_of_birth=p_dob
     and pg_catalog.lower(pg_catalog.btrim(other.applicant_name))
         =pg_catalog.lower(pg_catalog.btrim(p_name))
     and other.admission_status in ('draft','submitted','returned')
 ) then
   raise exception 'Potential duplicate active application; manual review required'
     using errcode='23505';
 end if;

 if p_application is null then
   insert into public.admission_applications(
     school_id,campus_id,academic_year_id,applicant_name,date_of_birth,
     previous_school,requested_class_id,requested_section_id,
     client_operation_id,created_by)
   values(p_school,p_campus,p_year,pg_catalog.btrim(p_name),p_dob,
     nullif(pg_catalog.btrim(coalesce(p_previous_school,'')),''),
     p_class,p_section,p_operation,p_actor)
   returning id into v_id;
 else
   v_id:=p_application;
   update public.admission_applications
    set academic_year_id=p_year,applicant_name=pg_catalog.btrim(p_name),
        date_of_birth=p_dob,
        previous_school=nullif(pg_catalog.btrim(coalesce(p_previous_school,'')),''),
        requested_class_id=p_class,requested_section_id=p_section,
        admission_status='draft',approval_state='not_required',
        documents_state='incomplete',missing_documents_due_on=null,
        conditional_reason=null,returned_reason=null,
        updated_at=pg_catalog.now(),revision=revision+1
    where id=v_id;
   delete from public.admission_application_guardians
    where application_id=v_id;
 end if;

 -- Birth certificate always required. Transfer certificate required only
 -- if there is a previous school. Do not erase uploaded file history.
 insert into public.student_documents(school_id,campus_id,application_id,
   document_kind,is_required,is_applicable,document_status)
 values(p_school,p_campus,v_id,'birth_certificate',true,true,'missing')
 on conflict (application_id,document_kind)
    where document_kind <> 'other'
 do update set is_required=true,is_applicable=true;

 insert into public.student_documents(school_id,campus_id,application_id,
   document_kind,is_required,is_applicable,document_status)
 values(p_school,p_campus,v_id,'transfer_certificate',
    pg_catalog.length(pg_catalog.btrim(coalesce(p_previous_school,'')))>0,
    pg_catalog.length(pg_catalog.btrim(coalesce(p_previous_school,'')))>0,
    'missing')
 on conflict (application_id,document_kind)
    where document_kind <> 'other'
 do update set
   is_required=excluded.is_required,
   is_applicable=excluded.is_applicable;

 for g in
    select * from pg_catalog.jsonb_to_recordset(p_guardians)
     as x(full_name text,relationship text,phone text,is_primary boolean,
          is_legal_guardian boolean,existing_guardian_id uuid)
 loop
   v_count:=v_count+1;
   if pg_catalog.length(pg_catalog.btrim(coalesce(g.full_name,'')))<2
      or g.relationship is null
      or g.relationship not in ('father','mother','guardian','other') then
     raise exception 'Invalid guardian name or relationship'
       using errcode='22023';
   end if;
   if coalesce(g.is_primary,false) then v_primary:=v_primary+1; end if;
   insert into public.admission_application_guardians(
     school_id,campus_id,application_id,existing_guardian_id,full_name,
     relationship,phone,is_primary,is_legal_guardian)
   values(p_school,p_campus,v_id,g.existing_guardian_id,
      pg_catalog.btrim(g.full_name),g.relationship,
      nullif(pg_catalog.btrim(coalesce(g.phone,'')),''),
      coalesce(g.is_primary,false),coalesce(g.is_legal_guardian,false));
 end loop;
 if v_primary>1 then
   raise exception 'Only one primary guardian allowed' using errcode='23505';
 end if;

 insert into public.admission_action_events(
   school_id,campus_id,application_id,operation_id,actor_id,
   action,previous_status,result_status)
 values(p_school,p_campus,v_id,p_operation,p_actor,
   case when p_application is null then 'draft_created' else 'draft_updated' end,
   v_previous_status,'draft');
 return v_id;
end;
$$;

create or replace function app_private.admission_submit(
 p_actor uuid,p_application uuid,p_expected_revision bigint,
 p_operation uuid,p_conditional_due date,p_conditional_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 a public.admission_applications%rowtype;
 v_missing boolean;
 v_need_principal boolean;
 v_day date;
 v_student uuid;
 v_status text;
begin
 select * into a from public.admission_applications
   where id=p_application for update;
 if not found then raise exception 'Admission not found'; end if;
 if not app_private.admission_actor_allowed(
    p_actor,a.school_id,a.campus_id,'submit') then
   raise exception 'Unauthorized admission submission' using errcode='42501';
 end if;
 if p_operation is null then raise exception 'Operation ID required'; end if;
 if exists (select 1 from public.admission_action_events e
            where e.school_id=a.school_id and e.operation_id=p_operation) then
   if not exists (select 1 from public.admission_action_events e
     where e.school_id=a.school_id and e.operation_id=p_operation
       and e.application_id=a.id and e.action='submitted') then
     raise exception 'Operation ID reused for another action';
   end if;
   return pg_catalog.jsonb_build_object('application_id',a.id,
       'status',a.admission_status,'student_id',a.student_id);
 end if;
 if a.revision is distinct from p_expected_revision then
   raise exception 'Admission revision conflict' using errcode='40001';
 end if;
 if a.admission_status<>'draft' or a.date_of_birth is null
    or a.requested_class_id is null then
   raise exception 'Complete student identity and class placement before submission';
 end if;
 if (select count(*) from public.admission_application_guardians
     where application_id=a.id and is_primary)<>1
    or not exists (select 1 from public.admission_application_guardians
       where application_id=a.id and is_primary
         and pg_catalog.length(pg_catalog.btrim(coalesce(phone,'')))>0) then
   raise exception 'Primary guardian contact required';
 end if;
 if not exists (select 1 from public.student_documents
    where application_id=a.id and document_kind='birth_certificate'
      and is_required and is_applicable) then
   raise exception 'Birth certificate requirement missing';
 end if;
 if a.previous_school is not null and not exists (
    select 1 from public.student_documents where application_id=a.id
      and document_kind='transfer_certificate' and is_required and is_applicable)
 then raise exception 'Transfer certificate requirement missing'; end if;
 select exists(select 1 from public.student_documents d
   where d.application_id=a.id and d.is_required and d.is_applicable
     and d.document_status<>'verified') into v_missing;
 select (pg_catalog.now() at time zone s.timezone_name)::date
 into v_day from public.schools s where s.id=a.school_id;
 if v_missing and (
   p_conditional_due is null or p_conditional_due<v_day
   or pg_catalog.length(pg_catalog.btrim(coalesce(p_conditional_reason,'')))=0
 ) then
   raise exception 'Missing documents require future deadline and reason';
 end if;
 v_need_principal:=app_private.admission_requires_principal(a.school_id);

 -- Preserve every deadline decision; don't silently change history.
 if v_missing then
   insert into public.admission_document_deadline_events(
     school_id,campus_id,application_id,document_id,old_due_on,
     new_due_on,reason,changed_by)
   select a.school_id,a.campus_id,a.id,d.id,d.submission_due_on,
          p_conditional_due,p_conditional_reason,p_actor
     from public.student_documents d
    where d.application_id=a.id and d.is_required and d.is_applicable
      and d.document_status<>'verified'
      and d.submission_due_on is distinct from p_conditional_due;
   update public.student_documents
     set submission_due_on=p_conditional_due,updated_at=pg_catalog.now(),
         revision=revision+1
   where application_id=a.id and is_required and is_applicable
     and document_status<>'verified';
 end if;
 update public.admission_applications
   set admission_status='submitted',
       approval_state=case when v_need_principal then 'pending'
                            else 'not_required' end,
       documents_state=case when v_missing then 'conditional' else 'complete' end,
       missing_documents_due_on=case when v_missing then p_conditional_due else null end,
       conditional_reason=case when v_missing then
         pg_catalog.btrim(p_conditional_reason) else null end,
       submitted_at=pg_catalog.now(),updated_at=pg_catalog.now(),
       revision=revision+1
 where id=a.id;
 if not v_need_principal then
   v_student:=app_private.admission_finalize(a.id,p_actor);
   v_status:='approved';
 else
   v_status:='submitted';
 end if;
 insert into public.admission_action_events(
   school_id,campus_id,application_id,operation_id,actor_id,action,
   previous_status,result_status,message)
 values(a.school_id,a.campus_id,a.id,p_operation,p_actor,'submitted',
    a.admission_status,v_status,
    case when v_missing then 'Conditional with deadline' else 'Documents complete' end);
 return pg_catalog.jsonb_build_object(
   'application_id',a.id,'status',v_status,
   'approval_required',v_need_principal,'student_id',v_student,
   'document_state',case when v_missing then 'conditional' else 'complete' end);
end;
$$;

create or replace function app_private.admission_review(
 p_actor uuid,p_application uuid,p_expected_revision bigint,
 p_operation uuid,p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 a public.admission_applications%rowtype;
 v_student uuid;
 v_status text;
begin
 select * into a from public.admission_applications
  where id=p_application for update;
 if not found then raise exception 'Admission not found'; end if;
 if not app_private.admission_actor_allowed(
      p_actor,a.school_id,a.campus_id,'review') then
   raise exception 'Unauthorized admission review' using errcode='42501';
 end if;
 if p_operation is null or p_decision is null
    or p_decision not in ('approve','return','reject') then
   raise exception 'Invalid review operation or decision';
 end if;
 if exists (select 1 from public.admission_action_events e
     where e.school_id=a.school_id and e.operation_id=p_operation) then
   if not exists(select 1 from public.admission_action_events e
     where e.school_id=a.school_id and e.operation_id=p_operation
       and e.application_id=a.id and e.action=
       case p_decision when 'approve' then 'approved'
                       when 'return' then 'returned' else 'rejected' end)
   then raise exception 'Operation ID reused for another review'; end if;
   return pg_catalog.jsonb_build_object('application_id',a.id,
     'status',a.admission_status,'student_id',a.student_id);
 end if;
 if a.revision is distinct from p_expected_revision then
   raise exception 'Admission revision conflict' using errcode='40001';
 end if;
 if a.admission_status<>'submitted' or a.approval_state<>'pending' then
   raise exception 'Admission is not pending Principal approval';
 end if;
 if p_decision<>'approve'
    and pg_catalog.length(pg_catalog.btrim(coalesce(p_reason,'')))=0 then
   raise exception 'Return/rejection reason required';
 end if;
 if p_decision='approve' then
   update public.admission_applications
    set approval_state='approved',reviewed_by=p_actor,
        reviewed_at=pg_catalog.now(),revision=revision+1,
        updated_at=pg_catalog.now()
    where id=a.id;
   v_student:=app_private.admission_finalize(a.id,p_actor);
   v_status:='approved';
 else
   v_status:=case when p_decision='return' then 'returned' else 'rejected' end;
   update public.admission_applications
     set admission_status=v_status,approval_state=v_status,
         returned_reason=pg_catalog.btrim(p_reason),
         reviewed_by=p_actor,reviewed_at=pg_catalog.now(),
         updated_at=pg_catalog.now(),revision=revision+1
    where id=a.id;
 end if;
 insert into public.admission_action_events(
    school_id,campus_id,application_id,operation_id,actor_id,action,
    previous_status,result_status,message)
 values(a.school_id,a.campus_id,a.id,p_operation,p_actor,
    case p_decision when 'approve' then 'approved'
                    when 'return' then 'returned' else 'rejected' end,
    a.admission_status,v_status,p_reason);
 return pg_catalog.jsonb_build_object('application_id',a.id,
     'status',v_status,'student_id',v_student);
end;
$$;

-- Executable only from a TRUSTED server-side database connection, never from
-- Flutter or Supabase Data API. PUBLIC grants are revoked explicitly.
revoke all on function app_private.admission_actor_allowed(uuid,uuid,uuid,text)
  from public,anon,authenticated;
revoke all on function app_private.admission_requires_principal(uuid)
  from public,anon,authenticated;
revoke all on function app_private.admission_finalize(uuid,uuid)
  from public,anon,authenticated;
revoke all on function app_private.admission_save_draft(
 uuid,uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)
  from public,anon,authenticated;
revoke all on function app_private.admission_submit(
 uuid,uuid,bigint,uuid,date,text)
  from public,anon,authenticated;
revoke all on function app_private.admission_review(
 uuid,uuid,bigint,uuid,text,text)
  from public,anon,authenticated;

grant usage on schema app_private to service_role;
grant execute on function app_private.admission_actor_allowed(uuid,uuid,uuid,text)
  to service_role;
grant execute on function app_private.admission_requires_principal(uuid)
  to service_role;
grant execute on function app_private.admission_finalize(uuid,uuid)
  to service_role;
grant execute on function app_private.admission_save_draft(
 uuid,uuid,uuid,uuid,uuid,bigint,uuid,text,date,text,uuid,uuid,jsonb)
  to service_role;
grant execute on function app_private.admission_submit(
 uuid,uuid,bigint,uuid,date,text) to service_role;
grant execute on function app_private.admission_review(
 uuid,uuid,bigint,uuid,text,text) to service_role;

commit;
-- Critical gaps outside D03-T03:
-- 1. No verified-token Edge/server entrypoint yet; never trust client p_actor.
-- 2. No local PostgreSQL migration tests or authenticated end-to-end QA.
-- 3. Student document upload/verification service is a separate task.
-- 4. Duplicate same-name/DOB candidates are hard blocked pending audited
--    Owner exception design; never silently combine real child records.
-- 5. Paid admissions/fee ledger belong to later finance tasks.
-- 6. Offline outbox/retry transport belongs to DB04; UUID used in the model.
