//+------------------------------------------------------------------+

//| QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5 |

//| Original MT5 EA for XAUUSD. 10K max-runner with strict lot band.|

//| Not copied from any MQL5 Market product. |

//+------------------------------------------------------------------+

#property strict

#property version "17.00"

#property description "XAUUSD V17 10K ProfitAsymmetry: single version for 10,000 capital, 0.01 base lot, 0.04 total max exposure, no martingale, no classic grid, adaptive elite entries, profit-only pyramiding, bigger runner capture and faster invalidation cuts."

#include <Trade/Trade.mqh>

CTrade trade;

//-------------------- Core --------------------

input string InpTradeSymbol = "XAUUSD";

input ulong InpMagic = 11880517;

input ENUM_TIMEFRAMES InpSignalTF = PERIOD_M15;

input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H1;

input ENUM_TIMEFRAMES InpMacroTF = PERIOD_H4;

input bool InpOneDecisionPerBar = true;

input bool InpRequireHedgingAccount = false;

//-------------------- Money management --------------------

input bool InpUseRiskLot = false;

input double InpFixedLot = 0.01;

input double InpRiskPercent = 0.08;

input double InpCapitalReference = 10000.0;

input bool InpForceTenKLotBand = true;

input double InpMinAllowedLot = 0.01;

input double InpMaxAllowedSingleLot = 0.04;

input double InpMaxAllowedTotalLots = 0.04;

input double InpMaxTotalLots = 0.04;

input double InpRecoveryLotMultiplier = 1.00;

input int InpMaxGridPositions = 1;

input double InpMinEquityForTrading = 100.0;

input bool InpRiskThrottleOnDD = true;

input double InpHalfRiskAtDDPercent = 3.0;

input bool InpCapitalProtectionMode = true;

input double InpDailyProfitTargetPercent = 4.20;

input int InpMaxConsecutiveLossBaskets = 2;

input int InpConsecutiveLossCooldownMin = 1440;

input double InpMinFreeMarginAfterTradePct = 65.0;

input bool InpUseDynamicScoreThreshold = true;

input double InpDDScorePenaltyAtPercent = 3.0;

//-------------------- Grid / basket --------------------

input bool InpUseGrid = false;

input double InpGridStepATR = 2.80;

input double InpGridStepExpansion = 1.45;

input bool InpAddGridOnlyIfTrendValid = true;

input double InpMaxBasketLossBeforeGridPct = 1.50;

input double InpBasketTakeProfitATR = 0.95;

input double InpBasketTPCompression = 0.10;

input double InpEmergencyStopATR = 3.80;

input bool InpCloseBasketOnOpposite = true;

input double InpOppositeScoreToClose = 72.0;

//-------------------- Exit management --------------------

input bool InpUseBreakEven = true;

input double InpBreakEvenStartATR = 0.55;

input double InpBreakEvenLockATR = 0.12;

input bool InpUseTrailing = true;

input double InpTrailStartATR = 1.15;

input double InpTrailDistanceATR = 0.72;

input bool InpUsePartialClose = false;

input double InpPartialCloseAtATR = 0.85;

input double InpPartialClosePercent = 40.0;

input bool InpUseBasketProfitLock = true;

input double InpBasketMinLockProfitPct = 0.55;

input double InpBasketLockRetainPct = 34.0;

input int InpMaxBasketMinutes = 480;

input bool InpCloseStaleBasketIfProfit = true;

input bool InpCloseStaleLossBasket = true;

input int InpMaxLosingBasketMinutes = 360;

input double InpMaxStaleBasketLossPct = 0.65;

//-------------------- Indicators --------------------

input int InpFastEMA = 34;

input int InpSlowEMA = 144;

input int InpMacroEMA = 200;

input int InpSignalEMA = 50;

input int InpRSIPeriod = 14;

input int InpADXPeriod = 14;

input int InpATRPeriod = 14;

input int InpBandsPeriod = 20;

input double InpBandsDeviation = 2.0;

input int InpStructureLookback = 36;

input int InpEfficiencyLookback = 24;

//-------------------- Filters --------------------

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

input double InpMinCandleBodyATR = 0.09;

input bool InpUseVWAPFilter = true;

input bool InpUseSMCStructureScore = true;

input double InpMaxDistanceFromSignalEMA_ATR = 2.65;

input bool InpRejectLargeWickAgainstTrade = true;

input double InpMaxOppositeWickATR = 0.90;

input int InpTradeDirectionMode = 0; // 0 both, 1 buy only, -1 sell only.

//-------------------- V9 quality filters --------------------

