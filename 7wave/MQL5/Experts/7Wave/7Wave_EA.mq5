//+------------------------------------------------------------------+
//|                                                     7Wave_EA.mq5 |
//|  7Wave, step 2: the EA trades exactly what the 7Wave indicator   |
//|  draws for the swing breakout (7wave/RULES.md, rules 5-6, and    |
//|  "Step 2"), nothing else. Fixed lot, one trade at a time, no     |
//|  risk engine yet.                                                |
//|                                                                  |
//|  Entry: at the open of every H1 bar, a stop order at the level   |
//|    the indicator armed for that bar, valid for that bar only. If |
//|    the bar opened beyond the level, a market order instead.      |
//|  Management (the research's "growth" profile):                   |
//|    stop 1.5 ATR from the fill (1R), target +3R; once the best    |
//|    price reaches +1R the stop trails 2 ATR behind it on          |
//|    completed M1 bars; exit at market after 24 hours.             |
//|  v1.01: a stop order the broker rejects is not given up: the     |
//|    entry stays wanted for its bar, is retried on the next ticks, |
//|    and turns into a market order once price reaches the level.   |
//+------------------------------------------------------------------+
#property copyright   "7Wave"
#property version     "1.01"
#property description "7Wave step 2: trades the 7Wave indicator's swing breakout (rules 5-6) with the research's growth exits."
#property description "Fixed lot, one trade at a time. Attach to an XAUUSD H1 chart; needs Indicators\\7Wave\\7Wave.ex5."
#property tester_indicator "7Wave\\7Wave.ex5"

#include <Trade\Trade.mqh>

input double InpLots  = 0.01;     // Fixed lot (the risk engine is step 3)
input long   InpMagic = 770001;   // Magic number of this EA's orders

#define IND_PATH      "7Wave\\7Wave"
#define BUF_BUY_STOP  19          // indicator buffer: buy-stop level armed for the bar
#define BUF_SELL_STOP 21          // indicator buffer: sell-stop level armed for the bar
#define BUF_ATR       27          // indicator buffer: Wilder ATR(14) of each closed H1 bar
#define STOP_ATR      1.5         // initial stop distance in ATR = 1R
#define TARGET_R      3.0         // target in R
#define TRAIL_FROM_R  1.0         // the trail starts once the best price is this many R in profit
#define TRAIL_ATR     2.0         // trail distance behind the best price, in ATR
#define MAX_HOLD_SEC  86400       // time exit after 24 hours
#define MAX_RETRIES   30          // attempts per bar for an entry the broker rejected
#define LOG_TESTER    "7wave_ea_trades_tester.csv"
#define LOG_LIVE      "7wave_ea_trades_live.csv"

CTrade   g_trade;
int      g_ind = INVALID_HANDLE;
datetime g_barDone = 0;           // the H1 bar whose entry decision is done

//--- the order armed for the current bar
datetime g_orderBar = 0;
double   g_orderLevel = 0.0, g_orderAtr = 0.0;
int      g_orderDir = 0;
bool     g_wantEntry = false;     // this bar's entry is still wanted: the broker rejected it, retry
int      g_retries = 0;

//--- the open trade (one at a time); g_pos = 0 when flat
ulong    g_pos = 0;
int      g_dir = 0;
double   g_fill = 0.0, g_atr = 0.0, g_risk = 0.0, g_trail = 0.0, g_best = 0.0, g_initSl = 0.0, g_tp = 0.0;
double   g_level = 0.0;
datetime g_fillTime = 0, g_signalBar = 0, g_m1Done = 0;
bool     g_needLevels = false;    // move the stop and target to the fill on the next tick
bool     g_trailed = false;       // the stop has been trailed at least once
bool     g_timeExit = false;      // the EA closed the trade on time
string   g_logName = "";          // trade log file in Common\Files

//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Period != PERIOD_H1)
     {
      Print("7Wave EA: attach it to an H1 chart; the setup is defined on H1.");
      return(INIT_FAILED);
     }
   g_ind = iCustom(_Symbol, PERIOD_H1, IND_PATH);
   if(g_ind == INVALID_HANDLE)
     {
      PrintFormat("7Wave EA: cannot load the indicator %s (error %d).", IND_PATH, GetLastError());
      return(INIT_FAILED);
     }
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints(50);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   if(MQLInfoInteger(MQL_TESTER))
      StartLog(LOG_TESTER, true);
   else
      StartLog(LOG_LIVE, false);
   g_barDone = iTime(_Symbol, PERIOD_H1, 0);   // act only at fresh bar opens, never mid-bar
   AdoptOpenTrade();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_ind != INVALID_HANDLE)
      IndicatorRelease(g_ind);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_needLevels)
      SetFillLevels();
   ManageTrade();
   datetime bar = iTime(_Symbol, PERIOD_H1, 0);
   if(bar != 0 && bar != g_barDone && DecideBar(bar))
      g_barDone = bar;
   else
      if(g_wantEntry && g_orderBar == bar && g_pos == 0 && !OurPositionOpen() && !OurOrderOpen())
        {
         if(g_retries < MAX_RETRIES)
           {
            g_retries++;
            PlaceEntry(g_orderDir, g_orderLevel, g_orderAtr, g_orderBar);   // market order once price is at the level
           }
         else
            g_wantEntry = false;
        }
  }

