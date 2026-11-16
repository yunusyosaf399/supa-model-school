-- DB07 — Inventory, Canteen, Uniform Production and Student Transport
-- DESIGN SOURCE ONLY, NOT A SUPABASE MIGRATION OR DEPLOYED SCHEMA.
-- Requires DB01/02 baselines and stacked DB03 -> DB04 -> DB05 -> DB06.
-- One school, multiple campuses, PKR/SAR money in integer minor units.
-- Quantity is numeric(14,3), never binary FLOAT; no inventory balance
-- stored as mutable UI value. See docs/36_DB07_BUSINESS_TRANSPORT_DESIGN.md.
BEGIN;

-- Extend DB06 expense source key for same-campus vehicle-maintenance
-- linkage. Cross-campus expense references are forbidden by composite FK.
ALTER TABLE public.expenses ADD CONSTRAINT db07_expense_campus_source_key
  UNIQUE (id,school_id,campus_id);

-- 01-03: common inventory catalog, units and physical stores.
CREATE TABLE public.inventory_categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
 code text NOT NULL CHECK (code ~ '^[A-Z][A-Z0-9_]{1,29}$'),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 140),
 is_active boolean NOT NULL DEFAULT true,
 UNIQUE (school_id,code),
 UNIQUE (id,school_id)
);

CREATE TABLE public.inventory_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 category_id uuid NOT NULL,
 sku text NOT NULL CHECK (length(btrim(sku)) BETWEEN 2 AND 64),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 180),
 item_kind text NOT NULL CHECK
  (item_kind IN ('canteen','uniform_material','uniform_finished','general','spare_part')),
 unit_kind text NOT NULL CHECK
  (unit_kind IN ('piece','pack','kg','litre','metre')),
 requires_lot boolean NOT NULL DEFAULT true,
 reorder_point numeric(14,3) NOT NULL DEFAULT 0 CHECK (reorder_point>=0),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (category_id,school_id)
  REFERENCES public.inventory_categories(id,school_id) ON DELETE RESTRICT,
 UNIQUE (school_id,sku),
 UNIQUE (id,school_id),
 UNIQUE (id,school_id,item_kind)
);

CREATE TABLE public.inventory_locations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 code text NOT NULL CHECK (length(btrim(code)) BETWEEN 2 AND 40),
 name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
 location_kind text NOT NULL CHECK
  (location_kind IN ('canteen','uniform_raw','uniform_finished','general','vehicle_store')),
 is_active boolean NOT NULL DEFAULT true,
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 UNIQUE (campus_id,code),
 UNIQUE (id,school_id,campus_id)
);

-- 04-08: ordering vs physical receipt; ordering is NOT an expense.
CREATE TABLE public.inventory_suppliers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
 supplier_code text NOT NULL CHECK (length(btrim(supplier_code)) BETWEEN 2 AND 40),
 display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 180),
 contact_phone text,
 is_active boolean NOT NULL DEFAULT true,
 UNIQUE (school_id,supplier_code),
 UNIQUE (id,school_id)
);

CREATE TABLE public.inventory_purchase_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 supplier_id uuid NOT NULL,
 order_code text NOT NULL CHECK (length(btrim(order_code)) BETWEEN 3 AND 60),
 ordered_on date NOT NULL,
 status text NOT NULL DEFAULT 'draft'
  CHECK (status IN ('draft','approved','cancelled')),
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 approved_by uuid REFERENCES auth.users(id),
 approved_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (supplier_id,school_id)
  REFERENCES public.inventory_suppliers(id,school_id) ON DELETE RESTRICT,
 CHECK (
  (status='approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL)
  OR (status IN ('draft','cancelled') AND approved_by IS NULL AND approved_at IS NULL)
 ),
 UNIQUE (school_id,order_code),
 UNIQUE (id,school_id,campus_id)
);

CREATE TABLE public.inventory_purchase_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 purchase_order_id uuid NOT NULL,
 item_id uuid NOT NULL,
 quantity numeric(14,3) NOT NULL CHECK (quantity>0),
 unit_cost_minor bigint NOT NULL CHECK (unit_cost_minor>=0),
 line_total_minor bigint GENERATED ALWAYS AS
  (round(quantity * unit_cost_minor::numeric,0)::bigint) STORED,
 FOREIGN KEY (purchase_order_id,school_id,campus_id)
  REFERENCES public.inventory_purchase_orders(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (item_id,school_id)
  REFERENCES public.inventory_items(id,school_id) ON DELETE RESTRICT,
 UNIQUE (purchase_order_id,item_id),
 UNIQUE (id,school_id,campus_id,purchase_order_id,item_id)
);

CREATE TABLE public.inventory_goods_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 purchase_order_id uuid NOT NULL,
 location_id uuid NOT NULL,
 receipt_code text NOT NULL CHECK (length(btrim(receipt_code)) BETWEEN 3 AND 60),
 received_on date NOT NULL,
 operation_id uuid NOT NULL,
 received_by uuid NOT NULL REFERENCES auth.users(id),
 received_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (purchase_order_id,school_id,campus_id)
  REFERENCES public.inventory_purchase_orders(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (location_id,school_id,campus_id)
  REFERENCES public.inventory_locations(id,school_id,campus_id)
  ON DELETE RESTRICT,
 UNIQUE (school_id,receipt_code),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,purchase_order_id)
);