input bool InpUseVolatilityShockFilter = true;

input double InpMaxCandleRangeATR = 2.20;

input double InpMaxGapATR = 0.70;

input bool InpUseTrendSlopeFilter = true;

input int InpSlopeLookbackBars = 4;

input double InpMinEMASlopeATR = 0.055;

input bool InpUseConsecutiveCloseFilter = true;

input int InpConfirmBars = 2;

input bool InpUseAdaptiveGridStop = true;

input double InpMaxProjectedBasketLossPct = 1.00;

input double InpBasketCashStopPct = 0.95;

input bool InpUseEquityCurvePause = true;

input double InpSoftDDPausePercent = 3.00;

input int InpSoftDDPauseMinutes = 720;

//-------------------- V9 quality filters --------------------

input bool InpUseATRAccelerationFilter = true;

input int InpATRAccelerationLookback = 12;

input double InpMaxATRAccelerationRatio = 1.65;

input bool InpUseSessionQualityFilter = true;

input bool InpBlockAsianSession = true;

input int InpAsianEndHourServer = 7;

input int InpLondonStartHourServer = 8;

input int InpLondonEndHourServer = 12;

input int InpNYStartHourServer = 13;

input int InpNYEndHourServer = 17;

input bool InpUseSpreadSpikeFilter = true;

input double InpMaxSpreadSpikeMultiplier = 1.85;

input double InpSpreadEmaAlpha = 0.08;

input bool InpCloseAtDailyProfitTarget = true;

input bool InpUseHardBasketTimeStop = true;

input int InpHardMaxBasketMinutes = 720;

input double InpHardTimeStopLossPct = 0.35;

input bool InpUseSignalDecayExit = true;

input double InpWeakSameDirectionScore = 52.0;

input bool InpVerboseDecisionLog = true;

//-------------------- V9 sentinel engine --------------------

input int InpStrategyProfile = 1; // 0 hybrid grid, 1 sniper one-shot, 2 conservative grid.

input bool InpUseDailyEquityTrail = true;

input double InpDailyEquityTrailStartPct = 1.40;

input double InpDailyEquityTrailRetainPct = 55.0;

input bool InpUseBasketTimeProfitExit = true;

input int InpBasketTimeProfitMinutes = 240;

input double InpMinTimedExitProfitPct = 0.03;

input bool InpUseScoreDivergenceExit = true;

input double InpScoreDivergenceCloseGap = 18.0;

input bool InpUseLiquidityDistanceFilter = true;

input double InpMinDistanceFromExtremeATR = 0.22;

input bool InpUseATRNormalizedSpread = true;

input double InpMaxSpreadATRPercent = 8.0;

input bool InpUseEntryScoreDecayBlock = true;

input double InpMinSameDirectionScoreForGrid = 64.0;

input bool InpUseCSVJournal = false;

input string InpCSVJournalName = "QQ_XAU_V17_10K_PROFITASYMMETRY_journal.csv";

//-------------------- V13 high-profit 10K refinements --------------------

input bool InpUseBasketNetBreakEvenLock = true;

input double InpBasketNetBEStartATR = 0.72;

input double InpBasketNetBELockATR = 0.18;

input bool InpUseRunnerScaleOut = true;

input double InpRunnerScaleOutAtATR = 3.20;

input int InpRunnerScaleOutMinPositions = 3;

input bool InpUseRunnerTimeoutOnlyIfWeak = true;

input double InpRunnerTimeoutWeakScoreBuffer = 7.0;

input bool InpUseHighConvictionReentry = true;

input double InpReentryAfterWinScore = 99.0;

input int InpMinMinutesAfterWinReentry = 45;

//-------------------- V14 apex-runner refinements --------------------

input bool InpUseV14ConvictionGate = true;

input double InpV14MinEntryScore = 96.0;

input double InpV14MinEntryGap = 26.0;

input bool InpV14RequireAlphaOrExplosive = true;

input bool InpUseV14ShockPause = true;

input double InpV14ShockCandleRangeATR = 2.40;

input double InpV14ShockGapATR = 0.62;

input double InpV14ShockATRAcceleration = 1.62;

input int InpV14ShockPauseMinutes = 120;

input bool InpUseV14AddQualityGate = true;

input double InpV14MinAddEfficiency = 0.58;

input double InpV14MinAddScoreGap = 28.0;

input bool InpV14NoAddAfterScaleOut = true;

input bool InpUseV14RunnerMFEGuard = true;

input double InpV14RunnerMFEGuardStartPct = 0.90;

input double InpV14RunnerMFERetainPct = 32.0;

