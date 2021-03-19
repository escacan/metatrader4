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
input double   ATRSLportion = 0.5;
input double   Risk = 0.01;
input double   NotionalBalance = 5000;
input int      BASE_TERM_FOR_BREAKOUT = 55;

//--- Global Var
ENUM_TIMEFRAMES BASE_TIMEFRAME = PERIOD_D1;
double TARGET_BUY_PRICE, TARGET_SELL_PRICE;
int CURRENT_UNIT_COUNT = 0; // Maximum Unit count = 4;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("Start Turtle Trading");

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

void updateTargetPrice(int cmd) {
   if (cmd == OP_BUY) {
      if(currentPrice > TARGET_BUY_PRICE) result = 1;
   }
   else if (cmd == OP_SELL) {
      if (currentPrice < TARGET_SELL_PRICE) result = -1;
   }
}

void setInitialTargetPrice() {
   TARGET_BUY_PRICE = iHighest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
   TARGET_SELL_PRICE = iLowest(Symbol(), BASE_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);         
}

// Check whether current price break the highest/lowest price
// Return 1 if cur > highest
// Return -1 else if cur < lowest
// Return 0 else
int canSendOrder (int cmd) {
   int result = 0;
   double currentPrice = Close[0];

   if (cmd == OP_BUY) {
      if(currentPrice > TARGET_BUY_PRICE) result = 1;
   }
   else if (cmd == OP_SELL) {
      if (currentPrice < TARGET_SELL_PRICE) result = -1;
   }
   return result;
}

double getUnitSize() {
      double atrValue = iATR(Symbol(), BASE_TIMEFRAME, 20, 1);

      double tradableLotSize = 0;
      double dollarVolatility = atrValue / MarketInfo(Symbol(), MODE_TICKSIZE) * MarketInfo(Symbol(), MODE_TICKVALUE);
      // PrintFormat("Expected SL Price per 1 Lot : %f", dollarVolatility);
      
      double maxRiskForAccount = NotionalBalance * Risk;

      double maxLotBasedOnDollarVolatility = maxRiskForAccount / dollarVolatility;
      
      double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
      double requiredMinBalance = tradableMinLotSize * dollarVolatility / Risk;
      
      PrintFormat("Tradable Minimum Lot Size on Symbol : %f", tradableMinLotSize);
      PrintFormat("Required Minimum Account : %f", requiredMinBalance);

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

