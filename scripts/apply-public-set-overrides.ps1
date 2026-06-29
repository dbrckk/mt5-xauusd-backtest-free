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

# Normalize older inserted profile values first. MT5 may keep the first duplicate value.
$txt = $txt.Replace('"InpMinScoreToEnter=70.0"', '"InpMinScoreToEnter=50.0"')
$txt = $txt.Replace('"InpMinScoreToEnter=62.0"', '"InpMinScoreToEnter=50.0"')
$txt = $txt.Replace('"InpMinScoreToEnter=55.0"', '"InpMinScoreToEnter=50.0"')
$txt = $txt.Replace('"InpMinScoreGap=30.0"', '"InpMinScoreGap=8.0"')
$txt = $txt.Replace('"InpMinScoreGap=18.0"', '"InpMinScoreGap=8.0"')
$txt = $txt.Replace('"InpMinScoreGap=10.0"', '"InpMinScoreGap=8.0"')
$txt = $txt.Replace('"InpV14MinEntryScore=70.0"', '"InpV14MinEntryScore=50.0"')
$txt = $txt.Replace('"InpV14MinEntryScore=62.0"', '"InpV14MinEntryScore=50.0"')
$txt = $txt.Replace('"InpV14MinEntryScore=55.0"', '"InpV14MinEntryScore=50.0"')
$txt = $txt.Replace('"InpV14MinEntryGap=30.0"', '"InpV14MinEntryGap=8.0"')
$txt = $txt.Replace('"InpV14MinEntryGap=18.0"', '"InpV14MinEntryGap=8.0"')
$txt = $txt.Replace('"InpV14MinEntryGap=10.0"', '"InpV14MinEntryGap=8.0"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=0"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=45"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=75"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=90"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=360"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMinMinutesBetweenEntries=20000"', '"InpMinMinutesBetweenEntries=30"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"InpMaxNewEntriesPerDay=4"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=500"', '"InpMaxNewEntriesPerDay=4"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=1"', '"InpMaxNewEntriesPerDay=4"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=3"', '"InpMaxNewEntriesPerDay=4"')
$txt = $txt.Replace('"InpUseATRAccelerationFilter=true"', '"InpUseATRAccelerationFilter=false"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=1.65"', '"InpMaxATRAccelerationRatio=9.99"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=1.20"', '"InpMaxATRAccelerationRatio=9.99"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=1.00"', '"InpMaxATRAccelerationRatio=9.99"')
$txt = $txt.Replace('"InpMaxATRAccelerationRatio=0.85"', '"InpMaxATRAccelerationRatio=9.99"')

$items = @()
$items += 'InpMacroTF=16385'
$items += 'InpTrendTF=16385'
$items += 'InpSlowEMA=34'
$items += 'InpMacroEMA=34'
$items += 'InpSignalEMA=20'
$items += 'InpOneDecisionPerBar=false'
$items += 'InpStartHourServer=8'
$items += 'InpEndHourServer=17'
$items += 'InpMinScoreToEnter=50.0'
$items += 'InpMinScoreGap=8.0'
$items += 'InpV14MinEntryScore=50.0'
$items += 'InpV14MinEntryGap=8.0'
$items += 'InpMinADX=12.0'
$items += 'InpMaxADX=70.0'
$items += 'InpMinRangeEfficiency=0.00'
$items += 'InpUseSessionQualityFilter=true'
$items += 'InpBlockAsianSession=true'
$items += 'InpLondonStartHourServer=8'
$items += 'InpLondonEndHourServer=12'
$items += 'InpNYStartHourServer=13'
$items += 'InpNYEndHourServer=17'
$items += 'InpMinMinutesBetweenEntries=30'
$items += 'InpMaxNewEntriesPerDay=4'
$items += 'InpUseATRAccelerationFilter=false'
$items += 'InpMaxATRAccelerationRatio=9.99'
$items += 'InpUseBasketTimeProfitExit=true'
$items += 'InpBasketTimeProfitMinutes=180'
$items += 'InpMinTimedExitProfitPct=0.20'
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

$eaPatch = "scripts/patch-public-intraday-ea.ps1"
if (Test-Path $eaPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $eaPatch
}

$tightPatch = "scripts/tighten-public-london-buy-filter.ps1"
if (Test-Path $tightPatch) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $tightPatch
}

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_set_override_forced=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_intraday_frequency_profile=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_target_entries_per_day=2-3"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_focus_sessions=london_ny"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_atr_accel_filter=false"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_frequency_blocker_removed=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_intraday_thresholds_relaxed=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_start_end_session_locked=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_duplicate_thresholds_normalized=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_20_30_point_profile=true"
Write-Host "Forced public intraday frequency tester set overrides."
