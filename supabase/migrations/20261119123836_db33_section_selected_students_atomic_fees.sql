-- DB33: atomic fee generation for a section or an explicit set of students.
-- The underlying DB25 charge logic controls discounts, optional fees and
-- cadence. All category/student charges commit together or none commit.
create or replace function app_private.sms_fee_generate_scoped(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_categories uuid[],
 p_scope text,p_section uuid,p_students uuid[],p_include_optional boolean,
 p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $body$
declare
 v_actor uuid:=(select auth.uid());
 v_cat_ids uuid[];
 v_student_ids uuid[];
 v_request jsonb;
 v_hash bytea;
 v_existing record;
 v_student uuid;
 v_cat record;
 v_line jsonb;
 v_details jsonb:='[]'::jsonb;
 v_added integer:=0;
 v_skipped integer:=0;
 v_eligible integer:=0;
 v_cat_added integer;
 v_cat_skipped integer;
 v_cat_eligible integer;
 v_result jsonb;
 v_count integer;
begin
 if v_actor is null or not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
 then raise exception 'Fee generation permission required' using errcode='42501';end if;
 if p_school is null or p_campus is null or p_year is null
   or p_month is null or p_operation is null or p_scope not in ('section','selected')
   or p_scope is null or p_categories is null
   or cardinality(p_categories) not between 1 and 20
   or (p_scope='section' and (p_section is null or
       coalesce(cardinality(p_students),0)<>0))
   or (p_scope='selected' and (p_section is not null or
       coalesce(cardinality(p_students),0) not between 1 and 120))
 then raise exception 'Invalid section/selected-student billing request'
 using errcode='22023';end if;

 select array_agg(x.id order by x.id) into v_cat_ids
 from (select distinct t.id from unnest(p_categories) t(id)) x;
 if cardinality(v_cat_ids)<>cardinality(p_categories)
    or array_position(v_cat_ids,null) is not null
 then raise exception 'Duplicate or null fee category' using errcode='22023';end if;
 select count(*) into v_count from public.fee_categories c
 where c.school_id=p_school and c.is_active and c.id=any(v_cat_ids);
 if v_count<>cardinality(v_cat_ids)
 then raise exception 'Category is not active for this school'
 using errcode='22023';end if;

 if p_scope='selected' then
   select array_agg(x.id order by x.id) into v_student_ids
   from (select distinct t.id from unnest(p_students) t(id)) x;
   if cardinality(v_student_ids)<>cardinality(p_students)
     or array_position(v_student_ids,null) is not null
   then raise exception 'Repeated or null student ID' using errcode='22023';end if;
 end if;

 -- One lock serializes all fee generation for the campus, including DB31.
 perform 1 from public.campuses c
 where c.id=p_campus and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus not active' using errcode='42501';end if;

 v_request:=jsonb_build_object('mode','scoped','school',p_school,
    'campus',p_campus,'year',p_year,'month',p_month,
    'categories',to_jsonb(v_cat_ids),'scope',p_scope,
    'section',p_section,
    'students',case when p_scope='selected' then to_jsonb(v_student_ids)
          else null end,
    'optional',coalesce(p_include_optional,false));
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
 select op.action,op.actor_id,op.request_sha256,op.result_json into v_existing
 from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
   if v_existing.action<>'generate_scoped_charges'
      or v_existing.actor_id<>v_actor or v_existing.request_sha256<>v_hash
   then raise exception 'Operation ID reused with changed billing details'
   using errcode='22023';end if;
   return v_existing.result_json;
 end if;

 if p_scope='section' then
   if not exists(
     select 1 from public.sections sec join public.classes cl on cl.id=sec.class_id
     where sec.id=p_section and cl.school_id=p_school
       and cl.campus_id=p_campus and cl.academic_year_id=p_year)
   then raise exception 'Section is outside selected campus/year'
   using errcode='42501';end if;
   select array_agg(e.student_id order by e.student_id) into v_student_ids
   from public.student_enrollments e
   join public.students st on st.id=e.student_id and st.school_id=e.school_id
   where e.school_id=p_school and e.campus_id=p_campus
     and e.academic_year_id=p_year and e.section_id=p_section
     and st.active_status='active'
     and e.admitted_on<(p_month+interval '1 month')::date
     and (e.ended_on is null or e.ended_on>=p_month);
 end if;

 if coalesce(cardinality(v_student_ids),0) not between 1 and 120
 then raise exception 'No eligible students or over 120 students in selection'
 using errcode='22023';end if;

 -- A selected group must be fully valid; never silently drop foreign IDs.
 if p_scope='selected' then
   select count(distinct e.student_id) into v_count
   from public.student_enrollments e
   join public.students st on st.id=e.student_id and st.school_id=e.school_id
   where e.school_id=p_school and e.campus_id=p_campus
     and e.academic_year_id=p_year and e.student_id=any(v_student_ids)
     and st.active_status='active'
     and e.admitted_on<(p_month+interval '1 month')::date
     and (e.ended_on is null or e.ended_on>=p_month);
   if v_count<>cardinality(v_student_ids) then
     raise exception 'Selected students must all be eligible in campus/year'
     using errcode='42501';end if;
 end if;

 for v_cat in
   select c.id,c.name,c.code,c.charge_frequency
   from public.fee_categories c
   where c.school_id=p_school and c.id=any(v_cat_ids)
   order by c.id
 loop
   v_cat_added:=0;v_cat_skipped:=0;v_cat_eligible:=0;
   foreach v_student in array v_student_ids loop
     v_line:=app_private.sms_fee_generate_category(
       p_school,p_campus,p_year,p_month,v_cat.id,
       'student',v_student,null,coalesce(p_include_optional,false),
       pg_catalog.md5(
         'db33:'||p_operation::text||':'||v_cat.id::text||':'||v_student::text
       )::uuid);
     v_cat_added:=v_cat_added+(v_line->>'added_charges')::integer;
     v_cat_skipped:=v_cat_skipped+(v_line->>'skipped_existing')::integer;
     v_cat_eligible:=v_cat_eligible+(v_line->>'eligible_students')::integer;
   end loop;
   v_added:=v_added+v_cat_added;
   v_skipped:=v_skipped+v_cat_skipped;
   v_eligible:=v_eligible+v_cat_eligible;
   v_details:=v_details||jsonb_build_array(jsonb_build_object(
     'id',v_cat.id,'code',v_cat.code,'category',v_cat.name,
     'frequency',v_cat.charge_frequency,'added_charges',v_cat_added,
     'skipped_existing',v_cat_skipped,'eligible_students',v_cat_eligible));
 end loop;

 v_result:=jsonb_build_object('saved',true,'mode','scoped',
   'scope',p_scope,'section_id',p_section,
   'student_count',cardinality(v_student_ids),
   'category_count',cardinality(v_cat_ids),
   'added_charges',v_added,'skipped_existing',v_skipped,
   'eligible_charges',v_eligible,'categories',v_details);
 insert into public.fee_operation_receipts(
   school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'generate_scoped_charges',v_actor,v_hash,v_result);
 return v_result;
end;
$body$;

create or replace function public.fee_generate_scoped(
 p_school uuid,p_campus uuid,p_year uuid,p_month date,p_categories uuid[],
 p_scope text,p_section uuid,p_students uuid[],p_include_optional boolean,
 p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $body$
 select app_private.sms_fee_generate_scoped(
 p_school,p_campus,p_year,p_month,p_categories,p_scope,p_section,
 p_students,p_include_optional,p_operation);
$body$;

revoke all on function
 app_private.sms_fee_generate_scoped(uuid,uuid,uuid,date,uuid[],text,uuid,uuid[],boolean,uuid),
 public.fee_generate_scoped(uuid,uuid,uuid,date,uuid[],text,uuid,uuid[],boolean,uuid)
from public,anon,authenticated;
grant execute on function
 app_private.sms_fee_generate_scoped(uuid,uuid,uuid,date,uuid[],text,uuid,uuid[],boolean,uuid),
 public.fee_generate_scoped(uuid,uuid,uuid,date,uuid[],text,uuid,uuid[],boolean,uuid)
to authenticated;
