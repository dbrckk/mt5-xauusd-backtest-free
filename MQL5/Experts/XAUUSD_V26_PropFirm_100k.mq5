//+------------------------------------------------------------------+
//| XAUUSD_V26_PropFirm_100k.mq5                                     |
//| V26 Combined EA: V24 SELL Ultimate + V25 BUY Quality             |
//| Defaults: 15k demo test, forced 0.02 lot, max 8 trades/day        |
//+------------------------------------------------------------------+
#property strict
#property version   "1.02"
#property description "XAUUSD V26 Combined EA - hardened execution, forced 0.02 lot, MTF test modes"

#include <Trade/Trade.mqh>

CTrade trade;

input string InpTradeSymbol = "";
input double FixedLot = 0.02;
input int MaxTradesPerDay = 8;
input int CooldownMinutes = 30;
input ulong MagicNumber = 260100;
input int SlippagePoints = 80;
input int BrokerStopBufferPoints = 30;
input bool UseExecutionTimeframeGate = true;
input bool UseExecutionTrendFilter = true;

input bool UseSession = true;
input int SessionStartHour = 8;
input int SessionEndHour = 21;
input bool BlockFridayAfter16 = true;

input bool EnableBuy = true;
input bool EnableSell = true;
input bool BuyFrequencyMode = false;
input bool UseBuyH1Filter = false;
input bool BlockBuyH2Bear = false;
input bool BlockBuyH4Bear = false;

input int FastLen = 9;
input int SlowLen = 21;
input int TrendLen = 200;
input int RsiLen = 14;
input int AtrLen = 14;
input int VolLen = 20;
input double SellVolMult = 0.80;
input double BuyVolMult = 0.80;
input double BuyMinRsi = 50.0;
input double BuyMaxRsi = 70.0;
input double BuyMinBodyRatio = 0.25;

input double SellTP_ATR = 2.50;
input double SellSL_ATR = 2.00;
input double BuyTP_ATR = 1.00;
input double BuySL_ATR = 2.00;

string Sym;
int tradesToday = 0;
int currentYear = -1;
int currentDayOfYear = -1;
datetime lastEntryTime = 0;
datetime lastAttemptTime = 0;
datetime lastExecutionBarTime = 0;
datetime lastSellBarTime = 0;
datetime lastBuyBarTime = 0;

int h1FastHandle, h1SlowHandle, h1TrendHandle, h1RsiHandle, h1AtrHandle;
int m15FastHandle, m15SlowHandle, m15TrendHandle, m15RsiHandle, m15AtrHandle;
int h2FastHandle, h2SlowHandle, h2TrendHandle, h2RsiHandle;
int h4FastHandle, h4SlowHandle, h4TrendHandle, h4RsiHandle;

ENUM_TIMEFRAMES ExecutionTF()
{
   return (ENUM_TIMEFRAMES)_Period;
}

bool CopyOne(int handle, int shift, double &value)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   value = buf[0];
   return true;
}

bool CopyRatesData(ENUM_TIMEFRAMES tf, int count, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(Sym, tf, 0, count, rates);
   return copied >= count;
}

double VolumeSMA(MqlRates &rates[], int startShift, int len)
{
   double sum = 0.0;
   for(int i=startShift; i<startShift+len; i++) sum += (double)rates[i].tick_volume;
   return sum / (double)len;
}

bool IsSessionOk()
{
   if(!UseSession) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.hour < SessionStartHour || dt.hour >= SessionEndHour) return false;
   if(BlockFridayAfter16 && dt.day_of_week == 5 && dt.hour >= 16) return false;
   return true;
}

void ResetDailyCounterIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.year != currentYear || dt.day_of_year != currentDayOfYear)
   {
      currentYear = dt.year;
      currentDayOfYear = dt.day_of_year;
      tradesToday = 0;
   }
}

