#property copyright "ManYo"
#property link      "https://github.com/ManYo945/EA48763"
#property version   "0.0.1"
#property description "與 SAR_Dev.mq5 相比，這個版本增加了 RVI 指標的應用。實驗進行中" 

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
input string IAmDivider3 = "**************************************************************************************************";
input int RVIPeriod = 14;                           // RVI period
input double RVIThreshold = 0.3;                    // RVI threshold
input double InpStopLoss_2 = 700;                       // Stop Loss in points with 2nd position
input double InpTakeProfit_2 = 950;                     // Take Profit in points with 2nd position
input double InpLots_2 = 0.01;                      // Lot size with 2nd position
input double InpStep_2 = 0.585;                         // Increase AF for SAR with 2nd position
input double InpMaximum_2 =  0.74;                       // Max AF for SAR with 2nd position
input ENUM_TIMEFRAMES period_2 = PERIOD_CURRENT;    // Period with 2nd position
input string IAmDivider4 = "**************************************************************************************************";

int handle;
int handle_2;
int handle_rvi;
int barsTotal;

CTrade trade;

int OnInit(){
    handle = iSAR(_Symbol, period, InpStep, InpMaximum);
    handle_2 = iSAR(_Symbol, period_2, InpStep_2, InpMaximum_2);
    handle_rvi = iRVI(_Symbol, period, RVIPeriod);
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
        double values[], values_2[], values_rvi[], values_signal[];
        int flag = 0;
        bool condition_1, condition_2;
        bool condition_3, condition_4;
        CopyBuffer(handle, MAIN_LINE, 0, 2, values);
        CopyBuffer(handle_2, MAIN_LINE, 0, 2, values_2);
        CopyBuffer(handle_rvi, 0, 0, 2, values_rvi);
        CopyBuffer(handle_rvi, 1, 0, 2, values_signal);
        
        if(MathAbs(values_rvi[1]) < RVIThreshold && MathAbs(values_signal[1]) < RVIThreshold) {
            flag = 1;
        }else{
            flag = -1;
        }

		// Inverse logic trading for SAR. But it is working well. :)
        if(CounterLogic) {
            if (flag == 1) {
                condition_1 = values[1] > iClose(_Symbol, period, 1) && values[0] < iHigh(_Symbol, period, 0);
                condition_2 = values[1] < iClose(_Symbol, period, 1) && values[0] > iLow(_Symbol, period, 0);
                condition_3 = false;
                condition_4 = false;
            }else if(flag == -1){
                // condition_3 = values_2[1] < iClose(_Symbol, period_2, 1) && values_2[0] > iHigh(_Symbol, period_2, 0);
                // condition_4 = values_2[1] > iClose(_Symbol, period_2, 1) && values_2[0] < iLow(_Symbol, period_2, 0);
                
                // 檢查艙位狀況是否為buy
                int totalPositions = PositionsTotal();
                for (int i = totalPositions - 1; i >= 0; i--) {
                    if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber) {
                        ulong ticket = PositionGetTicket(i);
                        // Print("Ticket: ", ticket, " Symbol: ", PositionGetSymbol(i), " Magic: ", PositionGetInteger(POSITION_MAGIC));
                        if (PositionSelectByTicket(ticket)) {
                            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                                condition_3 = true;
                                condition_4 = false;
                            }else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
                                condition_3 = false;
                                condition_4 = true;
                                }
                        }
                    }
                }
                condition_1 = false;
                condition_2 = false;
            }
        }else{
            if (flag == 1) {
                condition_1 = values[1] < iClose(_Symbol, period, 1) && values[0] > iLow(_Symbol, period, 0);
                condition_2 = values[1] > iClose(_Symbol, period, 1) && values[0] < iHigh(_Symbol, period, 0);
                condition_3 = false;
                condition_4 = false;
            }else{
                condition_1 = false;
                condition_2 = false;
                condition_3 = values_2[1] > iClose(_Symbol, period_2, 1) && values_2[0] < iLow(_Symbol, period_2, 0);
                condition_4 = values_2[1] < iClose(_Symbol, period_2, 1) && values_2[0] > iHigh(_Symbol, period_2, 0);
            }
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

        // the buy condition with 2nd position
        if(condition_3){
            CloseAllPositions();  // Close all positions before open new position
            double sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - InpStopLoss_2 * _Point;
            double tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + InpTakeProfit_2 * _Point;
            trade.Buy(InpLots_2, _Symbol, 0, sl, tp, "SAR Buy 2");
            barsTotal = bars;   // Update the barsTotal
        }

        // the sell condition with 2nd position
        if(condition_4){
            CloseAllPositions();    // Close all positions before open new position
            double sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) + InpStopLoss_2 * _Point;
            double tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) - InpTakeProfit_2 * _Point;
            trade.Sell(InpLots_2, _Symbol, 0, sl, tp, "SAR Sell 2");
            barsTotal = bars;   // Update the barsTotal
        }
        Comment("SAR Mode: ", flag,
                "\nSAR 1: ", values[0], " ", values[1],
                "\nSAR 2: ", values_2[0], " ", values_2[1],
                "\nRVI: ", values_rvi[0], " ", values_rvi[1],
                "\nSignal: ", values_signal[0], " ", values_signal[1]);
    }

}
