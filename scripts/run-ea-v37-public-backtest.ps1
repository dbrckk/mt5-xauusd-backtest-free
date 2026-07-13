$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Set-V43ProfileValue([string]$Text, [string]$Name, [string]$OldValue, [string]$NewValue) {
  $assignmentPattern = "(?m)^(\s*" + [regex]::Escape($Name) + "\s*=\s*)'" + [regex]::Escape($OldValue) + "'(\s*)$"
  $matches = [regex]::Matches($Text, $assignmentPattern)
  if ($matches.Count -ne 1) {
    throw "V43 wrapper transform expected exactly one locked-input assignment for $Name=$OldValue; found $($matches.Count)"
  }

  $Text = [regex]::Replace($Text, $assignmentPattern, ('${1}' + "'" + $NewValue + "'" + '${2}'), 1)
  $markerOld = $Name + '=' + $OldValue
  $markerNew = $Name + '=' + $NewValue
  if ($Text.Contains($markerOld)) { $Text = $Text.Replace($markerOld, $markerNew) }

  if ($Text -notmatch ("(?m)^\s*" + [regex]::Escape($Name) + "\s*=\s*'" + [regex]::Escape($NewValue) + "'\s*$")) {
    throw "V43 wrapper transform failed to verify canonical assignment: $Name=$NewValue"
  }
  return $Text
}

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$source = Join-Path $repo "scripts\run-ea-v35-public-backtest.ps1"
if (!(Test-Path $source)) { throw "V35 locked runner missing: $source" }
$boundedDownloader = Join-Path $repo "scripts\download_public_xau_m1_bounded.py"
if (!(Test-Path $boundedDownloader)) { throw "Bounded public downloader missing: $boundedDownloader" }

$text = Get-Content -Path $source -Raw -Encoding UTF8
$replacements = [ordered]@{
  'V35_SELL_STRUCTURE.set' = 'V43_H8_DIRECT_BREAK.set'
  'V35_SELL_STRUCTURE_journal.csv' = 'V43_H8_DIRECT_BREAK_journal.csv'
  'V35 Sell Structure MT5 Backtest' = 'V43 Hour-8 Direct Break MT5 Backtest'
  'XAUUSD_V35_Sell_Structure_Quality_Gate' = 'XAUUSD_V43_H8_Direct_Break_Impulse_State'
  'V35_CURRENT_RUN.txt' = 'V43_CURRENT_RUN.txt'
  'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V43_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
  'V35_MT5_ImportCustomSymbol.ini' = 'V43_MT5_ImportCustomSymbol.ini'
  'V35_MT5_Backtest.ini' = 'V43_MT5_Backtest.ini'
  'compile_v35_ea.log' = 'compile_v43_ea.log'
  'V35_WRAPPER_STAGE.txt' = 'V43_WRAPPER_STAGE.txt'
  'V35_LOCKED_RUNNER_PREVIEW.ps1' = 'V43_LOCKED_RUNNER_PREVIEW.ps1'
  'V35_LOCKED_RUNNER_CONSOLE.log' = 'V43_LOCKED_RUNNER_CONSOLE.log'
  'V35_LOCKED_RUNNER_EXIT_CODE.txt' = 'V43_LOCKED_RUNNER_EXIT_CODE.txt'
  'V35_LOCKED_RUNNER_ERROR.txt' = 'V43_LOCKED_RUNNER_ERROR.txt'
  'V35 locked runner' = 'V43 locked runner'
  'V35 runner lock failed' = 'V43 runner lock failed'
  'V35 EA' = 'V43 EA'
  'V35 Strategy Tester' = 'V43 Strategy Tester'
  'V35_${symbol}_${period}_${from}_${to}_model${model}' = 'V43_${symbol}_${period}_${from}_${to}_model${model}'
}
foreach ($entry in $replacements.GetEnumerator()) {
  if (!$text.Contains([string]$entry.Key)) { throw "V43 wrapper transform missing marker: $($entry.Key)" }
  $text = $text.Replace([string]$entry.Key, [string]$entry.Value)
}

