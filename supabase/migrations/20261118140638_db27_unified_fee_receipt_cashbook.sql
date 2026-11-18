-- DB27: read-only receipt-based fee collection cashbook.
-- Exact scope: student and non-student fee receipts; no retail/expense/P&L claims.
-- Each cashbook detail row represents a posted allocation, never a gross bill.
create or replace function app_private.sms_fee_collection_cashbook(
 p_school uuid,p_campus uuid,p_year uuid,p_from date,p_to date,
 p_method text,p_source text,p_category uuid,p_class uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
 v_actor uuid:=(select auth.uid());
 v_owner boolean;
 v_tz text;v_currency text;v_result jsonb;v_unbalanced bigint;
begin
 v_owner:=app_private.is_verified_school_owner(v_actor,p_school);
 if p_school is null or p_year is null or p_from is null or p_to is null
   or p_from>p_to or p_to-p_from>92
   or coalesce(p_method,'') not in ('all','cash','bank')
   or coalesce(p_source,'') not in ('all','student','other')
 then raise exception 'Invalid cashbook date range or filters' using errcode='22023';end if;
 if (p_campus is null and not v_owner)
   or (p_campus is not null and
       not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.read'))
 then raise exception 'Fee read permission required for selected campus'
 using errcode='42501';end if;
 if not exists(select 1 from public.academic_years y
   where y.id=p_year and y.school_id=p_school)
 then raise exception 'Academic year outside school' using errcode='22023';end if;
 if p_category is not null and not exists(select 1 from public.fee_categories c
     where c.id=p_category and c.school_id=p_school)
 then raise exception 'Category outside school' using errcode='42501';end if;
 if p_class is not null and not exists(select 1 from public.classes c
    where c.id=p_class and c.school_id=p_school
     and c.academic_year_id=p_year
     and (p_campus is null or c.campus_id=p_campus))
 then raise exception 'Class outside authorized campus/year' using errcode='42501';end if;
 select timezone_name,currency_code into v_tz,v_currency from public.schools
 where id=p_school and status='active';
 if v_tz is null or v_currency is null then
   raise exception 'School unavailable' using errcode='42501';end if;

 with all_lines as materialized (
   select 'student'::text source,r.id receipt_id,r.receipt_no,
     r.collection_campus_id campus_id,
     (r.issued_at at time zone v_tz)::date receipt_day,
     r.issued_at receipt_at,r.payment_method method,
     r.bank_reference,r.issued_by collector_id,
     st.full_name_en payer_name,st.registration_no payer_reference,
     ch.class_id,cl.name class_name,
     fc.id category_id,fc.name category_name,fc.charge_frequency frequency,
     a.amount_minor
   from public.fee_receipts r
   join public.fee_allocations a on a.receipt_id=r.id
     and a.school_id=r.school_id
   join public.fee_charges ch on ch.id=a.charge_id
     and ch.school_id=r.school_id and ch.student_id=r.student_id
   join public.fee_categories fc on fc.id=ch.category_id
   join public.students st on st.id=r.student_id and st.school_id=r.school_id
   left join public.classes cl on cl.id=ch.class_id
   where r.school_id=p_school and ch.academic_year_id=p_year
    and (p_campus is null or r.collection_campus_id=p_campus)
    and (r.issued_at at time zone v_tz)::date between p_from and p_to
   union all
   select 'other'::text,r.id,r.receipt_no,r.campus_id,
     (r.issued_at at time zone v_tz)::date,
     r.issued_at,r.method,r.bank_reference,r.issued_by,
     per.display_name,coalesce(per.contact,''),
     null::uuid,null::text,fc.id,fc.name,fc.charge_frequency,a.amount_minor
   from app_private.sms_fee_other_receipts r
   join app_private.sms_fee_other_allocations a on a.receipt_id=r.id
     and a.school_id=r.school_id and a.campus_id=r.campus_id
     and a.person_id=r.person_id
   join app_private.sms_fee_other_charges ch on ch.id=a.charge_id
     and ch.school_id=r.school_id and ch.campus_id=r.campus_id
     and ch.person_id=r.person_id
     and ch.academic_year_id=r.academic_year_id
   join app_private.sms_fee_other_people per on per.id=r.person_id
     and per.school_id=r.school_id and per.campus_id=r.campus_id
   join public.fee_categories fc on fc.id=ch.category_id
   where r.school_id=p_school and r.academic_year_id=p_year
     and (p_campus is null or r.campus_id=p_campus)
     and (r.issued_at at time zone v_tz)::date between p_from and p_to
 ), lines as materialized (
   select * from all_lines l
   where (p_method='all' or l.method=p_method)
    and (p_source='all' or l.source=p_source)
    and (p_category is null or l.category_id=p_category)
    and (p_class is null or l.class_id=p_class)
 )
 select jsonb_build_object(
  'entries',coalesce((
   select jsonb_agg(jsonb_build_object(
     'source',l.source,'receipt_id',l.receipt_id,
     'receipt_no',l.receipt_no,'campus_id',l.campus_id,
     'date',l.receipt_day,'time',l.receipt_at,
     'method',l.method,'bank_reference',l.bank_reference,
     'collector_id',l.collector_id,
     'payer_name',l.payer_name,'payer_reference',l.payer_reference,
     'class_id',l.class_id,'class_name',l.class_name,
     'category_id',l.category_id,'category',l.category_name,
     'frequency',l.frequency,'amount_minor',l.amount_minor
    ) order by l.receipt_at desc,l.source,l.receipt_no,l.category_name,l.receipt_id)
   from lines l),'[]'::jsonb),
  'summary',(select jsonb_build_object(
    'amount_minor',coalesce(sum(l.amount_minor),0),
    'cash_minor',coalesce(sum(l.amount_minor) filter(where l.method='cash'),0),
    'bank_minor',coalesce(sum(l.amount_minor) filter(where l.method='bank'),0),
    'student_minor',coalesce(sum(l.amount_minor) filter(where l.source='student'),0),
    'other_minor',coalesce(sum(l.amount_minor) filter(where l.source='other'),0),
    'receipt_count',count(distinct (l.source,l.receipt_id)),
    'allocation_lines',count(*)
   ) from lines l),
  'daily',coalesce((
   select jsonb_agg(jsonb_build_object(
     'date',x.receipt_day,'amount_minor',x.total,
     'student_minor',x.student_total,'other_minor',x.other_total,
     'cash_minor',x.cash_total,'bank_minor',x.bank_total)
      order by x.receipt_day desc)
   from (
     select l.receipt_day,sum(l.amount_minor) total,
      coalesce(sum(l.amount_minor) filter(where l.source='student'),0) student_total,
      coalesce(sum(l.amount_minor) filter(where l.source='other'),0) other_total,
      coalesce(sum(l.amount_minor) filter(where l.method='cash'),0) cash_total,
      coalesce(sum(l.amount_minor) filter(where l.method='bank'),0) bank_total
     from lines l group by l.receipt_day
   ) x),'[]'::jsonb),
  'category_totals',coalesce((
   select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,
     'frequency',x.frequency,'amount_minor',x.total) order by x.name)
   from (
     select l.category_id id,l.category_name name,l.frequency,
       sum(l.amount_minor) total
     from lines l group by l.category_id,l.category_name,l.frequency
   ) x),'[]'::jsonb)
 ) into v_result;
 if (v_result->'summary'->>'allocation_lines')::integer>5000 then
   raise exception 'Too many cashbook allocation lines; shorten date range'
   using errcode='54000';end if;

 select count(*) into v_unbalanced from (
   select r.id from public.fee_receipts r
   where r.school_id=p_school
     and (p_campus is null or r.collection_campus_id=p_campus)
     and (r.issued_at at time zone v_tz)::date between p_from and p_to
     and coalesce((select sum(a.amount_minor)
       from public.fee_allocations a where a.receipt_id=r.id),0)<>r.amount_minor
   union all
   select r.id from app_private.sms_fee_other_receipts r
   where r.school_id=p_school
     and (p_campus is null or r.campus_id=p_campus)
     and (r.issued_at at time zone v_tz)::date between p_from and p_to
     and coalesce((select sum(a.amount_minor)
       from app_private.sms_fee_other_allocations a
       where a.receipt_id=r.id),0)<>r.amount_minor
 ) mismatches;
 return v_result||jsonb_build_object(
  'school_id',p_school,'campus_id',p_campus,'year_id',p_year,
  'timezone',v_tz,'currency',v_currency,
  'from',p_from,'to',p_to,'method',p_method,'source',p_source,
  'category_filter',p_category,'class_filter',p_class,
  'year_options',coalesce((select jsonb_agg(jsonb_build_object(
     'id',y.id,'label',y.label) order by y.starts_on desc)
     from public.academic_years y where y.school_id=p_school),'[]'::jsonb),
  'campus_options',coalesce((select jsonb_agg(jsonb_build_object(
     'id',c.id,'name',c.name) order by c.name)
     from public.campuses c where c.school_id=p_school and c.is_active
      and (v_owner or c.id=p_campus)),'[]'::jsonb),
  'category_options',coalesce((select jsonb_agg(jsonb_build_object(
     'id',c.id,'name',c.name) order by c.name)
     from public.fee_categories c where c.school_id=p_school),'[]'::jsonb),
  'class_options',coalesce((select jsonb_agg(jsonb_build_object(
     'id',cl.id,'name',cl.name,'campus_id',cl.campus_id) order by cl.name)
     from public.classes cl where cl.school_id=p_school
       and cl.academic_year_id=p_year
       and (p_campus is null or cl.campus_id=p_campus)),'[]'::jsonb),
  'unbalanced_receipts',v_unbalanced,
  'scope_note','Posted student fee and non-student fee allocations only; not full general ledger, retail income or net profit.');
end;
$fn$;

create or replace function public.fee_collection_cashbook(
 p_school uuid,p_campus uuid,p_year uuid,p_from date,p_to date,
 p_method text default 'all',p_source text default 'all',
 p_category uuid default null,p_class uuid default null)
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.sms_fee_collection_cashbook(
 p_school,p_campus,p_year,p_from,p_to,p_method,p_source,p_category,p_class);
$fn$;

revoke all on function
 app_private.sms_fee_collection_cashbook(uuid,uuid,uuid,date,date,text,text,uuid,uuid),
 public.fee_collection_cashbook(uuid,uuid,uuid,date,date,text,text,uuid,uuid)
 from public,anon,authenticated;
grant execute on function
 app_private.sms_fee_collection_cashbook(uuid,uuid,uuid,date,date,text,text,uuid,uuid),
 public.fee_collection_cashbook(uuid,uuid,uuid,date,date,text,text,uuid,uuid)
 to authenticated;
