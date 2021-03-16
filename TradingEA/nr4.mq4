//+------------------------------------------------------------------+
//|                                                          NR4.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern int MagicNo = 2; 

input bool     USE_TIMEOUT_ORDER = false;
input int      TIMEOUT_BASE = 5;
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   ATRSLportion = 0.5;
input double   Risk = 0.15;
input double   BUY_TDW = 7;   // (0-Sunday, 1-Monday, ... ,6-Saturday)
input double   SELL_TDW = 7;   // (0-Sunday, 1-Monday, ... ,6-Saturday)

ENUM_TIMEFRAMES baseTimeFrame = PERIOD_D1;
double targetBuyPrice, targetSellPrice, possibleLotSize;
int currentDate = 0;

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
        datetime tempDate = TimeCurrent();
        int currentTime = TimeSeconds(tempDate);
        MqlDateTime strDate;
        TimeToStruct(tempDate, strDate);

        bool canBuy = true;
        bool canSell = true;
        if (BUY_TDW != 7) canBuy = strDate.day_of_week == BUY_TDW;
        if (SELL_TDW != 7) canSell = strDate.day_of_week == SELL_TDW;

        if (strDate.day != currentDate) {
            currentDate = strDate.day;

            bailoutOrders(currentTime);
            checkATR();
            possibleLotSize = 0;
            if (targetBuyPrice != -1 && targetSellPrice != -1) {
                possibleLotSize = getPossibleLotSize();
            }
        }

        int OpenRes = -1;
        int total = OrdersTotal(); 
        bool positionExist = false;
        bool newOrderExist = false;
      
        if (Ask >= targetBuyPrice) {
            PrintFormat("Cur Ask : %f, target Buy : %f", Ask, targetBuyPrice);

            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(0, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_BUY) {
                           Print("Buy Order Exist");
                           positionExist = true;
                           break;
                        }
                        else if (OrderType() == OP_SELL) {
                           Print("Sell Order Exist");
                           if(OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)){
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
            
            if (!positionExist && canBuy){
               Print("BUY Order Block");
               sendOrders(OP_BUY, Ask, possibleLotSize);
               newOrderExist = true;
            }
         }
         else if (Bid <= targetSellPrice) {
            PrintFormat("Cur Bid : %f, target Sell : %f", Bid, targetSellPrice);

            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(0, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_SELL) {
                           Print("Sell Order Exist");
                           positionExist = true;
                           break;
                        }
                        else if (OrderType() == OP_BUY) {
                           Print("Buy Order Exist");
                           if(OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)){
                              Print("Sell Momentum is found. Close Buy Order");
                              break;
                           }
                           else{
                              PrintFormat("Close Buy Order Failed : ", GetLastError());
                           }
                        }
                     }
                  }
               }
            }
            
            if (!positionExist && canSell) {
               Print("SELL Order Block");
               sendOrders(OP_SELL, Bid, possibleLotSize);
               newOrderExist = true;
            }         
         } 

         if (newOrderExist) {
            Print("StopLoss setting block");   
            
            total = OrdersTotal();
            // Set Cur price on orders
            double yesterdayAtr = iATR(Symbol(), baseTimeFrame, 1, 1);
            
            for(int i= 0; i< total; i++){
               if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
                  if(OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()) {
                     if (OrderType() == OP_BUY){
                        if(OrderStopLoss()== 0){
                           if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() - yesterdayAtr * ATRSLportion, 0, 0, White)){
                              Print("Stop Set on Buy Order");                        
                           }
                           else {
                              Print("Failed on set Stop on Buy Order");
                           }
                        }
                     }
                     else if (OrderType() == OP_SELL) {
                        if (OrderStopLoss() == 0){
                           if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + yesterdayAtr * ATRSLportion, 0, 0, White)){
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
//+------------------------------------------------------------------+
void bailoutOrders(int currentTime) {
        bool CloseSuccess = false;
        int orderTime = 0;
        int totalOrderCount = OrdersTotal();
        double openPrice = iOpen(Symbol(), baseTimeFrame, 0);

        if (totalOrderCount > 0) {
            Print("Bailout Exit Condition Check");
            for (int idx = 0; idx < totalOrderCount; idx++){
                if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                    if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                        orderTime = TimeSeconds(OrderOpenTime());

                        if (OrderType() == OP_BUY) {
                            PrintFormat("Order Info :: Today's Open : %f, OrderOpenPrice : %f", openPrice, OrderOpenPrice());

                            // 시가가 진입가보다 높은 경우
                            // 혹은 주문하고 기준일이 지나간 경우
                            if (openPrice > OrderOpenPrice() || timeoutOrder(currentTime, orderTime)) {
                                CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Bid, 3, White);
                                if (CloseSuccess){
                                Print("Bailout Buy Order");
                                totalOrderCount--;
                                }
                                else {
                                Print("Bailout Buy Failed, ", GetLastError());
                                }
                            }
                        }
                        else if (OrderType() == OP_SELL) {
                            PrintFormat("Order Info :: Today's Open : %f, OrderOpenPrice : %f", openPrice, OrderOpenPrice());
                            if (openPrice < OrderOpenPrice() || timeoutOrder(currentTime, orderTime)) {
                                CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Ask, 3, White);
                                if (CloseSuccess) {
                                Print("Bailout Sell Order");
                                totalOrderCount--;
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

void sendOrders(int cmd, double price, double lotSize) {
        int completedOrderCount= 0;
        string comment = "";

        if (cmd == 0) comment = "Send BUY order";
        else if (cmd == 1) comment = "Send SELL order";
        
        while (lotSize - MAX_LOT_SIZE_PER_ORDER > 0.0) {
            lotSize -= MAX_LOT_SIZE_PER_ORDER;
            if (OrderSend(Symbol(), cmd, MAX_LOT_SIZE_PER_ORDER, price, 3, 0, 0, comment, MagicNo, 0, Blue)) {
                completedOrderCount++;                   
            }
        }
    
        if (lotSize > 0) {
            if (OrderSend(Symbol(), cmd, lotSize, price, 3, 0, 0, comment, MagicNo, 0, Blue)) {
                completedOrderCount++;             
            }
        }

        PrintFormat("Total OrderSend Count : %d", completedOrderCount);
   }

double getPossibleLotSize() {
        double atrValue = iATR(Symbol(), baseTimeFrame, 1, 1);
        double tradableLotSize = 0;
        double ATR100forSL = atrValue / MarketInfo(Symbol(), MODE_TICKSIZE) * MarketInfo(Symbol(), MODE_TICKVALUE);
        double expectedSL = ATR100forSL * ATRSLportion; // sl price for 1 lot
        // PrintFormat("Expected SL Price per 1 Lot : %f", expectedSL);
        
        double maxRiskForAccount = AccountBalance() * Risk;
        // PrintFormat("Account : %f,  Max Lisk per trade : %f", AccountBalance(), maxRiskForAccount);
        double maxLotBasedOnSL = maxRiskForAccount / expectedSL;
        
        double tradableMinLotSize = MarketInfo(Symbol(), MODE_MINLOT);
        double requiredMinBalance = tradableMinLotSize * expectedSL / Risk;
        // PrintFormat("Required Minimum Account : %f", requiredMinBalance);
        
        // PrintFormat("Lot Size Per SL : %f", maxLotBasedOnSL);
        
        if (AccountBalance() < requiredMinBalance) {
            PrintFormat("Available Min Lot Size : %f", MarketInfo(Symbol(), MODE_MINLOT));
            PrintFormat("You need at least %f for risk management. Find other item.", requiredMinBalance);
            tradableLotSize = -1;
        }
        else {
            tradableLotSize = maxLotBasedOnSL - MathMod(maxLotBasedOnSL, tradableMinLotSize);
            PrintFormat("What you wanted : %f\nTradable Size : %f", maxLotBasedOnSL, tradableLotSize);
        }
        
        return tradableLotSize;      
}

void checkATR() {
        double day1, day2, day3, yesterday;
        yesterday = iATR(Symbol(), baseTimeFrame, 1, 1);
        day1 = iATR(Symbol(), baseTimeFrame, 1, 2);
        day2 = iATR(Symbol(), baseTimeFrame, 1, 3);
        day3 = iATR(Symbol(), baseTimeFrame, 1, 4);
        if (MathMin(MathMin(yesterday, day1), MathMin(day2, day3)) == yesterday) {
            targetBuyPrice = iHigh(Symbol(), baseTimeFrame, 1);
            targetSellPrice = iLow(Symbol(), baseTimeFrame, 1);
        } 
        else {
            targetBuyPrice = -1;
            targetSellPrice = -1;
        }
    }


bool timeoutOrder(int curTime, int orderOpenTime) {
      if (!USE_TIMEOUT_ORDER) return false;

      int elapsedTime = curTime - orderOpenTime;
      int elapsedDay = elapsedTime / 3600 / 24;
      if (elapsedDay >= TIMEOUT_BASE) return true;
      return false;
   }