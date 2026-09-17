-- Lets each shop configure its own Factory Reset Protection recovery
-- account instead of every phone across every shop sharing one. If Shop A's
-- account is ever compromised, only Shop A's phones are affected.

alter table shops add column if not exists frp_recovery_email text;

-- Device-authenticated, same trust model as get_device_lock_state: a phone
-- can only ever read the FRP email for its OWN shop, via its own device
-- credentials, nothing else.
create or replace function public.get_device_frp_email(p_device_id uuid, p_device_secret text)
returns table (frp_recovery_email text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from devices where id = p_device_id and device_secret = p_device_secret
  ) then
    raise exception 'invalid device credentials';
  end if;

  return query
    select s.frp_recovery_email
    from shops s
    join devices d on d.shop_id = s.id
    where d.id = p_device_id and d.device_secret = p_device_secret;
end;
$$;

grant execute on function public.get_device_frp_email(uuid, text) to anon, authenticated;
