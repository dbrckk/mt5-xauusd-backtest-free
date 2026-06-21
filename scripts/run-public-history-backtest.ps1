$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Section($t) { Write-Host ""; Write-Host "==================== $t ====================" }
function Kill-MT5() { Get-Process -Name "terminal64","terminal","metaeditor64","metaeditor","metatester64","metatester" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
function Find-File($roots, $name) { foreach ($r in $roots) { if (Test-Path $r) { $f = Get-ChildItem -Path $r -Filter $name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if ($null -ne $f) { return $f.FullName } } }; return $null }
function Download-File($urls, $dest) { foreach ($u in $urls) { try { Write-Host "Downloading: $u"; Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing -TimeoutSec 180; if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 100000)) { return $true } } catch { Write-Host "Download failed: $($_.Exception.Message)" } }; return $false }
function Copy-Logs($dataPath, $reportsRoot) { foreach ($d in @((Join-Path $dataPath "Logs"),(Join-Path $dataPath "MQL5\Logs"),(Join-Path $dataPath "Tester\logs"),(Join-Path $dataPath "Tester\cache"))) { if (Test-Path $d) { $target = Join-Path $reportsRoot ((Split-Path $d -Leaf) + "_copy"); New-Item -ItemType Directory -Force -Path $target | Out-Null; Copy-Item (Join-Path $d "*") $target -Recurse -Force -ErrorAction SilentlyContinue } } }
function Report-Usable($path) { if (!(Test-Path $path)) { return $false }; try { $txt = Get-Content -Path $path -Raw -Encoding Unicode } catch { $txt = Get-Content -Path $path -Raw }; if ([string]::IsNullOrWhiteSpace($txt)) { return $false }; if ($txt -match 'History Quality:</td>\s*<td nowrap><b>0%</b></td>' -and $txt -match 'Bars:</td>\s*<td nowrap><b>0</b></td>') { return $false }; if ($txt -match 'Total Net Profit:' -or $txt -match 'Total Trades:' -or $txt -match 'Bars:') { return $true }; return $false }

$repo = (Resolve-Path ".").Path
$reportsRoot = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$customSymbol = "XAU_PUBLIC"
$period = if ($env:BT_PERIOD) { $env:BT_PERIOD } else { "M15" }
$from = if ($env:BT_FROM_DATE) { $env:BT_FROM_DATE } else { "2026.06.01" }
$to = if ($env:BT_TO_DATE) { $env:BT_TO_DATE } else { "2026.06.20" }
$deposit = if ($env:BT_DEPOSIT) { $env:BT_DEPOSIT } else { "10000" }
$leverage = if ($env:BT_LEVERAGE) { $env:BT_LEVERAGE } else { "1:100" }
$model = if ($env:BT_MODEL) { $env:BT_MODEL } else { "0" }
$timeout = 180
if ($env:BT_TIMEOUT_MINUTES) { [int]::TryParse($env:BT_TIMEOUT_MINUTES, [ref]$timeout) | Out-Null }
if ($timeout -lt 30) { $timeout = 30 }
if ($timeout -gt 350) { $timeout = 350 }

$eaSource = Join-Path $repo "MQL5\Experts\QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
$importerSource = Join-Path $repo "MQL5\Experts\ImportCustomRatesEA.mq5"
if (!(Test-Path $eaSource)) { throw "EA source not found: $eaSource" }
if (!(Test-Path $importerSource)) { throw "Importer EA source not found: $importerSource" }
$eaName = [IO.Path]::GetFileNameWithoutExtension($eaSource)
$importerName = [IO.Path]::GetFileNameWithoutExtension($importerSource)

Section "Install MetaTrader 5"
$installer = Join-Path $env:RUNNER_TEMP "mt5setup.exe"
$urls = @("https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe", "https://download.mql5.com/cdn/web/metaquotes.ltd/mt5/mt5setup.exe")
if (!(Download-File $urls $installer)) { throw "Could not download MT5 installer." }
$terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $terminal) { $p = Start-Process -FilePath $installer -ArgumentList "/auto" -PassThru; $p.WaitForExit(180000) | Out-Null; Start-Sleep -Seconds 25; Kill-MT5 }
$terminal = Find-File @("C:\Program Files", "C:\Program Files (x86)") "terminal64.exe"
if ($null -eq $terminal) { throw "terminal64.exe not found." }
$metaeditor = Join-Path (Split-Path $terminal -Parent) "metaeditor64.exe"
if (!(Test-Path $metaeditor)) { throw "metaeditor64.exe not found." }
Write-Host "Terminal: $terminal"
Write-Host "MetaEditor: $metaeditor"

Section "Create MT5 data folder"
Kill-MT5
$p = Start-Process -FilePath $terminal -PassThru
Start-Sleep -Seconds 60
Kill-MT5
$dataRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (!(Test-Path $dataRoot)) { throw "MT5 data root not found: $dataRoot" }
Get-ChildItem -Path $dataRoot -Directory -ErrorAction SilentlyContinue | Select-Object Name,FullName,LastWriteTime | Format-Table -AutoSize | Out-String | Set-Content -Path (Join-Path $reportsRoot "terminal_data_folders.txt") -Encoding UTF8
$dataPathObj = Get-ChildItem -Path $dataRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("Common","Community") -and (Test-Path (Join-Path $_.FullName "MQL5")) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $dataPathObj) { throw "No usable MT5 terminal data folder found." }
$dataPath = $dataPathObj.FullName
Set-Content -Path (Join-Path $reportsRoot "mt5_data_path.txt") -Value $dataPath -Encoding UTF8
Write-Host "MT5 data path: $dataPath"

