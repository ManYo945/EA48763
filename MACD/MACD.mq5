#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "1.000"
#property strict
#property description "Last Edit: 2026.3.13"
#property description "This EA is a MACD strategy with RSI filter and divergence filter."

#include <Trade/Trade.mqh>

input group "Foundation Setting";
input bool	 OnCommit 		 = false;
input bool	 OnDraw   		 = false;
input int    Magic           = 900;   // magic number
input double Lots            = 0.01;
input double InpStopLoss    = 900;    // SL (points)
input double InpTakeProfit  = 5000;    // TP (points)

input group "MACD Setting";
input ENUM_TIMEFRAMES period = PERIOD_M30;
input int FastEMA = 14;
input int SlowEMA = 24;
input int MACDEMA = 7;
input ENUM_APPLIED_PRICE  AppliedPrice = PRICE_CLOSE;

input group "RSI Setting";
input ENUM_TIMEFRAMES RSI_Per = PERIOD_M4;
input int RSI_MA = 18;
input ENUM_APPLIED_PRICE  RSI_Price = PRICE_CLOSE;
input double RSI_OS  = 30;
input double RSI_OB  = 75;

input group "Time Filter";
input bool TimeFilter = true;        // Enable trading window
input int  StartHour  = 2,  StartMin = 10;
input int  EndHour    = 23, EndMin   = 0;

input group "移動停損"; 
input bool   TrailingOn			  = false;
input int    TrailingStopPoints = 350; 				// 移動停損點數

input group "Divergence";
input bool UseDivergenceFilter = true;
input int  DivLookbackBars = 65;     // 往回找樞紐的範圍
input int  DivPivotSpan    = 2;      // 左右各幾根判定 pivot

bool g_bull_div = false;
bool g_bear_div = false;
int  g_last_bars = 0;


input group "Test Para";
input bool   sw = false;
input bool   PendingTrailingOn  = true;
input int PendingPoint = 100;

CTrade trade;

int macd_handle = INVALID_HANDLE;
int rsi_handle  = INVALID_HANDLE;
int barsTotal = 0;
int START_MIN = 0, END_MIN   = 0;
int pos_long = 0, pos_short = 0, ord_long = 0, ord_short = 0;
bool OVER_BUY = false, OVER_SELL = false;
bool out_of_time_closed = false; // FIX: 防止時間外重複 ClosePositions

int OnInit()
{
	trade.SetExpertMagicNumber(Magic);
	macd_handle = iMACD(_Symbol, period, FastEMA, SlowEMA, MACDEMA, AppliedPrice);
	rsi_handle = iRSI(_Symbol, RSI_Per, RSI_MA, RSI_Price);
                       
    if(rsi_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE){
	  Print("Failed to create handle, err=", GetLastError());
	  return INIT_FAILED;
	}
	
	if(macd_handle == INVALID_HANDLE) { Print("[INIT ERROR] Cannot create MACD: ", GetLastError()); IndicatorRelease(macd_handle); return INIT_FAILED;}
	if(OnDraw){
		ChartIndicatorAdd(0, 1, macd_handle);
		ChartIndicatorAdd(0, 1, rsi_handle);
	}
	
	barsTotal = iBars(_Symbol, period);
	GetTimeFilter(START_MIN, END_MIN);

	return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
	if(macd_handle != INVALID_HANDLE) IndicatorRelease(macd_handle);
	if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
}

void OnTrade(void)
{
}

