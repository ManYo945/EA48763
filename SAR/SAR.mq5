#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "1.0.1"

#include <Trade/Trade.mqh>

input bool CounterLogic = true;                     // Counter logic for SAR
input string IAmDivider1 = "*************************************************************************************************";
input double InpStopLoss = 700;                     // Stop Loss in points
input double InpTakeProfit = 950;                   // Take Profit in points
input double InpLots = 0.01;                        // Lot size
input double InpStep = 0.585;                       // Increase AF for SAR
input double InpMaximum = 0.74;                     // Max AF for SAR
input ENUM_TIMEFRAMES period = PERIOD_CURRENT;      // Period
input int magicNumber = 100;                        // Unique magic number for trades
input string IAmDivider2 = "**************************************************************************************************";
input bool TimeFilter = false;                      // Use time filter
input int StartHour = 0;                            // Start hour for trading
input int StartMin = 30;                            // Start min for trading
input int EndHour = 23;                             // End hour for trading
input int EndMin = 30;                              // End min for trading

int handle;
int barsTotal;

CTrade trade;

int OnInit(){
    handle = iSAR(_Symbol, period, InpStep, InpMaximum);
    trade.SetExpertMagicNumber(magicNumber); // Set magic number
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void CloseAllPositions() {
    bool allClosed = true;
    int totalPositions = PositionsTotal();
    for (int i = totalPositions - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber) {
            ulong ticket = PositionGetTicket(i);
            // Print("Ticket: ", ticket, " Symbol: ", PositionGetSymbol(i), " Magic: ", PositionGetInteger(POSITION_MAGIC));
            if (PositionSelectByTicket(ticket)) {
                if (!trade.PositionClose(ticket)) {  // 嘗試平倉
                    allClosed = false;              // 若平倉失敗，設置標誌
                }
            }
        }
    }
    //return allClosed;
}

// Check the trading time
// TODO: It is not a good idea for now. I need some idea to fix it.
bool IsTradingTime(bool UseTimeFilter = false) {

    // If we don't use the time filter, we can trade anytime.
    if(!UseTimeFilter) {
        return true;
    }
    
    MqlDateTime time;
    TimeCurrent(time);

    time.hour = StartHour;
    time.min = StartMin;
    datetime start = StructToTime(time);

    time.hour = EndHour;
    time.min = EndMin;
    datetime end = StructToTime(time);

    datetime now = TimeCurrent();
    
    if(start < now && now < end) {
        return true;
    }else{
        CloseAllPositions();
        return false;
    }

}

void OnTick() {
    // TODO: we can add the trading time filter here, but it is not working well. I need some idea to fix it.
    if(!IsTradingTime(TimeFilter) && TimeFilter) {
        Comment("Now is not trading time.");
        return;
     }


    // TODO: for now, we only trade one time per bar, but we can try to trade multiple times per bar
    int bars = iBars(_Symbol, period);
    if(barsTotal == bars) {
        return;
    }else{
        double values[];
        bool condition_1, condition_2;
        CopyBuffer(handle, MAIN_LINE, 0, 2, values);
        
		// Inverse logic trading for SAR. But it is working well. :)
        if(CounterLogic) {
            condition_1 = values[1] > iClose(_Symbol, period, 1) && values[0] < iHigh(_Symbol, period, 0);
            condition_2 = values[1] < iClose(_Symbol, period, 1) && values[0] > iLow(_Symbol, period, 0);
        }else{
            condition_1 = values[1] < iClose(_Symbol, period, 1) && values[0] > iLow(_Symbol, period, 0);
            condition_2 = values[1] > iClose(_Symbol, period, 1) && values[0] < iHigh(_Symbol, period, 0);
        }

        // the buy condition
        if(condition_1){
	        CloseAllPositions();  // Close all positions before open new position
            double sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - InpStopLoss * _Point;
            double tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpTakeProfit * _Point;
            trade.Buy(InpLots, _Symbol, 0, sl, tp, "SAR Buy");
            barsTotal = bars;   // Update the barsTotal
        }
        
        // the sell condition
        if(condition_2){
	        CloseAllPositions();    // Close all positions before open new position
            double sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) + InpStopLoss * _Point;
            double tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpTakeProfit * _Point;
            trade.Sell(InpLots, _Symbol, 0, sl, tp, "SAR Sell");
            barsTotal = bars;   // Update the barsTotal
        }
    }
}
