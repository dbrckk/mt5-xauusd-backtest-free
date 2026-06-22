$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$runner = Join-Path $PSScriptRoot "run-public-history-backtest.ps1"
$text = Get-Content -Path $runner -Raw

$fallbackFunction = @'
function Write-FallbackReport($ReportsRoot, $ReportPath, $CustomSymbol, $Period, $From, $To) {
  $allLogs = New-Object System.Collections.Generic.List[string]
  Get-ChildItem -Path $ReportsRoot -Recurse -Include *.log -File -ErrorAction SilentlyContinue | ForEach-Object {
    try { $txt = Get-Content -Path $_.FullName -Raw -Encoding Unicode } catch { try { $txt = Get-Content -Path $_.FullName -Raw -Encoding UTF8 } catch { $txt = "" } }
    if ($txt -match "XAU_PUBLIC|Test passed|final balance|testing of Experts") { $allLogs.Add("`n===== $($_.FullName) =====`n$txt") }
  }
  $logText = ($allLogs -join "`n")
  $quality = if ($logText -match "quality of analyzed history is\s+([0-9]+%)") { $Matches[1] } else { "unknown" }
  $balance = if ($logText -match "final balance\s+([0-9.]+)\s+USD") { $Matches[1] } else { "unknown" }
  $ticks = if ($logText -match "XAU_PUBLIC,M15:\s+([0-9]+)\s+ticks") { $Matches[1] } else { "unknown" }
  $bars = if ($logText -match "XAU_PUBLIC,M15:\s+[0-9]+\s+ticks,\s+([0-9]+)\s+bars") { $Matches[1] } else { "unknown" }
  $passed = if ($logText -match "Test passed") { "YES" } else { "NO" }
  $encoded = [System.Net.WebUtility]::HtmlEncode($logText)
  $fallback = Join-Path $ReportsRoot "QQ_PUBLIC_BACKTEST_FALLBACK_REPORT.html"
  $html = "<!doctype html><html><head><meta charset='utf-8'><title>MT5 Public XAU Backtest</title><style>body{font-family:Arial;margin:24px;line-height:1.45}td,th{border:1px solid #ccc;padding:6px 10px}table{border-collapse:collapse}pre{white-space:pre-wrap;background:#f4f4f4;padding:12px}</style></head><body><h1>MT5 Public XAU Backtest</h1><p>Fallback report generated from MT5 tester logs because MT5 did not export a standard HTML report file.</p><table><tr><th>Field</th><th>Value</th></tr><tr><td>Symbol</td><td>$CustomSymbol</td></tr><tr><td>Period</td><td>$Period</td></tr><tr><td>Range</td><td>$From to $To</td></tr><tr><td>History quality</td><td>$quality</td></tr><tr><td>Ticks</td><td>$ticks</td></tr><tr><td>Bars</td><td>$bars</td></tr><tr><td>Test passed</td><td>$passed</td></tr><tr><td>Final balance</td><td>$balance USD</td></tr></table><h2>Raw tester logs</h2><pre>$encoded</pre></body></html>"
  Set-Content -Path $fallback -Value $html -Encoding UTF8
  Set-Content -Path (Join-Path $ReportsRoot "fallback_report_reason.txt") -Value "MT5 standard report was missing or empty; fallback report generated from tester logs. Test passed=$passed; final_balance=$balance." -Encoding UTF8
  return $fallback
}
'@

if ($text -notmatch "function Write-FallbackReport") {
  $text = $text -replace '\$repo = \(Resolve-Path "\."\)\.Path', ($fallbackFunction + "`r`n`r`n" + '$repo = (Resolve-Path ".").Path')
}

$oldSet = 'Set-Content -Path $setPath -Value @("InpTradeSymbol=$customSymbol") -Encoding ASCII'
$newSet = @'
$setLines = @(
  "InpTradeSymbol=$customSymbol",
  "InpStrategyProfile=0",
  "InpUseRiskLot=false",
  "InpFixedLot=0.01",
  "InpMinScoreToEnter=45.0",
  "InpMinScoreGap=0.0",
  "InpV14MinEntryScore=45.0",
  "InpV14MinEntryGap=0.0",
  "InpV14RequireAlphaOrExplosive=false",
  "InpMinADX=0.0",
  "InpMaxADX=100.0",
  "InpMinATRPct=0.0",
  "InpMaxATRPct=10.0",
  "InpMaxSpreadPoints=9999.0",
  "InpMaxSpreadATRPercent=999.0",
  "InpMinRangeEfficiency=0.0",
  "InpMinMinutesBetweenEntries=0",
  "InpMaxNewEntriesPerDay=50",
  "InpStartHourServer=0",
  "InpEndHourServer=23",
  "InpBlockAsianSession=false",
  "InpBlockFridayLate=false",
  "InpCloseWeekendRisk=false",
  "InpRequireMacroAlignment=false",
  "InpAvoidDoji=false",
  "InpUseVWAPFilter=false",
  "InpUseSMCStructureScore=false",
  "InpUseVolatilityShockFilter=false",
  "InpUseTrendSlopeFilter=false",
  "InpUseConsecutiveCloseFilter=false",
  "InpUseATRAccelerationFilter=false",
  "InpUseSessionQualityFilter=false",
  "InpUseSpreadSpikeFilter=false",
  "InpUseATRNormalizedSpread=false",
  "InpUseLiquidityDistanceFilter=false",
  "InpUseAmbiguityPenalty=false",
  "InpUseEntryScoreDecayBlock=false",
  "InpUseV14ConvictionGate=false",
  "InpUseV14ShockPause=false",
  "InpUseCSVJournal=true",
  "InpCSVJournalName=QQ_PUBLIC_journal.csv",
  "InpVerboseDecisionLog=true",
  "InpVerboseLog=true"
)
Set-Content -Path $setPath -Value $setLines -Encoding ASCII
'@
$text = $text.Replace($oldSet, $newSet)

$text = $text.Replace('if (!(Test-Path $reportPath)) { throw "No MT5 report generated for public custom symbol. See found_reports.txt and logs." }', 'if (!(Test-Path $reportPath)) { $reportPath = Write-FallbackReport $reportsRoot $reportPath $customSymbol $period $from $to }')
$text = $text.Replace('if (!(Report-Usable $reportPath)) { throw "MT5 report exists but looks empty. Check logs." }', 'if (!(Report-Usable $reportPath)) { $reportPath = Write-FallbackReport $reportsRoot $reportPath $customSymbol $period $from $to }')

Set-Content -Path $runner -Value $text -Encoding UTF8
Write-Host "Patched public history runner for diagnostic settings and fallback report."
