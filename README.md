# LockPilot backend

Database schema, security policies, and automatic enforcement logic for
LockPilot, hosted on Supabase (Postgres + Auth + auto-generated API).

**Status: live.** Unlike the Android app, this has actually been run
against a real database (Supabase project "Lockpilot") and confirmed
working, not just written and hoped-for.

## What's here

Run in order against a fresh Supabase project's SQL Editor:

1. `001_schema.sql` — the 7 core tables: shops, staff, customers, devices,
   installment_plans, payments, lock_events
2. `002_rls.sql` — Row Level Security policies. This is what actually
   enforces multi-tenancy — without it, any logged-in user could read any
   shop's data through Supabase's auto-generated REST API.
3. `003_functions.sql` — the automatic enforcement logic:
   - `evaluate_device_locks()` finds newly-overdue payments and locks
     those devices
   - a trigger on `payments` unlocks a device instantly the moment its
     last overdue payment is recorded as paid
4. `004_cron.sql` — schedules `evaluate_device_locks()` to run every hour,
   forever, via `pg_cron`

## The core mechanic

Every device has a `should_be_locked` boolean — the "desired state."
Nothing in this repo talks to an actual phone; that's Phase 2 (the Android
app needs to be taught to read this value and act on it, likely via a
small sync endpoint plus push notifications for instant delivery).

A payment is "overdue" when `due_date + shop.grace_period_days` has passed
and `paid_date` is still null. That's the only rule locking depends on.

## What's NOT here yet

- **No way for a device to authenticate itself.** `devices.device_secret`
  exists as a column but nothing issues or checks it yet.
- **No dashboard.** This is just the database — a shop owner has no UI to
  add customers, record payments, or see their numbers. That's Phase 3.
- **No push notifications.** `should_be_locked` changing in the database
  doesn't yet reach a phone in real time — needs Firebase Cloud Messaging
  wired up from a Supabase Edge Function.
- **No signup flow.** Creating a new shop + its first staff login is
  currently a manual process via the Supabase dashboard (Authentication
  tab + a manual insert into `staff`), not something a shop owner can do
  themselves yet.

## Local setup

There's no local database — this project runs entirely against the
hosted Supabase project. To apply these migrations to a *different*
Supabase project (e.g. moving from a dev project to production later),
paste each file's contents into that project's SQL Editor, in numeric
order, and run them one at a time.
