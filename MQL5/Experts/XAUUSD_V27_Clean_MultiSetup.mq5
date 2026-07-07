#property strict
#property version "2.90"
#property description "V30 Symmetric Opportunity Expansion: fresh cross-period validation"

#include <Trade/Trade.mqh>

CTrade trade;

input string InpTradeSymbol="";
input double FixedLot=0.02;
input bool UseRiskPercent=true;
input double RiskPercent=0.20;
input bool UseEquityForRisk=true;
input double MaxRiskLot=2.00;
input double MinLotRiskTolerance=1.10;
input int MaxTradesPerDay=4;
input int CooldownMinutes=45;
input ulong MagicNumber=280100;
input int SlippagePoints=120;
input int BrokerStopBufferPoints=40;

input bool UseSession=true;
input int SessionStartHour=7;
input int SessionEndHour=20;
input int LastEntryHour=19;
input int LastEntryMinute=15;
input int HardFlatHour=20;
input int HardFlatMinute=45;
input bool BlockFridayLateEntries=true;
input int FridayLastEntryHour=17;
input bool CloseBeforeWeekend=true;
input int FridayCloseHour=19;

input bool EnableBuy=true;
input bool EnableSell=true;
input double MinSignalScore=78.0;
input double MinDirectionScoreGap=10.0;
input double MinADX=20.0;
input double MaxSpreadATRFraction=0.07;

input int FastLen=9;
input int SlowLen=21;
input int TrendLen=200;
input int BiasFastLen=50;
input int BiasSlowLen=200;
input int RsiLen=14;
input int AtrLen=14;
input int AdxLen=14;
input int VolLen=20;
input int BreakoutLookback=5;
input int SweepLookback=5;
input double PullbackTouchATR=0.20;
input double MinBodyRatio=0.34;
input double MinVolumeRatio=0.95;

input double BreakoutTP_ATR=1.55;
input double BreakoutSL_ATR=1.05;
input double PullbackTP_ATR=1.35;
input double PullbackSL_ATR=1.00;
input double ContinuationTP_ATR=1.30;
input double ContinuationSL_ATR=1.00;
input double SweepTP_ATR=1.45;
input double SweepSL_ATR=0.95;

input bool UseBreakEven=true;
input double BreakEvenTriggerATR=0.85;
input double BreakEvenOffsetATR=0.02;
input bool UseTrailingStop=true;
input double TrailStartATR=1.25;
input double TrailDistanceATR=0.70;
input int MaxHoldBars=28;
input double TimeExitMinProgressATR=0.20;

input bool UseCSVJournal=true;
input string CSVJournalName="V30_SYMMETRIC_journal.csv";

string Sym;
string activeSetup="";
string activeRoute="";
int tradesToday=0;
int currentYear=-1;
int currentDay=-1;
datetime lastEntryTime=0;
datetime lastBarTime=0;
double activeATR=0.0;
double activeScore=0.0;
double activeRisk=0.0;

int fH=INVALID_HANDLE;
int sH=INVALID_HANDLE;
int tH=INVALID_HANDLE;
int rH=INVALID_HANDLE;
int aH=INVALID_HANDLE;
int dH=INVALID_HANDLE;
int h1f=INVALID_HANDLE;
int h1s=INVALID_HANDLE;
int h1r=INVALID_HANDLE;
int h4f=INVALID_HANDLE;
int h4s=INVALID_HANDLE;
int h4r=INVALID_HANDLE;

struct Candidate
{
   int dir;
   string setup;
   string route;
   double score;
   double atr;
};

void Reset(Candidate &c)
{
   c.dir=0;
   c.setup="";
   c.route="";
   c.score=0;
   c.atr=0;
}

bool One(int handle,int buffer,int shift,double &value)
{
   double x[];
   ArraySetAsSeries(x,true);
   if(handle==INVALID_HANDLE || CopyBuffer(handle,buffer,shift,1,x)!=1)
      return false;
   value=x[0];
   return MathIsValidNumber(value);
}

bool Rates(ENUM_TIMEFRAMES tf,int count,MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);
   return CopyRates(Sym,tf,0,count,rates)>=count;
}

double VolSma(MqlRates &rates[],int shift,int count)
{
   double sum=0;
   for(int i=shift;i<shift+count;i++)
      sum+=(double)rates[i].tick_volume;
   return sum/count;
}

