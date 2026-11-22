# Builds the Windows app. If supabase.env.json exists (not committed), cloud sync is turned on.
# supabase.env.json format:
#   { "SUPABASE_URL": "https://xxxx.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..." }
$flutter = 'C:\src\flutter\bin\flutter.bat'
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
Set-Location $PSScriptRoot
Get-Process stackd -ErrorAction SilentlyContinue | Stop-Process -Force
$extra = @()
if (Test-Path 'supabase.env.json') { $extra = @('--dart-define-from-file=supabase.env.json') }
& $flutter build windows --release @extra
if ($LASTEXITCODE -eq 0) { Start-Process 'build\windows\x64\runner\Release\stackd.exe' }
