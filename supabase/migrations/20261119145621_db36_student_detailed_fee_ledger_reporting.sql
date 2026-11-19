-- DB36: read-only student fee statement: every posted charge, exact
-- allocated receipts, grouped billing months/categories and school-year totals.
-- No mutation of posted charges, receipts, discounts or allocations.
create or replace function app_private.sms_fee_student_detailed_ledger(
  p_school uuid,p_campus uuid,p_year uuid,p_student uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
 v_school public.schools%rowtype;
 v_year public.academic_years%rowtype;
 v_student public.students%rowtype;
 v_class text;v_section text;v_registration text;
 v_charges jsonb;v_categories jsonb;v_months jsonb;
 v_receipts jsonb;v_allocations jsonb;v_totals jsonb;
begin
 if (select auth.uid()) is null
   or not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.read')
 then raise exception 'Fee ledger permission denied for this campus'
   using errcode='42501';end if;
 select * into v_school from public.schools s
 where s.id=p_school and s.status='active';
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school;
 select * into v_student from public.students s
 where s.id=p_student and s.school_id=p_school;
 if v_school.id is null or v_year.id is null or v_student.id is null
 then raise exception 'Student school/year not found' using errcode='42501';end if;
 select cl.name,sec.name into v_class,v_section
 from public.student_enrollments e
 join public.classes cl on cl.id=e.class_id
 left join public.sections sec on sec.id=e.section_id
 where e.school_id=p_school and e.campus_id=p_campus
   and e.academic_year_id=p_year and e.student_id=p_student
 order by e.admitted_on desc,e.id desc limit 1;
 if not found then raise exception 'Student enrollment outside selected campus/year'
 using errcode='42501';end if;

 select coalesce(jsonb_agg(jsonb_build_object(
   'id',c.id,'category_id',c.category_id,'category',fc.name,
   'frequency',fc.charge_frequency,'month',c.billing_month,
   'due_on',c.due_on,'source_kind',c.source_kind,
   'description',coalesce(c.description,''),
   'posted_at',c.posted_at,'gross_minor',c.gross_minor,
   'discount_minor',c.discount_minor,'net_minor',c.net_minor,
   'paid_minor',coalesce(a.paid_minor,0),
   'outstanding_minor',c.net_minor-coalesce(a.paid_minor,0))
   order by c.billing_month,c.due_on,c.posted_at,c.id),'[]'::jsonb)
 into v_charges
 from public.fee_charges c
 join public.fee_categories fc on fc.id=c.category_id and fc.school_id=c.school_id
 left join lateral (
   select coalesce(sum(a.amount_minor),0)::bigint paid_minor
   from public.fee_allocations a where a.charge_id=c.id
     and a.school_id=p_school and a.student_id=p_student
 ) a on true
 where c.school_id=p_school and c.campus_id=p_campus
   and c.academic_year_id=p_year and c.student_id=p_student;

 with line as (
   select c.category_id,fc.name,fc.charge_frequency,c.net_minor,c.gross_minor,
    c.discount_minor,coalesce(a.paid,0)::bigint paid
   from public.fee_charges c
   join public.fee_categories fc on fc.id=c.category_id
   left join lateral (
     select sum(a.amount_minor)::bigint paid from public.fee_allocations a
     where a.charge_id=c.id and a.school_id=p_school and a.student_id=p_student
   ) a on true
   where c.school_id=p_school and c.campus_id=p_campus
    and c.academic_year_id=p_year and c.student_id=p_student
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'category_id',x.category_id,'category',x.name,'frequency',x.charge_frequency,
  'charge_count',x.charge_count,'gross_minor',x.gross_minor,
  'discount_minor',x.discount_minor,'net_minor',x.net_minor,
  'paid_minor',x.paid_minor,'outstanding_minor',x.net_minor-x.paid_minor)
  order by x.name,x.category_id),'[]'::jsonb) into v_categories
 from (select category_id,name,charge_frequency,count(*)::integer charge_count,
    sum(gross_minor)::bigint gross_minor,
    sum(discount_minor)::bigint discount_minor,
    sum(net_minor)::bigint net_minor,sum(paid)::bigint paid_minor
    from line group by category_id,name,charge_frequency) x;

 with line as (
   select c.billing_month,c.net_minor,c.gross_minor,c.discount_minor,
     coalesce(a.paid,0)::bigint paid
   from public.fee_charges c
   left join lateral (
     select sum(a.amount_minor)::bigint paid from public.fee_allocations a
     where a.charge_id=c.id and a.school_id=p_school and a.student_id=p_student
   ) a on true
   where c.school_id=p_school and c.campus_id=p_campus
    and c.academic_year_id=p_year and c.student_id=p_student
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'month',x.billing_month,'charge_count',x.charge_count,
  'gross_minor',x.gross_minor,'discount_minor',x.discount_minor,
  'net_minor',x.net_minor,'paid_minor',x.paid_minor,
  'outstanding_minor',x.net_minor-x.paid_minor)
   order by x.billing_month),'[]'::jsonb) into v_months
 from (select billing_month,count(*)::integer charge_count,
  sum(gross_minor)::bigint gross_minor,
  sum(discount_minor)::bigint discount_minor,
  sum(net_minor)::bigint net_minor,sum(paid)::bigint paid_minor
  from line group by billing_month) x;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',a.id,'charge_id',c.id,'receipt_id',r.id,
  'receipt_no',r.receipt_no,'receipt_total_minor',r.amount_minor,
  'category_id',c.category_id,'category',fc.name,
  'month',c.billing_month,'amount_minor',a.amount_minor,
  'payment_method',r.payment_method,
  'issued_at',r.issued_at,'allocated_at',a.allocated_at)
  order by r.issued_at,a.allocated_at,a.id),'[]'::jsonb) into v_allocations
 from public.fee_allocations a
 join public.fee_charges c on c.id=a.charge_id
   and c.school_id=a.school_id and c.student_id=a.student_id
 join public.fee_receipts r on r.id=a.receipt_id
   and r.school_id=a.school_id and r.student_id=a.student_id
 join public.fee_categories fc on fc.id=c.category_id
 where c.school_id=p_school and c.campus_id=p_campus
  and c.academic_year_id=p_year and c.student_id=p_student;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',x.id,'number',x.receipt_no,
  'receipt_total_minor',x.amount_minor,
  'allocated_to_year_minor',x.allocated_to_year_minor,
  'method',x.payment_method,'bank_reference',x.bank_reference,
  'issued_at',x.issued_at)
  order by x.issued_at desc,x.id desc),'[]'::jsonb) into v_receipts
 from (
   select r.id,r.receipt_no,r.amount_minor,r.payment_method,
    r.bank_reference,r.issued_at,
    sum(a.amount_minor)::bigint allocated_to_year_minor
   from public.fee_receipts r
   join public.fee_allocations a on a.receipt_id=r.id
      and a.school_id=r.school_id and a.student_id=r.student_id
   join public.fee_charges c on c.id=a.charge_id
      and c.school_id=a.school_id and c.student_id=a.student_id
   where c.school_id=p_school and c.campus_id=p_campus
     and c.academic_year_id=p_year and c.student_id=p_student
   group by r.id,r.receipt_no,r.amount_minor,r.payment_method,
     r.bank_reference,r.issued_at
 ) x;

 select jsonb_build_object(
   'charge_count',count(c.id),
   'gross_minor',coalesce(sum(c.gross_minor),0)::bigint,
   'discount_minor',coalesce(sum(c.discount_minor),0)::bigint,
   'net_minor',coalesce(sum(c.net_minor),0)::bigint,
   'paid_minor',coalesce(sum(coalesce(a.paid,0)),0)::bigint,
   'outstanding_minor',
     coalesce(sum(c.net_minor-coalesce(a.paid,0)),0)::bigint,
   'receipt_count',jsonb_array_length(v_receipts)
 ) into v_totals
 from public.fee_charges c
 left join lateral (
   select sum(a.amount_minor)::bigint paid from public.fee_allocations a
    where a.charge_id=c.id and a.school_id=p_school and a.student_id=p_student
 ) a on true
 where c.school_id=p_school and c.campus_id=p_campus
 and c.academic_year_id=p_year and c.student_id=p_student;

 return jsonb_build_object(
  'school_id',p_school,'campus_id',p_campus,'year_id',p_year,
  'school_name',v_school.name,'year_label',v_year.label,
  'currency',v_school.currency_code,
  'student_id',p_student,'student_name',v_student.full_name_en,
  'registration',v_student.registration_no,
  'class_name',v_class,'section_name',v_section,
  'totals',v_totals,'months',v_months,'categories',v_categories,
  'charges',v_charges,'allocations',v_allocations,'receipts',v_receipts);
end;
$fn$;

create or replace function public.fee_student_detailed_ledger(
 p_school uuid,p_campus uuid,p_year uuid,p_student uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.sms_fee_student_detailed_ledger(
   p_school,p_campus,p_year,p_student);
$fn$;
revoke all on function app_private.sms_fee_student_detailed_ledger(
 uuid,uuid,uuid,uuid),
 public.fee_student_detailed_ledger(uuid,uuid,uuid,uuid)
 from public,anon,authenticated;
grant execute on function app_private.sms_fee_student_detailed_ledger(
 uuid,uuid,uuid,uuid),
 public.fee_student_detailed_ledger(uuid,uuid,uuid,uuid)
 to authenticated;