double HH(MqlRates &rates[],int shift,int count)
{
   double value=rates[shift].high;
   for(int i=shift+1;i<shift+count;i++)
      value=MathMax(value,rates[i].high);
   return value;
}

double LL(MqlRates &rates[],int shift,int count)
{
   double value=rates[shift].low;
   for(int i=shift+1;i<shift+count;i++)
      value=MathMin(value,rates[i].low);
   return value;
}

void J(string eventName,string direction,string setup,double score,double price,double atr,string details)
{
   if(!UseCSVJournal)
      return;

   int handle=FileOpen(CSVJournalName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(handle==INVALID_HANDLE)
      return;

   if(FileSize(handle)==0)
      FileWrite(handle,"time","event","direction","setup","score","price","atr","details");

   FileSeek(handle,0,SEEK_END);
   FileWrite(
      handle,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      eventName,
      direction,
      setup,
      DoubleToString(score,2),
      DoubleToString(price,3),
      DoubleToString(atr,5),
      details
   );
   FileClose(handle);
}

int MinuteOfDay(int hour,int minute)
{
   return hour*60+minute;
}

void ResetDay()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(now.year!=currentYear || now.day_of_year!=currentDay)
   {
      currentYear=now.year;
      currentDay=now.day_of_year;
      tradesToday=0;
   }
}

bool HardDailyFlat()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(now.day_of_week==0 || now.day_of_week==6)
      return true;
   return MinuteOfDay(now.hour,now.min)>=MinuteOfDay(HardFlatHour,HardFlatMinute);
}

bool LastEntryPassed()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   return MinuteOfDay(now.hour,now.min)>=MinuteOfDay(LastEntryHour,LastEntryMinute);
}

bool SessionOpen()
{
   if(!UseSession)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(now.day_of_week==0 || now.day_of_week==6)
      return false;
   if(now.hour<SessionStartHour || now.hour>=SessionEndHour)
      return false;
   if(BlockFridayLateEntries && now.day_of_week==5 && now.hour>=FridayLastEntryHour)
      return false;
   return true;
}

bool NewBar()
{
   MqlRates rates[];
   if(!Rates(PERIOD_M15,3,rates) || rates[1].time==lastBarTime)
      return false;
   lastBarTime=rates[1].time;
   return true;
}

bool Position(ulong &ticket)
{
   ticket=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong current=PositionGetTicket(i);
      if(current==0 || !PositionSelectByTicket(current))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=Sym)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      ticket=current;
      return true;
   }
   return false;
}

int Bias(ENUM_TIMEFRAMES tf)
{
   int fastHandle=tf==PERIOD_H1?h1f:h4f;
   int slowHandle=tf==PERIOD_H1?h1s:h4s;
   int rsiHandle=tf==PERIOD_H1?h1r:h4r;

   MqlRates rates[];
   double fast;
   double slow;
   double rsi;
   if(!Rates(tf,4,rates) || !One(fastHandle,0,1,fast) || !One(slowHandle,0,1,slow) || !One(rsiHandle,0,1,rsi))
      return 0;

   if(rates[1].close>slow && fast>slow && rsi>=52)
      return 1;
   if(rates[1].close<slow && fast<slow && rsi<=48)
      return -1;
   return 0;
}

double Tick()
{
   double value=SymbolInfoDouble(Sym,SYMBOL_TRADE_TICK_SIZE);
   if(value<=0)
      value=SymbolInfoDouble(Sym,SYMBOL_POINT);
   return value>0?value:0.001;
}

double Price(double value)
{
   return NormalizeDouble(MathRound(value/Tick())*Tick(),(int)SymbolInfoInteger(Sym,SYMBOL_DIGITS));
}

double MinStop()
{
   double point=SymbolInfoDouble(Sym,SYMBOL_POINT);
   if(point<=0)
      point=0.001;
   int brokerLevel=(int)MathMax(
      SymbolInfoInteger(Sym,SYMBOL_TRADE_STOPS_LEVEL),
      SymbolInfoInteger(Sym,SYMBOL_TRADE_FREEZE_LEVEL)
   );
   return MathMax((brokerLevel+BrokerStopBufferPoints)*point,2*Tick());
}

