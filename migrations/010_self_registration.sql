-- Self-service shop registration.
-- The dashboard's /app/register form calls supabase.auth.signUp() with
-- shop_name / shop_phone / full_name in the user's metadata. This trigger
-- fires the moment the new auth.users row lands and provisions the shop +
-- owner staff row automatically — no manual setup needed on our end.

create or replace function public.handle_new_shop_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_shop_id uuid;
begin
  -- Staff added to an existing shop some other way won't carry this
  -- metadata — only self-registration signups should create a new shop.
  if new.raw_user_meta_data ->> 'shop_name' is null then
    return new;
  end if;

  if exists (select 1 from staff where id = new.id) then
    return new;
  end if;

  insert into shops (name, phone)
  values (
    new.raw_user_meta_data ->> 'shop_name',
    new.raw_user_meta_data ->> 'shop_phone'
  )
  returning id into new_shop_id;

  insert into staff (id, shop_id, full_name, role)
  values (
    new.id,
    new_shop_id,
    new.raw_user_meta_data ->> 'full_name',
    'owner'
  );

  return new;
end;
$$;

create trigger on_auth_user_created_create_shop
  after insert on auth.users
  for each row
  execute function public.handle_new_shop_signup();
