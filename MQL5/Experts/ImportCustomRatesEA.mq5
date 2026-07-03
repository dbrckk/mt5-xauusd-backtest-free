#property strict
#property version   "1.10"
#property description "Imports strict public M1 OHLC data into a leverage-aware custom MT5 symbol."

input string InpCsvFile = "xau_public_m1.csv";
input string InpCustomSymbol = "XAU_PUBLIC";
input string InpCustomPath = "PublicData\\Metals";
input int    InpDigits = 3;
input double InpPoint = 0.001;

bool WriteResult(const string text)
{
   int handle = FileOpen("import_custom_rates_result.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return false;

   FileWrite(handle, text);
   FileClose(handle);
   return true;
}

bool EnsureSymbol()
{
   ResetLastError();
   if(!CustomSymbolCreate(InpCustomSymbol, InpCustomPath, "XAUUSD"))
   {
      int errorCode = GetLastError();
      if(errorCode != 5304 && errorCode != 5300)
         Print("CustomSymbolCreate failed: ", errorCode);
   }

   CustomSymbolSetString(InpCustomSymbol, SYMBOL_DESCRIPTION, "Strict public XAUUSD M1 history");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_BASE, "XAU");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_PROFIT, "USD");
   CustomSymbolSetString(InpCustomSymbol, SYMBOL_CURRENCY_MARGIN, "USD");

   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_DIGITS, InpDigits);
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_POINT, InpPoint);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_SPREAD_FLOAT, true);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL);

   // Critical V27 fix: CFDLEVERAGE applies the tester account leverage.
   // The previous CFD mode required near-full notional margin and broke Y3.
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_TRADE_CALC_MODE, SYMBOL_CALC_MODE_CFDLEVERAGE);
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

   int handle = FileOpen(InpCsvFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
   {
      int errorCode = GetLastError();
      Print("FileOpen failed: ", errorCode, " file=", InpCsvFile);
      WriteResult("IMPORT_FAILED file_open_error " + IntegerToString(errorCode));
      TerminalClose(3);
      return INIT_FAILED;
   }

   if(!FileIsEnding(handle))
   {
      for(int i = 0; i < 8 && !FileIsLineEnding(handle); i++)
         FileReadString(handle);
   }

   MqlRates rates[];
   ArrayResize(rates, 0, 20000);
   int count = 0;
   datetime previousTime = 0;
   int nonIncreasingRows = 0;

   while(!FileIsEnding(handle))
   {
      string timestamp = FileReadString(handle);
      if(timestamp == NULL || timestamp == "")
      {
         if(!FileIsEnding(handle))
            continue;
         break;
      }

      double openPrice = FileReadNumber(handle);
      double highPrice = FileReadNumber(handle);
      double lowPrice = FileReadNumber(handle);
      double closePrice = FileReadNumber(handle);
      long tickVolume = (long)FileReadNumber(handle);
      int spread = (int)FileReadNumber(handle);
      long realVolume = (long)FileReadNumber(handle);

      datetime timeValue = StringToTime(timestamp);
      if(timeValue <= 0 || openPrice <= 0 || highPrice <= 0 || lowPrice <= 0 || closePrice <= 0)
         continue;

      if(previousTime > 0 && timeValue <= previousTime)
      {
         nonIncreasingRows++;
         continue;
      }

      if(highPrice < MathMax(openPrice, closePrice) || lowPrice > MathMin(openPrice, closePrice))
         continue;

      ArrayResize(rates, count + 1, 20000);
      rates[count].time = timeValue;
      rates[count].open = openPrice;
      rates[count].high = highPrice;
      rates[count].low = lowPrice;
      rates[count].close = closePrice;
      rates[count].tick_volume = tickVolume;
      rates[count].spread = spread;
      rates[count].real_volume = realVolume;

      previousTime = timeValue;
      count++;
   }

   FileClose(handle);

   if(count < 1000)
   {
      Print("Not enough real bars imported: ", count);
      WriteResult("IMPORT_FAILED not_enough_real_bars " + IntegerToString(count));
      TerminalClose(4);
      return INIT_FAILED;
   }

   ArraySetAsSeries(rates, false);
   datetime fromTime = rates[0].time;
   datetime toTime = rates[count - 1].time;

   ResetLastError();
   int replaced = CustomRatesReplace(InpCustomSymbol, fromTime, toTime, rates);
   int replaceError = GetLastError();

   ResetLastError();
   int updated = CustomRatesUpdate(InpCustomSymbol, rates);
   int updateError = GetLastError();

   long calcMode = SymbolInfoInteger(InpCustomSymbol, SYMBOL_TRADE_CALC_MODE);
   Print(
      "IMPORT_CUSTOM_RATES_DONE count=", count,
      " replaced=", replaced,
      " replaceError=", replaceError,
      " updated=", updated,
      " updateError=", updateError,
      " calcMode=", calcMode,
      " skippedNonIncreasing=", nonIncreasingRows
   );

   string result =
      "IMPORT_OK symbol=" + InpCustomSymbol +
      " bars=" + IntegerToString(count) +
      " from=" + TimeToString(fromTime) +
      " to=" + TimeToString(toTime) +
      " calc_mode=" + IntegerToString((int)calcMode) +
      " skipped_non_increasing=" + IntegerToString(nonIncreasingRows);

   WriteResult(result);

   ChartSetSymbolPeriod(0, InpCustomSymbol, PERIOD_M1);
   TerminalClose(0);
   return INIT_SUCCEEDED;
}

void OnTick()
{
}
