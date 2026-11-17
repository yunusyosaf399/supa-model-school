-- Disposable LOCAL CI Supabase Auth identities only; NEVER deploy.
-- These accounts use example.invalid and do not contain real credentials.
BEGIN;
INSERT INTO auth.users(
  id,instance_id,aud,role,email,encrypted_password,
  email_confirmed_at,created_at,updated_at
) VALUES
(
 'c0c0c0c0-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated',
 'sms-adm-admin-a@example.invalid',
 '',now(),now(),now()
),
(
 'c0c0c0c0-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated',
 'sms-adm-reviewer-b@example.invalid',
 '',now(),now(),now()
);
COMMIT;
