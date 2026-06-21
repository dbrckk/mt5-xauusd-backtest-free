$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

function Build-Candidates($raw) {
  $items = New-Object System.Collections.Generic.List[string]
  if ($raw -and $raw.ToUpperInvariant() -notin @("AUTO", "FIND", "AUTO_GOLD")) {
    foreach ($part in ($raw -split ',')) {
      $p = $part.Trim()
      if ($p) { $items.Add($p) }
    }
  }
  foreach ($s in @("XAUUSD", "XAUUSD.", "XAUUSDm", "XAUUSD.r", "XAUUSD.pro", "GOLD", "GOLD.", "GOLDm", "Gold")) {
    $items.Add($s)
  }
  $seen = @{}
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($s in $items) {
    if (!$seen.ContainsKey($s)) {
      $seen[$s] = $true
      $out.Add($s)
    }
  }
  return $out
}

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$rawSymbol = if ($env:BT_SYMBOL) { $env:BT_SYMBOL } else { "AUTO" }
$candidates = Build-Candidates $rawSymbol
$candidates | Set-Content -Path (Join-Path $reports "symbol_candidates.txt") -Encoding UTF8

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("symbol`texit_code`tstatus")
$originalTimeout = $env:BT_TIMEOUT_MINUTES
$env:BT_TIMEOUT_MINUTES = "45"
$selected = $null

foreach ($candidate in $candidates) {
  Write-Host ""
  Write-Host "==================== AUTO TEST SYMBOL: $candidate ===================="
  $env:BT_SYMBOL = $candidate
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo "scripts\run-mt5-backtest.ps1")
  $code = $LASTEXITCODE
  if ($code -eq 0) {
    $summary.Add("$candidate`t$code`tSUCCESS")
    $selected = $candidate
    Set-Content -Path (Join-Path $reports "selected_symbol.txt") -Value $candidate -Encoding UTF8
    break
  }
  $summary.Add("$candidate`t$code`tFAILED_OR_NO_HISTORY")
}

if ($originalTimeout) { $env:BT_TIMEOUT_MINUTES = $originalTimeout }
$summary | Set-Content -Path (Join-Path $reports "symbol_scan_summary.tsv") -Encoding UTF8

if ($selected) {
  Write-Host "SELECTED_SYMBOL=$selected"
  exit 0
}

Write-Host "No usable XAU/GOLD symbol found. Check reports/symbol_scan_summary.tsv and Logs_copy in artifact."
exit 1
