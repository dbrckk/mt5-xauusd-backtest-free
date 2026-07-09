$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$sourceRunner = Join-Path $repo "scripts\run-ea-v27-public-backtest.ps1"
if (!(Test-Path $sourceRunner)) { throw "Base public backtest runner missing: $sourceRunner" }

$patchedRunner = Join-Path $env:RUNNER_TEMP "run-ea-v35-public-backtest.locked.ps1"
$text = Get-Content -Path $sourceRunner -Raw -Encoding UTF8

$replacements = [ordered]@{
  'V28_CONTEXTUAL_RISK.set' = 'V35_SELL_STRUCTURE.set'
  'V28_CONTEXTUAL_journal.csv' = 'V35_SELL_STRUCTURE_journal.csv'
  'V28_CURRENT_RUN.txt' = 'V35_CURRENT_RUN.txt'
  'V28_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
  'V28 Core Edge Router MT5 Backtest' = 'V35 Sell Structure MT5 Backtest'
  'XAUUSD_V28_Core_Edge_Router' = 'XAUUSD_V35_Sell_Structure_Quality_Gate'
  'effective_profile=V35_SELL_STRUCTURE.set' = 'effective_profile=V35_SELL_STRUCTURE.set'
  'routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14' = 'routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14'
  'Section "Compile importer and V28 EA"' = 'Section "Compile importer and V35 EA"'
  'Section "Create canonical V28 tester profile"' = 'Section "Create canonical V35 tester profile"'
  'Section "Run V28 Strategy Tester"' = 'Section "Run V35 Strategy Tester"'
  'V28_${symbol}_${period}_${from}_${to}_model${model}' = 'V35_${symbol}_${period}_${from}_${to}_model${model}'
  'V28_MT5_ImportCustomSymbol.ini' = 'V35_MT5_ImportCustomSymbol.ini'
  'V28_MT5_Backtest.ini' = 'V35_MT5_Backtest.ini'
  'compile_v28_ea.log' = 'compile_v35_ea.log'
  'V28 EA source not found' = 'V35 EA source not found'
  'V28 EA compilation failed.' = 'V35 EA compilation failed.'
  'V28 backtest timed out after' = 'V35 backtest timed out after'
}
foreach ($entry in $replacements.GetEnumerator()) {
  $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
}

$text = $text.Replace('$timeout = [Math]::Max(30, [Math]::Min(350, $timeout))', '$timeout = [Math]::Max(30, [Math]::Min(430, $timeout))')
$text = $text.Replace('if ($text -match "XAU_PUBLIC|XAUUSD_V27|V28|Test passed|final balance|deal #|No money") {', 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V35|Test passed|final balance|deal #|No money") {')

if ($text -match 'CORE_PULLBACK_BUY_15') { throw 'V35 runner lock failed: forbidden CORE_PULLBACK_BUY_15 marker remains.' }
if ($text -match 'V28_CONTEXTUAL_RISK\.set') { throw 'V35 runner lock failed: legacy V28 tester profile remains.' }
if ($text -match 'RiskPercent=0\.20') { 'V35 runner risk lock confirmed: RiskPercent=0.20' | Write-Host } else { throw 'V35 runner risk lock missing.' }
if ($text -notmatch 'V35_SELL_STRUCTURE\.set') { throw 'V35 runner profile lock missing.' }

Set-Content -Path $patchedRunner -Value $text -Encoding UTF8
& pwsh -NoProfile -ExecutionPolicy Bypass -File $patchedRunner
exit $LASTEXITCODE
