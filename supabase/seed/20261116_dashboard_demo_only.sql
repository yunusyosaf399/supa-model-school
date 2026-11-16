-- Clearly marked dashboard-only test figures.
-- Does not insert students, guardian identities, invoices, attendance, or
-- admission applications into operational tables.
-- One pending school + one campus only; idempotent and safely removable.

do $seed$
begin
  if (select count(*) from public.schools) <> 1
     or (select count(*) from public.campuses) <> 1
     or (select count(*) from public.students) <> 0
     or (select count(*) from public.academic_years) <> 0
     or not exists (
       select 1 from public.school_settings
       where setting_key='initial_setup'
         and setting_value->>'status'='pending'
     )
  then
    raise exception 'Demo snapshot seeding requires one empty pending school';
  end if;
end $seed$;

insert into app_private.dashboard_demo_snapshots(school_id,campus_id,snapshot)
select s.id,c.id,
jsonb_build_object(
  'is_demo',true,
  'year_label','2026–2027 (test)',
  'currency_code','PKR',
  'active_students',1248,
  'fee_collected',4860750,
  'fees_outstanding',742500,
  'attendance_present',1215,
  'attendance_total',1248,
  'fee_trend',jsonb_build_array(
    jsonb_build_object('label','Jun','amount',380000),
    jsonb_build_object('label','Jul','amount',520000),
    jsonb_build_object('label','Aug','amount',700000),
    jsonb_build_object('label','Sep','amount',650000),
    jsonb_build_object('label','Oct','amount',810000),
    jsonb_build_object('label','Nov','amount',915000)
  ),
  'recent_admissions',jsonb_build_array(
    jsonb_build_object('name','Demo Student 001','class','Grade 1 A','when','16 Nov 2026'),
    jsonb_build_object('name','Demo Student 002','class','Grade 2 A','when','16 Nov 2026'),
    jsonb_build_object('name','Demo Student 003','class','Grade 3 B','when','15 Nov 2026'),
    jsonb_build_object('name','Demo Student 004','class','Grade 5 A','when','15 Nov 2026')
  ),
  'pending_admissions',7,
  'pending_expenses',4,
  'pending_leave',3
)
from public.schools s
join public.campuses c on c.school_id=s.id
where s.name='Supa Model School' and s.status='active'
  and c.is_active
on conflict (school_id,campus_id) do nothing;

-- To remove ONLY these demo figures after testing (never use DELETE
-- on students/guardian/admission tables for this task):
-- delete from app_private.dashboard_demo_snapshots
-- where snapshot->>'is_demo'='true';