void OnTick()
{
    if(NotInTimeWindow()) return;
    
	checkPosition(pos_long, pos_short);
	checkOrder(ord_long, ord_short);

    if(ord_long != 0 || ord_short != 0){
    	PendingTrailing(Magic);
    }
    
	int bars_now = iBars(_Symbol, period);
	if(bars_now != g_last_bars){
		g_last_bars = bars_now;
		if(UseDivergenceFilter){
			g_bull_div = HasBullishDivergence(macd_handle, DivLookbackBars, DivPivotSpan);
			g_bear_div = HasBearishDivergence(macd_handle, DivLookbackBars, DivPivotSpan);
		}else{
			g_bull_div = true;
			g_bear_div = true;
		}
	}

	double rsi[1];
	if(CopyBuffer(rsi_handle, 0, 0, 1, rsi) != 1) return;

	if(!OVER_BUY && rsi[0]>RSI_OB && ord_short==0 && pos_short==0) OVER_BUY = true;
    if(!OVER_SELL && rsi[0]<RSI_OS && ord_long==0 && pos_long==0) OVER_SELL = true;
	
	double macd_m[3], macd_s[3];
	if(CopyBuffer(macd_handle, 0, 0, 3, macd_m) != 3) return;
	if(CopyBuffer(macd_handle, 1, 0, 3, macd_s) != 3) return;
    
	if(OnCommit){
		Comment("macd_m: ", macd_m[0], " / ", macd_m[1], " / ", macd_m[2], "\n",
				"macd_s:", macd_s[0], " / ", macd_s[1], " / ", macd_s[2], "\n",
				"OVER_BUY: ", OVER_BUY, "\n",
				"OVER_SELL: ", OVER_SELL, "\n",
				"ord_short/pos_short: ", ord_short, " / ", pos_short, "\n",
				"ord_long/pos_long: ", ord_long, " / ", pos_long, "\n"
			   );
	}
	
	if(OVER_BUY && g_bear_div){   // 超買 + 熊背離 => 掛 Sell Stop
		double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
		double price = NormalizeDouble(ask - PendingPoint*_Point, _Digits);
		sellStop(Lots, price, InpStopLoss, InpTakeProfit, "Sell Stop (BearDiv)");
		OVER_BUY = false;
	}

	if(OVER_SELL && g_bull_div){  // 超賣 + 牛背離 => 掛 Buy Stop
		double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
		double price = NormalizeDouble(bid + PendingPoint*_Point, _Digits);
		buyStop(Lots, price, InpStopLoss, InpTakeProfit, "Buy Stop (BullDiv)");
		OVER_SELL = false;
	}
}

void checkPosition(int &long_pos, int &short_pos){
	long_pos = 0; short_pos = 0;
	for(int i = PositionsTotal() - 1; i >= 0; --i) {
        ulong tk = PositionGetTicket(i); if(tk == 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) 	  continue;
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) long_pos++;
        else short_pos++;
    }
}

void checkOrder(int &long_pos, int &short_pos){
	long_pos = 0; short_pos = 0;
	for(int i = OrdersTotal() - 1; i >= 0; --i) {
        ulong tk = OrderGetTicket(i); if(tk == 0) continue;
        if(!OrderSelect(tk)) continue;
        if(OrderGetInteger(ORDER_MAGIC) != Magic) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) 	  continue;
        ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(type == ORDER_TYPE_BUY_STOP) long_pos++;
        else if(type == ORDER_TYPE_SELL_STOP)short_pos++;
    }
}

void buyStop(double lots, double price, double stopLoss, double takeProfit, string comment){
	price = NormalizeDouble(price, _Digits);
	double sl = NormalizeDouble(price - stopLoss * _Point, _Digits);
    double tp = NormalizeDouble(price + takeProfit * _Point, _Digits);
    trade.BuyStop(lots, price, _Symbol, sl, tp, 0, 0, comment);
}

void sellStop(double lots, double price, double stopLoss, double takeProfit, string comment){
	price = NormalizeDouble(price, _Digits); 
	double sl = NormalizeDouble(price + stopLoss * _Point, _Digits);
    double tp = NormalizeDouble(price - takeProfit * _Point, _Digits);
    trade.SellStop(lots, price, _Symbol, sl, tp, 0, 0, comment);
}

void buyLimit(double lots, double stopLoss, double takeProfit, string comment){
	double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
	double sl = NormalizeDouble(ask - stopLoss * _Point, _Digits);
    double tp = NormalizeDouble(ask + takeProfit * _Point, _Digits);
    trade.Buy(lots, _Symbol, 0, sl, tp, comment);
}

void sellLimit(double lots, double stopLoss, double takeProfit, string comment){
	double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);  
	double sl = NormalizeDouble(bid + stopLoss * _Point, _Digits);
    double tp = NormalizeDouble(bid - takeProfit * _Point, _Digits);
    trade.Sell(lots, _Symbol, 0, sl, tp, comment);
}

