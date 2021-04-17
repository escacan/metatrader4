//+------------------------------------------------------------------+
//|                                              Turtle Strategy.mq4 |
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

extern int MAGICNO = 3; 
//--- input parameters
input int      MARKET_GROUP = 0; // 0: Forex, 1: Metal, 2: Crypto, 3: Energy
input double   MAX_LOT_SIZE_PER_ORDER = 50.0;
input double   RISK = 0.01;
input double   NOTIONAL_BALANCE = 3000;
input int      BASE_TERM_FOR_BREAKOUT = 55;
input int      BASE_TERM_FOR_PROFIT = 10;
input int      MAXIMUM_UNIT_COUNT = 4;
input double   UNIT_STEP_UP_PORTION = 0.5; 
input double   STOPLOSS_PORTION = 0.5;
input ENUM_TIMEFRAMES BREAKOUT_TIMEFRAME = PERIOD_D1;
input bool     LOAD_BACKUP = true;

//--- Global Var
double TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE;
int CURRENT_UNIT_COUNT = 0;
int CURRENT_CMD = OP_BUY; // 0 : Buy  1 : Sell
double N_VALUE = 0; 
double DOLLAR_PER_POINT = 0;
int currentDate = 0;
bool backupFinished = false;

int TICKET_ARR[6][200] = {0};
double OPENPRICE_ARR[6] = {0};
bool firstTick = true;
string SYMBOL = "";
int lastCheckedTime=0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   // Print("Start Turtle Trading");
   SYMBOL = Symbol();

   if (LOAD_BACKUP) readBackUpFile();

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
   datetime currentTime = TimeCurrent();
   int currentCheckTime = TimeMinute(currentTime);

   if (lastCheckedTime == currentCheckTime) {
      return;
   } 
   else {
      lastCheckedTime = currentCheckTime;
   } 

   Comment(StringFormat("Dollar per point : %f\nN Value : %f\nCurrent Unit Count : %d\nShow prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n", DOLLAR_PER_POINT, N_VALUE, CURRENT_UNIT_COUNT,Ask,Bid,TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));

   MqlDateTime strDate;
   TimeToStruct(currentTime, strDate);

   // Daily Update
   if (strDate.day != currentDate || isZero(DOLLAR_PER_POINT) || isZero(N_VALUE)) {
      currentDate = strDate.day;
      
      // TODO : When failed to update Dollar per point, how to handle the issue?
      // Especially on Forex items.
      // When N_VALUE is zero, order is sent immediately. Should be fixed!!
      DOLLAR_PER_POINT = MarketInfo(SYMBOL, MODE_TICKVALUE) / MarketInfo(SYMBOL, MODE_TICKSIZE);

      if (CURRENT_UNIT_COUNT == 0 || isZero(N_VALUE)) {
         N_VALUE = iATR(SYMBOL, BREAKOUT_TIMEFRAME, 20, 1);
      }

      updateTargetPrice();
   }

   if (isZero(DOLLAR_PER_POINT) || isZero(N_VALUE)) {
      PrintFormat("Not initialized well. Dollar point : %f, N_VALUE : %f", DOLLAR_PER_POINT, N_VALUE);
      return;
   }

   double tradableSize = getUnitSize();

   if (tradableSize == 0) return;

   Comment(StringFormat("Dollar per point : %f\nN Value : %f\nCurrent Unit Count : %d\nShow prices\nAsk = %G\nBid = %G\nTargetBuy = %f\nTargetSell = %f\nTARGET_STOPLOSS_PRICE = %f\n", DOLLAR_PER_POINT, N_VALUE, CURRENT_UNIT_COUNT,Ask,Bid,TARGET_BUY_PRICE, TARGET_SELL_PRICE, TARGET_STOPLOSS_PRICE));

   if (firstTick || backupFinished) { 
      updateTargetPrice();

      if (isZero(TARGET_BUY_PRICE) || isZero(TARGET_SELL_PRICE)) return;
      else {
         backupFinished = false;
         firstTick = false;
      }
   }
   canSendOrder();
   setGlobalVar();
  }