bool IsNewExecutionBar()
{
   if(!UseExecutionTimeframeGate) return true;
   MqlRates r[];
   if(!CopyRatesData(ExecutionTF(), 3, r)) return false;
   if(r[1].time == lastExecutionBarTime) return false;
   lastExecutionBarTime = r[1].time;
   return true;
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string psym = PositionGetString(POSITION_SYMBOL);
      ulong pmagic = (ulong)PositionGetInteger(POSITION_MAGIC);
      if(psym == Sym && pmagic == MagicNumber) return true;
   }
   return false;
}

bool TrendState(ENUM_TIMEFRAMES tf, bool wantBull)
{
   int fh = tf == PERIOD_H1 ? h1FastHandle : tf == PERIOD_H2 ? h2FastHandle : h4FastHandle;
   int sh = tf == PERIOD_H1 ? h1SlowHandle : tf == PERIOD_H2 ? h2SlowHandle : h4SlowHandle;
   int th = tf == PERIOD_H1 ? h1TrendHandle : tf == PERIOD_H2 ? h2TrendHandle : h4TrendHandle;
   int rh = tf == PERIOD_H1 ? h1RsiHandle : tf == PERIOD_H2 ? h2RsiHandle : h4RsiHandle;
   MqlRates r[];
   if(!CopyRatesData(tf, 5, r)) return false;
   double fast1, slow1, trend1, trend4, rsi1;
   if(!CopyOne(fh, 1, fast1) || !CopyOne(sh, 1, slow1) || !CopyOne(th, 1, trend1) || !CopyOne(th, 4, trend4) || !CopyOne(rh, 1, rsi1)) return false;
   bool bull = r[1].close > trend1 && fast1 > slow1 && trend1 > trend4 && rsi1 > 50.0;
   bool bear = r[1].close < trend1 && fast1 < slow1 && trend1 < trend4 && rsi1 < 50.0;
   return wantBull ? bull : bear;
}

bool ExecutionTrendOk(ENUM_ORDER_TYPE type)
{
   if(!UseExecutionTrendFilter) return true;
   ENUM_TIMEFRAMES tf = ExecutionTF();
   if(tf == PERIOD_H1)
   {
      if(type == ORDER_TYPE_BUY && TrendState(PERIOD_H1, false)) return false;
      if(type == ORDER_TYPE_SELL && TrendState(PERIOD_H1, true)) return false;
   }
   if(tf == PERIOD_H2)
   {
      if(type == ORDER_TYPE_BUY && TrendState(PERIOD_H2, false)) return false;
      if(type == ORDER_TYPE_SELL && TrendState(PERIOD_H2, true)) return false;
   }
   if(tf == PERIOD_H4)
   {
      if(type == ORDER_TYPE_BUY && TrendState(PERIOD_H4, false)) return false;
      if(type == ORDER_TYPE_SELL && TrendState(PERIOD_H4, true)) return false;
   }
   return true;
}

bool SellSignal(double &atrValue)
{
   MqlRates r[];
   if(!CopyRatesData(PERIOD_H1, VolLen + 5, r)) return false;
   if(r[1].time == lastSellBarTime) return false;

   double f1, s1, f2, s2, tr1, rsi1, atr1;
   if(!CopyOne(h1FastHandle, 1, f1) || !CopyOne(h1SlowHandle, 1, s1) || !CopyOne(h1FastHandle, 2, f2) || !CopyOne(h1SlowHandle, 2, s2)) return false;
   if(!CopyOne(h1TrendHandle, 1, tr1) || !CopyOne(h1RsiHandle, 1, rsi1) || !CopyOne(h1AtrHandle, 1, atr1)) return false;

   double vSma = VolumeSMA(r, 1, VolLen);
   bool cross = f1 < s1 && f2 >= s2;
   bool trendOk = r[1].close < tr1;
   bool rsiOk = rsi1 < 50.0 && rsi1 > 32.0;
   bool volOk = (double)r[1].tick_volume > vSma * SellVolMult;

   if(cross && trendOk && rsiOk && volOk)
   {
      atrValue = atr1;
      lastSellBarTime = r[1].time;
      return true;
   }
   return false;
}

