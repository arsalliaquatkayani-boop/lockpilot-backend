-- The automatic enforcement logic. Two mechanisms:
--   1. evaluate_device_locks() — run on a schedule (see 004_cron.sql), finds
--      newly-overdue payments and locks those devices.
--   2. trg_payment_recorded — fires the instant a payment is marked paid,
--      so unlocking feels immediate rather than waiting for the next
--      scheduled run (matches the "unlocks the same second" promise).
--
-- Both write to devices.should_be_locked (the desired state Phase 2's
-- Android sync will read) and log to lock_events for the audit trail.

create or replace function public.evaluate_device_locks()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  -- Lock any device with a payment overdue past its shop's grace period,
  -- that isn't already marked locked.
  for r in
    select distinct d.id as device_id, d.shop_id
    from devices d
    join installment_plans ip on ip.device_id = d.id and ip.status = 'active'
    join shops s on s.id = d.shop_id
    join payments p on p.installment_plan_id = ip.id
    where p.paid_date is null
      and p.due_date < (current_date - s.grace_period_days)
      and d.should_be_locked = false
  loop
    update devices
      set should_be_locked = true, status = 'locked'
      where id = r.device_id;

    insert into lock_events (shop_id, device_id, event_type, trigger)
    values (r.shop_id, r.device_id, 'locked', 'overdue_payment');
  end loop;

  -- Safety net: unlock any device that's marked locked but no longer has
  -- any actually-overdue payment (covers anything trg_payment_recorded missed).
  for r in
    select d.id as device_id, d.shop_id
    from devices d
    join shops s on s.id = d.shop_id
    where d.should_be_locked = true
      and not exists (
        select 1
        from installment_plans ip
        join payments p on p.installment_plan_id = ip.id
        where ip.device_id = d.id
          and ip.status = 'active'
          and p.paid_date is null
          and p.due_date < (current_date - s.grace_period_days)
      )
  loop
    update devices
      set should_be_locked = false, status = 'active'
      where id = r.device_id;

    insert into lock_events (shop_id, device_id, event_type, trigger)
    values (r.shop_id, r.device_id, 'unlocked', 'payment_received');
  end loop;
end;
$$;

-- Instant unlock the moment a payment is recorded as paid, if that clears
-- every overdue payment on the device.
create or replace function public.on_payment_recorded()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device_id uuid;
  v_shop_id uuid;
  v_still_overdue boolean;
begin
  if new.paid_date is not null and old.paid_date is null then
    select ip.device_id, d.shop_id into v_device_id, v_shop_id
    from installment_plans ip
    join devices d on d.id = ip.device_id
    where ip.id = new.installment_plan_id;

    select exists (
      select 1
      from payments p2
      join installment_plans ip2 on ip2.id = p2.installment_plan_id
      join shops s on s.id = v_shop_id
      where ip2.device_id = v_device_id
        and ip2.status = 'active'
        and p2.paid_date is null
        and p2.due_date < (current_date - s.grace_period_days)
    ) into v_still_overdue;

    if not v_still_overdue then
      update devices
        set should_be_locked = false, status = 'active'
        where id = v_device_id and should_be_locked = true;

      if found then
        insert into lock_events (shop_id, device_id, event_type, trigger, triggered_by)
        values (v_shop_id, v_device_id, 'unlocked', 'payment_received', new.recorded_by);
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_payment_recorded
  after update on payments
  for each row
  execute function public.on_payment_recorded();
