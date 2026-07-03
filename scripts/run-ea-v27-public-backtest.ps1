$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Section([string]$Title) {
  Write-Host ""
  Write-Host "==================== $Title ===================="
}

function Kill-MT5 {
  Get-Process -Name "terminal64","terminal","metaeditor64","metaeditor","metatester64","metatester" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

function Find-File([string[]]$Roots, [string]$Name) {
  foreach ($root in $Roots) {
    if (!(Test-Path $root)) { continue }
    $file = Get-ChildItem -Path $root -Filter $Name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $file) { return $file.FullName }
  }
  return $null
}

function Download-File([string[]]$Urls, [string]$Destination) {
  foreach ($url in $Urls) {
    try {
      Write-Host "Downloading: $url"
      Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 180
      if ((Test-Path $Destination) -and ((Get-Item $Destination).Length -gt 100000)) {
        return $true
      }
    } catch {
      Write-Host "Download failed: $($_.Exception.Message)"
    }
  }
  return $false
}

function Read-AnyText([string]$Path) {
  if (!(Test-Path $Path)) { return "" }
  try { return Get-Content -Path $Path -Raw -Encoding Unicode } catch {}
  try { return Get-Content -Path $Path -Raw -Encoding UTF8 } catch {}
  try { return Get-Content -Path $Path -Raw } catch {}
  return ""
}

function Copy-TreeFiles([string]$Source, [string]$TargetRoot, [string]$Label) {
  if (!(Test-Path $Source)) { return }
  $target = Join-Path $TargetRoot $Label
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Copy-Item (Join-Path $Source "*") $target -Recurse -Force -ErrorAction SilentlyContinue
}

function Copy-Logs([string]$DataPath, [string]$ReportsRoot, [string]$DataRoot) {
  Copy-TreeFiles (Join-Path $DataPath "Logs") $ReportsRoot "terminal_logs_copy"
  Copy-TreeFiles (Join-Path $DataPath "MQL5\Logs") $ReportsRoot "mql5_logs_copy"
  Copy-TreeFiles (Join-Path $DataPath "Tester\logs") $ReportsRoot "tester_logs_copy"
  Copy-TreeFiles (Join-Path $DataPath "Tester\cache") $ReportsRoot "tester_cache_copy"
  Copy-TreeFiles (Join-Path $env:APPDATA "MetaQuotes\Tester") $ReportsRoot "metatester_copy"
}

function Add-Account([string]$IniPath, [string]$ReportsRoot) {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo "scripts\add-account-lines.ps1") -Path $IniPath
  $safe = [IO.Path]::Combine(
    [IO.Path]::GetDirectoryName($IniPath),
    ([IO.Path]::GetFileNameWithoutExtension($IniPath) + ".sanitized.ini")
  )
  if (Test-Path $safe) {
    Copy-Item $safe (Join-Path $ReportsRoot ([IO.Path]::GetFileName($safe))) -Force
  }
}

function Copy-FoundReports([string[]]$Roots, [string]$ReportsRoot) {
  $copied = @()
  foreach ($root in $Roots) {
    if (!(Test-Path $root)) { continue }
    Get-ChildItem -Path $root -Recurse -Include *.htm,*.html,*.xml -File -ErrorAction SilentlyContinue | ForEach-Object {
      $target = Join-Path $ReportsRoot $_.Name
      Copy-Item $_.FullName $target -Force -ErrorAction SilentlyContinue
      $copied += $target
    }
  }
  return $copied
}

function Read-TesterLogBlob([string]$ReportsRoot) {
  $parts = @()
  Get-ChildItem -Path $ReportsRoot -Recurse -Include *.log -File -ErrorAction SilentlyContinue | ForEach-Object {
    $text = Read-AnyText $_.FullName
    if ($text -match "XAU_PUBLIC|XAUUSD_V27|Test passed|final balance|deal #|No money") {
      $parts += "`n===== $($_.FullName) =====`n$text"
    }
  }
  return ($parts -join "`n")
}

