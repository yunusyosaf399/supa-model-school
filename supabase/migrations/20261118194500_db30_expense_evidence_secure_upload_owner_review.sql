-- DB30: private immutable expense invoices/receipts, Owner verification, payment linking.
-- All monetary facts remain in DB29. Uploads and evidence approval do not post cash.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sms-expense-evidence','sms-expense-evidence',false,10485760,
 array['application/pdf','image/jpeg','image/png','image/webp']::text[])
on conflict(id) do update set public=false,file_size_limit=10485760,
 allowed_mime_types=excluded.allowed_mime_types;

create table public.expense_attachments (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.schools(id),
 campus_id uuid not null references public.campuses(id),
 request_id uuid not null references public.expense_requests(id),
 payment_id uuid references public.expenses(id),
 evidence_kind text not null check(evidence_kind in ('invoice','receipt')),
 storage_bucket text not null default 'sms-expense-evidence'
  check(storage_bucket='sms-expense-evidence'),
 object_path text not null unique,
 file_name text not null check(length(file_name) between 1 and 180),
 mime_type text not null check(mime_type in
  ('application/pdf','image/jpeg','image/png','image/webp')),
 file_size_bytes bigint not null check(file_size_bytes between 1 and 10485760),
 review_status text not null default 'pending'
  check(review_status in ('pending','verified','rejected')),
 uploaded_by uuid not null references auth.users(id),
 uploaded_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id),
 reviewed_at timestamptz,
 rejection_reason text,
 constraint db30_receipts_link_payment check(
  (evidence_kind='invoice' and payment_id is null)
  or (evidence_kind='receipt' and payment_id is not null)),
 constraint db30_review_fields check(
  (review_status='pending' and reviewed_by is null and reviewed_at is null
   and rejection_reason is null)
  or (review_status='verified' and reviewed_by is not null
   and reviewed_at is not null and rejection_reason is null)
  or (review_status='rejected' and reviewed_by is not null
   and reviewed_at is not null and length(btrim(rejection_reason))>=4))
);
create index db30_evidence_request_idx on public.expense_attachments
 (school_id,campus_id,request_id,uploaded_at desc);
create index db30_evidence_payment_idx on public.expense_attachments
 (payment_id) where payment_id is not null;
alter table public.expense_attachments enable row level security;
revoke all on public.expense_attachments from public,anon,authenticated;

-- The verified school owner, granted expense readers/payers, and the
-- original requester (with create permission) can see only their campus.
create or replace function app_private.sms_expense_evidence_can_view(
 p_school uuid,p_campus uuid,p_request uuid)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select exists(select 1 from public.expense_requests r
 where r.id=p_request and r.school_id=p_school and r.campus_id=p_campus
 and (app_private.sms_expense_authorized(p_school,p_campus,'expenses.read')
   or app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')
   or (r.requester_id=(select auth.uid())
     and app_private.sms_expense_authorized(p_school,p_campus,'expenses.create'))));
$fn$;

-- File paths: school/campus/request/request/uuid.ext for invoices;
-- school/campus/request/payment_uuid/uuid.ext for posted-payment receipts.
-- No caller may upload to a foreign school, campus, or payment.
create or replace function app_private.sms_expense_evidence_can_upload(
 p_bucket text,p_path text)
returns boolean language plpgsql stable security definer set search_path=''
as $fn$
declare v_parts text[]:=string_to_array(p_path,'/');
 v_school uuid;v_campus uuid;v_request uuid;v_payment uuid;
 v_actor uuid:=(select auth.uid());v_owner boolean;v_status text;
 v_requester uuid;
begin
 if p_bucket<>'sms-expense-evidence' or v_actor is null
 or array_length(v_parts,1)<>5
 or v_parts[1] !~* '^[a-f0-9-]{36}$'
 or v_parts[2] !~* '^[a-f0-9-]{36}$'
 or v_parts[3] !~* '^[a-f0-9-]{36}$'
 or v_parts[5] !~* '^[a-f0-9-]{36}\\.(pdf|jpg|png|webp)$'
 then return false;end if;
 begin
  v_school:=v_parts[1]::uuid;v_campus:=v_parts[2]::uuid;
  v_request:=v_parts[3]::uuid;
  if v_parts[4]<>'request' then v_payment:=v_parts[4]::uuid;end if;
 exception when invalid_text_representation then return false;end;
 if not app_private.sms_expense_evidence_can_view(v_school,v_campus,v_request)
 then return false;end if;
 select status,requester_id into v_status,v_requester
 from public.expense_requests
 where id=v_request and school_id=v_school and campus_id=v_campus;
 if v_status not in ('pending','approved') then return false;end if;
 v_owner:=app_private.is_verified_school_owner(v_actor,v_school);
 if v_payment is null then
  return v_owner or app_private.sms_expense_authorized(
   v_school,v_campus,'expenses.pay') or (v_requester=v_actor
    and app_private.sms_expense_authorized(v_school,v_campus,'expenses.create'));
 end if;
 if v_status<>'approved' or not exists(
  select 1 from public.expenses e where e.id=v_payment
   and e.school_id=v_school and e.campus_id=v_campus
   and e.request_id=v_request) then return false;end if;
 return v_owner or app_private.sms_expense_authorized(
  v_school,v_campus,'expenses.pay');
