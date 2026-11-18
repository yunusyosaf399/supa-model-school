-- OPTIONAL IDEMPOTENT CATALOG TEMPLATES, NOT A HOSTED MIGRATION.
-- Requirements: DB03 public.fee_categories + DB06 public.expense_categories.
-- DO NOT run against the hosted database without reviewing school-specific chart
-- of accounts, DB05 payroll routes and DB07 COGS/tax classification.
-- These inserts create CATEGORY LABELS ONLY: no charges, expenses, posted
-- receipts, cash/bank movements, and no privileges or RLS bypass.
-- Existing category names and codes are never overwritten.
-- Seed currently active school(s) only; in this v1 app one school is expected.
-- FINANCE SAFETY: staff/principal salaries use payroll, not an operating
-- category. Stationery and canteen procurement are inventory, not COGS.
-- Uniform retail and fee assessments must not both charge the same sale.

BEGIN;
INSERT INTO public.fee_categories (school_id, code, name, charge_frequency, is_discountable, is_active)
SELECT s.id, f.code, f.name, f.frequency, f.discountable, true
FROM public.schools AS s
CROSS JOIN (VALUES
  ('TUITION','Tuition Fee','monthly',true),
  ('TRANSPORT','Transport Fee','monthly',true),
  ('ADMISSION','Admission Fee','one_time',false),
  ('EXAMINATION','Examination Fee','manual',false),
  ('PROMOTION','Promotion Fee','one_time',false),
  ('CERTIFICATE','Certificate Fee','manual',false),
  ('FINE','Fine / Penalty','manual',false),
  ('BOOKS_MATERIALS','Books and Learning Materials Fee','manual',false),
  ('UNIFORM_FEE','Uniform Fee (non-retail only)','manual',false)
) AS f(code,name,frequency,discountable)
WHERE s.status='active'
ON CONFLICT (school_id,code) DO NOTHING;

INSERT INTO public.expense_categories (school_id, code, name, expense_kind, is_active)
SELECT s.id, e.code, e.name, e.kind, true
FROM public.schools AS s
CROSS JOIN (VALUES
  ('BUILDING_RENT','Building Rent','operating'),
  ('HOTEL_TRAVEL','Hotel and Business Travel','operating'),
  ('WIFI_INTERNET','WiFi and Internet Billing','operating'),
  ('MEDICAL','Medical Expenses','operating'),
  ('SCHOOL_STATIONERY','School Consumable Stationery','operating'),
  ('LAB_CONSUMABLES','Laboratory Consumables','operating'),
  ('LAB_EQUIPMENT_ASSET','Durable Laboratory Equipment','capital_asset'),
  ('EXAM_OPERATIONS','Examination Operating Expenses','operating'),
  ('VEHICLE_FUEL','Vehicle Fuel and Oil','operating'),
  ('VEHICLE_MAINTENANCE','Vehicle Maintenance','operating'),
  ('TAILOR_SERVICE','Tailoring Services','operating'),
  ('GENERAL_MAINTENANCE','General Repairs and Maintenance','operating'),
  ('RETAIL_STATIONERY_STOCK','Stationery Inventory for Resale','inventory_procurement'),
  ('CANTEEN_STOCK','Canteen Inventory Purchases','inventory_procurement'),
  ('OTHER_OPERATING','Other Approved Operating Expenses','operating'),
  ('TEACHER_MOBILE_DATA','Teacher Business Mobile Packages','operating'),
  ('TUTOR_CONTRACTOR','External Tuition Tutor Contractor Fees','operating'),
  ('PRINCIPAL_REIMBURSEMENT','Approved Principal Reimbursements','operating')
) AS e(code,name,kind)
WHERE s.status='active'
ON CONFLICT (school_id,code) DO NOTHING;
COMMIT;
