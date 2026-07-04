//+------------------------------------------------------------------+
//| XAUUSD_V27_Clean_MultiSetup.mq5                                  |
//| Natural multi-setup XAUUSD intraday EA                            |
//| No forced trades. No arbitrary daily close.                       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.70"
#property description "V27 Clean Multi-Setup: natural breakout, pullback, continuation and sweep entries"

#include <Trade/Trade.mqh>

CTrade trade;

input string InpTradeSymbol = "";
input double FixedLot = 0.02;
input int MaxTradesPerDay = 4;
input int CooldownMinutes = 45;
input ulong MagicNumber = 270100;
input int SlippagePoints = 120;
input int BrokerStopBufferPoints = 40;

input bool UseSession = true;
input int SessionStartHour = 7;
input int SessionEndHour = 20;
input bool BlockFridayLateEntries = true;
input int FridayLastEntryHour = 17;
input bool CloseBeforeWeekend = true;
input int FridayCloseHour = 19;

input bool EnableBuy = true;
input bool EnableSell = true;
input double MinSignalScore = 72.0;
input double MinDirectionScoreGap = 6.0;
input double MinADX = 16.0;
input double MaxSpreadATRFraction = 0.10;

input int FastLen = 9;
input int SlowLen = 21;
input int TrendLen = 200;
input int BiasFastLen = 50;
input int BiasSlowLen = 200;
input int RsiLen = 14;
input int AtrLen = 14;
input int AdxLen = 14;
input int VolLen = 20;

input int BreakoutLookback = 5;
input int SweepLookback = 5;
input double PullbackTouchATR = 0.28;
input double MinBodyRatio = 0.25;
input double MinVolumeRatio = 0.80;

input double BreakoutTP_ATR = 1.25;
input double BreakoutSL_ATR = 1.35;
input double PullbackTP_ATR = 1.10;
input double PullbackSL_ATR = 1.25;
input double ContinuationTP_ATR = 1.00;
input double ContinuationSL_ATR = 1.30;
input double SweepTP_ATR = 1.30;
input double SweepSL_ATR = 1.20;

input bool UseBreakEven = true;
input double BreakEvenTriggerATR = 0.65;
input double BreakEvenOffsetATR = 0.05;
input bool UseTrailingStop = true;
input double TrailStartATR = 1.00;
input double TrailDistanceATR = 0.75;
input int MaxHoldBars = 20;
input double TimeExitMinProgressATR = 0.10;

input bool UseCSVJournal = true;
input string CSVJournalName = "V27_CLEAN_journal.csv";

string Sym;
int tradesToday = 0;
int currentYear = -1;
int currentDayOfYear = -1;
datetime lastEntryTime = 0;
datetime lastExecutionBarTime = 0;
double activeEntryATR = 0.0;
string activeSetup = "";
double activeScore = 0.0;

int m15FastHandle = INVALID_HANDLE;
int m15SlowHandle = INVALID_HANDLE;
int m15TrendHandle = INVALID_HANDLE;
int m15RsiHandle = INVALID_HANDLE;
int m15AtrHandle = INVALID_HANDLE;
int m15AdxHandle = INVALID_HANDLE;

int h1FastHandle = INVALID_HANDLE;
int h1SlowHandle = INVALID_HANDLE;
int h1RsiHandle = INVALID_HANDLE;

int h4FastHandle = INVALID_HANDLE;
int h4SlowHandle = INVALID_HANDLE;
int h4RsiHandle = INVALID_HANDLE;

struct SignalCandidate
{
   int direction;
   string setup;
   double score;
   double atr;
};

void ResetCandidate(SignalCandidate &candidate)
{
   candidate.direction = 0;
   candidate.setup = "";
   candidate.score = 0.0;
   candidate.atr = 0.0;
}

