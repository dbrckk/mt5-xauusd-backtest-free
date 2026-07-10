$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Replace-RequiredLiteral([string]$Text, [string]$Old, [string]$New, [string]$Label) {
  if (!$Text.Contains($Old)) { throw "V35 runner lock failed: cannot find $Label." }
  return $Text.Replace($Old, $New)
}

function Set-LockedInput([string]$Text, [string]$Name, [string]$Value) {
  $pattern = '(?m)^\s*"' + [regex]::Escape($Name) + '=[^"]*",\s*$'
  $replacement = '  "' + $Name + '=' + $Value + '",'
  if ($Text -match $pattern) {
    return [regex]::Replace($Text, $pattern, $replacement, 1)
  }

  $terminalPattern = '(?m)^\s*"' + [regex]::Escape($Name) + '=[^"]*"\s*
  if ($Name -eq 'MaxTradesPerWeek' -and $Text -match $anchor) {
    $insert = '  "MaxTradesPerDay=1",' + "`n" + '  "MaxTradesPerWeek=4",'
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  $anchor = '(?m)^\s*"UseBreakEven=true",\s*$'
  if ($Name -in @('PipSize','MinTargetPips') -and $Text -match $anchor) {
    $insert = if ($Name -eq 'PipSize') {
      '  "PipSize=0.01",' + "`n" + '  "UseBreakEven=true",'
    } else {
      '  "MinTargetPips=400.0",' + "`n" + '  "UseBreakEven=true",'
    }
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  throw "V35 runner lock failed: cannot lock tester input $Name."
}

function Write-Stage([string]$Stage) {
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  "${stamp} stage=$Stage" | Add-Content -Path (Join-Path $script:reportsRoot "V35_WRAPPER_STAGE.txt") -Encoding UTF8
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null
$script:reportsRoot = $reportsRoot

try {
  Write-Stage "init"

  $sourceRunner = Join-Path $repo "scripts\run-ea-v27-public-backtest.ps1"
  if (!(Test-Path $sourceRunner)) { throw "Base public backtest runner missing: $sourceRunner" }

  $patchedRunner = Join-Path $env:RUNNER_TEMP "run-ea-v35-public-backtest.locked.ps1"
  $text = Get-Content -Path $sourceRunner -Raw -Encoding UTF8
  Write-Stage "base-runner-loaded"

  $replacements = [ordered]@{
    'V28_CONTEXTUAL_RISK.set' = 'V35_SELL_STRUCTURE.set'
    'V28_CONTEXTUAL_journal.csv' = 'V35_SELL_STRUCTURE_journal.csv'
    'V28_CURRENT_RUN.txt' = 'V35_CURRENT_RUN.txt'
    'V28_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
    'V28 Core Edge Router MT5 Backtest' = 'V35 Sell Structure MT5 Backtest'
    'XAUUSD_V28_Core_Edge_Router' = 'XAUUSD_V35_Sell_Structure_Quality_Gate'
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
    $text = Replace-RequiredLiteral $text ([string]$entry.Key) ([string]$entry.Value) ([string]$entry.Key)
  }

  $text = Replace-RequiredLiteral $text '$timeout = [Math]::Max(30, [Math]::Min(350, $timeout))' '$timeout = [Math]::Max(30, [Math]::Min(430, $timeout))' 'timeout clamp'
  $text = Replace-RequiredLiteral $text 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V28|Test passed|final balance|deal #|No money") {' 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V35|Test passed|final balance|deal #|No money") {' 'tester log filter escaped form'
  Write-Stage "literal-replacements-complete"

  $lockedInputs = [ordered]@{
    FixedLot = '0.02'
    UseRiskPercent = 'true'
    RiskPercent = '0.20'
    UseEquityForRisk = 'true'
    MaxRiskLot = '2.00'
    MaxTradesPerDay = '1'
    MaxTradesPerWeek = '4'
    CooldownMinutes = '180'
    LastEntryHour = '18'
    LastEntryMinute = '30'
    HardFlatHour = '20'
    HardFlatMinute = '45'
    BlockFridayLateEntries = 'true'
    FridayLastEntryHour = '17'
    CloseBeforeWeekend = 'true'
    FridayCloseHour = '19'
    EnableBuy = 'true'
    EnableSell = 'true'
    MinSignalScore = '91.0'
    MinDirectionScoreGap = '10.0'
    MinADX = '28.0'
    MaxSpreadATRFraction = '0.045'
    MinBodyRatio = '0.48'
    MinVolumeRatio = '1.18'
    BreakoutTP_ATR = '3.40'
    BreakoutSL_ATR = '0.82'
    PullbackTP_ATR = '3.20'
    PullbackSL_ATR = '0.78'
    ContinuationTP_ATR = '3.75'
    ContinuationSL_ATR = '0.74'
    SweepTP_ATR = '3.90'
    SweepSL_ATR = '0.76'
    PipSize = '0.01'
    MinTargetPips = '400.0'
    UseBreakEven = 'true'
    BreakEvenTriggerATR = '0.90'
    BreakEvenOffsetATR = '0.03'
    UseTrailingStop = 'true'
    TrailStartATR = '2.75'
    TrailDistanceATR = '1.10'
    MaxHoldBars = '28'
    TimeExitMinProgressATR = '0.45'
    UseCSVJournal = 'true'
    CSVJournalName = 'V35_SELL_STRUCTURE_journal.csv'
  }
  foreach ($entry in $lockedInputs.GetEnumerator()) {
    $text = Set-LockedInput $text ([string]$entry.Key) ([string]$entry.Value)
  }
  Write-Stage "locked-inputs-complete"

  $required = @(
    'V35_SELL_STRUCTURE.set',
    'RiskPercent=0.20',
    'MaxTradesPerDay=1',
    'MaxTradesPerWeek=4',
    'MinSignalScore=91.0',
    'MinADX=28.0',
    'MaxSpreadATRFraction=0.045',
    'MinBodyRatio=0.48',
    'MinVolumeRatio=1.18',
    'ContinuationTP_ATR=3.75',
    'ContinuationSL_ATR=0.74',
    'SweepTP_ATR=3.90',
    'SweepSL_ATR=0.76',
    'PipSize=0.01',
    'MinTargetPips=400.0',
    'CSVJournalName=V35_SELL_STRUCTURE_journal.csv',
    'routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14',
    'effective_profile=V35_SELL_STRUCTURE.set'
  )
  foreach ($marker in $required) {
    if (!$text.Contains($marker)) { throw "V35 runner lock failed: required marker missing: $marker" }
  }

  $forbidden = @(
    'CORE_PULLBACK_BUY_15',
    'V28_CONTEXTUAL_RISK.set',
    'MaxTradesPerDay=4',
    'MinSignalScore=78.0',
    'MinADX=20.0',
    'BreakoutTP_ATR=1.55',
    'ContinuationTP_ATR=1.30',
    'SweepTP_ATR=1.45'
  )
  foreach ($marker in $forbidden) {
    if ($text.Contains($marker)) { throw "V35 runner lock failed: forbidden stale marker remains: $marker" }
  }
  Write-Stage "marker-validation-complete"

  Set-Content -Path $patchedRunner -Value $text -Encoding UTF8
  Copy-Item $patchedRunner (Join-Path $reportsRoot "V35_LOCKED_RUNNER_PREVIEW.ps1") -Force
  Write-Stage "patched-runner-written"

  $consolePath = Join-Path $reportsRoot "V35_LOCKED_RUNNER_CONSOLE.log"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $patchedRunner *>&1 |
    Tee-Object -FilePath $consolePath
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  "exit_code=$code" | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_EXIT_CODE.txt") -Encoding UTF8
  if ($code -ne 0) {
    throw "V35 locked runner exited with code $code. See reports/V35_LOCKED_RUNNER_CONSOLE.log."
  }
  Write-Stage "completed"
} catch {
  $_ | Out-String | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_ERROR.txt") -Encoding UTF8
  throw
}

exit 0

  $terminalReplacement = '  "' + $Name + '=' + $Value + '"'
  if ($Text -match $terminalPattern) {
    return [regex]::Replace($Text, $terminalPattern, $terminalReplacement, 1)
  }

  $anchor = '(?m)^\s*"MaxTradesPerDay=1",\s*
  if ($Name -eq 'MaxTradesPerWeek' -and $Text -match $anchor) {
    $insert = '  "MaxTradesPerDay=1",' + "`n" + '  "MaxTradesPerWeek=4",'
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  $anchor = '(?m)^\s*"UseBreakEven=true",\s*$'
  if ($Name -in @('PipSize','MinTargetPips') -and $Text -match $anchor) {
    $insert = if ($Name -eq 'PipSize') {
      '  "PipSize=0.01",' + "`n" + '  "UseBreakEven=true",'
    } else {
      '  "MinTargetPips=400.0",' + "`n" + '  "UseBreakEven=true",'
    }
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  throw "V35 runner lock failed: cannot lock tester input $Name."
}

function Write-Stage([string]$Stage) {
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  "${stamp} stage=$Stage" | Add-Content -Path (Join-Path $script:reportsRoot "V35_WRAPPER_STAGE.txt") -Encoding UTF8
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null
$script:reportsRoot = $reportsRoot

try {
  Write-Stage "init"

  $sourceRunner = Join-Path $repo "scripts\run-ea-v27-public-backtest.ps1"
  if (!(Test-Path $sourceRunner)) { throw "Base public backtest runner missing: $sourceRunner" }

  $patchedRunner = Join-Path $env:RUNNER_TEMP "run-ea-v35-public-backtest.locked.ps1"
  $text = Get-Content -Path $sourceRunner -Raw -Encoding UTF8
  Write-Stage "base-runner-loaded"

  $replacements = [ordered]@{
    'V28_CONTEXTUAL_RISK.set' = 'V35_SELL_STRUCTURE.set'
    'V28_CONTEXTUAL_journal.csv' = 'V35_SELL_STRUCTURE_journal.csv'
    'V28_CURRENT_RUN.txt' = 'V35_CURRENT_RUN.txt'
    'V28_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
    'V28 Core Edge Router MT5 Backtest' = 'V35 Sell Structure MT5 Backtest'
    'XAUUSD_V28_Core_Edge_Router' = 'XAUUSD_V35_Sell_Structure_Quality_Gate'
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
    $text = Replace-RequiredLiteral $text ([string]$entry.Key) ([string]$entry.Value) ([string]$entry.Key)
  }

  $text = Replace-RequiredLiteral $text '$timeout = [Math]::Max(30, [Math]::Min(350, $timeout))' '$timeout = [Math]::Max(30, [Math]::Min(430, $timeout))' 'timeout clamp'
  $text = Replace-RequiredLiteral $text 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V28|Test passed|final balance|deal #|No money") {' 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V35|Test passed|final balance|deal #|No money") {' 'tester log filter escaped form'
  Write-Stage "literal-replacements-complete"

  $lockedInputs = [ordered]@{
    FixedLot = '0.02'
    UseRiskPercent = 'true'
    RiskPercent = '0.20'
    UseEquityForRisk = 'true'
    MaxRiskLot = '2.00'
    MaxTradesPerDay = '1'
    MaxTradesPerWeek = '4'
    CooldownMinutes = '180'
    LastEntryHour = '18'
    LastEntryMinute = '30'
    HardFlatHour = '20'
    HardFlatMinute = '45'
    BlockFridayLateEntries = 'true'
    FridayLastEntryHour = '17'
    CloseBeforeWeekend = 'true'
    FridayCloseHour = '19'
    EnableBuy = 'true'
    EnableSell = 'true'
    MinSignalScore = '91.0'
    MinDirectionScoreGap = '10.0'
    MinADX = '28.0'
    MaxSpreadATRFraction = '0.045'
    MinBodyRatio = '0.48'
    MinVolumeRatio = '1.18'
    BreakoutTP_ATR = '3.40'
    BreakoutSL_ATR = '0.82'
    PullbackTP_ATR = '3.20'
    PullbackSL_ATR = '0.78'
    ContinuationTP_ATR = '3.75'
    ContinuationSL_ATR = '0.74'
    SweepTP_ATR = '3.90'
    SweepSL_ATR = '0.76'
    PipSize = '0.01'
    MinTargetPips = '400.0'
    UseBreakEven = 'true'
    BreakEvenTriggerATR = '0.90'
    BreakEvenOffsetATR = '0.03'
    UseTrailingStop = 'true'
    TrailStartATR = '2.75'
    TrailDistanceATR = '1.10'
    MaxHoldBars = '28'
    TimeExitMinProgressATR = '0.45'
    UseCSVJournal = 'true'
    CSVJournalName = 'V35_SELL_STRUCTURE_journal.csv'
  }
  foreach ($entry in $lockedInputs.GetEnumerator()) {
    $text = Set-LockedInput $text ([string]$entry.Key) ([string]$entry.Value)
  }
  Write-Stage "locked-inputs-complete"

  $required = @(
    'V35_SELL_STRUCTURE.set',
    'RiskPercent=0.20',
    'MaxTradesPerDay=1',
    'MaxTradesPerWeek=4',
    'MinSignalScore=91.0',
    'MinADX=28.0',
    'MaxSpreadATRFraction=0.045',
    'MinBodyRatio=0.48',
    'MinVolumeRatio=1.18',
    'ContinuationTP_ATR=3.75',
    'ContinuationSL_ATR=0.74',
    'SweepTP_ATR=3.90',
    'SweepSL_ATR=0.76',
    'PipSize=0.01',
    'MinTargetPips=400.0',
    'CSVJournalName=V35_SELL_STRUCTURE_journal.csv',
    'routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14',
    'effective_profile=V35_SELL_STRUCTURE.set'
  )
  foreach ($marker in $required) {
    if (!$text.Contains($marker)) { throw "V35 runner lock failed: required marker missing: $marker" }
  }

  $forbidden = @(
    'CORE_PULLBACK_BUY_15',
    'V28_CONTEXTUAL_RISK.set',
    'MaxTradesPerDay=4',
    'MinSignalScore=78.0',
    'MinADX=20.0',
    'BreakoutTP_ATR=1.55',
    'ContinuationTP_ATR=1.30',
    'SweepTP_ATR=1.45'
  )
  foreach ($marker in $forbidden) {
    if ($text.Contains($marker)) { throw "V35 runner lock failed: forbidden stale marker remains: $marker" }
  }
  Write-Stage "marker-validation-complete"

  Set-Content -Path $patchedRunner -Value $text -Encoding UTF8
  Copy-Item $patchedRunner (Join-Path $reportsRoot "V35_LOCKED_RUNNER_PREVIEW.ps1") -Force
  Write-Stage "patched-runner-written"

  $consolePath = Join-Path $reportsRoot "V35_LOCKED_RUNNER_CONSOLE.log"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $patchedRunner *>&1 |
    Tee-Object -FilePath $consolePath
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  "exit_code=$code" | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_EXIT_CODE.txt") -Encoding UTF8
  if ($code -ne 0) {
    throw "V35 locked runner exited with code $code. See reports/V35_LOCKED_RUNNER_CONSOLE.log."
  }
  Write-Stage "completed"
} catch {
  $_ | Out-String | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_ERROR.txt") -Encoding UTF8
  throw
}

exit 0

  if ($Name -eq 'MaxTradesPerWeek' -and $Text -match $anchor) {
    $insert = '  "MaxTradesPerDay=1",' + "`n" + '  "MaxTradesPerWeek=4",'
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  $anchor = '(?m)^\s*"UseBreakEven=true",\s*$'
  if ($Name -in @('PipSize','MinTargetPips') -and $Text -match $anchor) {
    $insert = if ($Name -eq 'PipSize') {
      '  "PipSize=0.01",' + "`n" + '  "UseBreakEven=true",'
    } else {
      '  "MinTargetPips=400.0",' + "`n" + '  "UseBreakEven=true",'
    }
    return [regex]::Replace($Text, $anchor, $insert, 1)
  }

  throw "V35 runner lock failed: cannot lock tester input $Name."
}

function Write-Stage([string]$Stage) {
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  "${stamp} stage=$Stage" | Add-Content -Path (Join-Path $script:reportsRoot "V35_WRAPPER_STAGE.txt") -Encoding UTF8
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null
$script:reportsRoot = $reportsRoot

try {
  Write-Stage "init"

  $sourceRunner = Join-Path $repo "scripts\run-ea-v27-public-backtest.ps1"
  if (!(Test-Path $sourceRunner)) { throw "Base public backtest runner missing: $sourceRunner" }

  $patchedRunner = Join-Path $env:RUNNER_TEMP "run-ea-v35-public-backtest.locked.ps1"
  $text = Get-Content -Path $sourceRunner -Raw -Encoding UTF8
  Write-Stage "base-runner-loaded"

  $replacements = [ordered]@{
    'V28_CONTEXTUAL_RISK.set' = 'V35_SELL_STRUCTURE.set'
    'V28_CONTEXTUAL_journal.csv' = 'V35_SELL_STRUCTURE_journal.csv'
    'V28_CURRENT_RUN.txt' = 'V35_CURRENT_RUN.txt'
    'V28_PUBLIC_BACKTEST_FALLBACK_REPORT.html' = 'V35_PUBLIC_BACKTEST_FALLBACK_REPORT.html'
    'V28 Core Edge Router MT5 Backtest' = 'V35 Sell Structure MT5 Backtest'
    'XAUUSD_V28_Core_Edge_Router' = 'XAUUSD_V35_Sell_Structure_Quality_Gate'
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
    $text = Replace-RequiredLiteral $text ([string]$entry.Key) ([string]$entry.Value) ([string]$entry.Key)
  }

  $text = Replace-RequiredLiteral $text '$timeout = [Math]::Max(30, [Math]::Min(350, $timeout))' '$timeout = [Math]::Max(30, [Math]::Min(430, $timeout))' 'timeout clamp'
  $text = Replace-RequiredLiteral $text 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V28|Test passed|final balance|deal #|No money") {' 'if ($text -match "XAU_PUBLIC|XAUUSD_V27|V35|Test passed|final balance|deal #|No money") {' 'tester log filter escaped form'
  Write-Stage "literal-replacements-complete"

  $lockedInputs = [ordered]@{
    FixedLot = '0.02'
    UseRiskPercent = 'true'
    RiskPercent = '0.20'
    UseEquityForRisk = 'true'
    MaxRiskLot = '2.00'
    MaxTradesPerDay = '1'
    MaxTradesPerWeek = '4'
    CooldownMinutes = '180'
    LastEntryHour = '18'
    LastEntryMinute = '30'
    HardFlatHour = '20'
    HardFlatMinute = '45'
    BlockFridayLateEntries = 'true'
    FridayLastEntryHour = '17'
    CloseBeforeWeekend = 'true'
    FridayCloseHour = '19'
    EnableBuy = 'true'
    EnableSell = 'true'
    MinSignalScore = '91.0'
    MinDirectionScoreGap = '10.0'
    MinADX = '28.0'
    MaxSpreadATRFraction = '0.045'
    MinBodyRatio = '0.48'
    MinVolumeRatio = '1.18'
    BreakoutTP_ATR = '3.40'
    BreakoutSL_ATR = '0.82'
    PullbackTP_ATR = '3.20'
    PullbackSL_ATR = '0.78'
    ContinuationTP_ATR = '3.75'
    ContinuationSL_ATR = '0.74'
    SweepTP_ATR = '3.90'
    SweepSL_ATR = '0.76'
    PipSize = '0.01'
    MinTargetPips = '400.0'
    UseBreakEven = 'true'
    BreakEvenTriggerATR = '0.90'
    BreakEvenOffsetATR = '0.03'
    UseTrailingStop = 'true'
    TrailStartATR = '2.75'
    TrailDistanceATR = '1.10'
    MaxHoldBars = '28'
    TimeExitMinProgressATR = '0.45'
    UseCSVJournal = 'true'
    CSVJournalName = 'V35_SELL_STRUCTURE_journal.csv'
  }
  foreach ($entry in $lockedInputs.GetEnumerator()) {
    $text = Set-LockedInput $text ([string]$entry.Key) ([string]$entry.Value)
  }
  Write-Stage "locked-inputs-complete"

  $required = @(
    'V35_SELL_STRUCTURE.set',
    'RiskPercent=0.20',
    'MaxTradesPerDay=1',
    'MaxTradesPerWeek=4',
    'MinSignalScore=91.0',
    'MinADX=28.0',
    'MaxSpreadATRFraction=0.045',
    'MinBodyRatio=0.48',
    'MinVolumeRatio=1.18',
    'ContinuationTP_ATR=3.75',
    'ContinuationSL_ATR=0.74',
    'SweepTP_ATR=3.90',
    'SweepSL_ATR=0.76',
    'PipSize=0.01',
    'MinTargetPips=400.0',
    'CSVJournalName=V35_SELL_STRUCTURE_journal.csv',
    'routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14',
    'effective_profile=V35_SELL_STRUCTURE.set'
  )
  foreach ($marker in $required) {
    if (!$text.Contains($marker)) { throw "V35 runner lock failed: required marker missing: $marker" }
  }

  $forbidden = @(
    'CORE_PULLBACK_BUY_15',
    'V28_CONTEXTUAL_RISK.set',
    'MaxTradesPerDay=4',
    'MinSignalScore=78.0',
    'MinADX=20.0',
    'BreakoutTP_ATR=1.55',
    'ContinuationTP_ATR=1.30',
    'SweepTP_ATR=1.45'
  )
  foreach ($marker in $forbidden) {
    if ($text.Contains($marker)) { throw "V35 runner lock failed: forbidden stale marker remains: $marker" }
  }
  Write-Stage "marker-validation-complete"

  Set-Content -Path $patchedRunner -Value $text -Encoding UTF8
  Copy-Item $patchedRunner (Join-Path $reportsRoot "V35_LOCKED_RUNNER_PREVIEW.ps1") -Force
  Write-Stage "patched-runner-written"

  $consolePath = Join-Path $reportsRoot "V35_LOCKED_RUNNER_CONSOLE.log"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $patchedRunner *>&1 |
    Tee-Object -FilePath $consolePath
  $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
  "exit_code=$code" | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_EXIT_CODE.txt") -Encoding UTF8
  if ($code -ne 0) {
    throw "V35 locked runner exited with code $code. See reports/V35_LOCKED_RUNNER_CONSOLE.log."
  }
  Write-Stage "completed"
} catch {
  $_ | Out-String | Set-Content -Path (Join-Path $reportsRoot "V35_LOCKED_RUNNER_ERROR.txt") -Encoding UTF8
  throw
}

exit 0
