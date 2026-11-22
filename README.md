# STACKD

Personal budgeting & savings for iPhone, Android and Windows — with **Clover**, a mischievous pixel-art raccoon who reacts to your real numbers.

- Manual accounts (cash, Venmo, Cash App, checking, savings). No bank connections.
- Immutable, auditable ledger in integer cents. Every entry editable and reversible.
- Budgets, paydays with confirm-first splits, Extra Money, bills & debts, savings vaults, vacations (shareable), forecasts, what-if, insights, weekly recaps.
- Works fully offline; optional private Supabase sync with row-level security.

## Quick start
```powershell
cd C:\Users\revel\OneDrive\Desktop\EmpireOS\stackd
C:\src\flutter\bin\flutter.bat test
```
Running the app needs a platform toolchain — see [docs/SETUP.md](docs/SETUP.md).

## Docs
- [Setup, Supabase config, Windows/Android/iOS builds](docs/SETUP.md)
- [PC + iPhone for free (Supabase + Codemagic + AltStore)](docs/IPHONE.md)
- [Architecture, ledger rules, sync, security, screens](docs/ARCHITECTURE.md)
- [Data dictionary](docs/DATA_DICTIONARY.md)
- [Clover sprite & audio manifest](docs/CLOVER_ASSETS.md)
- [Implementation checklist, test results, known limitations](docs/CHECKLIST.md)
- Schema & policies: [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql)
