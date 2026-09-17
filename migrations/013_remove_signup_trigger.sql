-- Security fix: the trigger below created a shop for ANY signup whose
-- client-supplied metadata happened to include a shop_name — including a
-- raw call to Supabase's public signUp() API made directly, completely
-- bypassing the website. That's a real self-registration backdoor, and the
-- whole point of the admin-only "Add shop" flow is that nobody should be
-- able to create a shop except through it.
--
-- admin-create-shop now inserts the shop + staff rows itself, using the
-- service_role client (see lockpilot-backend/supabase/functions/admin-create-shop),
-- right after creating the invited user — so this trigger is no longer
-- needed by anything legitimate.
drop trigger if exists on_auth_user_created_create_shop on auth.users;
drop function if exists public.handle_new_shop_signup();
