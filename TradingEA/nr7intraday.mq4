//+------------------------------------------------------------------+
//|                                                  NR7Intraday.mq4 |
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

input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 2000;

ENUM_TIMEFRAMES BREAKOUT_TIMEFRAME = PERIOD_D1;
bool IsNR7PositionExist = false;
int CURRENT_CMD_NR7 = OP_BUY; // 0 : Buy  1 : Sell
double OpenPriceNR7 = 0;
double TARGET_STOPLOSS = 0;
double RValueNR7 = 0;
double TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE;

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
    Comment(StringFormat("Dollar per point : %f\nR Value : %f\nShow prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n",
    DOLLAR_PER_POINT, RValueNR7, Ask, Bid, TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));
  }
//+------------------------------------------------------------------+

bool checkSetup() {
    double atrList[8];
    ArrayFill(atrList, 1, 7, 999999999);
    for (int i = 1; i < 8; i++) {
        double atrValue = iATR(NULL, BREAKOUT_TIMEFRAME, i);
        atrList[i] = atrValue;
    }

    PrintFormat("Current ATR : [%f, %f, %f, %f, %f, %f, %f]", atrList[1], atrList[2], atrList[3], atrList[4], atrList[5], atrList[6], atrList[7]);

    // Check atrList[1] is Minimum
    int minimumValue = ArrayMinimum(atrList, 7, 1);
    PrintFormat("Minimum ATR Index : %d", minimumValue);

    if (minimumValue == -1) return false;
    else if (minimumValue != 1) return false;

    // Check Intrady    compare 1 and 2
    double highOf2DaysAgo = iHigh(NULL, BREAKOUT_TIMEFRAME, 2);
    double lowOf2DaysAgo = iLow(NULL, BREAKOUT_TIMEFRAME, 2);

    double highOf1DaysAgo = iHigh(NULL, BREAKOUT_TIMEFRAME, 1);
    double lowOf1DaysAgo = iLow(NULL, BREAKOUT_TIMEFRAME, 1);

    if (isZero(highOf1DaysAgo) || isZero(highOf2DaysAgo) || isZero(lowOf1DaysAgo) || isZero(lowOf2DaysAgo)) return false;

    if (isSmaller(highOf1DaysAgo, highOf2DaysAgo) && isBigger(lowOf1DaysAgo, lowOf2DaysAgo)) {
        TARGET_BUY_PRICE = highOf1DaysAgo;
        TARGET_SELL_PRICE = lowOf1DaysAgo;
        RValueNR7 = TARGET_BUY_PRICE - TARGET_SELL_PRICE;

        return true;
    }
    return false;
}

void checkBreakout() {
    double currentPrice = Close[0];
    double tradableLotSize = getUnitSizeNR7();

    if (isZero(tradableLotSize)) {
        Print("checkBreakout :: Tradable Lot Size is Zero. Check Logs!");
        return;
    }

    // 현재 가격이 전일 고가보다 높은 경우
    if (currentPrice > TARGET_BUY_PRICE) {
        Print("Send Buy Order");
        OrderSend(NULL, OP_BUY, MAX_LOT_SIZE_PER_ORDER, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue);
        IsNR7PositionExist = true;
        CURRENT_CMD_NR7 = OP_BUY;
    }
    // 현재 가격이 전일 저가보다 낮은 경우
    else if (currentPrice < TARGET_SELL_PRICE) {
        Print("Send Sell Order");
        IsNR7PositionExist = true;
        CURRENT_CMD_NR7 = OP_SELL;
    }
}

void checkStopLoss() {
    // 현재 포지션을 가지고 있는가?  이건 checkStopLoss 함수를 호출하는 시점에 체크하도록 위치 변경이 필요.
    if (!IsNR7PositionExist) return;

    double currentPrice = Close[0];

    // Buy 포지션인 경우
    if (CURRENT_CMD_NR7 == OP_BUY) {
        if (currentPrice <= TARGET_STOPLOSS) {
            Print("Close position");
            return;
        }

        double diffPrice = fabs(currentPrice - OpenPriceNR7);
        int rMultiple = diffPrice / RValueNR7;
        if (rMultiple > 0) {
            double tempStoplossNR7 = OpenPriceNR7 + RValueNR7 * (rMultiple - 0.3);
            PrintFormat("rMultiple : %d, TempSL : %f", rMultiple, tempStoplossNR7);
            if (tempStoplossNR7 > TARGET_STOPLOSS) TARGET_STOPLOSS = tempStoplossNR7;
        }
    }
    // Sell 포지션인 경우
    else {
        if (currentPrice >= TARGET_STOPLOSS) {
            Print("Close position");
            return;
        }

        double diffPrice = fabs(currentPrice - OpenPriceNR7);
        int rMultiple = diffPrice / RValueNR7;
        if (rMultiple > 0) {
            double tempStoplossNR7 = OpenPriceNR7 - RValueNR7 * (rMultiple - 0.3);
            PrintFormat("rMultiple : %d, TempSL : %f", rMultiple, tempStoplossNR7);
            if (tempStoplossNR7 < TARGET_STOPLOSS) TARGET_STOPLOSS = tempStoplossNR7;
        }
    }
}

double getUnitSizeNR7() {
    double tradableLotSize = 0;

    // Turtle처럼 tick 체크하는 곳에서 체크하는게 좋을까?
    double DOLLAR_PER_POINT = MarketInfo(NULL, MODE_TICKVALUE) / MarketInfo(NULL, MODE_TICKSIZE);
    if (isZero(DOLLAR_PER_POINT)) {
        Print("getUnitSizeNR7 :: DOLLAR_PER_POINT is Zero. Need to check!");
    }
    else {
        double dollarVolatility = RValueNR7 * DOLLAR_PER_POINT;

        double maxRiskForAccount = NOTIONAL_BALANCE * RISK;

        double maxLotBasedOnDollarVolatility = maxRiskForAccount / dollarVolatility;

        double tradableMinLotSize = MarketInfo(NULL, MODE_MINLOT);
        double requiredMinBalance = tradableMinLotSize * dollarVolatility / RISK;

        if (maxLotBasedOnDollarVolatility >= tradableMinLotSize) {
            tradableLotSize = maxLotBasedOnDollarVolatility - MathMod(maxLotBasedOnDollarVolatility, tradableMinLotSize);
        }
        else {
            PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
        }
    }

    // PrintFormat("You can buy %f Lots!", tradableLotSize);
    return tradableLotSize;
}
