#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "1.001"
#property strict
#property description "Last Edit: 2025.11.18"

#include <Trade/Trade.mqh>

//=== Inputs ===============================================================
input group "Base Setting"; 
input bool 	 OnCommit   = false;
input double BaseLot      = 0.01;  // first lot size
input int    Magic        = 400;   // magic number

input group "Strategy Parameter";
input int    MaxLayers    = 2;     // Max numbers of grid（positon + order）
input double GridStepPts  = 160;   // grid step (points)

input group "SL Condition";
input bool	 swPoinOrCash  = true;  // true: close by point flase: close by cash
input double BasketTP      = 1500;  // All position TP ($)
input double BasketSL      = 30;    // All position SL ($)
input double BasketTP_Pts  = 600;   // All position TP（points）
input double BasketSL_Pts  = 70;    // All position SL（points）
input bool   WeightByLots  = true;  

input group "Grid Pause(Optimize Ongoing, unuseful for now)";
//=== Inputs =========================================================
input int    AtrPeriod     = 14;
input double AtrPause_pts  = 500;   // ATR 達此點數→暫停
input double AtrResume_pts = 300;   // ATR 低於此點數→恢復

input int    AdxPeriod     = 14;
input double AdxPause      = 50.4;  // ADX 達此→暫停
input double AdxResume     = 30;    // ADX 低於此→恢復
input double TrendK        = 20;    // |mid-anchor| ≥ K*GridStepPts →判定趨勢

input int    DonLen        = 0;     // Donchian 長度；0=停用
input double MaxSpread_pts = 300;   // 點差過大→暫停
input int    CooldownMin   = 5;     // 進入暫停後最少等待分鐘數
input int 	 MaxPauseMin   = 1455;  

input bool sw = true;

//=== State ==========================================================
enum GRID_STATE { RUN=0, PAUSE=1 };
GRID_STATE g_state = RUN;
double 	   atr_pts, adx;
datetime   g_pause_since = 0;
double     g_anchor = 0.0;

int hATR=INVALID_HANDLE, hADX=INVALID_HANDLE;
/////////////////////////////////////////////////////
CTrade trade;
double profit;
double basket_points;

//==========================================================================
int OnInit(){
	trade.SetExpertMagicNumber(Magic);
	//////////////////
	g_anchor = Mid();
   	hATR = iATR(_Symbol, PERIOD_CURRENT, AtrPeriod);
   	hADX = iADX(_Symbol, PERIOD_CURRENT, AdxPeriod);
   	/////////////////
	return INIT_SUCCEEDED;
}

void OnDeinit(const int){
	CloseGrid();
}

////////////////////
double Mid(){
	return 0.5*(SymbolInfoDouble(_Symbol,SYMBOL_BID) +
				SymbolInfoDouble(_Symbol,SYMBOL_ASK));
}

bool GetATRpts(double &atr_pts_f){
   if(hATR==INVALID_HANDLE) hATR=iATR(_Symbol,PERIOD_CURRENT,AtrPeriod);
   if(hATR==INVALID_HANDLE) return false;
   if(BarsCalculated(hATR)<AtrPeriod+2) return false;
   double a[1]; if(CopyBuffer(hATR,0,1,1,a)<=0) return false; // 用已收線
   atr_pts_f = a[0]/_Point; return true;
}

bool GetADX(double &adx_f){
   if(hADX==INVALID_HANDLE) hADX=iADX(_Symbol,PERIOD_CURRENT,AdxPeriod);
   if(hADX==INVALID_HANDLE) return false;
   if(BarsCalculated(hADX)<AdxPeriod+2) return false;
   double d[1]; if(CopyBuffer(hADX,2,1,1,d)<=0) return false; // ADX，用上一根
   adx_f = d[0]; return true;
}


bool DonchianBreakout()
{
   if(DonLen<=0) return false;
   double hi[], lo[];
   if(CopyHigh(_Symbol,PERIOD_CURRENT,0,DonLen+2,hi)<=0)  return false;
   if(CopyLow (_Symbol,PERIOD_CURRENT,0,DonLen+2,lo)<=0)  return false;
   double curH = hi[1], curL = lo[1];              // 只用上一根
   double maxPrev=lo[2], minPrev=hi[2];
   //Print("curH:",curH," curL:",curL," maxPrev:",maxPrev," minPrev:",minPrev);
   for(int i=2;i<=DonLen+1;i++){ 
      maxPrev = MathMax(maxPrev, hi[i]); 
      minPrev = MathMin(minPrev, lo[i]); 
   }
   return (curH>maxPrev || curL<minPrev);
}


bool SpreadTooWide()
{
   double spr = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   return spr >= MaxSpread_pts;
}

//--- 暫停與恢復條件（帶回滯）
bool ShouldPause()
{
   bool atr_ok=GetATRpts(atr_pts), adx_ok=GetADX(adx);
   bool byATR = atr_ok && (atr_pts >= AtrPause_pts);
   bool byADX = adx_ok && (adx >= AdxPause && MathAbs(Mid()-g_anchor) >= TrendK*GridStepPts*_Point);
   bool byDon = DonchianBreakout();
   bool bySpr = SpreadTooWide();
   return (byATR || byADX || byDon || bySpr);
}

