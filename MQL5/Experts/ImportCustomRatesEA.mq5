#property strict
#property version   "1.00"
#property description "Imports public M1 OHLC data into a custom MT5 symbol, then closes terminal."

input string InpCsvFile = "xau_public_m1.csv";
input string InpCustomSymbol = "XAU_PUBLIC";
input string InpCustomPath = "PublicData\\Metals";
input int    InpDigits = 3;
input double InpPoint = 0.001;

bool WriteResult(const string text)
{
   int h = FileOpen("import_custom_rates_result.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return false;
   FileWrite(h, text);
   FileClose(h);
   return true;
}

bool EnsureSymbol()
{
   ResetLastError();
   if(!CustomSymbolCreate(InpCustomSymbol, InpCustomPath, "XAUUSD"))
   {
      int err = GetLastError();
      if(err != 5304 && err != 5300)
         Print("CustomSymbolCreate failed: ", err);
   }

   CustomSymbolSetString(InpCustomSymbol, SYMBOL_DESCRIPTION, "Public XAUUSD M1 history");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_BASE, "XAU");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_PROFIT, "USD");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_MARGIN, "USD");
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_DIGITS, InpDigits);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_POINT, InpPoint);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_SPREAD_FLOAT, true);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_TRADE_CALC_MODE, SYMBOL_CALC_MODE_CFD);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_TRADE_CONTRACT_SIZE, 100.0);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_VOLUME_MIN, 0.01);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_VOLUME_MAX, 100.0);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_VOLUME_STEP, 0.01);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_CHART_MODE, SYMBOL_CHART_MODE_BID);

   if(!SymbolSelect(InpCustomSymbol, true))
   {
      Print("SymbolSelect failed: ", GetLastError());
      return false;
   }
   return true;
}

int OnInit()
{
   Print("IMPORT_CUSTOM_RATES_START file=", InpCsvFile, " symbol=", InpCustomSymbol);

   if(!EnsureSymbol())
   {
      WriteResult("IMPORT_FAILED symbol_setup_error");
      TerminalClose(2);
      return INIT_FAILED;
   }

   int h = FileOpen(InpCsvFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
   {
      int err = GetLastError();
      Print("FileOpen failed: ", err, " file=", InpCsvFile);
      WriteResult("IMPORT_FAILED file_open_error " + IntegerToString(err));
      TerminalClose(3);
      return INIT_FAILED;
   }

   // Header
   if(!FileIsEnding(h))
   {
      for(int i = 0; i < 8 && !FileIsLineEnding(h); i++)
         FileReadString(h);
   }

   MqlRates rates[];
   ArrayResize(rates, 0, 20000);
   int count = 0;

   while(!FileIsEnding(h))
   {
      string t = FileReadString(h);
      if(t == NULL || t == "")
      {
         if(!FileIsEnding(h))
            continue;
         break;
      }

      double o = FileReadNumber(h);
      double hi = FileReadNumber(h);
      double lo = FileReadNumber(h);
      double c = FileReadNumber(h);
      long tv = (long)FileReadNumber(h);
      int spread = (int)FileReadNumber(h);
      long rv = (long)FileReadNumber(h);

      datetime tm = StringToTime(t);
      if(tm <= 0 || o <= 0 || hi <= 0 || lo <= 0 || c <= 0)
         continue;

      ArrayResize(rates, count + 1, 20000);
      rates[count].time = tm;
      rates[count].open = o;
      rates[count].high = hi;
      rates[count].low = lo;
      rates[count].close = c;
      rates[count].tick_volume = tv;
      rates[count].spread = spread;
      rates[count].real_volume = rv;
      count++;
   }
   FileClose(h);

   if(count < 100)
   {
      Print("Not enough bars imported: ", count);
      WriteResult("IMPORT_FAILED not_enough_bars " + IntegerToString(count));
      TerminalClose(4);
      return INIT_FAILED;
   }

   ArraySetAsSeries(rates, false);
   datetime from_time = rates[0].time;
   datetime to_time = rates[count - 1].time;

   ResetLastError();
   int replaced = CustomRatesReplace(InpCustomSymbol, from_time, to_time, rates);
   int err1 = GetLastError();
   ResetLastError();
   int updated = CustomRatesUpdate(InpCustomSymbol, rates);
   int err2 = GetLastError();

   Print("IMPORT_CUSTOM_RATES_DONE count=", count, " replaced=", replaced, " err1=", err1, " updated=", updated, " err2=", err2);
   WriteResult("IMPORT_OK symbol=" + InpCustomSymbol + " bars=" + IntegerToString(count) + " from=" + TimeToString(from_time) + " to=" + TimeToString(to_time));

   ChartSetSymbolPeriod(0, InpCustomSymbol, PERIOD_M1);
   TerminalClose(0);
   return INIT_SUCCEEDED;
}

void OnTick() {}
