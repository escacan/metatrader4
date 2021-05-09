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

extern int MAGICNO = 4;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 2000;

ENUM_TIMEFRAMES BREAKOUT_TIMEFRAME = PERIOD_D1;
bool IsNR7PositionExist = false;
int CURRENT_CMD_NR7 = OP_BUY; // 0 : Buy  1 : Sell
int CURRENT_POSITION_TICKET_NUMBER = 0;
double RValueNR7 = 0;
double TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE;
bool SETUP_CONDITION_MADE = false;
int currentDate = 0;
int lastCheckedTime=0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
    Print("Init NR7Intraday EA");
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
   datetime currentTime = TimeCurrent();
   int currentCheckTime = TimeMinute(currentTime);

   if (lastCheckedTime == currentCheckTime) {
      return;
   }
   else {
      lastCheckedTime = currentCheckTime;
   }

    Comment(StringFormat("R Value : %f\nShow prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n",
        RValueNR7, Ask, Bid, TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));

    if (IsNR7PositionExist) {
        checkStopLoss();
    }
    else {
        MqlDateTime strDate;
        TimeToStruct(currentTime, strDate);

        // Daily Update
        if (strDate.day != currentDate) {
            currentDate = strDate.day;
            SETUP_CONDITION_MADE = checkSetup();
        }
    }

    if (SETUP_CONDITION_MADE && !IsNR7PositionExist) {
        checkBreakout();
    }
  }
//+------------------------------------------------------------------+

