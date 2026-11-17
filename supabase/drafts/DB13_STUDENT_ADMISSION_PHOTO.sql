-- DB13: optional student photo lives in same private 10 MiB admission bucket.
-- The Flutter client enforces a stricter 2 MiB image-only photo limit.
-- Only an authenticated verified school Owner may prepare a photo record
-- for a draft/returned application in an active campus.
create or replace function app_private.owner_prepare_admission_photo(
 p_application_id uuid
) returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());
 v_application public.admission_applications%rowtype;
 v_doc public.student_documents%rowtype;
begin
 if p_application_id is null or v_actor is null then
   raise exception 'Authorized Owner application required' using errcode='42501';
 end if;
 select * into v_application from public.admission_applications
   where id=p_application_id for update;
 if not found or v_application.admission_status not in ('draft','returned') or
    not app_private.is_verified_school_owner(v_actor,v_application.school_id)
    or not exists(select 1 from public.campuses c
       where c.id=v_application.campus_id and c.school_id=v_application.school_id
       and c.is_active) then
   raise exception 'Photo upload not authorized for this application'
     using errcode='42501';
 end if;
 insert into public.student_documents(
   school_id,campus_id,application_id,document_kind,
   is_required,is_applicable,document_status
 ) values(
   v_application.school_id,v_application.campus_id,
   v_application.id,'photo',false,true,'missing'
 )
 on conflict(application_id,document_kind)
   where document_kind<>'other'
 do update set is_required=false,is_applicable=true
 returning * into v_doc;
 return jsonb_build_object(
   'id',v_doc.id,'revision',v_doc.revision,
   'kind',v_doc.document_kind,'status',v_doc.document_status,
   'required',false,'applicable',true);
end;
$fn$;

create or replace function public.owner_prepare_admission_photo(
 p_application_id uuid
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_prepare_admission_photo(p_application_id);
$fn$;

revoke all on function app_private.owner_prepare_admission_photo(uuid)
 from public,anon,authenticated;
revoke all on function public.owner_prepare_admission_photo(uuid)
 from public,anon,authenticated;
grant execute on function app_private.owner_prepare_admission_photo(uuid)
 to authenticated;
grant execute on function public.owner_prepare_admission_photo(uuid)
 to authenticated;
