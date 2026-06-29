//+------------------------------------------------------------------+
//| PhoenixPineStrategy_XAU_PUBLIC.mq5                                |
//| Pine-to-MT5 public backtest strategy for XAU_PUBLIC                |
//| Converts the available Phoenix B-Bands + WaveTrend rules into EA.  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Phoenix Pine strategy conversion: red 3.618 band touches + normalized WT extremes for public MT5 backtests."

#include <Trade/Trade.mqh>
CTrade trade;

input string          InpTradeSymbol              = "XAU_PUBLIC";
input ulong           InpMagic                    = 26062901;
input ENUM_TIMEFRAMES InpSignalTF                 = PERIOD_M15;
input double          InpFixedLot                 = 0.01;
input int             InpBandPeriod               = 20;
input double          InpRedBandDeviation         = 3.618;
input int             InpWTChannelLength          = 10;
input int             InpWTAverageLength          = 21;
input int             InpWTSmoothLength           = 4;
input int             InpWTNormalizeLookback      = 100;
input double          InpWTBuyExtreme             = 5.0;
input double          InpWTSellExtreme            = 95.0;
input bool            InpAllowWTCrossFallback     = true;
input double          InpTargetPricePoints        = 20.0;
input double          InpStopPricePoints          = 20.0;
input bool            InpCloseOnOppositeSignal    = true;
input int             InpMinMinutesBetweenEntries = 30;
input int             InpMaxNewEntriesPerDay      = 4;
input bool            InpLondonSession            = true;
input bool            InpNewYorkSession           = true;
input int             InpLondonStartHour          = 8;
input int             InpLondonEndHour            = 12;
input int             InpNYStartHour              = 13;
input int             InpNYEndHour                = 15;
input bool            InpUseCSVJournal            = true;
input string          InpCSVJournalName           = "QQ_PUBLIC_journal.csv";

