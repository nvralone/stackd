# STACKD Architecture

## Stack

| Concern | Choice | Why |
|---|---|---|
| UI | Flutter 3.50 (`material_ui`), one codebase for iOS / Android / Windows | Requirement |
| State | One `ChangeNotifier` (`AppState`) exposed via `InheritedNotifier` | No state library needed |
| Local store | `sqlite3` (bundled SQLite via build hooks) | Offline-first, works on all 3 platforms, no codegen |
| Cloud | `supabase_flutter` (Auth + Postgres + RLS) | Requirement |
| Notifications | `flutter_local_notifications` + `timezone` | Local only, no push service |
| Voice | `audioplayers` (procedural WAV babble) + `flutter_tts` (device TTS) | Free, offline |
| Files | `path_provider` | DB location, export, temp audio |
| Charts | Hand-written `CustomPainter` | Avoids a chart dependency |
| UUIDs | 10-line v4 generator on `Random.secure()` | Avoids a dependency |
| Dev only | `image` (one-off tool to cut Clover out of the reference image) | Asset tooling |

No bank APIs, no AI services, no paid voice, no servers, no receipt images.

## Layers

```
lib/
  core/      money.dart (integer cents), dates.dart (UTC date-only), ids.dart
  data/      models.dart (1:1 with Supabase rows), local_db.dart (SQLite + outbox), sync.dart, defaults.dart
  domain/    ledger.dart, bills.dart, finance.dart, allocation.dart, forecast.dart, insights.dart, trips.dart   <- pure, tested
  clover/    moods.dart, dialogue.dart, brain.dart (rules), voice.dart, clover_widget.dart
  services/  notifications.dart (pure planner + plugin wrapper)
  state/     app_state.dart (all writes go through here)
  ui/        app.dart (shell/nav), theme.dart, common.dart, charts.dart, screens/*, sheets/*
```

Domain code never touches Flutter or storage, so every financial rule is unit-tested in isolation.

## Financial ledger rules

1. **Money is `int` cents everywhere.** Parsing (`parseCents`) is string-based; no `double` ever holds money. Splits use `splitEvenly` / `splitByWeights` (largest remainder) so parts always sum exactly.
2. **Balances are never stored.** `Ledger` derives account balances, vault balances and category spending from `ledger_events` every time.
3. **Events are immutable.** No UPDATE/DELETE policy exists on `ledger_events`. Corrections:
   - *Delete* = append a `reversal` event (`reverses_id`). Reversed events stop counting; both stay visible in Activity.
   - *Edit* = reversal + replacement event (`replaces_id`) in one SQLite transaction.
   - *Undo a split* = reverse every event sharing a `group_id`.
4. **Event effects**

   | kind | account effect | other |
   |---|---|---|
   | opening / adjustment | +/- signed amount | not income/spending |
   | income | + | `income_source=loan` is borrowed, not earned |
   | refund | + | reduces category spending, not income |
   | expense | − | category spending |
   | transfer | −from / +to | net zero, never income/spending |
   | goal_deposit / goal_withdraw | none | virtual allocation; `reason` = planned/emergency/other |
   | bill_payment | − | linked to `bill_id` + `bill_occurrence` |
   | loan_out / loan_in | − / + | money lent to / repaid by a friend |
5. **Real vs virtual money.** Accounts hold real money. Vaults and category budgets are allocations of that money, so `totalMoney` is never double counted. `availableToSpend = totalMoney − vault balances − unpaid bills due before next payday`.
6. **Scheduled ≠ paid.** Bill/debt schedules are generated deterministically from the bill definition plus `bill_overrides` (reschedule/skip). They reduce *projected* safe-to-spend only. Balances change only when the user confirms a payment (partial allowed).
7. **Nothing is auto-committed.** Paycheck / Extra Money proposals (`allocation.dart`) are pure functions; the allocation sheet writes only after an explicit confirm dialog.
8. **Idempotency.** Every write carries a client UUID generated when the form opens. Local inserts are `INSERT OR IGNORE`; cloud inserts are `upsert(ignoreDuplicates)` — double taps and sync retries cannot duplicate money.

## Paycheck distribution (lib/domain/allocation.dart)
`billNeeds(f)` looks only at existing bills:
- Due before the next payday: everything unpaid, minus envelope money for that bill, minus money already
  in accounts (soonest first). `reservedForBills` subtracts the same envelope money, so nothing is held twice.
