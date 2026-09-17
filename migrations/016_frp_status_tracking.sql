-- Visibility fix: today's testing found that FrpSetupWorker could be
-- silently killed by aggressive OEM battery management (confirmed on
-- MIUI/Android Go) before it ever applied the recovery-account policy —
-- with nothing telling anyone it hadn't happened. A phone could look fully
-- set up and have zero real FRP protection. This column + function let the
-- phone report back the moment it actually succeeds, so the dashboard can
-- show real confirmation instead of an assumption.

alter table devices add column if not exists frp_applied_at timestamptz;

create or replace function public.report_frp_applied(p_device_id uuid, p_device_secret text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update devices
    set frp_applied_at = now()
    where id = p_device_id and device_secret = p_device_secret;

  if not found then
    raise exception 'invalid device credentials';
  end if;
end;
$$;

grant execute on function public.report_frp_applied(uuid, text) to anon, authenticated;
