#property copyright "ManYo"
#property link      "https://www.mql5.com"
#property version   "0.1.0"

#include <Trade\Trade.mqh>

CTrade trade;

input int SMA = 10;       						// 短均線週期
input int LMA = 46;      						// 長均線週期
input double Lot = 0.01;         			 	// 手數
input double stop_flag = 2;						// EA停利
input ENUM_TIMEFRAMES period = PERIOD_CURRENT; 	// K線週期
input ENUM_MA_METHOD  MA_METH = MODE_LWMA;		// 平滑方法
input ENUM_APPLIED_PRICE MA_PRIC = PRICE_WEIGHTED;	// 平滑目標

int handle_SMA, handle_LMA;
double values_SMA[], values_LMA[];
int barsTotal;
double initialBalance;
bool last = -1;

int OnInit()
{
	trade.SetExpertMagicNumber(13456);
	handle_SMA = iMA(_Symbol, period, SMA, 0, MA_METH, MA_PRIC);
	handle_LMA = iMA(_Symbol, period, LMA, 0, MA_METH, MA_PRIC);
	initialBalance = AccountInfoDouble(ACCOUNT_BALANCE) * stop_flag;
	
	if(handle_SMA<0 || handle_LMA<0)
	   Alert("指標初始化失敗: ", GetLastError());
	else
	   Alert("EA 已啟用");
	  
	return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
	IndicatorRelease(handle_SMA);
	IndicatorRelease(handle_LMA);
}

void OnTick()
{
	double equity = AccountInfoDouble(ACCOUNT_EQUITY);
	
	if(equity >= initialBalance)
	{
		trade.PositionClose(_Symbol); // 平掉持有倉位
		ExpertRemove(); // 停止EA運行
		return;
	}

	int bars = iBars(_Symbol, period);
	
	if(barsTotal == bars)
		return;
	else
	{
		barsTotal = bars;
		CopyBuffer(handle_SMA, MAIN_LINE, 0, 2, values_SMA);
		CopyBuffer(handle_LMA, MAIN_LINE, 0, 2, values_LMA);

		bool hasPosition = (PositionSelect(_Symbol)); // 檢查當持倉

		bool upper = (values_SMA[1] > values_LMA[1]); // 看多
		bool lower = (values_SMA[1] < values_LMA[1]); // 看空
		
		// 如果持有倉位，平倉再開倉
		if(hasPosition)
		{
			double currentVolume = PositionGetDouble(POSITION_VOLUME);
			if( (upper && last == 0)|| (lower && last == 1))
			{
				trade.PositionClose(_Symbol); // 平倉
				// 再開倉
				if(upper)
				{
					trade.Buy(Lot, _Symbol, 0, 0, 0, "IMA Buy");
					last = 1;
				}
				else if(lower)
				{
					trade.Sell(Lot, _Symbol, 0, 0, 0, "IMA SELL");
					last = 0;
				}
			}
		}
		else
		{
			// 初始倉
			if(upper)
			{
				trade.Buy(Lot, _Symbol, 0, 0, 0, "IMA Buy first");
				last = 1;
			}
			else if(lower)
			{
				trade.Sell(Lot, _Symbol, 0, 0, 0, "IMA SELL first");
				last = 0;
			}
		}
	}
	MqlTick last_tick;
	SymbolInfoTick(_Symbol, last_tick);
	double close = last_tick.last;
	Comment("多單隔夜利息: ", SymbolInfoDouble(_Symbol, SYMBOL_SWAP_LONG),
			"\n空單隔夜利息: ", SymbolInfoDouble(_Symbol, SYMBOL_SWAP_SHORT),
			"\n目標權益數: ", initialBalance,
			"\n點差: ",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD),
			"\n時間: ", TimeCurrent(),
			"\n乖離SMA: ", (close - values_SMA[1])/values_SMA[1] * 100,
			"\n乖離LMA: ", (close - values_LMA[1])/values_LMA[1] * 100);
}
