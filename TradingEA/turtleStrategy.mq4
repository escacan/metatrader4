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
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 5000;
input int      BASE_TERM_FOR_BREAKOUT = 55;
input int      BASE_TERM_FOR_PROFIT = 10;
input int      MAXIMUM_UNIT_COUNT = 4;
input double   UNIT_STEP_UP_PORTION = 0.5; // Use this value for calculating new target price
input double   STOPLOSS_PORTION = 2;
input ENUM_TIMEFRAMES PRICE_TIMEFRAME = PERIOD_M15;

//--- Global Var
ENUM_TIMEFRAMES BASE_TIMEFRAME = PERIOD_D1;
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
   DOLLAR_PER_POINT = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
   N_VALUE = iATR(Symbol(), BASE_TIMEFRAME, 20, 1);

   Print("Start Turtle Trading");
   PrintFormat("Dollar Per Point : %f", DOLLAR_PER_POINT);

   double tradableLotSize = getUnitSize();
 
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
   Comment(StringFormat("Show prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n",Ask,Bid,TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));

   datetime tempDate = TimeCurrent();
   int currentTime = TimeSeconds(tempDate);
   MqlDateTime strDate;
   TimeToStruct(tempDate, strDate);

   // Daily Update
   if (strDate.day != currentDate) {
      updateWeekly();
   }

   if (CURRENT_UNIT_COUNT == 0) updateTargetPrice();
   canSendOrder();
  }

// Function which update Items we need to update Weekly
void updateWeekly() {
   N_VALUE = iATR(Symbol(), BASE_TIMEFRAME, 20, 1);
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
         if (TARGET_STOPLOSS_PRICE < targetStopLoss) TARGET_STOPLOSS_PRICE = targetStopLoss;
         TARGET_BUY_PRICE = latestOrderOpenPrice + diffPrice;
      }
      else if (CURRENT_CMD == OP_SELL) {
         if (TARGET_STOPLOSS_PRICE > targetStopLoss) TARGET_STOPLOSS_PRICE = targetStopLoss;
         TARGET_SELL_PRICE = latestOrderOpenPrice - diffPrice;
      }
   }
   else if (CURRENT_UNIT_COUNT == 0) {
      int highBarIndex = iHighest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
      if (highBarIndex == -1) TARGET_BUY_PRICE = 99999999999999;
      else TARGET_BUY_PRICE = High[highBarIndex];

      int lowBarIndex = iLowest(Symbol(), BASE_TIMEFRAME,MODE_LOW, BASE_TERM_FOR_BREAKOUT, 1);
      if (lowBarIndex == -1) TARGET_SELL_PRICE = -9999999999;
      else TARGET_SELL_PRICE = Low[lowBarIndex];
   }
}

// Function of Sending Order. When Order made, update Unit count and target price.
// Send order for [ (targetLotSize / Maximum lot size) + 1 ] times.
void sendOrders(int cmd, double price) {
   // Send Order
   double stoplossPrice = N_VALUE * STOPLOSS_PORTION;
   string comment = "";
   int ticketNum;
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
         CURRENT_CMD = cmd;
         TICKET_ARR[CURRENT_UNIT_COUNT][sentOrderCount] = ticketNum;
      }
   }

   if (sentOrderCount > 0) {
      TICKET_ARR[CURRENT_UNIT_COUNT][0] = sentOrderCount;

      if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
         OPENPRICE_ARR[CURRENT_UNIT_COUNT] = OrderOpenPrice();
      }
      else {
         Alert("Fail OrderSelect : Order ID = ", ticketNum);
      }

      CURRENT_UNIT_COUNT++;

      updateTargetPrice();
   }
}

void closeAllOrders () {
   // Check STOP LOSS
   if (CURRENT_UNIT_COUNT > 0) {
      double currentPrice = iOpen(Symbol(), PRICE_TIMEFRAME, 0);
      double profitBuyPrice = 0;
      double profitSellPrice = 0;

      int highBarIndex = iHighest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_PROFIT, 1);
      if (highBarIndex == -1) profitSellPrice = 99999999999999;
      else profitSellPrice = High[highBarIndex];

      int lowBarIndex = iLowest(Symbol(), BASE_TIMEFRAME,MODE_LOW, BASE_TERM_FOR_PROFIT, 1);
      if (lowBarIndex == -1) profitBuyPrice = -9999999999;
      else profitBuyPrice = Low[lowBarIndex];

      Comment(StringFormat("ProfitBuyPrice = %f\nProfitSellPrice = %f\n",profitBuyPrice,profitSellPrice));

      // TODO : For each of Orders, stop loss is OrderOpen - 1/2 * N_Value
      // When the order closed, we should update ARR.

      // When Price is high and turned down to PROFIT PRICE, close All the orders
      // TODO : DETACH Stop Loss from Profit breakout.
      if (CURRENT_CMD == OP_BUY) {
         if (currentPrice <= TARGET_STOPLOSS_PRICE) {
            int totalTicketCount = TICKET_ARR[--CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                     Alert("Fail OrderClose : Order ID = ", ticketNum);
                  }
               }
            }
         }
         else if (currentPrice <= profitBuyPrice) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                        Alert("Fail OrderClose : Order ID = ", ticketNum);
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
            int totalTicketCount = TICKET_ARR[--CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                     Alert("Fail OrderClose : Order ID = ", ticketNum);
                  }
               }
            }
         }
         else if (currentPrice >= profitSellPrice) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                        Alert("Fail OrderClose : Order ID = ", ticketNum);
                     }
                  }
               }

               TICKET_ARR[unitIdx][0] = 0;
            }

            CURRENT_UNIT_COUNT = 0;
         }
      }
   }
}

// Function of Check whether current price break the highest/lowest price
void canSendOrder () {
   closeAllOrders();

   // TODO : Let's try with M15 Bar close price.
   double currentPrice = iOpen(Symbol(), PRICE_TIMEFRAME, 0);
   
   // if Current unit count is maximum, we should not order any more.
   if (CURRENT_UNIT_COUNT >= MAXIMUM_UNIT_COUNT) return;

   if(currentPrice >= TARGET_BUY_PRICE) {
      PrintFormat("Send Buy Order On Cur Price : %f, Target Buy Price : %f", currentPrice, TARGET_BUY_PRICE);
      sendOrders(OP_BUY, Ask);
   }
   else if (currentPrice <= TARGET_SELL_PRICE) {
      sendOrders(OP_SELL, Bid);
      PrintFormat("Send Sell Order On Cur Price : %f, Target Sell Price : %f", currentPrice, TARGET_SELL_PRICE);
   }
   return;
}

// Function of check Unit Size for 1% Risk
// TODO : Need to remove commented sources
double getUnitSize() {
      // if Current unit count is maximum, we should not order any more.
      if (CURRENT_UNIT_COUNT == MAXIMUM_UNIT_COUNT) return 0;

      double tradableLotSize = 0;
      double dollarVolatility = N_VALUE * DOLLAR_PER_POINT;
      // PrintFormat("Expected SL Price per 1 Lot : %f", dollarVolatility);
      double maxRiskForAccount = 0;

      if (NOTIONAL_BALANCE <= AccountBalance()) {
         maxRiskForAccount = NOTIONAL_BALANCE * RISK;
      }
      else {
         maxRiskForAccount = AccountBalance() * RISK;
      }

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

