-- STACKD initial schema
-- Money is always bigint cents. Balances are never stored: they are derived from ledger_events.
-- ledger_events is append-only (no UPDATE/DELETE policies). Edits = reversal + replacement event.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- helpers
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------- profiles / preferences
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  user_id         uuid not null unique references auth.users(id) on delete cascade,
  display_name    text,
  currency        text not null default 'USD' check (char_length(currency) = 3),
  week_start      smallint not null default 1 check (week_start between 1 and 7), -- ISO: 1 = Monday
  theme           text not null default 'dark' check (theme in ('dark','light','system')),
  clover          jsonb not null default '{}'::jsonb,   -- personality, voice volume, mute, frequency, subtitles
  notifications   jsonb not null default '{}'::jsonb,   -- toggles + quiet hours
  onboarded       boolean not null default false,
  deleted         boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (id = user_id)
);

-- ---------------------------------------------------------------- manual money accounts
create table public.money_accounts (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name        text not null check (char_length(name) between 1 and 60),
  kind        text not null check (kind in ('cash','venmo','cashapp','checking','savings','custom')),
  color       integer not null default 4285132974,
  archived    boolean not null default false,
  sort        integer not null default 0,
  deleted     boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.money_accounts (user_id, updated_at);

-- ---------------------------------------------------------------- budget categories
create table public.categories (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name        text not null check (char_length(name) between 1 and 40),
  color       integer not null,
  icon        integer not null default 0,
  limit_cents bigint check (limit_cents is null or limit_cents >= 0),
  period      text not null default 'weekly' check (period in ('weekly','monthly')),
  rollover    boolean not null default false,
  essential   boolean not null default false,  -- essentials never trigger Clover scolding
  tag         text,                            -- e.g. 'fast_food' for analytics hooks
  archived    boolean not null default false,
  sort        integer not null default 0,
  deleted     boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index on public.categories (user_id, updated_at);

-- ---------------------------------------------------------------- income schedules
create table public.income_schedules (
  id             uuid primary key,
  user_id        uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name           text not null,
  frequency      text not null check (frequency in ('weekly','biweekly','semimonthly','monthly','irregular')),
  anchor_date    date not null,
  expected_cents bigint not null default 0 check (expected_cents >= 0),
  account_id     uuid references public.money_accounts(id) on delete set null,
  active         boolean not null default true,
  deleted        boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on public.income_schedules (user_id, updated_at);

-- ---------------------------------------------------------------- savings vaults
create table public.savings_goals (
  id                 uuid primary key,
  user_id            uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name               text not null check (char_length(name) between 1 and 60),
  goal_cents         bigint not null check (goal_cents > 0),
  target_date        date,
  contribution_cents bigint not null default 0 check (contribution_cents >= 0),
  contribution_freq  text not null default 'payday' check (contribution_freq in ('payday','weekly','monthly','none')),
  locked             boolean not null default false,
  color              integer not null default 4283215696,
  trip_id            uuid,
  archived           boolean not null default false,
  deleted            boolean not null default false,
  client_updated_at  timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index on public.savings_goals (user_id, updated_at);

-- ---------------------------------------------------------------- bills & debts
create table public.bills (
  id              uuid primary key,
  user_id         uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name            text not null,
  kind            text not null check (kind in ('recurring','one_time','debt_owed','debt_lent')),
  amount_cents    bigint not null check (amount_cents > 0),     -- per payment
  frequency       text not null check (frequency in ('once','weekly','biweekly','monthly','yearly')),
  first_due       date not null,
  payment_count   integer check (payment_count is null or payment_count > 0), -- null = open-ended
  principal_cents bigint check (principal_cents is null or principal_cents >= 0),
  fee_cents       bigint not null default 0 check (fee_cents >= 0),
  counterparty    text,
  category_id     uuid references public.categories(id) on delete set null,
  account_id      uuid references public.money_accounts(id) on delete set null,
  reminder_days   smallint not null default 2 check (reminder_days between 0 and 30),
  archived        boolean not null default false,
  deleted         boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.bills (user_id, updated_at);

create table public.bill_overrides (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade default auth.uid(),
  bill_id     uuid not null references public.bills(id) on delete cascade,
  occurrence  integer not null check (occurrence >= 0),
  due_on      date,
  skipped     boolean not null default false,
  deleted     boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (bill_id, occurrence)
);
create index on public.bill_overrides (user_id, updated_at);

-- ---------------------------------------------------------------- budget allocations
-- Extra budget assigned to a category for one period (e.g. part of an Extra Money split).
-- Budget periods themselves are derived (week_start / calendar month), so they need no table.
create table public.budget_allocations (
  id           uuid primary key,
  user_id      uuid not null references auth.users(id) on delete cascade default auth.uid(),
  category_id  uuid not null references public.categories(id) on delete cascade,
  period_start date not null,
  amount_cents bigint not null check (amount_cents > 0),
  group_id     uuid,
  note         text,
  deleted      boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on public.budget_allocations (user_id, updated_at);

-- ---------------------------------------------------------------- vacations (shareable)
create table public.trips (
  id            uuid primary key,
  owner_id      uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name          text not null,
  destination   text,
  depart_on     date,
  return_on     date,
  budget_cents  bigint not null default 0 check (budget_cents >= 0),
  shared        boolean not null default false,
  archived      boolean not null default false,
  deleted       boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (return_on is null or depart_on is null or return_on >= depart_on)
);
create index on public.trips (owner_id, updated_at);

alter table public.savings_goals
  add constraint savings_goals_trip_fk foreign key (trip_id) references public.trips(id) on delete set null;

create table public.trip_members (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','member')),
  status     text not null default 'invited' check (status in ('invited','accepted')),
  created_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);

create table public.trip_budget_items (
  id            uuid primary key,
  trip_id       uuid not null references public.trips(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade default auth.uid(),
  category      text not null, -- transportation, flights, accommodation, food, activities, shopping, emergency, custom
  label         text,
  planned_cents bigint not null default 0 check (planned_cents >= 0),
  deleted       boolean not null default false,
  client_updated_at timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on public.trip_budget_items (trip_id, updated_at);

-- Shared ledger for a trip. Each row optionally points to the payer's private ledger event,
-- so the payer's money is counted once in their ledger and once (as a shared view) here.
create table public.trip_entries (
  id              uuid primary key,
  trip_id         uuid not null references public.trips(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade default auth.uid(),
  kind            text not null check (kind in ('contribution','withdrawal','expense')),
  item_id         uuid references public.trip_budget_items(id) on delete set null,
  amount_cents    bigint not null check (amount_cents > 0),
  occurred_on     date not null,
  note            text,
  ledger_event_id uuid unique,          -- one shared row per private event: prevents double counting
  reverses_id     uuid references public.trip_entries(id),
  created_at      timestamptz not null default now()
);
create index on public.trip_entries (trip_id, created_at);

-- ---------------------------------------------------------------- the ledger (immutable)
create table public.ledger_events (
  id               uuid primary key,          -- client generated: idempotent inserts
  user_id          uuid not null references auth.users(id) on delete cascade default auth.uid(),
  kind             text not null check (kind in (
                     'opening','adjustment','income','refund','expense','transfer',
                     'goal_deposit','goal_withdraw','bill_payment','loan_out','loan_in','reversal')),
  occurred_on      date not null,
  amount_cents     bigint not null check (amount_cents <> 0),
  account_id       uuid references public.money_accounts(id),
  to_account_id    uuid references public.money_accounts(id),
  category_id      uuid references public.categories(id),
  goal_id          uuid references public.savings_goals(id),
  bill_id          uuid references public.bills(id),
  bill_occurrence  integer,
  trip_id          uuid references public.trips(id) on delete set null,
  income_source    text check (income_source in ('paycheck','side_job','tip','gift','sale','loan','other')),
  reason           text check (reason in ('planned','emergency','other')),
  group_id         uuid,                      -- splits created together share a group
  reverses_id      uuid references public.ledger_events(id),
  replaces_id      uuid references public.ledger_events(id),
  note             text check (note is null or char_length(note) <= 500),
  device_id        text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (amount_cents > 0 or kind in ('opening','adjustment')),
  check (kind <> 'transfer' or (account_id is not null and to_account_id is not null and account_id <> to_account_id)),
  check (kind not in ('goal_deposit','goal_withdraw') or goal_id is not null),
  check (kind <> 'reversal' or reverses_id is not null),
  check (kind not in ('income','refund','expense','transfer','bill_payment','loan_out','loan_in','opening','adjustment') or account_id is not null)
);
create index on public.ledger_events (user_id, updated_at);
create index on public.ledger_events (user_id, occurred_on);
create unique index ledger_one_reversal on public.ledger_events (reverses_id) where reverses_id is not null;

-- ---------------------------------------------------------------- Clover dialogue history
create table public.clover_events (
  id         uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  topic      text not null,
  line_id    text not null,
  mood       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.clover_events (user_id, updated_at);

-- ---------------------------------------------------------------- audit log (server side)
create table public.audit_log (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users(id) on delete cascade,
  table_name text not null,
  row_id     text not null,
  action     text not null,
  old_row    jsonb,
  new_row    jsonb,
  at         timestamptz not null default now()
);
create index on public.audit_log (user_id, at);

create or replace function public.write_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid := coalesce(auth.uid(), (to_jsonb(coalesce(new, old))->>'user_id')::uuid,
                             (to_jsonb(coalesce(new, old))->>'owner_id')::uuid);
begin
  insert into public.audit_log(user_id, table_name, row_id, action, old_row, new_row)
  values (uid, tg_table_name, coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id'), tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

-- Triggers: updated_at + audit on every mutable table
do $$
declare t text;
begin
  foreach t in array array['profiles','money_accounts','categories','income_schedules','savings_goals',
                           'bills','bill_overrides','budget_allocations','trips','trip_budget_items']
  loop
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_updated_at()', t, t);
    execute format('create trigger %I_audit after insert or update or delete on public.%I for each row execute function public.write_audit()', t, t);
  end loop;
  foreach t in array array['ledger_events','trip_entries']
  loop
    execute format('create trigger %I_audit after insert on public.%I for each row execute function public.write_audit()', t, t);
  end loop;
end $$;

-- Server clock decides sync ordering for the immutable ledger
create or replace function public.stamp_server_time() returns trigger
language plpgsql as $$ begin new.created_at := now(); new.updated_at := now(); return new; end $$;
create trigger ledger_stamp before insert on public.ledger_events for each row execute function public.stamp_server_time();

-- Reject cross-user references (a user must not attach events to another user's account/category/goal)
create or replace function public.ledger_owner_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.account_id is not null and not exists (select 1 from money_accounts where id = new.account_id and user_id = new.user_id)
     or new.to_account_id is not null and not exists (select 1 from money_accounts where id = new.to_account_id and user_id = new.user_id)
     or new.category_id is not null and not exists (select 1 from categories where id = new.category_id and user_id = new.user_id)
     or new.goal_id is not null and not exists (select 1 from savings_goals where id = new.goal_id and user_id = new.user_id)
     or new.bill_id is not null and not exists (select 1 from bills where id = new.bill_id and user_id = new.user_id)
     or new.reverses_id is not null and not exists (select 1 from ledger_events where id = new.reverses_id and user_id = new.user_id)
  then
    raise exception 'ledger reference belongs to another user';
  end if;
  return new;
end $$;
create trigger ledger_owner before insert on public.ledger_events for each row execute function public.ledger_owner_check();

-- ---------------------------------------------------------------- row level security
alter table public.profiles          enable row level security;
alter table public.money_accounts    enable row level security;
alter table public.categories        enable row level security;
alter table public.income_schedules  enable row level security;
alter table public.savings_goals     enable row level security;
alter table public.bills             enable row level security;
alter table public.bill_overrides    enable row level security;
alter table public.budget_allocations enable row level security;
alter table public.trips             enable row level security;
alter table public.trip_members      enable row level security;
alter table public.trip_budget_items enable row level security;
alter table public.trip_entries      enable row level security;
alter table public.ledger_events     enable row level security;
alter table public.clover_events     enable row level security;
alter table public.audit_log         enable row level security;

-- Private, owner-only tables
do $$
declare t text;
begin
  foreach t in array array['profiles','money_accounts','categories','income_schedules','savings_goals',
                           'bills','bill_overrides','budget_allocations','clover_events']
  loop
    execute format('create policy %I_sel on public.%I for select using (user_id = auth.uid())', t, t);
    execute format('create policy %I_ins on public.%I for insert with check (user_id = auth.uid())', t, t);
    execute format('create policy %I_upd on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', t, t);
  end loop;
end $$;

-- Ledger: insert + select only. No update, no delete. Ever.
create policy ledger_sel on public.ledger_events for select using (user_id = auth.uid());
create policy ledger_ins on public.ledger_events for insert with check (user_id = auth.uid());

create policy audit_sel on public.audit_log for select using (user_id = auth.uid());

-- Trip membership helper (security definer avoids recursive policy evaluation)
create or replace function public.is_trip_member(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from trips where id = t and owner_id = auth.uid())
      or exists (select 1 from trip_members where trip_id = t and user_id = auth.uid() and status = 'accepted');
$$;

create policy trips_sel on public.trips for select
  using (owner_id = auth.uid() or public.is_trip_member(id)
         or exists (select 1 from trip_members m where m.trip_id = id and m.user_id = auth.uid()));
create policy trips_ins on public.trips for insert with check (owner_id = auth.uid());
create policy trips_upd on public.trips for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy members_sel on public.trip_members for select using (user_id = auth.uid() or public.is_trip_member(trip_id));
-- invites go through invite_to_trip(); members may accept or leave their own row
create policy members_upd on public.trip_members for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy members_del on public.trip_members for delete
  using (user_id = auth.uid() or exists (select 1 from trips where id = trip_id and owner_id = auth.uid()));

create policy items_sel on public.trip_budget_items for select using (public.is_trip_member(trip_id));
create policy items_ins on public.trip_budget_items for insert with check (user_id = auth.uid() and public.is_trip_member(trip_id));
create policy items_upd on public.trip_budget_items for update using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));

-- Shared entries: members see all entries of the trip; each member writes only their own; append-only
create policy entries_sel on public.trip_entries for select using (public.is_trip_member(trip_id));
create policy entries_ins on public.trip_entries for insert with check (user_id = auth.uid() and public.is_trip_member(trip_id));

-- ---------------------------------------------------------------- RPCs
create or replace function public.invite_to_trip(p_trip uuid, p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare invitee uuid;
begin
  if not exists (select 1 from trips where id = p_trip and owner_id = auth.uid()) then
    raise exception 'only the trip owner can invite';
  end if;
  select id into invitee from auth.users where lower(email) = lower(p_email);
  if invitee is null then raise exception 'no STACKD user with that email'; end if;
  insert into trip_members(trip_id, user_id, role, status) values (p_trip, invitee, 'member', 'invited')
  on conflict do nothing;
  update trips set shared = true where id = p_trip;
end $$;

create or replace function public.ensure_trip_owner_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into trip_members(trip_id, user_id, role, status) values (new.id, new.owner_id, 'owner', 'accepted')
  on conflict do nothing;
  return new;
end $$;
create trigger trips_owner_member after insert on public.trips for each row execute function public.ensure_trip_owner_member();

-- Permanently deletes the caller and (by cascade) every row they own.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from auth.users where id = auth.uid();
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
revoke all on function public.invite_to_trip(uuid, text) from public, anon;
grant execute on function public.invite_to_trip(uuid, text) to authenticated;
