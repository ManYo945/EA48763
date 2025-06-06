//+------------------------------------------------------------------+
//|      SAR Counter‑Trend EA v1.1.1 (TimeWindow + Clean Visuals)   |
//|   • fixed the time window filter to work correctly               |
//+------------------------------------------------------------------+
#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "1.1.1"
#property strict

#include <Trade/Trade.mqh>

//‑‑‑ Inputs --------------------------------------------------------------
input bool   CounterLogic   = true;   // Counter logic for SAR
input double InpStopLoss    = 700;    // SL (points)
input double InpTakeProfit  = 950;    // TP (points)
input double InpLots        = 0.01;   // Lot size
input double InpStep        = 0.585;  // SAR step
input double InpMaximum     = 0.74;   // SAR max
input ENUM_TIMEFRAMES period = PERIOD_CURRENT;
input int    magicNumber    = 100;

//— Trading‑window filter
input bool TimeFilter = false;        // Enable trading window
input int  StartHour  = 0,  StartMin = 30;
input int  EndHour    = 23, EndMin   = 30;

//— Visuals
input color  BuyArrowColor  = clrLime;
input color  SellArrowColor = clrRed;

//‑‑‑ Globals --------------------------------------------------------------
int   sar_handle = INVALID_HANDLE;
int   barsTotal  = 0;
CTrade trade;

//+------------------------------------------------------------------+
int OnInit()
{
   sar_handle = iSAR(_Symbol, period, InpStep, InpMaximum);
   if(sar_handle == INVALID_HANDLE)
   { Print("[INIT ERROR] Cannot create SAR: ",GetLastError()); return INIT_FAILED; }
   ChartIndicatorAdd(0, 0, sar_handle);

   barsTotal = iBars(_Symbol, period);
   trade.SetExpertMagicNumber(magicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(sar_handle!=INVALID_HANDLE) IndicatorRelease(sar_handle);
}

//‑‑‑ Trading‑window helper -----------------------------------------------
bool InTimeWindow()
{
   if(!TimeFilter) return true;
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   int now  = tm.hour*60 + tm.min;
   int start= StartHour*60 + StartMin;
   int end  = EndHour  *60 + EndMin;
   bool ok  = (end>start)? (now>=start && now<end) : (now>=start || now<end);
   return ok;
}

//‑‑‑ Close EA positions ---------------------------------------------------
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=magicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      trade.PositionClose(ticket);
   }
}

//‑‑‑ Draw entry arrow ------------------------------------------------------
void DrawArrow(bool isBuy,double price)
{
   string name=(isBuy?"BUY_":"SELL_")+TimeToString(TimeCurrent(),TIME_SECONDS);
   ObjectCreate(0,name,OBJ_ARROW,0,TimeCurrent(),price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,isBuy?234:233); // down/up
   ObjectSetInteger(0,name,OBJPROP_COLOR,isBuy?BuyArrowColor:SellArrowColor);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
}

//‑‑‑ Core trading ----------------------------------------------------------
void OnTick()
{
   // if not in trading window, flatten all EA positions and exit
   if(!InTimeWindow())
   {
      CloseAllPositions();
      Comment("[INFO] Outside trading hours");
      return;
   }

   int bars=iBars(_Symbol,period);
   if(barsTotal==bars) return;           // one pass per bar

   double sar[2];
   if(CopyBuffer(sar_handle,0,0,2,sar)!=2) return; // SAR not ready

   double closePrev=iClose(_Symbol,period,1);
   double highCurr =iHigh (_Symbol,period,0);
   double lowCurr  =iLow  (_Symbol,period,0);

   bool buySig, sellSig;
   if(CounterLogic)
   { buySig=(sar[1]>closePrev && sar[0]<highCurr); sellSig=(sar[1]<closePrev && sar[0]>lowCurr); }
   else
   { buySig=(sar[1]<closePrev && sar[0]>lowCurr);  sellSig=(sar[1]>closePrev && sar[0]<highCurr); }

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   if(buySig)
   {
      CloseAllPositions();
      double sl=NormalizeDouble(ask-InpStopLoss*_Point,_Digits);
      double tp=NormalizeDouble(ask+InpTakeProfit*_Point,_Digits);
      if(trade.Buy(InpLots,_Symbol,0,sl,tp,"SAR Buy")) DrawArrow(true,ask);
      barsTotal=bars;
   }
   else if(sellSig)
   {
      CloseAllPositions();
      double sl=NormalizeDouble(bid+InpStopLoss*_Point,_Digits);
      double tp=NormalizeDouble(bid-InpTakeProfit*_Point,_Digits);
      if(trade.Sell(InpLots,_Symbol,0,sl,tp,"SAR Sell")) DrawArrow(false,bid);
      barsTotal=bars;
   }
}

//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//| v1.1.1 (2025‑05‑17)                                              |
//|   • fixed the time window filter to work correctly             |
//+------------------------------------------------------------------+
