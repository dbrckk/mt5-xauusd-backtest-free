$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$eaSource = "MQL5/Experts/QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $eaSource)) { throw "EA source not found: $eaSource" }

$txt = Get-Content -Path $eaSource -Raw

$oldStops = "    request.sl = NormalizeDouble(sl, digits);`r`n    request.tp = NormalizeDouble(tp, digits);"
if (-not $txt.Contains($oldStops)) {
  $oldStops = "    request.sl = NormalizeDouble(sl, digits);`n    request.tp = NormalizeDouble(tp, digits);"
}
$newStops = "    if(g_symbol == `"XAU_PUBLIC`")`r`n    {`r`n       request.sl = 0.0;`r`n       request.tp = 0.0;`r`n    }`r`n    else`r`n    {`r`n       request.sl = NormalizeDouble(sl, digits);`r`n       request.tp = NormalizeDouble(tp, digits);`r`n    }"

if ($txt.Contains($oldStops) -and -not $txt.Contains("public_v23_no_initial_stops_marker")) {
  $txt = $txt.Replace($oldStops, "    // public_v23_no_initial_stops_marker`r`n" + $newStops)
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_no_sl_orders=true"
}

$txt = $txt.Replace('request.deviation = InpDeviationPoints;', 'request.deviation = (g_symbol == "XAU_PUBLIC" ? 100000 : InpDeviationPoints);')

Set-Content -Path $eaSource -Value $txt -Encoding UTF8
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v23_order_execution_patch=true"
Write-Host "V23 public order execution patch applied."
