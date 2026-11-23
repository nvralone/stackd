-- The username-login Edge Function (server only, secret key) must read profiles to find which account
-- owns a username. Tables here use explicit grants, so the service role needs this one.
grant usage on schema public to service_role;
grant select on public.profiles to service_role;
