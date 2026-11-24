-- ============================================================
-- 061_fix_grants_and_accounts.sql
--
-- Ensures standard Supabase roles (anon, authenticated, service_role)
-- have full permissions on public tables, sequences, and functions.
-- Also ensures all existing auth users have their account and profile
-- created and linked.
-- ============================================================

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- Grant permissions on all existing objects in public schema
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO postgres, anon, authenticated, service_role;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO postgres, anon, authenticated, service_role;

-- Backfill: Ensure accounts exist for any users in auth.users
INSERT INTO public.accounts (name, owner_user_id)
SELECT
  COALESCE(NULLIF(u.raw_user_meta_data->>'full_name', ''), split_part(u.email, '@', 1), 'Personal') || '''s Workspace',
  u.id
FROM auth.users u
WHERE NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.owner_user_id = u.id)
ON CONFLICT (owner_user_id) DO NOTHING;

-- Backfill: Ensure profiles exist for any users in auth.users
INSERT INTO public.profiles (user_id, full_name, email, account_id, account_role)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1), 'User'),
  COALESCE(u.email, ''),
  a.id,
  'owner'::account_role_enum
FROM auth.users u
JOIN public.accounts a ON a.owner_user_id = u.id
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id = u.id)
ON CONFLICT (user_id) DO NOTHING;

-- Backfill: Link any profiles that have missing account_id or account_role
UPDATE public.profiles p
SET
  account_id = a.id,
  account_role = 'owner'::account_role_enum
FROM public.accounts a
WHERE a.owner_user_id = p.user_id
  AND (p.account_id IS NULL OR p.account_role IS NULL);