bool CopyOne(const int handle, const int bufferIndex, const int shift, double &value)
{
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(handle, bufferIndex, shift, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return MathIsValidNumber(value);
}

bool CopyRatesData(const ENUM_TIMEFRAMES timeframe, const int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   return CopyRates(Sym, timeframe, 0, count, rates) >= count;
}

double VolumeSMA(MqlRates &rates[], const int startShift, const int length)
{
   double sum = 0.0;
   for(int i = startShift; i < startShift + length; i++)
      sum += (double)rates[i].tick_volume;
   return sum / (double)length;
}

double HighestHigh(MqlRates &rates[], const int startShift, const int length)
{
   double value = rates[startShift].high;
   for(int i = startShift + 1; i < startShift + length; i++)
      value = MathMax(value, rates[i].high);
   return value;
}

double LowestLow(MqlRates &rates[], const int startShift, const int length)
{
   double value = rates[startShift].low;
   for(int i = startShift + 1; i < startShift + length; i++)
      value = MathMin(value, rates[i].low);
   return value;
}

void Journal(const string eventName,
             const string direction,
             const string setup,
             const double score,
             const double price,
             const double atrValue,
             const string details)
{
   if(!UseCSVJournal)
      return;

   int handle = FileOpen(CSVJournalName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
   if(handle == INVALID_HANDLE)
      return;

   if(FileSize(handle) == 0)
      FileWrite(handle, "time", "event", "direction", "setup", "score", "price", "atr", "details");

   FileSeek(handle, 0, SEEK_END);
   FileWrite(
      handle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      eventName,
      direction,
      setup,
      DoubleToString(score, 2),
      DoubleToString(price, 3),
      DoubleToString(atrValue, 5),
      details
   );
   FileClose(handle);
}

void ResetDailyCounterIfNeeded()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.year != currentYear || now.day_of_year != currentDayOfYear)
   {
      currentYear = now.year;
      currentDayOfYear = now.day_of_year;
      tradesToday = 0;
   }
}

bool IsEntrySessionOpen()
{
   if(!UseSession)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.day_of_week == 0 || now.day_of_week == 6)
      return false;
   if(now.hour < SessionStartHour || now.hour >= SessionEndHour)
      return false;
   if(BlockFridayLateEntries && now.day_of_week == 5 && now.hour >= FridayLastEntryHour)
      return false;
   return true;
}

bool IsNewExecutionBar()
{
   MqlRates rates[];
   if(!CopyRatesData(PERIOD_M15, 3, rates))
      return false;

   if(rates[1].time == lastExecutionBarTime)
      return false;

   lastExecutionBarTime = rates[1].time;
   return true;
}

bool FindManagedPosition(ulong &ticket)
{
   ticket = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong candidate = PositionGetTicket(i);
      if(candidate == 0 || !PositionSelectByTicket(candidate))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != Sym)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ticket = candidate;
      return true;
   }
   return false;
}

int BiasState(const ENUM_TIMEFRAMES timeframe)
{
   int fastHandle = timeframe == PERIOD_H1 ? h1FastHandle : h4FastHandle;
   int slowHandle = timeframe == PERIOD_H1 ? h1SlowHandle : h4SlowHandle;
   int rsiHandle = timeframe == PERIOD_H1 ? h1RsiHandle : h4RsiHandle;

   MqlRates rates[];
   if(!CopyRatesData(timeframe, 4, rates))
      return 0;

   double fast = 0.0;
   double slow = 0.0;
   double rsi = 50.0;
   if(!CopyOne(fastHandle, 0, 1, fast) ||
      !CopyOne(slowHandle, 0, 1, slow) ||
      !CopyOne(rsiHandle, 0, 1, rsi))
      return 0;

   bool bullish = rates[1].close > slow && fast > slow && rsi >= 52.0;
   bool bearish = rates[1].close < slow && fast < slow && rsi <= 48.0;

   if(bullish)
      return 1;
   if(bearish)
      return -1;
   return 0;
}

