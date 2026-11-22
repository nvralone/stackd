-- Row-level security tests (pgTAP). Run with the Supabase CLI against a local stack:
--   supabase start && supabase test db
-- NOT YET RUN: requires Docker + Supabase CLI, which were not available when this was written.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- two users
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

-- act as alice
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

insert into money_accounts (id, name, kind) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Alice cash', 'cash');
insert into ledger_events (id, kind, occurred_on, amount_cents, account_id)
  values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'opening', '2026-11-01', 10000, 'aaaaaaaa-0000-0000-0000-000000000001');
insert into trips (id, name) values ('aaaaaaaa-0000-0000-0000-0000000000f1', 'Shared trip');

select is((select count(*)::int from money_accounts), 1, 'alice sees her account');

-- duplicate event id is rejected (idempotency handled client-side with ignoreDuplicates)
select throws_ok($$insert into ledger_events (id, kind, occurred_on, amount_cents, account_id)
  values ('aaaaaaaa-0000-0000-0000-0000000000e1', 'opening', '2026-11-01', 10000, 'aaaaaaaa-0000-0000-0000-000000000001')$$,
  '23505', null, 'duplicate ledger id rejected');

-- ledger is append-only
select lives_ok($$update ledger_events set amount_cents = 1 where id = 'aaaaaaaa-0000-0000-0000-0000000000e1'$$, 'update runs');
select is((select amount_cents from ledger_events where id = 'aaaaaaaa-0000-0000-0000-0000000000e1'), 10000::bigint, 'ledger update had no effect (no policy)');
select lives_ok($$delete from ledger_events where id = 'aaaaaaaa-0000-0000-0000-0000000000e1'$$, 'delete runs');
select is((select count(*)::int from ledger_events), 1, 'ledger delete had no effect (no policy)');

-- act as bob
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select is((select count(*)::int from money_accounts), 0, 'bob cannot see alice accounts');
select is((select count(*)::int from ledger_events), 0, 'bob cannot see alice ledger');
select throws_ok($$insert into ledger_events (id, kind, occurred_on, amount_cents, account_id)
  values ('bbbbbbbb-0000-0000-0000-0000000000e1', 'expense', '2026-11-02', 500, 'aaaaaaaa-0000-0000-0000-000000000001')$$,
  null, null, 'bob cannot attach events to alice account');
select throws_ok($$insert into money_accounts (id, user_id, name, kind)
  values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'spoof', 'cash')$$,
  '42501', null, 'bob cannot write rows as alice');
select is((select count(*)::int from trips), 0, 'bob cannot see an unshared trip');

-- invite bob, then he can see the trip only
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
select invite_to_trip((select id from trips limit 1), 'bob@example.test');
set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
select is((select count(*)::int from trips), 1, 'invited bob sees the shared trip (but still no accounts)');

select * from finish();
rollback;