CREATE TABLE public.inventory_receipt_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 goods_receipt_id uuid NOT NULL,
 purchase_order_id uuid NOT NULL,
 purchase_line_id uuid NOT NULL,
 item_id uuid NOT NULL,
 received_qty numeric(14,3) NOT NULL CHECK (received_qty>0),
 unit_cost_minor bigint NOT NULL CHECK (unit_cost_minor>=0),
 FOREIGN KEY (goods_receipt_id,school_id,campus_id,purchase_order_id)
  REFERENCES public.inventory_goods_receipts
  (id,school_id,campus_id,purchase_order_id) ON DELETE RESTRICT,
 FOREIGN KEY (purchase_line_id,school_id,campus_id,purchase_order_id,item_id)
  REFERENCES public.inventory_purchase_lines
  (id,school_id,campus_id,purchase_order_id,item_id) ON DELETE RESTRICT,
 UNIQUE (goods_receipt_id,purchase_line_id),
 UNIQUE (id,school_id,campus_id,item_id)
);

-- 09: one physical lot in one campus location; moving stock to another
-- campus creates a NEW destination lot and a linked transfer pair.
CREATE TABLE public.inventory_lots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 location_id uuid NOT NULL,
 item_id uuid NOT NULL,
 lot_code text NOT NULL CHECK (length(btrim(lot_code)) BETWEEN 2 AND 64),
 expiry_on date,
 received_on date NOT NULL,
 source_receipt_line_id uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (location_id,school_id,campus_id)
  REFERENCES public.inventory_locations(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (item_id,school_id)
  REFERENCES public.inventory_items(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (source_receipt_line_id,school_id,campus_id,item_id)
  REFERENCES public.inventory_receipt_lines(id,school_id,campus_id,item_id)
  ON DELETE RESTRICT,
 UNIQUE (location_id,item_id,lot_code),
 UNIQUE (id,school_id,campus_id,location_id,item_id)
);

-- 10-11: transfer instruction does not move inventory by itself.
CREATE TABLE public.inventory_transfers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 from_campus_id uuid NOT NULL,
 from_location_id uuid NOT NULL,
 to_campus_id uuid NOT NULL,
 to_location_id uuid NOT NULL,
 requested_on date NOT NULL,
 status text NOT NULL DEFAULT 'requested'
  CHECK (status IN ('requested','approved','cancelled')),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
 operation_id uuid NOT NULL,
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 approved_by uuid REFERENCES auth.users(id),
 FOREIGN KEY (from_location_id,school_id,from_campus_id)
  REFERENCES public.inventory_locations(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (to_location_id,school_id,to_campus_id)
  REFERENCES public.inventory_locations(id,school_id,campus_id)
  ON DELETE RESTRICT,
 CHECK (from_location_id<>to_location_id),
 CHECK ((status='approved' AND approved_by IS NOT NULL)
    OR (status IN ('requested','cancelled') AND approved_by IS NULL)),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id)
);

CREATE TABLE public.inventory_transfer_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 transfer_id uuid NOT NULL,
 item_id uuid NOT NULL,
 transfer_qty numeric(14,3) NOT NULL CHECK (transfer_qty>0),
 FOREIGN KEY (transfer_id,school_id)
  REFERENCES public.inventory_transfers(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (item_id,school_id)
  REFERENCES public.inventory_items(id,school_id) ON DELETE RESTRICT,
 UNIQUE (transfer_id,item_id),
 UNIQUE (id,school_id,item_id)
);

-- 12-13: stocktaking is a snapshot, not an unapproved stock adjustment.
CREATE TABLE public.inventory_counts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 location_id uuid NOT NULL,
 counted_on date NOT NULL,
 status text NOT NULL DEFAULT 'draft'
  CHECK (status IN ('draft','approved')),
 counted_by uuid NOT NULL REFERENCES auth.users(id),
 approved_by uuid REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 FOREIGN KEY (location_id,school_id,campus_id)
  REFERENCES public.inventory_locations(id,school_id,campus_id)
  ON DELETE RESTRICT,
 CHECK ((status='approved' AND approved_by IS NOT NULL)
    OR (status='draft' AND approved_by IS NULL)),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,location_id)
);

CREATE TABLE public.inventory_count_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 location_id uuid NOT NULL,
 count_id uuid NOT NULL,
 item_id uuid NOT NULL,
 expected_qty numeric(14,3) NOT NULL CHECK (expected_qty>=0),
 counted_qty numeric(14,3) NOT NULL CHECK (counted_qty>=0),
 variance_qty numeric(14,3) GENERATED ALWAYS AS
  (counted_qty-expected_qty) STORED,
 reason text,
 FOREIGN KEY (count_id,school_id,campus_id,location_id)
  REFERENCES public.inventory_counts(id,school_id,campus_id,location_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (item_id,school_id)
  REFERENCES public.inventory_items(id,school_id) ON DELETE RESTRICT,
 CHECK (expected_qty=counted_qty OR length(btrim(coalesce(reason,'')))>=4),
 UNIQUE (count_id,item_id),
 UNIQUE (id,school_id,campus_id,item_id)
);