void Multipliers(string setup,double &tpMultiplier,double &slMultiplier)
{
   tpMultiplier=ContinuationTP_ATR;
   slMultiplier=ContinuationSL_ATR;
   if(setup=="BREAKOUT")
   {
      tpMultiplier=BreakoutTP_ATR;
      slMultiplier=BreakoutSL_ATR;
   }
   else if(setup=="PULLBACK")
   {
      tpMultiplier=PullbackTP_ATR;
      slMultiplier=PullbackSL_ATR;
   }
   else if(setup=="SWEEP")
   {
      tpMultiplier=SweepTP_ATR;
      slMultiplier=SweepSL_ATR;
   }
}

bool Stops(int dir,double entry,double atr,string setup,double &sl,double &tp)
{
   double tpMultiplier;
   double slMultiplier;
   Multipliers(setup,tpMultiplier,slMultiplier);

   double minDistance=MinStop();
   double tpDistance=MathMax(atr*tpMultiplier,minDistance);
   double slDistance=MathMax(atr*slMultiplier,minDistance);

   if(dir>0)
   {
      sl=Price(entry-slDistance);
      tp=Price(entry+tpDistance);
      return sl<entry && tp>entry;
   }

   sl=Price(entry+slDistance);
   tp=Price(entry-tpDistance);
   return sl>entry && tp<entry;
}

bool RiskMoney(int dir,double lot,double entry,double sl,double &risk)
{
   ENUM_ORDER_TYPE type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double profit=0;
   if(OrderCalcProfit(type,Sym,lot,entry,sl,profit))
   {
      risk=MathAbs(profit);
      return risk>0;
   }

   double contractSize=SymbolInfoDouble(Sym,SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize<=0)
      contractSize=100;
   risk=MathAbs(entry-sl)*contractSize*lot;
   return risk>0;
}

double VolDown(double lot)
{
   double minLot=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(Sym,SYMBOL_VOLUME_STEP);
   if(step<=0)
      step=0.01;
   if(minLot<=0)
      minLot=step;
   if(MaxRiskLot>0)
      maxLot=MathMin(maxLot,MaxRiskLot);
   if(lot<minLot)
      return 0;

   double value=MathFloor((lot+1e-10)/step)*step;
   value=MathMin(value,maxLot);
   return value>=minLot?NormalizeDouble(value,step<0.01?3:2):0;
}

bool Size(int dir,double entry,double sl,double &lot,double &plannedRisk,double &actualRisk)
{
   lot=0;
   plannedRisk=0;
   actualRisk=0;

   if(!UseRiskPercent)
   {
      lot=VolDown(FixedLot);
      return lot>0 && RiskMoney(dir,lot,entry,sl,actualRisk) && (plannedRisk=actualRisk)>0;
   }

   double base=UseEquityForRisk?AccountInfoDouble(ACCOUNT_EQUITY):AccountInfoDouble(ACCOUNT_BALANCE);
   if(base<=0 || RiskPercent<=0)
      return false;

   plannedRisk=base*RiskPercent/100.0;
   double oneLotRisk;
   if(!RiskMoney(dir,1.0,entry,sl,oneLotRisk) || oneLotRisk<=0)
      return false;

   lot=VolDown(plannedRisk/oneLotRisk);
   double minLot=SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN);
   if(minLot<=0)
      minLot=0.01;

   if(lot<=0)
   {
      double minRisk;
      if(!RiskMoney(dir,minLot,entry,sl,minRisk) || minRisk>plannedRisk*MinLotRiskTolerance)
         return false;
      lot=minLot;
   }

   if(!RiskMoney(dir,lot,entry,sl,actualRisk))
      return false;
   return actualRisk<=plannedRisk*MinLotRiskTolerance;
}

bool Route(string setup,int dir,int hour,string &name)
{
   name="";

   if(setup=="PULLBACK" && dir>0 && hour==15)
   {
      name="CORE_PULLBACK_BUY_15";
      return true;
   }
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

   return false;
}

