-- DB13: supplied/uploaded files do not need a missing-file deadline.
alter table public.admission_applications
 drop constraint admission_applications_documents_state_check;
alter table public.admission_applications
 add constraint admission_applications_documents_state_check
 check (documents_state in ('complete','conditional','incomplete','pending_verification'));

create or replace function app_private.admission_submit(
 p_actor uuid,p_application uuid,p_expected_revision bigint,
 p_operation uuid,p_conditional_due date,p_conditional_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
 a public.admission_applications%rowtype;
 v_missing boolean;
 v_unverified boolean;
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
       'status',a.admission_status,'student_id',a.student_id,
       'approval_required',a.approval_state='pending',
       'document_state',a.documents_state);
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
         and pg_catalog.length(pg_catalog.regexp_replace(coalesce(phone,''),'[^0-9]','','g')) >= 7) then
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
     and d.document_status in ('missing','rejected')) into v_missing;
 select exists(select 1 from public.student_documents d
   where d.application_id=a.id and d.is_required and d.is_applicable
     and d.document_status='uploaded') into v_unverified;
 select (pg_catalog.now() at time zone s.timezone_name)::date
 into v_day from public.schools s where s.id=a.school_id;
 if a.date_of_birth > v_day then
   raise exception 'Date of birth cannot be in the future' using errcode='22023';
 end if;
 -- Conditional document completion must be within two calendar months.
 if v_missing and (
   p_conditional_due is null or p_conditional_due<v_day
   or p_conditional_due > (v_day + interval '2 months')::date
   or pg_catalog.length(pg_catalog.btrim(coalesce(p_conditional_reason,'')))<4
 ) then
   raise exception 'Missing documents require a reason and deadline within two months'
     using errcode='22023';
 end if;
 v_need_principal:=true; -- Never bypass Principal.

 -- Preserve every deadline decision; don't silently change history.
 if v_missing then
   insert into public.admission_document_deadline_events(
     school_id,campus_id,application_id,document_id,old_due_on,
     new_due_on,reason,changed_by)
   select a.school_id,a.campus_id,a.id,d.id,d.submission_due_on,
          p_conditional_due,p_conditional_reason,p_actor
     from public.student_documents d
    where d.application_id=a.id and d.is_required and d.is_applicable
      and d.document_status in ('missing','rejected')
      and d.submission_due_on is distinct from p_conditional_due;
   update public.student_documents
     set submission_due_on=p_conditional_due,updated_at=pg_catalog.now(),
         revision=revision+1
   where application_id=a.id and is_required and is_applicable
     and document_status in ('missing','rejected');
 end if;
 update public.admission_applications
   set admission_status='submitted',
       approval_state='pending',
       documents_state=case when v_missing then 'conditional'
         when v_unverified then 'pending_verification' else 'complete' end,
       missing_documents_due_on=case when v_missing then p_conditional_due else null end,
       conditional_reason=case when v_missing then
         pg_catalog.btrim(p_conditional_reason) else null end,
       submitted_at=pg_catalog.now(),updated_at=pg_catalog.now(),
       revision=revision+1
 where id=a.id;
 -- A submission only queues Principal approval; no student is created.
 v_status:='submitted';
 insert into public.admission_action_events(
   school_id,campus_id,application_id,operation_id,actor_id,action,
   previous_status,result_status,message)
 values(a.school_id,a.campus_id,a.id,p_operation,p_actor,'submitted',
    a.admission_status,v_status,
    case when v_missing then 'Conditional with deadline'
         when v_unverified then 'Uploaded, pending Principal verification'
         else 'Documents verified' end);
 return pg_catalog.jsonb_build_object(
   'application_id',a.id,'status',v_status,
   'approval_required',true,'student_id',null,
   'document_state',case when v_missing then 'conditional'
      when v_unverified then 'pending_verification' else 'complete' end);
end;
$$;


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
     and pg_catalog.length(pg_catalog.regexp_replace(coalesce(ag.phone,''),'[^0-9]','','g')) >= 7
 ) then
   raise exception 'Exactly one primary guardian with phone required'
     using errcode='23514';
 end if;
 -- Re-check document completeness before final enrollment. Never rely only
 -- on a cached label set at submission time.
 if a.documents_state='pending_verification' then
   if exists(select 1 from public.student_documents d
     where d.application_id=a.id and d.is_required and d.is_applicable
       and d.document_status <> 'verified') then
     raise exception 'Principal must verify uploaded required certificates before approval'
       using errcode='23514';
   end if;
   update public.admission_applications
     set documents_state='complete',updated_at=pg_catalog.now(),
       revision=revision+1 where id=a.id;
   a.documents_state:='complete';
 end if;
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
   -- Documents were completed while Principal approval was pending.
   -- Keep deadline events as history, but current completeness is accurate.
   update public.admission_applications
      set documents_state='complete',missing_documents_due_on=null,
          conditional_reason=null,revision=revision+1,
          updated_at=pg_catalog.now()
    where id=a.id;
   a.documents_state:='complete';
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