// Function which update Target Price based on latest order's CMD and OpenPrice.
void updateTargetPrice() {
   double diffPrice = N_VALUE * UNIT_STEP_UP_PORTION;
   double diffStopLoss = N_VALUE * STOPLOSS_PORTION;
   if (CURRENT_CMD == OP_BUY) diffStopLoss *= -1;

   double latestOrderOpenPrice = 0;
   double targetStopLoss = 0;

   if (CURRENT_UNIT_COUNT > 0) {
      if (backupFinished) {
         int highBarIndex = iHighest(SYMBOL, BREAKOUT_TIMEFRAME, MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
         if (highBarIndex == -1) TARGET_BUY_PRICE = 99999999999999;
         else TARGET_BUY_PRICE = iHigh(SYMBOL, BREAKOUT_TIMEFRAME, highBarIndex);

         int lowBarIndex = iLowest(SYMBOL, BREAKOUT_TIMEFRAME, MODE_LOW, BASE_TERM_FOR_BREAKOUT, 1);
         if (lowBarIndex == -1) TARGET_SELL_PRICE = -9999999999;
         else TARGET_SELL_PRICE = iLow(SYMBOL, BREAKOUT_TIMEFRAME, lowBarIndex);

         if (isZero(TARGET_BUY_PRICE) || isZero(TARGET_SELL_PRICE)) {
            Print("updateTargetPrice :: Failed to get default target price for backup");
            return;
         }
      }

      latestOrderOpenPrice = OPENPRICE_ARR[CURRENT_UNIT_COUNT - 1];
      if (isZero(latestOrderOpenPrice)) {
         CURRENT_UNIT_COUNT--;
         PrintFormat("updateTargetPrice:: OPENPRICE_ARR[%d] is zero",  CURRENT_UNIT_COUNT);
         if (CURRENT_CMD == OP_BUY) {
            TARGET_BUY_PRICE = 0;
         }
         else if (CURRENT_CMD == OP_SELL) {
            TARGET_SELL_PRICE = 0;
         }
      }
      else {
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
   }
   else {
      int highBarIndex = iHighest(SYMBOL, BREAKOUT_TIMEFRAME, MODE_HIGH, BASE_TERM_FOR_BREAKOUT, 1);
      if (highBarIndex == -1) TARGET_BUY_PRICE = 99999999999999;
      else TARGET_BUY_PRICE = iHigh(SYMBOL, BREAKOUT_TIMEFRAME, highBarIndex);

      int lowBarIndex = iLowest(SYMBOL, BREAKOUT_TIMEFRAME, MODE_LOW, BASE_TERM_FOR_BREAKOUT, 1);
      if (lowBarIndex == -1) TARGET_SELL_PRICE = -9999999999;
      else TARGET_SELL_PRICE = iLow(SYMBOL, BREAKOUT_TIMEFRAME, lowBarIndex);
   }

   if (isZero(TARGET_BUY_PRICE) || isZero(TARGET_SELL_PRICE)) {
      Print("updateTargetPrice :: Failed to get target Price");
   }
   else {
      PrintFormat("UpdateTargetPrice:: Target Buy : %f, Target Sell : %f", TARGET_BUY_PRICE, TARGET_SELL_PRICE);
      backupOrderInfo();
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

   double lotSize = getUnitSize();

   if (isZero(lotSize)) return;

   while (lotSize > 0) {
      if (lotSize >= MAX_LOT_SIZE_PER_ORDER) {
         lotSize -= MAX_LOT_SIZE_PER_ORDER;
         // PrintFormat("Order Lot Size : %f", MAX_LOT_SIZE_PER_ORDER);
         ticketNum = OrderSend(SYMBOL, cmd, MAX_LOT_SIZE_PER_ORDER, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue);
      }
      else {
         // PrintFormat("Order Lot Size : %f", lotSize);
         ticketNum = OrderSend(SYMBOL, cmd, lotSize, price, 3, 0, 0, comment, MAGICNO, 0, clrBlue);
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
               PrintFormat("Fail OrderSelect : Order ID = ", ticketNum);
            }
         }
      }
      else {
         if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
            OPENPRICE_ARR[CURRENT_UNIT_COUNT] = OrderOpenPrice();
         }
         else {
            PrintFormat("Fail OrderSelect : Order ID = ", ticketNum);
         }
      }

      CURRENT_UNIT_COUNT++;

      updateTargetPrice();
   }
}

