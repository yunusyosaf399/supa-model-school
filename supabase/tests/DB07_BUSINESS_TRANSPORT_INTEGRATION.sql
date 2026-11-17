-- DB07 fictional acceptance fixture: DISPOSABLE LOCAL POSTGRES ONLY.
-- Requires DB01+DB02+DB03+DB04+DB05+DB06 and DB07 draft, in order.
-- Requires fictional local Auth user sms-adm-admin-a@example.invalid.
-- Not an end-to-end server posting/RLS/concurrency test.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB07_BUSINESS_TRANSPORT_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $fixture$
DECLARE
 actor_id uuid;
 s uuid := '11111111-1111-4111-8111-111111111111';
 a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
 y uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
 cl uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 student_id uuid := '22000000-0000-4000-8000-000000000001';
 enrollment_id uuid := '23000000-0000-4000-8000-000000000001';
 cat uuid := '24000000-0000-4000-8000-000000000001';
 item_c uuid := '24000000-0000-4000-8000-000000000002';
 item_m uuid := '24000000-0000-4000-8000-000000000003';
 item_f uuid := '24000000-0000-4000-8000-000000000004';
 loc_a uuid := '25000000-0000-4000-8000-000000000001';
 loc_b uuid := '25000000-0000-4000-8000-000000000002';
 supp uuid := '26000000-0000-4000-8000-000000000001';
 po uuid := '27000000-0000-4000-8000-000000000001';
 po_line uuid := '27000000-0000-4000-8000-000000000002';
 receipt uuid := '28000000-0000-4000-8000-000000000001';
 receipt_line uuid := '28000000-0000-4000-8000-000000000002';
 lot_a uuid := '29000000-0000-4000-8000-000000000001';
 lot_b uuid := '29000000-0000-4000-8000-000000000002';
 lot_material uuid := '29000000-0000-4000-8000-000000000003';
 lot_finished uuid := '29000000-0000-4000-8000-000000000004';
 xfer uuid := '2a000000-0000-4000-8000-000000000001';
 xfer_line uuid := '2a000000-0000-4000-8000-000000000002';
 cash_ledger uuid := '2b000000-0000-4000-8000-000000000001';
 cash_wallet uuid := '2b000000-0000-4000-8000-000000000002';
 can_prod uuid := '2c000000-0000-4000-8000-000000000001';
 can_sale uuid := '2c000000-0000-4000-8000-000000000002';
 can_sale_line uuid := '2c000000-0000-4000-8000-000000000003';
 uni_prod uuid := '2d000000-0000-4000-8000-000000000001';
 recipe uuid := '2d000000-0000-4000-8000-000000000002';
 batch uuid := '2d000000-0000-4000-8000-000000000003';
 material_issue uuid := '2d000000-0000-4000-8000-000000000004';
 prod_output uuid := '2d000000-0000-4000-8000-000000000005';
 uni_sale uuid := '2d000000-0000-4000-8000-000000000006';
 uni_sale_line uuid := '2d000000-0000-4000-8000-000000000007';
 route_a uuid := '2e000000-0000-4000-8000-000000000001';
 stop_a uuid := '2e000000-0000-4000-8000-000000000002';
 route_b uuid := '2e000000-0000-4000-8000-000000000003';
 stop_b uuid := '2e000000-0000-4000-8000-000000000004';
 vehicle uuid := '2f000000-0000-4000-8000-000000000001';
 dept uuid := '30000000-0000-4000-8000-000000000001';
 position_id uuid := '30000000-0000-4000-8000-000000000002';
 employee_id uuid := '30000000-0000-4000-8000-000000000003';
 emp_assign uuid := '30000000-0000-4000-8000-000000000004';
 driver_assign uuid := '30000000-0000-4000-8000-000000000005';
 maintenance_id uuid := '31000000-0000-4000-8000-000000000001';
 exp_cat uuid := '32000000-0000-4000-8000-000000000001';
 exp_req uuid := '32000000-0000-4000-8000-000000000002';
 posted_expense uuid := '32000000-0000-4000-8000-000000000003';
 stock_op integer := 0;
 stock_a numeric;
 stock_b numeric;
 stock_raw numeric;
 stock_finished numeric;
 n integer;
