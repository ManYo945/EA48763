//+------------------------------------------------------------------+
//|        VWAP Mean‑Reversion EA v0.1.1 (2025‑05‑09, MQL5)         |
//|      ● Reset the input variables to default values.             |
//+------------------------------------------------------------------+
#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "0.1.1"
#property strict

#include <Trade/Trade.mqh>

//‑‑‑ User Inputs --------------------------------------------------------------
input ENUM_TIMEFRAMES TF          = PERIOD_M1;     // Working timeframe
input double        DeviationPts  = 500;           // Entry threshold (points)
input double        StopLossPts   = 800;           // Stop‑loss distance (points)
input double        Lots          = 0.01;          // Lot size per entry
input int           MaxPositions  = 2;             // Max simultaneous positions
input int           MaxTradesDay  = 8;             // Max new trades per day
input uint          MagicNumber   = 300;      // Unique magic number
input bool          TimeFilter    = false;         // Enable trading window
input int           StartHour     = 1;
input int           StartMin      = 0;
input int           EndHour       = 23;
input int           EndMin        = 0;
input bool          ShowVolHist   = false;         // Draw volume histogram bars

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

//‑‑‑ Utility: close EA positions --------------------------------------------
void CloseMyPositions()
{
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0)              continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString (POSITION_SYMBOL)!=_Symbol)     continue;
      trade.PositionClose(ticket);
   }
}

//‑‑‑ Utility: count open positions ------------------------------------------
int MyOpenPositions()
{
   int cnt = 0;
   for(int i=PositionsTotal()-1;i>=0;--i)
      if(PositionGetInteger(POSITION_MAGIC)==MagicNumber && PositionGetString(POSITION_SYMBOL)==_Symbol)
         cnt++;
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

//+------------------------------------------------------------------+
//| Main logic (runs once per new bar)                               |
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
   Comment(StringFormat("VWAP: %.5f\nPrice: %.5f\nVolume: %ld\nDeviation: %.1f pts", vwap, close1, vol1, deviation_pts));

   // Guard: position & trade limits
   if(MyOpenPositions() >= MaxPositions) return;
   if(trades_today    >= MaxTradesDay)  return;

   // Prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Entry conditions
   if(deviation_pts < -DeviationPts)
   {
      double sl = NormalizeDouble(bid - StopLossPts * _Point, _Digits);
      double tp = NormalizeDouble(vwap, _Digits);
      if(trade.Buy(Lots, _Symbol, ask, sl, tp, "VWAP Buy"))
      {
         trades_today++;
         DrawMarker(true, vwap);
      }
   }
   else if(deviation_pts > DeviationPts)
   {
      double sl = NormalizeDouble(ask + StopLossPts * _Point, _Digits);
      double tp = NormalizeDouble(vwap, _Digits);
      if(trade.Sell(Lots, _Symbol, bid, sl, tp, "VWAP Sell"))
      {
         trades_today++;
         DrawMarker(false, vwap);
      }
   }

   // Exit logic: close when price reverts to VWAP
   for(int i = PositionsTotal()-1; i>=0; --i)
   {
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if((type==POSITION_TYPE_BUY  && close1 >= vwap) ||
         (type==POSITION_TYPE_SELL && close1 <= vwap))
         trade.PositionClose(PositionGetTicket(i));
   }
}

//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//| v0.1.0 (2025‑05‑09)                                              |
//|  • New EA based on VWAP mean‑reversion strategy                  |
//+------------------------------------------------------------------+
