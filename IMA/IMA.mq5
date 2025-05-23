#property copyright "ManYo"
#property link      "https://www.mql5.com"
#property version   "0.2.0"

#include <Trade\Trade.mqh>

CTrade trade;

input int SMA = 10;  // 短均線週期 (Now shorter period)
input int LMA = 46;  // 長均線週期 (Now longer period)
input double Lot = 0.01;   // 手數                    
input ENUM_TIMEFRAMES period = PERIOD_CURRENT; // EA關注週期
input ENUM_MA_METHOD  MA_METH = MODE_LWMA;     // MA方法
input ENUM_APPLIED_PRICE MA_PRIC = PRICE_WEIGHTED; // 價格定錨
input double TakeProfit = 50;                  // 停利
input double StopLoss = 50;                    // 停損
input int magicNumber = 12345;  // Unique magic number for trades

int handle_SMA, handle_LMA;
double values_SMA[], values_LMA[];
int barsTotal;

int OnInit()
{
    handle_SMA = iMA(_Symbol, period, SMA, 0, MA_METH, MA_PRIC);
    handle_LMA = iMA(_Symbol, period, LMA, 0, MA_METH, MA_PRIC);
    trade.SetExpertMagicNumber(magicNumber); // Set magic number
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    IndicatorRelease(handle_SMA);
    IndicatorRelease(handle_LMA);
}

void OnTick()
{
    int bars = iBars(_Symbol, period);

    if(barsTotal == bars)
        return;
    else
    {
        barsTotal = bars;
        CopyBuffer(handle_SMA, MAIN_LINE, 0, 2, values_SMA);
        CopyBuffer(handle_LMA, MAIN_LINE, 0, 2, values_LMA);

        // 检查当前是否持有仓位
        bool hasPosition = (PositionSelect(_Symbol));

        // 黄金交叉: 短均线从下往上穿过长均线
        bool goldenCross = (values_SMA[1] > values_LMA[1] && values_SMA[0] < values_LMA[0]);
        // 死亡交叉: 短均线从上往下穿过长均线
        bool deathCross = (values_SMA[1] < values_LMA[1] && values_SMA[0] > values_LMA[0]);

        MqlTick last_tick;
        SymbolInfoTick(_Symbol, last_tick);
        double close = last_tick.last;

        // 计算止盈和止损价格
        double tpPrice = 0, slPrice = 0;
        if (goldenCross)
        {
            tpPrice = close + TakeProfit * _Point;
            slPrice = close - StopLoss * _Point;
        }
        else if (deathCross)
        {
            tpPrice = close - TakeProfit * _Point;
            slPrice = close + StopLoss * _Point;
        }

        // 如果持有仓位，根据交叉情况平仓
        if(hasPosition)
        {
            if(goldenCross || deathCross)
            {
                trade.PositionClose(_Symbol); // 平掉持有仓位

                // 根据交叉情况再开仓
                if(goldenCross)
                {
                    trade.Buy(Lot, _Symbol, 0, slPrice, tpPrice, "IMA Buy");
                }
                else if(deathCross)
                {
                    trade.Sell(Lot, _Symbol, 0, slPrice, tpPrice, "IMA Sell");
                }
            }
        }
        else
        {
            // 根据交叉情况开仓
            if(goldenCross)
            {
                trade.Buy(Lot, _Symbol, 0, slPrice, tpPrice, "IMA Buy");
            }
            else if(deathCross)
            {
                trade.Sell(Lot, _Symbol, 0, slPrice, tpPrice, "IMA Sell");
            }
        }
    }
	
	MqlTick last_tick;
	SymbolInfoTick(_Symbol, last_tick);
	double close = last_tick.last;
	
    Comment("多单隔夜利息: ", SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG),
            "\n空单隔夜利息: ", SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT),
            "\n點差: ",SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
            "\n時間: ", TimeCurrent(),
            "\n乖離SMA: ", (close - values_SMA[1])/values_SMA[1] * 100,
            "\n乖離LMA: ", (close - values_LMA[1])/values_LMA[1] * 100);
}
