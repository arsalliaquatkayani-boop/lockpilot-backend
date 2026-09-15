-- Instant lock/unlock delivery: right now the phone only learns about a
-- should_be_locked change on its next 15-minute background check. This adds
-- a push-notification "doorbell" so the phone re-checks within seconds
-- instead of waiting — the push itself carries no lock state, it just tells
-- the phone "go check now", so the phone's own secure check
-- (get_device_lock_state) stays the single source of truth either way.

create extension if not exists pg_net;
create extension if not exists supabase_vault;

alter table devices add column if not exists fcm_token text;

-- Lets a paired device register its own push token. Same trust model as
-- every other device-facing function: authenticated by the device's own
-- secret, can only ever touch its own row.
create or replace function public.register_fcm_token(p_device_id uuid, p_device_secret text, p_fcm_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update devices
    set fcm_token = p_fcm_token
    where id = p_device_id and device_secret = p_device_secret;

  if not found then
    raise exception 'invalid device credentials';
  end if;
end;
$$;

grant execute on function public.register_fcm_token(uuid, text, text) to anon, authenticated;

-- Fires the push the instant should_be_locked changes for any reason —
-- a manual Lock/Unlock click on the dashboard, the hourly overdue sweep in
-- evaluate_device_locks(), or the instant-unlock trigger in
-- on_payment_recorded(). All three just update this one column, so hooking
-- in here covers every path with no changes needed anywhere else.
create or replace function public.notify_lock_state_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_function_url text;
begin
  if new.fcm_token is null then
    return new;
  end if;
  if new.should_be_locked is not distinct from old.should_be_locked then
    return new;
  end if;

  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'fcm_trigger_secret';
  select decrypted_secret into v_function_url
    from vault.decrypted_secrets where name = 'fcm_push_function_url';

  if v_secret is null or v_function_url is null then
    -- Not configured yet — push notifications are optional; the 15-minute
    -- background check still works as the fallback either way.
    return new;
  end if;

  perform net.http_post(
    url := v_function_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-trigger-secret', v_secret),
    body := jsonb_build_object(
      'fcm_token', new.fcm_token,
      'device_label', new.device_label,
      'should_be_locked', new.should_be_locked
    )
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_lock_state_changed on devices;
create trigger trg_notify_lock_state_changed
  after update on devices
  for each row
  execute function public.notify_lock_state_changed();
