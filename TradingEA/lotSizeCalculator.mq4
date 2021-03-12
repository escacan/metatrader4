//+------------------------------------------------------------------+
//|                                                         test.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
      double slPortionBasedOnATR = 0.5; // %
      double maxRiskPerTrade = 0.15; // %

      PrintFormat("Max Lot : %f", MarketInfo(NULL, MODE_MAXLOT));
      PrintFormat("Min Lot Size : %f", MarketInfo(NULL, MODE_MINLOT) );
      PrintFormat("Tick Size: %f", MarketInfo(NULL, MODE_TICKSIZE));
      PrintFormat("Tick Value: %f", MarketInfo(NULL, MODE_TICKVALUE));
      PrintFormat("Point Value: %f", MarketInfo(NULL, MODE_POINT));
      PrintFormat("Cur Balance : %f", AccountBalance());
      PrintFormat("Max Lisk Per Trade : %f", AccountBalance() * 0.1);
      PrintFormat("ATR : %f", iATR(NULL, PERIOD_D1, 1, 1));
      
      double ATR100forSL = iATR(NULL, PERIOD_D1, 1, 1) / MarketInfo(NULL, MODE_TICKSIZE) * MarketInfo(NULL, MODE_TICKVALUE);
      double expectedSL = ATR100forSL * slPortionBasedOnATR; // sl price for 1 lot
      PrintFormat("Expected SL Price per trade : %f", expectedSL);
      
      double maxRiskForAccount = AccountBalance() * maxRiskPerTrade;
      double maxLotBasedOnSL = maxRiskPerTrade / expectedSL;
      
      double tradableMinLotSize = MarketInfo(NULL, MODE_MINLOT);

      double requiredMinBalance = tradableMinLotSize * expectedSL / maxRiskPerTrade;
      PrintFormat("Required Minimum Account : %f", requiredMinBalance);
      
      PrintFormat("Lot Size Per SL : %f", maxLotBasedOnSL);
      PrintFormat("Available Min Lot Size : %f", MarketInfo(NULL, MODE_MINLOT));
      
      if (AccountBalance() < requiredMinBalance) {
         PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
         return 0;
      }
      
      if (MarketInfo(NULL, MODE_MINLOT) > maxLotBasedOnSL) {
         double tradableLotSize = (maxLotBasedOnSL / tradableMinLotSize) * tradableMinLotSize;
         PrintFormat("What you wanted : %f\nTradable Size : %f", maxLotBasedOnSL, tradableLotSize);
      }
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