// Compatibility marker block for the existing public GitHub runner tuning step.
/*
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

datetime g_lastBarTime = 0;
datetime g_lastEntryTime = 0;
datetime g_dayAnchor = 0;
int      g_entriesToday = 0;

string DirText(const int dir)
{
   if(dir > 0) return "BUY";
   if(dir < 0) return "SELL";
   return "NONE";
}

double BidPrice()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid > 0.0) return bid;
   return iClose(_Symbol, InpSignalTF, 0);
}

double AskPrice()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask > 0.0) return ask;
   return iClose(_Symbol, InpSignalTF, 0);
}

void JournalEvent(const string eventName, const string details)
{
   if(!InpUseCSVJournal) return;
   int handle = FileOpen(InpCSVJournalName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ';');
   if(handle == INVALID_HANDLE) return;
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), _Symbol, eventName, details);
   FileClose(handle);
}

void ResetDailyCountersIfNeeded()
{
   MqlDateTime nowStruct, dayStruct;
   TimeToStruct(TimeCurrent(), nowStruct);
   if(g_dayAnchor > 0) TimeToStruct(g_dayAnchor, dayStruct);
   if(g_dayAnchor == 0 || nowStruct.year != dayStruct.year || nowStruct.mon != dayStruct.mon || nowStruct.day != dayStruct.day)
   {
      g_dayAnchor = TimeCurrent();
      g_entriesToday = 0;
   }
}

bool SessionOK()
{
   datetime barTime = iTime(_Symbol, InpSignalTF, 1);
   if(barTime <= 0) barTime = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(barTime, t);
   if(t.day_of_week == 0 || t.day_of_week == 6) return false;
   bool london = InpLondonSession && t.hour >= InpLondonStartHour && t.hour < InpLondonEndHour;
   bool ny = InpNewYorkSession && t.hour >= InpNYStartHour && t.hour < InpNYEndHour;
   return (london || ny);
}

bool NewBar()
{
   datetime t = iTime(_Symbol, InpSignalTF, 0);
   if(t <= 0) return false;
   if(t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

void BuildEMA(const double &src[], double &out[], const int total, const int period)
{
   ArrayResize(out, total);
   if(total <= 0) return;
   double alpha = 2.0 / (period + 1.0);
   out[0] = src[0];
   for(int i = 1; i < total; i++)
      out[i] = alpha * src[i] + (1.0 - alpha) * out[i - 1];
}

double NormAt(const double &raw[], const int idx, const int lookback)
{
   if(idx < 0) return 50.0;
   int start = MathMax(0, idx - lookback + 1);
   double lo = raw[start];
   double hi = raw[start];
   for(int i = start; i <= idx; i++)
   {
      lo = MathMin(lo, raw[i]);
      hi = MathMax(hi, raw[i]);
   }
   if(hi - lo <= 0.0000001) return 50.0;
   return 100.0 * (raw[idx] - lo) / (hi - lo);
}

bool ComputeBands(const int shift, double &basis, double &upperRed, double &lowerRed)
{
   if(iBars(_Symbol, InpSignalTF) < InpBandPeriod + shift + 2) return false;
   double sum = 0.0;
   for(int i = 0; i < InpBandPeriod; i++)
      sum += iClose(_Symbol, InpSignalTF, shift + i);
   basis = sum / InpBandPeriod;

   double variance = 0.0;
   for(int i = 0; i < InpBandPeriod; i++)
   {
      double d = iClose(_Symbol, InpSignalTF, shift + i) - basis;
      variance += d * d;
   }
   double stdev = MathSqrt(variance / InpBandPeriod);
   upperRed = basis + InpRedBandDeviation * stdev;
   lowerRed = basis - InpRedBandDeviation * stdev;
   return true;
}

bool ComputeWT(double &wt1, double &wt2, double &wt1Prev, double &wt2Prev)
{
   int need = MathMax(160, InpWTNormalizeLookback + InpWTChannelLength + InpWTAverageLength + InpWTSmoothLength + 20);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpSignalTF, 0, need, rates);
   if(copied < 80) return false;

   int total = copied;
   double ap[], esa[], absDev[], d[], ci[], wtRaw[];
   ArrayResize(ap, total);
   ArrayResize(absDev, total);
   ArrayResize(ci, total);

   for(int i = 0; i < total; i++)
   {
      int r = total - 1 - i;
      ap[i] = (rates[r].high + rates[r].low + rates[r].close) / 3.0;
   }

   BuildEMA(ap, esa, total, InpWTChannelLength);
   for(int i = 0; i < total; i++) absDev[i] = MathAbs(ap[i] - esa[i]);
   BuildEMA(absDev, d, total, InpWTChannelLength);
   for(int i = 0; i < total; i++) ci[i] = (d[i] > 0.0000001 ? (ap[i] - esa[i]) / (0.015 * d[i]) : 0.0);
   BuildEMA(ci, wtRaw, total, InpWTAverageLength);

   int idx = total - 2;
   if(idx < InpWTSmoothLength + 2) return false;
   wt1 = NormAt(wtRaw, idx, InpWTNormalizeLookback);
   wt1Prev = NormAt(wtRaw, idx - 1, InpWTNormalizeLookback);

   wt2 = 0.0;
   wt2Prev = 0.0;
   for(int k = 0; k < InpWTSmoothLength; k++)
   {
      wt2 += NormAt(wtRaw, idx - k, InpWTNormalizeLookback);
      wt2Prev += NormAt(wtRaw, idx - 1 - k, InpWTNormalizeLookback);
   }
   wt2 /= InpWTSmoothLength;
   wt2Prev /= InpWTSmoothLength;
   return true;
}

int CountPositions(const int dir = 0)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir == 1 && type != POSITION_TYPE_BUY) continue;
      if(dir == -1 && type != POSITION_TYPE_SELL) continue;
      count++;
   }
   return count;
}

int BasketDirection()
{
   int buys = CountPositions(1);
   int sells = CountPositions(-1);
   if(buys > sells) return 1;
   if(sells > buys) return -1;
   return 0;
}

double WeightedEntry(const int dir)
{
   double pv = 0.0;
   double lots = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(dir == 1 && type != POSITION_TYPE_BUY) continue;
      if(dir == -1 && type != POSITION_TYPE_SELL) continue;
      double lot = PositionGetDouble(POSITION_VOLUME);
      pv += PositionGetDouble(POSITION_PRICE_OPEN) * lot;
      lots += lot;
   }
   if(lots <= 0.0) return 0.0;
   return pv / lots;
}

bool CloseAll(const string reason)
{
   bool ok = true;
   int before = CountPositions();
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      profit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(!trade.PositionClose(ticket)) ok = false;
   }
   JournalEvent(reason, StringFormat("positions=%d profit=%.2f ok=%s", before, profit, ok ? "true" : "false"));
   return ok;
}

bool GetSignal(int &dir, string &details)
{
   dir = 0;
   details = "";
   double basis, upperRed, lowerRed;
   if(!ComputeBands(1, basis, upperRed, lowerRed)) return false;

   double wt1, wt2, wt1Prev, wt2Prev;
   if(!ComputeWT(wt1, wt2, wt1Prev, wt2Prev)) return false;

   double high1 = iHigh(_Symbol, InpSignalTF, 1);
   double low1 = iLow(_Symbol, InpSignalTF, 1);
   double close1 = iClose(_Symbol, InpSignalTF, 1);

   bool lowerTouch = (low1 <= lowerRed);
   bool upperTouch = (high1 >= upperRed);
   bool buyExtreme = (wt1 <= InpWTBuyExtreme);
   bool sellExtreme = (wt1 >= InpWTSellExtreme);
   bool buyCross = InpAllowWTCrossFallback && wt1 > wt2 && wt1Prev <= wt2Prev && wt1 < 35.0;
   bool sellCross = InpAllowWTCrossFallback && wt1 < wt2 && wt1Prev >= wt2Prev && wt1 > 65.0;

   details = StringFormat("basis=%.3f upper=%.3f lower=%.3f h=%.3f l=%.3f c=%.3f wt1=%.1f wt2=%.1f wt1prev=%.1f wt2prev=%.1f",
                          basis, upperRed, lowerRed, high1, low1, close1, wt1, wt2, wt1Prev, wt2Prev);

   if(lowerTouch && (buyExtreme || buyCross))
   {
      dir = 1;
      return true;
   }
   if(upperTouch && (sellExtreme || sellCross))
   {
      dir = -1;
      return true;
   }
   return true;
}

void ManagePosition()
{
   int dir = BasketDirection();
   if(dir == 0) return;
   double entry = WeightedEntry(dir);
   if(entry <= 0.0) return;
   double dist = (dir == 1 ? BidPrice() - entry : entry - AskPrice());
   if(dist >= InpTargetPricePoints)
   {
      CloseAll("PUBLIC_20_POINT_PROFIT_EXIT");
      return;
   }
   if(dist <= -InpStopPricePoints)
   {
      CloseAll("PUBLIC_HARD_CUT");
      return;
   }
}

void TryOpen(const int dir, const string details)
{
   if(dir == 0) return;
   ResetDailyCountersIfNeeded();
   if(g_entriesToday >= InpMaxNewEntriesPerDay)
   {
      JournalEvent("DAILY_ENTRY_LIMIT", details);
      return;
   }
   if(g_lastEntryTime > 0 && (TimeCurrent() - g_lastEntryTime) < InpMinMinutesBetweenEntries * 60)
   {
      JournalEvent("WAIT_BETWEEN_ENTRIES", details);
      return;
   }
   if(!SessionOK())
   {
      JournalEvent("SESSION_BLOCK", details);
      return;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(80);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir == 1) ok = trade.Buy(InpFixedLot, _Symbol, 0.0, 0.0, 0.0, "PHOENIX_BUY");
   if(dir == -1) ok = trade.Sell(InpFixedLot, _Symbol, 0.0, 0.0, 0.0, "PHOENIX_SELL");

   if(ok)
   {
      g_entriesToday++;
      g_lastEntryTime = TimeCurrent();
      JournalEvent("OPEN_ENTRY", DirText(dir) + " lot=" + DoubleToString(InpFixedLot, 2) + " " + details);
   }
   else
   {
      JournalEvent("ORDER_FAIL", DirText(dir) + " retcode=" + IntegerToString((int)trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription() + " " + details);
   }
}

int OnInit()
{
   if(InpUseCSVJournal) FileDelete(InpCSVJournalName, FILE_COMMON);
   trade.SetExpertMagicNumber(InpMagic);
   JournalEvent("INIT", "Phoenix Pine strategy conversion loaded");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(InpTradeSymbol != "" && _Symbol != InpTradeSymbol) return;
   ManagePosition();
   if(!NewBar()) return;

   int signalDir = 0;
   string details = "";
   if(!GetSignal(signalDir, details))
   {
      JournalEvent("NO_SIGNAL_DATA", "insufficient data");
      return;
   }

   int openDir = BasketDirection();
   if(openDir != 0)
   {
      if(InpCloseOnOppositeSignal && signalDir != 0 && signalDir != openDir)
         CloseAll("OPPOSITE_SIGNAL_CLOSE");
      return;
   }

   if(signalDir == 0)
   {
      JournalEvent("NO_SIGNAL", details);
      return;
   }
   TryOpen(signalDir, details);
}
