-- DB35: add the verified Owner student-rate action to the existing
-- idempotent fee operation-receipt journal. Existing actions are preserved.
alter table public.fee_operation_receipts
  drop constraint fee_operation_receipts_action_check;
alter table public.fee_operation_receipts
  add constraint fee_operation_receipts_action_check
  check(action in (
    'generate_charges','manual_charge','post_receipt','apply_credit',
    'adjust_charge','reverse_receipt','admission_deposit',
    'reassign_collection','verify_bank_submission','student_rate'
  ));
