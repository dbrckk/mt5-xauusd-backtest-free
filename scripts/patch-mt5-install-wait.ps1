$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

# Public Dukascopy is unstable when the 5 matrix jobs download ticks at the same time.
# Stagger jobs so the current multiTF workflow behaves like a sequential safe runner.
$period = $env:BT_PERIOD
$delaySeconds = switch ($period) {
  "M15" { 0 }
  "M30" { 1200 }
  "H1"  { 2400 }
  "H2"  { 3600 }
  "H4"  { 4800 }
  default { 0 }
}
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_download_stagger_period=$period"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_download_stagger_seconds=$delaySeconds"
if ($delaySeconds -gt 0) {
  Start-Sleep -Seconds $delaySeconds
}

$signalPatch = "scripts/patch-public-signal-timeframes.ps1"
if (Test-Path $signalPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $signalPatch
}

$orderPatch = "scripts/patch-public-order-execution.ps1"
if (Test-Path $orderPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $orderPatch
}

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw

# Force faster public feed failure handling inside the generated runner.
if ($txt.Contains('$env:PUBLIC_MIN_REQUIRED_BARS = "700"') -and -not $txt.Contains('public_fast_feed_timeout_runtime=true')) {
  $fastFeed = '$env:PUBLIC_MIN_REQUIRED_BARS = "700"' + "`r`n" + '$env:PUBLIC_FETCH_TIMEOUT_SECONDS = "8"' + "`r`n" + '$env:PUBLIC_FETCH_RETRIES = "1"' + "`r`n" + 'Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_fast_feed_timeout_runtime=true"'
  $txt = $txt.Replace('$env:PUBLIC_MIN_REQUIRED_BARS = "700"', $fastFeed)
}

$oldInstall = 'if ($null -eq $terminal) { $p = Start-Process -FilePath $installer -ArgumentList "/auto" -PassThru; $p.WaitForExit(180000) | Out-Null; Start-Sleep -Seconds 25; Kill-MT5 }'
$newInstall = @'
if ($null -eq $terminal) {
  Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "mt5_install_attempt=auto_wait"
  $p = Start-Process -FilePath $installer -ArgumentList "/auto" -PassThru
  $deadline = (Get-Date).AddMinutes(8)
  do {
    Start-Sleep -Seconds 15
    $terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)", $env:LOCALAPPDATA, $env:APPDATA) "terminal64.exe"
    if ($null -ne $terminal) { break }
    if ($p.HasExited) { Start-Sleep -Seconds 15 }
  } while ((Get-Date) -lt $deadline)
  Kill-MT5
}
'@

$oldThrow = 'if ($null -eq $terminal) { throw "terminal64.exe not found." }'
$newThrow = @'
if ($null -eq $terminal) {
  Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "mt5_install_retry=silent"
  $p = Start-Process -FilePath $installer -ArgumentList "/silent" -PassThru
  $deadline = (Get-Date).AddMinutes(6)
  do {
    Start-Sleep -Seconds 15
    $terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)", $env:LOCALAPPDATA, $env:APPDATA) "terminal64.exe"
    if ($null -ne $terminal) { break }
  } while ((Get-Date) -lt $deadline)
  Kill-MT5
}
if ($null -eq $terminal) {
  Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)", $env:LOCALAPPDATA, $env:APPDATA -Recurse -Filter "terminal*.exe" -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String | Set-Content -Path (Join-Path $reportsRoot "mt5_terminal_search.txt") -Encoding UTF8
  throw "terminal64.exe not found after extended installer wait."
}
'@

if (!$txt.Contains($oldInstall)) { throw "Original MT5 install one-liner not found." }
if (!$txt.Contains($oldThrow)) { throw "Original MT5 terminal throw line not found." }

$txt = $txt.Replace($oldInstall, $newInstall)
$txt = $txt.Replace($oldThrow, $newThrow)
Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "mt5_install_wait_patch=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_direct_signal_patch_step=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_direct_order_patch_step=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_matrix_stagger_patch=true"
Write-Host "MT5 installer wait patch, stagger, and direct public runtime patches applied."
