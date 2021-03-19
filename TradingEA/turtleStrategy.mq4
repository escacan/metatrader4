//+------------------------------------------------------------------+
//|                                              Turtle Strategy.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern int MagicNo = 3; 
//--- input parameters
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 5000;
input int      BASE_TERM_FOR_BREAKOUT = 55;

//--- Global Var
ENUM_TIMEFRAMES BASE_TIMEFRAME = PERIOD_D1;
double TARGET_BUY_PRICE, TARGET_SELL_PRICE;
int CURRENT_UNIT_COUNT = 0;
int MAXIMUM_UNIT_COUNT = 4;
double N_VALUE = 0; // Need to Update Weekly
double UNIT_STEP_UP_PORTION = 0.5; // Use this value for calculating new target price
double DOLLAR_PER_POINT = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
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

  }

// Function which update Items we need to update Weekly
void updateWeekly() {
   N_VALUE = iATR(Symbol(), BASE_TIMEFRAME, 20, 1);
}

// Function which update Target Price based on latest order's CMD and OpenPrice.
void updateTargetPrice(int cmd, double latestOrderOpenPrice) {
   double diffPrice = N_VALUE * UNIT_STEP_UP_PORTION;
   
   if (CURRENT_UNIT_COUNT == MAXIMUM_UNIT_COUNT) {
      return;
   }
   else if (CURRENT_UNIT_COUNT > 0) {
      if (cmd == OP_BUY) {
         TARGET_BUY_PRICE = latestOrderOpenPrice + diffPrice;
      }
      else if (cmd == OP_SELL) {
         TARGET_SELL_PRICE = latestOrderOpenPrice - diffPrice;
      }
   }
   else if (CURRENT_UNIT_COUNT == 0) {
      TARGET_BUY_PRICE = iHighest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1) + MarketInfo(NULL, MODE_TICKSIZE);
      TARGET_SELL_PRICE = iLowest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1) - MarketInfo(NULL, MODE_TICKSIZE);
   }
}

// Function of Sending Order. When Order made, update Unit count and target price.
// Send order for [ (targetLotSize / Maximum lot size) + 1 ] times.
void sendOrders(int cmd) {
   // Send Order
   if (cmd == OP_BUY){
   
   }
   else if (cmd == OP_SELL) {

   }
   else {
      return;
   }

   if (true) { // OrderSend() == true
      // updateTargetPrice based on OrderOpenPrice
      double openPrice = 0; 

      updateTargetPrice(cmd, openPrice);
      CURRENT_UNIT_COUNT++;
   }
   else {
      PrintFormat("sendOrders:: OrderSend Failed - ", GetLastError());
   }
}

// Function of Check whether current price break the highest/lowest price
void canSendOrder (int cmd) {
   // if Current unit count is maximum, we should not order any more.
   if (CURRENT_UNIT_COUNT >= MAXIMUM_UNIT_COUNT) return;

   double currentPrice = Close[0];

   if (cmd == OP_BUY) {
      if(currentPrice >= TARGET_BUY_PRICE) sendOrders(cmd);
   }
   else if (cmd == OP_SELL) {
      if (currentPrice <= TARGET_SELL_PRICE) sendOrders(cmd);
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
      
      double maxRiskForAccount = NOTIONAL_BALANCE * RISK;

      double maxLotBasedOnDollarVolatility = maxRiskForAccount / dollarVolatility;
      
      double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
      double requiredMinBalance = tradableMinLotSize * dollarVolatility / RISK;
      
      PrintFormat("Tradable Minimum Lot Size on Symbol : %f", tradableMinLotSize);
      PrintFormat("Required Minimum Account : %f", requiredMinBalance);

      PrintFormat("Notional Balance : %f", NOTIONAL_BALANCE);

      tradableLotSize = maxLotBasedOnDollarVolatility - MathMod(maxLotBasedOnDollarVolatility, tradableMinLotSize);
      PrintFormat("You can trade : %f", tradableLotSize);

      // if (AccountBalance() < requiredMinBalance) {
      //    PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
      //    tradableLotSize = -1;
      // }
      // else {
      //    tradableLotSize = maxLotBasedOnDollarVolatility - MathMod(maxLotBasedOnDollarVolatility, tradableMinLotSize);
      //    PrintFormat("You can trade : %f", tradableLotSize);
      // }
      
      return tradableLotSize;      
}

