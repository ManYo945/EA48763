//+------------------------------------------------------------------+
//| Grid Trader EA alpha v0.1.0 (adaptive + overnight + grid reset)  |
//| Combines:                                                        |
//|   • Adaptive grid (ATR‑based step, equity‑based layers)          |
//|   • Volatility pulse pause                                       |
//|   • Gradient lot sizing                                          |
//|   • Per‑order TP / optional SL                                   |
//|   • Overnight handling (close/all/keep buy/keep sell)            |
//|   • Flexible grid reset (daily time / periodic / price drift)    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//=== Base Inputs ==========================================================
input double BaseLot       = 0.01;   // base lot size (layer0)
input double GridStepPts   = 200;    // fallback static step (points)
input double GridSLPts     = 0;      // SL per grid order (points, 0=off)
input int    MaxLayers     = 6;      // fallback static max layers/side
input double BasketTP      = 1500;   // basket TP ($)
input double BasketSL      = 2500;   // basket SL ($)
input int    Magic         = 300;

//=== A) Dynamic Step (ATR) ===============================================
input bool   UseDynamicStep = true;
input ENUM_TIMEFRAMES ATR_TF = PERIOD_M15;
input int    ATR_Period     = 14;
input double ATR_Mult       = 1.0;   // step = ATR×mult
input int    MinStepPts     = 80;

//=== B) Dynamic Layers ====================================================
input bool   UseDynamicLayers = true;
input double RiskPerLayer     = 500; // USD equity per layer

//=== C) Pulse Pause (volatility spike) ====================================
input bool   UsePulsePause = true;
input double SpikeMult     = 2.0;    // atr_now > SpikeMult × atr_prev
input int    PauseMinutes  = 30;

//=== D) Gradient Lot ======================================================
input bool   UseGradientLot = true;
input double LotSlope      = 0.2;    // lot = BaseLot*(1+idx*LotSlope)

//=== Overnight Handling ===================================================
enum OvernightModeEnum
  {
   OV_CLOSE_ALL = 0,
   OV_DO_NOTHING,
   OV_KEEP_BUY,
   OV_KEEP_SELL
  };
input OvernightModeEnum OvernightMode = OV_DO_NOTHING;
input int  OvernightHour   = 23;     // trigger H:M
input int  OvernightMinute = 0;
input bool UseServerTime   = true;   // true=TimeCurrent, false=TimeLocal

//=== Grid Reset ===========================================================
enum ResetModeEnum
  {
   RESET_NONE = 0,
   RESET_DAILY_TIME,
   RESET_PERIOD_MINUTES,
   RESET_PRICE_DRIFT
  };
input ResetModeEnum  GridResetMode      = RESET_NONE;
input int            ResetHour          = 3;      // daily H:M
input int            ResetMinute        = 0;
input int            ResetPeriodMinutes = 1020;   // periodic cycle
input double         ResetDriftSteps    = 12;     // drift in steps

//==========================================================================
CTrade trade;
int      atrHandle = INVALID_HANDLE;
datetime pauseUntil = 0;

// overnight / reset helpers
static int      TodayOvernightHandled = -1;
static int      TodayResetHandled     = -1;
static datetime LastResetTime         = 0;
static double   AnchorPrice           = 0;

//=== Forward Declarations =================================================
int     CountPendings(ENUM_ORDER_TYPE t);
int     CountPositions(long dir);
void    PlaceLimit(bool buy,double price,int layerIdx);
void    CloseGrid();
void    ManageGrid();
void    CheckBasketClose();
void    CheckOvernight();
void    ExecuteOvernight();
void    CheckGridReset();
void    ExecuteGridReset();

datetime Now(){ return UseServerTime ? TimeCurrent() : TimeLocal(); }

//==========================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   atrHandle = iATR(_Symbol,ATR_TF,ATR_Period);
   AnchorPrice = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
   LastResetTime = Now();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int)
{
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   CloseGrid();
}

