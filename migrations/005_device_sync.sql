-- Phase 2: lets a paired Android device check its own lock state without a
-- Supabase Auth session, using the device_secret issued when it was added
-- on the dashboard. This is the only way a phone talks to this database —
-- it can only ever read its own should_be_locked value, nothing else.

alter table devices
  alter column device_secret set default encode(gen_random_bytes(16), 'hex');

-- Backfill any device rows created before this migration (including ones
-- added via the dashboard before this existed).
update devices set device_secret = encode(gen_random_bytes(16), 'hex')
  where device_secret is null;

create or replace function public.get_device_lock_state(p_device_id uuid, p_device_secret text)
returns table (should_be_locked boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  update devices
    set last_seen_at = now()
    where id = p_device_id and device_secret = p_device_secret;

  if not found then
    raise exception 'invalid device credentials';
  end if;

  return query
    select d.should_be_locked from devices d
    where d.id = p_device_id and d.device_secret = p_device_secret;
end;
$$;

-- anon (the publishable key the Android app ships with) must be able to call
-- this — that's the whole point. It can still only ever affect/see the one
-- device row whose secret it presents.
grant execute on function public.get_device_lock_state(uuid, text) to anon, authenticated;
