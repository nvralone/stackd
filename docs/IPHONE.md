# STACKD on PC + iPhone (free)

Two pieces:
1. **Shared data**: a free Supabase project. Both devices sign in with the same email and sync.
2. **The iPhone app**: Codemagic (free cloud Mac) builds it, then AltStore on your PC installs it with your free Apple ID. The app has to be refreshed every 7 days; AltStore does that automatically when your PC and iPhone are on the same Wi-Fi with AltServer running.

Nothing here costs money. Apple's $99/year program is **not** needed.

---

## 1. GitHub (free) — holds the code for Codemagic
1. Create an account at github.com.
2. Create a new **private** repository named `stackd` (leave it empty: no README).
3. Tell Claude the repo URL. Claude commits and pushes; a browser window asks you to log in to GitHub once.

## 2. Supabase (free) — shared, private data
1. supabase.com → **Sign in with GitHub** → **New project** (Free plan). Pick a region near you and save the database password somewhere safe.
2. Left menu **SQL Editor** → **New query** → paste all of `supabase/migrations/0001_init.sql` → **Run**.
3. **Authentication → Sign In / Providers → Email**: on. (Optional: turn off "Confirm email" so sign-up is instant.)
4. **Project Settings → API Keys**: copy the **Project URL** and the **Publishable** key (starts with `sb_publishable_`).
   Never copy or share the **secret** / `service_role` key.
5. Give the URL + publishable key to Claude (or create `supabase.env.json` yourself, see step 5).

## 3. Codemagic (free) — builds the iPhone app
1. codemagic.io → **Sign up with GitHub** → **Add application** → choose `stackd` → it finds `codemagic.yaml`.
2. **Environment variables** (app or team settings) → add a group named **`stackd`** with:
   - `SUPABASE_URL` = your Project URL
   - `SUPABASE_PUBLISHABLE_KEY` = your publishable key
3. **Start new build** → workflow **"iPhone build (unsigned, for AltStore)"**. Takes ~10–20 minutes.
4. Download **STACKD.ipa** from the build's Artifacts.

## 4. AltStore (free) — installs it on your iPhone
1. On the PC install **iTunes** and **iCloud** from apple.com (the website versions, *not* the Microsoft Store ones). AltServer needs them.
2. Download **AltServer for Windows** from altstore.io, install and run it (it lives in the tray, bottom-right).
3. Connect the iPhone by USB → tap **Trust** on the phone. In iTunes, open the phone and tick **Sync with this iPhone over Wi-Fi** → Apply.
4. iPhone: **Settings → Privacy & Security → Developer Mode → On** (restart when asked).
5. PC tray: **AltServer → Install AltStore → (your iPhone)** → sign in with your Apple ID. (AltServer sends it only to Apple to make the free signing certificate. Some people use a spare Apple ID for this.)
6. iPhone: **Settings → General → VPN & Device Management** → trust your Apple ID.
7. Put `STACKD.ipa` on the phone (iCloud Drive / OneDrive / email to yourself) → open **AltStore → My Apps → +** → pick `STACKD.ipa`.
   Or on the PC: **Shift-click** the AltServer tray icon → **Sideload .ipa** → choose the file.
8. Every 7 days: keep AltServer running on the PC and the phone on the same Wi-Fi; AltStore refreshes in the background (or open AltStore → **Refresh All**).

## 5. Turn on sync on Windows
1. In the `stackd` folder create `supabase.env.json` (it is git-ignored):
   ```json
   { "SUPABASE_URL": "https://YOURPROJECT.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..." }
   ```
2. Run `build-windows.ps1` (right-click → Run with PowerShell). The app rebuilds and opens.
3. Settings → **Sign in to back up & sync** → create your account. Everything already on this PC uploads to it.
4. On the iPhone, sign in with the **same email** and password. Both devices now share the same data.

## Known limits
- The iPhone build has not been run yet: the first Codemagic build may surface an iOS-only error to fix.
- Free sideloading: max 3 sideloaded apps, 7-day refresh, no App Store.
- Notifications on iPhone ask for permission the first time.
