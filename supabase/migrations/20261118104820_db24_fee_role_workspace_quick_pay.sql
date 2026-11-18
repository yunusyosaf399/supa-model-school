-- DB24: role-scoped fee directory, explicit Quick Pay allocation & yearly categories.
-- No direct table grants. Posted invoices/allocations/receipts remain immutable.

alter table public.fee_categories
  drop constraint if exists fee_categories_charge_frequency_check;
alter table public.fee_categories
  add constraint fee_categories_charge_frequency_check
  check (charge_frequency in ('monthly','yearly','one_time','manual'));

create or replace function app_private.owner_create_fee_category(
  p_school uuid,p_code text,p_name text,p_frequency text,p_discountable boolean)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid;v_actor uuid:=(select auth.uid());
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only verified Owner can configure fee categories'
   using errcode='42501';end if;
 if p_code is null or p_code !~ '^[A-Z][A-Z0-9_]{1,29}$'
 or length(btrim(coalesce(p_name,''))) not between 2 and 120
 or p_frequency not in ('monthly','yearly','one_time','manual')
 or p_discountable is null
 then raise exception 'Invalid fee category inputs' using errcode='22023';end if;
 insert into public.fee_categories(
   school_id,code,name,charge_frequency,is_discountable,is_active)
 values(p_school,p_code,btrim(p_name),p_frequency,p_discountable,true)
 returning id into v_id;
 insert into app_private.sms_fee_setup_audit(
   school_id,actor_id,action,object_id,detail)
 values(p_school,v_actor,'category_created',v_id,
   jsonb_build_object('code',p_code,'frequency',p_frequency));
 return jsonb_build_object('id',v_id,'code',p_code,'saved',true);
end;
$$;

-- Owner can see every campus. For non-Owner staff, a current confirmed
-- campus role and an explicit Owner-issued fee permission are mandatory.
-- Only four roles are eligible; a grant on any other role cannot elevate it.
create or replace function app_private.sms_fee_role_authorized(
 p_school uuid,p_campus uuid,p_action text)
returns boolean language sql stable security definer set search_path=''
as $$
 select p_action in ('fees.read','fees.update')
   and exists(select 1 from public.campuses c join public.schools s
     on s.id=c.school_id
     where c.id=p_campus and c.school_id=p_school
       and c.is_active and s.status='active')
   and (
     app_private.is_verified_school_owner((select auth.uid()),p_school)
     or (
       exists(select 1 from public.user_roles r
         where r.user_id=(select auth.uid()) and r.school_id=p_school
           and r.campus_id=p_campus and r.is_active
           and r.role in ('principal','admin','accountant'))
       and app_private.sms_permission_allowed(p_school,p_campus,p_action)
     )
   );
$$;

create or replace function app_private.sms_fee_payment_workspace(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
 v_year uuid;v_year_label text;v_currency text;
 v_students jsonb;v_categories jsonb;v_years jsonb;
begin
 if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.read')
 then raise exception 'Fee viewing permission required for this campus'
   using errcode='42501';end if;

 if p_year is null then
  select y.id,y.label into v_year,v_year_label
  from public.academic_years y where y.school_id=p_school and y.is_active
  order by y.starts_on desc limit 1;
 else
  select y.id,y.label into v_year,v_year_label
  from public.academic_years y
  where y.id=p_year and y.school_id=p_school;
 end if;
 if v_year is null then
  raise exception 'Academic year not found for school' using errcode='22023';
 end if;
 select s.currency_code into v_currency from public.schools s
   where s.id=p_school;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',y.id,'label',y.label,'active',y.is_active)
   order by y.starts_on desc),'[]'::jsonb)
 into v_years from public.academic_years y where y.school_id=p_school;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',fc.id,'code',fc.code,'name',fc.name,
   'frequency',fc.charge_frequency,'active',fc.is_active)
   order by fc.charge_frequency,fc.name),'[]'::jsonb)
 into v_categories from public.fee_categories fc
 where fc.school_id=p_school and (
   fc.is_active or exists(select 1 from public.fee_charges ch
     where ch.category_id=fc.id and ch.school_id=p_school
       and ch.campus_id=p_campus and ch.academic_year_id=v_year));

 select coalesce(jsonb_agg(jsonb_build_object(
   'student_id',s.id,'name',s.full_name_en,
   'registration',s.registration_no,'enrollment_id',e.id,
   'class_id',cl.id,'class_name',cl.name,
   'section_id',sec.id,'section_name',sec.name,
   'charges',coalesce((
      select jsonb_agg(jsonb_build_object(
        'charge_id',ch.id,'category_id',ch.category_id,
        'category',fc.name,'frequency',fc.charge_frequency,
        'month',ch.billing_month,'due_on',ch.due_on,
        'net_minor',ch.net_minor,
        'paid_minor',coalesce((
          select sum(a.amount_minor) from public.fee_allocations a
          where a.charge_id=ch.id),0),
        'outstanding_minor',ch.net_minor-coalesce((
          select sum(a.amount_minor) from public.fee_allocations a
          where a.charge_id=ch.id),0))
        order by ch.due_on,ch.billing_month,fc.code,ch.id)
      from public.fee_charges ch
      join public.fee_categories fc on fc.id=ch.category_id
      where ch.school_id=p_school and ch.campus_id=p_campus
        and ch.academic_year_id=v_year and ch.enrollment_id=e.id
   ),'[]'::jsonb)
   ) order by cl.sort_order,sec.name,s.full_name_en,e.id),'[]'::jsonb)
 into v_students
 from public.student_enrollments e
 join public.students s on s.id=e.student_id and s.school_id=e.school_id
 join public.classes cl on cl.id=e.class_id
    and cl.campus_id=e.campus_id and cl.academic_year_id=e.academic_year_id
 left join public.sections sec on sec.id=e.section_id and sec.class_id=cl.id
 where e.school_id=p_school and e.campus_id=p_campus
   and e.academic_year_id=v_year;

 return jsonb_build_object(
  'school_id',p_school,'campus_id',p_campus,
  'year_id',v_year,'year_label',v_year_label,'years',v_years,
  'currency',v_currency,'students',v_students,'categories',v_categories,
  'can_collect',app_private.sms_fee_role_authorized(
       p_school,p_campus,'fees.update'));