-- 14-17: canteen catalog, effective price history and posted sales.
CREATE TABLE public.canteen_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 item_id uuid NOT NULL,
 item_kind text NOT NULL DEFAULT 'canteen' CHECK (item_kind='canteen'),
 display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 120),
 is_available boolean NOT NULL DEFAULT true,
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (item_id,school_id,item_kind)
  REFERENCES public.inventory_items(id,school_id,item_kind) ON DELETE RESTRICT,
 UNIQUE (campus_id,item_id),
 UNIQUE (id,school_id,campus_id),
 UNIQUE (id,school_id,campus_id,item_id)
);

CREATE TABLE public.canteen_prices (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 product_id uuid NOT NULL,
 effective_from date NOT NULL,
 price_minor bigint NOT NULL CHECK (price_minor>=0),
 authorized_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY (product_id,school_id,campus_id)
  REFERENCES public.canteen_products(id,school_id,campus_id)
  ON DELETE RESTRICT,
 UNIQUE (product_id,effective_from),
 UNIQUE (id,school_id,campus_id,product_id)
);

CREATE TABLE public.canteen_sales (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 sale_no text NOT NULL CHECK (length(btrim(sale_no)) BETWEEN 3 AND 50),
 student_id uuid,
 financial_account_id uuid NOT NULL,
 payment_method text NOT NULL CHECK (payment_method IN ('cash','bank')),
 total_minor bigint NOT NULL CHECK (total_minor>0),
 operation_id uuid NOT NULL,
 sold_by uuid NOT NULL REFERENCES auth.users(id),
 sold_at timestamptz NOT NULL DEFAULT now(),
 creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current(),
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (student_id,school_id)
  REFERENCES public.students(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (financial_account_id,school_id,campus_id,payment_method)
  REFERENCES public.financial_accounts
  (id,school_id,campus_id,account_kind) ON DELETE RESTRICT,
 UNIQUE (school_id,sale_no),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id)
);

CREATE TABLE public.canteen_sale_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 sale_id uuid NOT NULL,
 product_id uuid NOT NULL,
 item_id uuid NOT NULL,
 qty numeric(14,3) NOT NULL CHECK (qty>0),
 unit_price_minor bigint NOT NULL CHECK (unit_price_minor>=0),
 total_minor bigint GENERATED ALWAYS AS
  (round(qty * unit_price_minor::numeric,0)::bigint) STORED,
 FOREIGN KEY (sale_id,school_id,campus_id)
  REFERENCES public.canteen_sales(id,school_id,campus_id) ON DELETE RESTRICT,
 FOREIGN KEY (product_id,school_id,campus_id,item_id)
  REFERENCES public.canteen_products(id,school_id,campus_id,item_id)
  ON DELETE RESTRICT,
 UNIQUE (sale_id,product_id),
 UNIQUE (id,school_id,campus_id,item_id)
);

-- 18-23: uniforms: finished product, recipe, material issues, output.
CREATE TABLE public.uniform_products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 finished_item_id uuid NOT NULL,
 item_kind text NOT NULL DEFAULT 'uniform_finished'
  CHECK (item_kind='uniform_finished'),
 uniform_type text NOT NULL CHECK
  (uniform_type IN ('shirt','trousers','dress','jacket','shoes','set','other')),
 size_label text NOT NULL CHECK (length(btrim(size_label)) BETWEEN 1 AND 32),
 display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 160),
 is_active boolean NOT NULL DEFAULT true,
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (finished_item_id,school_id,item_kind)
  REFERENCES public.inventory_items(id,school_id,item_kind) ON DELETE RESTRICT,
 UNIQUE (campus_id,finished_item_id),
 UNIQUE (id,school_id,campus_id),
 UNIQUE (id,school_id,campus_id,finished_item_id)
);

CREATE TABLE public.uniform_recipes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 uniform_product_id uuid NOT NULL,
 version_no integer NOT NULL CHECK (version_no>0),
 status text NOT NULL DEFAULT 'draft'
  CHECK (status IN ('draft','approved','retired')),
 approved_by uuid REFERENCES auth.users(id),
 valid_from date NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (uniform_product_id,school_id,campus_id)
  REFERENCES public.uniform_products(id,school_id,campus_id) ON DELETE RESTRICT,
 CHECK (status<>'approved' OR approved_by IS NOT NULL),
 UNIQUE (uniform_product_id,version_no),
 UNIQUE (id,school_id,campus_id,uniform_product_id)
);
CREATE UNIQUE INDEX one_approved_uniform_recipe_per_product
 ON public.uniform_recipes(uniform_product_id) WHERE status='approved';

CREATE TABLE public.uniform_recipe_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 recipe_id uuid NOT NULL,
 material_item_id uuid NOT NULL,
 material_item_kind text NOT NULL DEFAULT 'uniform_material'
  CHECK (material_item_kind='uniform_material'),
 required_qty_per_unit numeric(14,3) NOT NULL CHECK (required_qty_per_unit>0),
 FOREIGN KEY (recipe_id,school_id,campus_id)
  REFERENCES public.uniform_recipes(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (material_item_id,school_id,material_item_kind)
  REFERENCES public.inventory_items(id,school_id,item_kind)
  ON DELETE RESTRICT,
 UNIQUE (recipe_id,material_item_id)
);