//==========================================================================
void OnTick()
{
   // volatility pause guard
   if(UsePulsePause && TimeCurrent()<pauseUntil) { CheckBasketClose(); CheckOvernight(); CheckGridReset(); return; }

   // detect spike
   double atrNow = 0, atrPrev = 0; static double atrLast = 0;
   if(UsePulsePause)
   {
      double buf[2];
      if(CopyBuffer(atrHandle,0,0,2,buf)==2)
      {
         atrNow  = buf[0];
         atrPrev = buf[1];
         if(atrPrev>0 && atrNow>SpikeMult*atrPrev)
         {
            pauseUntil = TimeCurrent()+PauseMinutes*60;
            Print("[PAUSE] Vol spike -> pause ",PauseMinutes," min");
         }
      }
   }

   ManageGrid();
   CheckBasketClose();
   CheckOvernight();
   CheckGridReset();
}

//-------------------------------------------------------------------------
//=== Helper calculations ==================================================

double GetATR()
{
   double val[];
   if(CopyBuffer(atrHandle,0,0,1,val)!=1) return 0;
   return val[0];
}

double GetGridStep()
{
   if(!UseDynamicStep) return GridStepPts;
   double atr = GetATR();
   double pts = ATR_Mult * atr / _Point;
   return MathMax(MinStepPts,pts);
}

int GetMaxLayers()
{
   if(!UseDynamicLayers) return MaxLayers;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int dyn = (int)MathFloor(equity / RiskPerLayer);
   return MathMax(1,MathMin(dyn,20));
}

//-------------------------------------------------------------------------
void ManageGrid()
{
   double step = GetGridStep();
   int maxL = GetMaxLayers();

   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double pt  = _Point;

   int buyLayer  = CountPositions(POSITION_TYPE_BUY)  + CountPendings(ORDER_TYPE_BUY_LIMIT);
   int sellLayer = CountPositions(POSITION_TYPE_SELL) + CountPendings(ORDER_TYPE_SELL_LIMIT);

   if(buyLayer==0)  PlaceLimit(true , ask - step*pt ,0);
   if(sellLayer==0) PlaceLimit(false, bid + step*pt ,0);

   for(int i=1;i<maxL;i++)
   {
      if(buyLayer  <= i-1) PlaceLimit(true , ask - (i+1)*step*pt ,i);
      if(sellLayer <= i-1) PlaceLimit(false, bid + (i+1)*step*pt ,i);
   }
}

void PlaceLimit(bool buy,double price,int layerIdx)
{
   int layers = buy ? CountPositions(POSITION_TYPE_BUY)+CountPendings(ORDER_TYPE_BUY_LIMIT)
                    : CountPositions(POSITION_TYPE_SELL)+CountPendings(ORDER_TYPE_SELL_LIMIT);
   if(layers>=GetMaxLayers()) return;

   double lot = UseGradientLot ? BaseLot*(1+layerIdx*LotSlope) : BaseLot;
   double step = GetGridStep();
   double tp   = buy ? price + step*_Point : price - step*_Point;
   double sl   = 0;
   if(GridSLPts>0)
      sl = buy ? price - GridSLPts*_Point : price + GridSLPts*_Point;

   bool ok = buy ? trade.BuyLimit (lot,price,_Symbol,sl,tp,0,0,"GridBuy")
                 : trade.SellLimit(lot,price,_Symbol,sl,tp,0,0,"GridSell");
   if(!ok) Print("[Grid] limit fail ",GetLastError());
}

//-------------------------------------------------------------------------
int CountPendings(ENUM_ORDER_TYPE type)
{
   int c=0;
   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=Magic || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)!=type) continue;
      c++;
   }
   return c;
}

int CountPositions(long dir)
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      if(PositionGetInteger(POSITION_MAGIC)!=Magic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE)!=dir) continue;
      c++;
   }
   return c;
}