bool BuySignal(double &atrValue)
{
   MqlRates r[];
   if(!CopyRatesData(PERIOD_M15, VolLen + 10, r)) return false;
   if(r[1].time == lastBuyBarTime) return false;

   double f1, s1, tr1, tr4, rsi1, atr1;
   if(!CopyOne(m15FastHandle, 1, f1) || !CopyOne(m15SlowHandle, 1, s1) || !CopyOne(m15TrendHandle, 1, tr1) || !CopyOne(m15TrendHandle, 4, tr4)) return false;
   if(!CopyOne(m15RsiHandle, 1, rsi1) || !CopyOne(m15AtrHandle, 1, atr1)) return false;

   double range = r[1].high - r[1].low;
   if(range <= 0.0) return false;
   double bodyRatio = MathAbs(r[1].close - r[1].open) / range;
   double vSma = VolumeSMA(r, 1, VolLen);
   double highestPrev3 = MathMax(r[2].high, MathMax(r[3].high, r[4].high));

   bool trendOk = r[1].close > tr1 && f1 > s1 && tr1 > tr4;
   bool rsiOk = rsi1 > BuyMinRsi && rsi1 < BuyMaxRsi;
   bool volOk = (double)r[1].tick_volume > vSma * BuyVolMult;
   bool bodyOk = bodyRatio >= BuyMinBodyRatio;
   bool breakoutOk = r[1].close > highestPrev3;
   bool momentumOk = r[1].close > r[1].open && r[1].close > r[2].high;
   bool triggerOk = BuyFrequencyMode ? momentumOk : breakoutOk;
   bool filterOk = true;
   if(UseBuyH1Filter && !TrendState(PERIOD_H1, true)) filterOk = false;
   if(BlockBuyH2Bear && TrendState(PERIOD_H2, false)) filterOk = false;
   if(BlockBuyH4Bear && TrendState(PERIOD_H4, false)) filterOk = false;

   if(trendOk && rsiOk && volOk && bodyOk && triggerOk && filterOk)
   {
      atrValue = atr1;
      lastBuyBarTime = r[1].time;
      return true;
   }
   return false;
}

double ForcedLot()
{
   return 0.02;
}

