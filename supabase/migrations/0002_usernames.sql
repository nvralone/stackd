-- Usernames (non-destructive: adds one nullable column, two functions; no existing data is changed).
-- A username is optional, unique (case-insensitive, stored lower-case), 3-20 chars of a-z 0-9 _ .
alter table public.profiles add column if not exists username text;
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username is null or username ~ '^[a-z0-9_.]{3,20}$');
create unique index if not exists profiles_username_key on public.profiles (username) where username is not null;

-- Is a username free? Only answers yes/no; never reveals who owns it.
create or replace function public.username_available(u text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where username = lower(trim(u)));
$$;
revoke all on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;

-- Claim or change your own username (signed-in users only).
create or replace function public.claim_username(u text) returns text
language plpgsql security definer set search_path = public as $$
declare v text := lower(trim(u));
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if v !~ '^[a-z0-9_.]{3,20}$' then raise exception 'Username must be 3-20 letters, numbers, _ or .'; end if;
  if exists (select 1 from public.profiles where username = v and user_id <> auth.uid()) then
    raise exception 'That username is taken';
  end if;
  insert into public.profiles (id, user_id, username) values (auth.uid(), auth.uid(), v)
    on conflict (id) do update set username = excluded.username;
  return v;
end $$;
revoke all on function public.claim_username(text) from public, anon;
grant execute on function public.claim_username(text) to authenticated;

-- Username sign-in happens in the Edge Function supabase/functions/username-login (server side), so a
-- username is never turned into an email address on anyone's device.
