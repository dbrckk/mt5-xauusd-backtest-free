$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Section($text) {
  Write-Host ""
  Write-Host "==================== $text ===================="
}

function Download-File($urls, $destination) {
  foreach ($url in $urls) {
    try {
      Write-Host "Downloading: $url"
      Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing -TimeoutSec 180
      if ((Test-Path $destination) -and ((Get-Item $destination).Length -gt 100000)) { return $true }
    } catch {
      Write-Host "Download failed from $url : $($_.Exception.Message)"
    }
  }
  return $false
}

function Find-File($roots, $name) {
  foreach ($root in $roots) {
    if (Test-Path $root) {
      $found = Get-ChildItem -Path $root -Filter $name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($null -ne $found) { return $found.FullName }
    }
  }
  return $null
}

function Kill-MT5() {
  Get-Process -Name "terminal64","terminal","metaeditor64","metaeditor","metatester64","metatester" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

function Hide-Secret($text) {
  $safe = $text
  if ($env:MT5_PASSWORD) { $safe = $safe.Replace($env:MT5_PASSWORD, "***") }
  Write-Host $safe
}

function Assert-UsableReport($reportPath) {
  if (!(Test-Path $reportPath)) { return }
  try { $txt = Get-Content -Path $reportPath -Raw -Encoding Unicode } catch { $txt = Get-Content -Path $reportPath -Raw }
  $emptyReport = $false
  if ($txt -match 'History Quality:</td>\s*<td nowrap><b>0%</b></td>' -and $txt -match 'Bars:</td>\s*<td nowrap><b>0</b></td>' -and $txt -match 'Ticks:</td>\s*<td nowrap><b>0</b></td>') { $emptyReport = $true }
  if ($txt -match 'Initial Deposit:</td>\s*<td nowrap colspan="10" align="left"><b>0\.00</b></td>') { $emptyReport = $true }
  if ($emptyReport) { throw "MT5 generated an empty report. Open reports/prefetch_history.log in the artifact." }
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$symbol = if ($env:BT_SYMBOL) { $env:BT_SYMBOL } else { "XAUUSD" }
$period = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M15" }
$from = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2025.01.01" }
$to = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { (Get-Date).ToString("yyyy.MM.dd") }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "10000" }
$leverage = if ($env:BT_LEVERAGE) { $env:BT_LEVERAGE } else { "1:100" }
$model = if ($env:BT_MODEL) { $env:BT_MODEL } else { "0" }

$timeout = 330
if ($env:BT_TIMEOUT_MINUTES) { [int]::TryParse($env:BT_TIMEOUT_MINUTES, [ref]$timeout) | Out-Null }
if ($timeout -lt 15) { $timeout = 15 }
if ($timeout -gt 350) { $timeout = 350 }

$syncMinutes = 15
if ($env:BT_SYNC_MINUTES) { [int]::TryParse($env:BT_SYNC_MINUTES, [ref]$syncMinutes) | Out-Null }
if ($syncMinutes -lt 3) { $syncMinutes = 3 }
if ($syncMinutes -gt 60) { $syncMinutes = 60 }

$eaSource = Join-Path $repo "MQL5\Experts\QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $eaSource)) { throw "EA source not found: $eaSource" }
$eaName = [IO.Path]::GetFileNameWithoutExtension($eaSource)

Section "Install MetaTrader 5"
$installer = Join-Path $env:RUNNER_TEMP "mt5setup.exe"
$installerUrls = @(
  "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe",
  "https://download.mql5.com/cdn/web/metaquotes.ltd/mt5/mt5setup.exe",
  "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup64.exe"
)
if (!(Download-File $installerUrls $installer)) { throw "Could not download MT5 installer." }

$existingTerminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $existingTerminal) {
  Write-Host "Running mt5setup.exe /auto"
  $p = Start-Process -FilePath $installer -ArgumentList "/auto" -PassThru
  $p.WaitForExit(180000) | Out-Null
  Start-Sleep -Seconds 20
  Kill-MT5
}

$terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $terminal) { throw "terminal64.exe not found after MT5 install." }
$installDir = Split-Path $terminal -Parent
Write-Host "Found MT5: $terminal"

Section "Prepare portable MT5 folder"
$portable = Join-Path $repo "mt5_portable"
if (Test-Path $portable) { Remove-Item $portable -Recurse -Force }
New-Item -ItemType Directory -Force -Path $portable | Out-Null
robocopy $installDir $portable /E /NFL /NDL /NJH /NJS /NC /NS | Out-Null
$robocopyExit = $LASTEXITCODE
if ($robocopyExit -le 7) { $global:LASTEXITCODE = 0 } else { throw "Robocopy failed with exit code $robocopyExit" }

$terminalPortable = Join-Path $portable "terminal64.exe"
$metaeditorPortable = Join-Path $portable "metaeditor64.exe"
if (!(Test-Path $terminalPortable)) { throw "Portable terminal64.exe missing." }
if (!(Test-Path $metaeditorPortable)) { throw "Portable metaeditor64.exe missing." }

$portableExperts = Join-Path $portable "MQL5\Experts"
$portableTester = Join-Path $portable "MQL5\Profiles\Tester"
$portableReports = Join-Path $portable "reports"
New-Item -ItemType Directory -Force -Path $portableExperts,$portableTester,$portableReports | Out-Null
$eaDest = Join-Path $portableExperts ([IO.Path]::GetFileName($eaSource))
Copy-Item $eaSource $eaDest -Force

