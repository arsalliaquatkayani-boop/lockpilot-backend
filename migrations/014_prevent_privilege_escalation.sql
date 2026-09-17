-- CRITICAL FIX — two real cross-tenant data breach paths.
--
-- 1) staff_update_self (002_rls.sql) lets a staff member update their own
--    row using only `id = auth.uid()`. Postgres RLS defaults an omitted
--    WITH CHECK to match USING — which re-validates `id`, not `shop_id` or
--    `role`. Nothing stopped any logged-in staff member (owner or plain
--    staff) from running an update that set their OWN shop_id to a
--    DIFFERENT shop's UUID, or their own role to 'owner' — since
--    current_shop_id() just reads shop_id off this same row, that
--    immediately grants full read/write access to that other shop's
--    customers, devices and payments.
--
-- 2) shops_update (002_rls.sql) lets any staff member update every column
--    on their own shop row, including the plan/billing_status/payment
--    columns added in 011 — so a shop could just set its own billing_status
--    to 'active' and plan to 'pro' itself, bypassing billing entirely.
--
-- Both are fixed the same way: a trigger that blocks changes to the
-- sensitive columns unless the caller is a platform admin, since RLS
-- policies alone can't restrict which columns an otherwise-permitted
-- UPDATE is allowed to touch.

create or replace function public.prevent_staff_privilege_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if is_platform_admin() then
    return new;
  end if;

  if new.shop_id is distinct from old.shop_id then
    raise exception 'Cannot change shop_id';
  end if;

  if new.role is distinct from old.role then
    raise exception 'Cannot change role';
  end if;

  return new;
end;
$$;

create trigger trg_prevent_staff_privilege_escalation
  before update on staff
  for each row
  execute function public.prevent_staff_privilege_escalation();

create or replace function public.prevent_shop_billing_tampering()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if is_platform_admin() then
    return new;
  end if;

  if new.plan is distinct from old.plan
    or new.billing_status is distinct from old.billing_status
    or new.next_payment_due is distinct from old.next_payment_due
    or new.last_payment_date is distinct from old.last_payment_date
  then
    raise exception 'Only LockPilot admin can change plan or billing status';
  end if;

  return new;
end;
$$;

create trigger trg_prevent_shop_billing_tampering
  before update on shops
  for each row
  execute function public.prevent_shop_billing_tampering();
