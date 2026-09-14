-- LockPilot core schema.
-- Multi-tenant: every business table carries shop_id and is locked down by
-- Row Level Security in 002_rls.sql — a shop can only ever see its own data.

create extension if not exists pgcrypto; -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- SHOPS
-- ---------------------------------------------------------------------
create table shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  address text,
  grace_period_days int not null default 3,
  created_at timestamptz not null default now()
);

comment on column shops.grace_period_days is
  'Days after a due_date before a missed payment counts as overdue for locking purposes.';

-- ---------------------------------------------------------------------
-- STAFF
-- One row per shop staff login, keyed to Supabase's own auth.users table.
-- ---------------------------------------------------------------------
create table staff (
  id uuid primary key references auth.users (id) on delete cascade,
  shop_id uuid not null references shops (id) on delete cascade,
  full_name text,
  role text not null default 'staff' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now()
);

create index staff_shop_id_idx on staff (shop_id);

-- ---------------------------------------------------------------------
-- CUSTOMERS
-- ---------------------------------------------------------------------
create table customers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops (id) on delete cascade,
  full_name text not null,
  phone text,
  city text,
  address text,
  created_at timestamptz not null default now()
);

create index customers_shop_id_idx on customers (shop_id);

-- ---------------------------------------------------------------------
-- DEVICES
-- should_be_locked is the "desired state" the Android app is expected to
-- converge to — the app reads this (directly or via a sync endpoint built
-- in Phase 2) and locks/unlocks itself to match it.
-- ---------------------------------------------------------------------
create table devices (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops (id) on delete cascade,
  customer_id uuid references customers (id) on delete set null,
  device_label text,
  imei text,
  android_device_id text unique,
  device_secret text,
  cost_price numeric(12, 2),
  sale_price numeric(12, 2),
  status text not null default 'active'
    check (status in ('active', 'locked', 'paid_off', 'inactive')),
  should_be_locked boolean not null default false,
  last_seen_at timestamptz,
  last_known_location jsonb,
  provisioned_at timestamptz,
  created_at timestamptz not null default now()
);

create index devices_shop_id_idx on devices (shop_id);
create index devices_customer_id_idx on devices (customer_id);

comment on column devices.android_device_id is
  'Identifier the Android app presents once provisioned — not set until Phase 2 pairing exists.';
comment on column devices.device_secret is
  'Credential the device uses to authenticate its own API calls — wiring comes in Phase 2.';

-- ---------------------------------------------------------------------
-- INSTALLMENT PLANS
-- ---------------------------------------------------------------------
create table installment_plans (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops (id) on delete cascade,
  device_id uuid not null references devices (id) on delete cascade,
  customer_id uuid not null references customers (id) on delete cascade,
  total_amount numeric(12, 2) not null,
  down_payment numeric(12, 2) not null default 0,
  installment_amount numeric(12, 2) not null,
  installment_count int not null,
  frequency text not null default 'monthly' check (frequency in ('weekly', 'monthly')),
  start_date date not null,
  status text not null default 'active' check (status in ('active', 'completed', 'defaulted')),
  created_at timestamptz not null default now()
);

create index installment_plans_shop_id_idx on installment_plans (shop_id);
create index installment_plans_device_id_idx on installment_plans (device_id);

-- ---------------------------------------------------------------------
-- PAYMENTS
-- One row per expected installment. paid_date is null until it's paid —
-- that's what makes a payment "overdue" once due_date + grace period passes.
-- ---------------------------------------------------------------------
create table payments (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops (id) on delete cascade,
  installment_plan_id uuid not null references installment_plans (id) on delete cascade,
  amount numeric(12, 2) not null,
  due_date date not null,
  paid_date date,
  recorded_by uuid references staff (id) on delete set null,
  created_at timestamptz not null default now()
);

create index payments_shop_id_idx on payments (shop_id);
create index payments_installment_plan_id_idx on payments (installment_plan_id);
create index payments_due_date_idx on payments (due_date) where paid_date is null;

-- ---------------------------------------------------------------------
-- LOCK EVENTS
-- Full audit trail — every automatic or manual lock/unlock is recorded here.
-- ---------------------------------------------------------------------
create table lock_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops (id) on delete cascade,
  device_id uuid not null references devices (id) on delete cascade,
  event_type text not null check (
    event_type in ('locked', 'unlocked', 'manual_lock', 'manual_unlock')
  ),
  trigger text,
  triggered_by uuid references staff (id) on delete set null,
  created_at timestamptz not null default now()
);

create index lock_events_shop_id_idx on lock_events (shop_id);
create index lock_events_device_id_idx on lock_events (device_id);