input bool InpV14RunnerMFEHoldIfExplosive = true;

//-------------------- V15 elite-profit refinements --------------------

input bool InpUseV15EliteProfitGate = true;

input double InpV15MinEntryScore = 97.0;

input double InpV15MinEntryGap = 28.0;

input double InpV15MinADX = 31.0;

input double InpV15MinEfficiency = 0.52;

input double InpV15MinBodyATR = 0.18;

input double InpV15MinSlopeATR = 0.105;

input double InpV15MaxHealthyATRAcceleration = 1.50;

input double InpV15MaxEMAExtensionATR = 2.65;

input bool InpV15RequireEliteTrend = true;

input bool InpV15UseMomentumScoreBoost = true;

input bool InpV15UseProfitStaircase = true;

input double InpV15StaircaseStartPct = 1.10;

input double InpV15StaircaseRetainPct = 36.0;

input bool InpV15HoldExceptionalRunner = true;

input double InpV15RunnerHoldScore = 99.0;

input double InpV15RunnerHoldADX = 38.0;

input double InpV15RunnerHoldEfficiency = 0.62;

input bool InpV15UseProfitCeilingClose = true;

input double InpV15AbsoluteProfitClosePct = 11.00;

input bool InpV15BlockWeakAddAfterWin = true;

input double InpV15MinAddBasketProfitPct = 0.55;

input double InpV15MinAddDistanceATR = 1.20;

//-------------------- V16 apex-compound profitability refinements --------------------

input bool InpUseV16ApexCompoundEngine = true;

input double InpV16MinEntryScore = 96.8;

input double InpV16MinEntryGap = 27.0;

input double InpV16MinADX = 29.0;

input double InpV16MinEfficiency = 0.50;

input double InpV16MinSlopeATR = 0.095;

input double InpV16MinBodyATR = 0.16;

input double InpV16MaxATRAcceleration = 1.56;

input double InpV16MaxEMAExtensionATR = 2.70;

input double InpV16MinSessionQuality = 1.0;

input bool InpV16RequireConfirmedClose = true;

input bool InpV16RequireApexTrend = true;

input bool InpV16UseScoreBoost = true;

input double InpV16ApexRunnerScore = 99.0;

input double InpV16ApexRunnerADX = 42.0;

input double InpV16ApexRunnerEfficiency = 0.66;

input double InpV16ApexTargetATR = 18.0;

input bool InpV16UseApexHighWaterLock = true;

input double InpV16HighWaterStartPct = 1.25;

input double InpV16HighWaterRetainPct = 36.0;

input double InpV16ApexHoldRetainPct = 24.0;

input bool InpV16UseBadEntryScratch = true;

input int InpV16ScratchMinutes = 30;

input double InpV16ScratchLossATR = 0.32;

input double InpV16ScratchOppositeGap = 8.0;

input bool InpV16UseApexAddGate = true;

input double InpV16MinAddScore = 99.0;

input double InpV16MinAddGap = 32.0;

input double InpV16MinAddBasketPct = 0.55;

input double InpV16MinAddDistanceATR = 1.15;

input int InpV16MaxPositions = 4;

input bool InpV16BlockAddIfProfitRetracing = true;

input double InpV16AddMaxRetracePct = 35.0;

//-------------------- V17 profit-asymmetry refinements --------------------

input bool InpUseV17ProfitAsymmetry = true;

input double InpV17CoreScore = 96.5;

input double InpV17ApexScore = 99.0;

input double InpV17MinGap = 26.0;

input double InpV17MinADX = 28.0;

input double InpV17MinEfficiency = 0.49;

input double InpV17MinSlopeATR = 0.088;

input double InpV17MaxATRAcceleration = 1.58;

input double InpV17MaxEMAExtensionATR = 2.85;

input double InpV17MinBodyATR = 0.14;

input bool InpV17AllowCleanContinuation = true;

input bool InpV17BlockThreeBarReversal = true;

input double InpV17ReversalWickATR = 0.72;

input bool InpV17UseFailedMomentumCut = true;

input int InpV17FailedMoveMinutes = 180;

input double InpV17FailedMoveMinMFE_ATR = 0.42;

input double InpV17FailedMoveLossATR = 0.22;

input bool InpV17UseRunnerProfitElasticity = true;

input double InpV17ElasticLockStartPct = 0.95;

input double InpV17ElasticRetainNormalPct = 44.0;

input double InpV17ElasticRetainApexPct = 26.0;

input double InpV17AbsoluteProfitCeilingPct = 16.0;

input bool InpV17UseProfitReacceleration = true;

input double InpV17ReaccelerationScore = 98.5;