$profile = [ordered]@{
  MinSignalScore = @('91.0','68.0')
  MinADX = @('28.0','15.0')
  MaxSpreadATRFraction = @('0.045','0.075')
  MinBodyRatio = @('0.48','0.12')
  MinVolumeRatio = @('1.18','0.65')
  ContinuationTP_ATR = @('3.75','4.20')
  ContinuationSL_ATR = @('0.74','0.66')
  BreakEvenTriggerATR = @('0.90','1.15')
  TrailStartATR = @('2.75','3.00')
  TrailDistanceATR = @('1.10','1.20')
  MaxHoldBars = @('28','24')
  TimeExitMinProgressATR = @('0.45','0.30')
}
foreach ($entry in $profile.GetEnumerator()) {
  $text = Set-V43ProfileValue $text ([string]$entry.Key) ([string]$entry.Value[0]) ([string]$entry.Value[1])
}

$anchor = '  Write-Stage "literal-replacements-complete"'
if (!$text.Contains($anchor)) { throw "V43 wrapper transform missing V35 downloader injection anchor" }
$injection = @'
  $text = Replace-RequiredLiteral $text 'download_public_xau_m1.py' 'download_public_xau_m1_bounded.py' 'bounded public downloader'
  Write-Stage "literal-replacements-complete"
'@
$text = $text.Replace($anchor, $injection.TrimEnd())

$required = @(
  'V43_H8_DIRECT_BREAK.set',
  'download_public_xau_m1_bounded.py',
  "MinSignalScore = '68.0'",
  "MinADX = '15.0'",
  "MaxSpreadATRFraction = '0.075'",
  "MinBodyRatio = '0.12'",
  "MinVolumeRatio = '0.65'",
  "ContinuationTP_ATR = '4.20'",
  "ContinuationSL_ATR = '0.66'",
  "BreakEvenTriggerATR = '1.15'",
  "TrailStartATR = '3.00'",
  "TrailDistanceATR = '1.20'",
  "MaxHoldBars = '24'",
  "TimeExitMinProgressATR = '0.30'",
  "CSVJournalName = 'V43_H8_DIRECT_BREAK_journal.csv'",
  "'effective_profile=V43_H8_DIRECT_BREAK.set'"
)
foreach ($marker in $required) {
  if (!$text.Contains($marker)) { throw "V43 runner marker missing: $marker" }
}

$forbidden = @('V35_SELL_STRUCTURE.set','V37_GEOMETRY_REGIME.set','V39_STRUCTURE_IMPULSE.set','V40_H8_CONTINUATION.set','V41_H8_OPPORTUNITY.set','V42_H8_STATE_MACHINE.set','MinSignalScore=91.0','MinSignalScore=88.0','MinSignalScore=76.0','MinSignalScore=74.0','MinADX=28.0','MinADX=25.0','MinADX=18.0','MaxSpreadATRFraction=0.045','MaxSpreadATRFraction=0.050','MaxSpreadATRFraction=0.065','MinBodyRatio=0.48','MinBodyRatio=0.42','MinBodyRatio=0.20','MinVolumeRatio=1.18','MinVolumeRatio=1.10','MinVolumeRatio=0.80',"BreakEvenTriggerATR = '0.90'","TrailStartATR = '2.75'","TrailDistanceATR = '1.10'","MaxHoldBars = '28'","TimeExitMinProgressATR = '0.45'")
foreach ($marker in $forbidden) {
  if ($text.Contains($marker)) { throw "V43 runner stale marker remains: $marker" }
}

$patched = Join-Path $env:RUNNER_TEMP "run-ea-v43-public-backtest.locked.ps1"
Set-Content -Path $patched -Value $text -Encoding UTF8
Copy-Item $patched (Join-Path $reports "V43_WRAPPER_SOURCE.ps1") -Force

& pwsh -NoProfile -ExecutionPolicy Bypass -File $patched
$code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
if ($code -ne 0) { throw "V43 runner exited with code $code" }
exit 0
