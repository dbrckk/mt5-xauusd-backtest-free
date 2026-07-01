$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$from = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2023.06.21" }
$to = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { "2026.06.21" }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "100000" }
$period = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M5" }

Set-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "EA_V26_PUBLIC_BACKTEST"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "from_date=$from"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "to_date=$to"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "deposit=$deposit"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "period=$period"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "ea=MQL5/Experts/XAUUSD_V26_PropFirm_100k.mq5"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "fixed_lot=0.20"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "max_trades_per_day=8"
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "cooldown_minutes=30"

$patchWait = Join-Path $repo "scripts/patch-mt5-install-wait.ps1"
if (Test-Path $patchWait) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $patchWait
}

$sourceRunner = Join-Path $repo "scripts/run-public-history-backtest.ps1"
$generatedRunner = Join-Path $repo "scripts/_run-ea-v26-public-backtest.generated.ps1"
$txt = Get-Content -Path $sourceRunner -Raw

$oldEa = '$eaSource = Join-Path $repo "MQL5\Experts\QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"'
$newEa = '$eaSource = Join-Path $repo "MQL5\Experts\XAUUSD_V26_PropFirm_100k.mq5"'
$txt = $txt.Replace($oldEa, $newEa)

$oldTune = 'Tune-EA-ForPublicBacktest $eaSource $reportsRoot'
$newTune = 'Set-Content -Path (Join-Path $reportsRoot "ea_v26_settings.txt") -Value "V26 EA settings: FixedLot=0.20; MaxTradesPerDay=8; CooldownMinutes=30; BUY Quality; SELL enabled; one position at a time" -Encoding UTF8'
$txt = $txt.Replace($oldTune, $newTune)

$txt = $txt.Replace('"InpTradeSymbol=$customSymbol"', '"InpTradeSymbol=$customSymbol"')
$txt = $txt.Replace('"InpFixedLot=0.01"', '"FixedLot=0.20"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"MaxTradesPerDay=8"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=0"', '"CooldownMinutes=30"')
$txt = $txt.Replace('"InpStrategyProfile=0"', '"BuyFrequencyMode=false"')
$txt = $txt.Replace('"InpUseRiskLot=false"', '"EnableBuy=true"')
$txt = $txt.Replace('"InpForceTenKLotBand=false"', '"EnableSell=true"')
$txt = $txt.Replace('"InpMaxAllowedSingleLot=0.10"', '"UseSession=true"')
$txt = $txt.Replace('"InpMaxAllowedTotalLots=0.20"', '"SessionStartHour=8"')
$txt = $txt.Replace('"InpMaxTotalLots=0.20"', '"SessionEndHour=21"')
$txt = $txt.Replace('"InpCapitalProtectionMode=false"', '"BlockFridayAfter16=true"')

Set-Content -Path $generatedRunner -Value $txt -Encoding UTF8

pwsh -NoProfile -ExecutionPolicy Bypass -File $generatedRunner 2>&1 | Tee-Object -FilePath (Join-Path $reportsRoot "run_ea_v26_generated_runner.log")
$code = $LASTEXITCODE
Add-Content (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") "run_public_backtest_exit_code=$code"
exit $code