end;$fn$;

-- Only already registered files are readable. Never expose a public URL.
create or replace function app_private.sms_expense_evidence_can_read(
 p_bucket text,p_path text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select p_bucket='sms-expense-evidence' and exists(
 select 1 from public.expense_attachments a
 where a.storage_bucket=p_bucket and a.object_path=p_path
 and app_private.sms_expense_evidence_can_view(
   a.school_id,a.campus_id,a.request_id));
$fn$;

revoke all on function
 app_private.sms_expense_evidence_can_view(uuid,uuid,uuid),
 app_private.sms_expense_evidence_can_upload(text,text),
 app_private.sms_expense_evidence_can_read(text,text)
 from public,anon,authenticated;
-- storage.objects RLS must be able to call its predicates.
grant execute on function
 app_private.sms_expense_evidence_can_upload(text,text),
 app_private.sms_expense_evidence_can_read(text,text)
 to authenticated;

create policy "db30_expense_evidence_immutable_insert"
 on storage.objects for insert to authenticated
 with check(bucket_id='sms-expense-evidence' and
 app_private.sms_expense_evidence_can_upload(bucket_id,name));
create policy "db30_expense_evidence_registered_read"
 on storage.objects for select to authenticated
 using(bucket_id='sms-expense-evidence' and
 app_private.sms_expense_evidence_can_read(bucket_id,name));
-- Intentionally no UPDATE or DELETE policy for this bucket.

create or replace function app_private.sms_expense_evidence_register(
 p_school uuid,p_campus uuid,p_request uuid,p_payment uuid,
 p_kind text,p_path text,p_file_name text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_existing public.expense_attachments%rowtype;
 v_obj storage.objects%rowtype;v_parts text[]:=string_to_array(p_path,'/');
 v_size bigint;v_mime text;v_id uuid;v_name text:=btrim(coalesce(p_file_name,''));
begin
 if v_actor is null or p_kind not in ('invoice','receipt') or
 length(v_name) not between 1 and 180 or
 (p_kind='invoice' and p_payment is not null) or
 (p_kind='receipt' and p_payment is null) or
 p_path is null or array_length(v_parts,1)<>5 or
 v_parts[1]<>p_school::text or v_parts[2]<>p_campus::text
 or v_parts[3]<>p_request::text or
 v_parts[4]<>coalesce(p_payment::text,'request') or
 not app_private.sms_expense_evidence_can_upload('sms-expense-evidence',p_path)
 then raise exception 'Evidence registration not authorized' using errcode='42501';end if;
 select * into v_existing from public.expense_attachments where object_path=p_path;
 if found then
  if v_existing.school_id=p_school and v_existing.campus_id=p_campus
  and v_existing.request_id=p_request
  and v_existing.payment_id is not distinct from p_payment
  and v_existing.evidence_kind=p_kind and v_existing.uploaded_by=v_actor
  then return jsonb_build_object('saved',true,'attachment_id',v_existing.id,
    'status',v_existing.review_status);end if;
  raise exception 'Evidence path already linked' using errcode='23505';
 end if;
 select * into v_obj from storage.objects o
 where o.bucket_id='sms-expense-evidence' and o.name=p_path
   and o.owner_id=v_actor::text and o.archived_at is null
   and coalesce(o.is_delete_marker,false)=false;
 if not found or coalesce(v_obj.metadata->>'size','') !~ '^[0-9]{1,10}$'
 then raise exception 'Uploaded evidence not found' using errcode='23503';end if;
 v_size:=(v_obj.metadata->>'size')::bigint;
 v_mime:=v_obj.metadata->>'mimetype';
 if v_size not between 1 and 10485760 or
  not ((right(p_path,4)='.pdf' and v_mime='application/pdf') or
   (right(p_path,4)='.jpg' and v_mime='image/jpeg') or
   (right(p_path,4)='.png' and v_mime='image/png') or
   (right(p_path,5)='.webp' and v_mime='image/webp'))
 then raise exception 'Invalid evidence MIME, size or extension'
 using errcode='22023';end if;
 insert into public.expense_attachments(
  school_id,campus_id,request_id,payment_id,evidence_kind,object_path,
  file_name,mime_type,file_size_bytes,uploaded_by)
 values(p_school,p_campus,p_request,p_payment,p_kind,p_path,
  v_name,v_mime,v_size,v_actor)
 returning id into v_id;
 return jsonb_build_object('saved',true,'attachment_id',v_id,'status','pending');
end;$fn$;

create or replace function app_private.sms_expense_evidence_list(
 p_school uuid,p_campus uuid,p_request uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_owner boolean;v_status text;
begin
 if not app_private.sms_expense_evidence_can_view(p_school,p_campus,p_request)
 then raise exception 'Expense documents not accessible' using errcode='42501';end if;
 select status into v_status from public.expense_requests
 where id=p_request and school_id=p_school and campus_id=p_campus;
 v_owner:=app_private.is_verified_school_owner((select auth.uid()),p_school);
 return jsonb_build_object(
 'is_owner',v_owner,'request_status',v_status,
 'can_upload_invoice',v_status in ('pending','approved') and
  (v_owner or app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')
   or exists(select 1 from public.expense_requests r where r.id=p_request
    and r.requester_id=(select auth.uid()) and
      app_private.sms_expense_authorized(p_school,p_campus,'expenses.create'))),
 'can_upload_receipt',v_status='approved' and
  (v_owner or app_private.sms_expense_authorized(p_school,p_campus,'expenses.pay')),
 'attachments',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'kind',a.evidence_kind,'payment_id',a.payment_id,
   'file_name',a.file_name,'mime_type',a.mime_type,
   'bytes',a.file_size_bytes,'path',a.object_path,
   'status',a.review_status,'uploaded_at',a.uploaded_at,
   'reviewed_at',a.reviewed_at,'rejection_reason',a.rejection_reason,
   'uploaded_by',a.uploaded_by) order by a.uploaded_at desc,a.id desc)
   from public.expense_attachments a where a.school_id=p_school
    and a.campus_id=p_campus and a.request_id=p_request),'[]'::jsonb));
