$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from V34, then apply the V35 conservative evidence-based layer.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v34-sniper-balanced.ps1

$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.93"', '#property version "2.94"')
$ea = $ea.Replace('V34 Balanced Sniper Quality Gate: HTF aligned 400-pip objective', 'V35 Sell Structure Quality Gate: weak pullback route pruned')
$ea = $ea.Replace('input string CSVJournalName="V34_BALANCED_SNIPER_journal.csv";', 'input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";')

# V34 evidence: CORE_PULLBACK_BUY_15 was unstable out-of-sample:
# Y0 1/5, PF 0.00, net -93.09; Y2 6/9, WR 66.7; combined below objective.
# V35 removes that weak route and keeps only sell routes with stricter HTF alignment.
$routePullbackBuy = @'

   if(setup=="PULLBACK" && dir>0 && hour==15)
   {
      name="CORE_PULLBACK_BUY_15";
      return true;
   }
'@
$ea = $ea.Replace($routePullbackBuy, "`n")

# Remove direct buy-side route eligibility and force H4 alignment, not merely non-opposition.
$routeQualityV34 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if((dir>0 && h1Bias<=0) || (dir<0 && h1Bias>=0))
      return false;
   if((dir>0 && h4Bias<0) || (dir<0 && h4Bias>0))
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="PULLBACK" && dir>0)
      return rsi>=53 && rsi<=65 && adx>=24 && volumeRatio>=1.08 && bodyRatio>=0.42;
   if(setup=="CONTINUATION" && dir<0)
      return rsi>=35 && rsi<=47 && adx>=25 && volumeRatio>=1.10 && bodyRatio>=0.43;
   if(setup=="SWEEP" && dir<0)
      return rsi>=35 && rsi<=49 && adx>=25 && volumeRatio>=1.12 && bodyRatio>=0.44;

   return false;
}
'@
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
if (!$ea.Contains($routeQualityV34)) { throw "V35 cannot find V34 RouteQuality block." }
$ea = $ea.Replace($routeQualityV34, $routeQualityV35)

# Global quality gates tightened. Risk remains unchanged at 0.20%.
$ea = $ea.Replace('input double MinSignalScore=86.0;', 'input double MinSignalScore=91.0;')
$ea = $ea.Replace('input double MinADX=24.0;', 'input double MinADX=28.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.055;', 'input double MaxSpreadATRFraction=0.045;')
$ea = $ea.Replace('input double MinBodyRatio=0.42;', 'input double MinBodyRatio=0.48;')
$ea = $ea.Replace('input double MinVolumeRatio=1.08;', 'input double MinVolumeRatio=1.18;')
$ea = $ea.Replace('input double ContinuationTP_ATR=3.35;', 'input double ContinuationTP_ATR=3.75;')
$ea = $ea.Replace('input double ContinuationSL_ATR=0.80;', 'input double ContinuationSL_ATR=0.74;')
$ea = $ea.Replace('input double SweepTP_ATR=3.55;', 'input double SweepTP_ATR=3.90;')
$ea = $ea.Replace('input double SweepSL_ATR=0.82;', 'input double SweepSL_ATR=0.76;')
$ea = $ea.Replace('input double BreakEvenTriggerATR=0.72;', 'input double BreakEvenTriggerATR=0.90;')
$ea = $ea.Replace('input double TrailStartATR=2.30;', 'input double TrailStartATR=2.75;')
$ea = $ea.Replace('input double TrailDistanceATR=1.00;', 'input double TrailDistanceATR=1.10;')
$ea = $ea.Replace('input double TimeExitMinProgressATR=0.38;', 'input double TimeExitMinProgressATR=0.45;')

# Base score sell-only sharpening. Buy scoring may remain in code, but RouteQuality blocks every buy route.
$ea = $ea.Replace('if(rsi>=37 && rsi<=45)', 'if(rsi>=38 && rsi<=44)')
$ea = $ea.Replace('else if(rsi>=35 && rsi<=48)', 'else if(rsi>=36 && rsi<=47)')
$ea = $ea.Replace('if(adx>=30)', 'if(adx>=32)')
$ea = $ea.Replace('if(volumeRatio>=1.32)', 'if(volumeRatio>=1.45)')
$ea = $ea.Replace('if(bodyRatio>=0.62)', 'if(bodyRatio>=0.66)')

$ea = $ea.Replace('string comment="V34 "+direction+" "+candidate.setup;', 'string comment="V35 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v34_balanced_sniper route="+activeRoute', '"v35_sell_structure route="+activeRoute')
$ea = $ea.Replace('V34_BALANCED_SNIPER_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_not_opposed=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true')

$required = @(
  'V35_SELL_STRUCTURE_QUALITY_GATE',
  'weak_pullback_buy_pruned=true',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20',
  'CORE_CONTINUATION_SELL_07_08',
  'CORE_SWEEP_SELL_13_14',
  'OrderCalcProfit'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V35 marker missing: $marker" }
}

$forbidden = @('EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','ZLEMA_AUTO','Zlema(','CORE_PULLBACK_BUY_15')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V35 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V35 sell-structure transform applied to $eaPath"