CREATE TABLE public.uniform_production_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 uniform_product_id uuid NOT NULL,
 recipe_id uuid NOT NULL,
 batch_code text NOT NULL CHECK (length(btrim(batch_code)) BETWEEN 3 AND 64),
 planned_units integer NOT NULL CHECK (planned_units>0),
 started_on date NOT NULL,
 status text NOT NULL DEFAULT 'planned'
  CHECK (status IN ('planned','in_progress','completed','cancelled')),
 finished_on date,
 operation_id uuid NOT NULL,
 supervised_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY (recipe_id,school_id,campus_id,uniform_product_id)
  REFERENCES public.uniform_recipes(id,school_id,campus_id,uniform_product_id)
  ON DELETE RESTRICT,
 CHECK ((status='completed' AND finished_on IS NOT NULL AND finished_on>=started_on)
   OR (status<>'completed' AND finished_on IS NULL)),
 UNIQUE (campus_id,batch_code),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,uniform_product_id)
);

CREATE TABLE public.uniform_material_issues (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 batch_id uuid NOT NULL,
 location_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 material_item_id uuid NOT NULL,
 material_item_kind text NOT NULL DEFAULT 'uniform_material'
  CHECK (material_item_kind='uniform_material'),
 issued_qty numeric(14,3) NOT NULL CHECK (issued_qty>0),
 operation_id uuid NOT NULL,
 issued_by uuid NOT NULL REFERENCES auth.users(id),
 issued_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (batch_id,school_id,campus_id)
  REFERENCES public.uniform_production_batches(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (lot_id,school_id,campus_id,location_id,material_item_id)
  REFERENCES public.inventory_lots(id,school_id,campus_id,location_id,item_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (material_item_id,school_id,material_item_kind)
  REFERENCES public.inventory_items(id,school_id,item_kind)
  ON DELETE RESTRICT,
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,material_item_id)
);

CREATE TABLE public.uniform_production_outputs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 batch_id uuid NOT NULL,
 uniform_product_id uuid NOT NULL,
 finished_item_id uuid NOT NULL,
 location_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 produced_units integer NOT NULL CHECK (produced_units>0),
 unit_cost_minor bigint NOT NULL CHECK (unit_cost_minor>=0),
 operation_id uuid NOT NULL,
 produced_by uuid NOT NULL REFERENCES auth.users(id),
 produced_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (batch_id,school_id,campus_id,uniform_product_id)
  REFERENCES public.uniform_production_batches(id,school_id,campus_id,uniform_product_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (uniform_product_id,school_id,campus_id,finished_item_id)
  REFERENCES public.uniform_products(id,school_id,campus_id,finished_item_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (lot_id,school_id,campus_id,location_id,finished_item_id)
  REFERENCES public.inventory_lots(id,school_id,campus_id,location_id,item_id)
  ON DELETE RESTRICT,
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,finished_item_id)
);

-- 24-25: uniform sales are independent from canteen sale receipts.
CREATE TABLE public.uniform_sales (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 sale_no text NOT NULL CHECK (length(btrim(sale_no)) BETWEEN 3 AND 50),
 student_id uuid,
 financial_account_id uuid NOT NULL,
 payment_method text NOT NULL CHECK (payment_method IN ('cash','bank')),
 total_minor bigint NOT NULL CHECK (total_minor>0),
 operation_id uuid NOT NULL,
 sold_by uuid NOT NULL REFERENCES auth.users(id),
 sold_at timestamptz NOT NULL DEFAULT now(),
 creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current(),
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (student_id,school_id)
  REFERENCES public.students(id,school_id) ON DELETE RESTRICT,
 FOREIGN KEY (financial_account_id,school_id,campus_id,payment_method)
  REFERENCES public.financial_accounts
  (id,school_id,campus_id,account_kind) ON DELETE RESTRICT,
 UNIQUE (school_id,sale_no),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id)
);

CREATE TABLE public.uniform_sale_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 sale_id uuid NOT NULL,
 uniform_product_id uuid NOT NULL,
 finished_item_id uuid NOT NULL,
 units integer NOT NULL CHECK (units>0),
 unit_price_minor bigint NOT NULL CHECK (unit_price_minor>=0),
 total_minor bigint GENERATED ALWAYS AS
  (units::bigint * unit_price_minor) STORED,
 FOREIGN KEY (sale_id,school_id,campus_id)
  REFERENCES public.uniform_sales(id,school_id,campus_id) ON DELETE RESTRICT,
 FOREIGN KEY (uniform_product_id,school_id,campus_id,finished_item_id)
  REFERENCES public.uniform_products(id,school_id,campus_id,finished_item_id)
  ON DELETE RESTRICT,
 UNIQUE (sale_id,uniform_product_id),
 UNIQUE (id,school_id,campus_id,finished_item_id)
);

-- 26-32: vehicle fleet, routes, pupils, drivers, trips and repairs.
CREATE TABLE public.transport_vehicles (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 registration_no text NOT NULL CHECK (length(btrim(registration_no)) BETWEEN 3 AND 48),
 capacity integer NOT NULL CHECK (capacity BETWEEN 1 AND 120),
 status text NOT NULL DEFAULT 'active'
  CHECK (status IN ('active','maintenance','retired')),
 acquired_on date,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 UNIQUE (school_id,registration_no),
 UNIQUE (id,school_id,campus_id)
);

CREATE TABLE public.transport_routes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 route_code text NOT NULL CHECK (length(btrim(route_code)) BETWEEN 2 AND 40),
 route_name text NOT NULL CHECK (length(btrim(route_name)) BETWEEN 3 AND 160),
 is_active boolean NOT NULL DEFAULT true,
 FOREIGN KEY (campus_id,school_id)
  REFERENCES public.campuses(id,school_id) ON DELETE RESTRICT,
 UNIQUE (campus_id,route_code),
 UNIQUE (id,school_id,campus_id)
);