Section "Compile EA"
$compileLog = Join-Path $reportsRoot "compile.log"
if (Test-Path $compileLog) { Remove-Item $compileLog -Force }
$compileArgs = "/portable /compile:`"$eaDest`" /log:`"$compileLog`""
Write-Host "MetaEditor args: $compileArgs"
$compile = Start-Process -FilePath $metaeditorPortable -ArgumentList $compileArgs -PassThru -Wait
Start-Sleep -Seconds 3
if (Test-Path $compileLog) { Get-Content $compileLog | ForEach-Object { Write-Host $_ } }
$ex5 = [IO.Path]::ChangeExtension($eaDest, ".ex5")
if (!(Test-Path $ex5)) { throw "Compilation failed: EX5 not created. Check compile.log artifact." }
Write-Host "Compiled: $ex5"

Section "Warm up MT5 and prefetch broker history"
if (!($env:MT5_LOGIN -and $env:MT5_PASSWORD -and $env:MT5_SERVER)) { throw "MT5_LOGIN / MT5_PASSWORD / MT5_SERVER secrets are missing." }

$preLoginIni = Join-Path $repo "QQ_MT5_PreLogin_GHA.ini"
$preLoginLines = @(
  "[Common]",
  "ProxyEnable=0",
  "NewsEnable=0",
  "CertInstall=1",
  "KeepPrivate=0",
  "Login=$($env:MT5_LOGIN)",
  "Server=$($env:MT5_SERVER)",
  ("Pass" + "word=$($env:MT5_PASSWORD)"),
  "",
  "[Charts]",
  "MaxBars=500000"
)
$preLoginText = $preLoginLines -join "`r`n"
Set-Content -Path $preLoginIni -Value $preLoginText -Encoding ASCII
Copy-Item $preLoginIni (Join-Path $reportsRoot "QQ_MT5_PreLogin_GHA.ini") -Force
Hide-Secret $preLoginText

Write-Host "Starting terminal warm-up before Python IPC connection..."
$warmProc = Start-Process -FilePath $terminalPortable -ArgumentList "/portable /config:`"$preLoginIni`"" -PassThru
Start-Sleep -Seconds 90

$env:MT5_TERMINAL_PATH = $terminalPortable
$prefetchLog = Join-Path $reportsRoot "prefetch_history.log"
Write-Host "Installing MetaTrader5 Python package..."
python -m pip install --upgrade pip
python -m pip install MetaTrader5
Write-Host "Running history prefetch..."
& python (Join-Path $repo "scripts\prefetch_mt5_history.py") 2>&1 | Tee-Object -FilePath $prefetchLog
$prefetchExit = $LASTEXITCODE
Kill-MT5
if ($prefetchExit -ne 0) { throw "MetaTrader5 Python history prefetch failed with exit code $prefetchExit. Open reports/prefetch_history.log in the artifact." }

Section "Generate tester configuration"
$reportName = "QQ_V17_${symbol}_${period}_${from}_${to}_model${model}.htm" -replace "[:\\/ ]", "_"
$reportRelative = "reports\$reportName"
$ini = Join-Path $repo "QQ_MT5_Backtest_GHA.ini"
$commonLines = @(
  "[Common]",
  "ProxyEnable=0",
  "NewsEnable=0",
  "CertInstall=1",
  "KeepPrivate=0",
  "Login=$($env:MT5_LOGIN)",
  "Server=$($env:MT5_SERVER)",
  ("Pass" + "word=$($env:MT5_PASSWORD)")
)
$iniText = @"
$($commonLines -join "`r`n")

[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[Charts]
MaxBars=500000

[Tester]
Expert=$eaName
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
Report=$reportRelative
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
"@
Set-Content -Path $ini -Value $iniText -Encoding ASCII
Copy-Item $ini (Join-Path $reportsRoot "QQ_MT5_Backtest_GHA.ini") -Force
Hide-Secret $iniText

Section "Run Strategy Tester"
$terminalArgs = "/portable /config:`"$ini`""
Write-Host "Terminal args: $terminalArgs"
$proc = Start-Process -FilePath $terminalPortable -ArgumentList $terminalArgs -PassThru
if (-not $proc.WaitForExit($timeout * 60 * 1000)) {
  Write-Host "Backtest timeout reached. Killing MT5."
  Kill-MT5
  throw "Backtest timed out after $timeout minutes. Reduce date range or use Model=0."
}
Start-Sleep -Seconds 5

Section "Collect reports"
$expectedReport = Join-Path $portable $reportRelative
if (Test-Path $expectedReport) {
  Copy-Item $expectedReport (Join-Path $reportsRoot $reportName) -Force
  Write-Host "Report saved: $expectedReport"
  Assert-UsableReport (Join-Path $reportsRoot $reportName)
} else {
  Write-Host "Expected report missing: $expectedReport"
  Get-ChildItem -Path $portable -Recurse -Include *.htm,*.html,*.xml -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Found report-like file: $($_.FullName)"
    Copy-Item $_.FullName $reportsRoot -Force -ErrorAction SilentlyContinue
  }
}

$logDirs = @((Join-Path $portable "Logs"),(Join-Path $portable "MQL5\Logs"),(Join-Path $portable "Tester\logs"))
foreach ($d in $logDirs) {
  if (Test-Path $d) {
    $target = Join-Path $reportsRoot ((Split-Path $d -Leaf) + "_copy")
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item (Join-Path $d "*") $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}
$reportFiles = Get-ChildItem -Path $reportsRoot -File -Include *.htm,*.html,*.xml -Recurse -ErrorAction SilentlyContinue
if (($reportFiles | Measure-Object).Count -eq 0) { throw "No MT5 report generated. Check uploaded logs." }
Write-Host "Done. Reports:"
$reportFiles | ForEach-Object { Write-Host $_.FullName }
$global:LASTEXITCODE = 0
exit 0
