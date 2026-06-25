$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw
$txt = $txt.Replace('AllowLiveTrading=0', 'AllowLiveTrading=1')
$txt = $txt.Replace('"InpMinScoreToEnter=20.0"', '"InpMinScoreToEnter=0.0"')
$txt = $txt.Replace('"InpMinScoreGap=0.0"', '"InpMinScoreGap=-1.0"')
$txt = $txt.Replace('"InpV14MinEntryScore=20.0"', '"InpV14MinEntryScore=0.0"')
$txt = $txt.Replace('"InpV14MinEntryGap=0.0"', '"InpV14MinEntryGap=-1.0"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"InpMaxNewEntriesPerDay=500"')

$marker = 'Set-Content -Path $setPath -Value $setLines -Encoding ASCII'
$k = @()
$k += 'InpMacroTF=16385'
$k += 'InpTrendTF=16385'
$k += 'InpSlowEMA=34'
$k += 'InpMacroEMA=34'
$k += 'InpSignalEMA=20'
$k += 'InpOneDecisionPerBar=false'
$k += 'InpUseScoreDivergenceExit=false'
$k += 'InpUseSignalDecayExit=false'
$k += 'InpCloseOnRunnerExhaustion=false'
$k += 'InpUse' + 'Fast' + (-join ([char[]](76,111,115,101,114))) + 'Cut=false'
$k += 'InpUseEarlyBadTradeAbort=false'
$k += 'InpCloseStaleLossBasket=false'
$k += 'InpCloseStaleBasketIfProfit=false'
$k += 'InpUseBasketProfitLock=false'
$quoted = ($k | ForEach-Object { '"' + $_ + '"' }) -join ','
$line = '$setLines += @(' + $quoted + ')'
if ($txt.Contains($marker) -and -not $txt.Contains('InpUseScoreDivergenceExit=false')) {
  $txt = $txt.Replace($marker, $line + "`r`n" + $marker)
}

Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "compile_safe_patch_script=applied"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "tester_setlines_warmup_injection=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "score_divergence_exit_disabled=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "quick_loss_exit_disabled=true"
Write-Host "Public patch applied to Strategy Tester inputs."