- Less frequent than paydays and due later (within ~3 months): share = still needed when this pay period
  began / paychecks left (regular paydays from today's pay period up to, not including, the due date),
  minus what was already added for it since the last payday. Irregular income is never assumed.
`suggestPaycheck` order: bills before payday, essential budgets, later bills (envelope, tagged per bill),
other budgets, savings goals, spare. Nothing is written until the user confirms in the split sheet.
Regression tests: test/bill_distribution_test.dart.

## Offline sync

- Every local write marks the row `dirty` (the outbox). Writes work with no network.
- `SyncService.push` uploads dirty rows table-by-table in FK order (chunks of 200), then marks them clean.
- `pull` fetches rows with server `updated_at` ≥ cursor − 2 min (overlap tolerates late commits), paginated.
- Conflicts: immutable rows can't conflict (union). Mutable config rows use last-writer-wins on `client_updated_at`; an unsynced newer local edit is kept and pushed (`LocalDb.mergeRemote`, tested).
- Retries: on failure, exponential backoff (10 s → ~5 min); also every 2 minutes and 2 s after each local change.
- Sign-out wipes the local DB (warns if changes are still queued). Account deletion calls the `delete_my_account()` RPC which cascades every row.

## Security

- Client contains only the Supabase URL + publishable (anon) key via `--dart-define`. No service-role key anywhere.
- RLS on every table. Private tables: owner only. Ledger: insert + select only. A trigger rejects ledger rows referencing another user's account/category/goal/bill.
- Shared trips: `is_trip_member()` (security definer) gates `trips`, `trip_budget_items`, `trip_entries`. Members see the shared plan and shared entries only — never private accounts or ledgers.
- Server-side `audit_log` trigger records every insert/update/delete on mutable tables and every ledger insert.
- Local data lives in the app's private support directory (sandboxed on iOS/Android, per-user AppData on Windows). It is **not** encrypted at rest (see Known limitations).

## Screens & routes

Shell destinations (bottom bar on phones < 900 px, `NavigationRail` sidebar on wider/Windows):

| Tab | Screen | Pushed routes / sheets |
|---|---|---|
| Home | `HomeScreen` | customize widgets dialog, Quick Add, Extra Money |
| Activity | `ActivityScreen` (search + filters) | `EventDetail` sheet (edit / reverse / undo group) |
| Budget | `BudgetScreen` | `ForecastScreen` (forecast + what-if), `CategoryDetail`, `CategoryEditor`, `ScheduleEditor` |
| Goals | `GoalsScreen` | `GoalDetail`, `MoveMoney`, `VaultTransfer`, `GoalEditor`, `TripDetail`, `TripEditor`, `TripItemEditor`, `TripExpense` |
| Bills | `BillsScreen` | `BillDetail`, `PayBill` (pay/partial/reschedule/skip), `BillEditor` |
| Insights | `InsightsScreen` | `RecapScreen` |
| Settings | `SettingsScreen` | `AccountEditor`, `MoodGallery`, `AuthScreen` |

Gate: `AuthScreen` (if cloud configured and not signed in / not local-only) → `OnboardingScreen` (10 steps) → `Shell`.

Shared components (`ui/common.dart`): `Panel`, `Stat`, `Money`, `Bar`, `Section`, `Empty`, `AmountField`, `AccountPicker`, `CategoryPicker`, `DateField`, `ColorChooser`, `confirm()`, `sheet()`, `PageBody`.

## Clover voice
Three styles: `clover` (character voice), `talk` (device TTS, pitched up), `babble` (gibberish).
The character voice is Kokoro-82M int8 (Apache-2.0) run on-device via the `sherpa_onnx` package. It is
downloaded once on request from the sherpa-onnx GitHub release (132 MB; ~148 MB on disk after keeping only
English files). It runs in a background isolate. `phonemizer.dart` turns text into phonemes with the model's
US lexicon (numbers, plurals, -ing/-ed, stretched words, sounding out unknown names) because sherpa-onnx 2.x
skips words not in the lexicon. Pitch is raised by resampling. ALL CAPS = yell (faster, higher, louder);
`*whispers*` = softer and slower. Sentences play as they're generated; finished lines are cached.
Honest limit: a general speech model shaped toward a character, not a voice actor. On Windows the app
ships its own onnxruntime.dll next to the exe (System32 has an older one).

## Clover

- `brain.dart` picks a topic from real data in priority order (overdue bill → bills exceed free money → goal complete → bill due → fast-food streak → overspent non-essential category → upcoming vacation → late night → spending less than last week → tight → idle).
- Lines come from `dialogue.dart` (109 lines, 32 topics, filtered by personality). Placeholders are filled only from recorded data; a line with any unfilled placeholder is skipped, so Clover can't invent numbers.
- Anti-repeat: the topic's most recent N−1 lines are excluded (history persisted, 80 entries).
- Essentials (`essential=true`) and `reason=emergency` withdrawals get supportive lines, never scolding.
