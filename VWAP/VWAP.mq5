#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "0.2.0"
#property strict
#property description "Last Edit: 2026.1.26"
#property description "(0.2.0 -> 1.000) Change version format to fit IDE."
#property description "(1.000 -> 1.001) Cleaned code base and set new parameters."

#include <Trade/Trade.mqh>

input group "Foundation Setting"; 
input bool			OnCommit 	  = false;
input bool			OnDraw  	  = false;
input ENUM_TIMEFRAMES TF          = PERIOD_M15;     // Working timeframe
input double        DeviationPts  = 100;           // Entry threshold (points)
input double        StopLossPts   = 700;           // Stop‑loss distance (points)
input double        Lots          = 0.01;          // Lot size per entry
input uint          MagicNumber   = 300;      // Unique magic number
input int           MaxPositions  = 2;             // Max simultaneous positions
input int           MaxTradesDay  = 10;             // Max new trades per day

input group "Time Filter"; 
input bool          TimeFilter    = true;         // Enable trading window
input int           StartHour     = 6;
input int           StartMin      = 0;
input int           EndHour       = 13;
input int           EndMin        = 30;

input group "移動停損"; 
input bool   TrailingOn			  = false;
input int    TrailingStopPoints = 350; 				// 移動停損點數

enum ENUM_STRAT_MODE{
	MODE_MEAN_REVERSION=0,
	MODE_BREAKOUT=1
	};

input ENUM_STRAT_MODE Mode = MODE_BREAKOUT;   // Trading logic mode
input double          RR   = 1.32;            // Breakout TP = RR * StopLossPts

CTrade   trade;
datetime last_bar_time = 0;

double   cumPV  = 0.0;
long     cumVol = 0;
int      trading_day  = -1;  // YYYYMMDD
int      trades_today = 0;

#define VWAP_LINE  "VWAP_line"

int OnInit(){
   trade.SetExpertMagicNumber((ulong)MagicNumber);
   if(ObjectFind(0, VWAP_LINE) < 0){
      ObjectCreate(0, VWAP_LINE, OBJ_HLINE, 0, 0, 0);
      ObjectSetInteger(0, VWAP_LINE, OBJPROP_COLOR, clrOrangeRed);
      ObjectSetInteger(0, VWAP_LINE, OBJPROP_WIDTH, 2);
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){}

void CloseMyPositions(){
   for(int i=PositionsTotal()-1;i>=0;--i){
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString (POSITION_SYMBOL)!=_Symbol) continue;
      trade.PositionClose(ticket);
   }
}

int MyOpenPositions(){
   int cnt = 0;
   for(int i=PositionsTotal()-1;i>=0;--i){
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString (POSITION_SYMBOL)!=_Symbol) continue;
      cnt++;
   }
   return cnt;
}

void CloseIfRevertToVWAP(double vwap, double close1){
   for(int i=PositionsTotal()-1; i>=0; --i){
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString (POSITION_SYMBOL)!=_Symbol) continue;

      long type = (long)PositionGetInteger(POSITION_TYPE);
      if( (type==POSITION_TYPE_BUY  && close1 >= vwap) ||
          (type==POSITION_TYPE_SELL && close1 <= vwap) ){
         trade.PositionClose(ticket);
      }
   }
}

bool InTradingWindow(){
   if(!TimeFilter) return true;
   MqlDateTime tm; TimeToStruct(TimeCurrent(), tm);
   int now   = tm.hour*60 + tm.min;
   int start = StartHour*60 + StartMin;
   int end   = EndHour  *60 + EndMin;
   bool ok   = (end>start) ? (now>=start && now<end) : (now>=start || now<end);
   if(!ok) CloseMyPositions();
   return ok;
}

double ComputeSL(bool isBuy, double entry_price){
   double sl = entry_price + (isBuy ? -1.0 : +1.0) * StopLossPts * _Point;
   return NormalizeDouble(sl, _Digits);
}

