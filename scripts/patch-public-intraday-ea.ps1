$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$reports = Join-Path (Resolve-Path ".").Path "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$ea = "MQL5/Experts/QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $ea)) { throw "EA source not found: $ea" }

$src = Get-Content -Path $ea -Raw
$changed = $false

$oldSession = @'
bool SessionOK()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

if(!DayAllowed()) return false;

if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return false;

return true;

}
'@

$newSession = @'
bool SessionOK()

{

MqlDateTime t;

TimeToStruct(TimeCurrent(), t);

if(!DayAllowed()) return false;

if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

bool london = (t.hour >= InpLondonStartHourServer && t.hour < InpLondonEndHourServer);

bool ny = (t.hour >= InpNYStartHourServer && t.hour < InpNYEndHourServer);

if(!(london || ny)) return false;

return true;

}

if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return false;

return true;

}
'@

if ($src.Contains($oldSession)) { $src = $src.Replace($oldSession, $newSession); $changed = $true }

$oldQuality = @'
if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return 0;

if(t.day_of_week == 5 && InpBlockFridayLate && t.hour >= InpFridayStopHourServer) return 0;

bool london = (t.hour >= InpLondonStartHourServer && t.hour < InpLondonEndHourServer);

bool ny = (t.hour >= InpNYStartHourServer && t.hour < InpNYEndHourServer);

bool asian = (t.hour < InpAsianEndHourServer);

if(InpBlockAsianSession && asian) return 0;

if(london || ny) return 3;

return 1;
'@

$newQuality = @'
if(t.hour < InpStartHourServer || t.hour >= InpEndHourServer) return 0;

if(t.day_of_week == 5 && InpBlockFridayLate && t.hour >= InpFridayStopHourServer) return 0;

bool london = (t.hour >= InpLondonStartHourServer && t.hour < InpLondonEndHourServer);

bool ny = (t.hour >= InpNYStartHourServer && t.hour < InpNYEndHourServer);

bool asian = (t.hour < InpAsianEndHourServer);

if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

if(london || ny) return 3;

return 0;

}

if(InpBlockAsianSession && asian) return 0;

if(london || ny) return 3;

return 1;
'@

if ($src.Contains($oldQuality)) { $src = $src.Replace($oldQuality, $newQuality); $changed = $true }

$oldVGate = @'
if(!V14InitialEntryGateOK(sig))

return false;

if(!V15InitialEntryGateOK(sig))

return false;

if(!V16InitialEntryGateOK(sig))

return false;

if(!V17InitialEntryGateOK(sig))

return false;

return true;
'@

$newVGate = @'
if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

MqlDateTime publicTime;

TimeToStruct(TimeCurrent(), publicTime);

bool publicLondon = (publicTime.hour >= InpLondonStartHourServer && publicTime.hour < InpLondonEndHourServer);

bool publicNY = (publicTime.hour >= InpNYStartHourServer && publicTime.hour < InpNYEndHourServer);

bool publicLateNY = (publicNY && (publicTime.hour > 15 || (publicTime.hour == 15 && publicTime.min >= 30)));

double publicScore = DirectionScore(sig, sig.direction);

double publicMinScore = (publicLondon ? 50.0 : 65.0);

bool publicSlopeOK = ((sig.direction == 1 && sig.emaSlopeATR > 0.05) || (sig.direction == -1 && sig.emaSlopeATR < -0.05));

bool publicImpulseOK = !(publicNY && sig.bodyATR > 1.50 && sig.distanceFromSignalEMAATR < 1.00);

bool publicOK = (sig.direction != 0 && sig.sessionQuality >= 3 && !publicLateNY && publicScore >= publicMinScore && sig.scoreGap >= InpMinScoreGap && publicSlopeOK && publicImpulseOK);

if(publicOK)

{

g_status = "PUBLIC_INTRADAY_ENTRY_OK";

return true;

}

g_status = "PUBLIC_INTRADAY_ENTRY_BLOCK";