CREATE TABLE public.transport_route_stops (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 route_id uuid NOT NULL,
 stop_order integer NOT NULL CHECK (stop_order>0),
 stop_name text NOT NULL CHECK (length(btrim(stop_name)) BETWEEN 2 AND 180),
 pickup_time time,
 dropoff_time time,
 FOREIGN KEY (route_id,school_id,campus_id)
  REFERENCES public.transport_routes(id,school_id,campus_id) ON DELETE RESTRICT,
 UNIQUE (route_id,stop_order),
 UNIQUE (id,school_id,campus_id,route_id)
);

CREATE TABLE public.transport_student_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 academic_year_id uuid NOT NULL,
 class_id uuid NOT NULL,
 student_id uuid NOT NULL,
 enrollment_id uuid NOT NULL,
 route_id uuid NOT NULL,
 stop_id uuid NOT NULL,
 starts_on date NOT NULL,
 ends_on date,
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,academic_year_id,class_id)
  REFERENCES public.student_enrollments
  (id,student_id,school_id,campus_id,academic_year_id,class_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (route_id,school_id,campus_id)
  REFERENCES public.transport_routes(id,school_id,campus_id) ON DELETE RESTRICT,
 FOREIGN KEY (stop_id,school_id,campus_id,route_id)
  REFERENCES public.transport_route_stops(id,school_id,campus_id,route_id)
  ON DELETE RESTRICT,
 CHECK (ends_on IS NULL OR ends_on>=starts_on),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id)
);
CREATE UNIQUE INDEX one_open_transport_route_per_student_year
 ON public.transport_student_assignments(student_id,academic_year_id)
 WHERE ends_on IS NULL;

CREATE TABLE public.transport_driver_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 employee_assignment_id uuid NOT NULL,
 starts_on date NOT NULL,
 ends_on date,
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY (vehicle_id,school_id,campus_id)
  REFERENCES public.transport_vehicles(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)
  REFERENCES public.employee_assignments(id,school_id,campus_id,employee_id)
  ON DELETE RESTRICT,
 CHECK (ends_on IS NULL OR ends_on>=starts_on),
 UNIQUE (id,school_id,campus_id,vehicle_id),
 UNIQUE (vehicle_id,starts_on)
);

CREATE TABLE public.transport_trip_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 route_id uuid NOT NULL,
 driver_assignment_id uuid NOT NULL,
 trip_date date NOT NULL,
 trip_kind text NOT NULL CHECK (trip_kind IN ('pickup','dropoff','special')),
 status text NOT NULL DEFAULT 'planned'
  CHECK (status IN ('planned','completed','cancelled')),
 start_odometer_km numeric(12,1),
 end_odometer_km numeric(12,1),
 departure_at timestamptz,
 arrival_at timestamptz,
 operation_id uuid NOT NULL,
 recorded_by uuid NOT NULL REFERENCES auth.users(id),
 FOREIGN KEY (route_id,school_id,campus_id)
  REFERENCES public.transport_routes(id,school_id,campus_id)
  ON DELETE RESTRICT,
 FOREIGN KEY (driver_assignment_id,school_id,campus_id,vehicle_id)
  REFERENCES public.transport_driver_assignments
  (id,school_id,campus_id,vehicle_id) ON DELETE RESTRICT,
 CHECK (end_odometer_km IS NULL OR start_odometer_km IS NULL OR
   end_odometer_km>=start_odometer_km),
 CHECK (arrival_at IS NULL OR departure_at IS NULL OR arrival_at>=departure_at),
 CHECK (status<>'completed' OR
   (start_odometer_km IS NOT NULL AND end_odometer_km IS NOT NULL
     AND departure_at IS NOT NULL AND arrival_at IS NOT NULL)),
 UNIQUE (school_id,operation_id),
 UNIQUE (vehicle_id,trip_date,trip_kind,route_id)
);

CREATE TABLE public.transport_maintenance_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 maintenance_date date NOT NULL,
 work_kind text NOT NULL
  CHECK (work_kind IN ('inspection','service','repair','tyres','fuel','other')),
 description text NOT NULL CHECK (length(btrim(description)) BETWEEN 4 AND 1000),
 odometer_km numeric(12,1) CHECK (odometer_km IS NULL OR odometer_km>=0),
 operation_id uuid NOT NULL,
 recorded_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (vehicle_id,school_id,campus_id)
  REFERENCES public.transport_vehicles(id,school_id,campus_id)
  ON DELETE RESTRICT,
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,vehicle_id)
);

-- 33: vehicle expense is a LINK to already-posted DB06 expense, never a
-- second expense record. Maintenance costs are not inferred from odometer.
CREATE TABLE public.transport_expense_links (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 maintenance_id uuid,
 expense_id uuid NOT NULL,
 FOREIGN KEY (vehicle_id,school_id,campus_id)
  REFERENCES public.transport_vehicles(id,school_id,campus_id) ON DELETE RESTRICT,
 FOREIGN KEY (maintenance_id,school_id,campus_id,vehicle_id)
  REFERENCES public.transport_maintenance_events
  (id,school_id,campus_id,vehicle_id) ON DELETE RESTRICT,
 FOREIGN KEY (expense_id,school_id,campus_id)
  REFERENCES public.expenses(id,school_id,campus_id) ON DELETE RESTRICT,
 UNIQUE (expense_id),
 UNIQUE (maintenance_id,expense_id)
);