//+------------------------------------------------------------------+
//| Fills and exits of this EA's trades.                             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN && HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == InpMagic)
      OnFill(trans.deal);
   else
      if((entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) && g_pos != 0 &&
         (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID) == g_pos)
         OnExit(trans.deal);
  }

//+------------------------------------------------------------------+
//| At a new H1 bar: drop last bar's order and arm this bar's.       |
//| Returns false when the indicator has not caught up yet.          |
//+------------------------------------------------------------------+
bool DecideBar(const datetime bar)
  {
   DeleteOurOrders();                        // a stop order lives for one bar only
   g_wantEntry = false;
   g_retries   = 0;
   if(BarsCalculated(g_ind) < Bars(_Symbol, PERIOD_H1))
      return(false);
   double buy[], sell[], atr[];
   if(CopyBuffer(g_ind, BUF_BUY_STOP, 0, 1, buy) != 1 || CopyBuffer(g_ind, BUF_SELL_STOP, 0, 1, sell) != 1 ||
      CopyBuffer(g_ind, BUF_ATR, 1, 1, atr) != 1)
      return(false);
   if(g_pos != 0 || OurPositionOpen())
      return(true);                          // one trade at a time
   if(atr[0] == EMPTY_VALUE || atr[0] <= 0.0)
      return(true);
   if(buy[0] != EMPTY_VALUE && buy[0] > 0.0)
      PlaceEntry(1, buy[0], atr[0], bar);
   else
      if(sell[0] != EMPTY_VALUE && sell[0] > 0.0)
         PlaceEntry(-1, sell[0], atr[0], bar);
   return(true);
  }

//+------------------------------------------------------------------+
//| A stop order at the armed level (market order if price is past).  |
//+------------------------------------------------------------------+
void PlaceEntry(const int dir, const double rawLevel, const double atr, const datetime bar)
  {
   double level = Px(rawLevel);
   double risk  = STOP_ATR * atr;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string note  = StringFormat("7W %s %.3f", dir > 0 ? "L" : "S", atr);   // the ATR travels with the trade
   ENUM_ORDER_TYPE_TIME life = ORDER_TIME_GTC;
   datetime expiry = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0)
     {
      life   = ORDER_TIME_SPECIFIED;
      expiry = bar + PeriodSeconds(PERIOD_H1) - 1;
     }
   g_orderBar   = bar;
   g_orderLevel = level;
   g_orderAtr   = atr;
   g_orderDir   = dir;
   bool   ok;
   string what;
   if(dir > 0)
     {
      if(ask >= level)
        {
         what = "market buy (the bar opened above the level)";
         ok = g_trade.Buy(InpLots, _Symbol, 0.0, Px(ask - risk), Px(ask + TARGET_R * risk), note);
        }
      else
        {
         what = "buy stop";
         ok = g_trade.BuyStop(InpLots, level, _Symbol, Px(level - risk), Px(level + TARGET_R * risk), life, expiry, note);
        }
     }
   else
     {
      if(bid <= level)
        {
         what = "market sell (the bar opened below the level)";
         ok = g_trade.Sell(InpLots, _Symbol, 0.0, Px(bid + risk), Px(bid - TARGET_R * risk), note);
        }
      else
        {
         what = "sell stop";
         ok = g_trade.SellStop(InpLots, level, _Symbol, Px(level + risk), Px(level - TARGET_R * risk), life, expiry, note);
        }
     }
   uint rc = g_trade.ResultRetcode();
   ok = ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED || rc == TRADE_RETCODE_DONE_PARTIAL);
   g_wantEntry = !ok;                        // rejected: keep it wanted for this bar and retry on the next tick
   PrintFormat("7Wave EA: %s at %s for the %s bar, ATR %.2f, stop %.2f away: %s (retcode %d)", what,
               DoubleToString(level, _Digits), TimeToString(bar), atr, risk,
               ok ? "placed" : "REJECTED, retrying on the next tick", rc);
  }