end;
$$;

-- Only posted bills can be paid. Allocation lines (one per charge) are
-- reviewed and submitted by the operator; the database verifies them
-- atomically under the same campus lock used by the old Owner collector.
create or replace function app_private.sms_fee_quick_pay_post(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,
 p_amount_minor bigint,p_method text,p_bank_reference text,
 p_lines jsonb,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_actor uuid:=(select auth.uid());v_bank text;
 v_payload jsonb;v_hash bytea;v_old record;
 v_serial bigint;v_number text;v_receipt uuid;
 v_line jsonb;v_charge uuid;v_minor bigint;v_total bigint:=0;
 v_invoice record;v_owed bigint;v_result jsonb;
 v_allocations jsonb:='[]'::jsonb;
begin
 if not app_private.sms_fee_role_authorized(
    p_school,p_campus,'fees.update')
 then raise exception 'Fee collection permission required for this campus'
 using errcode='42501';end if;
 v_bank:=nullif(btrim(coalesce(p_bank_reference,'')),'');
 if p_school is null or p_student is null or p_year is null
   or p_operation is null or p_amount_minor is null
   or p_amount_minor<=0 or p_amount_minor>100000000000
   or p_method not in ('cash','bank')
   or (p_method='bank' and length(coalesce(v_bank,''))<3)
   or p_lines is null or jsonb_typeof(p_lines)<>'array'
   or jsonb_array_length(p_lines) not between 1 and 200
 then raise exception 'Invalid Quick Pay request' using errcode='22023';end if;
 if p_method='cash' then v_bank:=null;end if;

 if not exists(select 1 from public.student_enrollments e
    where e.student_id=p_student and e.school_id=p_school
      and e.campus_id=p_campus and e.academic_year_id=p_year)
 then raise exception 'Student outside selected campus and academic year'
 using errcode='42501';end if;
 perform 1 from public.campuses c
   where c.id=p_campus and c.school_id=p_school and c.is_active
   for update;
 if not found then raise exception 'Inactive campus' using errcode='42501';end if;

 v_payload:=jsonb_build_object(
   'school',p_school,'campus',p_campus,'year',p_year,'student',p_student,
   'amount',p_amount_minor,'method',p_method,'reference',v_bank,
   'lines',p_lines);
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_payload::text,'UTF8'));
 select op.request_sha256,op.result_json,op.action,op.actor_id into v_old
 from public.fee_operation_receipts op
 where op.school_id=p_school and op.operation_id=p_operation;
 if found then
  if v_old.action<>'post_receipt' or v_old.request_sha256<>v_hash
    or v_old.actor_id<>v_actor then
   raise exception 'Operation ID already used with different details'
   using errcode='22023';
  end if;
  return v_old.result_json;
 end if;

 if exists(
  select 1 from jsonb_array_elements(p_lines) line
  where jsonb_typeof(line)<>'object'
    or jsonb_typeof(line->'charge_id')<>'string'
    or jsonb_typeof(line->'amount_minor') not in ('number','string'))
 then raise exception 'Invalid allocation format' using errcode='22023';end if;
 if exists(
  select 1 from jsonb_array_elements(p_lines) line
  group by line->>'charge_id' having count(*)>1)
 then raise exception 'Duplicate charge allocations' using errcode='22023';end if;

 -- Validate every line against the locked outstanding charge before
 -- posting anything. Any error causes the complete transaction to roll back.
 for v_line in select value from jsonb_array_elements(p_lines) as x(value) loop
  begin
   v_charge:=(v_line->>'charge_id')::uuid;
   v_minor:=(v_line->>'amount_minor')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
   raise exception 'Invalid allocation ID or amount' using errcode='22023';
  end;
  if v_minor is null or v_minor<=0 or v_minor>p_amount_minor then
   raise exception 'Allocation must be positive and within payment'
    using errcode='22023';end if;
  select c.id,c.net_minor into v_invoice
   from public.fee_charges c
   where c.id=v_charge and c.school_id=p_school and c.campus_id=p_campus
     and c.academic_year_id=p_year and c.student_id=p_student
   for update;
  if not found then raise exception 'Charge not owned by selected student'
    using errcode='42501';end if;
  select v_invoice.net_minor-coalesce(sum(a.amount_minor),0)
   into v_owed from public.fee_allocations a
   where a.charge_id=v_charge;
  if v_minor>v_owed then
   raise exception 'Outstanding balance changed for charge %',v_charge
   using errcode='22023';end if;
  v_total:=v_total+v_minor;
  if v_total>p_amount_minor then
   raise exception 'Allocations exceed total received' using errcode='22023';
  end if;
 end loop;
 if v_total<>p_amount_minor then
  raise exception 'Allocations must equal amount received'
   using errcode='22023';end if;

 insert into public.fee_receipt_counters(school_id,next_serial)
 values(p_school,2)
 on conflict(school_id) do update
   set next_serial=public.fee_receipt_counters.next_serial+1
 returning next_serial-1 into v_serial;
 v_number:='SMS-'||lpad(v_serial::text,9,'0');
 insert into public.fee_receipts(
   school_id,collection_campus_id,student_id,receipt_no,
   operation_id,amount_minor,payment_method,bank_reference,issued_by)
 values(p_school,p_campus,p_student,v_number,p_operation,
   p_amount_minor,p_method,v_bank,v_actor)
 returning id into v_receipt;

 for v_line in select value from jsonb_array_elements(p_lines) as x(value) loop
  insert into public.fee_allocations(
    school_id,student_id,receipt_id,charge_id,amount_minor)
  values(p_school,p_student,v_receipt,
    (v_line->>'charge_id')::uuid,
    (v_line->>'amount_minor')::bigint);
 end loop;
 v_result:=jsonb_build_object('saved',true,'receipt_id',v_receipt,
   'receipt_no',v_number,'amount_minor',p_amount_minor,
   'allocations',p_lines);
 insert into public.fee_operation_receipts(
  school_id,operation_id,action,actor_id,request_sha256,result_json)
 values(p_school,p_operation,'post_receipt',v_actor,v_hash,v_result);
 return v_result;
