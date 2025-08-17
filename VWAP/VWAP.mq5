//+------------------------------------------------------------------+
//|   VWAP Dual-Mode EA v0.2.0 (2025-08-18, MQL5)                   |
//|   • Mean-Reversion or Breakout selectable by input.             |
//+------------------------------------------------------------------+
#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "0.2.0"
#property strict

#include <Trade/Trade.mqh>

//‑‑‑ User Inputs --------------------------------------------------------------
input ENUM_TIMEFRAMES TF          = PERIOD_M15;     // Working timeframe
input double        DeviationPts  = 600;           // Entry threshold (points)
input double        StopLossPts   = 700;           // Stop‑loss distance (points)
input double        Lots          = 0.01;          // Lot size per entry
input int           MaxPositions  = 2;             // Max simultaneous positions
input int           MaxTradesDay  = 10;             // Max new trades per day
input uint          MagicNumber   = 300;      // Unique magic number
input bool          TimeFilter    = true;         // Enable trading window
input int           StartHour     = 6;
input int           StartMin      = 0;
input int           EndHour       = 16;
input int           EndMin        = 30;
input bool          ShowVolHist   = true;         // Draw volume histogram bars

// ▼ New: strategy mode
enum ENUM_STRAT_MODE { MODE_MEAN_REVERSION=0, MODE_BREAKOUT=1 };
input ENUM_STRAT_MODE Mode = MODE_BREAKOUT;   // Trading logic mode
input double        RR            = 1.32;           // Breakout TP = RR * StopLossPts

//‑‑‑ Globals ------------------------------------------------------------------
CTrade   trade;
datetime last_bar_time = 0;

double   cumPV  = 0.0;
long     cumVol = 0;
int      trading_day  = -1;  // YYYYMMDD
int      trades_today = 0;

#define VWAP_LINE  "VWAP_line"
#define VOL_PREFIX "VOL_"
#define ARROW_UP    233      // Wingdings up arrow
#define ARROW_DOWN  234      // Wingdings down arrow

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber((ulong)MagicNumber);
   if(ObjectFind(0, VWAP_LINE) < 0)
   {
      ObjectCreate(0, VWAP_LINE, OBJ_HLINE, 0, 0, 0);
      ObjectSetInteger(0, VWAP_LINE, OBJPROP_COLOR, clrOrangeRed);
      ObjectSetInteger(0, VWAP_LINE, OBJPROP_WIDTH, 2);
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){}


//+------------------------------------------------------------------+
//| Compatibility helpers                                            |
//+------------------------------------------------------------------+
bool SelectPositionByIndexCompat(int index, ulong &ticket_out)
{
   ticket_out = PositionGetTicket(index);
   if(ticket_out==0) return false;
   return PositionSelectByTicket(ticket_out);
}


//‑‑‑ Utility: close EA positions --------------------------------------------
void CloseMyPositions()
{
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      // ulong ticket = PositionGetTicket(i);
      // if(ticket==0)              continue;
      // if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      // if(PositionGetString (POSITION_SYMBOL)!=_Symbol)     continue;
      // trade.PositionClose(ticket);
      
      ulong ticket;
      if(!SelectPositionByIndexCompat(i, ticket)) continue;

      if((uint)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)          continue;

      trade.PositionClose(ticket);
   }
}

//‑‑‑ Utility: count open positions ------------------------------------------
int MyOpenPositions()
{
   int cnt = 0;
   // for(int i = PositionsTotal() - 1; i >= 0; --i)
   // {
   //    ulong ticket = PositionGetTicket(i);
   //    if(ticket==0) continue;

   //    // MT5 build < 2000 may not expose PositionSelectByIndex; use ticket fallback
   // #ifdef __MQL5__
   //    #ifdef PositionSelectByIndex
   //       if(!PositionSelectByIndex(i))
   //          continue;
   //    #else
   //       if(!PositionSelectByTicket(ticket))
   //          continue;
   //    #endif
   // #else
   //    if(!PositionSelectByTicket(ticket))
   //       continue;
   // #endif

   //    if(PositionGetInteger(POSITION_MAGIC)  != (long)MagicNumber) continue;
   //    if(PositionGetString (POSITION_SYMBOL) != _Symbol)           continue;
   //    cnt++;
   // }

   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket;
      if(!SelectPositionByIndexCompat(i, ticket)) continue;

      if((uint)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)          continue;

      cnt++;
   }
   return cnt;
}


