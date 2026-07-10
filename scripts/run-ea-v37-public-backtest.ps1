$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$source = Join-Path $repo "scripts\run-ea-v35-public-backtest.ps1"
if (!(Test-Path $source)) { throw "V35 locked runner missing: $source" }

$text = Get-Content -Path $source -Raw -Encoding UTF8
$replacements = [ordered]@{
  'V35_SELL_STRUCTURE.set' = 'V37_GEOMETRY_REGIME.set'
  'V35_SELL_STRUCTURE_journal.csv' = 'V37_GEOMETRY_REGIME_journal.csv'
  'V35 Sell Structure MT5 Backtest' = 'V37 Geometry Regime MT5 Backtest'
  'XAUUSD_V35_Sell_Structure_Quality_Gate' = 'XAUUSD_V37_Geometry_Regime_Gate'
  'V35_CURRENT_RUN.txt' = 'V37_CURRENT_RUN.txt'
  'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V37_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
  'V35_MT5_ImportCustomSymbol.ini' = 'V37_MT5_ImportCustomSymbol.ini'
  'V35_MT5_Backtest.ini' = 'V37_MT5_Backtest.ini'
  'compile_v35_ea.log' = 'compile_v37_ea.log'
  'V35_WRAPPER_STAGE.txt' = 'V37_WRAPPER_STAGE.txt'
  'V35_LOCKED_RUNNER_PREVIEW.ps1' = 'V37_LOCKED_RUNNER_PREVIEW.ps1'
  'V35_LOCKED_RUNNER_CONSOLE.log' = 'V37_LOCKED_RUNNER_CONSOLE.log'
  'V35_LOCKED_RUNNER_EXIT_CODE.txt' = 'V37_LOCKED_RUNNER_EXIT_CODE.txt'
  'V35_LOCKED_RUNNER_ERROR.txt' = 'V37_LOCKED_RUNNER_ERROR.txt'
  'V35 locked runner' = 'V37 locked runner'
  'V35 runner lock failed' = 'V37 runner lock failed'
  'V35 EA' = 'V37 EA'
  'V35 Strategy Tester' = 'V37 Strategy Tester'
  'V35_${symbol}_${period}_${from}_${to}_model${model}' = 'V37_${symbol}_${period}_${from}_${to}_model${model}'
  "MinSignalScore = '91.0'" = "MinSignalScore = '88.0'"
  "MinADX = '28.0'" = "MinADX = '25.0'"
  "MaxSpreadATRFraction = '0.045'" = "MaxSpreadATRFraction = '0.050'"
  "MinBodyRatio = '0.48'" = "MinBodyRatio = '0.42'"
  "MinVolumeRatio = '1.18'" = "MinVolumeRatio = '1.10'"
  "'MinSignalScore=91.0'" = "'MinSignalScore=88.0'"
  "'MinADX=28.0'" = "'MinADX=25.0'"
  "'MaxSpreadATRFraction=0.045'" = "'MaxSpreadATRFraction=0.050'"
  "'MinBodyRatio=0.48'" = "'MinBodyRatio=0.42'"
  "'MinVolumeRatio=1.18'" = "'MinVolumeRatio=1.10'"
  'CSVJournalName = ''V35_SELL_STRUCTURE_journal.csv''' = 'CSVJournalName = ''V37_GEOMETRY_REGIME_journal.csv'''
  "'CSVJournalName=V35_SELL_STRUCTURE_journal.csv'" = "'CSVJournalName=V37_GEOMETRY_REGIME_journal.csv'"
  "'effective_profile=V35_SELL_STRUCTURE.set'" = "'effective_profile=V37_GEOMETRY_REGIME.set'"
}

foreach ($entry in $replacements.GetEnumerator()) {
  if (!$text.Contains([string]$entry.Key)) {
    throw "V37 wrapper transform missing marker: $($entry.Key)"
  }
  $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
}

$required = @(
  'V37_GEOMETRY_REGIME.set',
  "MinSignalScore = '88.0'",
  "MinADX = '25.0'",
  "MaxSpreadATRFraction = '0.050'",
  "MinBodyRatio = '0.42'",
  "MinVolumeRatio = '1.10'",
  "CSVJournalName = 'V37_GEOMETRY_REGIME_journal.csv'",
  "'effective_profile=V37_GEOMETRY_REGIME.set'"
)
foreach ($marker in $required) {
  if (!$text.Contains($marker)) { throw "V37 runner marker missing: $marker" }
}

$forbidden = @('V35_SELL_STRUCTURE.set','MinSignalScore=91.0','MinADX=28.0','MaxSpreadATRFraction=0.045','MinBodyRatio=0.48','MinVolumeRatio=1.18')
foreach ($marker in $forbidden) {
  if ($text.Contains($marker)) { throw "V37 runner stale marker remains: $marker" }
}

$patched = Join-Path $env:RUNNER_TEMP "run-ea-v37-public-backtest.locked.ps1"
Set-Content -Path $patched -Value $text -Encoding UTF8
Copy-Item $patched (Join-Path $reports "V37_WRAPPER_SOURCE.ps1") -Force

& pwsh -NoProfile -ExecutionPolicy Bypass -File $patched
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) { throw "V37 runner exited with code $code" }
exit 0