//+------------------------------------------------------------------+
//| Grid Trader EA v0.1.0  (safer grid)                               |
//| • MaxPosPerSide 限制持倉層數，防爆倉                             |
//| • 每格自帶 TP = GridStepPts（獨立獲利了結）                      |
//| • 若已達上限則不再新掛單                                        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

//=== Inputs ===============================================================
input double BaseLot      = 0.01;  // first lot size
input int    MaxLayers    = 2;     // 最大網格層數（每邊持倉 + 掛單 總數）
input double GridStepPts  = 160;   // grid step (points)
input double BasketTP     = 1500;  // 全籃 TP ($)
input double BasketSL     = 2500;  // 全籃 SL ($)
input int    Magic        = 400;   // magic number

CTrade trade;

//=== Helper ===============================================================
int  CountPendings(ENUM_ORDER_TYPE type);
int  CountPositions(long dir);
void PlaceLimit(bool buy,double price);
void CloseGrid();

//==========================================================================
int OnInit(){ trade.SetExpertMagicNumber(Magic); return INIT_SUCCEEDED; }
void OnDeinit(const int){ CloseGrid(); }

void OnTick()
{
   ManageGrid();
   CheckBasketClose();
}

//-------------------------------------------------------------------------
void ManageGrid()
{
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double pt  = _Point;

   // 當前層數（含已成交持倉 + 掛單）
   int buyLayer  = CountPositions(POSITION_TYPE_BUY)  + CountPendings(ORDER_TYPE_BUY_LIMIT);
   int sellLayer = CountPositions(POSITION_TYPE_SELL) + CountPendings(ORDER_TYPE_SELL_LIMIT);

   // 初始掛單
   if(buyLayer==0)  PlaceLimit(true , ask - GridStepPts*pt);
   if(sellLayer==0) PlaceLimit(false, bid + GridStepPts*pt);

   // 逐層遞增，但不超過 MaxLayers
   for(int i=1;i<MaxLayers;i++)
   {
      if(buyLayer <= i-1)  PlaceLimit(true , ask - (i+1)*GridStepPts*pt);
      if(sellLayer<= i-1)  PlaceLimit(false, bid + (i+1)*GridStepPts*pt);
   }
}

void PlaceLimit(bool buy,double price)
{
   // 檢查層數限制
   int layers = buy ? CountPositions(POSITION_TYPE_BUY)+CountPendings(ORDER_TYPE_BUY_LIMIT)
                    : CountPositions(POSITION_TYPE_SELL)+CountPendings(ORDER_TYPE_SELL_LIMIT);
   if(layers>=MaxLayers) return;

   double lot=BaseLot;
   double tp = buy ? price + GridStepPts*_Point : price - GridStepPts*_Point;
   bool ok = buy
             ? trade.BuyLimit (lot, price, _Symbol, 0, tp, 0, 0, "GridBuy")
             : trade.SellLimit(lot, price, _Symbol, 0, tp, 0, 0, "GridSell");
   if(!ok) Print("[Grid] limit fail ",GetLastError());
}

int CountPendings(ENUM_ORDER_TYPE type)
{
   int c=0;
   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)!=Magic) continue;
      if(OrderGetString (ORDER_SYMBOL)!=_Symbol) continue;
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
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
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

void CloseGrid()
{
   for(int i=PositionsTotal()-1;i>=0;--i)
      if(PositionGetInteger(POSITION_MAGIC)==Magic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         trade.PositionClose(PositionGetTicket(i));

   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==Magic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }
}

//+------------------------------------------------------------------+
//| CHANGELOG                                                        |
//| v0.1.0 (2025‑05‑20)                                                |
//| • MaxLayers input 限制開倉層數                                    |
//| • 每格自帶 TakeProfit = GridStep                                  |
//| • 修復 OrderGetInteger/OrderGetString 調用順序                     |
//+------------------------------------------------------------------+
