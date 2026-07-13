$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$source = Join-Path $repo "scripts\run-ea-v35-public-backtest.ps1"
if (!(Test-Path $source)) { throw "V35 locked runner missing: $source" }

$boundedDownloader = Join-Path $repo "scripts\download_public_xau_m1_bounded.py"
if (!(Test-Path $boundedDownloader)) { throw "Bounded public downloader missing: $boundedDownloader" }

$text = Get-Content -Path $source -Raw -Encoding UTF8
$replacements = [ordered]@{
  'V35_SELL_STRUCTURE.set' = 'V40_H8_CONTINUATION.set'
  'V35_SELL_STRUCTURE_journal.csv' = 'V40_H8_CONTINUATION_journal.csv'
  'V35 Sell Structure MT5 Backtest' = 'V40 Hour-8 Continuation MT5 Backtest'
  'XAUUSD_V35_Sell_Structure_Quality_Gate' = 'XAUUSD_V40_H8_Continuation_State_Gate'
  'V35_CURRENT_RUN.txt' = 'V40_CURRENT_RUN.txt'
  'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V40_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
  'V35_MT5_ImportCustomSymbol.ini' = 'V40_MT5_ImportCustomSymbol.ini'
  'V35_MT5_Backtest.ini' = 'V40_MT5_Backtest.ini'
  'compile_v35_ea.log' = 'compile_v40_ea.log'
  'V35_WRAPPER_STAGE.txt' = 'V40_WRAPPER_STAGE.txt'
  'V35_LOCKED_RUNNER_PREVIEW.ps1' = 'V40_LOCKED_RUNNER_PREVIEW.ps1'
  'V35_LOCKED_RUNNER_CONSOLE.log' = 'V40_LOCKED_RUNNER_CONSOLE.log'
  'V35_LOCKED_RUNNER_EXIT_CODE.txt' = 'V40_LOCKED_RUNNER_EXIT_CODE.txt'
  'V35_LOCKED_RUNNER_ERROR.txt' = 'V40_LOCKED_RUNNER_ERROR.txt'
  'V35 locked runner' = 'V40 locked runner'
  'V35 runner lock failed' = 'V40 runner lock failed'
  'V35 EA' = 'V40 EA'
  'V35 Strategy Tester' = 'V40 Strategy Tester'
  'V35_${symbol}_${period}_${from}_${to}_model${model}' = 'V40_${symbol}_${period}_${from}_${to}_model${model}'
  "MinSignalScore = '91.0'" = "MinSignalScore = '74.0'"
  "MinADX = '28.0'" = "MinADX = '18.0'"
  "MaxSpreadATRFraction = '0.045'" = "MaxSpreadATRFraction = '0.065'"
  "MinBodyRatio = '0.48'" = "MinBodyRatio = '0.20'"
  "MinVolumeRatio = '1.18'" = "MinVolumeRatio = '0.80'"
  "ContinuationTP_ATR = '3.75'" = "ContinuationTP_ATR = '4.20'"
  "ContinuationSL_ATR = '0.74'" = "ContinuationSL_ATR = '0.66'"
  "TrailStartATR = '2.75'" = "TrailStartATR = '3.00'"
  "TrailDistanceATR = '1.10'" = "TrailDistanceATR = '1.20'"
  "MaxHoldBars = '28'" = "MaxHoldBars = '24'"
  "TimeExitMinProgressATR = '0.45'" = "TimeExitMinProgressATR = '0.30'"
  "'MinSignalScore=91.0'" = "'MinSignalScore=74.0'"
  "'MinADX=28.0'" = "'MinADX=18.0'"
  "'MaxSpreadATRFraction=0.045'" = "'MaxSpreadATRFraction=0.065'"
  "'MinBodyRatio=0.48'" = "'MinBodyRatio=0.20'"
  "'MinVolumeRatio=1.18'" = "'MinVolumeRatio=0.80'"
  "'ContinuationTP_ATR=3.75'" = "'ContinuationTP_ATR=4.20'"
  "'ContinuationSL_ATR=0.74'" = "'ContinuationSL_ATR=0.66'"
  "'TrailStartATR=2.75'" = "'TrailStartATR=3.00'"
  "'TrailDistanceATR=1.10'" = "'TrailDistanceATR=1.20'"
  "'MaxHoldBars=28'" = "'MaxHoldBars=24'"
  "'TimeExitMinProgressATR=0.45'" = "'TimeExitMinProgressATR=0.30'"
}