input double InpV17ReaccelerationADX = 36.0;

input double InpV17ReaccelerationEfficiency = 0.58;

input double InpV17AddMinBasketPct = 0.48;

input double InpV17AddMinDistanceATR = 1.05;

//-------------------- V9 max-profit engine --------------------

input bool InpUseProfitExpansion = true;

input bool InpUseRunnerMode = true;

input bool InpUseDynamicTP = true;

input double InpStrongTrendTPATR = 3.10;

input double InpStrongTrendADX = 28.0;

input double InpStrongTrendEfficiency = 0.42;

input double InpStrongTrendScore = 94.0;

input double InpExpansionTriggerATR = 1.55;

input double InpExpansionTrailATR = 1.30;

input bool InpUseAddToWinner = true;

input int InpMaxWinnerAdds = 3;

input double InpWinnerAddStepATR = 1.10;

input double InpWinnerAddLotMultiplier = 1.00;

input double InpMinScoreForWinnerAdd = 98.0;

input int InpMinMinutesBetweenWinnerAdds = 90;

input bool InpRequireProtectedSLForAdd = true;

input bool InpUseProfitTargetExtension = true;

input double InpProfitTargetExtensionScore = 96.0;

input double InpMaxRunnerMinutes = 960;

input bool InpCloseRunnerOnSessionEnd = false;

//-------------------- V10 hyper-profit engine --------------------

input bool InpUseAsymmetricProfitEngine = true;

input bool InpUseFastLoserCut = true;

input int InpFastLoserCutMinutes = 90;

input double InpFastLoserCutATR = 0.82;

input double InpFastLoserMinSameScore = 58.0;

input double InpFastLoserOppositeGap = 10.0;

input bool InpUseHyperRunnerTP = true;

input double InpMegaTrendScore = 97.0;

input double InpMegaTrendADX = 34.0;

input double InpMegaTrendEfficiency = 0.52;

input double InpMegaTrendTPATR = 5.20;

input double InpHyperTrendTPATR = 7.40;

input double InpRunnerStretchStartATR = 2.00;

input double InpRunnerMaxTrailATR = 2.80;

input bool InpUseLockedProfitPyramid = true;

input int InpMaxPyramidAdds = 3;

input double InpPyramidMinBasketProfitPct = 0.42;

input double InpPyramidStepATR = 1.15;

input double InpPyramidLotDecay = 1.00;

input double InpPyramidMinSameScore = 98.0;

input bool InpUseDailyProfitUnlock = true;

input double InpDailyProfitUnlockAtPct = 1.25;

input double InpUnlockedMaxDailyProfitPct = 8.00;

input bool InpUseEquitySnowballLimit = true;

input double InpSnowballRiskBoostAtProfitPct = 1.25;

input double InpSnowballRiskMultiplier = 1.00;

input double InpAbsoluteMaxBasketProfitPct = 15.00;

input bool InpCloseOnRunnerExhaustion = true;

input double InpRunnerExhaustionScoreDrop = 16.0;

//-------------------- V13 alpha-harvest engine --------------------

input bool InpUseAlphaHarvestEngine = true;

input bool InpUseTrendConvictionBonus = true;

input double InpAlphaMinADX = 30.0;

input double InpAlphaMinEfficiency = 0.48;

input double InpAlphaMinSlopeATR = 0.090;

input double InpAlphaMinScoreGap = 22.0;

input bool InpUseExplosiveRunnerTarget = true;

input double InpExplosiveTrendScore = 99.0;

input double InpExplosiveTrendADX = 40.0;

input double InpExplosiveTrendEfficiency = 0.62;

input double InpExplosiveTrendTPATR = 18.00;

input bool InpUseAdaptiveRunnerTrail = true;

input double InpAlphaTrailTightenDrop = 9.0;

input double InpAlphaTrailWidenScore = 98.0;

input double InpAlphaMaxTrailATR = 4.20;

input bool InpUseEarlyBadTradeAbort = true;

input int InpEarlyAbortMinutes = 45;

input double InpEarlyAbortLossATR = 0.48;

input double InpEarlyAbortMaxSameScore = 62.0;

input bool InpUseTrendVault = true;

input double InpTrendVaultStartPct = 3.20;

input double InpTrendVaultRetainPct = 55.0;

input bool InpUsePullbackPyramid = true;

input double InpPullbackPyramidMaxEMA_ATR = 0.85;

input double InpPullbackPyramidMinScore = 98.0;

input bool InpUseProfitOnlyAdds = true;

input double InpMinBasketProfitForAnyAddPct = 0.42;

