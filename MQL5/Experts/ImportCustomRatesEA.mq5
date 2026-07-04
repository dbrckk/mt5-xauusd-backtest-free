#property strict
#property version   "1.21"
#property description "Imports strict public M1 OHLC data into a leverage-aware custom MT5 symbol and validates symbol invariants."

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

   // Source prices are valid to 0.001. A coarser inherited tick size would
   // reject natural entries as Invalid price, so it is explicitly fixed.
   CustomSymbolSetDouble(InpCustomSymbol, SYMBOL_TRADE_TICK_SIZE, InpPoint);

   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_SPREAD_FLOAT, true);
   CustomSymbolSetInteger(InpCustomSymbol, SYMBOL_TRADE_MODE, SYMBOL_TRADE_MODE_FULL);

   // Apply tester leverage instead of requiring near-full notional margin.
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

bool ValidateSymbolInvariants(string &details)
{
   long calcMode = SymbolInfoInteger(InpCustomSymbol, SYMBOL_TRADE_CALC_MODE);
   double pointSize = SymbolInfoDouble(InpCustomSymbol, SYMBOL_POINT);
   double tickSize = SymbolInfoDouble(InpCustomSymbol, SYMBOL_TRADE_TICK_SIZE);
   double contractSize = SymbolInfoDouble(InpCustomSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double volumeMin = SymbolInfoDouble(InpCustomSymbol, SYMBOL_VOLUME_MIN);
   double volumeStep = SymbolInfoDouble(InpCustomSymbol, SYMBOL_VOLUME_STEP);

   double tolerance = MathMax(0.000000001, InpPoint * 0.0001);
   bool pointOk = MathAbs(pointSize - InpPoint) <= tolerance;
   bool tickOk = MathAbs(tickSize - InpPoint) <= tolerance;
   bool leverageModeOk = calcMode == SYMBOL_CALC_MODE_CFDLEVERAGE;
   bool contractOk = MathAbs(contractSize - 100.0) <= 0.000001;
   bool minLotOk = MathAbs(volumeMin - 0.01) <= 0.0000001;
   bool volumeStepOk = MathAbs(volumeStep - 0.01) <= 0.0000001;

   details =
      "calc_mode=" + IntegerToString((int)calcMode) +
      " point=" + DoubleToString(pointSize, InpDigits) +
      " tick_size=" + DoubleToString(tickSize, InpDigits) +
      " contract_size=" + DoubleToString(contractSize, 2) +
      " volume_min=" + DoubleToString(volumeMin, 2) +
      " volume_step=" + DoubleToString(volumeStep, 2);

   return pointOk && tickOk && leverageModeOk && contractOk && minLotOk && volumeStepOk;
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

   string invariantDetails = "";
   if(!ValidateSymbolInvariants(invariantDetails))
   {
      string invariantError = "IMPORT_FAILED symbol_invariant_error " + invariantDetails;
      Print(invariantError);
      WriteResult(invariantError);
      TerminalClose(5);
      return INIT_FAILED;
   }
   Print("SYMBOL_INVARIANTS_OK ", invariantDetails);

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

   // Revalidate after history import as a final guard against symbol metadata drift.
   invariantDetails = "";
   if(!ValidateSymbolInvariants(invariantDetails))
   {
      string invariantError = "IMPORT_FAILED post_import_symbol_invariant_error " + invariantDetails;
      Print(invariantError);
      WriteResult(invariantError);
      TerminalClose(6);
      return INIT_FAILED;
   }

   Print(
      "IMPORT_CUSTOM_RATES_DONE count=", count,
      " replaced=", replaced,
      " replaceError=", replaceError,
      " updated=", updated,
      " updateError=", updateError,
      " ", invariantDetails,
      " skippedNonIncreasing=", nonIncreasingRows
   );

   string result =
      "IMPORT_OK symbol=" + InpCustomSymbol +
      " bars=" + IntegerToString(count) +
      " from=" + TimeToString(fromTime) +
      " to=" + TimeToString(toTime) +
      " invariants=PASS " + invariantDetails +
      " skipped_non_increasing=" + IntegerToString(nonIncreasingRows);

   WriteResult(result);

   ChartSetSymbolPeriod(0, InpCustomSymbol, PERIOD_M1);
   TerminalClose(0);
   return INIT_SUCCEEDED;
}

void OnTick()
{
}
