#property copyright "ManYo"
#property link      "https://www.mql5.com"
#property version   "1.1.1"
#property description "This EA is a simple day open breakout strategy."
#property description "(1.0.2 -> 1.0.3) add the time interval constraint for the reversal trade"
#property description "(Error!) Now find a big trouble, the dayOpenPrice does not update correctly, need to fix it"
#property description "(1.0.3 -> 1.1.0) I hope this version had fixed the dayOpenPrice update issue :("
#property description "(1.1.0 -> 1.1.1) Fix the bug of the dayOpenPrice update issue......I hope, please :("

#include <Trade/Trade.mqh>

input group "=== Base Settings ==="
input double InpLots = 0.01;                   // 手數
input double InpStopLoss = 10000;              // 停損點數
input double InpTakeProfit = 2000;             // 停利點數
input int magicNumber = 200;                   // EA專用 magic number
input int MinReversalInterval = 10;            // 反轉間隔時間（分鐘）

input group "=== Time Settings ==="
input bool TimeFilter = true;                  // 使用時間過濾
input int StartHour = 2;                       // 交易開始小時
input int StartMin = 2;                        // 交易開始分鐘
input int EndHour = 23;                        // 交易結束小時
input int EndMin = 0;                          // 交易結束分鐘
input int resetHour = 1;                       // 重設開盤價時間
input int resetMin = 16;                       // 重設開盤價分鐘
input int resetSecond = 1;                     // 重設開盤價秒數

CTrade trade;
datetime lastTradeTime = 0;                    // 上次交易時間
double dayOpenPrice;                           // 紀錄當前日K開盤價
int reversalCount = 0;                         // 單日反轉次數紀錄
bool isFirstTrade = true;                      // 確認是否為第一筆交易
int direction, currentDirection;
bool keep = false;

int OnInit() {
    ResetDailyLevels();
    trade.SetExpertMagicNumber(magicNumber);   // 設定 magic number
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

void OnTick() {
    UpdateDailyLevels();      // 更新日K開盤價

    if (TimeFilter && !IsTradingTime()) {
        CloseAllPositions();  // 離開交易時間，平倉
        isFirstTrade = true;  // 離開交易時間後，重置第一筆交易基準
        return;
    }

    CheckAndTrade();          // 檢查交易條件
    DisplayReversalCount();   // 在圖表顯示反轉次數
}

void CheckAndTrade() {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bool hasPosition = CheckPosition();
    direction = GetTradeDirection();       // 1: 做多, -1: 做空, 0: 無交易條件

    datetime currentTime = TimeCurrent();      // 當前時間

    // 判斷是否達到交易間隔
    Comment("Current Time: ", TimeToString(currentTime), " Last Trade Time: ", TimeToString(lastTradeTime), "\nDay Open Price: ", dayOpenPrice);

    if (currentTime - lastTradeTime < MinReversalInterval * 60 && !isFirstTrade) {
        Print("Trade skipped due to interval constraint.");
        return;
    }


    if (direction != 0) {
        if (isFirstTrade) {
            // 第一筆交易，直接執行且不計算反轉次數
            ExecuteTrade(direction, bid, ask);
            isFirstTrade = false;             // 已完成第一筆交易
            // dayOpenPrice = ask;               // 更新開盤價為當前價格
            lastTradeTime = currentTime;      // 記錄交易時間
            return;
        }

        if (hasPosition) {
            currentDirection = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
            if (currentDirection != direction) {
                if (CloseAllPositions()) {              // 平倉再進行反向交易
                    reversalCount++;                    // 紀錄反轉次數
                    ExecuteTrade(direction, bid, ask);  // 重新進行反向交易
                    lastTradeTime = currentTime;        // 更新交易時間
                }
                return;                                 // 確保不再進行其他處理
            } else {
                return;  // 不需反向，直接退出
            }
        }

        ExecuteTrade(direction, bid, ask);    // 執行交易
        lastTradeTime = currentTime;          // 更新交易時間
    }
}

bool CheckPosition(){
    int totalPositions = PositionsTotal();
    for (int i = totalPositions - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber) {
            return true;
        }
    }
    return false;
}

void ExecuteTrade(int now_direction, double bid, double ask) {
    double sl = now_direction == 1 ? bid - InpStopLoss * _Point : ask + InpStopLoss * _Point;
    double tp = now_direction == 1 ? bid + InpTakeProfit * _Point : ask - InpTakeProfit * _Point;
    if (now_direction == 1) {
        trade.Buy(InpLots, _Symbol, 0, sl, tp, "Day Open Breakout Buy");
    } else if (now_direction == -1) {
        trade.Sell(InpLots, _Symbol, 0, sl, tp, "Day Open Breakout Sell");
    }
}

int GetTradeDirection() {
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if (price > dayOpenPrice) return 1;  // 價格突破日K開盤價，做多
    if (price < dayOpenPrice) return -1; // 價格低於日K開盤價，做空
    return 0;                            // 無交易條件
}

void ResetDailyLevels() {
    dayOpenPrice = iOpen(_Symbol, PERIOD_M1, 0);
    // dayOpenPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
    // double  LASTPRICE = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    reversalCount = 0;                   // 重設反轉次數
    isFirstTrade = true;                 // 重置為第一筆交易
}

void UpdateDailyLevels() {
    MqlDateTime time;
    TimeCurrent(time);
    Print("Current Time: ", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)); // 調試輸出當前時間

    if (time.hour == resetHour && time.min == resetMin && time.sec == resetSecond && !keep) {
        Print("Resetting daily levels."); // 調試輸出重設訊息
        ResetDailyLevels();              // 指定重設
        keep = true;
    }
    else if (time.hour == resetHour && time.min == resetMin && time.sec == (resetSecond+1) && keep)
    {
        keep = false;
    }
    
}

bool IsTradingTime() {
    MqlDateTime time;
    TimeCurrent(time);
    int currentMinutes = time.hour * 60 + time.min;
    int startMinutes = StartHour * 60 + StartMin;
    int endMinutes = EndHour * 60 + EndMin;

    return (currentMinutes >= startMinutes && currentMinutes <= endMinutes);
}

bool CloseAllPositions() {
    bool allClosed = true;
    int totalPositions = PositionsTotal();
    for (int i = totalPositions - 1; i >= 0; i--) {
        if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber) {
            ulong ticket = PositionGetTicket(i);
            Print("Ticket: ", ticket, " Symbol: ", PositionGetSymbol(i), " Magic: ", PositionGetInteger(POSITION_MAGIC));
            if (PositionSelectByTicket(ticket)) {
                if (!trade.PositionClose(ticket)) {  // 嘗試平倉
                    allClosed = false;              // 若平倉失敗，設置標誌
                }
            }
        }
    }
    return allClosed;
}

void DisplayReversalCount() {
    string text = "Daily Reversals: " + IntegerToString(reversalCount) + "  Current Direction: " + IntegerToString(currentDirection) + " Direction: " + IntegerToString(direction);
    if (!ObjectCreate(0, "ReversalCount", OBJ_LABEL, 0, 0, 0)) {
        Print("Failed to create label object!");
    }
    ObjectSetInteger(0, "ReversalCount", OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, "ReversalCount", OBJPROP_YDISTANCE, 70);
    ObjectSetInteger(0, "ReversalCount", OBJPROP_CORNER, 0);
    ObjectSetInteger(0, "ReversalCount", OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, "ReversalCount", OBJPROP_TEXT, text);
}

