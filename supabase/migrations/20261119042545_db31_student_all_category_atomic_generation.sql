-- DB31. Live applied version 20261119042545. Batch fee generation is atomic
-- and retries reuse derived per-category operation UUIDs. Never posts cash.
CREATE OR REPLACE FUNCTION app_private.sms_fee_generate_categories(p_school uuid, p_campus uuid, p_year uuid, p_month date, p_categories uuid[], p_scope text, p_target uuid, p_include_optional boolean, p_operation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_ids uuid[];
  v_count integer;
  v_previous record;
  v_request jsonb;
  v_hash bytea;
  v_category record;
  v_line jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_added integer := 0;
  v_skipped integer := 0;
  v_eligible integer := 0;
  v_result jsonb;
begin
  if not app_private.sms_fee_role_authorized(p_school,p_campus,'fees.update')
  then raise exception 'Authorized Fee Manager required'
    using errcode='42501'; end if;

  if p_operation is null or p_school is null or p_campus is null
    or p_year is null or p_month is null
    or p_scope is null or p_scope not in ('campus','class','student')
    or (p_scope='campus' and p_target is not null)
    or (p_scope<>'campus' and p_target is null)
    or p_categories is null or cardinality(p_categories) not between 1 and 40
  then raise exception 'Invalid batch billing request'
    using errcode='22023'; end if;

  select array_agg(x.category_id order by x.category_id) into v_ids
  from (select distinct u.category_id from unnest(p_categories) as u(category_id)) x;
  if cardinality(v_ids) <> cardinality(p_categories)
    or array_position(v_ids,null) is not null
  then raise exception 'Duplicate or null category in batch'
    using errcode='22023';end if;
  select count(*) into v_count from public.fee_categories c
  where c.school_id=p_school and c.is_active and c.id=any(v_ids);
  if v_count <> cardinality(v_ids)
  then raise exception 'Category inactive or outside this school'
    using errcode='22023';end if;

  -- Holding this lock for all categories prevents a concurrent writer from
  -- making the batch only partially visible; all inserts commit together.
  perform 1 from public.campuses c
  where c.id=p_campus and c.school_id=p_school and c.is_active
  for update;
  if not found then raise exception 'Campus inactive' using errcode='42501';end if;

  v_request:=jsonb_build_object(
    'mode','batch','school',p_school,'campus',p_campus,
    'year',p_year,'month',p_month,'categories',to_jsonb(v_ids),
    'scope',p_scope,'target',p_target,
    'include_optional',coalesce(p_include_optional,false));
  v_hash:=pg_catalog.sha256(pg_catalog.convert_to(v_request::text,'UTF8'));
  select op.action,op.actor_id,op.request_sha256,op.result_json
  into v_previous from public.fee_operation_receipts op
  where op.school_id=p_school and op.operation_id=p_operation;
  if found then
    if v_previous.action<>'generate_charges'
      or v_previous.actor_id<>v_actor
      or v_previous.request_sha256<>v_hash
      or v_previous.result_json->>'mode'<>'batch'
    then raise exception 'Batch operation reused with changed details'
      using errcode='22023';end if;
    return v_previous.result_json;
  end if;

  for v_category in
    select c.id,c.code,c.name,c.charge_frequency
    from public.fee_categories c
    where c.school_id=p_school and c.id=any(v_ids)
    order by c.id
  loop
    -- Derived stable operations guarantee replay protection individually,
    -- while the outer PostgreSQL transaction guarantees all-or-nothing.
    v_line:=app_private.sms_fee_generate_category(
      p_school,p_campus,p_year,p_month,v_category.id,
      p_scope,p_target,null,coalesce(p_include_optional,false),
      pg_catalog.md5(p_operation::text||':'||v_category.id::text)::uuid);
    v_added:=v_added+(v_line->>'added_charges')::integer;
    v_skipped:=v_skipped+(v_line->>'skipped_existing')::integer;
    v_eligible:=v_eligible+(v_line->>'eligible_students')::integer;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'id',v_category.id,'code',v_category.code,
      'category',v_category.name,'frequency',v_category.charge_frequency,
      'added_charges',(v_line->>'added_charges')::integer,
      'skipped_existing',(v_line->>'skipped_existing')::integer,
      'eligible_students',(v_line->>'eligible_students')::integer));
  end loop;

  v_result:=jsonb_build_object(
    'saved',true,'mode','batch','month',p_month,
    'category_count',cardinality(v_ids),
    'added_charges',v_added,'skipped_existing',v_skipped,
    'eligible_charges',v_eligible,'categories',v_lines);
  insert into public.fee_operation_receipts(
    school_id,operation_id,action,actor_id,request_sha256,result_json)
  values(p_school,p_operation,'generate_charges',v_actor,v_hash,v_result);
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fee_generate_categories(p_school uuid, p_campus uuid, p_year uuid, p_month date, p_categories uuid[], p_scope text, p_target uuid, p_include_optional boolean, p_operation uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select app_private.sms_fee_generate_categories(
    p_school,p_campus,p_year,p_month,p_categories,
    p_scope,p_target,p_include_optional,p_operation);
$function$;

revoke all on function app_private.sms_fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid),
  public.fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid)
from public, anon, authenticated;
grant execute on function app_private.sms_fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid),
  public.fee_generate_categories(uuid,uuid,uuid,date,uuid[],text,uuid,boolean,uuid)
to authenticated;
