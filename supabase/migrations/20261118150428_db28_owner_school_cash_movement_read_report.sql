-- DB28: School-wide posted cash movement preview, Owner-only and read-only.
-- Reuses DB27 fee allocations; excludes retail cancellations rather than
-- asserting their reversals are cash refunds; excludes pending expense requests.
create or replace function app_private.sms_school_cashflow_report(
 p_school uuid,p_campus uuid,p_year uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
 v_owner uuid:=(select auth.uid());
 v_year public.academic_years%rowtype;
 v_tz text;v_currency text;v_fee jsonb;v_entries jsonb;
 v_summary jsonb;v_daily jsonb;v_reversed_minor bigint;
 v_reversed_count bigint;v_pending integer;v_stock_cost bigint;
begin
 if not app_private.is_verified_school_owner(v_owner,p_school)
 then raise exception 'Verified School Owner required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>92
 then raise exception 'Choose a valid period up to 93 days' using errcode='22023';end if;
 select * into v_year from public.academic_years y
 where y.id=p_year and y.school_id=p_school;
 if v_year.id is null or p_from<v_year.starts_on or p_to>v_year.ends_on
 then raise exception 'Period outside school academic year' using errcode='22023';end if;
 if p_campus is not null and not exists(select 1 from public.campuses c
   where c.id=p_campus and c.school_id=p_school and c.is_active)
 then raise exception 'Invalid school campus' using errcode='42501';end if;
 select timezone_name,currency_code into v_tz,v_currency
 from public.schools where id=p_school and status='active';
 if v_tz is null then raise exception 'School not active' using errcode='42501';end if;
 v_fee:=app_private.sms_fee_collection_cashbook(
   p_school,p_campus,p_year,p_from,p_to,'all','all',null,null);

 with movement as materialized (
  select f->>'source' source,'fee'::text kind,
   f->>'receipt_no' reference,f->>'payer_name' counterparty,
   f->>'category' category,(f->>'date')::date movement_day,
   f->>'method' method,(f->>'amount_minor')::bigint signed_minor
  from jsonb_array_elements(v_fee->'entries') f
  union all
  select 'canteen','retail',s.sale_no,'Canteen','Canteen',
    (s.sold_at at time zone v_tz)::date,s.payment_method,s.total_minor
  from public.canteen_sales s
  where s.school_id=p_school and (p_campus is null or s.campus_id=p_campus)
    and (s.sold_at at time zone v_tz)::date between p_from and p_to
    and not exists(select 1 from public.retail_sale_reversals rv
      where rv.canteen_sale_id=s.id and rv.school_id=s.school_id)
  union all
  select 'uniform','retail',s.sale_no,'Uniform','Uniform',
    (s.sold_at at time zone v_tz)::date,s.payment_method,s.total_minor
  from public.uniform_sales s
  where s.school_id=p_school and (p_campus is null or s.campus_id=p_campus)
    and (s.sold_at at time zone v_tz)::date between p_from and p_to
    and not exists(select 1 from public.retail_sale_reversals rv
      where rv.uniform_sale_id=s.id and rv.school_id=s.school_id)
  union all
  select 'expense','outflow',ex.id::text,
    coalesce(ex.vendor_name,'Paid expense'),cat.name,ex.paid_on,
    acct.account_kind,-ex.amount_minor
  from public.expenses ex
  join public.expense_requests req on req.id=ex.request_id
    and req.school_id=ex.school_id and req.campus_id=ex.campus_id
    and req.status='approved'
  join public.expense_categories cat on cat.id=ex.category_id
    and cat.school_id=ex.school_id
  join public.financial_accounts acct on acct.id=ex.financial_account_id
    and acct.school_id=ex.school_id and acct.campus_id=ex.campus_id
  where ex.school_id=p_school and (p_campus is null or ex.campus_id=p_campus)
    and ex.paid_on between p_from and p_to
  union all
  select 'salary','outflow',pay.id::text,'Staff salary','Salary',
    (pay.paid_at at time zone v_tz)::date,pay.method,-pay.amount_minor
  from public.salary_payments pay
  where pay.school_id=p_school and (p_campus is null or pay.campus_id=p_campus)
    and (pay.paid_at at time zone v_tz)::date between p_from and p_to
    and not exists(select 1 from public.salary_payment_reversals rv
      where rv.payment_id=pay.id and rv.school_id=pay.school_id)
  union all
  select 'fee_refund','outflow',rv.id::text,'Student fee refund','Fee refund',
    (rv.reversed_at at time zone v_tz)::date,
    r.payment_method,-r.amount_minor
  from public.fee_receipt_reversals rv
  join public.fee_receipts r on r.id=rv.receipt_id
    and r.school_id=rv.school_id
  where rv.school_id=p_school and
    (p_campus is null or r.collection_campus_id=p_campus)
    and (rv.reversed_at at time zone v_tz)::date between p_from and p_to
    and exists(select 1 from public.fee_allocations a
      join public.fee_charges ch on ch.id=a.charge_id
      where a.receipt_id=r.id and ch.academic_year_id=p_year)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'date',movement_day,'source',source,'kind',kind,'reference',reference,
   'counterparty',counterparty,'category',category,'method',method,
   'signed_minor',signed_minor)
    order by movement_day desc,source,reference,category),'[]'::jsonb)
 into v_entries from movement;
 if jsonb_array_length(v_entries)>5000 then
   raise exception 'Too many transactions; narrow range' using errcode='54000';end if;
 with rows as (
  select (x->>'signed_minor')::bigint amount_minor,
    x->>'source' source,x->>'method' method
  from jsonb_array_elements(v_entries) x
 )
 select jsonb_build_object(
  'inflow_minor',coalesce(sum(amount_minor) filter(where amount_minor>0),0),
  'outflow_minor',coalesce(-sum(amount_minor) filter(where amount_minor<0),0),
  'net_movement_minor',coalesce(sum(amount_minor),0),
  'student_fee_minor',coalesce(sum(amount_minor) filter(where source='student'),0),
  'other_fee_minor',coalesce(sum(amount_minor) filter(where source='other'),0),
  'canteen_minor',coalesce(sum(amount_minor) filter(where source='canteen'),0),
  'uniform_minor',coalesce(sum(amount_minor) filter(where source='uniform'),0),
  'expense_minor',coalesce(-sum(amount_minor) filter(where source='expense'),0),
  'salary_minor',coalesce(-sum(amount_minor) filter(where source='salary'),0),
  'fee_refund_minor',coalesce(-sum(amount_minor) filter(where source='fee_refund'),0),
  'cash_in_minor',coalesce(sum(amount_minor) filter(
    where method='cash' and amount_minor>0),0),
  'bank_in_minor',coalesce(sum(amount_minor) filter(
    where method='bank' and amount_minor>0),0),
  'cash_out_minor',coalesce(-sum(amount_minor) filter(
    where method='cash' and amount_minor<0),0),
  'bank_out_minor',coalesce(-sum(amount_minor) filter(
    where method='bank' and amount_minor<0),0),
  'transaction_lines',count(*)
 ) into v_summary from rows;
 with rows as (
  select (x->>'date')::date posting_date,
    (x->>'signed_minor')::bigint amount_minor
  from jsonb_array_elements(v_entries) x
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'date',posting_date,'inflow_minor',inflow_minor,
   'outflow_minor',outflow_minor,'net_minor',net_minor)
   order by posting_date desc),'[]'::jsonb)
 into v_daily from (
  select posting_date,
    coalesce(sum(amount_minor) filter(where amount_minor>0),0) inflow_minor,
    coalesce(-sum(amount_minor) filter(where amount_minor<0),0) outflow_minor,
    sum(amount_minor) net_minor
  from rows group by posting_date
 ) summary_days;

 select coalesce(sum(x.amount_minor),0),count(*)
 into v_reversed_minor,v_reversed_count
 from (
  select s.total_minor amount_minor from public.retail_sale_reversals rv
  join public.canteen_sales s on s.id=rv.canteen_sale_id
  where rv.school_id=p_school and rv.sale_kind='canteen'
    and (p_campus is null or rv.campus_id=p_campus)
    and (s.sold_at at time zone v_tz)::date between p_from and p_to
  union all
  select s.total_minor from public.retail_sale_reversals rv
  join public.uniform_sales s on s.id=rv.uniform_sale_id
  where rv.school_id=p_school and rv.sale_kind='uniform'
    and (p_campus is null or rv.campus_id=p_campus)
    and (s.sold_at at time zone v_tz)::date between p_from and p_to
 ) x;
 select count(*) into v_pending from public.expense_requests e
 where e.school_id=p_school and (p_campus is null or e.campus_id=p_campus)
 and e.status='pending' and e.expense_date between p_from and p_to;
 -- Identifiable direct stock depletion only: this is a NON-CASH cost
 -- indicator, not a complete audited cost of goods sold.
 select coalesce(sum(round(-mv.delta_qty * mv.unit_cost_minor)::bigint),0)
 into v_stock_cost
 from public.inventory_stock_movements mv
 join public.inventory_movement_sources src
   on src.movement_id=mv.id and src.school_id=mv.school_id
     and src.campus_id=mv.campus_id
 where mv.school_id=p_school and (p_campus is null or mv.campus_id=p_campus)
   and (mv.occurred_at at time zone v_tz)::date between p_from and p_to
   and ((mv.movement_kind='canteen_sale' and
       exists(select 1 from public.canteen_sale_lines ln
         join public.canteen_sales s on s.id=ln.sale_id
         where ln.id=src.canteen_sale_line_id and s.school_id=mv.school_id
           and not exists(select 1 from public.retail_sale_reversals rv
             where rv.canteen_sale_id=s.id)))
     or (mv.movement_kind='uniform_sale' and
       exists(select 1 from public.uniform_sale_lines ln
         join public.uniform_sales s on s.id=ln.sale_id
         where ln.id=src.uniform_sale_line_id and s.school_id=mv.school_id
           and not exists(select 1 from public.retail_sale_reversals rv
             where rv.uniform_sale_id=s.id))));
 return jsonb_build_object(
   'school_id',p_school,'campus_id',p_campus,'year_id',p_year,
   'from',p_from,'to',p_to,'currency',v_currency,'timezone',v_tz,
   'summary',v_summary,'entries',v_entries,'daily',v_daily,
   'cancelled_retail_minor',v_reversed_minor,
   'cancelled_retail_count',v_reversed_count,
   'direct_stock_cost_minor',v_stock_cost,
   'pending_expense_requests',v_pending,
   'unbalanced_fee_receipts',v_fee->'unbalanced_receipts',
   'scope_note','Posted fee receipts plus unreversed retail sales less approved paid expenses, salary payments and fee refunds. Not audited bank balances, recognized profit or full general ledger. Retail cancellations excluded; cash refunds unverified. Transfers, deposits, capital movements excluded.',
   'campus_options',coalesce((select jsonb_agg(
     jsonb_build_object('id',c.id,'name',c.name) order by c.name)
     from public.campuses c where c.school_id=p_school and c.is_active),
    '[]'::jsonb),
   'year_options',coalesce((select jsonb_agg(jsonb_build_object(
     'id',y.id,'label',y.label,'starts_on',y.starts_on,'ends_on',y.ends_on)
     order by y.starts_on desc) from public.academic_years y
     where y.school_id=p_school),'[]'::jsonb)
 );
end;
$fn$;
create or replace function public.school_cashflow_report(
 p_school uuid,p_campus uuid,p_year uuid,p_from date,p_to date)
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.sms_school_cashflow_report(
  p_school,p_campus,p_year,p_from,p_to);
$fn$;
revoke all on function
 app_private.sms_school_cashflow_report(uuid,uuid,uuid,date,date),
 public.school_cashflow_report(uuid,uuid,uuid,date,date)
 from public,anon,authenticated;
grant execute on function
 app_private.sms_school_cashflow_report(uuid,uuid,uuid,date,date),
 public.school_cashflow_report(uuid,uuid,uuid,date,date)
 to authenticated;
