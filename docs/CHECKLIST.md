# STACKD Implementation Checklist

Legend: ✅ done & tested · 🟡 done, not verified on a device/server · ❌ not done · 🎨 needs art

_Last updated 2026-11-22._

## Environment
- ✅ Flutter 3.50.1 / Dart 3.14 installed at `C:\src\flutter`
- ✅ VS 2022 Build Tools (C++ + ATL), NuGet CLI, Developer Mode — `flutter build windows --debug` succeeds (2026-11-22)
- ✅ Release build launches on this Windows 11 PC (onboarding screen rendered, window "STACKD"). Required Smart App Control off (it blocks unsigned locally built DLLs). Desktop shortcut: `Desktop\STACKD.lnk`.
- 🟡 Windows: full click-through of every screen, sound and notifications not yet observed on the real app
- ❌ Android SDK / Studio — not installed
- ❌ Xcode — impossible on Windows (needs a Mac)
- ❌ Docker + Supabase CLI — not installed (RLS tests not run)

## Stage 1 — Foundation
- ✅ Project, dark-first theme + light mode, design tokens, accent colors
- ✅ Adaptive navigation: bottom bar (phones) / sidebar rail (≥900 px, Windows) — widget-tested at 320, 390, 1366 px
- 🟡 Supabase email auth (sign up / sign in / local-only mode) — code complete, not run against a real project
- ✅ 10-step onboarding with skippable optional steps, no invented transactions

## Stage 2 — Ledger, accounts, offline
- ✅ Integer-cent money, exact splits
- ✅ Manual accounts (cash/Venmo/Cash App/checking/savings/custom), opening balance as event, balance correction via adjustment, archive
- ✅ Immutable ledger; edit = reversal + replacement; delete = reversal; undo group
- ✅ Transfers (no income/expense, no double counting)
- ✅ SQLite outbox, idempotent inserts, survives restart (tested)
- 🟡 Supabase push/pull, LWW conflicts, backoff retry — merge logic unit-tested; network path not run against a server
- ✅ Activity: search, filters, detail, audit info

## Stage 3 — Budget, income, extra money, bills
- ✅ Default categories (Personal/Daily neutral), unlimited custom, rename, color, icon, weekly/monthly limit, rollover, essential flag, archive, history, previous-period compare
- ✅ Custom week start day
- ✅ Income schedules (weekly/biweekly/semimonthly/monthly/irregular), variable amounts
- ✅ Paycheck allocation proposal → editable → explicit confirm (or skip)
- ✅ Extra Money: amount/date/source/notes; Suggested / Manual / Single; preview; confirm; undo; refunds classified as refunds
- ✅ Bills & debts: recurring, one-time, borrowed, lent; principal, fees, schedule generation, partial/early/late payments, missed (overdue), reschedule, skip, remaining balance, history
- ✅ Scheduled payments affect projected safe-to-spend only

## Stage 4 — Goals, vacations, forecasting
- ✅ Savings vaults: goal, target date, planned vs actual, deposits/withdrawals (reason), vault-to-vault transfer, history, forecast date, archive, Savings Lock (typed UNLOCK)
- ✅ Vacation planner: destination, dates, budget items by category, paid vs saved vs remaining, weekly need
- 🟡 Shared trips: invite by email, accept, shared contributions/withdrawals/expenses, no double counting via unique `ledger_event_id` — not run against a server
- ✅ Deterministic 4/8-week forecast, payday balance, buffer status, actual vs assumption labels
- ✅ What-If (spend less/more, save more, new monthly bill, extra income, move goal date) — never writes

## Stage 5 — Clover
- ✅ Base sprite from the supplied art (background removed only)
- ✅ 20 moods with procedural motion + effect glyphs
- ✅ 20 pixel-art faces + blink + talk frames + wagging tail (generated from the base art; see CLOVER_ASSETS.md)
- ✅ Voice: 'Talks' (device voice saying his lines, pitched up, ALL-CAPS spoken as words) or 'Gibberish' (formant babble); not yet heard by a person on device
- ✅ Personalities Friendly / Chaotic / Savage; 109 lines in 32 topics; anti-repeat; data-only placeholders
- ✅ Emergency withdrawals and essentials are never punished
- 🟡 Voice: procedural babble (WAV synth tested) + device TTS narration; volume/mute/silent/subtitles/frequency/replay — playback not heard on a device
- ✅ Weekly recap with breakdown, comparisons, Clover reaction, narration button

## Stage 6 — Insights, reminders, settings
- ✅ Weekly/monthly charts, by category vs previous, fast food, savings rate, over budget, cut-back ideas (suggestions only), recurring costs
- ✅ Reminder planner (payday, bills, overdue, savings, recap) with quiet hours — tested
- 🟡 Local notification scheduling / 80% limit warnings / vacation milestones — not observed on a device
- ✅ Settings: accounts, theme, week start, Clover, notifications, export JSON, sync status, sign out (wipe), delete account (double confirm)
- ✅ Configurable home widgets

## Added 2026-11-22 (user feedback)
- ✅ Delete + Edit menu on bills, debts, vaults, trips, categories (confirm first; history kept; vault money returns to safe-to-spend)
- ✅ Move a bill to Budget (turns it into a category limit)
- ✅ Weekly plan: recommends weekly amounts for bills, essentials, goals, spending; 'Use these amounts' applies limits/contributions after confirm

## Stage 7 — Quality
- ✅ `flutter analyze`: 0 issues
- ✅ `flutter test`: **69/69 passing** (money, dates, ledger, transfers, reversal, income classification, savings, debt schedules, partial/missed, rescheduling, recurring, budgets/rollover, allocation, forecast, what-if, duplicates, offline queue, conflict merge, wipe/export, edit/undo, Clover moods/dialogue/anti-repeat/recap, babble WAV, reminders/quiet hours, mobile nav, desktop nav, narrow layout, Quick Add end-to-end, onboarding)
- 🟡 RLS pgTAP tests written (`supabase/tests/rls_test.sql`), **not run**
- ✅ Windows release build runs; ❌ Android/iOS not built yet

## Known limitations / unresolved
1. Local SQLite is not encrypted at rest (relies on OS app sandbox / Windows user profile). Option: SQLCipher + secure-storage key.
2. Rollover carries one period back only.
3. Paying more than an occurrence's amount doesn't auto-apply to the next occurrence.
4. Bills whose `first_due` is far in the past show every unpaid past occurrence as overdue — set the next due date when creating.
5. Shared-trip member list shows "Member" rather than names (no public profile lookup, by design for privacy).
6. Clover dialogue history is per-device (`clover_events` table reserved for sync).
7. Currency is USD-formatted only.
8. Windows notifications for scheduled reminders depend on the plugin's Windows support; immediate toasts are more reliable.