//+------------------------------------------------------------------+
void OnFill(const ulong deal)
  {
   g_pos       = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   g_dir       = (HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY) ? 1 : -1;
   g_fill      = HistoryDealGetDouble(deal, DEAL_PRICE);
   g_fillTime  = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   g_atr       = g_orderAtr;
   g_level     = g_orderLevel;
   g_signalBar = g_orderBar;
   StartTrade();
   g_needLevels = true;
   PrintFormat("7Wave EA: %s filled at %s (level %s); stop %s, target %s", g_dir > 0 ? "BUY" : "SELL",
               DoubleToString(g_fill, _Digits), DoubleToString(g_level, _Digits), DoubleToString(g_initSl, _Digits),
               DoubleToString(g_tp, _Digits));
  }

//+------------------------------------------------------------------+
//| R distance, trail, stop and target of the trade from its fill.   |
//+------------------------------------------------------------------+
void StartTrade()
  {
   g_risk     = STOP_ATR * g_atr;
   g_trail    = TRAIL_ATR * g_atr;
   g_best     = g_fill;
   g_trailed  = false;
   g_timeExit = false;
   g_initSl   = Px(g_fill - g_dir * g_risk);
   g_tp       = Px(g_fill + g_dir * TARGET_R * g_risk);
   g_m1Done   = (datetime)(g_fillTime / 60 * 60);   // the fill minute itself never counts for the trail
  }

//+------------------------------------------------------------------+
//| Move the stop and target from the order level to the fill.       |
//+------------------------------------------------------------------+
void SetFillLevels()
  {
   if(g_pos == 0 || !PositionSelectByTicket(g_pos))
     {
      g_needLevels = false;
      return;
     }
   double tick = TickSize();
   if(MathAbs(PositionGetDouble(POSITION_SL) - g_initSl) < tick / 2 &&
      MathAbs(PositionGetDouble(POSITION_TP) - g_tp) < tick / 2)
     {
      g_needLevels = false;
      return;
     }
   if(g_trade.PositionModify(g_pos, g_initSl, g_tp))
      g_needLevels = false;
   else
      PrintFormat("7Wave EA: could not move the stop/target to the fill yet (retcode %d), retrying",
                  g_trade.ResultRetcode());
  }

//+------------------------------------------------------------------+
//| Time exit, and the trail on every completed M1 bar.              |
//+------------------------------------------------------------------+
void ManageTrade()
  {
   if(g_pos == 0 || g_needLevels || !PositionSelectByTicket(g_pos))
      return;
   if(TimeCurrent() - g_fillTime >= MAX_HOLD_SEC)
     {
      g_timeExit = true;
      if(!g_trade.PositionClose(g_pos))
        {
         g_timeExit = false;
         PrintFormat("7Wave EA: time exit failed (retcode %d), retrying", g_trade.ResultRetcode());
        }
      return;
     }
   datetime lastDone = iTime(_Symbol, PERIOD_M1, 1);     // the last completed M1 bar
   if(lastDone <= g_m1Done)
      return;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_M1, g_m1Done + 60, lastDone, r);
   if(n <= 0)
      return;
   double sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   double newSl = sl;
   for(int k = 0; k < n; k++)
     {
      if(r[k].time <= g_m1Done)
         continue;
      double spr   = r[k].spread * _Point;
      double favor = (g_dir > 0) ? r[k].high : r[k].low + spr;
      double cls   = (g_dir > 0) ? r[k].close : r[k].close + spr;
      if(g_dir * (favor - g_best) > 0)
         g_best = favor;
      if(g_dir * (g_best - g_fill) >= TRAIL_FROM_R * g_risk)
        {
         double lvl = g_best - g_dir * g_trail;
         if(g_dir * (lvl - newSl) > 0 && g_dir * (cls - lvl) > 0)
            newSl = lvl;
        }
      g_m1Done = r[k].time;
     }
   newSl = Px(newSl);
   if(g_dir * (newSl - sl) >= TickSize() / 2)
     {
      if(g_trade.PositionModify(g_pos, newSl, tp))
        {
         g_trailed = true;
         PrintFormat("7Wave EA: trail moved the stop to %s (best %s)", DoubleToString(newSl, _Digits),
                     DoubleToString(g_best, _Digits));
        }
     }
  }