foreach ($entry in $replacements.GetEnumerator()) {
  if (!$text.Contains([string]$entry.Key)) {
    throw "V40 wrapper transform missing marker: $($entry.Key)"
  }
  $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
}

# Break-even is intentionally patched with an anchored regex rather than two brittle
# literal replacements. This changes the locked-input assignment itself; the generated
# runner therefore receives the V40 value without depending on formatting in the V35
# validation-marker list.
$breakEvenPattern = "(?m)^(\s*BreakEvenTriggerATR\s*=\s*)'0\.90'(\s*)$"
if ($text -notmatch $breakEvenPattern) {
  throw "V40 wrapper transform missing BreakEvenTriggerATR locked-input assignment"
}
$text = [regex]::Replace($text, $breakEvenPattern, '${1}''1.15''${2}', 1)

$anchor = '  Write-Stage "literal-replacements-complete"'
if (!$text.Contains($anchor)) {
  throw "V40 wrapper transform missing V35 downloader injection anchor"
}
$injection = @'
  $text = Replace-RequiredLiteral $text 'download_public_xau_m1.py' 'download_public_xau_m1_bounded.py' 'bounded public downloader'
  Write-Stage "literal-replacements-complete"
'@
$text = $text.Replace($anchor, $injection.TrimEnd())

$required = @(
  'V40_H8_CONTINUATION.set',
  'download_public_xau_m1_bounded.py',
  "MinSignalScore = '74.0'",
  "MinADX = '18.0'",
  "MaxSpreadATRFraction = '0.065'",
  "MinBodyRatio = '0.20'",
  "MinVolumeRatio = '0.80'",
  "ContinuationTP_ATR = '4.20'",
  "ContinuationSL_ATR = '0.66'",
  "BreakEvenTriggerATR = '1.15'",
  "TrailStartATR = '3.00'",
  "TrailDistanceATR = '1.20'",
  "MaxHoldBars = '24'",
  "TimeExitMinProgressATR = '0.30'",
  "CSVJournalName = 'V40_H8_CONTINUATION_journal.csv'",
  "'effective_profile=V40_H8_CONTINUATION.set'"
)
foreach ($marker in $required) {
  if (!$text.Contains($marker)) { throw "V40 runner marker missing: $marker" }
}

$forbidden = @('V35_SELL_STRUCTURE.set','V37_GEOMETRY_REGIME.set','V39_STRUCTURE_IMPULSE.set','MinSignalScore=91.0','MinSignalScore=88.0','MinSignalScore=76.0','MinADX=28.0','MinADX=25.0','MinADX=16.0','MaxSpreadATRFraction=0.045','MaxSpreadATRFraction=0.050','MaxSpreadATRFraction=0.070','MinBodyRatio=0.48','MinBodyRatio=0.42','MinBodyRatio=0.18','MinVolumeRatio=1.18','MinVolumeRatio=1.10','MinVolumeRatio=0.75',"BreakEvenTriggerATR = '0.90'")
foreach ($marker in $forbidden) {
  if ($text.Contains($marker)) { throw "V40 runner stale marker remains: $marker" }
}

$patched = Join-Path $env:RUNNER_TEMP "run-ea-v40-public-backtest.locked.ps1"
Set-Content -Path $patched -Value $text -Encoding UTF8
Copy-Item $patched (Join-Path $reports "V40_WRAPPER_SOURCE.ps1") -Force

& pwsh -NoProfile -ExecutionPolicy Bypass -File $patched
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) { throw "V40 runner exited with code $code" }
exit 0