//‑‑‑ Utility: trading window --------------------------------------------------
bool InTradingWindow()
{
   if(!TimeFilter) return true;
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   int now   = tm.hour*60 + tm.min;
   int start = StartHour*60 + StartMin;
   int end   = EndHour  *60 + EndMin;
   bool ok   = (end>start) ? (now>=start && now<end) : (now>=start || now<end);
   if(!ok) CloseMyPositions();
   return ok;
}

//‑‑‑ Draw simple volume bar (OBJ_TREND) --------------------------------------
void DrawVolumeBar(datetime bar_time, long volume)
{
   if(!ShowVolHist) return;
   string id = VOL_PREFIX + IntegerToString((long)bar_time);
   if(ObjectFind(0, id) >= 0) return; // already exists

   // Use current bid as baseline to avoid plotting at zero level
   double base = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double top  = base + volume * _Point * 0.1; // scale factor for visibility
   datetime t2 = bar_time + PeriodSeconds(TF)/2;

   ObjectCreate(0, id, OBJ_TREND, 0, bar_time, base, t2, top);
   ObjectSetInteger(0, id, OBJPROP_COLOR, clrSteelBlue);
   ObjectSetInteger(0, id, OBJPROP_WIDTH, 2);
}

//‑‑‑ Draw entry arrow ---------------------------------------------------------
void DrawMarker(bool isBuy, double price)
{
   string name = (isBuy?"BUY_":"SELL_") + TimeToString(TimeCurrent(), TIME_SECONDS);
   int arrow   = isBuy ? ARROW_DOWN : ARROW_UP;
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//─── Helpers: SL/TP calculation ────────────────────────────────────
double ComputeSL(bool isBuy, double entry_price)
{
   double sl = entry_price + (isBuy ? -1.0 : +1.0) * StopLossPts * _Point;
   return NormalizeDouble(sl, _Digits);
}

double ComputeTP(bool isBuy, double entry_price, double vwap_current)
{
   if(Mode==MODE_MEAN_REVERSION)
   {
      return NormalizeDouble(vwap_current, _Digits);
   }
   // Breakout: RR * StopLossPts from entry
   double tp = entry_price + (isBuy ? +1.0 : -1.0) * (RR * StopLossPts) * _Point;
   return NormalizeDouble(tp, _Digits);
}

void CloseIfRevertToVWAP(double vwap, double close1)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket;
      if(!SelectPositionByIndexCompat(i, ticket)) continue;

      if((uint)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)          continue;

      long type = (long)PositionGetInteger(POSITION_TYPE);
      if( (type==POSITION_TYPE_BUY  && close1 >= vwap) ||
          (type==POSITION_TYPE_SELL && close1 <= vwap) )
      {
         trade.PositionClose(ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!InTradingWindow()) return;

   datetime cur_bar = iTime(_Symbol, TF, 0);
   if(cur_bar == last_bar_time) return; // process only once per bar
   last_bar_time = cur_bar;

   // Previous bar data (index 1)
   double high1  = iHigh (_Symbol, TF, 1);
   double low1   = iLow  (_Symbol, TF, 1);
   double close1 = iClose(_Symbol, TF, 1);
   long   vol1   = (long)iVolume(_Symbol, TF, 1);

   // Day rollover
   MqlDateTime tm_bar; TimeToStruct(cur_bar, tm_bar);
   int yyyymmdd = tm_bar.year*10000 + tm_bar.mon*100 + tm_bar.day;
   if(yyyymmdd != trading_day)
   {
      trading_day  = yyyymmdd;
      cumPV = 0.0; cumVol = 0; trades_today = 0;
   }

   // VWAP update
   double typical = (high1 + low1 + close1) / 3.0;
   cumPV  += typical * vol1;
   cumVol += vol1;
   if(cumVol == 0) return;
   double vwap = cumPV / (double)cumVol;

   ObjectSetDouble(0, VWAP_LINE, OBJPROP_PRICE, vwap);
   DrawVolumeBar(cur_bar, vol1);

   // HUD comment
   double deviation_pts = (close1 - vwap) / _Point;
   int myPos = MyOpenPositions();
   Comment(StringFormat("VWAP: %.5f\nPrice: %.5f\nVolume: %ld\nDeviation: %.1f pts\nNow position: %d\n coda: %d/%d", vwap, close1, vol1, deviation_pts, myPos, trades_today, MaxTradesDay));

   // Guard: position & trade limits
   if(myPos >= MaxPositions) return;
   if(trades_today    >= MaxTradesDay)  return;

   // Prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ── Entry conditions ───────────────────────────────────────────
   bool fireBuy=false, fireSell=false;

   if(Mode==MODE_MEAN_REVERSION)
   {
      // Mean reversion: fade distance to VWAP
      if(deviation_pts < -DeviationPts) fireBuy  = true;  // price << vwap
      if(deviation_pts > +DeviationPts) fireSell = true;  // price >> vwap
   }
   else // MODE_BREAKOUT
   {
      // Breakout: follow distance from VWAP
      if(deviation_pts > +DeviationPts) fireBuy  = true;  // strength continues
      if(deviation_pts < -DeviationPts) fireSell = true;  // weakness continues
   }

   
   // Buy
   if(fireBuy)
   {
      double entry = ask;
      double sl = ComputeSL(true, entry);
      double tp = ComputeTP(true, entry, vwap);
      if(trade.Buy(Lots, _Symbol, entry, sl, tp, Mode==MODE_MEAN_REVERSION?"VWAP Buy MR":"VWAP Buy BO"))
      {
         trades_today++;
         DrawMarker(true, vwap);
      }
   }

   // Sell
   if(fireSell)
   {
      double entry = bid;
      double sl = ComputeSL(false, entry);
      double tp = ComputeTP(false, entry, vwap);
      if(trade.Sell(Lots, _Symbol, entry, sl, tp, Mode==MODE_MEAN_REVERSION?"VWAP Sell MR":"VWAP Sell BO"))
      {
         trades_today++;
         DrawMarker(false, vwap);
      }
   }

   // Exits
   if(Mode==MODE_MEAN_REVERSION)
      CloseIfRevertToVWAP(vwap, close1); // Breakout uses SL/TP only

   // // Entry conditions
   // if(deviation_pts < -DeviationPts)
   // {
   //    double sl = NormalizeDouble(bid - StopLossPts * _Point, _Digits);
   //    double tp = NormalizeDouble(vwap, _Digits);
   //    if(trade.Buy(Lots, _Symbol, ask, sl, tp, "VWAP Buy"))
   //    {
   //       trades_today++;
   //       DrawMarker(true, vwap);
   //    }
   // }
   // else if(deviation_pts > DeviationPts)
   // {
   //    double sl = NormalizeDouble(ask + StopLossPts * _Point, _Digits);
   //    double tp = NormalizeDouble(vwap, _Digits);
   //    if(trade.Sell(Lots, _Symbol, bid, sl, tp, "VWAP Sell"))
   //    {
   //       trades_today++;
   //       DrawMarker(false, vwap);
   //    }
   // }

   // // Exit logic: close when price reverts to VWAP
   // for(int i = PositionsTotal()-1; i>=0; --i)
   // {
   //    if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
   //    long type = PositionGetInteger(POSITION_TYPE);
   //    if((type==POSITION_TYPE_BUY  && close1 >= vwap) ||
   //       (type==POSITION_TYPE_SELL && close1 <= vwap))
   //       trade.PositionClose(PositionGetTicket(i));
   // }
}

//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//| v0.2.0 (2025-08-18) Added dual mode: Mean-Reversion & Breakout. |
//| TP for Breakout = RR * StopLossPts from entry; MR keeps TP=VWAP. |
//| Cleaned position iteration with PositionSelectByIndex.           |
//+------------------------------------------------------------------+