bool RouteQuality(string setup,int dir,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if((dir>0 && h1Bias<=0) || (dir<0 && h1Bias>=0))
      return false;
   if((dir>0 && h4Bias<0) || (dir<0 && h4Bias>0))
      return false;
   if(adx<MinADX || volumeRatio<MinVolumeRatio || bodyRatio<MinBodyRatio)
      return false;

   if(setup=="PULLBACK" && dir>0)
      return rsi>51 && rsi<66 && volumeRatio>=1.00 && bodyRatio>=0.36;
   if(setup=="PULLBACK" && dir<0)
      return rsi>34 && rsi<49 && volumeRatio>=1.00 && bodyRatio>=0.36;
   if(setup=="CONTINUATION" && dir<0)
      return rsi>=35 && rsi<=47 && volumeRatio>=1.04 && bodyRatio>=0.38;
   if(setup=="CONTINUATION" && dir>0)
      return rsi>=53 && rsi<=65 && volumeRatio>=1.04 && bodyRatio>=0.38;
   if(setup=="SWEEP" && dir<0)
      return rsi>34 && rsi<50 && volumeRatio>=1.00 && bodyRatio>=0.36;

   return true;
}

bool EdgeQuality(string route,double rsi,double adx,double volumeRatio,double bodyRatio,int h1Bias,int h4Bias)
{
   if(route=="EDGE_PULLBACK_SELL_15")
      return h1Bias<0 && h4Bias<0 && rsi>=36 && rsi<=48 && adx>=22 && volumeRatio>=1.05 && bodyRatio>=0.40;

   if(route=="EDGE_CONTINUATION_BUY_07_08")
      return h1Bias>0 && h4Bias>0 && rsi>=53 && rsi<=64 && adx>=22 && volumeRatio>=1.05 && bodyRatio>=0.40;

   return true;
}

double BaseScore(
   bool buy,
   MqlRates &rates[],
   double fast,
   double slow,
   double trend,
   double rsi,
   double adx,
   double atr,
   double volumeRatio,
   double bodyRatio,
   int h1Bias,
   int h4Bias
)
{
   bool local=buy?(rates[1].close>trend && fast>slow):(rates[1].close<trend && fast<slow);
   if(!local)
      return -1000;
   if((buy && h1Bias<=0) || (!buy && h1Bias>=0))
      return -1000;
   if((buy && h4Bias<0) || (!buy && h4Bias>0))
      return -1000;

   MqlTick tick;
   if(!SymbolInfoTick(Sym,tick))
      return -1000;
   if(atr<=0 || MathMax(0.0,tick.ask-tick.bid)>atr*MaxSpreadATRFraction)
      return -1000;

   double score=54;
   if(buy)
   {
      if(rsi>=54 && rsi<=64)
         score+=12;
      else if(rsi>=52 && rsi<=66)
         score+=7;
   }
   else
   {
      if(rsi>=36 && rsi<=46)
         score+=12;
      else if(rsi>=34 && rsi<=48)
         score+=7;
   }

   if(adx>=28)
      score+=12;
   else if(adx>=MinADX)
      score+=8;

   if(volumeRatio>=1.20)
      score+=12;
   else if(volumeRatio>=MinVolumeRatio)
      score+=7;

   if(bodyRatio>=0.60)
      score+=9;
   else if(bodyRatio>=MinBodyRatio)
      score+=5;

   return score;
}

void Consider(
   int dir,
   string setup,
   double score,
   double atr,
   int hour,
   double rsi,
   double adx,
   double volumeRatio,
   double bodyRatio,
   int h1Bias,
   int h4Bias,
   Candidate &candidate
)
{
   if(score<MinSignalScore)
      return;
   if(!RouteQuality(setup,dir,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias))
      return;

   string route;
   if(!Route(setup,dir,hour,route))
      return;
   if(!EdgeQuality(route,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias))
      return;

   if(candidate.dir==0 || score>candidate.score)
   {
      candidate.dir=dir;
      candidate.setup=setup;
      candidate.route=route;
      candidate.score=score;
      candidate.atr=atr;
   }
}