double ComputeTP(bool isBuy, double entry_price, double vwap_current){
   if(Mode==MODE_MEAN_REVERSION){
      return NormalizeDouble(vwap_current, _Digits);
   }
   // Breakout: RR * StopLossPts from entry
   double tp = entry_price + (isBuy ? +1.0 : -1.0) * (RR * StopLossPts) * _Point;
   return NormalizeDouble(tp, _Digits);
}

void OnTick(){
	if(!InTradingWindow()) return;
	TrailingStop(MagicNumber);
	datetime cur_bar = iTime(_Symbol, TF, 0);
	if(cur_bar == last_bar_time) return; // process only once per bar
	last_bar_time = cur_bar;
	
	double high1  = iHigh (_Symbol, TF, 1);
	double low1   = iLow  (_Symbol, TF, 1);
	double close1 = iClose(_Symbol, TF, 1);
	long   vol1   = (long)iVolume(_Symbol, TF, 1);

	// Day rollover
	MqlDateTime tm_bar; TimeToStruct(cur_bar, tm_bar);
	int yyyymmdd = tm_bar.year*10000 + tm_bar.mon*100 + tm_bar.day;
	if(yyyymmdd != trading_day){
	  trading_day  = yyyymmdd;
	  cumPV = 0.0; cumVol = 0; trades_today = 0;
	}

	// VWAP update
	double typical = (high1 + low1 + close1) / 3.0;
	cumPV  += typical * vol1;
	cumVol += vol1;
	if(cumVol == 0) return;
	double vwap = cumPV / (double)cumVol;

	if(OnDraw)
		ObjectSetDouble(0, VWAP_LINE, OBJPROP_PRICE, vwap);

	// HUD comment
	double deviation_pts = (close1 - vwap) / _Point;
	int myPos = MyOpenPositions();
	
	if(OnCommit)
		Comment(StringFormat("VWAP: %.5f\nPrice: %.5f\nVolume: %ld\nDeviation: %.1f pts\nNow position: %d\ncoda: %d/%d", vwap, close1, vol1, deviation_pts, myPos, trades_today, MaxTradesDay));

   // Guard: position & trade limits
   if(myPos >= MaxPositions) return;
   if(trades_today >= MaxTradesDay)  return;

   // ── Entry conditions ───────────────────────────────────────────
   bool fireBuy=false, fireSell=false;

   if(Mode==MODE_MEAN_REVERSION){
      // Mean reversion: fade distance to VWAP
      if(deviation_pts < -DeviationPts) fireBuy  = true;  // price << vwap
      if(deviation_pts > +DeviationPts) fireSell = true;  // price >> vwap
      CloseIfRevertToVWAP(vwap, close1); // Breakout uses SL/TP only
   }
   else{
      // MODE_BREAKOUT: follow distance from VWAP
      if(deviation_pts > +DeviationPts) fireBuy  = true;  // strength continues
      if(deviation_pts < -DeviationPts) fireSell = true;  // weakness continues
   }
   
   // Buy
   if(fireBuy){
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = ComputeSL(true, entry);
      double tp = ComputeTP(true, entry, vwap);
      if(trade.Buy(Lots, _Symbol, entry, sl, tp, Mode==MODE_MEAN_REVERSION?"VWAP Buy MR":"VWAP Buy BO"))
         trades_today++;
   }

   // Sell
   if(fireSell){
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = ComputeSL(false, entry);
      double tp = ComputeTP(false, entry, vwap);
      if(trade.Sell(Lots, _Symbol, entry, sl, tp, Mode==MODE_MEAN_REVERSION?"VWAP Sell MR":"VWAP Sell BO"))
         trades_today++;
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
				double new_sl = Bid - TrailingStopPoints*_Point;	
				if(new_sl > sl) trade.PositionModify(_Symbol, new_sl, tp);
			}
		}
		else if(type == POSITION_TYPE_SELL){ 
			if(open_price - Ask >= TrailingStopPoints*_Point){
			  double new_sl = Ask + TrailingStopPoints*_Point;
			  if(new_sl < sl || sl == 0) trade.PositionModify(_Symbol, new_sl, tp);
			}
		}
	}
}