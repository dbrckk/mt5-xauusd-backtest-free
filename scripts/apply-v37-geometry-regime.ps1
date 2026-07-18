$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

$ea = $ea.Replace('#property version "2.94"', '#property version "3.10"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V50 Hour-8 Pullback Rejection and Break-Retest State Machine')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V50_H8_BREAK_RETEST_EVIDENCE_PRUNED_journal.csv";')

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
   if(setup=="PULLBACK_REJECTION" && dir<0 && hour==8)
   {
      name="STATE_PULLBACK_REJECTION_SELL_08";
      return true;
   }
   if(setup=="BREAK_RETEST" && dir<0 && hour==8)
   {
      name="STATE_BREAK_RETEST_SELL_08";
      return true;
   }
'@
if (!$ea.Contains($routeOld)) { throw "V50 cannot find V35 sell route block." }
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
$routeQualityV50 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0 || setup!="BREAK_RETEST")
      return false;
   if(h1Bias>=0 || h4Bias>0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   return rsi>=32 && rsi<=52 && adx>=16 && volumeRatio>=0.75 && bodyRatio>=0.16;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V50 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV50)

$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=72.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=16.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.065;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.16;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=0.75;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.75;', 'input double ContinuationTP_ATR=3.20;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.74;', 'input double ContinuationSL_ATR=0.72;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.90;', 'input double BreakEvenTriggerATR=0.85;')
$ea = $ea.Replace('input double TrailStartATR=2.75;', 'input double TrailStartATR=2.00;')
$ea = $ea.Replace('input double TrailDistanceATR=1.10;', 'input double TrailDistanceATR=0.90;')
$ea = $ea.Replace('input int MaxHoldBars=28;', 'input int MaxHoldBars=20;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.45;', 'input double TimeExitMinProgressATR=0.22;')

$indicatorOld = @'
   double fast1;
   double fast2;
   double slow1;
   double trend;
   double rsi;
   double atr;
   double adx;
   if(!One(fH,0,1,fast1) || !One(fH,0,2,fast2) || !One(sH,0,1,slow1) || !One(tH,0,1,trend) ||
      !One(rH,0,1,rsi) || !One(aH,0,1,atr) || !One(dH,0,1,adx) || atr<=0)
      return false;
'@
$indicatorNew = @'
   double fast1;
   double fast2;
   double slow1;
   double slow2;
   double trend;
   double rsi;
   double atr;
   double adx;
   if(!One(fH,0,1,fast1) || !One(fH,0,2,fast2) || !One(sH,0,1,slow1) || !One(sH,0,2,slow2) || !One(tH,0,1,trend) ||
      !One(rH,0,1,rsi) || !One(aH,0,1,atr) || !One(dH,0,1,adx) || atr<=0)
      return false;
'@
if (!$ea.Contains($indicatorOld)) { throw "V50 cannot find indicator acquisition block." }
$ea = $ea.Replace($indicatorOld, $indicatorNew)

$biasAnchor = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
'@
$stateLines = @'
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);
   double spread=(double)SymbolInfoInteger(Sym,SYMBOL_SPREAD)*SymbolInfoDouble(Sym,SYMBOL_POINT);
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double bearishDisplacement=(rates[1].open-rates[1].close)/atr;
   double priorStructureLow=LL(rates,3,6);
   double microStructureLow=LL(rates,3,3);
   bool regimeBearish=(h1Bias<0 && h4Bias<=0);
   bool localBearish=(fast1<slow1 && fast1<=fast2 && slow1<=slow2 && rates[1].close<trend);
   bool spreadSafe=(spread<=atr*MaxSpreadATRFraction);
   bool rejectionClose=(rates[1].close<rates[1].open && closeLocation<=0.45 && bearishDisplacement>=0.10);
   bool pullbackTouched=false;
   bool pullbackRejectionState=false;
   bool priorBreak=(rates[2].close<priorStructureLow && rates[2].close<rates[2].open);
   bool retestTouched=(rates[1].high>=priorStructureLow-atr*0.05 && rates[1].high<=priorStructureLow+atr*0.35);
   bool retestRejected=(rates[1].close<priorStructureLow && rejectionClose);
   bool classicalRetest=(priorBreak && retestTouched && retestRejected);
   bool microBreak=(rates[2].close<microStructureLow && rates[2].close<rates[2].open);
   bool microRetestTouched=(rates[1].high>=rates[2].close && rates[1].high<=microStructureLow+atr*0.25);
   bool microRetestRejected=(rates[1].close<rates[2].close && rejectionClose);
   bool microRetest=(microBreak && microRetestTouched && microRetestRejected);
   bool breakRetestState=(regimeBearish && localBearish && spreadSafe && (classicalRetest || microRetest));