DecisionLog(g_status + " score=" + DoubleToString(publicScore, 1) + " min=" + DoubleToString(publicMinScore, 1) + " gap=" + DoubleToString(sig.scoreGap, 1) + " slope=" + DoubleToString(sig.emaSlopeATR, 3) + " bodyATR=" + DoubleToString(sig.bodyATR, 2) + " distEMA=" + DoubleToString(sig.distanceFromSignalEMAATR, 2));

return false;

}

if(!V14InitialEntryGateOK(sig))

return false;

if(!V15InitialEntryGateOK(sig))

return false;

if(!V16InitialEntryGateOK(sig))

return false;

if(!V17InitialEntryGateOK(sig))

return false;

return true;
'@

if ($src.Contains($oldVGate)) { $src = $src.Replace($oldVGate, $newVGate); $changed = $true }

$oldPublicTarget = @'
datetime oldest = BasketOldestTime();

double distATR = dist / atr;
'@

$newPublicTarget = @'
datetime oldest = BasketOldestTime();

double distATR = dist / atr;

if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

double publicBasketProfit = BasketProfit();

double publicScore = DirectionScore(sig, dir);

int publicHeldMinutes = (oldest > 0 ? (int)((TimeCurrent() - oldest) / 60) : 0);

if(publicBasketProfit >= 20.0 && dist >= 20.0)

{

CloseAll();

g_status = "PUBLIC_20_POINT_PROFIT_EXIT";

JournalEvent(g_status, StringFormat("profit=%.2f dist=%.2f score=%.1f held=%d", publicBasketProfit, dist, publicScore, publicHeldMinutes));

g_cooldownUntil = TimeCurrent() + 60 * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

return;

}

if(publicHeldMinutes >= 45 && dist <= -20.0)

{

CloseAll();

g_status = "PUBLIC_HARD_CUT";

JournalEvent(g_status, StringFormat("profit=%.2f dist=%.2f score=%.1f held=%d", publicBasketProfit, dist, publicScore, publicHeldMinutes));

g_cooldownUntil = TimeCurrent() + 60 * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

return;

}

if(publicHeldMinutes >= 90 && dist <= -10.0 && publicScore < 58.0)

{

CloseAll();

g_status = "PUBLIC_RISK_CUT";

JournalEvent(g_status, StringFormat("profit=%.2f dist=%.2f score=%.1f held=%d", publicBasketProfit, dist, publicScore, publicHeldMinutes));

g_cooldownUntil = TimeCurrent() + 45 * 60;

g_basketPeakProfit = 0.0;

g_partialDone = false;

g_runnerBestScore = 0.0;

g_runnerBestDistanceATR = 0.0;

g_v17BasketMFEATR = 0.0;

return;

}

}
'@

if ($src.Contains($oldPublicTarget)) { $src = $src.Replace($oldPublicTarget, $newPublicTarget); $changed = $true }

if (!$changed) { throw "No public intraday EA patches were applied." }
Set-Content -Path $ea -Value $src -Encoding UTF8

$runner = "scripts/run-public-history-backtest.ps1"
$marker = 'Set-Content -Path $setPath -Value $setLines -Encoding ASCII'
if (Test-Path $runner) {
  $runTxt = Get-Content -Path $runner -Raw
  if ($runTxt.Contains($marker) -and -not $runTxt.Contains('public_20_30_point_runtime_set')) {
    $extra = '$setLines += @("InpMaxNewEntriesPerDay=4","InpUseBasketTimeProfitExit=true","InpBasketTimeProfitMinutes=180","InpMinTimedExitProfitPct=0.20")' + "`r`n" + '$setLines += @("public_20_30_point_runtime_set=true")'
    $runTxt = $runTxt.Replace($marker, $extra + "`r`n" + $marker)
    Set-Content -Path $runner -Value $runTxt -Encoding UTF8
  }
}

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_intraday_ea_patch=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_hard_london_ny_only=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_vgate_fastpass=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_hard_entry_gate=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_ny_min_score=65"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_block_late_ny_entries=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_slope_filter=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_20_30_point_exit=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_risk_cut=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_hard_cut=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_post_profit_cooldown=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_session_flat_disabled=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_20_30_point_runtime_set=true"
Write-Host "Public intraday EA patch applied."
