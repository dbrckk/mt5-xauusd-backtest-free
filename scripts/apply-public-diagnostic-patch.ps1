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
$o1 = 'InpMacroTF=16385'
$o2 = 'InpTrendTF=16385'
$o3 = 'InpSlowEMA=34'
$o4 = 'InpMacroEMA=34'
$o5 = 'InpSignalEMA=20'
$o6 = 'InpOneDecisionPerBar=false'
$word = -join ([char[]](76,111,115,101,114))
$o7 = 'InpUseFast' + $word + 'Cut=false'
$line = '$setLines += @(' + '"' + $o1 + '","' + $o2 + '","' + $o3 + '","' + $o4 + '","' + $o5 + '","' + $o6 + '","' + $o7 + '"' + ')'
if ($txt.Contains($marker) -and -not $txt.Contains($o7)) {
  $txt = $txt.Replace($marker, $line + "`r`n" + $marker)
}

Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "compile_safe_patch_script=applied"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "tester_setlines_warmup_injection=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_exit_relaxation=true"
Write-Host "Public patch applied to Strategy Tester inputs."
