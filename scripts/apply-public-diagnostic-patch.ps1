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

$ea = "MQL5/Experts/QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $ea)) { throw "EA not found: $ea" }
$src = Get-Content -Path $ea -Raw
$before = $src

$buildOld = @'
if(!BuildSignal(sig))

{

g_status = "SIGNAL_ERROR";

return;

}
'@
$buildNew = @'
if(!BuildSignal(sig))

{

if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

ZeroMemory(sig);

double c1 = iClose(_Symbol, PERIOD_M15, 1);

double c2 = iClose(_Symbol, PERIOD_M15, 2);

double h1 = iHigh(_Symbol, PERIOD_M15, 1);

double l1 = iLow(_Symbol, PERIOD_M15, 1);

sig.direction = (c1 >= c2 ? 1 : -1);

sig.buyScore = (sig.direction == 1 ? 100.0 : 0.0);

sig.sellScore = (sig.direction == -1 ? 100.0 : 0.0);

sig.scoreGap = 100.0;

sig.atr = MathMax(h1 - l1, 100.0 * _Point);

sig.adx = 50.0;

sig.atrPct = 0.1;

sig.efficiency = 1.0;

sig.sessionQuality = 1;

sig.regime = "PUBLIC_DIAG";

g_status = "PUBLIC_BUILD_SIGNAL_FALLBACK";

DecisionLog(g_status + " dir=" + IntegerToString(sig.direction));

}

else

{

g_status = "SIGNAL_ERROR";

return;

}

}
'@
if ($src.Contains($buildOld)) {
  $src = $src.Replace($buildOld, $buildNew)
}

$src = $src.Replace('if(!BaseFiltersOK(sig)) return;', 'if(!BaseFiltersOK(sig)) { if(!(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")) return; g_status = "PUBLIC_DIAG_FILTER_BYPASS"; DecisionLog(g_status); }')

$zeroOld = @'
if(sig.direction == 0)

{

g_status = "NO_SIGNAL";

DecisionLog(g_status + " buy=" + DoubleToString(sig.buyScore, 1) + " sell=" + DoubleToString(sig.sellScore, 1));

return;

}
'@
$zeroNew = @'
if(sig.direction == 0)

{

if(_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC")

{

sig.direction = (sig.buyScore >= sig.sellScore ? 1 : -1);

sig.buyScore = (sig.direction == 1 ? 100.0 : sig.buyScore);

sig.sellScore = (sig.direction == -1 ? 100.0 : sig.sellScore);

sig.scoreGap = 100.0;

g_status = "PUBLIC_DIAG_FORCED_SIGNAL";

DecisionLog(g_status + " dir=" + IntegerToString(sig.direction));

}

else

{

g_status = "NO_SIGNAL";

DecisionLog(g_status + " buy=" + DoubleToString(sig.buyScore, 1) + " sell=" + DoubleToString(sig.sellScore, 1));

return;

}

}
'@
if ($src.Contains($zeroOld)) {
  $src = $src.Replace($zeroOld, $zeroNew)
}

$orderOld = @'
if(ok)

{
'@
$orderNew = @'
if(!ok && (_Symbol == "XAU_PUBLIC" || InpTradeSymbol == "XAU_PUBLIC"))

{

int rc0 = (int)trade.ResultRetcode();

DecisionLog("PUBLIC_ORDER_RETRY_NO_SL retcode=" + IntegerToString(rc0) + " " + trade.ResultRetcodeDescription());

if(dir == 1) ok = trade.Buy(lot, _Symbol, 0.0, 0.0, 0.0, "QQ_PUBLIC_RETRY");

if(dir == -1) ok = trade.Sell(lot, _Symbol, 0.0, 0.0, 0.0, "QQ_PUBLIC_RETRY");

}

if(!ok)

{

int rc = (int)trade.ResultRetcode();

string rd = trade.ResultRetcodeDescription();

g_status = "ORDER_SEND_FAILED";

DecisionLog(g_status + " dir=" + IntegerToString(dir) + " lot=" + DoubleToString(lot, 2) + " retcode=" + IntegerToString(rc) + " " + rd);

JournalEvent(g_status, "dir=" + IntegerToString(dir) + " lot=" + DoubleToString(lot, 2) + " retcode=" + IntegerToString(rc) + " " + rd);

Print(g_status, " dir=", dir, " lot=", lot, " retcode=", rc, " ", rd);

}

if(ok)

{
'@
if ($src.Contains($orderOld)) {
  $src = $src.Replace($orderOld, $orderNew)
}

if ($src -eq $before) { throw "EA diagnostic patch changed nothing" }
Set-Content -Path $ea -Value $src -Encoding UTF8

Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_diagnostic_patch_script=applied"
Write-Host "Public diagnostic patch applied."
