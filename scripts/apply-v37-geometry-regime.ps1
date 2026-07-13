$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "3.02"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V44 Hour-8 Early Failure Exit: V41 entry baseline')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V44_H8_EARLY_FAILURE_journal.csv";')

# Keep only the independently supported continuation cell at hour 08.
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
if (!$ea.Contains($routeOld)) { throw "V44 cannot find V35 sell route block." }
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
$routeQualityV44 = @'
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
if (!$ea.Contains($routeQualityV35)) { throw "V44 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV44)

# Preserve the V41 opportunity envelope and V40 structural exits.
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

$exitInputAnchor = 'input double TimeExitMinProgressATR=0.30;'
$exitInputs = @'
input double TimeExitMinProgressATR=0.30;
input bool UseEarlyFailureExit=true;
input int EarlyFailureBars=4;
input double EarlyFailureMinProgressATR=0.10;
input double EarlyFailureAdverseATR=0.30;
'@
if (!$ea.Contains($exitInputAnchor)) { throw "V44 cannot find exit input anchor." }
$ea = $ea.Replace($exitInputAnchor, $exitInputs.TrimEnd())

# Restore the broad V41-style hour-8 opportunity trigger; only exits change in this experiment.
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
   bool h8OpportunityTrigger=(bearishState && h1Bias<0 && h4Bias<=0 && (structurePressure || momentumExpansion));
'@
if (!$ea.Contains($biasAnchor)) { throw "V44 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $entryLines.TrimEnd())

$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(h8OpportunityTrigger && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)'
if (!$ea.Contains($continuationOld)) { throw "V44 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

# Deterministic early-failure exit: cut stalled or adversely displaced trades during the first four M15 bars.
$manageAnchor = @'
   if(MaxHoldBars>0 && TimeCurrent()-openTime>=MaxHoldBars*900 && favorableDistance<atr*TimeExitMinProgressATR)
   {
      Close("TIME_STOP_NO_PROGRESS");
      return;
   }

   double desiredSl=sl;
'@
$manageReplacement = @'
   if(MaxHoldBars>0 && TimeCurrent()-openTime>=MaxHoldBars*900 && favorableDistance<atr*TimeExitMinProgressATR)
   {
      Close("TIME_STOP_NO_PROGRESS");
      return;
   }

   if(UseEarlyFailureExit && EarlyFailureBars>0)
   {
      int elapsedBars=(int)((TimeCurrent()-openTime)/900);
      double adverseDistance=buy?openPrice-marketPrice:marketPrice-openPrice;
      double fastNow;
      bool fastAvailable=One(fH,0,1,fastNow);
      bool structureInvalidated=fastAvailable && ((buy && marketPrice<fastNow) || (!buy && marketPrice>fastNow));
      bool stalled=(elapsedBars>=2 && favorableDistance<atr*EarlyFailureMinProgressATR && structureInvalidated);
      bool adverse=(elapsedBars>=1 && adverseDistance>=atr*EarlyFailureAdverseATR);
      if(elapsedBars<=EarlyFailureBars && (stalled || adverse))
      {
         Close(adverse?"EARLY_FAILURE_ADVERSE":"EARLY_FAILURE_STALLED");
         return;
      }
   }

   double desiredSl=sl;
'@
if (!$ea.Contains($manageAnchor)) { throw "V44 cannot find Manage exit anchor." }
$ea = $ea.Replace($manageAnchor, $manageReplacement.TrimEnd())

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V44 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v44_h8_early_failure route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V44_H8_EARLY_FAILURE_EXIT risk_normalized=true max_trades_week=4 min_target_pips=400 h1_bearish_h4_not_bullish=true v41_entry_baseline=true early_failure_exit=true early_failure_bars=4 early_failure_adverse_atr=0.30 exits_structural_target_locked=true routes=CORE_CONTINUATION_SELL_08 rejected_cells_pruned=true')

$required = @(
  'V44_H8_EARLY_FAILURE_EXIT',
  'v41_entry_baseline=true',
  'early_failure_exit=true',
  'UseEarlyFailureExit=true',
  'EarlyFailureBars=4',
  'EarlyFailureAdverseATR=0.30',
  'h8OpportunityTrigger',
  'structurePressure',
  'momentumExpansion',
  'EARLY_FAILURE_ADVERSE',
  'EARLY_FAILURE_STALLED',
  'CORE_CONTINUATION_SELL_08',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V44 marker missing: $marker" }
}

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','ZLEMA_AUTO','Zlema(','boundedRetest','retestTouch','h8StateTrigger','h8DirectTrigger','directStructureBreak','bearishExpansion')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V44 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V44 hour-8 early-failure exit transform applied to $eaPath"