//-------------------------------------------------------------------------
double BasketProfit()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
      if(PositionGetInteger(POSITION_MAGIC)==Magic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         p+=PositionGetDouble(POSITION_PROFIT);
   return p;
}

void CheckBasketClose()
{
   double pr=BasketProfit();
   if(pr>=BasketTP || pr<=-BasketSL) CloseGrid();
}

//-------------------------------------------------------------------------
void CheckOvernight()
{
   if(OvernightMode==OV_DO_NOTHING) return;

   datetime now = Now();
   MqlDateTime dt; TimeToStruct(now,dt);

   bool afterTrigger = (dt.hour>OvernightHour) || (dt.hour==OvernightHour && dt.min>=OvernightMinute);
   if(afterTrigger)
   {
      if(TodayOvernightHandled!=dt.day)
      {
         ExecuteOvernight();
         TodayOvernightHandled=dt.day;
      }
   }
   else if(dt.day!=TodayOvernightHandled)
      TodayOvernightHandled=-1; // reset flag for new day
}

void ExecuteOvernight()
{
   Print("[Grid] Overnight mode:",OvernightMode);

   // delete pendings
   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==Magic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }

   // handle positions
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      if(PositionGetInteger(POSITION_MAGIC)!=Magic || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long type = PositionGetInteger(POSITION_TYPE);

      bool needClose=false;
      if(OvernightMode==OV_CLOSE_ALL)                               needClose=true;
      else if(OvernightMode==OV_KEEP_BUY  && type==POSITION_TYPE_SELL) needClose=true;
      else if(OvernightMode==OV_KEEP_SELL && type==POSITION_TYPE_BUY ) needClose=true;

      if(needClose) trade.PositionClose(PositionGetTicket(i));
   }
}

//-------------------------------------------------------------------------
void CheckGridReset()
{
   if(GridResetMode==RESET_NONE) return;

   datetime now=Now();
   MqlDateTime dt; TimeToStruct(now,dt);

   bool doReset=false;
   switch(GridResetMode)
   {
      case RESET_DAILY_TIME:
         if(dt.hour>ResetHour || (dt.hour==ResetHour && dt.min>=ResetMinute))
         {
            if(TodayResetHandled!=dt.day) doReset=true;
         }
         else if(dt.day!=TodayResetHandled) TodayResetHandled=-1;
         break;
      case RESET_PERIOD_MINUTES:
         if((now-LastResetTime)>=ResetPeriodMinutes*60) doReset=true;
         break;
      case RESET_PRICE_DRIFT:
      {
         double mid=(SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
         double drift=MathAbs(mid-AnchorPrice);
         if(drift>=ResetDriftSteps*GetGridStep()*_Point) doReset=true;
         break;
      }
      default: break;
   }

   if(doReset) ExecuteGridReset();
}

void ExecuteGridReset()
{
   Print("[Grid] Grid reset triggered, mode:",GridResetMode);
   CloseGrid();

   AnchorPrice = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)+SymbolInfoDouble(_Symbol,SYMBOL_BID))*0.5;
   LastResetTime=Now();
   MqlDateTime dt; TimeToStruct(LastResetTime,dt);
   TodayResetHandled=dt.day;
}

//-------------------------------------------------------------------------
void CloseGrid()
{
   // close positions
   for(int i=PositionsTotal()-1;i>=0;--i)
      if(PositionGetInteger(POSITION_MAGIC)==Magic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         trade.PositionClose(PositionGetTicket(i));

   // delete orders
   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==Magic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }
}

//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//| v0.1.0 (2025‑05‑30)                                              |
//|   • Merge v0.1.0 adaptive grid with overnight & reset features    |
//|   • Added per‑order SL input (GridSLPts)                          |
//|   • Unified dynamic step/layers & gradient lots                  |
//|   • Refactored helper routines, central time selection           |
//+------------------------------------------------------------------+
