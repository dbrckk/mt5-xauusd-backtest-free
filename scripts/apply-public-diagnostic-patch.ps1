$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw
$txt = $txt.Replace('AllowLiveTrading=0', 'AllowLiveTrading=1')
$txt = $txt.Replace('input double InpMinScoreToEnter = 20.0;', 'input double InpMinScoreToEnter = 0.0;')
$txt = $txt.Replace('input double InpMinScoreGap = 0.0;', 'input double InpMinScoreGap = -1.0;')
$txt = $txt.Replace('input double InpV14MinEntryScore = 20.0;', 'input double InpV14MinEntryScore = 0.0;')
$txt = $txt.Replace('input double InpV14MinEntryGap = 0.0;', 'input double InpV14MinEntryGap = -1.0;')
$txt = $txt.Replace('"InpMinScoreToEnter=20.0"', '"InpMinScoreToEnter=0.0"')
$txt = $txt.Replace('"InpMinScoreGap=0.0"', '"InpMinScoreGap=-1.0"')
$txt = $txt.Replace('"InpV14MinEntryScore=20.0"', '"InpV14MinEntryScore=0.0"')
$txt = $txt.Replace('"InpV14MinEntryGap=0.0"', '"InpV14MinEntryGap=-1.0"')
$txt = $txt.Replace('"InpMaxNewEntriesPerDay=80"', '"InpMaxNewEntriesPerDay=500"')
Set-Content -Path $runner -Value $txt -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "compile_safe_patch_script=applied"
Write-Host "Compile-safe public patch applied."
