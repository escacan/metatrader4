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
double DOLLAR_VOLATILITY = MarketInfo(Symbol(), MODE_TICKVALUE) / MarketInfo(Symbol(), MODE_TICKSIZE);
double MY_DIGIT = MarketInfo(Symbol(), MODE_DIGITS);

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
         int ticketArray[200] = {0};
         int ticketCount = 0;

         if (currentPrice >= TARGET_BUY) {
            // PrintFormat("Cur Ask : %f, target Buy : %f", Ask, TARGET_BUY);

            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_BUY) {
                           positionExist = true;
                        }
                        else if (OrderType() == OP_SELL) {
                           Print("Sell Order Exist");
                           ticketArray[ticketCount++] = OrderTicket();
                        } 
                     }
                  }
               }
            }

            if (ticketCount > 0) {
                for (int i = 0; i< ticketCount; i++) {
                    if (OrderSelect(ticketArray[i], SELECT_BY_TICKET, MODE_TRADES)) {
                        if(OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrRed)){
                            Print("Buy Momentum is found. Close Sell Order");
                        }
                        else {
                            PrintFormat("Close Order Failed :: ", GetLastError());
                        }
                    }
                }
            }
            
            if (!positionExist){
               sendOrders(OP_BUY, Ask, POSSIBLE_LOT_SIZE);
            }
         }
         else if (currentPrice <= TARGET_SELL) {
            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_SELL) {
                           positionExist = true;
                        }
                        else if (OrderType() == OP_BUY) {
                           ticketArray[ticketCount++] = OrderTicket();
                        }
                     }
                  }
               }
            }
            
            if (ticketCount > 0) {
                for (int i = 0; i< ticketCount; i++) {
                    if (OrderSelect(ticketArray[i], SELECT_BY_TICKET, MODE_TRADES)) {
                        if(OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrRed)){
                            Print("Sell Momentum is found. Close Buy Order");
                        }
                        else{
                            PrintFormat("Close Buy Order Failed : ", GetLastError());
                        }
                    }
                }
            }

            if (!positionExist) {
               sendOrders(OP_SELL, Bid, POSSIBLE_LOT_SIZE);
            }         
         } 
      }
  }

void sendOrders(int cmd, double price, double lotSize) {
      double stoplossPrice = YESTERDAY_ATR * ATR_STOPLOSS;
      string comment = "";
      int ticketNum;

      if (cmd == 0) {
          if (USE_RSI && !checkRSI()) lotSize = 0; 

          comment = "Send BUY order";
          stoplossPrice *= -1;
      }
      else if (cmd == 1) {
          if (USE_RSI && checkRSI()) lotSize = 0; 

          comment = "Send SELL order";
      }

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

         if (ticketNum) {
            if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                if(!OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + stoplossPrice, 0, 0, clrWhite)){
                    Alert("Fail OrderModify : Order ID = ", ticketNum);
                }
            }
         }
         else {
            Print("sendOrders::OrderSend Failed, ", GetLastError());         
         }
      }
   }

double getPossibleLotSize() {
      double tradableLotSize = 0;

      PrintFormat("Tick Value : %f, Tick Size : %f, Point Size : %f", MarketInfo(Symbol(), MODE_TICKVALUE), MarketInfo(Symbol(), MODE_TICKSIZE), MarketInfo(Symbol(), MODE_POINT));
      PrintFormat("Dollar Volatility : %f,  ATR : %f", DOLLAR_VOLATILITY, YESTERDAY_ATR);

      double ATR100forSL = YESTERDAY_ATR * DOLLAR_VOLATILITY;
      double expectedSL = ATR100forSL * ATR_STOPLOSS; // sl price for 1 lot
      PrintFormat("Expected SL Price per 1 Lot : %f", expectedSL);
      
      double maxRiskForAccount = AccountBalance() * RISK;
      PrintFormat("Account : %f,  Max Lisk per trade : %f", AccountBalance(), maxRiskForAccount);
      double maxLotBasedOnSL = maxRiskForAccount / expectedSL;
      double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
      double requiredMinBalance = tradableMinLotSize * expectedSL / RISK;

      if (maxLotBasedOnSL >= tradableMinLotSize) {
         tradableLotSize = maxLotBasedOnSL - MathMod(maxLotBasedOnSL, tradableMinLotSize);
      }
      else {
         PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
      }

      PrintFormat("You can buy %f Lots!", tradableLotSize);      
      return tradableLotSize;      
}

void bailoutOrders(int currentTime, int totalOrderCount, double openPrice) {
      bool CloseSuccess = false;
      int orderTime = 0;
      int ticketArray[300] = {0};
      int ticketCount = 0;

      if (totalOrderCount > 0) {
         Print("Bailout Exit Condition Check");
         for (int idx = 0; idx < totalOrderCount; idx++){
            if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
               if (OrderMagicNumber() == MAGICNO && OrderSymbol() == Symbol()){
                  if (OrderType() == OP_BUY) {
                     // 시가가 진입가보다 높은 경우
                     if (openPrice > OrderOpenPrice()) {
                        ticketArray[ticketCount++] = OrderTicket();
                     }
                  }
                  else if (OrderType() == OP_SELL) {
                     if (openPrice < OrderOpenPrice()) {
                        CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Ask, 3, White);
                        ticketArray[ticketCount++] = OrderTicket() * -1;
                     }                        
                  }
               }
            }
         }
      }

      for (int i= 0; i< ticketCount; i++){
         int curTicket = ticketArray[i];
         double price = 0;
         if (curTicket > 0) price = Bid;
         else {
             curTicket *= -1;
             price = Ask;
         }

         if (OrderSelect(curTicket, SELECT_BY_TICKET, MODE_TRADES)) {
            CloseSuccess = OrderClose(curTicket, OrderLots(), price, 3, White);
            if (CloseSuccess){
                Print("Bailout Order");
            }
            else {
                Print("Bailout Buy Order Failed, ", GetLastError());
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