'@
if (!$ea.Contains($biasAnchor)) { throw "V50 cannot find HTF bias insertion point." }
$ea = $ea.Replace($biasAnchor, $stateLines.TrimEnd())

$continuationPattern = '(?ms)^[ \t]*if\(rates\[1\]\.close<rates\[2\]\.low\s*&&\s*rates\[2\]\.close<rates\[2\]\.open\s*&&\s*fast1<fast2\s*&&\s*bodyRatio>=0\.38\s*&&\s*volumeRatio>=MinVolumeRatio\)\s*\r?\n[ \t]*Consider\(-1,"CONTINUATION",sellBase\+18,atr,now\.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate\);'
$stateEntry = @'
      if(breakRetestState && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"BREAK_RETEST",sellBase+26,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
'@
$matches = [regex]::Matches($ea, $continuationPattern)
if ($matches.Count -ne 1) { throw "V50 expected exactly one continuation sell condition, found $($matches.Count)." }
$ea = [regex]::Replace($ea, $continuationPattern, $stateEntry.TrimEnd(), 1)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V50 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v50_h8_break_retest_evidence_pruned route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V50_H8_PULLBACK_BREAK_RETEST_STATE_MACHINE risk_normalized=true max_trades_week=4 min_target_pips=400 deterministic_state_machine=true h1_bearish_h4_not_bullish=true routes=STATE_BREAK_RETEST_SELL_08 rejected_cells_pruned=07|10|11|12|13|14 rejected_v49_hour09_states=true pullback_route_disabled_after_run100=true classical_or_micro_retest=true structural_exits=true')

$required = @('V50_H8_PULLBACK_BREAK_RETEST_STATE_MACHINE','deterministic_state_machine=true','pullbackRejectionState','breakRetestState','pullbackTouched','priorBreak','microRetest','STATE_PULLBACK_REJECTION_SELL_08','STATE_BREAK_RETEST_SELL_08','MaxTradesPerWeek=4','MinTargetPips=400.0','RiskPercent=0.20','double slow2;','SYMBOL_SPREAD','pullback_route_disabled_after_run100=true')
foreach ($marker in $required) { if (!$ea.Contains($marker)) { throw "V50 marker missing: $marker" } }

$forbidden = @('CORE_CONTINUATION_SELL_07_08','CORE_SWEEP_SELL_13_14','CORE_PULLBACK_BUY_15','EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','STATE_STRUCTURE_BREAK_SELL_09','STATE_SWEEP_FAILURE_SELL_09','STATE_STRUCTURE_BREAK_SELL_08','STATE_SWEEP_FAILURE_SELL_08','TEST_CONTINUATION_SELL_09','TEST_CONTINUATION_SELL_10','TEST_CONTINUATION_SELL_11','TEST_CONTINUATION_SELL_12','ZLEMA_AUTO','Zlema(','boundedRetest','UseEarlyFailureExit','EARLY_FAILURE_ADVERSE','EARLY_FAILURE_STALLED')
foreach ($marker in $forbidden) { if ($ea.Contains($marker)) { throw "V50 forbidden marker present: $marker" } }

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V50 evidence-pruned hour-8 classical/micro break-retest transform applied to $eaPath"