end;$fn$;

create or replace function app_private.sms_expense_evidence_review(
 p_school uuid,p_campus uuid,p_attachment uuid,
 p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_evidence public.expense_attachments%rowtype;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Only Owner may verify expense evidence' using errcode='42501';end if;
 if p_decision not in ('verified','rejected') or
  (p_decision='rejected' and length(coalesce(v_reason,''))<4)
 then raise exception 'Invalid evidence review' using errcode='22023';end if;
 if p_decision='verified' then v_reason:=null;end if;
 select * into v_evidence from public.expense_attachments
 where id=p_attachment and school_id=p_school and campus_id=p_campus
 for update;
 if not found then raise exception 'Evidence not found in campus' using errcode='42501';end if;
 if v_evidence.review_status=p_decision and v_evidence.reviewed_by=v_actor
    and v_evidence.rejection_reason is not distinct from v_reason
 then return jsonb_build_object('saved',true,'attachment_id',p_attachment,'status',p_decision);
 end if;
 if v_evidence.review_status<>'pending'
 then raise exception 'Evidence was already reviewed' using errcode='22023';end if;
 update public.expense_attachments set
 review_status=p_decision,reviewed_by=v_actor,reviewed_at=now(),
 rejection_reason=v_reason where id=p_attachment;
 return jsonb_build_object('saved',true,'attachment_id',p_attachment,'status',p_decision);
end;$fn$;

create or replace function public.expense_evidence_register(
 p_school uuid,p_campus uuid,p_request uuid,p_payment uuid,
 p_kind text,p_path text,p_file_name text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_evidence_register(
 p_school,p_campus,p_request,p_payment,p_kind,p_path,p_file_name);$fn$;
create or replace function public.expense_evidence_list(
 p_school uuid,p_campus uuid,p_request uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.sms_expense_evidence_list(p_school,p_campus,p_request);$fn$;
create or replace function public.expense_evidence_review(
 p_school uuid,p_campus uuid,p_attachment uuid,p_decision text,p_reason text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.sms_expense_evidence_review(
 p_school,p_campus,p_attachment,p_decision,p_reason);$fn$;

revoke all on function
 app_private.sms_expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text),
 app_private.sms_expense_evidence_list(uuid,uuid,uuid),
 app_private.sms_expense_evidence_review(uuid,uuid,uuid,text,text),
 public.expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text),
 public.expense_evidence_list(uuid,uuid,uuid),
 public.expense_evidence_review(uuid,uuid,uuid,text,text)
 from public,anon,authenticated;
grant execute on function
 app_private.sms_expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text),
 app_private.sms_expense_evidence_list(uuid,uuid,uuid),
 app_private.sms_expense_evidence_review(uuid,uuid,uuid,text,text),
 public.expense_evidence_register(uuid,uuid,uuid,uuid,text,text,text),
 public.expense_evidence_list(uuid,uuid,uuid),
 public.expense_evidence_review(uuid,uuid,uuid,text,text)
 to authenticated;