end;
$$;

create or replace function public.fee_payment_workspace(
 p_school uuid,p_campus uuid,p_year uuid default null)
returns jsonb language sql stable security invoker set search_path=''
as $$select app_private.sms_fee_payment_workspace(p_school,p_campus,p_year);$$;

create or replace function public.fee_quick_pay_post(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid,
 p_amount_minor bigint,p_method text,p_bank_reference text,
 p_lines jsonb,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $$select app_private.sms_fee_quick_pay_post(
  p_school,p_campus,p_year,p_student,p_amount_minor,p_method,
  p_bank_reference,p_lines,p_operation);$$;

revoke all on function
 app_private.sms_fee_role_authorized(uuid,uuid,text),
 app_private.sms_fee_payment_workspace(uuid,uuid,uuid),
 app_private.sms_fee_quick_pay_post(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid),
 public.fee_payment_workspace(uuid,uuid,uuid),
 public.fee_quick_pay_post(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid)
from public,anon,authenticated;

grant execute on function
 app_private.sms_fee_payment_workspace(uuid,uuid,uuid),
 app_private.sms_fee_quick_pay_post(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid),
 public.fee_payment_workspace(uuid,uuid,uuid),
 public.fee_quick_pay_post(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,uuid)
to authenticated;

-- Required for private definer -> helper function resolution under PostgREST
grant execute on function app_private.sms_fee_role_authorized(uuid,uuid,text)
to authenticated;

update app_private.sms_permission_catalog
set is_implemented=true
where code in ('fees.read','fees.update');
