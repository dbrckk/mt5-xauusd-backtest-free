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
$replacements = [ordered]@{
  '"InpMinScoreToEnter=70.0"' = '"InpMinScoreToEnter=50.0"'
  '"InpMinScoreToEnter=62.0"' = '"InpMinScoreToEnter=50.0"'
  '"InpMinScoreToEnter=55.0"' = '"InpMinScoreToEnter=50.0"'
  '"InpMinScoreGap=30.0"' = '"InpMinScoreGap=8.0"'
  '"InpMinScoreGap=18.0"' = '"InpMinScoreGap=8.0"'
  '"InpMinScoreGap=10.0"' = '"InpMinScoreGap=8.0"'
  '"InpV14MinEntryScore=70.0"' = '"InpV14MinEntryScore=50.0"'
  '"InpV14MinEntryScore=62.0"' = '"InpV14MinEntryScore=50.0"'
  '"InpV14MinEntryScore=55.0"' = '"InpV14MinEntryScore=50.0"'
  '"InpV14MinEntryGap=30.0"' = '"InpV14MinEntryGap=8.0"'
  '"InpV14MinEntryGap=18.0"' = '"InpV14MinEntryGap=8.0"'
  '"InpV14MinEntryGap=10.0"' = '"InpV14MinEntryGap=8.0"'
  '"InpMinMinutesBetweenEntries=0"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMinMinutesBetweenEntries=45"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMinMinutesBetweenEntries=75"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMinMinutesBetweenEntries=90"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMinMinutesBetweenEntries=360"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMinMinutesBetweenEntries=20000"' = '"InpMinMinutesBetweenEntries=30"'
  '"InpMaxNewEntriesPerDay=80"' = '"InpMaxNewEntriesPerDay=4"'
  '"InpMaxNewEntriesPerDay=500"' = '"InpMaxNewEntriesPerDay=4"'
  '"InpMaxNewEntriesPerDay=1"' = '"InpMaxNewEntriesPerDay=4"'
  '"InpMaxNewEntriesPerDay=3"' = '"InpMaxNewEntriesPerDay=4"'
  '"InpUseATRAccelerationFilter=true"' = '"InpUseATRAccelerationFilter=false"'
  '"InpMaxATRAccelerationRatio=1.65"' = '"InpMaxATRAccelerationRatio=9.99"'
  '"InpMaxATRAccelerationRatio=1.20"' = '"InpMaxATRAccelerationRatio=9.99"'
  '"InpMaxATRAccelerationRatio=1.00"' = '"InpMaxATRAccelerationRatio=9.99"'
  '"InpMaxATRAccelerationRatio=0.85"' = '"InpMaxATRAccelerationRatio=9.99"'
}
foreach ($key in $replacements.Keys) {
  $txt = $txt.Replace($key, $replacements[$key])
}

