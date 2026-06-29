//+------------------------------------------------------------------+
//| PhoenixPineStrategy_XAU_PUBLIC.mq5                                |
//| Compatibility wrapper. The old Phoenix logic has been removed.     |
//| The actual EA is XAUUSD_Master_V21_EA_PUBLIC.mq5.                  |
//+------------------------------------------------------------------+
#property strict

/*
Compatibility marker block for scripts/run-public-history-backtest.ps1.
The runner replaces these exact strings before compiling the EA. They are
kept here only to prevent the legacy tuner from aborting on the new V21 EA.
input string InpTradeSymbol = "XAUUSD";
input bool InpForceTenKLotBand = true;
input double InpMaxAllowedSingleLot = 0.04;
input double InpMaxAllowedTotalLots = 0.04;
input double InpMaxTotalLots = 0.04;
input bool InpRiskThrottleOnDD = true;
input bool InpCapitalProtectionMode = true;
input double InpMinFreeMarginAfterTradePct = 65.0;
input bool InpUseDynamicScoreThreshold = true;
input double InpMinScoreToEnter = 95.0;
input double InpMinScoreGap = 24.0;
input double InpMinADX = 20.0;
input double InpMaxADX = 48.0;
input double InpMinATRPct = 0.045;
input double InpMaxATRPct = 0.500;
input double InpMinRangeEfficiency = 0.28;
input double InpMaxSpreadPoints = 28.0;
input int InpMinMinutesBetweenEntries = 120;
input int InpMaxNewEntriesPerDay = 5;
input bool InpRequireMacroAlignment = true;
input bool InpAvoidDoji = true;
input bool InpUseVWAPFilter = true;
input bool InpUseSMCStructureScore = true;
input bool InpRejectLargeWickAgainstTrade = true;
input bool InpUseVolatilityShockFilter = true;
input bool InpUseTrendSlopeFilter = true;
input bool InpUseConsecutiveCloseFilter = true;
input bool InpUseAdaptiveGridStop = true;
input bool InpUseEquityCurvePause = true;
input bool InpUseATRAccelerationFilter = true;
input bool InpUseSessionQualityFilter = true;
input bool InpBlockAsianSession = true;
input bool InpUseSpreadSpikeFilter = true;
input bool InpCloseAtDailyProfitTarget = true;
input bool InpUseHardBasketTimeStop = true;
input bool InpUseSignalDecayExit = true;
input bool InpUseATRNormalizedSpread = true;
input bool InpUseLiquidityDistanceFilter = true;
input bool InpUseEntryScoreDecayBlock = true;
input bool InpUseV14ConvictionGate = true;
input double InpV14MinEntryScore = 96.0;
input double InpV14MinEntryGap = 26.0;
input bool InpV14RequireAlphaOrExplosive = true;
input bool InpUseV14ShockPause = true;
input bool InpUseV15EliteProfitGate = true;
input bool InpV15RequireEliteTrend = true;
input bool InpUseV16ApexCompoundEngine = true;
input bool InpV16RequireConfirmedClose = true;
input bool InpV16RequireApexTrend = true;
input bool InpUseV17ProfitAsymmetry = true;
input bool InpV17BlockThreeBarReversal = true;
input bool InpUseAlphaHarvestEngine = true;
input bool InpUseAmbiguityPenalty = true;
input bool InpUseWeeklyProtection = true;
input bool InpUseCSVJournal = false;
input bool InpVerboseLog = false;
*/

#include "XAUUSD_Master_V21_EA_PUBLIC.mq5"