void closeAllOrders () {
   bool closedOrderExist = false;
   double currentPrice = Close[0];

   // Check STOP LOSS
   if (CURRENT_UNIT_COUNT > 0) {
      if (isZero(currentPrice)) {
         Print("closeAllOrders :: Fail iOpen Current Price");
         return;
      }

      double profitBuyPrice = 0;
      double profitSellPrice = 0;

      int highBarIndex = iHighest(SYMBOL, BREAKOUT_TIMEFRAME,MODE_HIGH, BASE_TERM_FOR_PROFIT, 1);
      if (highBarIndex == -1) profitSellPrice = 99999999999999;
      else profitSellPrice = iHigh(SYMBOL, BREAKOUT_TIMEFRAME, highBarIndex);

      if (isZero(profitSellPrice)) {
         Print("closeAllOrders :: iHigh failed");
         return;
      }


      int lowBarIndex = iLowest(SYMBOL, BREAKOUT_TIMEFRAME,MODE_LOW, BASE_TERM_FOR_PROFIT, 1);
      if (lowBarIndex == -1) profitBuyPrice = -9999999999;
      else profitBuyPrice = iLow(SYMBOL, BREAKOUT_TIMEFRAME, lowBarIndex);

      if (isZero(profitBuyPrice)) {
         Print("closeAllOrders :: iLos failed");
         return;
      }

      if (CURRENT_CMD == OP_BUY) {
         if (isSmaller(currentPrice,TARGET_STOPLOSS_PRICE)) {
            CURRENT_UNIT_COUNT--;
            if (CURRENT_UNIT_COUNT == 0) N_VALUE = 0;

            int totalTicketCount = TICKET_ARR[CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               PrintFormat("215::Close order of UNIT %d", CURRENT_UNIT_COUNT);

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                     PrintFormat("Fail OrderClose : Order ID = ", ticketNum);
                  }
                  else {
                     closedOrderExist = true;
                  }
               }
            }
         }
         
         if (isSmaller(currentPrice, profitBuyPrice)) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  PrintFormat("234::Close order of UNIT %d", CURRENT_UNIT_COUNT);

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) {
                        PrintFormat("Fail OrderClose : Order ID = ", ticketNum);
                     }
                     else {
                        closedOrderExist = true;
                     }
                  }
               }

               TICKET_ARR[unitIdx][0] = 0;
            }

            CURRENT_UNIT_COUNT = 0;
            N_VALUE = 0;
         }
      }
      else if (CURRENT_CMD == OP_SELL) {
         if (isBigger(currentPrice, TARGET_STOPLOSS_PRICE) ) {
            CURRENT_UNIT_COUNT--;
            if (CURRENT_UNIT_COUNT == 0) N_VALUE = 0;

            int totalTicketCount = TICKET_ARR[CURRENT_UNIT_COUNT][0];

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[CURRENT_UNIT_COUNT][ticketIdx];

               if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                  if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                     PrintFormat("Fail OrderClose : Order ID = ", ticketNum);
                  }
                  else {
                     closedOrderExist = true;
                  }
               }
            }
         }
         
         if (isBigger(currentPrice, profitSellPrice)) {
            for (int unitIdx = 0; unitIdx < CURRENT_UNIT_COUNT; unitIdx++) {
               int totalTicketCount = TICKET_ARR[unitIdx][0];

               for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
                  int ticketNum = TICKET_ARR[unitIdx][ticketIdx];

                  if (OrderSelect(ticketNum, SELECT_BY_TICKET, MODE_TRADES)) {
                     if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) {
                        PrintFormat("Fail OrderClose : Order ID = ", ticketNum);
                     }
                     else {
                        closedOrderExist = true;
                     }
                  }
               }

               TICKET_ARR[unitIdx][0] = 0;
            }

            CURRENT_UNIT_COUNT = 0;
            N_VALUE = 0;
         }
      }
   }

   if (closedOrderExist) updateTargetPrice();
}