function Write-FallbackReport(
  [string]$ReportsRoot,
  [string]$Symbol,
  [string]$Period,
  [string]$FromDate,
  [string]$ToDate
) {
  $logText = Read-TesterLogBlob $ReportsRoot
  $balance = if ($logText -match "final balance\s+([0-9.]+)\s+USD") { $Matches[1] } else { "unknown" }
  $passed = if ($logText -match "Test passed") { "YES" } else { "NO" }
  $encoded = [System.Net.WebUtility]::HtmlEncode($logText)
  $path = Join-Path $ReportsRoot "V27_PUBLIC_BACKTEST_FALLBACK_REPORT.html"
  $html = @"
<!doctype html>
<html>
<head><meta charset="utf-8"><title>V27 Clean MT5 Backtest</title></head>
<body>
<h1>V27 Clean MT5 Backtest</h1>
<table>
<tr><th>Symbol</th><td>$Symbol</td></tr>
<tr><th>Period</th><td>$Period</td></tr>
<tr><th>Range</th><td>$FromDate to $ToDate</td></tr>
<tr><th>Test passed</th><td>$passed</td></tr>
<tr><th>Final balance</th><td>$balance USD</td></tr>
</table>
<pre>$encoded</pre>
</body>
</html>
"@
  Set-Content -Path $path -Value $html -Encoding UTF8
  return $path
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$symbol = "XAU_PUBLIC"
$period = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M15" }
$from = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2023.06.21" }
$to = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { "2024.06.21" }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "15000" }
$leverage = if ($env:BT_LEVERAGE) { $env:BT_LEVERAGE } else { "1:100" }
$model = if ($env:BT_MODEL) { $env:BT_MODEL } else { "0" }
$timeout = 350
if ($env:BT_TIMEOUT_MINUTES) {
  [int]::TryParse($env:BT_TIMEOUT_MINUTES, [ref]$timeout) | Out-Null
}
$timeout = [Math]::Max(30, [Math]::Min(350, $timeout))

$eaSource = Join-Path $repo "MQL5\Experts\XAUUSD_V27_Clean_MultiSetup.mq5"
$importerSource = Join-Path $repo "MQL5\Experts\ImportCustomRatesEA.mq5"

if (!(Test-Path $eaSource)) { throw "EA source not found: $eaSource" }
if (!(Test-Path $importerSource)) { throw "Importer source not found: $importerSource" }

$runMarker = @(
  "strategy=XAUUSD_V27_Clean_MultiSetup",
  "forced_trades=false",
  "arbitrary_daily_close=false",
  "natural_setups=BREAKOUT,PULLBACK,CONTINUATION,SWEEP",
  "symbol=$symbol",
  "period=$period",
  "from_date=$from",
  "to_date=$to",
  "deposit=$deposit",
  "leverage=$leverage",
  "model=$model"
)
$runMarker | Set-Content -Path (Join-Path $reportsRoot "V27_CURRENT_RUN.txt") -Encoding UTF8

Section "Install MetaTrader 5"
$installer = Join-Path $env:RUNNER_TEMP "mt5setup.exe"
$urls = @(
  "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe",
  "https://download.mql5.com/cdn/web/metaquotes.ltd/mt5/mt5setup.exe"
)
if (!(Download-File $urls $installer)) {
  throw "Could not download MT5 installer."
}

$terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $terminal) {
  $process = Start-Process -FilePath $installer -ArgumentList "/auto" -PassThru
  $process.WaitForExit(180000) | Out-Null
  Start-Sleep -Seconds 25
  Kill-MT5
}

$terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $terminal) { throw "terminal64.exe not found." }

$metaeditor = Join-Path (Split-Path $terminal -Parent) "metaeditor64.exe"
if (!(Test-Path $metaeditor)) { throw "metaeditor64.exe not found." }

Section "Create MT5 data folder"
Kill-MT5
Start-Process -FilePath $terminal | Out-Null
Start-Sleep -Seconds 60
Kill-MT5

$dataRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (!(Test-Path $dataRoot)) { throw "MT5 data root not found: $dataRoot" }

$dataPathObject = Get-ChildItem -Path $dataRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notin @("Common","Community") -and (Test-Path (Join-Path $_.FullName "MQL5")) } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($null -eq $dataPathObject) {
  throw "No usable MT5 terminal data folder found."
}
$dataPath = $dataPathObject.FullName
Set-Content -Path (Join-Path $reportsRoot "mt5_data_path.txt") -Value $dataPath -Encoding UTF8

Section "Download strict public XAUUSD history"
$publicDir = Join-Path $reportsRoot "public_history"
New-Item -ItemType Directory -Force -Path $publicDir | Out-Null
$csvPath = Join-Path $publicDir "xau_public_m1.csv"

python (Join-Path $repo "scripts\download_public_xau_m1.py") $from $to $csvPath 2>&1 |
  Tee-Object -FilePath (Join-Path $reportsRoot "download_public_history.log")