bool checkSetup() {
    double atrList[8];
    ArrayFill(atrList, 1, 7, 999999999);
    for (int i = 1; i < 8; i++) {
        double atrValue = iATR(NULL, BREAKOUT_TIMEFRAME, 1, i);
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

    // TODO : 포지션이 있다면 아래 값들을 업데이트 하면 안된다!!
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
    double openPrice = Open[0];

   if (isZero(currentPrice) || isZero(openPrice)) {
      Print("canSendOrder :: Failed to Get current Price Data");
      return;
   }


    double tradableLotSize = getUnitSizeNR7();

    if (isZero(tradableLotSize)) {
        Print("checkBreakout :: Tradable Lot Size is Zero. Check Logs!");
        return;
    }

    int ticketNum = 0;

    // 현재 가격이 전일 고가보다 높은 경우 && Target 가격을 돌파하는 경우
    // TODO : 현재 가격과 Target 가격과 차이가 너무 많이 나는 경우를 필터링 해야한다!
    if (isBigger(currentPrice, TARGET_BUY_PRICE) && isSmaller(openPrice, TARGET_BUY_PRICE)) {
        Print("Send Buy Order");
        ticketNum = OrderSend(NULL, OP_BUY, tradableLotSize, Ask, 3, 0, 0, "", MAGICNO, 0, clrBlue);
        if (ticketNum < 0) {
            Print("OrderSend failed with error #",GetLastError());
        }
        else {
            CURRENT_POSITION_TICKET_NUMBER = ticketNum;
            IsNR7PositionExist = true;
            CURRENT_CMD_NR7 = OP_BUY;
            TARGET_STOPLOSS_PRICE = TARGET_SELL_PRICE;
        }
    }
    // 현재 가격이 전일 저가보다 낮은 경우 && Target 가격을 돌파하는 경우
    // TODO : 현재 가격과 Target 가격과 차이가 너무 많이 나는 경우를 필터링 해야한다!
    else if (isSmaller(currentPrice, TARGET_SELL_PRICE) && isBigger(openPrice, TARGET_SELL_PRICE)) {
        Print("Send Sell Order");
        ticketNum = OrderSend(NULL, OP_SELL, tradableLotSize, Bid, 3, 0, 0, "", MAGICNO, 0, clrBlue);
        if (ticketNum < 0) {
            Print("OrderSend failed with error #",GetLastError());
        }
        else {
            CURRENT_POSITION_TICKET_NUMBER = ticketNum;
            IsNR7PositionExist = true;
            CURRENT_CMD_NR7 = OP_SELL;
            TARGET_STOPLOSS_PRICE = TARGET_BUY_PRICE;
        }
    }
}

void checkStopLoss() {
    double currentPrice = Close[0];
    if (isZero(currentPrice)) {
        Print("canSendOrder :: Failed to Get current Price Data");
        return;
    }

    if (isZero(TARGET_STOPLOSS_PRICE)) {
        Print("checkStopLoss:: STARGET_STOPLOSS_PRICE is Zero! Need to check");
        return;
    }

    // Buy 포지션인 경우
    if (CURRENT_CMD_NR7 == OP_BUY) {
        if (currentPrice <= TARGET_STOPLOSS_PRICE) {
            Print("Close position");
            closeOrder();
            return;
        }

        double diffPrice = fabs(currentPrice - TARGET_BUY_PRICE);
        PrintFormat("Cur Price : %f, Target Buy : %f,  Diff : %f", currentPrice, TARGET_BUY_PRICE, diffPrice);

        int rMultiple = 0;
        if (isBigger(diffPrice, RValueNR7)) {
            while (diffPrice > 0) {
                rMultiple++;
                diffPrice -= RValueNR7;
            }
        }
        rMultiple--;
        PrintFormat("R Multiple : %d", rMultiple);
        if (rMultiple > 0) {
            double tempStoplossNR7 = TARGET_BUY_PRICE + RValueNR7 * (rMultiple - 0.3);
            PrintFormat("rMultiple : %d, TempSL : %f", rMultiple, tempStoplossNR7);
            if (tempStoplossNR7 > TARGET_STOPLOSS_PRICE) {
                PrintFormat("Update SL Price from %f -> %f", TARGET_STOPLOSS_PRICE, tempStoplossNR7);
                TARGET_STOPLOSS_PRICE = tempStoplossNR7;
            }
        }
    }
    // Sell 포지션인 경우
    else {
        if (currentPrice >= TARGET_STOPLOSS_PRICE) {
            Print("Close position");
            closeOrder();
            return;
        }

        double diffPrice = fabs(currentPrice - TARGET_SELL_PRICE);
        PrintFormat("Cur Price : %f, Target Sell : %f,  Diff : %f", currentPrice, TARGET_SELL_PRICE, diffPrice);
        int rMultiple = 0;
        if (isBigger(diffPrice, RValueNR7)) {
            while (diffPrice > 0) {
                rMultiple++;
                diffPrice -= RValueNR7;
            }
        }
        rMultiple--;
        PrintFormat("R Multiple : %d", rMultiple);
        if (rMultiple > 0) {
            double tempStoplossNR7 = TARGET_SELL_PRICE - RValueNR7 * (rMultiple - 0.3);
            PrintFormat("rMultiple : %d, TempSL : %f", rMultiple, tempStoplossNR7);
            if (tempStoplossNR7 < TARGET_STOPLOSS_PRICE) {
                PrintFormat("Update SL Price from %f -> %f", TARGET_STOPLOSS_PRICE, tempStoplossNR7);
                TARGET_STOPLOSS_PRICE = tempStoplossNR7;
            }
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

void closeOrder() {
    if (OrderSelect(CURRENT_POSITION_TICKET_NUMBER, SELECT_BY_TICKET, MODE_TRADES)) {
        if (CURRENT_CMD_NR7 == OP_BUY) {
            if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                PrintFormat("Fail OrderClose : Order ID = ", CURRENT_POSITION_TICKET_NUMBER);
            }
            else {
                IsNR7PositionExist = false;
                datetime currentTime = TimeCurrent();
                MqlDateTime strDate;
                TimeToStruct(currentTime, strDate);
                currentDate = strDate.day;

                SETUP_CONDITION_MADE = checkSetup();
            }
        }
        else {
            if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                PrintFormat("Fail OrderClose : Order ID = ", CURRENT_POSITION_TICKET_NUMBER);
            }
            else {
                IsNR7PositionExist = false;
                datetime currentTime = TimeCurrent();
                MqlDateTime strDate;
                TimeToStruct(currentTime, strDate);
                currentDate = strDate.day;

                SETUP_CONDITION_MADE = checkSetup();
            }
        }
    }
}
