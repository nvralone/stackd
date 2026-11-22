# Setup & Builds

## 1. Flutter SDK
This machine: Flutter 3.50.1 stable at `C:\src\flutter` (not on PATH). Either add `C:\src\flutter\bin` to PATH or call `C:\src\flutter\bin\flutter.bat` directly.

```powershell
cd C:\Users\revel\OneDrive\Desktop\EmpireOS\stackd
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat test
```

## 2. Supabase (optional — the app works fully offline without it)
1. Create a free project at supabase.com (manual step, needs your account).
2. SQL Editor → paste and run `supabase/migrations/0001_init.sql` (or `supabase db push` with the CLI).
3. Authentication → Providers → Email: enabled. Decide whether "Confirm email" is on (the app handles both).
4. Project Settings → API: copy the **Project URL** and the **publishable / anon** key. **Never** use the `service_role` / secret key in the app.
5. Pass them at build/run time:

```powershell
C:\src\flutter\bin\flutter.bat run --dart-define=SUPABASE_URL=https://YOURPROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Without the defines, STACKD runs in local-only mode (no sign-in screen, no sync).

Optional RLS tests: install Docker + Supabase CLI, then `supabase start` and `supabase test db` (runs `supabase/tests/rls_test.sql`).

## 3. Windows
Requirements (not installed on this PC yet):
- Visual Studio 2022 (Community is free) with the **Desktop development with C++** workload.
- Windows **Developer Mode** on (`start ms-settings:developers`) — Flutter plugins need symlinks.

```powershell
C:\src\flutter\bin\flutter.bat run -d windows
```

```powershell
C:\src\flutter\bin\flutter.bat build windows --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```
Output: `build\windows\x64\runner\Release\` (copy the whole folder). For an installer, MSIX packaging is optional.

## 4. Android
Requirements: Android Studio (installs the SDK + an emulator). Then `flutter doctor --android-licenses`.

```powershell
C:\src\flutter\bin\flutter.bat run -d android
```

```powershell
C:\src\flutter\bin\flutter.bat build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```
Already configured: INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED permissions, scheduled-notification receivers, core library desugaring.
Release signing: currently uses the debug key. For Play Store, create an upload keystore and configure `signingConfigs` in `android/app/build.gradle.kts` (manual step; keep the keystore out of git).

## 5. iOS
Requires a Mac with Xcode (cannot be built from Windows). On the Mac:
```bash
flutter pub get && cd ios && pod install && cd ..
flutter run -d ios
flutter build ipa --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```
Signing: open `ios/Runner.xcworkspace`, set your Apple Developer Team and a unique bundle id (currently `com.stackd.stackd`). Installing on a physical device needs a (free or paid) Apple account; App Store/TestFlight needs the paid program.

## 6. Clover art
See `docs/CLOVER_ASSETS.md`. Drop finished mood sprites into `assets/clover/moods/` — they load automatically.

## 7. Screenshots (dev)
`flutter test screens/screens_test.dart --update-goldens` renders key screens to `screens/out/` using demo fixture data (test only, never shipped).
