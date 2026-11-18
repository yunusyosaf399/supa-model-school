-- DB29F: Owner-only expense review is not a delegable staff capability.
-- Staff can be granted expenses.create/read/pay; approvals remain Owner-only.
update app_private.sms_permission_catalog set is_implemented=false where code='expenses.review';
