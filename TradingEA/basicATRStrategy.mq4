//+------------------------------------------------------------------+
//|                                           Basic ATR Strategy.mq4 |
//|                        Copyright 2021, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2021, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

extern int MagicNo = 1; 
//--- input parameters
input double   ATRportion = 0.6;
input double   Risk = 0.15;

//--- Global Var
ENUM_TIMEFRAMES baseTimeFrame = PERIOD_D1;
int currentDate = 0;
int curPos = 0; // 0 : No Position.  1 : Buy.  2: Sell
double targetBuyPrice, targetSellPrice, possibleLotSize;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("Start Basic Trading");
      
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
      int total = OrdersTotal();
      datetime tempDate = TimeCurrent();
      MqlDateTime strDate;
      TimeToStruct(tempDate, strDate);
      
      int OpenRes = -1;
      bool CloseSuccess = false;
            
      // When New day Started
      if (strDate.day != currentDate) {
         currentDate = strDate.day;
         PrintFormat("New Day : %d", currentDate);
         double yesterdayAtr = iATR(Symbol(), baseTimeFrame, 1, 1);
         double targetRange = yesterdayAtr * ATRportion;
         double curOpen = iOpen(Symbol(), baseTimeFrame, 0);
         
         PrintFormat("Today: %d, OpenPrice: %f, yesterday ATR: %f", currentDate, curOpen, yesterdayAtr); 

         // Bailout Exit                          
         if (total > 0) {
            for (int idx = 0; idx < total; idx++){
               if (OrderSelect(idx, SELECT_BY_POS, MODE_TRADES)) {
                  if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                     if (OrderType() == OP_BUY) {
                        PrintFormat("Order Info :: Today's Open : %f, OrderOpenPrice : %f", curOpen, OrderOpenPrice());
                     
                        if (curOpen > OrderOpenPrice()) {
                           CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Bid, 3, White);
                           if (CloseSuccess){
                              Print("Bailout Buy Order");
                              curPos = 0;                     
                           }
                           else {
                              Print("Bailout Buy Failed, ", GetLastError());
                           }
                        }
                     }
                     else if (OrderType() == OP_SELL) {
                        PrintFormat("Order Info :: Today's Open : %f, OrderOpenPrice : %f", curOpen, OrderOpenPrice());
                        if (curOpen < OrderOpenPrice()) {
                           CloseSuccess = OrderClose(OrderTicket(), OrderLots(), Ask, 3, White);
                           if (CloseSuccess) {
                              Print("Bailout Sell Order");
                              curPos = 0;                           
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
         
         possibleLotSize = getPossibleLotSize(yesterdayAtr);
         targetBuyPrice = curOpen + targetRange;
         targetSellPrice = curOpen - targetRange;   
      }
      else {
         if (Close[0] >= targetBuyPrice) {
            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(0, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_BUY) {
                           if (curPos != 1) curPos = 1;
                           break;
                        }
                        else if (OrderType() == OP_SELL) {
                           if(OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)){
                              curPos= 0;
                              Print("Buy Momentum is found. Close Sell Order");
                              break;                           
                           }
                           else {
                              PrintFormat("Close Order Failed :: ", GetLastError());
                           }
                        } 
                     }
                  }
               }
            }
            
            if (curPos == 0){
               OpenRes = OrderSend(Symbol(), OP_BUY, possibleLotSize, Ask, 3, 0, 0, "Order Buy", MagicNo, 0, Green);            
               if(OpenRes){
                  curPos= 1;
                  Print("Buy Order");               
               }
               else{
                  Print("Buy Order Failed! : ,", GetLastError());
               }
            }
         }
         else if (Close[0] <= targetSellPrice) {
            if (total > 0) {
               for (int idx = 0; idx < total; idx++){
                  if (OrderSelect(0, SELECT_BY_POS, MODE_TRADES)) {
                     if (OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()){
                        if (OrderType() == OP_SELL) {
                           break;
                        }
                        else if (OrderType() == OP_BUY) {
                           if(OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)){
                              curPos= 0;
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
            
            if (curPos == 0) {
               OpenRes = OrderSend(Symbol(), OP_SELL, possibleLotSize, Bid, 3, 0, 0, "Order Sell", MagicNo, 0, Blue);
               if (OpenRes){
                  curPos = 2;
                  Print("Sell Order");               
               }
               else {
                  Print("Sell Order Failed! :: ,", GetLastError());
               }
            }         
         }    
           
         // Set Cur price on orders
         double yesterdayAtr = iATR(Symbol(), baseTimeFrame, 1, 1);
         
         for(int i= 0; i< OrdersTotal(); i++){
            if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
               if(OrderMagicNumber() == MagicNo && OrderSymbol() == Symbol()) {
                  if (OrderType() == OP_BUY){
                     if(OrderStopLoss()== 0){
                        if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() - yesterdayAtr * 0.5, 0, 0, White)){
                           Print("Stop Set on Buy Order");                        
                        }
                        else {
                           Print("Failed on set Stop on Buy Order");
                        }
                        break;
                     }
                  }
                  else if (OrderType() == OP_SELL) {
                     if (OrderStopLoss() == 0){
                        if(OrderModify(OrderTicket(), OrderOpenPrice(), OrderOpenPrice() + yesterdayAtr * 0.5, 0, 0, White)){
                           Print("Stop Set on Sell Order");                        
                        }
                        else {
                           Print("Failed on set Stop on Sell Order");
                        }
                        break;
                     }
                  }
               }
            }
         }
      }
  }

double getPossibleLotSize(double atrValue) {
   double totalAccountBalance = AccountBalance();
   double maxRiskPerTrade = totalAccountBalance * Risk;
   double possibleLot = maxRiskPerTrade / (100000 * 0.5 * atrValue);
   return possibleLot;
}