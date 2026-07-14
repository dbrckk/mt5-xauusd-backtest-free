$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "3.05"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V47 H8-H9-H11 Continuation Expansion: hour-10 rejected, hour-11 independent validation')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V47_H8_H9_H11_CONTINUATION_journal.csv";')

# Retain V45 hour-08/hour-09 evidence, permanently prune failed hour 10, and add only fresh hour 11.
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
   if(setup=="CONTINUATION" && dir<0 && hour==9)
   {
      name="PROVISIONAL_CONTINUATION_SELL_09";
      return true;
   }
   if(setup=="CONTINUATION" && dir<0 && hour==11)
   {
      name="TEST_CONTINUATION_SELL_11";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V47 cannot find V35 sell route block." }
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
$routeQualityV47 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || setup!="CONTINUATION")
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   return rsi>=26 && rsi<=60 && adx>=15 && volumeRatio>=0.65 && bodyRatio>=0.12;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V47 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV47)

# Preserve the broad V41 opportunity envelope and V40 structural exits.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=68.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=15.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.075;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.12;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.65;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=4.20;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.66;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=1.15;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=3.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=1.20;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=24;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.30;')

# Broad deterministic continuation trigger. Routing isolates hour 11 for fresh evidence.
$biasAnchor = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
'@
$entryLines = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   bool bearishState=(fast1<slow1 && fast1<=fast2 && rates[1].close<fast1);
   bool structurePressure=(rates[1].close<rates[2].low && rates[1].close<rates[1].open);
   bool momentumExpansion=(bearishDisplacement>=0.08 && closeLocation<=0.45 && rates[1].close<rates[2].close);
   bool sessionOpportunityTrigger=(bearishState && h1Bias<0 && h4Bias<=0 && (structurePressure || momentumExpansion));
'@
if (!$ea.Contains($biasAnchor)) { throw "V47 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $entryLines.TrimEnd())

$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(sessionOpportunityTrigger && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)'
if (!$ea.Contains($continuationOld)) { throw "V47 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V47 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v47_h8_h9_h11_continuation route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V47_H8_H9_H11_CONTINUATION_EXPANSION risk_normalized=true max_trades_week=4 min_target_pips=400 h1_bearish_h4_not_bullish=true v41_entry_baseline=true structural_exits_restored=true routes=CORE_CONTINUATION_SELL_08|PROVISIONAL_CONTINUATION_SELL_09|TEST_CONTINUATION_SELL_11 rejected_cells_pruned=true retained_v45_h9=true rejected_v46_h10=true fresh_cell_11=true')

$required = @(
  'V47_H8_H9_H11_CONTINUATION_EXPANSION',
  'v41_entry_baseline=true',
  'structural_exits_restored=true',
  'retained_v45_h9=true',
  'rejected_v46_h10=true',
  'fresh_cell_11=true',
  'sessionOpportunityTrigger',
  'structurePressure',
  'momentumExpansion',
  'CORE_CONTINUATION_SELL_08',
  'PROVISIONAL_CONTINUATION_SELL_09',
  'TEST_CONTINUATION_SELL_11',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V47 marker missing: $marker" }
}

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','TEST_CONTINUATION_SELL_09','TEST_CONTINUATION_SELL_10','ZLEMA_AUTO','Zlema(','boundedRetest','retestTouch','h8StateTrigger','h8DirectTrigger','directStructureBreak','bearishExpansion','UseEarlyFailureExit','EARLY_FAILURE_ADVERSE','EARLY_FAILURE_STALLED')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V47 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V47 H8-H9-H11 continuation expansion transform applied to $eaPath"
