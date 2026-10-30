# Just Type It - installer for Windows
# Created by Stefano Roman Gunness - MIT License
#
# Installs Just Type It for the current user only. No administrator password needed.
#
# One-line install (PowerShell, a normal window):
#   irm https://raw.githubusercontent.com/stefanoromang/just-type-it/main/install-windows.ps1 | iex

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$repo = "stefanoromang/just-type-it"
$appDir = Join-Path $env:LOCALAPPDATA "Programs\JustTypeIt"
$exe = Join-Path $appDir "JustTypeIt.exe"

Write-Host ""
Write-Host "Just Type It - free, private AI writing assistant for Windows" -ForegroundColor Green
Write-Host "Created by Stefano Roman Gunness"
Write-Host "Installing for $env:USERNAME only (no administrator password needed)."
Write-Host ""

if ([Environment]::OSVersion.Version.Build -lt 19041) { Write-Host "Just Type It needs Windows 10 (version 2004) or Windows 11." -ForegroundColor Red; exit 1 }
if (-not [Environment]::Is64BitOperatingSystem) { Write-Host "Just Type It needs 64-bit Windows." -ForegroundColor Red; exit 1 }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Finding the latest version..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "JustTypeIt-Installer" }
$zip = $release.assets | Where-Object { $_.name -like "JustTypeIt-*-win-x64-portable.zip" } | Select-Object -First 1
if (-not $zip) { Write-Host "The Windows version isn't published yet. See https://github.com/$repo/releases" -ForegroundColor Yellow; exit 1 }

Write-Host "Downloading $($zip.name) ($([math]::Round($zip.size / 1MB)) MB)..."
$tmp = Join-Path $env:TEMP $zip.name
Invoke-WebRequest $zip.browser_download_url -OutFile $tmp -UseBasicParsing
Get-Process JustTypeIt -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
Expand-Archive $tmp -DestinationPath $appDir -Force
Remove-Item $tmp -ErrorAction SilentlyContinue
Get-ChildItem $appDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

$shell = New-Object -ComObject WScript.Shell
$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "Just Type It.lnk"
$s = $shell.CreateShortcut($startMenu); $s.TargetPath = $exe; $s.Description = "Just Type It - by Stefano Roman Gunness"; $s.Save()
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "JustTypeIt" -Value "`"$exe`" --background"

Start-Process $exe
Write-Host ""
Write-Host "Done! Just Type It is in your system tray (bottom-right, near the clock)." -ForegroundColor Green
Write-Host "Type in Outlook, Word, Teams, Chrome or any app and mistakes are underlined."
Write-Host "Select text anywhere and press Ctrl+Alt+G to check it."
