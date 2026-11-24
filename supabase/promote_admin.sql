-- Run in the Supabase SQL Editor after replacing the email below.
-- The user must already exist in Authentication > Users.
-- This preserves other app metadata while setting the trusted admin role.
begin;

do $$
declare
  admin_email text := 'admin@gmail.com';
begin
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', 'admin')
  where lower(email) = lower(admin_email);

  if not found then
    raise exception 'No Supabase Auth user found for %', admin_email;
  end if;
end $$;

commit;
