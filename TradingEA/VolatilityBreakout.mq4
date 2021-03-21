//+------------------------------------------------------------------+
//|                                           VolatilityBreakout.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern int MAGICNO = 1; 
//--- input parameters
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   ATR_PORTION = 1;
input double   ATR_STOPLOSS = 0.5;
input double   RISK = 0.15;
input double   BUY_TDW = 7;   // (0-Sunday, 1-Monday, ... ,6-Saturday)
input double   SELL_TDW = 7;   // (0-Sunday, 1-Monday, ... ,6-Saturday)
input bool     USE_OBV = true;
input bool     USE_RSI = true;
input int      OBV_BASE = 2;
input int      RSI_PERIOD = 14;
input bool     USE_TIMEOUT_ORDER = false;
input int      TIMEOUT_BASE = 5;

//--- Global Var
ENUM_TIMEFRAMES BASE_TIMEFRAME = PERIOD_D1;
int currentDate = 0;
double TARGET_BUY, TARGET_SELL, POSSIBLE_LOT_SIZE, YESTERDAY_ATR;
double DOLLAR_VOLATILITY = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE) * MarketInfo(Symbol(), MODE_POINT);
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("Start VolatilityBreakout Trading");
   
   PrintFormat("Cur ATR portion : %f, ATR SL portion : %f", ATR_PORTION, ATR_STOPLOSS);
   PrintFormat("Max Lot Size per Order : %f", MAX_LOT_SIZE_PER_ORDER);
 
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
      int total = OrdersTotal(); // 현재 Symbol에서 진입한 Order Count를 가져와야 한다! 다양한 마켓에서 사용 가능하기 때문.
      datetime tempDate = TimeCurrent();
      int currentTime = TimeSeconds(tempDate);
      MqlDateTime strDate;
      TimeToStruct(tempDate, strDate);

      bool positionExist = false;
      bool newOrderExist = false;
      
      // When New day Started
      if (strDate.day != currentDate) {
         currentDate = strDate.day;
         // PrintFormat("New Day : %d", currentDate);
         YESTERDAY_ATR = iATR(Symbol(), BASE_TIMEFRAME, 1, 1);
         double targetRange = YESTERDAY_ATR * ATR_PORTION;
         double todayOpen = iOpen(Symbol(), BASE_TIMEFRAME, 0);
         
         PrintFormat("Today: %d, OpenPrice: %f, yesterday ATR: %f", currentDate, todayOpen, YESTERDAY_ATR); 

         bailoutOrders(currentTime, total, todayOpen);
         
         POSSIBLE_LOT_SIZE = getPossibleLotSize();
         TARGET_BUY = todayOpen + targetRange;
         TARGET_SELL = todayOpen - targetRange;   
      }
      else {
         if (POSSIBLE_LOT_SIZE == 0) return;

         int OpenRes = -1;
         double currentPrice = Close[0];

         if (currentPrice >= TARGET_BUY) {
            // PrintFormat("Cur Ask : %f, target Buy : %f", Ask, TARGET_BUY);

            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_BUY) {
                           Print("Buy Order Exist");
                           positionExist = true;
                        }
                        else if (OrderType() == OP_SELL) {
                           Print("Sell Order Exist");
                           if(OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrRed)){
                              Print("Buy Momentum is found. Close Sell Order");
                           }
                           else {
                              PrintFormat("Close Order Failed :: ", GetLastError());
                           }
                        } 
                     }
                  }
               }
            }
            
            if (!positionExist){
            //    Print("BUY Order Block");
               newOrderExist = sendOrders(OP_BUY, Ask, POSSIBLE_LOT_SIZE);
            }
         }
         else if (currentPrice <= TARGET_SELL) {
            // PrintFormat("Cur Bid : %f, target Sell : %f", Bid, TARGET_SELL);

            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_SELL) {
                           Print("Sell Order Exist");
                           positionExist = true;
                        }
                        else if (OrderType() == OP_BUY) {
                           Print("Buy Order Exist");
                           if(OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrRed)){
                              Print("Sell Momentum is found. Close Buy Order");
                           }
                           else{
                              PrintFormat("Close Buy Order Failed : ", GetLastError());
                           }
                        }
                     }
                  }
               }
            }
            
            if (!positionExist) {
            //    Print("SELL Order Block");
               newOrderExist = sendOrders(OP_SELL, Bid, POSSIBLE_LOT_SIZE);
            }         
         } 

         if (newOrderExist) {
            Print("StopLoss setting block");   
            
            total = OrdersTotal();
            // Set Cur price on orders
            
            for(int i= 0; i< total; i++){
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                  if(OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()) {
                     if (OrderType() == OP_BUY){
                        if(OrderStopLoss()== 0){
                           if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() - YESTERDAY_ATR * ATR_STOPLOSS, 0, 0, clrWhite)){
                              Print("Stop Set on Buy Order");                        
                           }
                           else {
                              Print("Failed on set Stop on Buy Order");
                           }
                        }
                     }
                     else if (OrderType() == OP_SELL) {
                        if (OrderStopLoss() == 0){
                           if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + YESTERDAY_ATR * ATR_STOPLOSS, 0, 0, clrWhite)){
                              Print("Stop Set on Sell Order");                        
                           }
                           else {
                              Print("Failed on set Stop on Sell Order");
                           }
                        }
                     }
                  }
               }
            }
         }
      }
  }

