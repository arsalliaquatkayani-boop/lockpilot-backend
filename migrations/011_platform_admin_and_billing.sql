-- Master LockPilot admin panel: a small team (not shop staff) who can see
-- and manage every shop — creating new shops, tracking their LockPilot
-- subscription plan/payment status. Bootstrapped manually (see README);
-- there's no self-service way to become one.

create table platform_admins (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  created_at timestamptz not null default now()
);

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from platform_admins where id = auth.uid())
$$;

alter table platform_admins enable row level security;

create policy platform_admins_select_self on platform_admins
  for select using (id = auth.uid());

-- ---------------------------------------------------------------------
-- SHOP BILLING — manual tracking for now, no live payment gateway.
-- ---------------------------------------------------------------------
alter table shops
  add column plan text not null default 'trial' check (plan in ('trial', 'basic', 'pro')),
  add column billing_status text not null default 'active' check (billing_status in ('active', 'overdue', 'suspended')),
  add column next_payment_due date,
  add column last_payment_date date;

-- Platform admins can see and manage every shop, on top of the existing
-- "staff can see their own shop" policies from 002_rls.sql.
create policy shops_admin_select on shops
  for select using (is_platform_admin());
create policy shops_admin_insert on shops
  for insert with check (is_platform_admin());
create policy shops_admin_update on shops
  for update using (is_platform_admin());

-- Platform admins can also see who staffs each shop (name/role), to show
-- an owner's name on the admin dashboard — but nothing about that shop's
-- own customers, which stays fully off-limits to keep tenant data private.
create policy staff_admin_select on staff
  for select using (is_platform_admin());

-- staff.email lets the admin dashboard show/contact a shop owner without
-- a separate admin-API call. Populated going forward by the signup
-- trigger below; backfilled once here for any existing rows.
alter table staff add column email text;

update staff
set email = u.email
from auth.users u
where staff.id = u.id and staff.email is null;

create or replace function public.handle_new_shop_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_shop_id uuid;
begin
  if new.raw_user_meta_data ->> 'shop_name' is null then
    return new;
  end if;

  if exists (select 1 from staff where id = new.id) then
    return new;
  end if;

  insert into shops (name, phone)
  values (
    new.raw_user_meta_data ->> 'shop_name',
    new.raw_user_meta_data ->> 'shop_phone'
  )
  returning id into new_shop_id;

  insert into staff (id, shop_id, full_name, role, email)
  values (
    new.id,
    new_shop_id,
    new.raw_user_meta_data ->> 'full_name',
    'owner',
    new.email
  );

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Aggregate shop stats for the admin dashboard. Deliberately exposes only
-- counts, not row-level customer/device data — platform admins manage
-- billing, not a given shop's actual customer records.
-- ---------------------------------------------------------------------
create or replace function public.admin_shop_stats(target_shop_id uuid)
returns table (
  customers_count bigint,
  devices_count bigint,
  active_plans_count bigint,
  locked_devices_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from customers where shop_id = target_shop_id),
    (select count(*) from devices where shop_id = target_shop_id),
    (select count(*) from installment_plans where shop_id = target_shop_id and status = 'active'),
    (select count(*) from devices where shop_id = target_shop_id and status = 'locked')
  where is_platform_admin()
$$;