-- 34: stock journal is append-only. Negative movement for consumption,
-- sale, waste or transfer-out; positive for receipts/production/transfer-in.
-- Available stock must be computed from signed deltas under server row locks.
CREATE TABLE public.inventory_stock_movements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 location_id uuid NOT NULL,
 item_id uuid NOT NULL,
 lot_id uuid NOT NULL,
 movement_kind text NOT NULL CHECK (movement_kind IN (
  'goods_receipt','transfer_in','transfer_out','canteen_sale',
  'uniform_sale','production_input','production_output',
  'adjustment_in','adjustment_out','waste','customer_return')),
 delta_qty numeric(14,3) NOT NULL CHECK (delta_qty<>0),
 unit_cost_minor bigint NOT NULL CHECK (unit_cost_minor>=0),
 operation_id uuid NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT now(),
 posted_by uuid NOT NULL REFERENCES auth.users(id),
 creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current(),
 FOREIGN KEY (lot_id,school_id,campus_id,location_id,item_id)
  REFERENCES public.inventory_lots(id,school_id,campus_id,location_id,item_id)
  ON DELETE RESTRICT,
 CHECK (
  (movement_kind IN ('goods_receipt','transfer_in','production_output',
                     'adjustment_in','customer_return') AND delta_qty>0)
  OR
  (movement_kind IN ('transfer_out','canteen_sale','uniform_sale',
                     'production_input','adjustment_out','waste') AND delta_qty<0)
 ),
 UNIQUE (school_id,operation_id),
 UNIQUE (id,school_id,campus_id,item_id,movement_kind)
);
CREATE INDEX db07_stock_movement_location_item_idx
 ON public.inventory_stock_movements(school_id,campus_id,location_id,item_id);

-- 35: every stock movement has ONE typed source, submitted in same
-- trusted transaction. Never fabricate stock just by uploading a receipt.
CREATE TABLE public.inventory_movement_sources (
 movement_id uuid PRIMARY KEY,
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 item_id uuid NOT NULL,
 movement_kind text NOT NULL,
 goods_receipt_line_id uuid,
 transfer_line_id uuid,
 canteen_sale_line_id uuid,
 uniform_sale_line_id uuid,
 material_issue_id uuid,
 production_output_id uuid,
 count_line_id uuid,
 manual_adjustment_reason text,
 FOREIGN KEY (movement_id,school_id,campus_id,item_id,movement_kind)
  REFERENCES public.inventory_stock_movements
  (id,school_id,campus_id,item_id,movement_kind) ON DELETE RESTRICT,
 FOREIGN KEY (goods_receipt_line_id,school_id,campus_id,item_id)
  REFERENCES public.inventory_receipt_lines
  (id,school_id,campus_id,item_id) ON DELETE RESTRICT,
 FOREIGN KEY (transfer_line_id,school_id,item_id)
  REFERENCES public.inventory_transfer_lines
  (id,school_id,item_id) ON DELETE RESTRICT,
 FOREIGN KEY (canteen_sale_line_id,school_id,campus_id,item_id)
  REFERENCES public.canteen_sale_lines
  (id,school_id,campus_id,item_id) ON DELETE RESTRICT,
 FOREIGN KEY (uniform_sale_line_id,school_id,campus_id,item_id)
  REFERENCES public.uniform_sale_lines
  (id,school_id,campus_id,finished_item_id) ON DELETE RESTRICT,
 FOREIGN KEY (material_issue_id,school_id,campus_id,item_id)
  REFERENCES public.uniform_material_issues
  (id,school_id,campus_id,material_item_id) ON DELETE RESTRICT,
 FOREIGN KEY (production_output_id,school_id,campus_id,item_id)
  REFERENCES public.uniform_production_outputs
  (id,school_id,campus_id,finished_item_id) ON DELETE RESTRICT,
 FOREIGN KEY (count_line_id,school_id,campus_id,item_id)
  REFERENCES public.inventory_count_lines
  (id,school_id,campus_id,item_id) ON DELETE RESTRICT,
 CHECK (
  num_nonnulls(
   goods_receipt_line_id,transfer_line_id,canteen_sale_line_id,
   uniform_sale_line_id,material_issue_id,production_output_id,
   count_line_id,manual_adjustment_reason)=1
 ),
 CHECK (
  (movement_kind='goods_receipt' AND goods_receipt_line_id IS NOT NULL)
  OR (movement_kind IN ('transfer_in','transfer_out') AND transfer_line_id IS NOT NULL)
  OR (movement_kind='canteen_sale' AND canteen_sale_line_id IS NOT NULL)
  OR (movement_kind='uniform_sale' AND uniform_sale_line_id IS NOT NULL)
  OR (movement_kind='production_input' AND material_issue_id IS NOT NULL)
  OR (movement_kind='production_output' AND production_output_id IS NOT NULL)
  OR (movement_kind IN ('adjustment_in','adjustment_out') AND
     (count_line_id IS NOT NULL OR length(btrim(coalesce(manual_adjustment_reason,'')))>=4))
  OR (movement_kind IN ('waste','customer_return') AND
     length(btrim(coalesce(manual_adjustment_reason,'')))>=4)
 )
);