BEGIN
 SELECT id INTO actor_id FROM auth.users
  WHERE email='sms-adm-admin-a@example.invalid';
 IF actor_id IS NULL THEN
  RAISE EXCEPTION 'Create fictional LOCAL auth user first';
 END IF;
 INSERT INTO public.schools(id,name,currency_code,timezone_name)
  VALUES(s,'Fictional Business School','PKR','Asia/Karachi');
 INSERT INTO public.campuses(id,school_id,code,name)
  VALUES(a,s,'MAIN','Main Campus'),(b,s,'GIRLS','Girls Campus');
 INSERT INTO public.academic_years(id,school_id,label,starts_on,ends_on,is_active)
  VALUES(y,s,'2026-27','2026-04-01','2027-03-31',true);
 INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
  VALUES(cl,s,a,y,'Grade 1');
 INSERT INTO public.students(id,school_id,registration_no,full_name_en)
  VALUES(student_id,s,'FAKE-001','Fictional Pupil');
 INSERT INTO public.student_enrollments(
  id,student_id,school_id,campus_id,academic_year_id,class_id,admitted_on)
 VALUES(enrollment_id,student_id,s,a,y,cl,'2026-04-01');

 INSERT INTO public.inventory_categories(id,school_id,code,name)
  VALUES(cat,s,'STOCK','School Store Stock');
 INSERT INTO public.inventory_items(id,school_id,category_id,sku,name,item_kind,unit_kind)
 VALUES
 (item_c,s,cat,'CANTEEN-01','Packed Juice','canteen','piece'),
 (item_m,s,cat,'FABRIC-01','Uniform Fabric','uniform_material','metre'),
 (item_f,s,cat,'UNIFORM-01','Shirt Small','uniform_finished','piece');
 INSERT INTO public.inventory_locations(id,school_id,campus_id,code,name,location_kind)
 VALUES
 (loc_a,s,a,'CANTEEN-A','Main Store','canteen'),
 (loc_b,s,b,'CANTEEN-B','Girls Store','canteen');
 INSERT INTO public.inventory_suppliers(id,school_id,supplier_code,display_name)
 VALUES(supp,s,'SUP01','Fictional Supplier');
 INSERT INTO public.inventory_purchase_orders(
  id,school_id,campus_id,supplier_id,order_code,ordered_on,
  status,requested_by,approved_by,approved_at)
 VALUES(po,s,a,supp,'PO-FAKE-001','2026-04-03','approved',actor_id,actor_id,now());
 INSERT INTO public.inventory_purchase_lines(
  id,school_id,campus_id,purchase_order_id,item_id,quantity,unit_cost_minor)
 VALUES(po_line,s,a,po,item_c,10,500);
 INSERT INTO public.inventory_goods_receipts(
  id,school_id,campus_id,purchase_order_id,location_id,receipt_code,
  received_on,operation_id,received_by)
 VALUES(receipt,s,a,po,loc_a,'GRN-FAKE-001','2026-04-04',
  'aaa00000-0000-4000-8000-000000000001',actor_id);
 INSERT INTO public.inventory_receipt_lines(
  id,school_id,campus_id,goods_receipt_id,purchase_order_id,
  purchase_line_id,item_id,received_qty,unit_cost_minor)
 VALUES(receipt_line,s,a,receipt,po,po_line,item_c,10,500);
 INSERT INTO public.inventory_lots(
  id,school_id,campus_id,location_id,item_id,lot_code,received_on,source_receipt_line_id)
 VALUES(lot_a,s,a,loc_a,item_c,'LOT-JUICE-001','2026-04-04',receipt_line);
 INSERT INTO public.inventory_lots(
  id,school_id,campus_id,location_id,item_id,lot_code,received_on)
 VALUES(lot_b,s,b,loc_b,item_c,'LOT-JUICE-B-01','2026-04-05'),
 (lot_material,s,a,loc_a,item_m,'LOT-FABRIC-01','2026-04-04'),
 (lot_finished,s,a,loc_a,item_f,'LOT-UNIFORM-01','2026-04-05');

 -- Purchase order/receipt must not create another DB06 paid expense.
 IF (SELECT count(*) FROM public.expenses WHERE school_id=s)<>0 THEN
  RAISE EXCEPTION 'Inventory purchase automatically created cash expense';
 END IF;

 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES(s,a,loc_a,item_c,lot_a,'goods_receipt',10,500,
  'aaa00000-0000-4000-8000-000000000002',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,goods_receipt_line_id)
 SELECT id,s,a,item_c,'goods_receipt',receipt_line
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000002';

 -- Transfer 3 units A->B: request alone changes no quantity;
 -- two separately sourced ledger moves change both location balances.
 INSERT INTO public.inventory_transfers(
  id,school_id,from_campus_id,from_location_id,to_campus_id,to_location_id,
  requested_on,status,reason,operation_id,requested_by,approved_by)
 VALUES(xfer,s,a,loc_a,b,loc_b,'2026-04-05','approved',
  'Intercampus stock transfer','aaa00000-0000-4000-8000-000000000003',
  actor_id,actor_id);
 INSERT INTO public.inventory_transfer_lines(id,school_id,transfer_id,item_id,transfer_qty)
 VALUES(xfer_line,s,xfer,item_c,3);
 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES
 (s,a,loc_a,item_c,lot_a,'transfer_out',-3,500,
  'aaa00000-0000-4000-8000-000000000004',actor_id),
 (s,b,loc_b,item_c,lot_b,'transfer_in',3,500,
  'aaa00000-0000-4000-8000-000000000005',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,transfer_line_id)
 SELECT id,school_id,campus_id,item_id,movement_kind,xfer_line
 FROM public.inventory_stock_movements
 WHERE operation_id IN ('aaa00000-0000-4000-8000-000000000004',
                        'aaa00000-0000-4000-8000-000000000005');

 -- Physical campus A CASH asset account required for cash point-of-sale.
 INSERT INTO public.ledger_accounts(
  id,school_id,campus_id,code,name,account_type,account_scope)
 VALUES(cash_ledger,s,a,'CASH_A','Campus A Cash','asset','campus');
 INSERT INTO public.financial_accounts(
  id,school_id,campus_id,ledger_account_id,account_kind,
  display_name,opened_on,created_by)
 VALUES(cash_wallet,s,a,cash_ledger,'cash','Main Cash','2026-04-01',actor_id);

 INSERT INTO public.canteen_products(
  id,school_id,campus_id,item_id,display_name)
 VALUES(can_prod,s,a,item_c,'Juice Pack');
 INSERT INTO public.canteen_prices(
  school_id,campus_id,product_id,effective_from,price_minor,authorized_by)
 VALUES(s,a,can_prod,'2026-04-01',1200,actor_id);
 INSERT INTO public.canteen_sales(
  id,school_id,campus_id,sale_no,student_id,financial_account_id,
  payment_method,total_minor,operation_id,sold_by)
 VALUES(can_sale,s,a,'CANTEEN-0001',student_id,cash_wallet,
  'cash',2400,'aaa00000-0000-4000-8000-000000000006',actor_id);
 INSERT INTO public.canteen_sale_lines(
  id,school_id,campus_id,sale_id,product_id,item_id,qty,unit_price_minor)
 VALUES(can_sale_line,s,a,can_sale,can_prod,item_c,2,1200);
 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES(s,a,loc_a,item_c,lot_a,'canteen_sale',-2,500,
  'aaa00000-0000-4000-8000-000000000007',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,canteen_sale_line_id)
 SELECT id,s,a,item_c,'canteen_sale',can_sale_line
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000007';

 -- Wrong payment method cannot use cash wallet as a bank account.
 BEGIN
  INSERT INTO public.canteen_sales(
   school_id,campus_id,sale_no,student_id,financial_account_id,
   payment_method,total_minor,operation_id,sold_by)
  VALUES(s,a,'CANTEEN-INVALID',student_id,cash_wallet,'bank',300,
   'aaa00000-0000-4000-8000-000000000008',actor_id);
  RAISE EXCEPTION 'Canteen bank method spoofed cash account';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 -- A posted retail sale must have at least one correctly summed line.
 BEGIN
  INSERT INTO public.canteen_sales(
   school_id,campus_id,sale_no,financial_account_id,payment_method,
   total_minor,operation_id,sold_by)
  VALUES(s,a,'CANTEEN-BAD-TOTAL',cash_wallet,'cash',
   9999,'aaa00000-0000-4000-8000-000000000009',actor_id);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'Retail sale without items accepted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 SET CONSTRAINTS ALL DEFERRED;

 -- Uniform raw material opening is a separately approved adjustment.
 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES(s,a,loc_a,item_m,lot_material,'adjustment_in',20,1000,
  'aaa00000-0000-4000-8000-000000000010',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,manual_adjustment_reason)
 SELECT id,s,a,item_m,'adjustment_in','Fictional signed opening stock adjustment'
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000010';

 INSERT INTO public.uniform_products(
  id,school_id,campus_id,finished_item_id,
  uniform_type,size_label,display_name)
 VALUES(uni_prod,s,a,item_f,'shirt','S','School Shirt Small');
 INSERT INTO public.uniform_recipes(
  id,school_id,campus_id,uniform_product_id,version_no,status,approved_by,valid_from)
 VALUES(recipe,s,a,uni_prod,1,'approved',actor_id,'2026-04-01');
 INSERT INTO public.uniform_recipe_lines(
  school_id,campus_id,recipe_id,material_item_id,required_qty_per_unit)
 VALUES(s,a,recipe,item_m,2);
 INSERT INTO public.uniform_production_batches(
  id,school_id,campus_id,uniform_product_id,recipe_id,batch_code,
  planned_units,started_on,operation_id,supervised_by)
 VALUES(batch,s,a,uni_prod,recipe,'BATCH-SHIRT-001',2,'2026-04-05',
  'aaa00000-0000-4000-8000-000000000011',actor_id);
 INSERT INTO public.uniform_material_issues(
  id,school_id,campus_id,batch_id,location_id,lot_id,
  material_item_id,issued_qty,operation_id,issued_by)
 VALUES(material_issue,s,a,batch,loc_a,lot_material,item_m,4,
  'aaa00000-0000-4000-8000-000000000012',actor_id);
 INSERT INTO public.uniform_production_outputs(
  id,school_id,campus_id,batch_id,uniform_product_id,finished_item_id,
  location_id,lot_id,produced_units,unit_cost_minor,operation_id,produced_by)
 VALUES(prod_output,s,a,batch,uni_prod,item_f,loc_a,lot_finished,2,2000,
  'aaa00000-0000-4000-8000-000000000013',actor_id);
 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES(s,a,loc_a,item_m,lot_material,'production_input',-4,1000,
  'aaa00000-0000-4000-8000-000000000014',actor_id),
 (s,a,loc_a,item_f,lot_finished,'production_output',2,2000,
  'aaa00000-0000-4000-8000-000000000015',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,material_issue_id)
 SELECT id,s,a,item_m,'production_input',material_issue
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000014';
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,production_output_id)
 SELECT id,s,a,item_f,'production_output',prod_output
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000015';

 INSERT INTO public.uniform_sales(
  id,school_id,campus_id,sale_no,student_id,financial_account_id,
  payment_method,total_minor,operation_id,sold_by)
 VALUES(uni_sale,s,a,'UNIFORM-0001',student_id,cash_wallet,'cash',
  9500,'aaa00000-0000-4000-8000-000000000016',actor_id);
 INSERT INTO public.uniform_sale_lines(
  id,school_id,campus_id,sale_id,uniform_product_id,finished_item_id,
  units,unit_price_minor)
 VALUES(uni_sale_line,s,a,uni_sale,uni_prod,item_f,1,9500);
 INSERT INTO public.inventory_stock_movements(
  school_id,campus_id,location_id,item_id,lot_id,movement_kind,
  delta_qty,unit_cost_minor,operation_id,posted_by)
 VALUES(s,a,loc_a,item_f,lot_finished,'uniform_sale',-1,2000,
  'aaa00000-0000-4000-8000-000000000017',actor_id);
 INSERT INTO public.inventory_movement_sources(
  movement_id,school_id,campus_id,item_id,movement_kind,uniform_sale_line_id)
 SELECT id,s,a,item_f,'uniform_sale',uni_sale_line
 FROM public.inventory_stock_movements
 WHERE operation_id='aaa00000-0000-4000-8000-000000000017';

 -- Validate both retail sale totals and every stock movement typed source.
 SET CONSTRAINTS ALL IMMEDIATE;
 SET CONSTRAINTS ALL DEFERRED;

 SELECT coalesce(sum(delta_qty),0) INTO stock_a
 FROM public.inventory_stock_movements
 WHERE school_id=s AND campus_id=a AND item_id=item_c;
 SELECT coalesce(sum(delta_qty),0) INTO stock_b
 FROM public.inventory_stock_movements
 WHERE school_id=s AND campus_id=b AND item_id=item_c;
 SELECT coalesce(sum(delta_qty),0) INTO stock_raw
 FROM public.inventory_stock_movements WHERE item_id=item_m;
 SELECT coalesce(sum(delta_qty),0) INTO stock_finished
 FROM public.inventory_stock_movements WHERE item_id=item_f;
 IF stock_a<>5 OR stock_b<>3 OR stock_raw<>16 OR stock_finished<>1 THEN
  RAISE EXCEPTION
   'Stock ledger quantities incorrect: A %, B %, raw %, finished %',
   stock_a,stock_b,stock_raw,stock_finished;
 END IF;

 BEGIN
  INSERT INTO public.inventory_stock_movements(
   school_id,campus_id,location_id,item_id,lot_id,movement_kind,
   delta_qty,unit_cost_minor,operation_id,posted_by)
  VALUES(s,b,loc_b,item_c,lot_a,'goods_receipt',1,500,
   'aaa00000-0000-4000-8000-000000000018',actor_id);
  RAISE EXCEPTION 'CROSS CAMPUS inventory lot accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;

 BEGIN
  INSERT INTO public.inventory_stock_movements(
   school_id,campus_id,location_id,item_id,lot_id,movement_kind,
   delta_qty,unit_cost_minor,operation_id,posted_by)
  VALUES(s,a,loc_a,item_c,lot_a,'adjustment_in',1,500,
   'aaa00000-0000-4000-8000-000000000019',actor_id);
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'Stock movement without typed source accepted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 SET CONSTRAINTS ALL DEFERRED;

 BEGIN
  DELETE FROM public.inventory_stock_movements
   WHERE operation_id='aaa00000-0000-4000-8000-000000000002';
  RAISE EXCEPTION 'Original stock movement was mutable';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  -- CASCADE ensures the integrity trigger, rather than a preemptive FK
  -- TRUNCATE restriction, rejects bulk deletion of posted evidence.
  TRUNCATE public.canteen_sale_lines CASCADE;
  RAISE EXCEPTION 'Retail sale evidence TRUNCATE bypass succeeded';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 -- Transport: enrolled pupil can use only same-campus route and stop.
 INSERT INTO public.transport_routes(id,school_id,campus_id,route_code,route_name)
 VALUES(route_a,s,a,'A1','Main Route A'),
       (route_b,s,b,'B1','Girls Route B');
 INSERT INTO public.transport_route_stops(
  id,school_id,campus_id,route_id,stop_order,stop_name)
 VALUES(stop_a,s,a,route_a,1,'Main Street Stop'),
       (stop_b,s,b,route_b,1,'Girls Street Stop');
 INSERT INTO public.transport_student_assignments(
  school_id,campus_id,academic_year_id,class_id,student_id,enrollment_id,
  route_id,stop_id,starts_on,approved_by,operation_id)
 VALUES(s,a,y,cl,student_id,enrollment_id,route_a,stop_a,
  '2026-04-05',actor_id,'aaa00000-0000-4000-8000-000000000020');
 BEGIN
  -- Temporarily end the valid A route within the negative-test subtransaction
  -- so the one-open-route unique index does not mask the campus FK test.
  UPDATE public.transport_student_assignments SET ends_on='2026-04-06'
   WHERE operation_id='aaa00000-0000-4000-8000-000000000020' AND ends_on IS NULL;
  INSERT INTO public.transport_student_assignments(
   school_id,campus_id,academic_year_id,class_id,student_id,enrollment_id,
   route_id,stop_id,starts_on,approved_by,operation_id)
  VALUES(s,a,y,cl,student_id,enrollment_id,route_b,stop_b,
   '2026-04-07',actor_id,'aaa00000-0000-4000-8000-000000000021');
  RAISE EXCEPTION 'CROSS CAMPUS transport route accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;

 INSERT INTO public.transport_vehicles(
  id,school_id,campus_id,registration_no,capacity)
 VALUES(vehicle,s,a,'FAKE-BUS-001',30);
 INSERT INTO public.employee_departments(id,school_id,code,name)
 VALUES(dept,s,'TRANSPORT','Transport Staff');
 INSERT INTO public.employee_positions(id,school_id,department_id,code,title)
 VALUES(position_id,s,dept,'DRIVER','School Driver');
 INSERT INTO public.employees(
  id,school_id,employee_no,full_name,hired_on,employment_type,created_by)
 VALUES(employee_id,s,'FAKE-DRIVER','Fictional Driver',
  '2026-01-01','permanent',actor_id);
 INSERT INTO public.employee_assignments(
  id,school_id,campus_id,employee_id,department_id,position_id,
  starts_on,approved_by)
 VALUES(emp_assign,s,a,employee_id,dept,position_id,'2026-04-01',actor_id);
 INSERT INTO public.transport_driver_assignments(
  id,school_id,campus_id,vehicle_id,employee_id,employee_assignment_id,
  starts_on,approved_by)
 VALUES(driver_assign,s,a,vehicle,employee_id,emp_assign,'2026-04-01',actor_id);
 INSERT INTO public.transport_trip_logs(
  school_id,campus_id,vehicle_id,route_id,driver_assignment_id,
  trip_date,trip_kind,status,start_odometer_km,end_odometer_km,
  departure_at,arrival_at,operation_id,recorded_by)
 VALUES(s,a,vehicle,route_a,driver_assign,'2026-04-06','pickup','completed',
  100,115,'2026-04-06T07:00:00+00','2026-04-06T07:45:00+00',
  'aaa00000-0000-4000-8000-000000000022',actor_id);
 BEGIN
  INSERT INTO public.transport_trip_logs(
   school_id,campus_id,vehicle_id,route_id,driver_assignment_id,
   trip_date,trip_kind,status,start_odometer_km,end_odometer_km,
   departure_at,arrival_at,operation_id,recorded_by)
  VALUES(s,a,vehicle,route_a,driver_assign,'2026-04-06','pickup','completed',
   115,100,'2026-04-06T09:00:00+00','2026-04-06T09:20:00+00',
   'aaa00000-0000-4000-8000-000000000023',actor_id);
  RAISE EXCEPTION 'Trip with decreasing odometer accepted';
 EXCEPTION WHEN check_violation THEN NULL;
 END;

 INSERT INTO public.transport_maintenance_events(
  id,school_id,campus_id,vehicle_id,maintenance_date,work_kind,
  description,operation_id,recorded_by)
 VALUES(maintenance_id,s,a,vehicle,'2026-04-07','repair',
  'Fictional vehicle safety repair','aaa00000-0000-4000-8000-000000000024',actor_id);
 INSERT INTO public.expense_categories(id,school_id,code,name,expense_kind)
 VALUES(exp_cat,s,'VEHICLE','Vehicle Repairs','operating');
 INSERT INTO public.expense_requests(
  id,school_id,campus_id,category_id,expense_kind,requested_amount_minor,
  expense_date,purpose,requester_id,request_operation_id,
  status,reviewed_by,reviewed_at)
 VALUES(exp_req,s,a,exp_cat,'operating',2000,'2026-04-07',
  'Fictional authorized vehicle repair',actor_id,
  'aaa00000-0000-4000-8000-000000000025',
  'approved',actor_id,now());
 INSERT INTO public.expenses(
  id,school_id,campus_id,category_id,expense_kind,request_id,
  financial_account_id,amount_minor,paid_on,operation_id,posted_by)
 VALUES(posted_expense,s,a,exp_cat,'operating',exp_req,cash_wallet,
  2000,'2026-04-07','aaa00000-0000-4000-8000-000000000026',actor_id);
 INSERT INTO public.transport_expense_links(
  school_id,campus_id,vehicle_id,maintenance_id,expense_id)
 VALUES(s,a,vehicle,maintenance_id,posted_expense);
 IF (SELECT count(*) FROM public.expenses WHERE school_id=s)<>1 THEN
  RAISE EXCEPTION 'Transport maintenance created DUPLICATE expense';
 END IF;

 INSERT INTO public.retail_sale_reversals(
  school_id,campus_id,sale_kind,canteen_sale_id,reversal_operation_id,
  reason,approved_by)
 VALUES(s,a,'canteen',can_sale,'aaa00000-0000-4000-8000-000000000027',
  'Fictional audited sale reversal',actor_id);
 BEGIN
  INSERT INTO public.retail_sale_reversals(
   school_id,campus_id,sale_kind,canteen_sale_id,reversal_operation_id,
   reason,approved_by)
  VALUES(s,a,'canteen',can_sale,'aaa00000-0000-4000-8000-000000000028',
   'Duplicate attempt must fail',actor_id);
  RAISE EXCEPTION 'Same retail sale reversed twice';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;

 INSERT INTO public.db07_operation_receipts(
  school_id,operation_id,action,actor_id,request_sha256,result_json)
 VALUES(s,'aaa00000-0000-4000-8000-000000000029','post_canteen_sale',
  actor_id,decode(repeat('ab',32),'hex'),'{"accepted":true}'::jsonb);
 BEGIN
  UPDATE public.db07_operation_receipts
   SET result_json='{}'::jsonb WHERE school_id=s;
  RAISE EXCEPTION 'Operation receipt was mutable';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 SELECT count(*) INTO n
 FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relrowsecurity AND c.relname IN (
  'inventory_categories','inventory_items','inventory_locations',
  'inventory_suppliers','inventory_purchase_orders','inventory_purchase_lines',
  'inventory_goods_receipts','inventory_receipt_lines','inventory_lots',
  'inventory_transfers','inventory_transfer_lines','inventory_counts',
  'inventory_count_lines','canteen_products','canteen_prices',
  'canteen_sales','canteen_sale_lines','uniform_products',
  'uniform_recipes','uniform_recipe_lines','uniform_production_batches',
  'uniform_material_issues','uniform_production_outputs','uniform_sales',
  'uniform_sale_lines','transport_vehicles','transport_routes',
  'transport_route_stops','transport_student_assignments',
  'transport_driver_assignments','transport_trip_logs',
  'transport_maintenance_events','transport_expense_links',
  'inventory_stock_movements','inventory_movement_sources',
  'retail_sale_reversals','db07_operation_receipts'
 );
 IF n<>37 THEN RAISE EXCEPTION 'DB07 RLS missing: %/37',n; END IF;
 IF pg_catalog.has_table_privilege('authenticated','public.inventory_stock_movements','INSERT')
  OR pg_catalog.has_table_privilege('authenticated','public.uniform_sales','SELECT')
  OR pg_catalog.has_table_privilege('anon','public.transport_student_assignments','SELECT') THEN
  RAISE EXCEPTION 'Unauthenticated or unscoped client granted DB07 table access';
 END IF;
END;
$fixture$;
\echo DB07 fictional schema integrity/RLS fixture passed -- ROLLBACK
ROLLBACK;
