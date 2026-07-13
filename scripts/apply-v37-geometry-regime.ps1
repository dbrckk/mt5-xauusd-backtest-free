$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "2.98"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V40 Hour-8 Continuation State Gate: rejected cells removed')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V40_H8_CONTINUATION_journal.csv";')

# V39 evidence rejected continuation hour 07 and sweep hours 13-14. Retain only
# continuation hour 08, the sole cell with positive evidence in Y0_OOS and Y3.
$routeOld = @'
   if(setup=="CONTINUATION" && dir<0 && hour>=7 && hour<9)
   {
      name="CORE_CONTINUATION_SELL_07_08";
      return true;
   }
   if(setup=="SWEEP" && dir<0 && hour>=13 && hour<15)
   {
      name="CORE_SWEEP_SELL_13_14";
      return true;
   }
'@
$routeNew = @'
   if(setup=="CONTINUATION" && dir<0 && hour==8)
   {
      name="CORE_CONTINUATION_SELL_08";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V40 cannot find V35 sell route block." }
$ea = $ea.Replace($routeOld, $routeNew)

$routeQualityV35 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0)
      return false;
   if(h1Bias>=0 || h4Bias>=0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="CONTINUATION" && dir<0)
      return rsi>=36 && rsi<=45 && adx>=28 && volumeRatio>=1.18 && bodyRatio>=0.48;
   if(setup=="SWEEP" && dir<0)
      return rsi>=36 && rsi<=48 && adx>=28 && volumeRatio>=1.20 && bodyRatio>=0.50;

   return false;
}
'@
$routeQualityV40 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || setup!="CONTINUATION")
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   return rsi>=30 && rsi<=55 && adx>=18 && volumeRatio>=0.80 && bodyRatio>=0.20;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V40 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV40)

# Opportunity and execution profile. Risk remains fixed at 0.20%.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=74.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=18.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.065;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.20;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.80;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=4.20;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.66;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=1.15;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=3.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=1.20;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=24;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.30;')

$volumeLine = '   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;'
$stateLines = @'
   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double recentLow=LL(rates,2,3);
   bool bearishState=(fast1<slow1 && fast1<=fast2 && rates[1].close<fast1);
   bool structurePressure=(rates[1].low<=rates[2].low && rates[1].close<=recentLow+atr*0.10);
'@
if (!$ea.Contains($volumeLine)) { throw "V40 cannot find volume ratio insertion point." }
$ea = $ea.Replace($volumeLine, $stateLines.TrimEnd())

$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(bearishState && structurePressure && rates[1].close<rates[1].open && rates[1].close<rates[2].close && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio && closeLocation<=0.58 && bearishDisplacement>=0.08)'
if (!$ea.Contains($continuationOld)) { throw "V40 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V40 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v40_h8_continuation route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V40_H8_CONTINUATION_STATE_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_bearish_h4_not_bullish=true deterministic_state=true routes=CORE_CONTINUATION_SELL_08 rejected_cells_pruned=true')

$required = @(
  'V40_H8_CONTINUATION_STATE_GATE',
  'deterministic_state=true',
  'bearishState',
  'structurePressure',
  'CORE_CONTINUATION_SELL_08',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V40 marker missing: $marker" }
}

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','ZLEMA_AUTO','Zlema(')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V40 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V40 hour-8 continuation-state transform applied to $eaPath"
