$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$eaPath = "MQL5/Experts/XAUUSD_V27_Clean_MultiSetup.mq5"
if (!(Test-Path $eaPath)) { throw "EA source missing: $eaPath" }

$ea = Get-Content $eaPath -Raw

$ea = $ea.Replace('#property version "2.90"', '#property version "2.91"')
$ea = $ea.Replace('V30 Symmetric Opportunity Expansion: fresh cross-period validation', 'V32 Pruned Core Quality Gate: EDGE routes removed')
$ea = $ea.Replace('input string CSVJournalName="V30_SYMMETRIC_journal.csv";', 'input string CSVJournalName="V32_PRUNED_CORE_journal.csv";')

$edgeRouteBlock = @'

   if(setup=="PULLBACK" && dir<0 && hour==15)
   {
      name="EDGE_PULLBACK_SELL_15";
      return true;
   }
   if(setup=="CONTINUATION" && dir>0 && hour>=7 && hour<9)
   {
      name="EDGE_CONTINUATION_BUY_07_08";
      return true;
   }
'@
$ea = $ea.Replace($edgeRouteBlock, "`n")

$edgeQualityBlock = @'
bool EdgeQuality(string route,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(route=="EDGE_PULLBACK_SELL_15")
      return h1Bias<0 && h4Bias<0 && rsi>=36 && rsi<=48 && adx>=22 && volumeRatio>=1.05 && bodyRatio>=0.40;

   if(route=="EDGE_CONTINUATION_BUY_07_08")
      return h1Bias>0 && h4Bias>0 && rsi>=53 && rsi<=64 && adx>=22 && volumeRatio>=1.05 && bodyRatio>=0.40;

   return true;
}
'@
$edgeQualityReplacement = @'
bool EdgeQuality(string route,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   return true;
}
'@
$ea = $ea.Replace($edgeQualityBlock, $edgeQualityReplacement)

$ea = $ea.Replace('string comment="V30 "+direction+" "+candidate.setup;', 'string comment="V32 "+direction+" "+candidate.setup;')
$ea = $ea.Replace('"v30_symmetric route="+activeRoute', '"v32_pruned_core route="+activeRoute')
$ea = $ea.Replace('V30_SYMMETRIC_OPPORTUNITY_EXPANSION risk_normalized=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14|EDGE_PULLBACK_SELL_15|EDGE_CONTINUATION_BUY_07_08', 'V32_PRUNED_CORE_QUALITY_GATE risk_normalized=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14 edge_routes_pruned=true')

if ($ea.Contains('EDGE_PULLBACK_SELL_15') -or $ea.Contains('EDGE_CONTINUATION_BUY_07_08')) {
  throw "V32 pruning failed: EDGE route marker still present in EA source."
}
if (!$ea.Contains('V32_PRUNED_CORE_QUALITY_GATE')) {
  throw "V32 identity marker missing after transform."
}
if (!$ea.Contains('RiskPercent=0.20')) {
  throw "Risk marker missing after transform."
}

Set-Content -Path $eaPath -Value $ea -Encoding UTF8
Write-Host "V32 edge pruning transform applied to $eaPath"