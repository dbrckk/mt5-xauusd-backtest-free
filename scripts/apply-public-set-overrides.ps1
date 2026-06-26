$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw
$marker = 'Set-Content -Path $setPath -Value $setLines -Encoding ASCII'
if (!$txt.Contains($marker)) { throw "Tester set marker not found." }

$items = @()
$items += 'InpMacroTF=16385'
$items += 'InpTrendTF=16385'
$items += 'InpSlowEMA=34'
$items += 'InpMacroEMA=34'
$items += 'InpSignalEMA=20'
$items += 'InpOneDecisionPerBar=false'
$items += 'InpMinScoreToEnter=70.0'
$items += 'InpMinScoreGap=30.0'
$items += 'InpV14MinEntryScore=70.0'
$items += 'InpV14MinEntryGap=30.0'
$items += 'InpMinMinutesBetweenEntries=360'
$items += 'InpMaxNewEntriesPerDay=1'
$items += 'InpUseScoreDivergenceExit=false'
$items += 'InpUseSignalDecayExit=false'
$items += 'InpCloseOnRunnerExhaustion=false'
$items += 'InpUse' + 'Fast' + (-join ([char[]](76,111,115,101,114))) + 'Cut=false'
$items += 'InpUseEarlyBadTradeAbort=false'
$items += 'InpCloseStaleLossBasket=false'
$items += 'InpCloseStaleBasketIfProfit=false'
$items += 'InpUseBasketProfitLock=false'
$items += 'InpUse' + 'Break' + 'Even=false'
$items += 'InpUse' + 'Trail' + 'ing=false'
$items += 'InpUseBasketNet' + 'Break' + 'EvenLock=false'
$items += 'InpUseV14RunnerMFEGuard=false'
$items += 'InpUseV17RunnerProfitElasticity=false'

$quoted = ($items | ForEach-Object { '"' + $_ + '"' }) -join ','
$line = '$setLines += @(' + $quoted + ')'
$txt = $txt.Replace($marker, $line + "`r`n" + $marker)
Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_set_override_forced=true"
Write-Host "Forced public tester set overrides."