double TickSize()
{
   double tickSize = SymbolInfoDouble(Sym, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(Sym, SYMBOL_POINT);
   if(tickSize <= 0.0)
      tickSize = point;
   if(tickSize <= 0.0)
      tickSize = 0.001;
   return tickSize;
}

double NormalizePrice(const double price)
{
   int digits = (int)SymbolInfoInteger(Sym, SYMBOL_DIGITS);
   double tickSize = TickSize();
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

double NormalizeVolume(const double lot)
{
   double minLot = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(Sym, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;
   if(lot < minLot || lot > maxLot)
      return 0.0;

   double steps = MathRound((lot - minLot) / step);
   double normalized = minLot + steps * step;
   if(MathAbs(normalized - lot) > 0.0000001)
      return 0.0;

   return NormalizeDouble(normalized, 2);
}

double MinimumStopDistance()
{
   double point = SymbolInfoDouble(Sym, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.001;

   int stopLevel = (int)SymbolInfoInteger(Sym, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(Sym, SYMBOL_TRADE_FREEZE_LEVEL);
   int minPoints = (int)MathMax(stopLevel, freezeLevel) + BrokerStopBufferPoints;

   return MathMax((double)minPoints * point, 2.0 * TickSize());
}

void SetupMultipliers(const string setup, double &tpMultiplier, double &slMultiplier)
{
   tpMultiplier = ContinuationTP_ATR;
   slMultiplier = ContinuationSL_ATR;

   if(setup == "BREAKOUT")
   {
      tpMultiplier = BreakoutTP_ATR;
      slMultiplier = BreakoutSL_ATR;
   }
   else if(setup == "PULLBACK")
   {
      tpMultiplier = PullbackTP_ATR;
      slMultiplier = PullbackSL_ATR;
   }
   else if(setup == "SWEEP")
   {
      tpMultiplier = SweepTP_ATR;
      slMultiplier = SweepSL_ATR;
   }
}

bool BuildStops(const int direction,
                const double entryPrice,
                const double atrValue,
                const string setup,
                double &sl,
                double &tp)
{
   if(atrValue <= 0.0)
      return false;

   double tpMultiplier = 1.0;
   double slMultiplier = 1.0;
   SetupMultipliers(setup, tpMultiplier, slMultiplier);

   double minDistance = MinimumStopDistance();
   double tpDistance = MathMax(atrValue * tpMultiplier, minDistance);
   double slDistance = MathMax(atrValue * slMultiplier, minDistance);

   if(direction > 0)
   {
      sl = NormalizePrice(entryPrice - slDistance);
      tp = NormalizePrice(entryPrice + tpDistance);
      return sl < entryPrice && tp > entryPrice;
   }

   sl = NormalizePrice(entryPrice + slDistance);
   tp = NormalizePrice(entryPrice - tpDistance);
   return sl > entryPrice && tp < entryPrice;
}

double CommonScore(const bool buy,
                   MqlRates &rates[],
                   const double fast1,
                   const double slow1,
                   const double trend1,
                   const double rsi1,
                   const double adx1,
                   const double atr1,
                   const double volumeRatio,
                   const double bodyRatio,
                   const int h1Bias,
                   const int h4Bias)
{
   bool localTrend = buy
      ? rates[1].close > trend1 && fast1 > slow1
      : rates[1].close < trend1 && fast1 < slow1;

   if(!localTrend)
      return -1000.0;

   if((buy && h1Bias < 0) || (!buy && h1Bias > 0))
      return -1000.0;

   MqlTick tick;
   if(!SymbolInfoTick(Sym, tick))
      return -1000.0;

   double spread = MathMax(0.0, tick.ask - tick.bid);
   if(atr1 <= 0.0 || spread > atr1 * MaxSpreadATRFraction)
      return -1000.0;

   double score = 20.0;

   if((buy && h1Bias > 0) || (!buy && h1Bias < 0))
      score += 20.0;
   else
      score += 7.0;

   if((buy && h4Bias > 0) || (!buy && h4Bias < 0))
      score += 10.0;
   else if(h4Bias == 0)
      score += 4.0;
   else
      score -= 8.0;

   if(buy)
   {
      if(rsi1 >= 52.0 && rsi1 <= 66.0)
         score += 10.0;
      else if(rsi1 > 48.0 && rsi1 < 72.0)
         score += 5.0;
   }
   else
   {
      if(rsi1 >= 34.0 && rsi1 <= 48.0)
         score += 10.0;
      else if(rsi1 > 28.0 && rsi1 < 52.0)
         score += 5.0;
   }

   if(adx1 >= 25.0)
      score += 10.0;
   else if(adx1 >= MinADX)
      score += 7.0;

   if(volumeRatio >= 1.10)
      score += 10.0;
   else if(volumeRatio >= MinVolumeRatio)
      score += 6.0;

   if(bodyRatio >= 0.55)
      score += 8.0;
   else if(bodyRatio >= MinBodyRatio)
      score += 4.0;

   return score;
}

void ConsiderCandidate(const int direction,
                       const string setup,
                       const double score,
                       const double atrValue,
                       SignalCandidate &candidate)
{
   if(score < MinSignalScore)
      return;

   if(candidate.direction == 0 || score > candidate.score)
   {
      candidate.direction = direction;
      candidate.setup = setup;
      candidate.score = score;
      candidate.atr = atrValue;
   }
}

bool EvaluateSignals(SignalCandidate &best)
{
   ResetCandidate(best);

   int requiredBars = (int)MathMax(VolLen + 10, MathMax(BreakoutLookback + 10, SweepLookback + 10));
   MqlRates rates[];
   if(!CopyRatesData(PERIOD_M15, requiredBars, rates))
      return false;

   double fast1 = 0.0;
   double fast2 = 0.0;
   double slow1 = 0.0;
   double trend1 = 0.0;
   double rsi1 = 50.0;
   double atr1 = 0.0;
   double adx1 = 0.0;

   if(!CopyOne(m15FastHandle, 0, 1, fast1) ||
      !CopyOne(m15FastHandle, 0, 2, fast2) ||
      !CopyOne(m15SlowHandle, 0, 1, slow1) ||
      !CopyOne(m15TrendHandle, 0, 1, trend1) ||
      !CopyOne(m15RsiHandle, 0, 1, rsi1) ||
      !CopyOne(m15AtrHandle, 0, 1, atr1) ||
      !CopyOne(m15AdxHandle, 0, 1, adx1))
      return false;

   if(atr1 <= 0.0)
      return false;

   double range = rates[1].high - rates[1].low;
   if(range <= 0.0)
      return false;

   double bodyRatio = MathAbs(rates[1].close - rates[1].open) / range;
   double volumeSma = VolumeSMA(rates, 2, VolLen);
   double volumeRatio = volumeSma > 0.0 ? (double)rates[1].tick_volume / volumeSma : 0.0;
   int h1Bias = BiasState(PERIOD_H1);
   int h4Bias = BiasState(PERIOD_H4);

   SignalCandidate buyCandidate;
   SignalCandidate sellCandidate;
   ResetCandidate(buyCandidate);
   ResetCandidate(sellCandidate);

   double buyBase = CommonScore(true, rates, fast1, slow1, trend1, rsi1, adx1, atr1, volumeRatio, bodyRatio, h1Bias, h4Bias);
   double sellBase = CommonScore(false, rates, fast1, slow1, trend1, rsi1, adx1, atr1, volumeRatio, bodyRatio, h1Bias, h4Bias);

   if(EnableBuy && buyBase > 0.0)
   {
      double previousHigh = HighestHigh(rates, 2, BreakoutLookback);
      double previousLow = LowestLow(rates, 2, SweepLookback);

      bool breakout = rates[1].close > previousHigh &&
                      rates[1].close > rates[1].open &&
                      bodyRatio >= 0.30 &&
                      volumeRatio >= 0.90;
      if(breakout)
         ConsiderCandidate(1, "BREAKOUT", buyBase + 24.0, atr1, buyCandidate);

      bool pullbackTouched = rates[1].low <= slow1 + atr1 * PullbackTouchATR ||
                             rates[2].low <= slow1 + atr1 * PullbackTouchATR;
      bool pullback = pullbackTouched &&
                      rates[1].close > fast1 &&
                      rates[1].close > rates[1].open &&
                      rsi1 > 49.0 &&
                      rsi1 < 69.0;
      if(pullback)
         ConsiderCandidate(1, "PULLBACK", buyBase + 22.0, atr1, buyCandidate);

      bool continuation = rates[1].close > rates[2].high &&
                          rates[2].close > rates[2].open &&
                          fast1 > fast2 &&
                          bodyRatio >= 0.35 &&
                          volumeRatio >= MinVolumeRatio;
      if(continuation)
         ConsiderCandidate(1, "CONTINUATION", buyBase + 18.0, atr1, buyCandidate);

      bool sweep = h1Bias > 0 &&
                   rates[1].low < previousLow &&
                   rates[1].close > previousLow &&
                   rates[1].close > rates[1].open &&
                   rsi1 > 45.0;
      if(sweep)
         ConsiderCandidate(1, "SWEEP", buyBase + 23.0, atr1, buyCandidate);
   }

   if(EnableSell && sellBase > 0.0)
   {
      double previousLow = LowestLow(rates, 2, BreakoutLookback);
      double previousHigh = HighestHigh(rates, 2, SweepLookback);

      bool breakout = rates[1].close < previousLow &&
                      rates[1].close < rates[1].open &&
                      bodyRatio >= 0.30 &&
                      volumeRatio >= 0.90;
      if(breakout)
         ConsiderCandidate(-1, "BREAKOUT", sellBase + 24.0, atr1, sellCandidate);

      bool pullbackTouched = rates[1].high >= slow1 - atr1 * PullbackTouchATR ||
                             rates[2].high >= slow1 - atr1 * PullbackTouchATR;
      bool pullback = pullbackTouched &&
                      rates[1].close < fast1 &&
                      rates[1].close < rates[1].open &&
                      rsi1 > 31.0 &&
                      rsi1 < 51.0;
      if(pullback)
         ConsiderCandidate(-1, "PULLBACK", sellBase + 22.0, atr1, sellCandidate);

      bool continuation = rates[1].close < rates[2].low &&
                          rates[2].close < rates[2].open &&
                          fast1 < fast2 &&
                          bodyRatio >= 0.35 &&
                          volumeRatio >= MinVolumeRatio;
      if(continuation)
         ConsiderCandidate(-1, "CONTINUATION", sellBase + 18.0, atr1, sellCandidate);

      bool sweep = h1Bias < 0 &&
                   rates[1].high > previousHigh &&
                   rates[1].close < previousHigh &&
                   rates[1].close < rates[1].open &&
                   rsi1 < 55.0;
      if(sweep)
         ConsiderCandidate(-1, "SWEEP", sellBase + 23.0, atr1, sellCandidate);
   }

   if(buyCandidate.direction != 0 && sellCandidate.direction != 0)
   {
      double gap = MathAbs(buyCandidate.score - sellCandidate.score);
      if(gap < MinDirectionScoreGap)
         return false;

      if(buyCandidate.score > sellCandidate.score)
         best = buyCandidate;
      else
         best = sellCandidate;
      return true;
   }

   if(buyCandidate.direction != 0)
   {
      best = buyCandidate;
      return true;
   }

   if(sellCandidate.direction != 0)
   {
      best = sellCandidate;
      return true;
   }

   return false;
}

bool OpenTrade(const SignalCandidate &signal)
{
   MqlTick tick;
   if(!SymbolInfoTick(Sym, tick))
      return false;

   double lot = NormalizeVolume(FixedLot);
   if(lot <= 0.0)
      return false;

   double entryPrice = NormalizePrice(signal.direction > 0 ? tick.ask : tick.bid);
   double sl = 0.0;
   double tp = 0.0;
   if(!BuildStops(signal.direction, entryPrice, signal.atr, signal.setup, sl, tp))
      return false;

   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   string direction = signal.direction > 0 ? "BUY" : "SELL";
   string comment = "V27 " + direction + " " + signal.setup;
   bool ok = false;

   if(signal.direction > 0)
      ok = trade.Buy(lot, Sym, 0.0, sl, tp, comment);
   else
      ok = trade.Sell(lot, Sym, 0.0, sl, tp, comment);

   if(!ok)
   {
      uint firstRetcode = trade.ResultRetcode();
      string firstDetails = StringFormat("initial retcode=%u comment=%s", firstRetcode, trade.ResultComment());
      Journal("OPEN_RETRY", direction, signal.setup, signal.score, entryPrice, signal.atr, firstDetails);

      if(signal.direction > 0)
         ok = trade.Buy(lot, Sym, 0.0, 0.0, 0.0, comment + " retry");
      else
         ok = trade.Sell(lot, Sym, 0.0, 0.0, 0.0, comment + " retry");

      if(ok)
      {
         ulong ticket = 0;
         if(!FindManagedPosition(ticket) || !PositionSelectByTicket(ticket))
            ok = false;
         else
         {
            double actualEntry = PositionGetDouble(POSITION_PRICE_OPEN);
            if(BuildStops(signal.direction, actualEntry, signal.atr, signal.setup, sl, tp))
            {
               if(!trade.PositionModify(Sym, sl, tp))
               {
                  Journal("OPEN_FAIL", direction, signal.setup, signal.score, actualEntry, signal.atr, "protective stop attach failed");
                  trade.PositionClose(Sym);
                  ok = false;
               }
            }
            else
            {
               trade.PositionClose(Sym);
               ok = false;
            }
         }
      }
   }

   if(!ok)
   {
      string details = StringFormat("retcode=%u comment=%s", trade.ResultRetcode(), trade.ResultComment());
      Journal("OPEN_FAIL", direction, signal.setup, signal.score, entryPrice, signal.atr, details);
      return false;
   }

   tradesToday++;
   lastEntryTime = TimeCurrent();
   activeEntryATR = signal.atr;
   activeSetup = signal.setup;
   activeScore = signal.score;

   Journal("OPEN_ENTRY", direction, signal.setup, signal.score, entryPrice, signal.atr, "natural_signal=true");
   return true;
}

bool CloseManagedPosition(const string reason)
{
   ulong ticket = 0;
   if(!FindManagedPosition(ticket))
      return false;

   if(!PositionSelectByTicket(ticket))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);
   string direction = type == POSITION_TYPE_BUY ? "BUY" : "SELL";
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);

   bool ok = trade.PositionClose(ticket);
   Journal(ok ? "CLOSE_EVENT" : "CLOSE_FAIL", direction, activeSetup, activeScore, price, activeEntryATR, reason);
   if(ok)
   {
      activeEntryATR = 0.0;
      activeSetup = "";
      activeScore = 0.0;
   }
   return ok;
}

void ManageOpenPosition()
{
   ulong ticket = 0;
   if(!FindManagedPosition(ticket))
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   MqlTick tick;
   if(!SymbolInfoTick(Sym, tick))
      return;

   double atrValue = activeEntryATR;
   if(atrValue <= 0.0)
   {
      if(!CopyOne(m15AtrHandle, 0, 1, atrValue) || atrValue <= 0.0)
         return;
      activeEntryATR = atrValue;
   }

   bool isBuy = type == POSITION_TYPE_BUY;
   double marketPrice = isBuy ? tick.bid : tick.ask;
   double favorableDistance = isBuy ? marketPrice - openPrice : openPrice - marketPrice;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(CloseBeforeWeekend && now.day_of_week == 5 && now.hour >= FridayCloseHour)
   {
      CloseManagedPosition("WEEKEND_PROTECTION");
      return;
   }

   int maxHoldSeconds = MaxHoldBars * 15 * 60;
   if(MaxHoldBars > 0 && TimeCurrent() - openTime >= maxHoldSeconds)
   {
      if(favorableDistance < atrValue * TimeExitMinProgressATR)
      {
         CloseManagedPosition("TIME_STOP_NO_PROGRESS");
         return;
      }
   }

   double desiredSL = currentSL;
   bool changeSL = false;

   if(UseBreakEven && favorableDistance >= atrValue * BreakEvenTriggerATR)
   {
      double breakEvenSL = isBuy
         ? openPrice + atrValue * BreakEvenOffsetATR
         : openPrice - atrValue * BreakEvenOffsetATR;

      if(isBuy)
      {
         if(currentSL == 0.0 || breakEvenSL > desiredSL)
         {
            desiredSL = breakEvenSL;
            changeSL = true;
         }
      }
      else
      {
         if(currentSL == 0.0 || breakEvenSL < desiredSL)
         {
            desiredSL = breakEvenSL;
            changeSL = true;
         }
      }
   }

   if(UseTrailingStop && favorableDistance >= atrValue * TrailStartATR)
   {
      double trailSL = isBuy
         ? marketPrice - atrValue * TrailDistanceATR
         : marketPrice + atrValue * TrailDistanceATR;

      if(isBuy)
      {
         if(currentSL == 0.0 || trailSL > desiredSL)
         {
            desiredSL = trailSL;
            changeSL = true;
         }
      }
      else
      {
         if(currentSL == 0.0 || trailSL < desiredSL)
         {
            desiredSL = trailSL;
            changeSL = true;
         }
      }
   }

   if(!changeSL)
      return;

   double minDistance = MinimumStopDistance();
   desiredSL = NormalizePrice(desiredSL);

   if(isBuy)
   {
      if(desiredSL >= marketPrice - minDistance)
         return;
      if(currentSL > 0.0 && desiredSL <= currentSL + TickSize())
         return;
   }
   else
   {
      if(desiredSL <= marketPrice + minDistance)
         return;
      if(currentSL > 0.0 && desiredSL >= currentSL - TickSize())
         return;
   }

   if(trade.PositionModify(Sym, desiredSL, currentTP))
   {
      Journal(
         "STOP_UPDATE",
         isBuy ? "BUY" : "SELL",
         activeSetup,
         activeScore,
         marketPrice,
         atrValue,
         "adaptive_protection"
      );
   }
}

int OnInit()
{
   Sym = InpTradeSymbol == "" ? _Symbol : InpTradeSymbol;
   if(!SymbolSelect(Sym, true))
      return INIT_FAILED;

   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   m15FastHandle = iMA(Sym, PERIOD_M15, FastLen, 0, MODE_EMA, PRICE_CLOSE);
   m15SlowHandle = iMA(Sym, PERIOD_M15, SlowLen, 0, MODE_EMA, PRICE_CLOSE);
   m15TrendHandle = iMA(Sym, PERIOD_M15, TrendLen, 0, MODE_EMA, PRICE_CLOSE);
   m15RsiHandle = iRSI(Sym, PERIOD_M15, RsiLen, PRICE_CLOSE);
   m15AtrHandle = iATR(Sym, PERIOD_M15, AtrLen);
   m15AdxHandle = iADX(Sym, PERIOD_M15, AdxLen);

   h1FastHandle = iMA(Sym, PERIOD_H1, BiasFastLen, 0, MODE_EMA, PRICE_CLOSE);
   h1SlowHandle = iMA(Sym, PERIOD_H1, BiasSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   h1RsiHandle = iRSI(Sym, PERIOD_H1, RsiLen, PRICE_CLOSE);

   h4FastHandle = iMA(Sym, PERIOD_H4, BiasFastLen, 0, MODE_EMA, PRICE_CLOSE);
   h4SlowHandle = iMA(Sym, PERIOD_H4, BiasSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   h4RsiHandle = iRSI(Sym, PERIOD_H4, RsiLen, PRICE_CLOSE);

   if(m15FastHandle == INVALID_HANDLE ||
      m15SlowHandle == INVALID_HANDLE ||
      m15TrendHandle == INVALID_HANDLE ||
      m15RsiHandle == INVALID_HANDLE ||
      m15AtrHandle == INVALID_HANDLE ||
      m15AdxHandle == INVALID_HANDLE ||
      h1FastHandle == INVALID_HANDLE ||
      h1SlowHandle == INVALID_HANDLE ||
      h1RsiHandle == INVALID_HANDLE ||
      h4FastHandle == INVALID_HANDLE ||
      h4SlowHandle == INVALID_HANDLE ||
      h4RsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ResetDailyCounterIfNeeded();
   Journal("EA_START", "", "", 0.0, 0.0, 0.0, "V27_CLEAN_MULTISETUP");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(m15FastHandle);
   IndicatorRelease(m15SlowHandle);
   IndicatorRelease(m15TrendHandle);
   IndicatorRelease(m15RsiHandle);
   IndicatorRelease(m15AtrHandle);
   IndicatorRelease(m15AdxHandle);

   IndicatorRelease(h1FastHandle);
   IndicatorRelease(h1SlowHandle);
   IndicatorRelease(h1RsiHandle);
   IndicatorRelease(h4FastHandle);
   IndicatorRelease(h4SlowHandle);
   IndicatorRelease(h4RsiHandle);
}

void OnTick()
{
   ResetDailyCounterIfNeeded();
   ManageOpenPosition();

   ulong ticket = 0;
   if(FindManagedPosition(ticket))
      return;

   if(!IsEntrySessionOpen())
      return;
   if(tradesToday >= MaxTradesPerDay)
      return;
   if(lastEntryTime > 0 && TimeCurrent() - lastEntryTime < CooldownMinutes * 60)
      return;
   if(!IsNewExecutionBar())
      return;

   SignalCandidate signal;
   if(!EvaluateSignals(signal))
      return;

   OpenTrade(signal);
}
//+------------------------------------------------------------------+
