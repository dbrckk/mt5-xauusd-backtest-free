$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

# Rebuild deterministically from the committed V35 sell-only profile.
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/apply-v35-sell-structure.ps1
$ea = Get-Content $eaPath -Raw

# Identity.
$ea = $ea.Replace('#property version "2.94"', '#property version "2.96"')
$ea = $ea.Replace('V35 Sell Structure Quality Gate: weak pullback route pruned', 'V38 Broad Sell Opportunity Gate: validated routes only')
$ea = $ea.Replace('input string CSVJournalName="V35_SELL_STRUCTURE_journal.csv";', 'input string CSVJournalName="V38_BROAD_SELL_journal.csv";')

# Expand opportunity only inside the two previously accepted route-hour cells.
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
$routeQualityV38 = @'
bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(dir>=0)
      return false;
   if(h1Bias>=0 || h4Bias>=0)
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="CONTINUATION" && dir<0)
      return rsi>=34 && rsi<=49 && adx>=22 && volumeRatio>=1.00 && bodyRatio>=0.34;
   if(setup=="SWEEP" && dir<0)
      return rsi>=34 && rsi<=50 && adx>=23 && volumeRatio>=1.02 && bodyRatio>=0.36;

   return false;
}
'@
if (!$ea.Contains($routeQualityV35)) { throw "V38 cannot find V35 RouteQuality block." }
$ea = $ea.Replace($routeQualityV35, $routeQualityV38)

# Recover a statistically useful sample without opening rejected routes or hours.
$ea = $ea.Replace('input double MinSignalScore=91.0;', 'input double MinSignalScore=84.0;')
$ea = $ea.Replace('input double MinADX=28.0;', 'input double MinADX=22.0;')
$ea = $ea.Replace('input double MaxSpreadATRFraction=0.045;', 'input double MaxSpreadATRFraction=0.060;')
$ea = $ea.Replace('input double MinBodyRatio=0.48;', 'input double MinBodyRatio=0.34;')
$ea = $ea.Replace('input double MinVolumeRatio=1.18;', 'input double MinVolumeRatio=1.00;')

# Retain directional geometry, but remove the V37 double-filter that reduced four years to two trades.
$volumeLine = '   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;'
$geometryLines = @'
   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;
   double closeLocation=(rates[1].close-rates[1].low)/range;
   double upperWickRatio=(rates[1].high-MathMax(rates[1].open,rates[1].close))/range;
'@
if (!$ea.Contains($volumeLine)) { throw "V38 cannot find volume ratio insertion point." }
$ea = $ea.Replace($volumeLine, $geometryLines.TrimEnd())

$continuationOld = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)'
$continuationNew = '      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio && closeLocation<=0.38 && upperWickRatio<=0.50)'
if (!$ea.Contains($continuationOld)) { throw "V38 cannot find continuation sell condition." }
$ea = $ea.Replace($continuationOld, $continuationNew)

$sweepOld = '      if(h1Bias<0 && h4Bias<0 && rates[1].high>previousHigh && rates[1].close<previousHigh && rates[1].close<rates[1].open && rsi<53 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)'
$sweepNew = '      if(h1Bias<0 && h4Bias<0 && rates[1].high>previousHigh && rates[1].close<previousHigh && rates[1].close<rates[1].open && rsi<53 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio && closeLocation<=0.45 && upperWickRatio>=0.20)'
if (!$ea.Contains($sweepOld)) { throw "V38 cannot find sweep sell condition." }
$ea = $ea.Replace($sweepOld, $sweepNew)

$ea = $ea.Replace('string comment="V35 "+direction+" "+candidate.setup;', 'string comment="V38 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v35_sell_structure route="+activeRoute', '"v38_broad_sell route="+activeRoute')
$ea = $ea.Replace('V35_SELL_STRUCTURE_QUALITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true weak_pullback_buy_pruned=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true', 'V38_BROAD_SELL_OPPORTUNITY_GATE risk_normalized=true max_trades_week=4 min_target_pips=400 h1_aligned_h4_aligned=true directional_geometry=true routes=CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true')

$required = @(
  'V38_BROAD_SELL_OPPORTUNITY_GATE',
  'directional_geometry=true',
  'closeLocation<=0.38',
  'upperWickRatio>=0.20',
  'MaxTradesPerWeek=4',
  'MinTargetPips=400.0',
  'RiskPercent=0.20',
  'CORE_CONTINUATION_SELL_07_08',
  'CORE_SWEEP_SELL_13_14'
)
foreach ($marker in $required) {
  if (!$ea.Contains($marker)) { throw "V38 marker missing: $marker" }
}

$forbidden = @('EDGE_PULLBACK_SELL_15','EDGE_CONTINUATION_BUY_07_08','CORE_PULLBACK_BUY_15','ZLEMA_AUTO','Zlema(')
foreach ($marker in $forbidden) {
  if ($ea.Contains($marker)) { throw "V38 forbidden marker present: $marker" }
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V38 broad-sell opportunity transform applied to $eaPath"