Section "Download public XAUUSD history"
$publicDir = Join-Path $reportsRoot "public_history"
New-Item -ItemType Directory -Force -Path $publicDir | Out-Null
$csvPath = Join-Path $publicDir "xau_public_m1.csv"
python (Join-Path $repo "scripts\download_public_xau_m1.py") $from $to $csvPath 2>&1 | Tee-Object -FilePath (Join-Path $reportsRoot "download_public_history.log")
if ($LASTEXITCODE -ne 0) { throw "Public XAU history download failed." }
$filesDir = Join-Path $dataPath "MQL5\Files"
New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
Copy-Item $csvPath (Join-Path $filesDir "xau_public_m1.csv") -Force

Section "Copy and compile EAs"
$targetExperts = Join-Path $dataPath "MQL5\Experts"
New-Item -ItemType Directory -Force -Path $targetExperts | Out-Null
$eaDest = Join-Path $targetExperts ([IO.Path]::GetFileName($eaSource))
$importerDest = Join-Path $targetExperts ([IO.Path]::GetFileName($importerSource))
Copy-Item $eaSource $eaDest -Force
Copy-Item $importerSource $importerDest -Force
$compileMainLog = Join-Path $reportsRoot "compile_main_ea.log"
$compileImporterLog = Join-Path $reportsRoot "compile_importer_ea.log"
Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$importerDest`" /log:`"$compileImporterLog`"" -PassThru -Wait | Out-Null
Start-Sleep -Seconds 2
Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$eaDest`" /log:`"$compileMainLog`"" -PassThru -Wait | Out-Null
Start-Sleep -Seconds 2
if (Test-Path $compileImporterLog) { Get-Content $compileImporterLog | ForEach-Object { Write-Host $_ } }
if (Test-Path $compileMainLog) { Get-Content $compileMainLog | ForEach-Object { Write-Host $_ } }
if (!(Test-Path ([IO.Path]::ChangeExtension($importerDest, ".ex5")))) { throw "Importer compilation failed." }
if (!(Test-Path ([IO.Path]::ChangeExtension($eaDest, ".ex5")))) { throw "Main EA compilation failed." }

Section "Import CSV into custom MT5 symbol"
$importIni = Join-Path $repo "QQ_MT5_ImportCustomSymbol.ini"
$importText = @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1

[Charts]
MaxBars=1000000

[StartUp]
Symbol=EURUSD
Period=M1
Expert=$importerName
"@
Set-Content -Path $importIni -Value $importText -Encoding ASCII
Set-Content -Path (Join-Path $reportsRoot "QQ_MT5_ImportCustomSymbol.ini") -Value $importText -Encoding UTF8
Kill-MT5
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$importIni`"" -PassThru
if (-not $proc.WaitForExit(8 * 60 * 1000)) { Kill-MT5; throw "Custom symbol importer timed out." }
Start-Sleep -Seconds 5
$importResult = Join-Path $filesDir "import_custom_rates_result.txt"
if (Test-Path $importResult) { Copy-Item $importResult (Join-Path $reportsRoot "import_custom_rates_result.txt") -Force; Get-Content $importResult | ForEach-Object { Write-Host $_ } } else { Copy-Logs $dataPath $reportsRoot; throw "Custom symbol import result missing." }
if (!((Get-Content $importResult -Raw) -match "IMPORT_OK")) { Copy-Logs $dataPath $reportsRoot; throw "Custom symbol import failed." }

Section "Run Strategy Tester on custom public symbol"
$reportName = "QQ_V17_${customSymbol}_${period}_${from}_${to}_model${model}.htm" -replace "[:\\/ ]", "_"
$reportPath = Join-Path $reportsRoot $reportName
$testIni = Join-Path $repo "QQ_MT5_PublicHistory_Backtest.ini"
$testText = @"
[Experts]
AllowLiveTrading=0
AllowDllImport=0
Enabled=1
Account=0
Profile=0

[Charts]
MaxBars=1000000

[Tester]
Expert=$eaName
Symbol=$customSymbol
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
Report=$reportPath
ReplaceReport=1
ShutdownTerminal=1
UseLocal=1
UseRemote=0
UseCloud=0
Visual=0
"@
Set-Content -Path $testIni -Value $testText -Encoding ASCII
Set-Content -Path (Join-Path $reportsRoot "QQ_MT5_PublicHistory_Backtest.ini") -Value $testText -Encoding UTF8
Kill-MT5
$testProc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$testIni`"" -PassThru
if (-not $testProc.WaitForExit($timeout * 60 * 1000)) { Kill-MT5; throw "Backtest timed out after $timeout minutes." }
Start-Sleep -Seconds 10
Copy-Logs $dataPath $reportsRoot
if (!(Test-Path $reportPath)) { throw "No MT5 report generated for public custom symbol." }
if (!(Report-Usable $reportPath)) { throw "MT5 report exists but looks empty. Check logs." }
Set-Content -Path (Join-Path $reportsRoot "selected_symbol.txt") -Value $customSymbol -Encoding UTF8
Write-Host "PUBLIC_HISTORY_BACKTEST_OK symbol=$customSymbol report=$reportPath"
exit 0
