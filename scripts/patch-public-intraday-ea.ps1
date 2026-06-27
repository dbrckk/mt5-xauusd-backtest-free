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

if ($src.Contains($oldSession)) {
  $src = $src.Replace($oldSession, $newSession)
  $changed = $true
}

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

if ($src.Contains($oldQuality)) {
  $src = $src.Replace($oldQuality, $newQuality)
  $changed = $true
}

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

double publicScore = DirectionScore(sig, sig.direction);

if(sig.direction != 0 && publicScore >= InpMinScoreToEnter && sig.scoreGap >= InpMinScoreGap && sig.sessionQuality >= 3)

{

g_status = "PUBLIC_INTRADAY_ENTRY_OK";

return true;

}

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

if ($src.Contains($oldVGate)) {
  $src = $src.Replace($oldVGate, $newVGate)
  $changed = $true
}

if (!$changed) { throw "No public intraday EA patches were applied." }

Set-Content -Path $ea -Value $src -Encoding UTF8
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_intraday_ea_patch=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_hard_london_ny_only=true"
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_vgate_fastpass=true"
Write-Host "Public intraday EA patch applied."