if ($LASTEXITCODE -ne 0) {
  throw "Public XAU history quality gate failed."
}

$filesDir = Join-Path $dataPath "MQL5\Files"
New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
Copy-Item $csvPath (Join-Path $filesDir "xau_public_m1.csv") -Force

Section "Compile importer and V27 EA"
$targetExperts = Join-Path $dataPath "MQL5\Experts"
New-Item -ItemType Directory -Force -Path $targetExperts | Out-Null

$eaDestination = Join-Path $targetExperts ([IO.Path]::GetFileName($eaSource))
$importerDestination = Join-Path $targetExperts ([IO.Path]::GetFileName($importerSource))
Copy-Item $eaSource $eaDestination -Force
Copy-Item $importerSource $importerDestination -Force

$compileImporterLog = Join-Path $reportsRoot "compile_importer_ea.log"
$compileMainLog = Join-Path $reportsRoot "compile_v27_ea.log"

Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$importerDestination`" /log:`"$compileImporterLog`"" -PassThru -Wait | Out-Null
Start-Sleep -Seconds 2
Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$eaDestination`" /log:`"$compileMainLog`"" -PassThru -Wait | Out-Null
Start-Sleep -Seconds 2

if (Test-Path $compileImporterLog) { Get-Content $compileImporterLog | ForEach-Object { Write-Host $_ } }
if (Test-Path $compileMainLog) { Get-Content $compileMainLog | ForEach-Object { Write-Host $_ } }

$importerEx5 = [IO.Path]::ChangeExtension($importerDestination, ".ex5")
$eaEx5 = [IO.Path]::ChangeExtension($eaDestination, ".ex5")
if (!(Test-Path $importerEx5)) { throw "Importer compilation failed." }
if (!(Test-Path $eaEx5)) { throw "V27 EA compilation failed." }

Section "Import CSV into XAU_PUBLIC"
$importerName = [IO.Path]::GetFileNameWithoutExtension($importerSource)
$importIni = Join-Path $repo "V27_MT5_ImportCustomSymbol.ini"
$importText = @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
[Charts]
MaxBars=2000000
[StartUp]
Symbol=EURUSD
Period=M1
Expert=$importerName
"@
Set-Content -Path $importIni -Value $importText -Encoding ASCII
Add-Account $importIni $reportsRoot

