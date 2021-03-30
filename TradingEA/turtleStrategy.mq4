//+------------------------------------------------------------------+
//|                                              Turtle Strategy.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern int MAGICNO = 3; 
//--- input parameters
input int      MARKET_GROUP = 0; // 0: Forex,  1: Metal,  2: Crypto
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 5000;
input int      BASE_TERM_FOR_BREAKOUT = 55;
input int      BASE_TERM_FOR_PROFIT = 10;
input int      MAXIMUM_UNIT_COUNT = 4;
input double   UNIT_STEP_UP_PORTION = 0.5; 
input double   STOPLOSS_PORTION = 0.5;
input ENUM_TIMEFRAMES BREAKOUT_TIMEFRAME = PERIOD_D1;
input ENUM_TIMEFRAMES PRICE_TIMEFRAME = PERIOD_M15;

//--- Global Var
double TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE;
int CURRENT_UNIT_COUNT = 0;
int CURRENT_CMD = OP_BUY; // 0 : Buy  1 : Sell
double N_VALUE = 0; // Need to Update Weekly
double DOLLAR_PER_POINT = 0;
int currentDate = 0;

int TICKET_ARR[4][200] = {0};
double OPENPRICE_ARR[4] = {0};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("Start Turtle Trading");

   setGlobalVar();

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("Close Strategy with reason : %s", reason);
   return;
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- 
   // Daily Update
   if (strDate.day != currentDate) {
      currentDate = strDate.day;

      DOLLAR_PER_POINT = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
      N_VALUE = iATR(Symbol(), BREAKOUT_TIMEFRAME, 20, 1);
   }

   double tradableSize = getUnitSize();
   PrintFormat("You can trade %f on this Item", tradableSize);

   if (tradableSize == 0) return;

   Comment(StringFormat("Current Unit Count : %d\nShow prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n",CURRENT_UNIT_COUNT,Ask,Bid,TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));

   datetime tempDate = TimeCurrent();
   int currentTime = TimeSeconds(tempDate);
   MqlDateTime strDate;
   TimeToStruct(tempDate, strDate);

   if (CURRENT_UNIT_COUNT == 0) updateTargetPrice();
   canSendOrder();
  }

// Function which update Target Price based on latest order's CMD and OpenPrice.
void updateTargetPrice() {
   double diffPrice = N_VALUE * UNIT_STEP_UP_PORTION;
   double diffStopLoss = N_VALUE * STOPLOSS_PORTION;
   if (CURRENT_CMD == OP_BUY) diffStopLoss *= -1;

   double latestOrderOpenPrice = 0;
   double targetStopLoss = 0;

   if (CURRENT_UNIT_COUNT > 0) {
      latestOrderOpenPrice = OPENPRICE_ARR[CURRENT_UNIT_COUNT - 1];
      targetStopLoss = latestOrderOpenPrice + diffStopLoss;

      if (CURRENT_CMD == OP_BUY) {
         TARGET_STOPLOSS_PRICE = targetStopLoss;
         TARGET_BUY_PRICE = latestOrderOpenPrice + diffPrice;
      }
      else if (CURRENT_CMD == OP_SELL) {
         TARGET_STOPLOSS_PRICE = targetStopLoss;
         TARGET_SELL_PRICE = latestOrderOpenPrice - diffPrice;
      }
   }
   else if (CURRENT_UNIT_COUNT == 0) {
      int highBarIndex = iHighest(Symbol(), BREAKOUT_TIMEFRAME, MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
      if (highBarIndex == -1) TARGET_BUY_PRICE = 99999999999999;
      else TARGET_BUY_PRICE = iHigh(Symbol(), BREAKOUT_TIMEFRAME, highBarIndex);

      int lowBarIndex = iLowest(Symbol(), BREAKOUT_TIMEFRAME, MODE_LOW, BASE_TERM_FOR_BREAKOUT, 1);
      if (lowBarIndex == -1) TARGET_SELL_PRICE = -9999999999;
      else TARGET_SELL_PRICE = iLow(Symbol(), BREAKOUT_TIMEFRAME, lowBarIndex);
   }
}

// Function of Sending Order. When Order made, update Unit count and target price.
// Send order for [ (targetLotSize / Maximum lot size) + 1 ] times.
void sendOrders(int cmd, double price) {
   // Send Order
   double stoplossPrice = N_VALUE * STOPLOSS_PORTION;
   string comment = "";
   int ticketNum = -1;
   TICKET_ARR[CURRENT_UNIT_COUNT][0] = 0;
   int sentOrderCount = 0;

   if (cmd == 0) {
         comment = "Send BUY order";
         stoplossPrice *= -1;
   }
   else if (cmd == 1) {
         comment = "Send SELL order";
   }

   double lotSize = getUnitSize();
   
   while (lotSize > 0) {
      if (lotSize >= MAX_LOT_SIZE_PER_ORDER) {
         lotSize -= MAX_LOT_SIZE_PER_ORDER;
         PrintFormat("Order Lot Size : %f", MAX_LOT_SIZE_PER_ORDER);
         ticketNum = OrderSend(Symbol(), cmd, MAX_LOT_SIZE_PER_ORDER, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue);
      }
      else {
         PrintFormat("Order Lot Size : %f", lotSize);
         ticketNum = OrderSend(Symbol(), cmd, lotSize, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue);
         lotSize = 0;
      }

      // There could be multiple orders for same unit. Fix Arr index
      if (ticketNum) {
         sentOrderCount++;
         TICKET_ARR[CURRENT_UNIT_COUNT][sentOrderCount] = ticketNum;
      }
   }

   if (sentOrderCount > 0) {
      CURRENT_CMD = cmd;
      TICKET_ARR[CURRENT_UNIT_COUNT][0] = sentOrderCount;

      if (ticketNum == -1) {
         for (int idx = 1; idx<= sentOrderCount; idx++) {
            ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][idx];

            if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
               OPENPRICE_ARR[CURRENT_UNIT_COUNT] = OrderOpenPrice();
               break;
            }
            else {
               Alert("Fail OrderSelect : Order ID = ", ticketNum);
            }
         }
      }
      else {
         if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
            OPENPRICE_ARR[CURRENT_UNIT_COUNT] = OrderOpenPrice();
         }
         else {
            Alert("Fail OrderSelect : Order ID = ", ticketNum);
         }
      }

      CURRENT_UNIT_COUNT++;

      updateTargetPrice();
   }
}