-- 36: One cancellation/reversal per RETAIL sale, leave original evidence.
CREATE TABLE public.retail_sale_reversals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 campus_id uuid NOT NULL,
 sale_kind text NOT NULL CHECK (sale_kind IN ('canteen','uniform')),
 canteen_sale_id uuid UNIQUE,
 uniform_sale_id uuid UNIQUE,
 reversal_operation_id uuid NOT NULL,
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 4 AND 500),
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 reversed_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY (canteen_sale_id,school_id,campus_id)
  REFERENCES public.canteen_sales(id,school_id,campus_id) ON DELETE RESTRICT,
 FOREIGN KEY (uniform_sale_id,school_id,campus_id)
  REFERENCES public.uniform_sales(id,school_id,campus_id) ON DELETE RESTRICT,
 CHECK ((sale_kind='canteen' AND canteen_sale_id IS NOT NULL AND uniform_sale_id IS NULL)
  OR (sale_kind='uniform' AND uniform_sale_id IS NOT NULL AND canteen_sale_id IS NULL)),
 UNIQUE (school_id,reversal_operation_id)
);

-- 37: source-request hash/receipt; generated by a future approved
-- online transaction, NOT by the Flutter client.
CREATE TABLE public.db07_operation_receipts (
 school_id uuid NOT NULL REFERENCES public.schools(id) ON DELETE RESTRICT,
 operation_id uuid NOT NULL,
 action text NOT NULL CHECK (action IN (
  'approve_purchase','receive_goods','transfer_stock','adjust_stock',
  'post_canteen_sale','reverse_canteen_sale','approve_recipe',
  'start_production','complete_production','post_uniform_sale',
  'reverse_uniform_sale','assign_route','record_trip','record_maintenance')),
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 request_sha256 bytea NOT NULL CHECK (octet_length(request_sha256)=32),
 result_json jsonb NOT NULL CHECK (jsonb_typeof(result_json)='object'),
 processed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (school_id,operation_id)
);

-- Protect sale financial total against missing or altered line items.
CREATE FUNCTION app_private.db07_validate_sale_line_tx()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE v_creation_txid bigint;
BEGIN
 IF TG_TABLE_NAME='canteen_sale_lines' THEN
  SELECT s.creation_txid INTO v_creation_txid FROM public.canteen_sales s
    WHERE s.id=NEW.sale_id AND s.school_id=NEW.school_id AND s.campus_id=NEW.campus_id;
 ELSE
  SELECT s.creation_txid INTO v_creation_txid FROM public.uniform_sales s
    WHERE s.id=NEW.sale_id AND s.school_id=NEW.school_id AND s.campus_id=NEW.campus_id;
 END IF;
 IF v_creation_txid IS DISTINCT FROM pg_catalog.txid_current() THEN
  RAISE EXCEPTION 'Retail sale lines must be posted with sale header'
   USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER db07_canteen_line_origin BEFORE INSERT ON public.canteen_sale_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_validate_sale_line_tx();
CREATE TRIGGER db07_uniform_line_origin BEFORE INSERT ON public.uniform_sale_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_validate_sale_line_tx();

CREATE FUNCTION app_private.db07_verify_sale_total()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE v_count bigint; v_sum numeric;
BEGIN
 IF TG_TABLE_NAME='canteen_sales' THEN
  SELECT count(*),coalesce(sum(l.total_minor),0) INTO v_count,v_sum
    FROM public.canteen_sale_lines l WHERE l.sale_id=NEW.id;
 ELSE
  SELECT count(*),coalesce(sum(l.total_minor),0) INTO v_count,v_sum
    FROM public.uniform_sale_lines l WHERE l.sale_id=NEW.id;
 END IF;
 IF v_count<1 OR v_sum<>NEW.total_minor THEN
  RAISE EXCEPTION 'Retail sale total must equal summed line items'
   USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER db07_canteen_total
 AFTER INSERT ON public.canteen_sales
 DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_verify_sale_total();
CREATE CONSTRAINT TRIGGER db07_uniform_total
 AFTER INSERT ON public.uniform_sales
 DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_verify_sale_total();

CREATE FUNCTION app_private.db07_validate_movement_source()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
DECLARE v_created_txid bigint;
BEGIN
 SELECT m.creation_txid INTO v_created_txid
  FROM public.inventory_stock_movements m
  WHERE m.id=NEW.movement_id AND m.school_id=NEW.school_id;
 IF v_created_txid IS DISTINCT FROM pg_catalog.txid_current() THEN
  RAISE EXCEPTION 'Stock source must post in movement transaction'
    USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER db07_stock_source_origin BEFORE INSERT
 ON public.inventory_movement_sources
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_validate_movement_source();

CREATE FUNCTION app_private.db07_require_movement_source()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM public.inventory_movement_sources s
  WHERE s.movement_id=NEW.id AND s.school_id=NEW.school_id
 ) THEN
  RAISE EXCEPTION 'Stock movement missing typed source'
    USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER db07_stock_source_commit
 AFTER INSERT ON public.inventory_stock_movements
 DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_require_movement_source();

CREATE FUNCTION app_private.db07_reject_posted_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=''
AS $$
BEGIN
 RAISE EXCEPTION 'Posted inventory/retail/transport evidence is immutable'
   USING ERRCODE='23514';
