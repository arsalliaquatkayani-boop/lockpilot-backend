-- New-device email verification.
-- A login only needs an emailed one-time code the first time it happens
-- from a given browser — the website generates a random device_token and
-- keeps it in localStorage. Once that token is recorded here, future
-- logins from the same browser skip the OTP step. Covers both shop staff
-- and platform admins (keyed to auth.users directly, not the staff table).

create table trusted_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  device_token uuid not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  unique (user_id, device_token)
);

create index trusted_devices_user_id_idx on trusted_devices (user_id);

alter table trusted_devices enable row level security;

create policy trusted_devices_select on trusted_devices
  for select using (user_id = auth.uid());
create policy trusted_devices_insert on trusted_devices
  for insert with check (user_id = auth.uid());
create policy trusted_devices_update on trusted_devices
  for update using (user_id = auth.uid());
