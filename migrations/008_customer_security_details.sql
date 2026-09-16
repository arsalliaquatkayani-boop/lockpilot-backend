-- Adds identity-verification fields to customers (CNIC number + a private
-- storage bucket for CNIC photo copies) plus a guarantor/reference contact,
-- since a shop's real recourse against a defaulting customer depends on
-- having verified who they actually are.

alter table customers
  add column if not exists cnic_number text,
  add column if not exists cnic_front_path text,
  add column if not exists cnic_back_path text,
  add column if not exists guarantor_name text,
  add column if not exists guarantor_phone text;

-- Private bucket for CNIC photo copies. NOT public — CNIC images are
-- sensitive government-ID scans, so they must only ever be reachable via a
-- short-lived signed URL generated for a logged-in staff member, never a
-- plain public link.
insert into storage.buckets (id, name, public)
values ('customer-documents', 'customer-documents', false)
on conflict (id) do nothing;

-- Files are stored at "{shop_id}/{customer_id}-front.jpg" (and "-back.jpg").
-- These policies reuse current_shop_id() from 002_rls.sql so a staff member
-- can only upload/view/replace files inside their own shop's folder.
create policy "customer_documents_select" on storage.objects
  for select using (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = current_shop_id()::text
  );

create policy "customer_documents_insert" on storage.objects
  for insert with check (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = current_shop_id()::text
  );

create policy "customer_documents_update" on storage.objects
  for update using (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = current_shop_id()::text
  );

create policy "customer_documents_delete" on storage.objects
  for delete using (
    bucket_id = 'customer-documents'
    and (storage.foldername(name))[1] = current_shop_id()::text
  );
