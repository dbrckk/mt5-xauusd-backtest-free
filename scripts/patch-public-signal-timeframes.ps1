$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$runner = "scripts/run-public-history-backtest.ps1"
if (!(Test-Path $runner)) { throw "Runner not found: $runner" }

$txt = Get-Content -Path $runner -Raw
$marker = 'Set-Content -Path $setPath -Value $setLines -Encoding ASCII'
if (!$txt.Contains($marker)) { throw "Tester set marker not found." }

$extra = @'
$publicSignalTF = switch ($period) {
  "M15" { "15" }
  "M30" { "30" }
  "H1"  { "16385" }
  "H2"  { "16386" }
  "H4"  { "16388" }
  default { "15" }
}
$setLines += @("InpSignalTF=$publicSignalTF")
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_signal_tf_runtime_set=$publicSignalTF"
Add-Content -Path (Join-Path $reportsRoot "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_signal_tf_period=$period"
'@

if (-not $txt.Contains('public_signal_tf_runtime_set=')) {
  $txt = $txt.Replace($marker, $extra + "`r`n" + $marker)
  Set-Content -Path $runner -Value $txt -Encoding UTF8
}

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_multitf_signal_patch=true"
Write-Host "Public signal timeframe patch applied."
