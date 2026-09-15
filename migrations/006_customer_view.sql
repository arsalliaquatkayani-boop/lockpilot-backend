-- Lets a paired device fetch everything its own customer should be able to
-- see about their plan: which shop to contact, how much is paid off, and
-- the full payment history. Same trust model as get_device_lock_state
-- (005_device_sync.sql) — authenticated by the device's own secret, and it
-- can only ever see its own device/plan/payments, nothing else.

create or replace function public.get_device_customer_view(p_device_id uuid, p_device_secret text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device devices%rowtype;
  v_shop shops%rowtype;
  v_plan installment_plans%rowtype;
  v_result json;
begin
  select * into v_device from devices
    where id = p_device_id and device_secret = p_device_secret;

  if not found then
    raise exception 'invalid device credentials';
  end if;

  update devices set last_seen_at = now() where id = p_device_id;

  select * into v_shop from shops where id = v_device.shop_id;

  select * into v_plan from installment_plans
    where device_id = p_device_id
    order by created_at desc
    limit 1;

  select json_build_object(
    'device_label', v_device.device_label,
    'status', v_device.status,
    'should_be_locked', v_device.should_be_locked,
    'shop_name', v_shop.name,
    'shop_phone', v_shop.phone,
    'plan', case when v_plan.id is null then null else json_build_object(
      'total_amount', v_plan.total_amount,
      'down_payment', v_plan.down_payment,
      'installment_amount', v_plan.installment_amount,
      'installment_count', v_plan.installment_count,
      'frequency', v_plan.frequency,
      'start_date', v_plan.start_date,
      'plan_status', v_plan.status,
      'paid_count', (
        select count(*) from payments
        where installment_plan_id = v_plan.id and paid_date is not null
      ),
      'remaining_count', (
        select count(*) from payments
        where installment_plan_id = v_plan.id and paid_date is null
      ),
      'remaining_balance', (
        select coalesce(sum(amount), 0) from payments
        where installment_plan_id = v_plan.id and paid_date is null
      )
    ) end,
    'payments', case when v_plan.id is null then '[]'::json else (
      select coalesce(json_agg(json_build_object(
        'due_date', p.due_date,
        'amount', p.amount,
        'paid_date', p.paid_date
      ) order by p.due_date), '[]'::json)
      from payments p where p.installment_plan_id = v_plan.id
    ) end
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.get_device_customer_view(uuid, text) to anon, authenticated;
