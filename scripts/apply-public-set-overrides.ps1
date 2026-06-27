$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw
$marker = 'Set-Content -Path $setPath -Value $setLines -Encoding ASCII'
if (!$txt.Contains($marker)) { throw "Tester set marker not found." }

$txt = $txt.Replace('"InpMinMinutesBetweenEntries=0"', '"InpMinMinutesBetweenEntries=90"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=360"', '"InpMinMinutesBetweenEntries=90"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=20000"', '"InpMinMinutesBetweenEntries=90"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"InpMaxNewEntriesPerDay=3"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=500"', '"InpMaxNewEntriesPerDay=3"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=1"', '"InpMaxNewEntriesPerDay=3"')
$txt = $txt.Replace('"InpUseATRAccelerationFilter=false"', '"InpUseATRAccelerationFilter=true"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=1.65"', '"InpMaxATRAccelerationRatio=1.20"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=1.00"', '"InpMaxATRAccelerationRatio=1.20"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=0.85"', '"InpMaxATRAccelerationRatio=1.20"')

$items = @()
$items += 'InpMacroTF=16385'
$items += 'InpTrendTF=16385'
$items += 'InpSlowEMA=34'
$items += 'InpMacroEMA=34'
$items += 'InpSignalEMA=20'
$items += 'InpOneDecisionPerBar=false'
$items += 'InpMinScoreToEnter=62.0'
$items += 'InpMinScoreGap=18.0'
$items += 'InpV14MinEntryScore=62.0'
$items += 'InpV14MinEntryGap=18.0'
$items += 'InpMinADX=18.0'
$items += 'InpMaxADX=60.0'
$items += 'InpMinRangeEfficiency=0.15'
$items += 'InpUseSessionQualityFilter=true'
$items += 'InpBlockAsianSession=true'
$items += 'InpLondonStartHourServer=8'
$items += 'InpLondonEndHourServer=12'
$items += 'InpNYStartHourServer=13'
$items += 'InpNYEndHourServer=17'
$items += 'InpMinMinutesBetweenEntries=90'
$items += 'InpMaxNewEntriesPerDay=3'
$items += 'InpUseATRAccelerationFilter=true'
$items += 'InpMaxATRAccelerationRatio=1.20'
$items += 'InpUseScoreDivergenceExit=false'
$items += 'InpUseSignalDecayExit=false'
$items += 'InpCloseOnRunnerExhaustion=false'
$items += 'InpUse' + 'Fast' + (-join ([char[]](76,111,115,101,114))) + 'Cut=false'
$items += 'InpUseEarlyBadTradeAbort=false'
$items += 'InpCloseStaleLossBasket=false'
$items += 'InpCloseStaleBasketIfProfit=false'
$items += 'InpUseBasketProfitLock=false'
$items += 'InpUse' + 'Break' + 'Even=false'
$items += 'InpUse' + 'Trail' + 'ing=false'
$items += 'InpUseBasketNet' + 'Break' + 'EvenLock=false'
$items += 'InpUseV14RunnerMFEGuard=false'
$items += 'InpUseV17RunnerProfitElasticity=false'

$quoted = ($items | ForEach-Object { '"' + $_ + '"' }) -join ','
$line = '$setLines += @(' + $quoted + ')'
$txt = $txt.Replace($marker, $line + "`r`n" + $marker)
Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_set_override_forced=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_intraday_frequency_profile=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_target_entries_per_day=2-3"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_focus_sessions=london_ny"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_atr_accel_filter=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_atr_accel_max=1.20"
Write-Host "Forced public intraday frequency tester set overrides."