// Function of Check whether current price break the highest/lowest price
void canSendOrder () {
   closeAllOrders();

   if (CURRENT_UNIT_COUNT >= MAXIMUM_UNIT_COUNT) return;

   // TODO : Need to check total UNIT count.
   // Strong Related : 6
   // Loosely related : 10
   // Single Direction : 12 per dir

   double currentPrice = Close[0];

   if (isZero(currentPrice)) {
      Print("canSendOrder :: Fail iOpen Current Price");
      return;
   }

   if (CURRENT_UNIT_COUNT > 0) {
      if(isBigger(currentPrice, TARGET_BUY_PRICE) && CURRENT_CMD == OP_BUY) {
         if (!checkTotalMarketsUnitCount(CURRENT_CMD)) return;

         PrintFormat("Send Buy Order On Cur Price : %f, Target Buy Price : %f", currentPrice, TARGET_BUY_PRICE);
         sendOrders(OP_BUY, Ask);
      }
      else if (isSmaller(currentPrice, TARGET_SELL_PRICE) && CURRENT_CMD == OP_SELL) {
         if (!checkTotalMarketsUnitCount(CURRENT_CMD)) return;

         PrintFormat("Send Sell Order On Cur Price : %f, Target Sell Price : %f", currentPrice, TARGET_SELL_PRICE);
         sendOrders(OP_SELL, Bid);
      }
   }
   else {
      if(isBigger(currentPrice, TARGET_BUY_PRICE)) {
         if (!checkTotalMarketsUnitCount(OP_BUY)) return;

         PrintFormat("Send Buy Order On Cur Price : %f, Target Buy Price : %f", currentPrice, TARGET_BUY_PRICE);
         sendOrders(OP_BUY, Ask);
      }
      else if (isSmaller(currentPrice, TARGET_SELL_PRICE)) {
         if (!checkTotalMarketsUnitCount(OP_SELL)) return;

         PrintFormat("Send Sell Order On Cur Price : %f, Target Sell Price : %f", currentPrice, TARGET_SELL_PRICE);
         sendOrders(OP_SELL, Bid);
      }
   }
}