//+------------------------------------------------------------------+
void OnExit(const ulong deal)
  {
   double   px  = HistoryDealGetDouble(deal, DEAL_PRICE);
   datetime t   = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   long     why = HistoryDealGetInteger(deal, DEAL_REASON);
   string reason = (why == DEAL_REASON_TP) ? "target" :
                   (why == DEAL_REASON_SL) ? (g_trailed ? "trail" : "stop") :
                   (g_timeExit ? "time" : "other");
   double usd = 0.0;
   if(HistorySelectByPosition(g_pos))
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong d = HistoryDealGetTicket(i);
         usd += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) +
                HistoryDealGetDouble(d, DEAL_SWAP);
        }
   double r = (g_risk > 0) ? (px - g_fill) * g_dir / g_risk : 0.0;
   double bestR = (g_risk > 0) ? (g_best - g_fill) * g_dir / g_risk : 0.0;
   PrintFormat("7Wave EA: %s closed at %s by %s: %+.2fR, %+.2f USD", g_dir > 0 ? "BUY" : "SELL",
               DoubleToString(px, _Digits), reason, r, usd);
   LogTrade(t, px, reason, r, usd, bestR);
   g_pos = 0;
   g_dir = 0;
   g_needLevels = false;
  }

//+------------------------------------------------------------------+
//| After a restart: pick up an open trade of this EA.               |
//+------------------------------------------------------------------+
void AdoptOpenTrade()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      g_pos      = ticket;
      g_dir      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      g_fill     = PositionGetDouble(POSITION_PRICE_OPEN);
      g_fillTime = (datetime)PositionGetInteger(POSITION_TIME);
      string parts[];
      g_atr = 0.0;
      if(StringSplit(PositionGetString(POSITION_COMMENT), ' ', parts) >= 3)
         g_atr = StringToDouble(parts[2]);
      if(g_atr <= 0.0)
         g_atr = MathAbs(g_fill - PositionGetDouble(POSITION_SL)) / STOP_ATR;
      StartTrade();
      g_trailed = g_dir * (PositionGetDouble(POSITION_SL) - g_initSl) > TickSize() / 2;
      //--- best price since the fill, from the completed M1 bars
      MqlRates r[];
      datetime lastDone = iTime(_Symbol, PERIOD_M1, 1);
      int n = CopyRates(_Symbol, PERIOD_M1, g_m1Done + 60, lastDone, r);
      for(int k = 0; k < n; k++)
        {
         double favor = (g_dir > 0) ? r[k].high : r[k].low + r[k].spread * _Point;
         if(g_dir * (favor - g_best) > 0)
            g_best = favor;
         g_m1Done = r[k].time;
        }
      PrintFormat("7Wave EA: picked up the open %s from %s at %s (ATR %.2f)", g_dir > 0 ? "BUY" : "SELL",
                  TimeToString(g_fillTime), DoubleToString(g_fill, _Digits), g_atr);
      break;
     }
   DeleteOurOrders();
  }

//+------------------------------------------------------------------+
bool OurPositionOpen()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool OurOrderOpen()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void DeleteOurOrders()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(g_trade.OrderDelete(ticket))
         PrintFormat("7Wave EA: deleted the unfilled order %I64u (its bar is over)", ticket);
     }
  }

//+------------------------------------------------------------------+
double TickSize()
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return(tick > 0.0 ? tick : _Point);
  }

//+------------------------------------------------------------------+
//| Price rounded to the broker's tick size (AGENTS.md, lesson 3).   |
//+------------------------------------------------------------------+
double Px(const double price)
  {
   double tick = TickSize();
   return(NormalizeDouble(MathRound(price / tick) * tick, _Digits));
  }

//+------------------------------------------------------------------+
//| Trade log in Common\Files: rewritten per tester run, appended    |
//| live.                                                            |
//+------------------------------------------------------------------+
void StartLog(const string name, const bool fresh)
  {
   g_logName = name;
   bool exists = FileIsExist(name, FILE_COMMON);
   if(!fresh && exists)
      return;
   int h = FileOpen(name, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, "signal_bar,side,level,fill_time,fill,atr,risk,stop,target,exit_time,exit,why,R,profit_usd,best_R\n");
   FileClose(h);
  }

void LogTrade(const datetime exitTime, const double exitPx, const string why, const double r, const double usd,
              const double bestR)
  {
   int h = FileOpen(g_logName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, StringFormat("%s,%s,%s,%s,%s,%.3f,%.3f,%s,%s,%s,%s,%s,%.3f,%.2f,%.3f\n",
                                   TimeToString(g_signalBar), g_dir > 0 ? "BUY" : "SELL",
                                   DoubleToString(g_level, _Digits), TimeToString(g_fillTime, TIME_DATE | TIME_SECONDS),
                                   DoubleToString(g_fill, _Digits), g_atr, g_risk, DoubleToString(g_initSl, _Digits),
                                   DoubleToString(g_tp, _Digits), TimeToString(exitTime, TIME_DATE | TIME_SECONDS),
                                   DoubleToString(exitPx, _Digits), why, r, usd, bestR));
   FileClose(h);
  }
//+------------------------------------------------------------------+