# V22+: download warmup + official validation range. Do not stop before FromDate.
$oldDownload = 'python (Join-Path $repo "scripts\download_public_xau_m1.py") $from $to $csvPath 2>&1 | Tee-Object -FilePath (Join-Path $reportsRoot "download_public_history.log")'
$newDownload = @'
$historyFrom = $from
try {
  $fromDateObj = [datetime]::ParseExact($from, 'yyyy.MM.dd', [System.Globalization.CultureInfo]::InvariantCulture)
  $historyFrom = $fromDateObj.AddDays(-21).ToString('yyyy.MM.dd')
} catch {
  Write-Host "Warmup date parse failed; using requested start date only: $from"
}
$maxHistoryDays = if ([string]::IsNullOrWhiteSpace($env:PUBLIC_MAX_HISTORY_DAYS)) { "60" } else { $env:PUBLIC_MAX_HISTORY_DAYS }
$maxDownloadSeconds = if ([string]::IsNullOrWhiteSpace($env:PUBLIC_MAX_DOWNLOAD_SECONDS)) { "2700" } else { $env:PUBLIC_MAX_DOWNLOAD_SECONDS }
$fetchTimeout = if ([string]::IsNullOrWhiteSpace($env:PUBLIC_FETCH_TIMEOUT_SECONDS)) { "20" } else { $env:PUBLIC_FETCH_TIMEOUT_SECONDS }
$fetchRetries = if ([string]::IsNullOrWhiteSpace($env:PUBLIC_FETCH_RETRIES)) { "2" } else { $env:PUBLIC_FETCH_RETRIES }
$env:PUBLIC_MAX_HISTORY_DAYS = $maxHistoryDays
$env:PUBLIC_MIN_BARS_TO_STOP = "999999999"
$env:PUBLIC_MAX_DOWNLOAD_SECONDS = $maxDownloadSeconds
$env:PUBLIC_MIN_REQUIRED_BARS = "700"
$env:PUBLIC_FETCH_TIMEOUT_SECONDS = $fetchTimeout
$env:PUBLIC_FETCH_RETRIES = $fetchRetries
Set-Content -Path (Join-Path $reportsRoot "public_history_requested_range.txt") -Value "requested_from=$from`nrequested_to=$to`nhistory_from=$historyFrom`nhistory_to=$to`nwarmup_days=21`npublic_max_history_days=$env:PUBLIC_MAX_HISTORY_DAYS`npublic_min_bars_to_stop=$env:PUBLIC_MIN_BARS_TO_STOP`npublic_max_download_seconds=$env:PUBLIC_MAX_DOWNLOAD_SECONDS`npublic_fetch_timeout_seconds=$env:PUBLIC_FETCH_TIMEOUT_SECONDS`npublic_fetch_retries=$env:PUBLIC_FETCH_RETRIES" -Encoding UTF8
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_warmup_history_download=true"
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_warmup_history_from=$historyFrom"
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_full_range_guard_runtime=true"
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_dynamic_history_days=$env:PUBLIC_MAX_HISTORY_DAYS"
python (Join-Path $repo "scripts\download_public_xau_m1.py") $historyFrom $to $csvPath 2>&1 | Tee-Object -FilePath (Join-Path $reportsRoot "download_public_history.log")
'@
if ($txt.Contains($oldDownload)) {
  $txt = $txt.Replace($oldDownload, $newDownload)
}