double NormalizeVolume(double lot)
{
   double minLot = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(Sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(Sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   if(lot < minLot || lot > maxLot) return 0.0;
   double steps = MathRound((lot - minLot) / step);
   double normalized = minLot + steps * step;
   if(MathAbs(normalized - lot) > 0.0000001) return 0.0;
   return NormalizeDouble(normalized, 2);
}

double TickSize()
{
   double tickSize = SymbolInfoDouble(Sym, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(Sym, SYMBOL_POINT);
   if(tickSize <= 0.0) tickSize = point;
   if(tickSize <= 0.0) tickSize = 0.01;
   return tickSize;
}

double NormalizePrice(double price)
{
   int digits = (int)SymbolInfoInteger(Sym, SYMBOL_DIGITS);
   double tickSize = TickSize();
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

double MinStopDistance()
{
   double point = SymbolInfoDouble(Sym, SYMBOL_POINT);
   if(point <= 0.0) point = 0.01;
   int stopLevel = (int)SymbolInfoInteger(Sym, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(Sym, SYMBOL_TRADE_FREEZE_LEVEL);
   int minPoints = (int)MathMax(stopLevel, freezeLevel) + BrokerStopBufferPoints;
   double minDistance = (double)minPoints * point;
   minDistance = MathMax(minDistance, 2.0 * TickSize());
   return minDistance;
}

bool BuildStops(ENUM_ORDER_TYPE type, double entryPrice, double atrValue, double &sl, double &tp)
{
   if(atrValue <= 0.0) return false;
   double tpMult = type == ORDER_TYPE_BUY ? BuyTP_ATR : SellTP_ATR;
   double slMult = type == ORDER_TYPE_BUY ? BuySL_ATR : SellSL_ATR;
   double minDistance = MinStopDistance();
   double slDistance = MathMax(atrValue * slMult, minDistance);
   double tpDistance = MathMax(atrValue * tpMult, minDistance);

   if(type == ORDER_TYPE_BUY)
   {
      sl = NormalizePrice(entryPrice - slDistance);
      tp = NormalizePrice(entryPrice + tpDistance);
      if(sl >= entryPrice || tp <= entryPrice) return false;
      if((entryPrice - sl) < minDistance || (tp - entryPrice) < minDistance) return false;
   }
   else
   {
      sl = NormalizePrice(entryPrice + slDistance);
      tp = NormalizePrice(entryPrice - tpDistance);
      if(sl <= entryPrice || tp >= entryPrice) return false;
      if((sl - entryPrice) < minDistance || (entryPrice - tp) < minDistance) return false;
   }
   return true;
}

bool PlaceOrder(ENUM_ORDER_TYPE type, double lot, double price, double sl, double tp, string comment)
{
   bool ok = false;
   if(type == ORDER_TYPE_BUY) ok = trade.Buy(lot, Sym, price, sl, tp, comment);
   if(type == ORDER_TYPE_SELL) ok = trade.Sell(lot, Sym, price, sl, tp, comment);
   if(ok) return true;

   uint rc = trade.ResultRetcode();
   bool fallbackAllowed = (rc == TRADE_RETCODE_INVALID_PRICE || rc == TRADE_RETCODE_INVALID_STOPS || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_REQUOTE);
   if(!fallbackAllowed) return false;

   MqlTick retryTick;
   if(!SymbolInfoTick(Sym, retryTick)) return false;
   double retryPrice = NormalizePrice(type == ORDER_TYPE_BUY ? retryTick.ask : retryTick.bid);
   if(!BuildStops(type, retryPrice, MathAbs(tp - sl), sl, tp)) return false;

   if(type == ORDER_TYPE_BUY) ok = trade.Buy(lot, Sym, retryPrice, 0.0, 0.0, comment + " retry");
   if(type == ORDER_TYPE_SELL) ok = trade.Sell(lot, Sym, retryPrice, 0.0, 0.0, comment + " retry");
   if(!ok) return false;

   if(!trade.PositionModify(Sym, sl, tp))
   {
      trade.PositionClose(Sym);
      return false;
   }
   return true;
}

bool OpenTrade(ENUM_ORDER_TYPE type, double atrValue)
{
   if(!ExecutionTrendOk(type)) return false;
   MqlTick tick;
   if(!SymbolInfoTick(Sym, tick)) return false;
   double price = NormalizePrice(type == ORDER_TYPE_BUY ? tick.ask : tick.bid);
   double sl = 0.0;
   double tp = 0.0;
   if(!BuildStops(type, price, atrValue, sl, tp)) return false;

   double lot = NormalizeVolume(ForcedLot());
   if(lot <= 0.0) return false;

   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   lastAttemptTime = TimeCurrent();
   bool ok = PlaceOrder(type, lot, price, sl, tp, type == ORDER_TYPE_BUY ? "V26 BUY" : "V26 SELL");
   if(ok)
   {
      tradesToday++;
      lastEntryTime = TimeCurrent();
   }
   return ok;
}

int OnInit()
{
   Sym = InpTradeSymbol == "" ? _Symbol : InpTradeSymbol;
   if(!SymbolSelect(Sym, true)) return INIT_FAILED;
   trade.SetExpertMagicNumber((int)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   h1FastHandle = iMA(Sym, PERIOD_H1, FastLen, 0, MODE_EMA, PRICE_CLOSE);
   h1SlowHandle = iMA(Sym, PERIOD_H1, SlowLen, 0, MODE_EMA, PRICE_CLOSE);
   h1TrendHandle = iMA(Sym, PERIOD_H1, TrendLen, 0, MODE_EMA, PRICE_CLOSE);
   h1RsiHandle = iRSI(Sym, PERIOD_H1, RsiLen, PRICE_CLOSE);
   h1AtrHandle = iATR(Sym, PERIOD_H1, AtrLen);

   m15FastHandle = iMA(Sym, PERIOD_M15, FastLen, 0, MODE_EMA, PRICE_CLOSE);
   m15SlowHandle = iMA(Sym, PERIOD_M15, SlowLen, 0, MODE_EMA, PRICE_CLOSE);
   m15TrendHandle = iMA(Sym, PERIOD_M15, TrendLen, 0, MODE_EMA, PRICE_CLOSE);
   m15RsiHandle = iRSI(Sym, PERIOD_M15, RsiLen, PRICE_CLOSE);
   m15AtrHandle = iATR(Sym, PERIOD_M15, AtrLen);

   h2FastHandle = iMA(Sym, PERIOD_H2, FastLen, 0, MODE_EMA, PRICE_CLOSE);
   h2SlowHandle = iMA(Sym, PERIOD_H2, SlowLen, 0, MODE_EMA, PRICE_CLOSE);
   h2TrendHandle = iMA(Sym, PERIOD_H2, TrendLen, 0, MODE_EMA, PRICE_CLOSE);
   h2RsiHandle = iRSI(Sym, PERIOD_H2, RsiLen, PRICE_CLOSE);

   h4FastHandle = iMA(Sym, PERIOD_H4, FastLen, 0, MODE_EMA, PRICE_CLOSE);
   h4SlowHandle = iMA(Sym, PERIOD_H4, SlowLen, 0, MODE_EMA, PRICE_CLOSE);
   h4TrendHandle = iMA(Sym, PERIOD_H4, TrendLen, 0, MODE_EMA, PRICE_CLOSE);
   h4RsiHandle = iRSI(Sym, PERIOD_H4, RsiLen, PRICE_CLOSE);

   if(h1FastHandle == INVALID_HANDLE || h1SlowHandle == INVALID_HANDLE || h1TrendHandle == INVALID_HANDLE || h1RsiHandle == INVALID_HANDLE || h1AtrHandle == INVALID_HANDLE) return INIT_FAILED;
   if(m15FastHandle == INVALID_HANDLE || m15SlowHandle == INVALID_HANDLE || m15TrendHandle == INVALID_HANDLE || m15RsiHandle == INVALID_HANDLE || m15AtrHandle == INVALID_HANDLE) return INIT_FAILED;
   if(h2FastHandle == INVALID_HANDLE || h2SlowHandle == INVALID_HANDLE || h2TrendHandle == INVALID_HANDLE || h2RsiHandle == INVALID_HANDLE) return INIT_FAILED;
   if(h4FastHandle == INVALID_HANDLE || h4SlowHandle == INVALID_HANDLE || h4TrendHandle == INVALID_HANDLE || h4RsiHandle == INVALID_HANDLE) return INIT_FAILED;

   ResetDailyCounterIfNeeded();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(h1FastHandle); IndicatorRelease(h1SlowHandle); IndicatorRelease(h1TrendHandle); IndicatorRelease(h1RsiHandle); IndicatorRelease(h1AtrHandle);
   IndicatorRelease(m15FastHandle); IndicatorRelease(m15SlowHandle); IndicatorRelease(m15TrendHandle); IndicatorRelease(m15RsiHandle); IndicatorRelease(m15AtrHandle);
   IndicatorRelease(h2FastHandle); IndicatorRelease(h2SlowHandle); IndicatorRelease(h2TrendHandle); IndicatorRelease(h2RsiHandle);
   IndicatorRelease(h4FastHandle); IndicatorRelease(h4SlowHandle); IndicatorRelease(h4TrendHandle); IndicatorRelease(h4RsiHandle);
}

void OnTick()
{
   ResetDailyCounterIfNeeded();
   if(!IsSessionOk()) return;
   if(HasOpenPosition()) return;
   if(tradesToday >= MaxTradesPerDay) return;
   if(lastAttemptTime > 0 && (TimeCurrent() - lastAttemptTime) < CooldownMinutes * 60) return;
   if(!IsNewExecutionBar()) return;

   double sellAtr = 0.0;
   double buyAtr = 0.0;
   bool sellOk = EnableSell && SellSignal(sellAtr);
   bool buyOk = EnableBuy && BuySignal(buyAtr);

   if(sellOk) { OpenTrade(ORDER_TYPE_SELL, sellAtr); return; }
   if(buyOk) { OpenTrade(ORDER_TYPE_BUY, buyAtr); return; }
}
