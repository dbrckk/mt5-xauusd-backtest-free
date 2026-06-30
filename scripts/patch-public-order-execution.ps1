$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repo = (Resolve-Path ".").Path
$reports = Join-Path $repo "reports"
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$eaSource = "MQL5/Experts/QuantumQueenStyle_XAU_Grid_PRO_V17_10K_PROFITASYMMETRY.mq5"
if (!(Test-Path $eaSource)) { throw "EA source not found: $eaSource" }

$txt = Get-Content -Path $eaSource -Raw

if (-not $txt.Contains("public_v24_market_execution_retry_marker")) {
  $start = $txt.IndexOf("bool OpenMarketOrder(int direction, double atr)")
  if ($start -lt 0) { throw "OpenMarketOrder start not found." }
  $end = $txt.IndexOf("int Signal(double &atr)", $start)
  if ($end -lt 0) { throw "OpenMarketOrder end marker not found." }

  $newFunction = @'
bool OpenMarketOrder(int direction, double atr)
{
   // public_v24_market_execution_retry_marker
   if(direction == 0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return false;

   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   double rawPrice = (direction > 0 ? tick.ask : tick.bid);
   double volume = NormalizedLot();
   string side = (direction > 0 ? "BUY" : "SELL");

   ENUM_ORDER_TYPE_FILLING fillings[3];
   fillings[0] = ORDER_FILLING_FOK;
   fillings[1] = ORDER_FILLING_IOC;
   fillings[2] = ORDER_FILLING_RETURN;

   double prices[2];
   prices[0] = NormalizeDouble(rawPrice, digits);
   prices[1] = 0.0;

   for(int p = 0; p < 2; p++)
   {
      for(int f = 0; f < 3; f++)
      {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action = TRADE_ACTION_DEAL;
         request.symbol = g_symbol;
         request.magic = InpMagic;
         request.volume = volume;
         request.type = (direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         request.price = prices[p];
         request.sl = 0.0;
         request.tp = 0.0;
         request.deviation = 100000;
         request.type_filling = fillings[f];
         request.type_time = ORDER_TIME_GTC;
         request.comment = (direction > 0 ? "Master V24 BUY" : "Master V24 SELL");

         bool ok = OrderSend(request, result);
         string details = StringFormat("%s retcode=%u price=%.5f sl=%.5f tp=%.5f atr=%.5f fill=%d attempt=%d",
                                      side, result.retcode, request.price, request.sl, request.tp, atr, (int)request.type_filling, p * 3 + f + 1);

         if(ok && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED))
         {
            Journal("OPEN_ENTRY", details);
            DebugLog("OPEN_ENTRY " + details);
            g_lastEntryTime = TimeCurrent();
            g_entriesToday++;
            return true;
         }

         Journal("OPEN_FAIL", details);
         DebugLog("OPEN_FAIL " + details);
      }
   }

   return false;
}

'@
  $txt = $txt.Substring(0, $start) + $newFunction + $txt.Substring($end)
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_no_sl_orders=true"
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v24_market_execution_retry=true"
}

if (-not $txt.Contains("public_v25_intraday_exit_manager_marker")) {
  $insertAt = $txt.IndexOf("void OnTick()")
  if ($insertAt -lt 0) { throw "OnTick marker not found." }

  $exitCode = @'

bool ClosePublicPosition(ulong ticket, string reason)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   long positionType = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return false;

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = g_symbol;
   request.magic = InpMagic;
   request.volume = volume;
   request.type = (positionType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   request.price = (positionType == POSITION_TYPE_BUY ? tick.bid : tick.ask);
   request.deviation = 100000;
   request.type_filling = ORDER_FILLING_FOK;
   request.type_time = ORDER_TIME_GTC;
   request.comment = reason;

   bool ok = OrderSend(request, result);
   Journal(ok ? reason : "PUBLIC_EXIT_FAIL", StringFormat("ticket=%I64u retcode=%u price=%.5f", ticket, result.retcode, request.price));
   return ok && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_DONE_PARTIAL || result.retcode == TRADE_RETCODE_PLACED);
}

void ManagePublicIntradayExits()
{
   // public_v25_intraday_exit_manager_marker
   if(g_symbol != "XAU_PUBLIC") return;
   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick)) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int heldMinutes = (int)((TimeCurrent() - openTime) / 60);
      double nowPrice = (type == POSITION_TYPE_BUY ? tick.bid : tick.ask);
      double points = (type == POSITION_TYPE_BUY ? nowPrice - openPrice : openPrice - nowPrice);

      if(points >= 25.0)
      {
         ClosePublicPosition(ticket, "PUBLIC_TP_25_POINTS");
         continue;
      }
      if(points <= -35.0)
      {
         ClosePublicPosition(ticket, "PUBLIC_SL_35_POINTS");
         continue;
      }
      if(heldMinutes >= 240 && points >= 5.0)
      {
         ClosePublicPosition(ticket, "PUBLIC_TIME_PROFIT_EXIT");
         continue;
      }
      if(heldMinutes >= 360)
      {
         ClosePublicPosition(ticket, "PUBLIC_MAX_TIME_EXIT");
         continue;
      }
      if(dt.hour >= 16 && dt.min >= 45)
      {
         ClosePublicPosition(ticket, "PUBLIC_SESSION_END_EXIT");
         continue;
      }
   }
}

'@
  $txt = $txt.Substring(0, $insertAt) + $exitCode + $txt.Substring($insertAt)

  $oldOnTick = "void OnTick()`r`n{`r`n    if(!Ready() || !NewBar()) return;"
  if (-not $txt.Contains($oldOnTick)) {
    $oldOnTick = "void OnTick()`n{`n    if(!Ready() || !NewBar()) return;"
  }
  if ($txt.Contains($oldOnTick)) {
    $txt = $txt.Replace($oldOnTick, "void OnTick()`r`n{`r`n    ManagePublicIntradayExits();`r`n    if(!Ready() || !NewBar()) return;")
  } else {
    $oldOnTickLoose = "void OnTick()`r`n{"
    if (-not $txt.Contains($oldOnTickLoose)) { $oldOnTickLoose = "void OnTick()`n{" }
    if (!$txt.Contains($oldOnTickLoose)) { throw "OnTick body marker not found." }
    $txt = $txt.Replace($oldOnTickLoose, "void OnTick()`r`n{`r`n    ManagePublicIntradayExits();")
  }

  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v25_intraday_exit_manager=true"
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v25_tp_points=25"
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v25_sl_points=35"
  Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v25_max_hold_minutes=360"
}

Set-Content -Path $eaSource -Value $txt -Encoding UTF8
Add-Content -Path (Join-Path $reports "CURRENT_PUBLIC_XAU_ONLY.txt") -Value "public_v23_order_execution_patch=true"
Write-Host "V25 public order execution and intraday exit patch applied."
