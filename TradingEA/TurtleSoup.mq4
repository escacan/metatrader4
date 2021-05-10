//+------------------------------------------------------------------+
//|                                                   TurtleSoup.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#define isZero(x) (fabs(x) < 0.000000001)
#define isEqual(x,y) (fabs(x-y) < 0.000000001)
#define isBigger(x,y) (x-y >= 0.000000001)
#define isSmaller(x,y) (x-y <= -0.000000001)

extern int MAGICNO = 5;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 2000;

ENUM_TIMEFRAMES BREAKOUT_TIMEFRAME = PERIOD_D1;
bool IsPositionExist = false;
int CURRENT_CMD = OP_BUY; // 0 : Buy  1 : Sell
int CURRENT_POSITION_TICKET_NUMBER = 0;
double R_VALUE = 0;
double TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE;
bool SETUP_CONDITION_MADE = false;
int currentDate = 0;
int lastCheckedTime=0;
int BASE_TERM_FOR_BREAKOUT = 20;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---

  }
//+------------------------------------------------------------------+

void setup() {
    // 현재 가격이 신저가, 신고가인지 체크하는 로직
    // 이전의 고가, 저가가 발생한 날과의 날짜 차이 체크하기
    // close 가격이 이전의 고가, 저가 보다 바깥인지 체크하기
    // TARGET 가격을 이전의 고가, 저가로 세팅하고  SL은 새로 만들어진 고가, 저가.

    int highBarIndex = iHighest(NULL, BREAKOUT_TIMEFRAME, MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
    int lowBarIndex = iLowest(NULL, BREAKOUT_TIMEFRAME, MODE_LOW, BASE_TERM_FOR_BREAKOUT, 1);

    PrintFormat("highBarIndex : %d, lowBarIndex : %d", highBarIndex, lowBarIndex);
    if (highBarIndex == 1) {
        int previousHighIndex = iHighest(NULL, BREAKOUT_TIMEFRAME, MODE_HIGH, BASE_TERM_FOR_BREAKOUT - 1, 2);
        PrintFormat("previousHighIndex : %d", previousHighIndex);

        if (previousHighIndex - highBarIndex >= 3) {
            double day1Close = iClose(NULL, BREAKOUT_TIMEFRAME, 1);
            double prevHighPrice = iHigh(NULL, BREAKOUT_TIMEFRAME, previousHighIndex);
            if (day1Close >= prevHighPrice) {
                TARGET_BUY_PRICE = -1;
                TARGET_SELL_PRICE = prevHighPrice;
                TARGET_STOPLOSS_PRICE = iHigh(NULL, BREAKOUT_TIMEFRAME, 1);
                R_VALUE = fabs(TARGET_SELL_PRICE - TARGET_STOPLOSS_PRICE);
            }
        }
    }
    else if (lowBarIndex == 1) {
        int previousLowIndex = iLowest(NULL, BREAKOUT_TIMEFRAME, MODE_LOW, BASE_TERM_FOR_BREAKOUT - 1, 2);
        PrintFormat("previousLowIndex : %d", previousLowIndex);

        if (previousLowIndex - lowBarIndex >= 3) {
            double day1Close = iClose(NULL, BREAKOUT_TIMEFRAME, 1);
            double prevLowPrice = iLow(NULL, BREAKOUT_TIMEFRAME, previousLowIndex);
            if (day1Close <= prevLowPrice) {
                TARGET_SELL_PRICE = -1;
                TARGET_BUY_PRICE = prevLowPrice;
                TARGET_STOPLOSS_PRICE = iLow(NULL, BREAKOUT_TIMEFRAME, 1);
                R_VALUE = fabs(TARGET_BUY_PRICE - TARGET_STOPLOSS_PRICE);
            }
        }
    }
}
