-- Runs the overdue check every hour, automatically, forever — this is what
-- makes locking "automatic" instead of something a human has to trigger.
--
-- NOTE: pg_cron sometimes needs to be turned on from the Supabase dashboard
-- (Database → Extensions → search "pg_cron" → Enable) rather than by SQL,
-- depending on your project's settings. If the "create extension" line
-- below fails, do that first, then re-run just this file.

create extension if not exists pg_cron;

select cron.schedule(
  'evaluate-device-locks-hourly',
  '0 * * * *',  -- top of every hour
  $$select public.evaluate_device_locks();$$
);