void PendingTrailing(int magic){
	if(!PendingTrailingOn) return;

	double Bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
	double Ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

	for(int i=0; i<OrdersTotal(); i++){
		ulong tk = OrderGetTicket(i); if(tk == 0) continue;
        if(!OrderSelect(tk)) continue;
		if(OrderGetInteger(ORDER_MAGIC) != magic) continue;
		if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
		
		double open_price = OrderGetDouble(ORDER_PRICE_OPEN);
		double sl         = OrderGetDouble(ORDER_SL);
		double tp         = OrderGetDouble(ORDER_TP);
		long type         = OrderGetInteger(ORDER_TYPE);
		
		if(type == ORDER_TYPE_BUY_STOP){
			if(open_price - Bid >= PendingPoint*_Point){
				double new_price = NormalizeDouble(Bid + PendingPoint*_Point, _Digits);
				double new_sl = NormalizeDouble(new_price - InpStopLoss*_Point, _Digits);
				double new_tp = NormalizeDouble(new_price + InpTakeProfit*_Point, _Digits);
				if(!trade.OrderModify(tk, new_price, new_sl, new_tp, ORDER_TIME_GTC, 0, 0))
					Print("ORDER_TYPE_BUY_STOP Error");
			}
		}
		else if(type == ORDER_TYPE_SELL_STOP){ 
			if(Ask - open_price >= PendingPoint*_Point){
			  	double new_price = NormalizeDouble(Ask - PendingPoint*_Point, _Digits);
			  	double new_sl = NormalizeDouble(new_price + InpStopLoss*_Point, _Digits);
				double new_tp = NormalizeDouble(new_price - InpTakeProfit*_Point, _Digits);
			  	if(!trade.OrderModify(tk, new_price, new_sl, new_tp, ORDER_TIME_GTC, 0, 0))
					Print("ORDER_TYPE_SELL_STOP Error");
			}
		}
	}
}

void TrailingStop(int magic){
	if(!TrailingOn) return;
	for(int i=0; i<PositionsTotal(); i++){	
		ulong ticket = PositionGetTicket(i);
		if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
		if(PositionGetSymbol(i) != _Symbol) continue;
		
		double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
		double sl         = PositionGetDouble(POSITION_SL);
		double tp         = PositionGetDouble(POSITION_TP);
		long type         = PositionGetInteger(POSITION_TYPE);
		double Bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
		double Ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
		
		if(type == POSITION_TYPE_BUY){
			if(Bid - open_price >= TrailingStopPoints*_Point){
				//double new_sl = Bid - TrailingStopPoints*_Point;	
				//if(new_sl > sl) trade.PositionModify(_Symbol, new_sl, tp);
				trade.PositionModify(_Symbol, open_price, tp);
			}
		}
		else if(type == POSITION_TYPE_SELL){ 
			if(open_price - Ask >= TrailingStopPoints*_Point){
			  //double new_sl = Ask + TrailingStopPoints*_Point;
			  //if(new_sl < sl || sl == 0) trade.PositionModify(_Symbol, new_sl, tp);
			  trade.PositionModify(_Symbol, open_price, tp);
			}
		}
	}
}

void GetTimeFilter(int &startMin, int &endMin){
	startMin = StartHour * 60 + StartMin;
	endMin   = EndHour   * 60 + EndMin;
}

bool NotInTimeWindow(){
	/*use method
	int START_MIN = 0, END_MIN   = 0;
	int nowMin = (TimeCurrent() % 86400) / 60;
    if(!InTimeWindowFast(nowMin))
        return;
	*/
	if(!TimeFilter) return false;
	int nowMin = (int)(((long)TimeCurrent() % 86400) / 60);
	bool canTrade = (END_MIN > START_MIN)
           ? (nowMin >= START_MIN && nowMin < END_MIN)
           : (nowMin >= START_MIN || nowMin < END_MIN);
    if(!canTrade){
		if(!out_of_time_closed){          // FIX: 只執行一次平倉
			ClosePositions(Magic, 'A');
			out_of_time_closed = true;
		}
		if(OnCommit) Comment("[INFO]Not trading time.");
		return true;
	}
	out_of_time_closed = false;           // FIX: 回到可交易時重置旗標
    return false;
}