// Function of check Unit Size for 1% Risk
// TODO : Need to remove commented sources
double getUnitSize() {
      // if Current unit count is maximum, we should not order any more.
      if (CURRENT_UNIT_COUNT == MAXIMUM_UNIT_COUNT) return 0;

      double tradableLotSize = 0;
      double dollarVolatility = N_VALUE * DOLLAR_PER_POINT * STOPLOSS_PORTION;
      
      double maxRiskForAccount = NOTIONAL_BALANCE * RISK;

      double maxLotBasedOnDollarVolatility = maxRiskForAccount / dollarVolatility;
      
      double tradableMinLotSize = MarketInfo(SYMBOL, MODE_MINLOT);
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

// Function of setting GlobalVar for Current Item's UNIT Count.
void setGlobalVar() {
   string globalVarName = "GROUP" + IntegerToString(MARKET_GROUP) + "_" + SYMBOL;

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
   int marketUnitCount[10][2] = {0}; // marketUnitCount[MARKET_GROUP][0: Buy, 1: Sell]
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

// Function of write Backup file.
void backupOrderInfo() {
   string backupFile =SYMBOL + ".txt";

   int filehandle=FileOpen(backupFile,FILE_WRITE|FILE_TXT);
   if(filehandle!=INVALID_HANDLE) {
      // PrintFormat("File Write : %s", backupFile);

      FileWrite(filehandle,CURRENT_CMD);
      FileWrite(filehandle,CURRENT_UNIT_COUNT);

      if (CURRENT_UNIT_COUNT > 0) {
         for (int unitIdx= 0; unitIdx< CURRENT_UNIT_COUNT; unitIdx++) {
            int totalTicketCount = TICKET_ARR[unitIdx][0];
            FileWrite(filehandle,totalTicketCount);
            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               int ticketNum = TICKET_ARR[unitIdx][ticketIdx];
               FileWrite(filehandle,ticketNum);
            }
         }
      }

      FileClose(filehandle);
     }
   else Print("Operation FileOpen failed, error ",GetLastError());
}

void readBackUpFile() {
   string backupFile = SYMBOL + ".txt";
   int    str_size = 0;
   string str = "";
   int totalTicketCount = 0;
   int ticketNum = 0;

   PrintFormat("Read File :: %s", backupFile);
   
   int filehandle = FileOpen(backupFile,FILE_READ|FILE_TXT);
   if(filehandle != INVALID_HANDLE)
   {
      PrintFormat("Read File :: %s", backupFile);

      str_size=FileReadInteger(filehandle,INT_VALUE);
      str=FileReadString(filehandle,str_size);
      CURRENT_CMD = StrToInteger(str);

      str_size=FileReadInteger(filehandle,INT_VALUE);
      str=FileReadString(filehandle,str_size);
      CURRENT_UNIT_COUNT = StrToInteger(str);

      PrintFormat("readBackUpFile :: CURRENCT_CMD : %d,  CURRENT_UNIT_COUNT : %d", CURRENT_CMD, CURRENT_UNIT_COUNT);

      if (CURRENT_UNIT_COUNT > 0) {
         for (int unitIdx= 0; unitIdx< CURRENT_UNIT_COUNT; unitIdx++) {
            str_size=FileReadInteger(filehandle,INT_VALUE);
            str=FileReadString(filehandle,str_size);
            totalTicketCount = StrToInteger(str);
            TICKET_ARR[unitIdx][0] = totalTicketCount;
            PrintFormat("Total Ticket Count :: TICKET_ARR[%d][0]: %d", unitIdx, TICKET_ARR[unitIdx][0]);

            for (int ticketIdx = 1; ticketIdx <= totalTicketCount; ticketIdx++) {
               str_size=FileReadInteger(filehandle,INT_VALUE);
               str=FileReadString(filehandle,str_size);
               TICKET_ARR[unitIdx][ticketIdx] = StrToInteger(str);
               PrintFormat("TICKET_ARR[%d][%d] : %d", unitIdx, ticketIdx, TICKET_ARR[unitIdx][ticketIdx]);
            }
         }

         int unitIdx = CURRENT_UNIT_COUNT - 1 ;
         while(unitIdx >= 0) {
            totalTicketCount = TICKET_ARR[unitIdx][0];
            for (int ticketIdx = totalTicketCount; ticketIdx >= 1; ticketIdx--) {
               PrintFormat("Check TICKET_ARR[%d][%d]", unitIdx, ticketIdx);
               if (OrderSelect(TICKET_ARR[unitIdx][ticketIdx], SELECT_BY_TICKET, MODE_TRADES)) {
                  PrintFormat("Select Order %d", TICKET_ARR[unitIdx][ticketIdx]);
                  if (OrderCloseTime() != 0) {
                     TICKET_ARR[unitIdx][0]--;
                     TICKET_ARR[unitIdx][ticketIdx] = 0;
                  }
                  else {
                     if (isZero(OPENPRICE_ARR[unitIdx])) OPENPRICE_ARR[unitIdx] = OrderOpenPrice();
                  }
               }
               else {
                  PrintFormat("Failed to select Order %d", TICKET_ARR[unitIdx][ticketIdx]);
               }
            }

            if (isZero(OPENPRICE_ARR[unitIdx])) {
               PrintFormat("OPENPRICE_ARR[%d] is zero",  unitIdx);
               CURRENT_UNIT_COUNT--;
            }

            unitIdx--;
         }
      }

      FileClose(filehandle);

      setGlobalVar();
      backupFinished = true;
   }
   else
   {
      PrintFormat("File "+backupFile+" not found, the last error is ", GetLastError());
   }  
}  