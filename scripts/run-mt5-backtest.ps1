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
      if ((Test-Path $destination) -and ((Get-Item $destination).Length -gt 100000)) {
        return $true
      }
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

function Write-SafeText($text, $password) {
  $safe = $text
  if ($password) { $safe = $safe.Replace($password, "***") }
  Write-Host $safe
}

function Read-ReportText($reportPath) {
  try {
    return Get-Content -Path $reportPath -Raw -Encoding Unicode
  } catch {
    return Get-Content -Path $reportPath -Raw
  }
}

function Assert-UsableReport($reportPath) {
  if (!(Test-Path $reportPath)) { return }
  $txt = Read-ReportText $reportPath
  $isEmpty = $false

  if ($txt -match 'History Quality:</td>\s*<td nowrap><b>0%</b></td>' -and
      $txt -match 'Bars:</td>\s*<td nowrap><b>0</b></td>' -and
      $txt -match 'Ticks:</td>\s*<td nowrap><b>0</b></td>') {
    $isEmpty = $true
  }

  if ($txt -match 'Initial Deposit:</td>\s*<td nowrap colspan="10" align="left"><b>0\.00</b></td>') {
    $isEmpty = $true
  }

  if ($isEmpty) {
    throw "MT5 generated an EMPTY report: 0 bars / 0 ticks / 0 history. The broker history was not synchronized or the symbol name is wrong. Check reports/prefetch_history.log for XAU/GOLD symbol candidates."
  }
}

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$symbol  = if ($env:BT_SYMBOL) { $env:BT_SYMBOL } else { "XAUUSD" }
$period  = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M15" }
$from    = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2025.01.01" }
$to      = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { (Get-Date).ToString("yyyy.MM.dd") }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "10000" }
$leverage= if ($env:BT_LEVERAGE) { $env:BT_LEVERAGE } else { "1:100" }
$model   = if ($env:BT_MODEL) { $env:BT_MODEL } else { "0" }

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
if (!(Download-File $installerUrls $installer)) {
  throw "Could not download MT5 installer. MetaQuotes CDN may be temporarily unavailable."
}

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
if ($robocopyExit -le 7) {
  $global:LASTEXITCODE = 0
} else {
  throw "Robocopy failed with exit code $robocopyExit"
}

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
if (Test-Path $compileLog) {
  Get-Content $compileLog | ForEach-Object { Write-Host $_ }
}
$ex5 = [IO.Path]::ChangeExtension($eaDest, ".ex5")
if (!(Test-Path $ex5)) {
  throw "Compilation failed: EX5 not created. Check compile.log artifact."
}
Write-Host "Compiled: $ex5"

Section "Prefetch broker history with MetaTrader5 Python API"
if (!($env:MT5_LOGIN -and $env:MT5_PASSWORD -and $env:MT5_SERVER)) {
  throw "MT5_LOGIN / MT5_PASSWORD / MT5_SERVER secrets are missing. They are required to download broker history in GitHub Actions."
}

$pyScript = Join-Path $reportsRoot "prefetch_mt5_history.py"
$prefetchLog = Join-Path $reportsRoot "prefetch_history.log"

$pyCode = @'
import os
import sys
import time
import datetime as dt

try:
    import MetaTrader5 as mt5
except Exception as exc:
    print("IMPORT_ERROR", repr(exc))
    sys.exit(10)

def env(name, default=""):
    return os.environ.get(name, default).strip()

def parse_date(s, add_day=False):
    d = dt.datetime.strptime(s, "%Y.%m.%d")
    if add_day:
        d += dt.timedelta(days=1)
    return d.replace(tzinfo=dt.timezone.utc)

TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1,
    "M2": mt5.TIMEFRAME_M2,
    "M3": mt5.TIMEFRAME_M3,
    "M4": mt5.TIMEFRAME_M4,
    "M5": mt5.TIMEFRAME_M5,
    "M6": mt5.TIMEFRAME_M6,
    "M10": mt5.TIMEFRAME_M10,
    "M12": mt5.TIMEFRAME_M12,
    "M15": mt5.TIMEFRAME_M15,
    "M20": mt5.TIMEFRAME_M20,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H2": mt5.TIMEFRAME_H2,
    "H3": mt5.TIMEFRAME_H3,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}

terminal_path = env("MT5_TERMINAL_PATH")
login_s = env("MT5_LOGIN")
password = env("MT5_PASSWORD")
server = env("MT5_SERVER")
symbol = env("BT_SYMBOL", "XAUUSD")
period = env("BT_PERIOD", "M15").upper()
from_s = env("BT_FROM_DATE", "2025.01.01")
to_s = env("BT_TO_DATE", "2025.01.15")
sync_minutes = int(env("BT_SYNC_MINUTES", "15"))

print("terminal_path=", terminal_path)
print("server=", server)
print("login=", login_s)
print("symbol=", symbol)
print("period=", period)
print("from=", from_s, "to=", to_s, "sync_minutes=", sync_minutes)

login = int(login_s)
ok = mt5.initialize(path=terminal_path, login=login, password=password, server=server, timeout=90000, portable=True)
if not ok:
    print("initialize with login failed:", mt5.last_error())
    ok = mt5.initialize(path=terminal_path, timeout=90000, portable=True)
    if not ok:
        print("initialize terminal failed:", mt5.last_error())
        sys.exit(11)
    if not mt5.login(login, password=password, server=server, timeout=90000):
        print("login failed:", mt5.last_error())
        mt5.shutdown()
        sys.exit(12)

account = mt5.account_info()
print("account_info=", account)
if account is None:
    print("no account_info:", mt5.last_error())
    mt5.shutdown()
    sys.exit(13)

