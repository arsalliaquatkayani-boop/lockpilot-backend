-- Two additions to the device + installment plan creation form:
--
-- 1. Some phones (dual-SIM especially) have more than one IMEI. Adds an
--    "imeis" array column alongside the original single "imei" column
--    (kept as-is, unused going forward, for backward compatibility) and
--    backfills it from any IMEI already on file.
--
-- 2. Shops want every customer's payment due on a fixed day of the month
--    (e.g. always the 5th), independent of the day they happened to buy
--    the phone. Adds an optional "due_day_of_month" on installment_plans;
--    when set, the app's schedule builder uses that day instead of the
--    plan's start-date day for monthly plans.

alter table devices
  add column if not exists imeis text[] default '{}'::text[];

update devices
  set imeis = array[imei]
  where imei is not null and imei <> '' and imeis = '{}'::text[];

alter table installment_plans
  add column if not exists due_day_of_month smallint;

alter table installment_plans
  add constraint installment_plans_due_day_of_month_check
  check (due_day_of_month is null or (due_day_of_month between 1 and 31));