bool sendOrders(int cmd, double price, double lotSize) {
      int completedOrderCount= 0;
      string comment = "";

      if (cmd == 0) comment = "Send BUY order";
      else if (cmd == 1) comment = "Send SELL order";
      
      while (lotSize - MAX_LOT_SIZE_PER_ORDER > 0.0) {
         lotSize -= MAX_LOT_SIZE_PER_ORDER;
         PrintFormat("Order Lot Size : %f", MAX_LOT_SIZE_PER_ORDER);
         if (OrderSend(Symbol(), cmd, MAX_LOT_SIZE_PER_ORDER, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue)) {
            completedOrderCount++;                   
         }
         else {
            Print("sendOrders::206:: OrderSend Failed, ", GetLastError());         
         }
      }
   
      if (lotSize > 0) {
         PrintFormat("Order Lot Size : %f", lotSize);
         if (OrderSend(Symbol(), cmd, lotSize, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue)) {
            completedOrderCount++;             
         }
         else {
            Print("sendOrders::216:: OrderSend Failed, ", GetLastError());         
         }
      }

      PrintFormat("Total OrderSend Count : %d", completedOrderCount);

      return completedOrderCount > 0;
   }

double getPossibleLotSize() {
      double tradableLotSize = 0;
      double ATR100forSL = YESTERDAY_ATR * DOLLAR_VOLATILITY;
      double expectedSL = ATR100forSL * ATR_STOPLOSS; // sl price for 1 lot
      // PrintFormat("Expected SL Price per 1 Lot : %f", expectedSL);
      
      double maxRiskForAccount = AccountBalance() * RISK;
      // PrintFormat("Account : %f,  Max Lisk per trade : %f", AccountBalance(), maxRiskForAccount);
      double maxLotBasedOnSL = maxRiskForAccount / expectedSL;
      
      double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
      double requiredMinBalance = tradableMinLotSize * expectedSL / RISK;
      
      PrintFormat("Tradable Minimum Lot Size on Symbol : %f", tradableMinLotSize);

      PrintFormat("Required Minimum Account : %f", requiredMinBalance);
      
      PrintFormat("Lot Size Per SL : %f", maxLotBasedOnSL);
      
      if (AccountBalance() < requiredMinBalance) {
         PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
         tradableLotSize = -1;
      }
      else {
         tradableLotSize = maxLotBasedOnSL - MathMod(maxLotBasedOnSL, tradableMinLotSize);
         PrintFormat("What you wanted : %f\nTradable Size : %f", maxLotBasedOnSL, tradableLotSize);
      }
      
      return tradableLotSize;      
}

void bailoutOrders(int currentTime, int totalOrderCount, double openPrice) {
      bool CloseSuccess = false;
      int orderTime = 0;

      if (totalOrderCount > 0) {
         Print("Bailout Exit Condition Check");
         for (int idx = 0; idx < totalOrderCount; idx++){
            if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
               if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                  orderTime = TimeSeconds(OrderOpenTime());

                  if (OrderType() == OP_BUY) {
                     // 시가가 진입가보다 높은 경우
                     // 혹은 주문하고 기준일이 지나간 경우
                     if (openPrice > OrderOpenPrice()) {
                        CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Bid, 3, White);
                        if (CloseSuccess){
                           Print("Bailout Buy Order");
                        }
                        else {
                           Print("Bailout Buy Order Failed, ", GetLastError());
                        }
                     }
                  }
                  else if (OrderType() == OP_SELL) {
                     if (openPrice < OrderOpenPrice()) {
                        CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Ask, 3, White);
                        if (CloseSuccess) {
                           Print("Bailout Sell Order");
                        }
                        else {
                           Print("Bailout Sell Failed, ", GetLastError());
                        }
                     }                        
                  }
               }
            }
         }
      }
   }

// Check whether OBV increased between 5 days
bool checkOBV() {
      // Return true when OBV is increased
      // Return false when OBV is decreased
   
      double latestObvValue = iOBV(Symbol(), BASE_TIMEFRAME, 0, 1);
      double oldObvValue = iOBV(Symbol(), BASE_TIMEFRAME, 0, 1 + OBV_BASE);  

      bool res = true;
      if (latestObvValue - oldObvValue < 0) res = false;

      return res;
   } 

bool checkRSI() {
      // Return true when RSI > 0.5
      // Return false when RSI < 0.5

      double rsiValue = iRSI(Symbol(), BASE_TIMEFRAME, RSI_PERIOD, 0, 1);
      if (rsiValue > 0.5) return true;
      return false;
   }