bool Signals(Candidate &best)
{
   Reset(best);
   int need=(int)MathMax(VolLen+10,MathMax(BreakoutLookback+10,SweepLookback+10));
   MqlRates rates[];
   if(!Rates(PERIOD_M15,need,rates))
      return false;

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

   double range=rates[1].high-rates[1].low;
   if(range<=0)
      return false;

   double bodyRatio=MathAbs(rates[1].close-rates[1].open)/range;
   double volumeSma=VolSma(rates,2,VolLen);
   double volumeRatio=volumeSma>0?(double)rates[1].tick_volume/volumeSma:0;
   int h1Bias=Bias(PERIOD_H1);
   int h4Bias=Bias(PERIOD_H4);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);

   Candidate buyCandidate;
   Candidate sellCandidate;
   Reset(buyCandidate);
   Reset(sellCandidate);

   double buyBase=BaseScore(true,rates,fast1,slow1,trend,rsi,adx,atr,volumeRatio,bodyRatio,h1Bias,h4Bias);
   double sellBase=BaseScore(false,rates,fast1,slow1,trend,rsi,adx,atr,volumeRatio,bodyRatio,h1Bias,h4Bias);

   if(EnableBuy && buyBase>0)
   {
      double previousHigh=HH(rates,2,BreakoutLookback);
      double previousLow=LL(rates,2,SweepLookback);

      if(rates[1].close>previousHigh && rates[1].close>rates[1].open && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(1,"BREAKOUT",buyBase+24,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);

      bool pullbackTouch=rates[1].low<=slow1+atr*PullbackTouchATR || rates[2].low<=slow1+atr*PullbackTouchATR;
      if(pullbackTouch && rates[1].close>fast1 && rates[1].close>rates[1].open && rsi>51 && rsi<66)
         Consider(1,"PULLBACK",buyBase+22,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);

      if(rates[1].close>rates[2].high && rates[2].close>rates[2].open && fast1>fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)
         Consider(1,"CONTINUATION",buyBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);

      if(h1Bias>0 && h4Bias>0 && rates[1].low<previousLow && rates[1].close>previousLow && rates[1].close>rates[1].open && rsi>47 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(1,"SWEEP",buyBase+23,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,buyCandidate);
   }

   if(EnableSell && sellBase>0)
   {
      double previousLow=LL(rates,2,BreakoutLookback);
      double previousHigh=HH(rates,2,SweepLookback);

      if(rates[1].close<previousLow && rates[1].close<rates[1].open && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"BREAKOUT",sellBase+24,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);

      bool pullbackTouch=rates[1].high>=slow1-atr*PullbackTouchATR || rates[2].high>=slow1-atr*PullbackTouchATR;
      if(pullbackTouch && rates[1].close<fast1 && rates[1].close<rates[1].open && rsi>34 && rsi<50)
         Consider(-1,"PULLBACK",sellBase+22,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);

      if(rates[1].close<rates[2].low && rates[2].close<rates[2].open && fast1<fast2 && bodyRatio>=0.38 && volumeRatio>=MinVolumeRatio)
         Consider(-1,"CONTINUATION",sellBase+18,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);

      if(h1Bias<0 && h4Bias<0 && rates[1].high>previousHigh && rates[1].close<previousHigh && rates[1].close<rates[1].open && rsi<53 && bodyRatio>=MinBodyRatio && volumeRatio>=MinVolumeRatio)
         Consider(-1,"SWEEP",sellBase+23,atr,now.hour,rsi,adx,volumeRatio,bodyRatio,h1Bias,h4Bias,sellCandidate);
   }

   if(buyCandidate.dir!=0 && sellCandidate.dir!=0)
   {
      if(MathAbs(buyCandidate.score-sellCandidate.score)<MinDirectionScoreGap)
         return false;
      best=buyCandidate.score>sellCandidate.score?buyCandidate:sellCandidate;
      return true;
   }

   if(buyCandidate.dir!=0)
   {
      best=buyCandidate;
      return true;
   }
   if(sellCandidate.dir!=0)
   {
      best=sellCandidate;
      return true;
   }
   return false;
}

bool Open(const Candidate &candidate)
{
   MqlTick tick;
   if(!SymbolInfoTick(Sym,tick))
      return false;

   double entry=Price(candidate.dir>0?tick.ask:tick.bid);
   double sl;
   double tp;
   if(!Stops(candidate.dir,entry,candidate.atr,candidate.setup,sl,tp))
      return false;

   double lot;
   double plannedRisk;
   double actualRisk;
   string direction=candidate.dir>0?"BUY":"SELL";
   if(!Size(candidate.dir,entry,sl,lot,plannedRisk,actualRisk))
   {
      J("RISK_SKIP",direction,candidate.setup,candidate.score,entry,candidate.atr,"route="+candidate.route);
      return false;
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   string comment="V30 "+direction+" "+candidate.setup;
   bool ok=candidate.dir>0
      ?trade.Buy(lot,Sym,0,sl,tp,comment)
      :trade.Sell(lot,Sym,0,sl,tp,comment);

   if(!ok)
   {
      J(
         "OPEN_RETRY",
         direction,
         candidate.setup,
         candidate.score,
         entry,
         candidate.atr,
         StringFormat("route=%s retcode=%u lot=%.2f",candidate.route,trade.ResultRetcode(),lot)
      );

      ok=candidate.dir>0
         ?trade.Buy(lot,Sym,0,0,0,comment+" retry")
         :trade.Sell(lot,Sym,0,0,0,comment+" retry");

      if(ok)
      {
         ulong ticket;
         if(!Position(ticket) || !PositionSelectByTicket(ticket))
            ok=false;
         else
         {
            double actualEntry=PositionGetDouble(POSITION_PRICE_OPEN);
            if(!Stops(candidate.dir,actualEntry,candidate.atr,candidate.setup,sl,tp) || !trade.PositionModify(Sym,sl,tp))
            {
               trade.PositionClose(Sym);
               ok=false;
            }
         }
      }
   }

   if(!ok)
   {
      J(
         "OPEN_FAIL",
         direction,
         candidate.setup,
         candidate.score,
         entry,
         candidate.atr,
         StringFormat("route=%s retcode=%u comment=%s",candidate.route,trade.ResultRetcode(),trade.ResultComment())
      );
      return false;
   }

   tradesToday++;
   lastEntryTime=TimeCurrent();
   activeATR=candidate.atr;
   activeSetup=candidate.setup;
   activeRoute=candidate.route;
   activeScore=candidate.score;
   activeRisk=plannedRisk;

   J(
      "OPEN_ENTRY",
      direction,
      candidate.setup,
      candidate.score,
      entry,
      candidate.atr,
      StringFormat(
         "natural_signal=true route=%s lot=%.2f planned_risk=%.2f actual_risk=%.2f risk_pct=%.3f",
         candidate.route,
         lot,
         plannedRisk,
         actualRisk,
         RiskPercent
      )
   );
   return true;
}

bool Close(string reason)
{
   ulong ticket;
   if(!Position(ticket) || !PositionSelectByTicket(ticket))
      return false;

   string direction=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";
   double price=PositionGetDouble(POSITION_PRICE_CURRENT);
   bool ok=trade.PositionClose(ticket);

   J(
      ok?"CLOSE_EVENT":"CLOSE_FAIL",
      direction,
      activeSetup,
      activeScore,
      price,
      activeATR,
      "reason="+reason+" route="+activeRoute
   );

   if(ok)
   {
      activeATR=0;
      activeSetup="";
      activeRoute="";
      activeScore=0;
      activeRisk=0;
   }
   return ok;
}

void Manage()
{
   ulong ticket;
   if(!Position(ticket) || !PositionSelectByTicket(ticket))
      return;

   long type=PositionGetInteger(POSITION_TYPE);
   bool buy=type==POSITION_TYPE_BUY;
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);

   MqlTick tick;
   if(!SymbolInfoTick(Sym,tick))
      return;

   double atr=activeATR;
   if(atr<=0 && (!One(aH,0,1,atr) || atr<=0))
      return;
   activeATR=atr;

   double marketPrice=buy?tick.bid:tick.ask;
   double favorableDistance=buy?marketPrice-openPrice:openPrice-marketPrice;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);

   if(HardDailyFlat())
   {
      Close("HARD_DAILY_FLAT");
      return;
   }
   if(CloseBeforeWeekend && now.day_of_week==5 && now.hour>=FridayCloseHour)
   {
      Close("WEEKEND_PROTECTION");
      return;
   }
   if(MaxHoldBars>0 && TimeCurrent()-openTime>=MaxHoldBars*900 && favorableDistance<atr*TimeExitMinProgressATR)
   {
      Close("TIME_STOP_NO_PROGRESS");
      return;
   }

   double desiredSl=sl;
   bool change=false;

   if(UseBreakEven && favorableDistance>=atr*BreakEvenTriggerATR)
   {
      double be=buy?openPrice+atr*BreakEvenOffsetATR:openPrice-atr*BreakEvenOffsetATR;
      if((buy && (sl==0 || be>desiredSl)) || (!buy && (sl==0 || be<desiredSl)))
      {
         desiredSl=be;
         change=true;
      }
   }

   if(UseTrailingStop && favorableDistance>=atr*TrailStartATR)
   {
      double trailing=buy?marketPrice-atr*TrailDistanceATR:marketPrice+atr*TrailDistanceATR;
      if((buy && (sl==0 || trailing>desiredSl)) || (!buy && (sl==0 || trailing<desiredSl)))
      {
         desiredSl=trailing;
         change=true;
      }
   }

   if(!change)
      return;

   desiredSl=Price(desiredSl);
   double minDistance=MinStop();
   if(buy)
   {
      if(desiredSl>=marketPrice-minDistance || (sl>0 && desiredSl<=sl+Tick()))
         return;
   }
   else
   {
      if(desiredSl<=marketPrice+minDistance || (sl>0 && desiredSl>=sl-Tick()))
         return;
   }

   if(trade.PositionModify(Sym,desiredSl,tp))
      J("STOP_UPDATE",buy?"BUY":"SELL",activeSetup,activeScore,marketPrice,atr,"v30_symmetric route="+activeRoute);
}