void ClosePositions(ulong magicNumber, char mode = 'A'){
	/*mode 'A' : all
	mode 'L' : only long
	mode 'S' : only short*/
	
	if(mode != 'A' && mode != 'L' && mode != 'S'){
		Print("[MODE ERROR] ONLY CAN USE MODE [A, L, S]");
	}
    for(int i = PositionsTotal() - 1; i >= 0; --i) {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) 	  continue;
        if(mode == 'L' && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
        	trade.PositionClose(ticket);
        	continue;
        }else if(mode == 'S' && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL){
        	trade.PositionClose(ticket);
        	continue;
        }else if(mode == 'A'){
        	trade.PositionClose(ticket);
        }
    }
}

bool IsPivotLow(const double &arr[], int i, int span){
   for(int k=1; k<=span; k++){
      if(arr[i] >= arr[i-k] || arr[i] >= arr[i+k]) return false;
   }
   return true;
}

bool IsPivotHigh(const double &arr[], int i, int span){
   for(int k=1; k<=span; k++){
      if(arr[i] <= arr[i-k] || arr[i] <= arr[i+k]) return false;
   }
   return true;
}

// 牛背離: 價格創更低低點，但 MACD 創更高低點
bool HasBullishDivergence(int macdHandle, int lookback, int span){
   int n = lookback + span + 5;
   double closeBuf[], macdBuf[];
   ArraySetAsSeries(closeBuf, true);
   ArraySetAsSeries(macdBuf, true);

   if(CopyClose(_Symbol, period, 0, n, closeBuf) < n) return false;
   if(CopyBuffer(macdHandle, 0, 0, n, macdBuf) < n) return false; // 0: MACD main

   int p1=-1, p2=-1, m1=-1, m2=-1;

   // 從已收棒開始找 (shift >= 1)
   for(int i=span+1; i<=lookback; i++){
      if(p1<0 && IsPivotLow(closeBuf, i, span)) p1=i;
      else if(p2<0 && IsPivotLow(closeBuf, i, span)) { p2=i; break; }
   }
   for(int i=span+1; i<=lookback; i++){
      if(m1<0 && IsPivotLow(macdBuf, i, span)) m1=i;
      else if(m2<0 && IsPivotLow(macdBuf, i, span)) { m2=i; break; }
   }

   if(p1<0 || p2<0 || m1<0 || m2<0) return false;

   bool priceLowerLow = closeBuf[p1] < closeBuf[p2];
   bool macdHigherLow = macdBuf[m1] > macdBuf[m2];
   return (priceLowerLow && macdHigherLow);
}

// 熊背離: 價格創更高高點，但 MACD 創更低高點
bool HasBearishDivergence(int macdHandle, int lookback, int span){
   int n = lookback + span + 5;
   double closeBuf[], macdBuf[];
   ArraySetAsSeries(closeBuf, true);
   ArraySetAsSeries(macdBuf, true);

   if(CopyClose(_Symbol, period, 0, n, closeBuf) < n) return false;
   if(CopyBuffer(macdHandle, 0, 0, n, macdBuf) < n) return false;

   int p1=-1, p2=-1, m1=-1, m2=-1;

   for(int i=span+1; i<=lookback; i++){
      if(p1<0 && IsPivotHigh(closeBuf, i, span)) p1=i;
      else if(p2<0 && IsPivotHigh(closeBuf, i, span)) { p2=i; break; }
   }
   for(int i=span+1; i<=lookback; i++){
      if(m1<0 && IsPivotHigh(macdBuf, i, span)) m1=i;
      else if(m2<0 && IsPivotHigh(macdBuf, i, span)) { m2=i; break; }
   }

   if(p1<0 || p2<0 || m1<0 || m2<0) return false;

   bool priceHigherHigh = closeBuf[p1] > closeBuf[p2];
   bool macdLowerHigh   = macdBuf[m1] < macdBuf[m2];
   return (priceHigherHigh && macdLowerHigh);
}
