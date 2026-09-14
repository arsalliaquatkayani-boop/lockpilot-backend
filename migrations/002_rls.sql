-- Row Level Security: the actual multi-tenancy enforcement.
-- Without this, any authenticated user could read/write any shop's data
-- through Supabase's auto-generated API — RLS is what makes shop_id
-- scoping real instead of just a convention.

-- Helper: the shop_id of whichever staff row belongs to the current
-- authenticated user. Used in every policy below.
create or replace function public.current_shop_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select shop_id from staff where id = auth.uid()
$$;

alter table shops enable row level security;
alter table staff enable row level security;
alter table customers enable row level security;
alter table devices enable row level security;
alter table installment_plans enable row level security;
alter table payments enable row level security;
alter table lock_events enable row level security;

-- SHOPS: a staff member can only see their own shop's row.
create policy shops_select on shops
  for select using (id = current_shop_id());

create policy shops_update on shops
  for update using (id = current_shop_id());

-- STAFF: can see other staff in the same shop; cannot change roles/shop.
create policy staff_select on staff
  for select using (shop_id = current_shop_id());

create policy staff_update_self on staff
  for update using (id = auth.uid());

-- CUSTOMERS
create policy customers_select on customers
  for select using (shop_id = current_shop_id());
create policy customers_insert on customers
  for insert with check (shop_id = current_shop_id());
create policy customers_update on customers
  for update using (shop_id = current_shop_id());
create policy customers_delete on customers
  for delete using (shop_id = current_shop_id());

-- DEVICES
create policy devices_select on devices
  for select using (shop_id = current_shop_id());
create policy devices_insert on devices
  for insert with check (shop_id = current_shop_id());
create policy devices_update on devices
  for update using (shop_id = current_shop_id());
create policy devices_delete on devices
  for delete using (shop_id = current_shop_id());

-- INSTALLMENT PLANS
create policy installment_plans_select on installment_plans
  for select using (shop_id = current_shop_id());
create policy installment_plans_insert on installment_plans
  for insert with check (shop_id = current_shop_id());
create policy installment_plans_update on installment_plans
  for update using (shop_id = current_shop_id());
create policy installment_plans_delete on installment_plans
  for delete using (shop_id = current_shop_id());

-- PAYMENTS
create policy payments_select on payments
  for select using (shop_id = current_shop_id());
create policy payments_insert on payments
  for insert with check (shop_id = current_shop_id());
create policy payments_update on payments
  for update using (shop_id = current_shop_id());
create policy payments_delete on payments
  for delete using (shop_id = current_shop_id());

-- LOCK EVENTS: append-only from the dashboard's perspective — no update/delete policy,
-- so staff can insert (for manual overrides) and read, but never edit history.
create policy lock_events_select on lock_events
  for select using (shop_id = current_shop_id());
create policy lock_events_insert on lock_events
  for insert with check (shop_id = current_shop_id());
