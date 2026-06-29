$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$ea = "MQL5/Experts/QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $ea)) { throw "EA source not found: $ea" }

$src = Get-Content -Path $ea -Raw
$old = 'publicScore <= 55.0 && sig.bodyATR > 0.30 && sig.distanceFromSignalEMAATR > 2.20'
$new = 'publicScore <= 65.0 && sig.bodyATR > 0.50 && sig.distanceFromSignalEMAATR > 2.20'

if (!$src.Contains($old) -and !$src.Contains($new)) {
  throw "London buy chase filter pattern not found."
}

if ($src.Contains($old)) {
  $src = $src.Replace($old, $new)
  Set-Content -Path $ea -Value $src -Encoding UTF8
}

$signalPatch = "scripts/patch-public-signal-timeframes.ps1"
if (Test-Path $signalPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $signalPatch
}

$orderPatch = "scripts/patch-public-order-execution.ps1"
if (Test-Path $orderPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $orderPatch
}

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_strict_london_buy_chase_block=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_london_buy_chase_score_max=65"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_london_buy_chase_bodyatr_min=0.50"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_london_buy_chase_distema_min=2.20"
Write-Host "Strict public London buy chase filter, signal timeframe patch, and order execution patch applied."