# V22: reject an imported CSV that ends before the tester FromDate.
$importGuardAnchor = 'if (!((Get-Content $importResult -Raw) -match "IMPORT_OK")) { Copy-Logs $dataPath $reportsRoot $dataRoot; throw "Custom symbol import failed." }'
$importGuard = @'
if (!((Get-Content $importResult -Raw) -match "IMPORT_OK")) { Copy-Logs $dataPath $reportsRoot $dataRoot; throw "Custom symbol import failed." }
try {
  $csvRows = Import-Csv -Path $csvPath
  if ($null -eq $csvRows -or $csvRows.Count -lt 2) { throw "CSV has no usable rows." }
  $lastCsvTime = [datetime]::ParseExact($csvRows[-1].time, 'yyyy.MM.dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
  $fromDateObj = [datetime]::ParseExact($from, 'yyyy.MM.dd', [System.Globalization.CultureInfo]::InvariantCulture)
  Set-Content -Path (Join-Path $reportsRoot "public_import_range_guard.txt") -Value "from=$from`nlast_csv_time=$($lastCsvTime.ToString('yyyy.MM.dd HH:mm'))" -Encoding UTF8
  if ($lastCsvTime -lt $fromDateObj) {
    throw "Imported public history ends before tester FromDate. last_csv_time=$($lastCsvTime.ToString('yyyy.MM.dd HH:mm')) from=$from"
  }
  Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_import_range_guard=passed"
} catch {
  Copy-Logs $dataPath $reportsRoot $dataRoot
  throw "Public import range guard failed: $($_.Exception.Message)"
}
'@
if ($txt.Contains($importGuardAnchor) -and -not $txt.Contains('public_import_range_guard=passed')) {
  $txt = $txt.Replace($importGuardAnchor, $importGuard)
}

$items = @(
  'InpMacroTF=16385',
  'InpTrendTF=16385',
  'InpSlowEMA=34',
  'InpMacroEMA=34',
  'InpSignalEMA=20',
  'InpOneDecisionPerBar=false',
  'InpStartHourServer=8',
  'InpEndHourServer=17',
  'InpMinScoreToEnter=50.0',
  'InpMinScoreGap=8.0',
  'InpV14MinEntryScore=50.0',
  'InpV14MinEntryGap=8.0',
  'InpMinADX=12.0',
  'InpMaxADX=70.0',
  'InpMinRangeEfficiency=0.00',
  'InpUseSessionQualityFilter=true',
  'InpBlockAsianSession=true',
  'InpLondonStartHourServer=8',
  'InpLondonEndHourServer=12',
  'InpNYStartHourServer=13',
  'InpNYEndHourServer=17',
  'InpMinMinutesBetweenEntries=30',
  'InpMaxNewEntriesPerDay=4',
  'InpUseATRAccelerationFilter=false',
  'InpMaxATRAccelerationRatio=9.99',
  'InpUseBasketTimeProfitExit=true',
  'InpBasketTimeProfitMinutes=180',
  'InpMinTimedExitProfitPct=0.20',
  'InpUseScoreDivergenceExit=false',
  'InpUseSignalDecayExit=false',
  'InpCloseOnRunnerExhaustion=false',
  'InpUseFastLoserCut=false',
  'InpUseEarlyBadTradeAbort=false',
  'InpCloseStaleLossBasket=false',
  'InpCloseStaleBasketIfProfit=false',
  'InpUseBasketProfitLock=false',
  'InpUseBreakEven=false',
  'InpUseTrailing=false',
  'InpUseBasketNetBreakEvenLock=false',
  'InpUseV14RunnerMFEGuard=false',
  'InpUseV17RunnerProfitElasticity=false'
)
$quoted = ($items | ForEach-Object { '"' + $_ + '"' }) -join ','
$line = '$setLines += @(' + $quoted + ')'
if (-not $txt.Contains('public_v22_setline_injection_marker')) {
  $txt = $txt.Replace($marker, '# public_v22_setline_injection_marker' + "`r`n" + $line + "`r`n" + $marker)
}

# V22: reject zero-bar MT5 runs before writing PUBLIC_HISTORY_BACKTEST_OK.
$okAnchor = 'Write-Host "PUBLIC_HISTORY_BACKTEST_OK symbol=$customSymbol report=$reportPath"'
$zeroGuard = @'
$guardLogText = Read-LogText $reportsRoot
$zeroPattern = [regex]::Escape("$customSymbol,$period") + "\s*:\s*0\s+ticks,\s*0\s+bars"
if ($guardLogText -match $zeroPattern) {
  Set-Content -Path (Join-Path $reportsRoot "public_zero_bar_guard.txt") -Value "failed_zero_ticks_zero_bars symbol=$customSymbol period=$period" -Encoding UTF8
  throw "Invalid public backtest: MT5 generated 0 ticks / 0 bars for $customSymbol,$period."
}
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_zero_bar_guard=passed"
Write-Host "PUBLIC_HISTORY_BACKTEST_OK symbol=$customSymbol report=$reportPath"
'@
if ($txt.Contains($okAnchor) -and -not $txt.Contains('public_zero_bar_guard=passed')) {
  $txt = $txt.Replace($okAnchor, $zeroGuard)
}

Set-Content -Path $runner -Value $txt -Encoding UTF8

$eaPatch = "scripts/patch-public-intraday-ea.ps1"
if (Test-Path $eaPatch) {
  & pwsh -NoProfile -File $eaPatch
}

$tightPatch = "scripts/tighten-public-london-buy-filter.ps1"
if (Test-Path $tightPatch) {
  & pwsh -NoProfile -File $tightPatch
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
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v22_runtime_full_range_fix=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_dynamic_history_window_support=true"
Write-Host "Forced public intraday tester overrides with dynamic full-range guards."
