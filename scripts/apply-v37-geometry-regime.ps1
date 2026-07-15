$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "3.07"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V49 Deterministic Regime Structure State Machine: structure-break and sweep-failure states')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V49_REGIME_STRUCTURE_STATE_MACHINE_journal.csv";')

# Preserve only independently retained hours 08 and 09. Rejected hours 07/10/11/12/13/14 remain absent.
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
   if(setup=="STRUCTURE_BREAK" && dir<0 && hour==8)
   {
      name="STATE_STRUCTURE_BREAK_SELL_08";
      return true;
   }
   if(setup=="STRUCTURE_BREAK" && dir<0 && hour==9)
   {
      name="STATE_STRUCTURE_BREAK_SELL_09";
      return true;
   }
   if(setup=="SWEEP_FAILURE" && dir<0 && hour==8)
   {
      name="STATE_SWEEP_FAILURE_SELL_08";
      return true;
   }
   if(setup=="SWEEP_FAILURE" && dir<0 && hour==9)
   {
      name="STATE_SWEEP_FAILURE_SELL_09";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V49 cannot find V35 sell route block." }
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
$routeQualityV49 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || (setup!="STRUCTURE_BREAK" && setup!="SWEEP_FAILURE"))
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="STRUCTURE_BREAK")
      return rsi>=28 && rsi<=54 && adx>=18 && volumeRatio>=0.82 && bodyRatio>=0.22;
   if(setup=="SWEEP_FAILURE")
      return rsi>=30 && rsi<=56 && adx>=16 && volumeRatio>=0.75 && bodyRatio>=0.18;

   return false;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V49 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV49)

# Keep the risk-normalized asymmetric exit profile validated operationally in V45-V48.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=72.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=16.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.060;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.18;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.75;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=4.20;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.66;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=1.15;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=3.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=1.20;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=24;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.30;')

# Deterministic state machine: HTF regime -> local trend -> volatility context -> structure event.
$biasAnchor = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
'@
$stateLines = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double recentRangeMean=0.0;
   for(int stateIndex=3;stateIndex<=8;stateIndex++)
      recentRangeMean+=(rates[stateIndex].high-rates[stateIndex].low)/6.0;
   double priorStructureLow=LL(rates,2,6);
   double priorLiquidityHigh=HH(rates,3,6);
   bool regimeBearish=(h1Bias<0 && h4Bias<=0);
   bool localBearish=(fast1<slow1 && fast1<=fast2 && rates[1].close<fast1 && rates[1].close<trend);
   bool volatilityReady=(recentRangeMean<=atr*1.10 && range>=atr*0.55);
   bool decisiveClose=(rates[1].close<rates[1].open && closeLocation<=0.38 && bearishDisplacement>=0.20);
   bool structureBreakState=(regimeBearish && localBearish && volatilityReady && decisiveClose && rates[1].close<priorStructureLow);
   bool priorSweep=(rates[2].high>priorLiquidityHigh && rates[2].close<rates[2].high-(rates[2].high-rates[2].low)*0.45);
   bool sweepFailureState=(regimeBearish && localBearish && priorSweep && decisiveClose && rates[1].close<rates[2].low);
'@
if (!$ea.Contains($biasAnchor)) { throw "V49 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $stateLines.TrimEnd())

# Match the V35 continuation entry independently of CRLF/LF normalization and indentation.
$continuationPattern = '(?ms)^[ \t]*if\(rates\[1\]\.close<rates\[2\]\.low\s*&&\s*rates\[2\]\.close<rates\[2\]\.open\s*&&\s*fast1<fast2\s*&&\s*bodyRatio>=0\.38\s*&&\s*volumeRatio>=MinVolumeRatio\)\s*\r?\n[ \t]*Consider\(-1,"CONTINUATION",sellBase\+18,atr,now\.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate\);'
$stateEntry = @'
      if(structureBreakState && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"STRUCTURE_BREAK",sellBase+22,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);

      if(sweepFailureState && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"SWEEP_FAILURE",sellBase+20,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
'@
$continuationMatches = [regex]::Matches($ea, $continuationPattern)
if ($continuationMatches.Count -ne 1) { throw "V49 expected exactly one continuation sell condition, found $($continuationMatches.Count)." }
$ea = [regex]::Replace($ea, $continuationPattern, $stateEntry.TrimEnd(), 1)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V49 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v49_regime_structure_state route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V49_REGIME_STRUCTURE_STATE_MACHINE risk_normalized=true max_trades_week=4 min_target_pips=400 deterministic_state_machine=true h1_bearish_h4_not_bullish=true routes=STATE_STRUCTURE_BREAK_SELL_08|STATE_STRUCTURE_BREAK_SELL_09|STATE_SWEEP_FAILURE_SELL_08|STATE_SWEEP_FAILURE_SELL_09 rejected_cells_pruned=07|10|11|12|13|14 structural_exits_restored=true V48 H8-H9-H12 Continuation Expansion V48_H8_H9_H12_CONTINUATION_EXPANSION v41_entry_baseline=true retained_v45_h9=true rejected_v46_h10=true rejected_v47_h11=true fresh_cell_12=true sessionOpportunityTrigger structurePressure momentumExpansion CORE_CONTINUATION_SELL_08 PROVISIONAL_CONTINUATION_SELL_09 TEST_CONTINUATION_SELL_12')

$required = @(
   'V49_REGIME_STRUCTURE_STATE_MACHINE',
   'deterministic_state_machine=true',
   'structureBreakState',
   'sweepFailureState',
   'volatilityReady',
   'priorSweep',
   'STATE_STRUCTURE_BREAK_SELL_08',
   'STATE_STRUCTURE_BREAK_SELL_09',
   'STATE_SWEEP_FAILURE_SELL_08',
   'STATE_SWEEP_FAILURE_SELL_09',
   'MaxTradesPerWeek=4',
   'MinTargetPips=400.0',
   'RiskPercent=0.20'
)
foreach ($marker in $required) {
   if (!$ea.Contains($marker)) { throw "V49 marker missing: $marker" }
}

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','TEST_CONTINUATION_SELL_09','TEST_CONTINUATION_SELL_10','TEST_CONTINUATION_SELL_11','ZLEMA_AUTO','Zlema(','boundedRetest','retestTouch','h8StateTrigger','h8DirectTrigger','directStructureBreak','bearishExpansion','UseEarlyFailureExit','EARLY_FAILURE_ADVERSE','EARLY_FAILURE_STALLED')
foreach ($marker in $forbidden) {
   if ($ea.Contains($marker)) { throw "V49 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V49 deterministic regime/structure state-machine transform applied to $eaPath"
