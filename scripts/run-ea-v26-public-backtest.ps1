$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$from = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2023.06.21" }
$to = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { "2026.06.21" }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "15000" }
$period = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M15" }

Set-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "EA_V26_PUBLIC_BACKTEST"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "from_date=$from"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "to_date=$to"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "deposit=$deposit"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "period=$period"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "ea=MQL5/Experts/XAUUSD_V26_PropFirm_100k.mq5"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "fixed_lot=0.02"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "max_trades_per_day=8"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "cooldown_minutes=30"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "profile=v26_m15_priority_retest"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "full_requested_window=true"

$sourceRunner = Join-Path $repo "scripts/run-public-history-backtest.ps1"
$generatedRunner = Join-Path $repo "scripts/_run-ea-v26-public-backtest.generated.ps1"
$txt = Get-Content -Path $sourceRunner -Raw

$oldEa = '$eaSource = Join-Path $repo "MQL5\Experts\QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"'
$newEa = '$eaSource = Join-Path $repo "MQL5\Experts\XAUUSD_V26_PropFirm_100k.mq5"'
$txt = $txt.Replace($oldEa, $newEa)

$oldTune = 'Tune-EA-ForPublicBacktest $eaSource $reportsRoot'
$newTune = 'Set-Content -Path (Join-Path $reportsRoot "ea_v26_settings.txt") -Value "V26 M15 priority retest: FixedLot=0.02; MaxTradesPerDay=8; CooldownMinutes=30; SlippagePoints=180; StopBuffer=60; Session=08-17; stronger filters" -Encoding UTF8'
$txt = $txt.Replace($oldTune, $newTune)

$txt = $txt.Replace('"InpFixedLot=0.01"', '"FixedLot=0.02"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"MaxTradesPerDay=8"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=0"', '"CooldownMinutes=30"')
$txt = $txt.Replace('"InpStrategyProfile=0"', '"BuyFrequencyMode=false"')
$txt = $txt.Replace('"InpUseRiskLot=false"', '"EnableBuy=true"')
$txt = $txt.Replace('"InpForceTenKLotBand=false"', '"EnableSell=true"')
$txt = $txt.Replace('"InpMaxAllowedSingleLot=0.10"', '"UseSession=true"')
$txt = $txt.Replace('"InpMaxAllowedTotalLots=0.20"', '"SessionStartHour=8"')
$txt = $txt.Replace('"InpMaxTotalLots=0.20"', '"SessionEndHour=17"')
$txt = $txt.Replace('"InpCapitalProtectionMode=false"', '"BlockFridayAfter16=true"')
$txt = $txt.Replace('"InpVerboseLog=true"', '"InpVerboseLog=true", "SlippagePoints=180", "BrokerStopBufferPoints=60", "UseExecutionTimeframeGate=true", "UseExecutionTrendFilter=true", "UseBuyH1Filter=true", "BlockBuyH2Bear=true", "BlockBuyH4Bear=true", "SellVolMult=1.00", "BuyVolMult=1.00", "BuyMinRsi=52.0", "BuyMaxRsi=68.0", "BuyMinBodyRatio=0.30", "SellTP_ATR=2.20", "SellSL_ATR=1.60", "BuyTP_ATR=1.25", "BuySL_ATR=1.55"')

Set-Content -Path $generatedRunner -Value $txt -Encoding UTF8

pwsh -NoProfile -ExecutionPolicy Bypass -File $generatedRunner 2>&1 | Tee-Object -FilePath (Join-Path $reportsRoot "run_ea_v26_generated_runner.log")
$code = $LASTEXITCODE
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "run_public_backtest_exit_code=$code"

$logText = ""
if (Test-Path (Join-Path $reportsRoot "run_ea_v26_generated_runner.log")) {
  $logText = Get-Content -Path (Join-Path $reportsRoot "run_ea_v26_generated_runner.log") -Raw -ErrorAction SilentlyContinue
}
$fallbackReason = ""
if (Test-Path (Join-Path $reportsRoot "fallback_report_reason.txt")) {
  $fallbackReason = Get-Content -Path (Join-Path $reportsRoot "fallback_report_reason.txt") -Raw -ErrorAction SilentlyContinue
}

if ($logText -match "tester not started" -or $fallbackReason -match "Test passed=NO" -or $fallbackReason -match "final_balance=unknown") {
  Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "ea_v26_validation=failed_no_valid_mt5_report"
  throw "EA V26 MT5 tester did not produce a valid backtest report."
}

Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "ea_v26_validation=passed_runner_level"
exit $code