input bool InpUseAmbiguityPenalty = true;

input double InpAmbiguousBothScoreLevel = 82.0;

input double InpAmbiguityMinGap = 18.0;

input bool InpUseWeeklyProtection = true;

input double InpWeeklyLossStopPct = 3.00;

input double InpWeeklyProfitVaultPct = 7.50;

input double InpWeeklyProfitRetainPct = 48.0;

//-------------------- Account protection --------------------

input double InpMaxDailyLossPercent = 1.20;

input double InpMaxEquityDDPercent = 4.8;

input double InpHardStopEquityDDPercent = 6.8;

input bool InpCloseAllOnHardDD = true;

input int InpCooldownAfterLossMinutes = 720;

input int InpCooldownAfterDDMinutes = 1440;

//-------------------- Sessions --------------------

input int InpStartHourServer = 2;

input int InpEndHourServer = 21;

input bool InpTradeMonday = true;

input bool InpTradeTuesday = true;

input bool InpTradeWednesday = true;

input bool InpTradeThursday = true;

input bool InpTradeFriday = true;

input bool InpBlockFridayLate = true;

input int InpFridayStopHourServer = 16;

input bool InpCloseWeekendRisk = true;

input int InpWeekendFlatHourServer = 15;

// Manual blackout: "2026.06.18 14:00-2026.06.18 15:30;2026.06.19 13:00-2026.06.19 14:00"

input bool InpUseManualNewsBlackout = false;

input string InpNewsBlackoutWindows = "";

//-------------------- Execution / dashboard --------------------

input int InpDeviationPoints = 30;

input bool InpShowDashboard = true;

input bool InpVerboseLog = false;

//-------------------- Handles --------------------

int hFast = INVALID_HANDLE;

int hSlow = INVALID_HANDLE;

int hMacro = INVALID_HANDLE;

int hSignalEMA = INVALID_HANDLE;

int hRSI = INVALID_HANDLE;

int hADX = INVALID_HANDLE;

int hATR = INVALID_HANDLE;

int hBands = INVALID_HANDLE;

//-------------------- State --------------------

datetime g_lastBar = 0;

datetime g_lastEntry = 0;

datetime g_dayStart = 0;

datetime g_weekStart = 0;

datetime g_cooldownUntil = 0;

double g_dayStartEquity = 0.0;

double g_weekStartEquity = 0.0;

double g_weekPeakEquity = 0.0;

double g_dayPeakEquity = 0.0;

double g_peakEquity = 0.0;

double g_basketPeakProfit = 0.0;

int g_entriesToday = 0;

bool g_partialDone = false;

int g_consecutiveLossBaskets = 0;

datetime g_lastBasketClose = 0;

bool g_lastBasketWasProfit = false;

datetime g_lastWinnerAdd = 0;

datetime g_v14ShockPauseUntil = 0;

double g_runnerBestScore = 0.0;

double g_runnerBestDistanceATR = 0.0;

double g_v17BasketMFEATR = 0.0;

double g_spreadEma = 0.0;

datetime g_lastDecisionLog = 0;

string g_status = "INIT";

//-------------------- Types --------------------

struct SignalPack

{

int direction;

double buyScore;

double sellScore;

double atr;

double adx;

double atrPct;

double efficiency;

double vwap;

double distanceFromSignalEMAATR;

double bodyATR;

double candleRangeATR;

double gapATR;

double emaSlopeATR;

double atrAcceleration;

int sessionQuality;

bool buyConfirmed;

bool sellConfirmed;

double oppositeWickATRBuy;

double oppositeWickATRSell;

double distanceToRecentHighATR;

double distanceToRecentLowATR;

double scoreGap;

string regime;

string reason;

};

//-------------------- Forward declarations --------------------

void ResetWeekIfNeeded();

double WeeklyLossPct();

double WeeklyProfitPct();

double WeeklyPeakProfitPct();

//-------------------- Helpers --------------------

bool SymbolOK()

{

return (_Symbol == InpTradeSymbol || StringFind(_Symbol, InpTradeSymbol) >= 0);

}

double Ask()

{

return SymbolInfoDouble(_Symbol, SYMBOL_ASK);

}

double Bid()

{

return SymbolInfoDouble(_Symbol, SYMBOL_BID);

}

double SpreadPts()

{

double ask = Ask();

double bid = Bid();

if(ask <= 0 || bid <= 0 || _Point <= 0) return 999999.0;

return (ask - bid) / _Point;

}

double NormPrice(const double p)

{

return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

}

double NormalizeLot(double lot)

{

double minLot = SymbolInfo