void closeAllOrders () {
   bool closedOrderExist = false;

   // Check STOP LOSS
   if (CURRENT_UNIT_COUNT > 0) {
      double currentPrice = iOpen(Symbol(), PRICE_TIMEFRAME, 0);
      double profitBuyPrice = 0;
      double profitSellPrice = 0;

      int highBarIndex = iHighest(Symbol(), BREAKOUT_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_PROFIT, 1);
      if (highBarIndex == -1) profitSellPrice = 99999999999999;
      else profitSellPrice = iHigh(Symbol(), BREAKOUT_TIMEFRAME, highBarIndex);

      int lowBarIndex = iLowest(Symbol(), BREAKOUT_TIMEFRAME,MODE_LOW, BASE_TERM_FOR_PROFIT, 1);
      if (lowBarIndex == -1) profitBuyPrice = -9999999999;
      else profitBuyPrice = iLow(Symbol(), BREAKOUT_TIMEFRAME, lowBarIndex);

      if (CURRENT_CMD == OP_BUY) {
         if (currentPrice <= TARGET_STOPLOSS_PRICE) {
            CURRENT_UNIT_COUNT--;
            int totalTicketCount = TICKET_ARR[CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               PrintFormat("215::Close order of UNIT %d", CURRENT_UNIT_COUNT);

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                     Alert("Fail OrderClose : Order ID = ", ticketNum);
                  }
                  else {
                     closedOrderExist = true;
                  }
               }
            }
         }
         
         if (currentPrice <= profitBuyPrice) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  PrintFormat("234::Close order of UNIT %d", CURRENT_UNIT_COUNT);

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                        Alert("Fail OrderClose : Order ID = ", ticketNum);
                     }
                     else {
                        closedOrderExist = true;
                     }
                  }
               }

               TICKET_ARR[unitIdx][0] = 0;
            }

            CURRENT_UNIT_COUNT = 0;
         }
      }
      else if (CURRENT_CMD == OP_SELL) {
         if (currentPrice >= TARGET_STOPLOSS_PRICE ) {
            CURRENT_UNIT_COUNT--;
            int totalTicketCount = TICKET_ARR[CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                     Alert("Fail OrderClose : Order ID = ", ticketNum);
                  }
                  else {
                     closedOrderExist = true;
                  }
               }
            }
         }
         
         if (currentPrice >= profitSellPrice) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                        Alert("Fail OrderClose : Order ID = ", ticketNum);
                     }
                     else {
                        closedOrderExist = true;
                     }
                  }
               }

               TICKET_ARR[unitIdx][0] = 0;
            }

            CURRENT_UNIT_COUNT = 0;
         }
      }
   }

   if (closedOrderExist) updateTargetPrice();
}

