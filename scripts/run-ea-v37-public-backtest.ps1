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
  'V35_SELL_STRUCTURE.set' = 'V39_STRUCTURE_IMPULSE.set'
  'V35_SELL_STRUCTURE_journal.csv' = 'V39_STRUCTURE_IMPULSE_journal.csv'
  'V35 Sell Structure MT5 Backtest' = 'V39 Structure Impulse MT5 Backtest'
  'XAUUSD_V35_Sell_Structure_Quality_Gate' = 'XAUUSD_V39_Structure_Impulse_Gate'
  'V35_CURRENT_RUN.txt' = 'V39_CURRENT_RUN.txt'
  'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V39_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
  'V35_MT5_ImportCustomSymbol.ini' = 'V39_MT5_ImportCustomSymbol.ini'
  'V35_MT5_Backtest.ini' = 'V39_MT5_Backtest.ini'
  'compile_v35_ea.log' = 'compile_v39_ea.log'
  'V35_WRAPPER_STAGE.txt' = 'V39_WRAPPER_STAGE.txt'
  'V35_LOCKED_RUNNER_PREVIEW.ps1' = 'V39_LOCKED_RUNNER_PREVIEW.ps1'
  'V35_LOCKED_RUNNER_CONSOLE.log' = 'V39_LOCKED_RUNNER_CONSOLE.log'
  'V35_LOCKED_RUNNER_EXIT_CODE.txt' = 'V39_LOCKED_RUNNER_EXIT_CODE.txt'
  'V35_LOCKED_RUNNER_ERROR.txt' = 'V39_LOCKED_RUNNER_ERROR.txt'
  'V35 locked runner' = 'V39 locked runner'
  'V35 runner lock failed' = 'V39 runner lock failed'
  'V35 EA' = 'V39 EA'
  'V35 Strategy Tester' = 'V39 Strategy Tester'
  'V35_${symbol}_${period}_${from}_${to}_model${model}' = 'V39_${symbol}_${period}_${from}_${to}_model${model}'
  "MinSignalScore = '91.0'" = "MinSignalScore = '76.0'"
  "MinADX = '28.0'" = "MinADX = '16.0'"
  "MaxSpreadATRFraction = '0.045'" = "MaxSpreadATRFraction = '0.070'"
  "MinBodyRatio = '0.48'" = "MinBodyRatio = '0.18'"
  "MinVolumeRatio = '1.18'" = "MinVolumeRatio = '0.75'"
  "'MinSignalScore=91.0'" = "'MinSignalScore=76.0'"
  "'MinADX=28.0'" = "'MinADX=16.0'"
  "'MaxSpreadATRFraction=0.045'" = "'MaxSpreadATRFraction=0.070'"
  "'MinBodyRatio=0.48'" = "'MinBodyRatio=0.18'"
  "'MinVolumeRatio=1.18'" = "'MinVolumeRatio=0.75'"
}

foreach ($entry in $replacements.GetEnumerator()) {
  if (!$text.Contains([string]$entry.Key)) {
    throw "V39 wrapper transform missing marker: $($entry.Key)"
  }
  $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
}

# V35 is itself a locked wrapper around the V27 runner. Inject the bounded
# downloader replacement into that inner transform rather than looking for the
# downloader marker in the outer V35 source, where it does not exist.
$anchor = '  Write-Stage "literal-replacements-complete"'
if (!$text.Contains($anchor)) {
  throw "V39 wrapper transform missing V35 downloader injection anchor"
}
$injection = @'
  $text = Replace-RequiredLiteral $text 'download_public_xau_m1.py' 'download_public_xau_m1_bounded.py' 'bounded public downloader'
  Write-Stage "literal-replacements-complete"
'@
$text = $text.Replace($anchor, $injection.TrimEnd())

$required = @(
  'V39_STRUCTURE_IMPULSE.set',
  'download_public_xau_m1_bounded.py',
  "MinSignalScore = '76.0'",
  "MinADX = '16.0'",
  "MaxSpreadATRFraction = '0.070'",
  "MinBodyRatio = '0.18'",
  "MinVolumeRatio = '0.75'",
  "CSVJournalName = 'V39_STRUCTURE_IMPULSE_journal.csv'",
  "'effective_profile=V39_STRUCTURE_IMPULSE.set'"
)
foreach ($marker in $required) {
  if (!$text.Contains($marker)) { throw "V39 runner marker missing: $marker" }
}

$forbidden = @('V35_SELL_STRUCTURE.set','V37_GEOMETRY_REGIME.set','MinSignalScore=91.0','MinSignalScore=88.0','MinADX=28.0','MinADX=25.0','MaxSpreadATRFraction=0.045','MaxSpreadATRFraction=0.050','MinBodyRatio=0.48','MinBodyRatio=0.42','MinVolumeRatio=1.18','MinVolumeRatio=1.10')
foreach ($marker in $forbidden) {
  if ($text.Contains($marker)) { throw "V39 runner stale marker remains: $marker" }
}

$patched = Join-Path $env:RUNNER_TEMP "run-ea-v39-public-backtest.locked.ps1"
Set-Content -Path $patched -Value $text -Encoding UTF8
Copy-Item $patched (Join-Path $reports "V39_WRAPPER_SOURCE.ps1") -Force

& pwsh -NoProfile -ExecutionPolicy Bypass -File $patched
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) { throw "V39 runner exited with code $code" }
exit 0