Kill-MT5
$importProcess = Start-Process -FilePath $terminal -ArgumentList "/config:`"$importIni`"" -PassThru
if (-not $importProcess.WaitForExit(10 * 60 * 1000)) {
  Kill-MT5
  throw "Custom symbol importer timed out."
}
Start-Sleep -Seconds 5

$importResult = Join-Path $filesDir "import_custom_rates_result.txt"
if (!(Test-Path $importResult)) {
  Copy-Logs $dataPath $reportsRoot $dataRoot
  throw "Custom symbol import result missing."
}
Copy-Item $importResult (Join-Path $reportsRoot "import_custom_rates_result.txt") -Force
if (!((Get-Content $importResult -Raw) -match "IMPORT_OK")) {
  Copy-Logs $dataPath $reportsRoot $dataRoot
  throw "Custom symbol import failed."
}

Section "Create canonical V27 tester profile"
$setDir = Join-Path $dataPath "MQL5\Profiles\Tester"
New-Item -ItemType Directory -Force -Path $setDir | Out-Null
$setPath = Join-Path $setDir "V27_CLEAN.set"

$setLines = @(
  "InpTradeSymbol=XAU_PUBLIC",
  "FixedLot=0.02",
  "MaxTradesPerDay=4",
  "CooldownMinutes=45",
  "MagicNumber=270100",
  "SlippagePoints=120",
  "BrokerStopBufferPoints=40",
  "UseSession=true",
  "SessionStartHour=7",
  "SessionEndHour=20",
  "BlockFridayLateEntries=true",
  "FridayLastEntryHour=17",
  "CloseBeforeWeekend=true",
  "FridayCloseHour=19",
  "EnableBuy=true",
  "EnableSell=true",
  "MinSignalScore=72.0",
  "MinDirectionScoreGap=6.0",
  "MinADX=16.0",
  "MaxSpreadATRFraction=0.10",
  "FastLen=9",
  "SlowLen=21",
  "TrendLen=200",
  "BiasFastLen=50",
  "BiasSlowLen=200",
  "RsiLen=14",
  "AtrLen=14",
  "AdxLen=14",
  "VolLen=20",
  "BreakoutLookback=5",
  "SweepLookback=5",
  "PullbackTouchATR=0.28",
  "MinBodyRatio=0.25",
  "MinVolumeRatio=0.80",
  "BreakoutTP_ATR=1.25",
  "BreakoutSL_ATR=1.35",
  "PullbackTP_ATR=1.10",
  "PullbackSL_ATR=1.25",
  "ContinuationTP_ATR=1.00",
  "ContinuationSL_ATR=1.30",
  "SweepTP_ATR=1.30",
  "SweepSL_ATR=1.20",
  "UseBreakEven=true",
  "BreakEvenTriggerATR=0.65",
  "BreakEvenOffsetATR=0.05",
  "UseTrailingStop=true",
  "TrailStartATR=1.00",
  "TrailDistanceATR=0.75",
  "MaxHoldBars=20",
  "TimeExitMinProgressATR=0.10",
  "UseCSVJournal=true",
  "CSVJournalName=V27_CLEAN_journal.csv"
)
$setLines | Set-Content -Path $setPath -Encoding ASCII
Copy-Item $setPath (Join-Path $reportsRoot "V27_CLEAN.set") -Force

Section "Run V27 Strategy Tester"
$eaName = [IO.Path]::GetFileNameWithoutExtension($eaSource)
$reportBaseName = "V27_${symbol}_${period}_${from}_${to}_model${model}" -replace "[:\\/ ]", "_"
$reportBasePath = Join-Path $reportsRoot $reportBaseName
$testIni = Join-Path $repo "V27_MT5_Backtest.ini"

$testerInputs = $setLines -join "`r`n"
$testText = @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0
[Charts]
MaxBars=2000000
[Tester]
Expert=$eaName
ExpertParameters=V27_CLEAN.set
Symbol=$symbol
Period=$period
Deposit=$deposit
Currency=USD
Leverage=$leverage
Model=$model
ExecutionMode=0
Optimization=0
FromDate=$from
ToDate=$to
ForwardMode=0
Report=$reportBasePath
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
[TesterInputs]
$testerInputs
"@

Set-Content -Path $testIni -Value $testText -Encoding ASCII
Add-Account $testIni $reportsRoot
Copy-Item $testIni (Join-Path $reportsRoot "V27_MT5_Backtest.ini") -Force

Kill-MT5
$testProcess = Start-Process -FilePath $terminal -ArgumentList "/config:`"$testIni`"" -PassThru
if (-not $testProcess.WaitForExit($timeout * 60 * 1000)) {
  Kill-MT5
  throw "V27 backtest timed out after $timeout minutes."
}
Start-Sleep -Seconds 10

Copy-Logs $dataPath $reportsRoot $dataRoot
$journalPath = Join-Path $filesDir "V27_CLEAN_journal.csv"
if (Test-Path $journalPath) {
  Copy-Item $journalPath (Join-Path $reportsRoot "V27_CLEAN_journal.csv") -Force
}

$foundReports = Copy-FoundReports @(
  $reportsRoot,
  $dataPath,
  (Join-Path $env:APPDATA "MetaQuotes\Tester"),
  (Join-Path $env:APPDATA "MetaQuotes\Terminal")
) $reportsRoot
$foundReports | Set-Content -Path (Join-Path $reportsRoot "found_reports.txt") -Encoding UTF8

$logBlob = Read-TesterLogBlob $reportsRoot
$hasTestPassed = $logBlob -match "Test passed"
$hasFinalBalance = $logBlob -match "final balance\s+[0-9.]+\s+USD"
$hasV27 = $logBlob -match "XAUUSD_V27_Clean_MultiSetup"

if (!$hasTestPassed -and !$hasFinalBalance) {
  Write-FallbackReport $reportsRoot $symbol $period $from $to | Out-Null
  throw "V27 MT5 tester did not produce a valid completion marker."
}

if (!$hasV27) {
  throw "Tester logs do not prove that the V27 EA executed."
}

Write-FallbackReport $reportsRoot $symbol $period $from $to | Out-Null
Set-Content -Path (Join-Path $reportsRoot "V27_RUN_OK.txt") -Value "V27_CLEAN_BACKTEST_OK" -Encoding UTF8
Write-Host "V27_CLEAN_BACKTEST_OK symbol=$symbol period=$period range=$from..$to"
exit 0