// Function of Check whether current price break the highest/lowest price
void canSendOrder () {
   closeAllOrders();

   // if Current unit count is maximum, we should not order any more.
   if (CURRENT_UNIT_COUNT >= MAXIMUM_UNIT_COUNT) return;

   // TODO : Need to check total UNIT count.
   // Strong Related : 6
   // Loosely related : 10
   // Single Direction : 12 per dir

   // TODO : Let's try with M15 Bar close price.
   double currentPrice = iOpen(Symbol(), PRICE_TIMEFRAME, 0);

   if (CURRENT_UNIT_COUNT > 0) {
      if(currentPrice >= TARGET_BUY_PRICE && CURRENT_CMD == OP_BUY) {
         if (!checkTotalMarketsUnitCount(CURRENT_CMD)) return;

         PrintFormat("Send Buy Order On Cur Price : %f, Target Buy Price : %f", currentPrice, TARGET_BUY_PRICE);
         sendOrders(OP_BUY, Ask);
      }
      else if (currentPrice <= TARGET_SELL_PRICE && CURRENT_CMD == OP_SELL) {
         if (!checkTotalMarketsUnitCount(CURRENT_CMD)) return;

         PrintFormat("Send Sell Order On Cur Price : %f, Target Sell Price : %f", currentPrice, TARGET_SELL_PRICE);
         sendOrders(OP_SELL, Bid);
      }
   }
   else {
      if(currentPrice >= TARGET_BUY_PRICE) {
         if (!checkTotalMarketsUnitCount(OP_BUY)) return;

         PrintFormat("Send Buy Order On Cur Price : %f, Target Buy Price : %f", currentPrice, TARGET_BUY_PRICE);
         sendOrders(OP_BUY, Ask);
      }
      else if (currentPrice <= TARGET_SELL_PRICE) {
         if (!checkTotalMarketsUnitCount(OP_SELL)) return;

         sendOrders(OP_SELL, Bid);
         PrintFormat("Send Sell Order On Cur Price : %f, Target Sell Price : %f", currentPrice, TARGET_SELL_PRICE);
      }
   }
}

// Function of check Unit Size for 1% Risk
// TODO : Need to remove commented sources
double getUnitSize() {
      // if Current unit count is maximum, we should not order any more.
      if (CURRENT_UNIT_COUNT == MAXIMUM_UNIT_COUNT) return 0;

      double tradableLotSize = 0;
      double dollarVolatility = N_VALUE * DOLLAR_PER_POINT;
      
      double maxRiskForAccount = NOTIONAL_BALANCE * RISK;

      double maxLotBasedOnDollarVolatility = maxRiskForAccount / dollarVolatility;
      
      double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
      double requiredMinBalance = tradableMinLotSize * dollarVolatility / RISK;
      
      if (maxLotBasedOnDollarVolatility >= tradableMinLotSize) {
         tradableLotSize = maxLotBasedOnDollarVolatility - MathMod(maxLotBasedOnDollarVolatility, tradableMinLotSize);
      }
      else {
         PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
      }

      // PrintFormat("You can buy %f Lots!", tradableLotSize);      
      return tradableLotSize;      
}

// Function of checking current Item's Power.
// Check price movement during the 3 months
double checkPower() {
   // Current Price - Price Prior to 3 months  /  N  
   double currentPrice = iOpen(Symbol(), PERIOD_D1, 0);
   double prevPrice = iOpen(Symbol(), PERIOD_D1, 90);

   double result = (currentPrice - prevPrice) / N_VALUE;
   return result;
}

// Function of setting GlobalVar for Current Item's UNIT Count.
void setGlobalVar() {
   string globalVarName = "";
   if (MARKET_GROUP == 0) globalVarName += "GROUP0_";
   else if (MARKET_GROUP == 1) globalVarName += "GROUP1_";
   else if (MARKET_GROUP == 2) globalVarName += "GROUP2_";

   globalVarName += Symbol();

   if(GlobalVariableSet(globalVarName, CURRENT_UNIT_COUNT) == 0) {
      PrintFormat("GlobalVariableSet Failed : ", GetLastError());
   }
}

// Function of counting Total Market's Unit Count
// Strong Related : 6
// Loosely related : 10
// Single Direction : 12 per dir
bool checkTotalMarketsUnitCount(int cmd) {
   int totalBuyUnitCount = 0;
   int totalSellUnitCount = 0;
   int marketUnitCount[3][2] = {0}; // marketUnitCount[MARKET_GROUP][0: Buy, 1: Sell]
   string symbolName = "";
   int unitCount = 0;
   int symbolMarketGroup = 0;

   int totalVarNum = GlobalVariablesTotal();
   for (int i = 0; i< totalVarNum; i++) {
      symbolName = GlobalVariableName(i);
      unitCount = (int)GlobalVariableGet(symbolName);

      if(StringFind(symbolName,"GROUP", 0) != -1) {
         symbolMarketGroup = symbolName[5] - '0';

         if (unitCount >= 0) {
            totalBuyUnitCount += unitCount;
            marketUnitCount[symbolMarketGroup][0] += unitCount;
         }
         else {
            totalSellUnitCount -= unitCount;
            marketUnitCount[symbolMarketGroup][1] -= unitCount;
         }
      }
   }

   // PrintFormat("Total BUY : %d, SELL : %d", totalBuyUnitCount, totalSellUnitCount);
   // for(int i= 0; i< 3; i++){
   //    PrintFormat("For Group %d,  BUY : %d, SELL : %d", i, marketUnitCount[i][0],marketUnitCount[i][1]);
   // }

   if (cmd == OP_BUY && totalBuyUnitCount < 12) {
      if (marketUnitCount[MARKET_GROUP][0] < 6) return true;
   }
   else if (cmd == OP_SELL && totalSellUnitCount < 12) {
      if (marketUnitCount[MARKET_GROUP][1] < 6) return true;
   }

   return false;
}