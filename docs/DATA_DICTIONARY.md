# Data Dictionary

Source of truth: `supabase/migrations/0001_init.sql`. All money columns are `bigint` cents. All ids are client-generated UUID v4 (idempotent writes). Mutable tables carry `deleted` (soft delete, synced), `client_updated_at` (conflict resolution) and server `updated_at` (sync cursor). Each local SQLite row stores the same JSON shape.

| Requirement | Table / model |
|---|---|
| Users & preferences | `profiles` (`clover` jsonb: personality, volume, muted, silent, subtitles, tts, frequency, home_hidden; `notifications` jsonb: toggles, quiet_start, quiet_end) |
| Manual money accounts | `money_accounts` |
| Categories | `categories` |
| Budget periods | Derived (`week_start` + calendar month), see `periodOf()` |
| Budget allocations | `budget_allocations` |
| Financial transactions | `ledger_events` |
| Transaction splits | `ledger_events.group_id` (events created together) + `budget_allocations.group_id` |
| Savings goals / events | `savings_goals` / `ledger_events` kinds `goal_deposit`, `goal_withdraw` |
| Vacation plans / budgets | `trips` / `trip_budget_items` |
| Shared goal memberships | `trip_members` |
| Shared contributions/expenses | `trip_entries` |
| Income schedules | `income_schedules` |
| Bills, debt agreements, debt schedules | `bills` (schedule generated deterministically) + `bill_overrides` |
| Confirmed payments | `ledger_events` kinds `bill_payment`, `loan_in` with `bill_id` + `bill_occurrence` |
| Notifications | Derived by `planReminders()`; preferences in `profiles.notifications` |
| Clover personality | `profiles.clover` |
| Clover dialogue events | `clover_events` (table ready; history currently kept locally) |
| Sync metadata | local `kv` (`cursor:<table>`, `device_id`), row `dirty` flag; server `updated_at` |
| Audit records | `audit_log` (server trigger) + immutable ledger |

## Tables

### profiles
`id`=`user_id` (auth user) · `display_name` · `currency` (3 letters) · `week_start` 1–7 (ISO, 1=Mon) · `theme` dark/light/system · `clover` jsonb · `notifications` jsonb · `onboarded`.

### money_accounts
`name` (1–60) · `kind` cash/venmo/cashapp/checking/savings/custom · `color` ARGB int · `archived` · `sort`. **No balance column.** Starting balance = `opening` event.

### categories
`name` (1–40) · `color` · `icon` (index) · `limit_cents` (null = no limit) · `period` weekly/monthly · `rollover` (one period carry-over of unused or overspent) · `essential` (never scolded) · `tag` (`fast_food`, `groceries`, `gas` analytics hooks) · `archived`.

### budget_allocations
`category_id` · `period_start` · `amount_cents` > 0 · `group_id`. Adds budget to one category period. Not money movement.

### income_schedules
`frequency` weekly/biweekly/semimonthly/monthly/irregular · `anchor_date` (any real payday) · `expected_cents` (forecast assumption only) · `account_id` · `active`.

### savings_goals
`goal_cents` > 0 · `target_date` · `contribution_cents` + `contribution_freq` payday/weekly/monthly/none (*planned*, never counted as saved) · `locked` (Savings Lock: typed confirmation) · `trip_id` (vacation vault).

### bills
`kind` recurring/one_time/debt_owed/debt_lent · `amount_cents` per payment · `frequency` once/weekly/biweekly/monthly/yearly · `first_due` · `payment_count` (null = open-ended) · `principal_cents` · `fee_cents` (total fees/interest; last payment = remainder) · `counterparty` · `category_id` · `account_id` · `reminder_days`.
Occurrence *i* due = `nthOccurrence(first_due, frequency, i)` unless overridden.

### bill_overrides
Unique (`bill_id`, `occurrence`) · `due_on` (reschedule) · `skipped`.

### trips / trip_members / trip_budget_items / trip_entries
`trips`: `owner_id`, destination, `depart_on` ≤ `return_on`, `budget_cents`, `shared`.
`trip_members`: (trip, user) PK, `role` owner/member, `status` invited/accepted. Created by `invite_to_trip()` RPC; owner row by trigger.
`trip_budget_items`: `category` transportation/flights/accommodation/food/activities/shopping/emergency/custom, `planned_cents`.
`trip_entries` (append-only): `kind` contribution/withdrawal/expense, `amount_cents` > 0, `ledger_event_id` UNIQUE (one shared row per private event → no double counting), `reverses_id`.

### ledger_events (immutable)
`kind` (see ARCHITECTURE) · `occurred_on` · `amount_cents` (≠0; >0 except opening/adjustment) · `account_id` · `to_account_id` (transfer, ≠ account) · `category_id` · `goal_id` · `bill_id` + `bill_occurrence` · `trip_id` · `income_source` paycheck/side_job/tip/gift/sale/loan/other · `reason` planned/emergency/other · `group_id` · `reverses_id` (unique: one reversal per event) · `replaces_id` · `note` ≤500 · `device_id`.
Constraints enforce: transfers have two distinct accounts; goal events have a goal; reversals point at an event; money-moving kinds have an account; references belong to the same user (trigger).

**Bill envelope earmarks (no schema change).** A `goal_deposit` into the "Bill savings" vault with
`bill_id` set is money set aside for that bill; a `goal_withdraw` with `bill_id` is money used for it.
Per bill: running total, never below 0. Envelope deposits without `bill_id` are *unassigned* and are
never assigned to a bill unless the user turns on "Use unassigned Bill savings" in a paycheck split
(that records a withdraw-unassigned + deposit-for-bill pair; the envelope total does not change).
If money is taken back out so the envelope holds less than all earmarks, bills due last lose theirs first.
`bill_id` on goal events never counts as a bill payment (`paidFor` only counts `bill_payment` / `loan_in`).

### clover_events
`topic`, `line_id`, `mood` — reserved for cross-device anti-repeat.

### audit_log
`table_name`, `row_id`, `action`, `old_row`, `new_row`, `at`. Read-only to the owner.

## RPCs
- `invite_to_trip(p_trip uuid, p_email text)` — owner only; looks up the invitee by email.
- `delete_my_account()` — deletes the caller's auth user; every table cascades.

## Indexes
`(user_id, updated_at)` on every synced table; `(user_id, occurred_on)` on ledger; partial unique on `ledger_events(reverses_id)`; `(trip_id, created_at)` on trip entries.