bool ShouldResume()
{
   // 冷卻時間
   if((TimeCurrent()-g_pause_since) < CooldownMin*60) return false;

   bool atr_ok=GetATRpts(atr_pts), adx_ok=GetADX(adx);
   bool atr_back = atr_ok ? (atr_pts <= AtrResume_pts) : true;
   bool adx_back = adx_ok ? (adx <= AdxResume) : true;
   bool spr_ok   = !SpreadTooWide();
   //bool trend_back = MathAbs(Mid()-g_anchor) < TrendK*GridStepPts*_Point; // 放寬亦可
   bool trend_back = true;
   return (atr_back && adx_back && spr_ok && trend_back);
}

void SafetyUnpause()
{
   if(TimeCurrent()-g_pause_since < MaxPauseMin*60) return;
   
   // 點差正常即可重製
   if(!SpreadTooWide()){
   	  CloseGrid();
      g_state = RUN;
      g_anchor = Mid();
      ManageGrid();
      g_pause_since = 0;
   }
}

////////////////////
void OnTrade(void)
{
   g_pause_since = TimeCurrent();
}
  
int puaseTime = 0;
  
void OnTick()
{  
	SafetyUnpause();
	
	bool PauseOrNot = ShouldPause();
   // 狀態機
   if(g_state==RUN && PauseOrNot){
      g_state = sw ? PAUSE : RUN;
      CloseGrid(); // 關倉撤單，或只撤單保留倉位，依你需求
      puaseTime = puaseTime+1;
   }
   else if(g_state==PAUSE && ShouldResume()){
      g_state = RUN;
      g_anchor = Mid();
   }

   if(g_state==RUN && !PauseOrNot){
      ManageGrid();
      CheckBasketClose();
   }
   if(OnCommit){
		Comment("profit: ", profit, "\n",
   			"basket_points: ", basket_points,"\n",
   			"atr_pts: ", atr_pts,"\n",
   			"adx: ", adx,"\n",
   			"state=", (g_state==RUN?"RUN":"PAUSE"),"\n",
   			"last_tradeTime: ", g_pause_since, "\n",
   			"puaseTime: ", puaseTime
   			);
   }
}

//-------------------------------------------------------------------------
void ManageGrid()
{
   int buyLayer  = CountPositions(POSITION_TYPE_BUY)  + CountPendings(ORDER_TYPE_BUY_LIMIT);
   int sellLayer = CountPositions(POSITION_TYPE_SELL) + CountPendings(ORDER_TYPE_SELL_LIMIT);

   // 第一層
   if(buyLayer==0)  PlaceLimit(true ,  g_anchor - 1*GridStepPts*_Point);
   if(sellLayer==0) PlaceLimit(false,  g_anchor + 1*GridStepPts*_Point);

   // 其餘層
   for(int i=1;i<MaxLayers;i++){
      if(buyLayer <= i-1)  PlaceLimit(true , g_anchor - (i+1)*GridStepPts*_Point);
      if(sellLayer<= i-1)  PlaceLimit(false, g_anchor + (i+1)*GridStepPts*_Point);
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

double BasketPoints(bool weight_by_lots=true)
{
   double pt = _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double sum_pts = 0.0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
   	  ulong tk = PositionGetTicket(i);
   	  PositionSelectByTicket(tk);
      if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
      if(PositionGetString (POSITION_SYMBOL)!=_Symbol) continue;

      long   type   = PositionGetInteger(POSITION_TYPE);
      double open   = PositionGetDouble (POSITION_PRICE_OPEN);
      double lots   = PositionGetDouble (POSITION_VOLUME);

      // 單筆「已浮動點數」（不含手續費/隔夜息）
      double pts = 0.0;
      if(type==POSITION_TYPE_BUY)
         pts = (bid - open)/pt;
      else if(type==POSITION_TYPE_SELL)
         pts = (open - ask)/pt;

      sum_pts += weight_by_lots ? pts * lots : pts;
   }
   return sum_pts;
}


//-------------------------------------------------------------------------
double BasketProfit()
{
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;--i){
   	  ulong tk = PositionGetTicket(i);
   	  PositionSelectByTicket(tk);
      if(PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      p+=PositionGetDouble(POSITION_PROFIT);
    }
   return p;
}

void CheckBasketClose()
{
	profit=BasketProfit();
   	basket_points = BasketPoints(WeightByLots);
   	
	if(swPoinOrCash)
	  {
	   if(basket_points >= BasketTP_Pts || basket_points <= -BasketSL_Pts)
      		CloseGrid();
	  }else
     {
      	if(profit>=BasketTP || profit<=-BasketSL) CloseGrid();
     }
}

void CloseGrid()
{
   for(int i=PositionsTotal()-1;i>=0;--i){
   	  ulong tk = PositionGetTicket(i); if(tk==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)==Magic && PositionGetString(POSITION_SYMBOL)==_Symbol)
         trade.PositionClose(PositionGetTicket(i));
   }
   
   for(int i=OrdersTotal()-1;i>=0;--i)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      if(OrderGetInteger(ORDER_MAGIC)==Magic && OrderGetString(ORDER_SYMBOL)==_Symbol)
         trade.OrderDelete(tk);
   }
}