END;
$$;
CREATE TRIGGER db07_inv_goods_receipts_immutable BEFORE UPDATE OR DELETE ON public.inventory_goods_receipts
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_goods_receipts_no_truncate BEFORE TRUNCATE ON public.inventory_goods_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_receipt_lines_immutable BEFORE UPDATE OR DELETE ON public.inventory_receipt_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_receipt_lines_no_truncate BEFORE TRUNCATE ON public.inventory_receipt_lines
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_lots_immutable BEFORE UPDATE OR DELETE ON public.inventory_lots
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_lots_no_truncate BEFORE TRUNCATE ON public.inventory_lots
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_can_sales_immutable BEFORE UPDATE OR DELETE ON public.canteen_sales
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_can_sales_no_truncate BEFORE TRUNCATE ON public.canteen_sales
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_can_sale_lines_immutable BEFORE UPDATE OR DELETE ON public.canteen_sale_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_can_sale_lines_no_truncate BEFORE TRUNCATE ON public.canteen_sale_lines
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_sales_immutable BEFORE UPDATE OR DELETE ON public.uniform_sales
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_sales_no_truncate BEFORE TRUNCATE ON public.uniform_sales
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_sale_lines_immutable BEFORE UPDATE OR DELETE ON public.uniform_sale_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_sale_lines_no_truncate BEFORE TRUNCATE ON public.uniform_sale_lines
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_material_issues_immutable BEFORE UPDATE OR DELETE ON public.uniform_material_issues
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_material_issues_no_truncate BEFORE TRUNCATE ON public.uniform_material_issues
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_production_outputs_immutable BEFORE UPDATE OR DELETE ON public.uniform_production_outputs
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_uni_production_outputs_no_truncate BEFORE TRUNCATE ON public.uniform_production_outputs
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_stock_movements_immutable BEFORE UPDATE OR DELETE ON public.inventory_stock_movements
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_stock_movements_no_truncate BEFORE TRUNCATE ON public.inventory_stock_movements
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_movement_sources_immutable BEFORE UPDATE OR DELETE ON public.inventory_movement_sources
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_movement_sources_no_truncate BEFORE TRUNCATE ON public.inventory_movement_sources
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_ret_sale_reversals_immutable BEFORE UPDATE OR DELETE ON public.retail_sale_reversals
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_ret_sale_reversals_no_truncate BEFORE TRUNCATE ON public.retail_sale_reversals
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_op_operation_receipts_immutable BEFORE UPDATE OR DELETE ON public.db07_operation_receipts
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_op_operation_receipts_no_truncate BEFORE TRUNCATE ON public.db07_operation_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_tr_trip_logs_immutable BEFORE UPDATE OR DELETE ON public.transport_trip_logs
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_tr_trip_logs_no_truncate BEFORE TRUNCATE ON public.transport_trip_logs
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_tr_expense_links_immutable BEFORE UPDATE OR DELETE ON public.transport_expense_links
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_tr_expense_links_no_truncate BEFORE TRUNCATE ON public.transport_expense_links
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_transfer_lines_immutable BEFORE UPDATE OR DELETE ON public.inventory_transfer_lines
 FOR EACH ROW EXECUTE FUNCTION app_private.db07_reject_posted_mutation();
CREATE TRIGGER db07_inv_transfer_lines_no_truncate BEFORE TRUNCATE ON public.inventory_transfer_lines
 FOR EACH STATEMENT EXECUTE FUNCTION app_private.db07_reject_posted_mutation();

-- Public API deny-by-default; no unreviewed direct access or posting RPCs.
ALTER TABLE public.inventory_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_purchase_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_goods_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_receipt_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_transfer_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_count_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_sale_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_recipe_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_production_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_material_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_production_outputs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.uniform_sale_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_route_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_student_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_driver_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_trip_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_maintenance_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_expense_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movement_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retail_sale_reversals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.db07_operation_receipts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
 public.inventory_categories,
 public.inventory_items,
 public.inventory_locations,
 public.inventory_suppliers,
 public.inventory_purchase_orders,
 public.inventory_purchase_lines,
 public.inventory_goods_receipts,
 public.inventory_receipt_lines,
 public.inventory_lots,
 public.inventory_transfers,
 public.inventory_transfer_lines,
 public.inventory_counts,
 public.inventory_count_lines,
 public.canteen_products,
 public.canteen_prices,
 public.canteen_sales,
 public.canteen_sale_lines,
 public.uniform_products,
 public.uniform_recipes,
 public.uniform_recipe_lines,
 public.uniform_production_batches,
 public.uniform_material_issues,
 public.uniform_production_outputs,
 public.uniform_sales,
 public.uniform_sale_lines,
 public.transport_vehicles,
 public.transport_routes,
 public.transport_route_stops,
 public.transport_student_assignments,
 public.transport_driver_assignments,
 public.transport_trip_logs,
 public.transport_maintenance_events,
 public.transport_expense_links,
 public.inventory_stock_movements,
 public.inventory_movement_sources,
 public.retail_sale_reversals,
 public.db07_operation_receipts
FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db07_validate_sale_line_tx()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db07_verify_sale_total()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db07_validate_movement_source()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db07_require_movement_source()
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION app_private.db07_reject_posted_mutation()
 FROM PUBLIC,anon,authenticated;

-- Explicitly unfinished: school roles, COGS/DB06 sale journal kinds,
-- concurrency-safe no-negative-stock, lot expiry, cost valuation,
-- real teacher/driver licensing, DB08 approval and DB09 sync.
COMMIT;