all_symbols = mt5.symbols_get()
if all_symbols is None:
    print("symbols_get failed:", mt5.last_error())
    all_symbols = []

names = [s.name for s in all_symbols]
gold_candidates = sorted([n for n in names if ("XAU" in n.upper() or "GOLD" in n.upper())])
print("XAU/GOLD candidates count=", len(gold_candidates))
print("XAU/GOLD candidates=", gold_candidates[:100])

if symbol not in names:
    print(f"REQUESTED_SYMBOL_NOT_FOUND: {symbol}")
    if gold_candidates:
        print("Use one exact candidate above as the workflow symbol.")
    mt5.shutdown()
    sys.exit(14)

info = mt5.symbol_info(symbol)
print("symbol_info_before_select=", info)
if not mt5.symbol_select(symbol, True):
    print("symbol_select failed:", mt5.last_error())
    mt5.shutdown()
    sys.exit(15)

start = parse_date(from_s)
end = parse_date(to_s, add_day=True)
tf_requested = TIMEFRAMES.get(period, mt5.TIMEFRAME_M15)

def fetch_rates(tf_name, tf):
    last_count = 0
    for attempt in range(max(1, sync_minutes)):
        rates = mt5.copy_rates_range(symbol, tf, start, end)
        count = 0 if rates is None else len(rates)
        print(f"fetch_rates attempt={attempt+1}/{sync_minutes} tf={tf_name} count={count} last_error={mt5.last_error()}")
        if count > 0:
            print("first_bar=", rates[0])
            print("last_bar=", rates[-1])
            return count
        last_count = count
        time.sleep(60)
    return last_count

# MT5 Strategy Tester often needs M1 base data even when testing M15.
m1_count = fetch_rates("M1", mt5.TIMEFRAME_M1)
tf_count = fetch_rates(period, tf_requested) if period != "M1" else m1_count

tick_end = min(end, start + dt.timedelta(days=2))
ticks = mt5.copy_ticks_range(symbol, start, tick_end, mt5.COPY_TICKS_ALL)
tick_count = 0 if ticks is None else len(ticks)
print("tick_probe_count_first_2_days=", tick_count, "last_error=", mt5.last_error())

mt5.shutdown()

if m1_count <= 0 and tf_count <= 0:
    print("NO_HISTORY_DOWNLOADED_FOR_SYMBOL")
    print("Most likely causes:")
    print("1) wrong symbol name for this broker")
    print("2) MT5_SERVER secret is not the exact broker server name")
    print("3) broker blocks history download on GitHub runner")
    print("4) demo account has no XAU/GOLD market data")
    sys.exit(20)

print("PREFETCH_OK m1_count=", m1_count, "tf_count=", tf_count, "tick_probe_count=", tick_count)
sys.exit(0)
'@

Set-Content -Path $pyScript -Value $pyCode -Encoding UTF8
$env:MT5_TERMINAL_PATH = $terminalPortable

Write-Host "Installing MetaTrader5 Python package..."
python -m pip install --upgrade pip
python -m pip install MetaTrader5

Write-Host "Running history prefetch..."
& python $pyScript 2>&1 | Tee-Object -FilePath $prefetchLog
$prefetchExit = $LASTEXITCODE
if ($prefetchExit -ne 0) {
  throw "MetaTrader5 Python history prefetch failed with exit code $prefetchExit. Open reports/prefetch_history.log in the artifact. It will show exact XAU/GOLD symbol candidates or login/history errors."
}

Section "Generate tester configuration"
$reportName = "QQ_V17_${symbol}_${period}_${from}_${to}_model${model}.htm" -replace "[:\\/ ]", "_"
$reportRelative = "reports\$reportName"
$ini = Join-Path $repo "QQ_MT5_Backtest_GHA.ini"

$commonLines = New-Object System.Collections.Generic.List[string]
$commonLines.Add("[Common]")
$commonLines.Add("ProxyEnable=0")
$commonLines.Add("NewsEnable=0")
$commonLines.Add("CertInstall=1")
$commonLines.Add("KeepPrivate=0")
$commonLines.Add("Login=$($env:MT5_LOGIN)")
$commonLines.Add("Server=$($env:MT5_SERVER)")
$commonLines.Add("Password=$($env:MT5_PASSWORD)")
Write-Host "Broker login: configured from GitHub Secrets. Server=$($env:MT5_SERVER), Login=$($env:MT5_LOGIN)"

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
Write-SafeText $iniText $env:MT5_PASSWORD

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
  Write-Host "Searching for HTML/XML reports..."
  Get-ChildItem -Path $portable -Recurse -Include *.htm,*.html,*.xml -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Found report-like file: $($_.FullName)"
    Copy-Item $_.FullName $reportsRoot -Force -ErrorAction SilentlyContinue
  }
}

$logDirs = @(
  (Join-Path $portable "Logs"),
  (Join-Path $portable "MQL5\Logs"),
  (Join-Path $portable "Tester\logs")
)
foreach ($d in $logDirs) {
  if (Test-Path $d) {
    $target = Join-Path $reportsRoot ((Split-Path $d -Leaf) + "_copy")
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item (Join-Path $d "*") $target -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$reportFiles = Get-ChildItem -Path $reportsRoot -File -Include *.htm,*.html,*.xml -Recurse -ErrorAction SilentlyContinue
if (($reportFiles | Measure-Object).Count -eq 0) {
  Write-Host "No report generated. This usually means: bad symbol name, missing broker data, login/server problem, or MT5 install/start failure. Logs are uploaded as artifact."
  throw "No MT5 report generated. Check uploaded logs."
}

Write-Host "Done. Reports:"
$reportFiles | ForEach-Object { Write-Host $_.FullName }

$global:LASTEXITCODE = 0
exit 0