int OnInit()
{
   Sym=InpTradeSymbol==""?_Symbol:InpTradeSymbol;
   if(!SymbolSelect(Sym,true) || RiskPercent<=0 || RiskPercent>2)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(Sym);

   fH=iMA(Sym,PERIOD_M15,FastLen,0,MODE_EMA,PRICE_CLOSE);
   sH=iMA(Sym,PERIOD_M15,SlowLen,0,MODE_EMA,PRICE_CLOSE);
   tH=iMA(Sym,PERIOD_M15,TrendLen,0,MODE_EMA,PRICE_CLOSE);
   rH=iRSI(Sym,PERIOD_M15,RsiLen,PRICE_CLOSE);
   aH=iATR(Sym,PERIOD_M15,AtrLen);
   dH=iADX(Sym,PERIOD_M15,AdxLen);

   h1f=iMA(Sym,PERIOD_H1,BiasFastLen,0,MODE_EMA,PRICE_CLOSE);
   h1s=iMA(Sym,PERIOD_H1,BiasSlowLen,0,MODE_EMA,PRICE_CLOSE);
   h1r=iRSI(Sym,PERIOD_H1,RsiLen,PRICE_CLOSE);
   h4f=iMA(Sym,PERIOD_H4,BiasFastLen,0,MODE_EMA,PRICE_CLOSE);
   h4s=iMA(Sym,PERIOD_H4,BiasSlowLen,0,MODE_EMA,PRICE_CLOSE);
   h4r=iRSI(Sym,PERIOD_H4,RsiLen,PRICE_CLOSE);

   if(fH==INVALID_HANDLE || sH==INVALID_HANDLE || tH==INVALID_HANDLE || rH==INVALID_HANDLE || aH==INVALID_HANDLE || dH==INVALID_HANDLE ||
      h1f==INVALID_HANDLE || h1s==INVALID_HANDLE || h1r==INVALID_HANDLE || h4f==INVALID_HANDLE || h4s==INVALID_HANDLE || h4r==INVALID_HANDLE)
      return INIT_FAILED;

   ResetDay();
   J(
      "EA_START",
      "",
      "",
      0,
      0,
      0,
      "V30_SYMMETRIC_OPPORTUNITY_EXPANSION risk_normalized=true routes=CORE_PULLBACK_BUY_15|CORE_CONTINUATION_SELL_07_08|CORE_SWEEP_SELL_13_14|EDGE_PULLBACK_SELL_15|EDGE_CONTINUATION_BUY_07_08"
   );
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(fH);
   IndicatorRelease(sH);
   IndicatorRelease(tH);
   IndicatorRelease(rH);
   IndicatorRelease(aH);
   IndicatorRelease(dH);
   IndicatorRelease(h1f);
   IndicatorRelease(h1s);
   IndicatorRelease(h1r);
   IndicatorRelease(h4f);
   IndicatorRelease(h4s);
   IndicatorRelease(h4r);
}

void OnTick()
{
   ResetDay();
   Manage();

   ulong ticket;
   if(Position(ticket) || HardDailyFlat() || LastEntryPassed() || !SessionOpen() || tradesToday>=MaxTradesPerDay ||
      (lastEntryTime>0 && TimeCurrent()-lastEntryTime<CooldownMinutes*60) || !NewBar())
      return;

   Candidate candidate;
   if(Signals(candidate))
      Open(candidate);
}
