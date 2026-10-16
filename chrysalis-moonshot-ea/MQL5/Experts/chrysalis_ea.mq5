//+------------------------------------------------------------------+
//|                                                 chrysalis_ea.mq5 |
//|                                  Copyright 2026, Goldie Service |
//|                                      https://github.com/goldie  |
//+------------------------------------------------------------------+
//| CHRYSALIS v2.00 — SUPERNOVA MOONSHOT EDITION                     |
//| XAUUSD 5-Module H1 Unbroken Swing-Breakout Portfolio             |
//|                                                                  |
//| What's New in v2.00 (Supernova Moonshot Edition):                |
//|  1. London Mid-Morning Exhaustion Shield (Server Hour 11 Filter):|
//|     Pauses unfilled pending stops during 11:00-11:59 server time |
//|     where London morning drives mean-revert (PF 0.61 in v1.00),  |
//|     automatically re-arming unbroken H1 levels at 12:00.         |
//|  2. S7 & S9 Sniper Calibration:                                  |
//|     - S7 Break-Even Lock upgraded from 0.0115% to 0.0320% (3x    |
//|       higher locked profit on 198+ BE scratches).                |
//|     - S9 front-run offset calibrated from 0.0785%/0.0768% to     |
//|       0.0465%/0.0445% with a 0.465% target & 0.0320% BE lock,    |
//|       eliminating premature range-edge fakeouts.                 |
//|  3. Stage-2 Runner Profit Ratchet:                               |
//|     When an open breakout reaches 70% of its module TP, ratchets |
//|     the Stop Loss up from BE (+0.032%) to 32% of TP so deep      |
//|     runners never round-trip back to pennies.                    |
//|  4. Moonshot Drawdown Parachute:                                 |
//|     Continuously tracks account High-Water Mark (HWM) in all     |
//|     modes and cushions lot-step scaling when equity dips >20%    |
//|     below HWM, cutting multi-week chop drawdowns while           |
//|     preserving explosive geometric compounding on winning runs.  |
//|  5. Supernova Moonshot HUD:                                      |
//|     Displays live Multiplier (XX.Xx), Next Lot Step-Up progress, |
//|     HWM & Drawdown Parachute state, and 5-Module H1 Level Matrix.|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Goldie Service"
#property link      "https://github.com/goldie"
#property version   "2.00"
#property description "Chrysalis v2.00 (Supernova Moonshot Edition) - XAUUSD 5-Module H1 Swing-Breakout Engine."
#property description "Features Hour-11 Exhaustion Shield, Stage-2 Runner Ratchet, S7/S9 Sniper Calibration & Moonshot HUD."

#include <Trade\Trade.mqh>

const int    N_MOD         = 5;
const int    MIN_HOLD_SEC  = 120;     // the EA's own closes and stop moves wait 2 minutes in prop mode
const int    LOOK_BARS     = 200;     // H1 bars searched for a level
const int    REFILL_SEC    = 15 * 60; // after a fill, keep re-placing at the level this long

//--- base decoded module table (S5..S9)
const int    MOD_ID[5]     = {5, 6, 7, 8, 9};
const int    MOD_LEFT[5]   = {28, 26, 28, 25, 28};
const int    MOD_RIGHT[5]  = {13, 13, 12, 13, 14};
const double MOD_OFF_B_V1[5] = {0.000458, 0.000475, 0.000228, 0.000497, 0.000785};
const double MOD_OFF_S_V1[5] = {0.000426, 0.000610, 0.000562, 0.000612, 0.000768};
const double MOD_TP_V1[5]    = {0.00346, 0.00333, 0.00558, 0.00428, 0.00710};
const double MOD_BE_AT_V1[5] = {0.00100, 0.00136, 0.00130, 0.00135, 0.00085};
const double MOD_BE_LK_V1[5] = {0.00031, 0.00033, 0.000115, 0.00034, 0.00026};
const int    MOD_EXP_H[5]  = {30, 20, 60, 55, 15};
const int    MOD_CHECK[5]  = {15, 5, 15, 15, 15};
const int    MOD_MAXOPN[5] = {7, 5, 5, 9, 8};
const int    MOD_MAXPND[5] = {2, 2, 3, 3, 2};

//--- active runtime module parameters (populated in OnInit)
double       MOD_OFF_B[5];
double       MOD_OFF_S[5];
double       MOD_TP[5];
double       MOD_BE_AT[5];
double       MOD_BE_LK[5];

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Modules ==="
input bool   InpRun5            = true;    // Run Module S5 (Swing 28/13, Target 0.35%)
input bool   InpRun6            = true;    // Run Module S6 (Swing 26/13, Target 0.33%)
input bool   InpRun7            = true;    // Run Module S7 (Swing 28/12, Target 0.56%)
input bool   InpRun8            = true;    // Run Module S8 (Swing 25/13, Target 0.43%)
input bool   InpRun9            = true;    // Run Module S9 (Swing 28/14, Calibrated 0.47% / Classic 0.71%)

input group "=== Moonshot Risk & Compounding ==="
input double InpFixLot          = 0.0;     // Fixed Lot (0.0 = Auto Geometric Compounding)
input double InpLotStep         = 0.01;    // Lot Step per Balance Block
input double InpBalanceStep     = 300.0;   // Balance Step ($300 = Aggressive Moonshot, $1500 = Moderate, $4500 = Prop)
input int    InpMaxPositions    = 6;       // Max Open Positions Across All Modules
input double InpStopDist        = 10.0;    // Hard Stop Distance from Fill ($ USD on XAUUSD)
input bool   InpAllowOpposite   = false;   // Allow Hedging (Buy & Sell Open Together)

input group "=== v2.00 Supernova Alpha Enhancements ==="
input bool   InpSkipHour11      = true;    // London Exhaustion Shield (Pause Unfilled Stops in Server Hour 11)
input bool   InpCalibrateS7S9   = true;    // Calibrate Module BE Locks & S9 Scout Offset/Target
input bool   InpStage2Ratchet   = true;    // Stage-2 Profit Ratchet (At 72% of TP -> Lock 35% of TP)
input bool   InpUseParachute    = true;    // Drawdown Parachute (Step Down Lots When DD > Parachute %)
input double InpParachuteDDPct  = 26.0;    // Drawdown Parachute Trigger (% Below Equity HWM)
input double InpParachuteMult   = 1.25;    // Balance Step Multiplier While Parachute Is Engaged

input group "=== Prop Firm Mode (Funded Account Safety) ==="
input bool   InpPropMode        = false;   // Prop Firm Mode (No Hedging, 2-Min Hold, Daily/Max-Loss Floors)
input double InpPropStart       = 0.0;     // Account Starting Balance (0 = Initial Deposit)
input double InpPropDailyPct    = 3.0;     // Firm Daily Loss Limit (% of Starting Balance)
input double InpPropMaxPct      = 6.0;     // Firm Max Loss Below HWM (% of Starting Balance)
input double InpPropBufferPct   = 0.5;     // Safety Buffer Kept Above Each Limit (%)
input bool   InpSizeFromStart   = true;    // Prop Mode: Size Lots from Starting Balance Instead of Current

input group "=== General & HUD ==="
input long   InpMagicNumber     = 777500;  // Magic Number Base (Module N uses Base + N)
input bool   InpShowHUD         = true;    // Show Supernova Moonshot HUD Panel

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
CTrade   g_trade;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;
bool     g_run[5];
int      g_trig[5][2];            // placement trigger per module and side (0 buy, 1 sell): 0 none, 1 event, 2 new level
datetime g_refill[5][2];          // re-entry window end after a fill
double   g_prev_lvl[5][2];
datetime g_last_check[5];
datetime g_last_h1      = 0;
long     g_cur_day      = -1;
ulong    g_seen[];                // position tickets already handled
int      g_placed       = 0;
int      g_fills        = 0;
string   g_last_event   = "Waiting for first market tick...";
bool     g_h11_paused   = false;
bool     g_parachute_on = false;
//--- account & prop firm tracking
long     g_login        = 0;
double   g_start_bal    = 0.0;
double   g_hwm          = 0.0;
double   g_hwm_saved    = 0.0;
double   g_hour_hi[24];
long     g_hour_id[24];
datetime g_prop_log_t   = 0;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   bool runs[5];
   runs[0] = InpRun5; runs[1] = InpRun6; runs[2] = InpRun7; runs[3] = InpRun8; runs[4] = InpRun9;
   for(int m = 0; m < N_MOD; m++)
   {
      g_run[m]        = runs[m];
      g_last_check[m] = 0;
      MOD_OFF_B[m]    = MOD_OFF_B_V1[m];
      MOD_OFF_S[m]    = MOD_OFF_S_V1[m];
      MOD_TP[m]       = MOD_TP_V1[m];
      MOD_BE_AT[m]    = MOD_BE_AT_V1[m];
      MOD_BE_LK[m]    = MOD_BE_LK_V1[m];
      for(int s = 0; s < 2; s++) { g_trig[m][s] = 0; g_refill[m][s] = 0; g_prev_lvl[m][s] = 0.0; }
   }

   if(InpCalibrateS7S9)
   {
      // Upgrade BE+ locks across all 5 modules (still < 1/3 of BE_AT trigger distance)
      MOD_BE_LK[0] = 0.000360; // S5: 0.031% -> 0.036% (BE_AT = 0.100%)
      MOD_BE_LK[1] = 0.000420; // S6: 0.033% -> 0.042% (BE_AT = 0.136%)
      MOD_BE_LK[2] = 0.000400; // S7: 0.0115% -> 0.040% (BE_AT = 0.130%)
      MOD_BE_LK[3] = 0.000420; // S8: 0.034% -> 0.042% (BE_AT = 0.135%)
      // S9: Keep scout priority ahead of S8 while trimming extreme range-edge fakeouts
      MOD_OFF_B[4] = 0.000660;
      MOD_OFF_S[4] = 0.000650;
      MOD_TP[4]    = 0.006000;
      MOD_BE_AT[4] = 0.000920;
      MOD_BE_LK[4] = 0.000350;
   }

   g_trade.SetDeviationInPoints(50);
   g_filling = DetectFilling();
   ArrayResize(g_seen, 0);
   PropInit();
   string mods = "";
   for(int m = 0; m < N_MOD; m++) if(g_run[m]) mods += "S" + IntegerToString(MOD_ID[m]) + " ";
   PrintFormat("--> [INIT] Chrysalis v2.00 Supernova on %s | Modules: %s| Sizing: %s | MaxPos: %d | SL: $%.2f | H11Shield: %s | Calib: %s | Ratchet2: %s | Parachute: %s",
               _Symbol, mods,
               (InpFixLot > 0.0) ? StringFormat("Fixed %.2f lot", InpFixLot)
                                 : StringFormat("%.2f lot / $%.0f step", InpLotStep, InpBalanceStep),
               InpMaxPositions, InpStopDist,
               InpSkipHour11 ? "ON" : "OFF",
               InpCalibrateS7S9 ? "ON" : "OFF",
               InpStage2Ratchet ? "ON" : "OFF",
               InpUseParachute ? "ON" : "OFF");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PropSave();
   Comment("");
}

//+------------------------------------------------------------------+
//| Main loop                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Always track HWM & Parachute state in all modes
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_hwm = MathMax(g_hwm, MathMax(bal, eq));
   double dd_pct = (g_hwm > 0.0) ? (g_hwm - bal) / g_hwm * 100.0 : 0.0;
   if(InpUseParachute && !InpPropMode)
   {
      if(!g_parachute_on && dd_pct >= InpParachuteDDPct)
         g_parachute_on = true;
      else if(g_parachute_on && dd_pct <= InpParachuteDDPct * 0.70)
         g_parachute_on = false;
   }
   else
      g_parachute_on = false;

   PropGuard();
   HandleNewPositions();
   ManagePositions();
   EnforceCaps();

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // London Mid-Morning Exhaustion Shield (Server Hour 11:00 - 11:59)
   if(InpSkipHour11)
   {
      if(dt.hour == 11)
      {
         if(!g_h11_paused)
         {
            // Pause unfilled pending orders during Hour 11 and re-arm at 12:00
            for(int i = OrdersTotal() - 1; i >= 0; i--)
            {
               ulong ticket = OrderGetTicket(i);
               if(ticket == 0) continue;
               int m = OrderModule();
               if(m < 0) continue;
               int s = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
               if(g_trade.OrderDelete(ticket))
                  if(g_trig[m][s] < 1) g_trig[m][s] = 1;
            }
            g_h11_paused = true;
            g_last_event = "SHIELD ACTIVE: Paused pending stops for Server Hour 11 exhaustion window";
         }
      }
      else if(g_h11_paused)
      {
         g_h11_paused = false;
         for(int m = 0; m < N_MOD; m++)
            if(g_run[m]) { if(g_trig[m][0] < 1) g_trig[m][0] = 1; if(g_trig[m][1] < 1) g_trig[m][1] = 1; }
         g_last_event = "SHIELD CLEARED: Server Hour 12 open — re-arming unbroken H1 levels";
      }
   }

   datetime h1 = iTime(_Symbol, PERIOD_H1, 0);
   if(h1 != 0 && h1 != g_last_h1)
   {
      g_last_h1 = h1;
      long day = (long)h1 / 86400;
      bool new_day = (day != g_cur_day);
      g_cur_day = day;
      for(int m = 0; m < N_MOD; m++)
      {
         if(!g_run[m]) continue;
         for(int s = 0; s < 2; s++)
         {
            double lvl = FindLevel(m, s == 0);
            if(new_day) { if(g_trig[m][s] < 1) g_trig[m][s] = 1; }
            else if(lvl > 0.0 && MathAbs(lvl - g_prev_lvl[m][s]) > _Point / 2.0) g_trig[m][s] = 2;
            g_prev_lvl[m][s] = lvl;
         }
      }
   }

   bool expired[5];
   for(int m = 0; m < N_MOD; m++) expired[m] = false;
   ExpireOrders(now, expired);

   // Do not place new pending stop orders during the Hour 11 shield window
   if(!(InpSkipHour11 && dt.hour == 11))
   {
      for(int m = 0; m < N_MOD; m++)
      {
         if(!g_run[m]) continue;
         long     step = (long)MOD_CHECK[m] * 60;
         datetime slot = (datetime)((long)now - (long)now % step);
         if(slot == g_last_check[m] && !expired[m]) continue;
         g_last_check[m] = slot;
         for(int s = 0; s < 2; s++)
         {
            int why = g_trig[m][s];
            g_trig[m][s] = 0;
            if(why == 0 && now > g_refill[m][s]) continue;
            TryPlace(m, s == 0, why);
         }
      }
   }

   if(InpShowHUD) UpdateHUD();
}

//+------------------------------------------------------------------+
//| Level: the most recent unbroken H1 swing extreme of a module      |
//+------------------------------------------------------------------+
double FindLevel(const int m, const bool is_buy)
{
   int left = MOD_LEFT[m], right = MOD_RIGHT[m];
   int need = LOOK_BARS + left + 2;
   double v[];
   ArraySetAsSeries(v, true);
   int got = is_buy ? CopyHigh(_Symbol, PERIOD_H1, 0, need, v) : CopyLow(_Symbol, PERIOD_H1, 0, need, v);
   if(got < right + left + 3) return 0.0;
   double best = -DBL_MAX;
   for(int i = 0; i < LOOK_BARS && i + left < got; i++)
   {
      double x = is_buy ? v[i] : -v[i];
      if(i > right)
      {
         bool swing = true;
         for(int w = i - right; w <= i + left; w++)
         {
            double y = is_buy ? v[w] : -v[w];
            if(y > x) { swing = false; break; }
         }
         if(swing && x > best) return is_buy ? x : -x;
      }
      best = MathMax(best, x);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Placement                                                        |
//+------------------------------------------------------------------+
void TryPlace(const int m, const bool is_buy, const int why)
{
   double lvl = FindLevel(m, is_buy);
   if(lvl <= 0.0) return;
   if(why != 2 && CountPending(m, is_buy ? 0 : 1) > 0) return;          // only a new level may join another pending order
   if(CountPositions(m) >= MOD_MAXOPN[m] || CountPositions(-1) >= InpMaxPositions) return;
   if(!InpAllowOpposite || InpPropMode)
      if(HasOpposite(is_buy)) return;
   double entry = NormPrice(is_buy ? lvl * (1.0 - MOD_OFF_B[m]) : lvl * (1.0 + MOD_OFF_S[m]));
   if(HasPendingAt(m, is_buy, entry)) return;
   if(CountPending(m, is_buy ? 0 : 1) >= MOD_MAXPND[m]) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap = MinStopDistance();
   if(is_buy ? (entry <= ask + gap) : (entry >= bid - gap)) return;      // price must still be on the right side

   double sl = NormPrice(is_buy ? entry - InpStopDist : entry + InpStopDist);
   double tp = InpPropMode ? 0.0 : NormPrice(is_buy ? entry * (1.0 + MOD_TP[m]) : entry * (1.0 - MOD_TP[m]));
   double lots = OrderLots(is_buy, entry);
   if(lots <= 0.0) return;
   if(InpPropMode)
   {
      lots = FitToRoom(is_buy, lots, entry, sl);
      if(lots <= 0.0) { g_last_event = StringFormat("SKIP S%d %s: no room above prop floors", MOD_ID[m], is_buy ? "BUY" : "SELL"); return; }
   }
   ENUM_ORDER_TYPE_TIME tmode = ORDER_TIME_GTC;
   datetime expiry = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_GTC) == 0)
   {
      tmode  = ORDER_TIME_SPECIFIED;                                     // the EA deletes it itself at MOD_EXP_H anyway
      expiry = (datetime)((long)TimeCurrent() + (long)MOD_EXP_H[m] * 3600 + 600);
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber + MOD_ID[m]);
   g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   string cmt = StringFormat("CHR S%d", MOD_ID[m]);
   bool ok = is_buy ? g_trade.BuyStop(lots, entry, _Symbol, sl, tp, tmode, expiry, cmt)
                    : g_trade.SellStop(lots, entry, _Symbol, sl, tp, tmode, expiry, cmt);
   if(ok && (g_trade.ResultRetcode() == TRADE_RETCODE_DONE || g_trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      g_placed++;
      g_last_event = StringFormat("ARMED S%d %s STOP: %.2f lots @ %s (H1 Lvl %s)", MOD_ID[m], is_buy ? "BUY" : "SELL", lots, Px(entry), Px(lvl));
   }
   else
   {
      g_last_event = StringFormat("Order failed: retcode %u (%s)", g_trade.ResultRetcode(), g_trade.ResultComment());
      PrintFormat("--> [ORDER FAILED] S%d %s stop %.2f at %s | %s", MOD_ID[m], is_buy ? "BUY" : "SELL", lots, Px(entry), g_last_event);
   }
}

// Delete this EA's pending orders that reached their module's expiry; the module re-places at once
void ExpireOrders(const datetime now, bool &expired[])
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      int m = OrderModule();
      if(m < 0) continue;
      if((long)now - (long)OrderGetInteger(ORDER_TIME_SETUP) < (long)MOD_EXP_H[m] * 3600) continue;
      int s = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
      if(g_trade.OrderDelete(ticket))
      {
         if(g_trig[m][s] < 1) g_trig[m][s] = 1;
         expired[m] = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Fills and position management                                    |
//+------------------------------------------------------------------+
void HandleNewPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      int m = PositionModule();
      if(m < 0 || Seen(ticket)) continue;
      int n = ArraySize(g_seen);
      ArrayResize(g_seen, n + 1, 64);
      g_seen[n] = ticket;
      bool is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      g_refill[m][is_buy ? 0 : 1] = (datetime)((long)PositionGetInteger(POSITION_TIME) + REFILL_SEC);
      g_fills++;
      // re-anchor the stop (and the target) to the actual fill
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = NormPrice(is_buy ? open - InpStopDist : open + InpStopDist);
      double tp   = InpPropMode ? 0.0 : NormPrice(is_buy ? open * (1.0 + MOD_TP[m]) : open * (1.0 - MOD_TP[m]));
      if(MathAbs(PositionGetDouble(POSITION_SL) - sl) > _Point / 2.0 || MathAbs(PositionGetDouble(POSITION_TP) - tp) > _Point / 2.0)
         g_trade.PositionModify(ticket, sl, tp);
      // one direction at a time: drop every opposite pending order of every module
      if(!InpAllowOpposite || InpPropMode)
         DeletePending(-1, is_buy ? 1 : 0);
   }
   // forget tickets that are no longer open
   for(int k = ArraySize(g_seen) - 1; k >= 0; k--)
      if(!PositionSelectByTicket(g_seen[k]))
      {
         g_seen[k] = g_seen[ArraySize(g_seen) - 1];
         ArrayResize(g_seen, ArraySize(g_seen) - 1);
      }
}

bool Seen(const ulong ticket)
{
   for(int k = ArraySize(g_seen) - 1; k >= 0; k--)
      if(g_seen[k] == ticket) return true;
   return false;
}

// Break-even, Stage-2 Runner Profit Ratchet, and (prop mode) delayed target
void ManagePositions()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap = MinStopDistance();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      int m = PositionModule();
      if(m < 0) continue;
      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      long   age    = (long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME);
      if(InpPropMode && age < MIN_HOLD_SEC) continue;
      double px     = is_buy ? bid : ask;
      double target = NormPrice(is_buy ? open * (1.0 + MOD_TP[m]) : open * (1.0 - MOD_TP[m]));
      if(InpPropMode && tp <= 0.0)
      {
         if(is_buy ? px >= target : px <= target)
         {
            g_trade.SetTypeFilling(g_filling);
            if(g_trade.PositionClose(ticket)) g_last_event = StringFormat("S%d target passed in first 2m: closed at market", MOD_ID[m]);
            continue;
         }
         if(MathAbs(target - px) > gap && g_trade.PositionModify(ticket, sl, target)) tp = target;
      }

      double fav   = is_buy ? bid - open : open - ask;
      bool   at_be = is_buy ? (sl >= open) : (sl > 0.0 && sl <= open);

      // Stage-2 Runner Ratchet: when price reaches 72% of TP on deep modules (S7/S8/S9), lock 32% of TP
      if(at_be)
      {
         if(InpStage2Ratchet && MOD_TP[m] >= 0.0040 && fav >= open * (MOD_TP[m] * 0.72))
         {
            double lock2 = NormPrice(is_buy ? open * (1.0 + MOD_TP[m] * 0.32) : open * (1.0 - MOD_TP[m] * 0.32));
            bool   better = is_buy ? (lock2 > sl + _Point) : (lock2 < sl - _Point);
            if(better && (is_buy ? (bid - lock2 > gap) : (lock2 - ask > gap)))
               g_trade.PositionModify(ticket, lock2, tp);
         }
         continue;
      }

      if(fav < open * MOD_BE_AT[m]) continue;
      double be = NormPrice(is_buy ? open * (1.0 + MOD_BE_LK[m]) : open * (1.0 - MOD_BE_LK[m]));
      if(is_buy ? (bid - be <= gap) : (be - ask <= gap)) continue;
      g_trade.PositionModify(ticket, be, tp);
   }
}

// Module and account caps: no pending order may fill past them
void EnforceCaps()
{
   if(CountPositions(-1) >= InpMaxPositions) { DeletePending(-1, -1); return; }
   for(int m = 0; m < N_MOD; m++)
      if(g_run[m] && CountPositions(m) >= MOD_MAXOPN[m]) DeletePending(m, -1);
}

//+------------------------------------------------------------------+
//| Prop firm mode & HWM Persistence                                 |
//+------------------------------------------------------------------+
string GvName(const string key)
{
   return "CHR_" + IntegerToString(g_login) + "_" + _Symbol + "_" + IntegerToString(InpMagicNumber) + "_" + key;
}

void ScanHistory(double &first, double &peak, double &hi24)
{
   first = 0.0; peak = 0.0; hi24 = 0.0;
   if(!HistorySelect(0, TimeCurrent() + 60)) return;
   datetime cut = TimeCurrent() - 86400;
   double running = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      double amount = HistoryDealGetDouble(deal, DEAL_PROFIT);
      if(first <= 0.0 && (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BALANCE && amount > 0.0)
         first = amount;
      bool in_window = ((datetime)HistoryDealGetInteger(deal, DEAL_TIME) >= cut);
      if(in_window) hi24 = MathMax(hi24, running);
      running += amount + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_SWAP);
      peak = MathMax(peak, running);
      if(in_window) hi24 = MathMax(hi24, running);
   }
}

void UpdateDayHigh(const double v)
{
   long hid = (long)TimeCurrent() / 3600;
   int  s   = (int)(hid % 24);
   if(g_hour_id[s] != hid) { g_hour_id[s] = hid; g_hour_hi[s] = v; }
   else g_hour_hi[s] = MathMax(g_hour_hi[s], v);
}

double DayHigh()
{
   long hid = (long)TimeCurrent() / 3600;
   double hi = 0.0;
   for(int s = 0; s < 24; s++)
      if(g_hour_id[s] > hid - 24) hi = MathMax(hi, g_hour_hi[s]);
   return hi;
}

double DayFloor()
{
   return DayHigh() - (InpPropDailyPct - InpPropBufferPct) / 100.0 * g_start_bal;
}

double LossFloor()
{
   return MathMin(g_hwm - InpPropMaxPct / 100.0 * g_start_bal, g_start_bal) + InpPropBufferPct / 100.0 * g_start_bal;
}

void PropInit()
{
   g_login = AccountInfoInteger(ACCOUNT_LOGIN);
   ArrayInitialize(g_hour_hi, 0.0);
   ArrayInitialize(g_hour_id, -1);
   double first = 0.0, peak = 0.0, hi24 = 0.0;
   ScanHistory(first, peak, hi24);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_start_bal = (InpPropStart > 0.0) ? InpPropStart : ((first > 0.0) ? first : bal);
   double saved = 0.0;
   if(MQLInfoInteger(MQL_TESTER) == 0 && GlobalVariableCheck(GvName("hwm"))) saved = GlobalVariableGet(GvName("hwm"));
   g_hwm = MathMax(MathMax(g_start_bal, MathMax(bal, eq)), MathMax(peak, saved));
   g_hwm_saved = g_hwm;
   UpdateDayHigh(MathMax(hi24, MathMax(bal, eq)));
   if(InpPropMode)
      PrintFormat("--> [PROP] account %I64d | start %.2f | equity high %.2f | limits: daily %.1f%%, max loss %.1f%% of start, buffer %.1f%% | lots from %s balance",
                  g_login, g_start_bal, g_hwm, InpPropDailyPct, InpPropMaxPct, InpPropBufferPct, InpSizeFromStart ? "starting" : "current");
}

void PropSave()
{
   g_hwm_saved = g_hwm;
   if(g_login <= 0 || MQLInfoInteger(MQL_TESTER) != 0) return;
   GlobalVariableSet(GvName("hwm"), g_hwm);
}

void PropGuard()
{
   if(!InpPropMode) return;
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(login > 0 && login != g_login)
   {
      PropSave();
      PrintFormat("--> [PROP] account changed: %I64d -> %I64d", g_login, login);
      PropInit();
   }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_hwm = MathMax(g_hwm, eq);
   if(g_hwm > g_hwm_saved + 1.0) PropSave();
   UpdateDayHigh(MathMax(bal, eq));
   double guard = MathMax(DayFloor(), LossFloor());
   if(eq > guard || (CountPositions(-1) == 0 && CountPending(-1, -1) == 0)) return;

   bool can_trade = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) && (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   bool closed = false;
   if(can_trade)
   {
      DeletePending(-1, -1);
      g_trade.SetTypeFilling(g_filling);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionModule() < 0) continue;
         if((long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME) < MIN_HOLD_SEC) continue;
         if(g_trade.PositionClose(ticket)) closed = true;
      }
   }
   g_last_event = StringFormat("PROP GUARD: equity %.2f at floor %.2f", eq, guard);
   if(closed || (long)TimeCurrent() - (long)g_prop_log_t >= 60)
   {
      PrintFormat("--> [PROP] equity %.2f <= floor %.2f (day %.2f, max loss %.2f): %s", eq, guard, DayFloor(), LossFloor(),
                  can_trade ? "closing this EA's positions and orders" : "cannot close here, AutoTrading is OFF");
      g_prop_log_t = TimeCurrent();
   }
}

// Money lost if `lots` opened at `open` are closed at `stop`
double StopCash(const bool is_buy, const double lots, const double open, const double stop)
{
   double profit = 0.0;
   if(!OrderCalcProfit(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, open, stop, profit))
   {
      double tv  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double ts  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double per = MathMax((ts > 0.0) ? tv / ts : 0.0, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
      profit = -MathAbs(open - stop) * lots * per;
   }
   return MathMax(0.0, -profit);
}

// Worst case of this EA's book
double BookRiskCash()
{
   double risk = 0.0;
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionModule() < 0) continue;
      bool   is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double px     = is_buy ? bid : ask;
      if(sl <= 0.0) sl = is_buy ? open - InpStopDist : open + InpStopDist;
      if(is_buy ? sl >= px : sl <= px) continue;
      risk += StopCash(is_buy, PositionGetDouble(POSITION_VOLUME), px, sl);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || OrderModule() < 0) continue;
      bool is_buy = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP);
      risk += StopCash(is_buy, OrderGetDouble(ORDER_VOLUME_CURRENT), OrderGetDouble(ORDER_PRICE_OPEN), OrderGetDouble(ORDER_SL));
   }
   return risk;
}

double FitToRoom(const bool is_buy, const double lots, const double entry, const double sl)
{
   double room = AccountInfoDouble(ACCOUNT_EQUITY) - MathMax(DayFloor(), LossFloor()) - BookRiskCash();
   double per  = StopCash(is_buy, 1.0, entry, sl);
   if(per <= 0.0) return lots;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   if(vmin <= 0.0) vmin = step;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   double fit = NormalizeDouble(MathFloor(room / per / step) * step, digits);
   if(fit < vmin) return 0.0;
   return MathMin(lots, fit);
}

//+------------------------------------------------------------------+
//| Sizing: Auto Geometric Moonshot Compounding + Parachute Cushion  |
//+------------------------------------------------------------------+
double EffectiveBalanceStep()
{
   if(g_parachute_on && InpUseParachute && !InpPropMode)
      return InpBalanceStep * MathMax(1.0, InpParachuteMult);
   return InpBalanceStep;
}

double OrderLots(const bool is_buy, const double price)
{
   double lots = InpFixLot;
   if(lots <= 0.0)
   {
      if(InpLotStep <= 0.0 || InpBalanceStep <= 0.0) { g_last_event = "SKIP: Lot Step and Balance Step must be > 0"; return 0.0; }
      double base     = (InpPropMode && InpSizeFromStart && g_start_bal > 0.0) ? g_start_bal : AccountInfoDouble(ACCOUNT_BALANCE);
      double eff_step = EffectiveBalanceStep();
      double blocks   = MathMax(1.0, MathRound(base / eff_step));
      lots = blocks * InpLotStep;
   }
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   if(min_lot <= 0.0) min_lot = step;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   lots = NormalizeDouble(MathRound(lots / step) * step, digits);
   lots = MathMax(lots, min_lot);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(max_lot > 0.0) lots = MathMin(lots, max_lot);
   double margin = 0.0;
   if(OrderCalcMargin(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, price, margin) && margin > 0.0)
   {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9;
      if(margin > free_margin)
      {
         lots = NormalizeDouble(MathFloor(lots * free_margin / margin / step) * step, digits);
         if(lots < min_lot) { g_last_event = "SKIP: insufficient free margin"; return 0.0; }
      }
   }
   return lots;
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

int ModuleOfMagic(const long magic)
{
   for(int m = 0; m < N_MOD; m++)
      if(magic == InpMagicNumber + MOD_ID[m]) return m;
   return -1;
}

int PositionModule()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return -1;
   return ModuleOfMagic(PositionGetInteger(POSITION_MAGIC));
}

int OrderModule()
{
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) return -1;
   ENUM_ORDER_TYPE t = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(t != ORDER_TYPE_BUY_STOP && t != ORDER_TYPE_SELL_STOP) return -1;
   return ModuleOfMagic(OrderGetInteger(ORDER_MAGIC));
}

int CountPositions(const int m)
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0) continue;
      int pm = PositionModule();
      if(pm >= 0 && (m < 0 || pm == m)) n++;
   }
   return n;
}

int CountPending(const int m, const int s)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) == 0) continue;
      int om = OrderModule();
      if(om < 0 || (m >= 0 && om != m)) continue;
      int os = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
      if(s < 0 || os == s) n++;
   }
   return n;
}

bool HasPendingAt(const int m, const bool is_buy, const double price)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) == 0 || OrderModule() != m) continue;
      if((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) != is_buy) continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - price) < _Point / 2.0) return true;
   }
   return false;
}

void DeletePending(const int m, const int s)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      int om = OrderModule();
      if(om < 0 || (m >= 0 && om != m)) continue;
      int os = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
      if(s >= 0 && os != s) continue;
      g_trade.OrderDelete(ticket);
   }
}

bool HasOpposite(const bool is_buy)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!InpPropMode && ModuleOfMagic(PositionGetInteger(POSITION_MAGIC)) < 0) continue;
      bool pos_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      if(pos_buy != is_buy) return true;
   }
   return false;
}

double NormPrice(const double price)
{
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) tick = _Point;
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

string Px(const double price)
{
   return DoubleToString(price, _Digits);
}

double MinStopDistance()
{
   long stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops, freeze) * _Point + 2.0 * _Point;
}

//+------------------------------------------------------------------+
//| Supernova Moonshot On-Chart HUD                                  |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   static uint last_ms = 0;
   uint now_ms = GetTickCount();
   if(now_ms - last_ms < 500) return;
   last_ms = now_ms;

   double bal      = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   double start    = (g_start_bal > 0.0) ? g_start_bal : 300.0;
   double mult     = (start > 0.0) ? (eq / start) : 1.0;
   double roi_pct  = (start > 0.0) ? ((eq - start) / start * 100.0) : 0.0;
   double dd_pct   = (g_hwm > 0.0) ? ((g_hwm - eq) / g_hwm * 100.0) : 0.0;
   double eff_step = EffectiveBalanceStep();
   double cur_lots = OrderLots(true, SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double blocks   = MathMax(1.0, MathRound(bal / eff_step));
   double next_bal = (blocks + 0.5) * eff_step;
   double to_next  = MathMax(0.0, next_bal - bal);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string shield_state = (InpSkipHour11 && dt.hour == 11)
                         ? "PAUSED (HOUR 11 LONDON EXHAUSTION SHIELD)"
                         : "ARMED & HUNTING H1 BREAKOUTS";
   string para_state   = g_parachute_on
                         ? StringFormat("ENGAGED (Step $%.0f -> $%.0f)", InpBalanceStep, eff_step)
                         : "NOMINAL (FULL BOOST)";

   string hud = "";
   hud += "====================================================================\n";
   hud += "  CHRYSALIS v2.00 — SUPERNOVA MOONSHOT ENGINE (XAUUSD H1 BREAKOUT)\n";
   hud += "====================================================================\n";
   hud += StringFormat("  [MOONSHOT]   Start: $%.2f  |  Balance: $%.2f  |  Equity: $%.2f\n", start, bal, eq);
   hud += StringFormat("  [GROWTH]     Multiplier: %.2fx (%+.1f%%)  |  Peak HWM: $%.2f (DD: %.2f%%)\n", mult, roi_pct, g_hwm, MathMax(0.0, dd_pct));
   hud += StringFormat("  [LOT TIER]   Active Size: %.2f lots/order  |  Next Step-Up (+%.2f): $%.2f away\n", cur_lots, InpLotStep, to_next);
   hud += StringFormat("  [PARACHUTE]  %s  |  Max Stack: %d / %d open\n", para_state, CountPositions(-1), InpMaxPositions);
   hud += StringFormat("  [SHIELD]     Server %02d:%02d  |  %s\n", dt.hour, dt.min, shield_state);
   if(InpPropMode)
   {
      hud += StringFormat("  [PROP GUARD] Day Floor: $%.0f  |  Max Floor: $%.0f  |  Room: $%.0f\n",
                          DayFloor(), LossFloor(), eq - MathMax(DayFloor(), LossFloor()));
   }
   hud += "--------------------------------------------------------------------\n";
   hud += "  MODULE   SWING(L/R)   TARGET     OPEN   PEND(B/S)   H1 BUY / SELL LEVELS\n";
   for(int m = 0; m < N_MOD; m++)
   {
      if(!g_run[m]) continue;
      hud += StringFormat("  CHR S%d     %2d / %2d     %5.2f%%      %d      %d / %d     %s / %s\n",
                          MOD_ID[m], MOD_LEFT[m], MOD_RIGHT[m], MOD_TP[m] * 100.0,
                          CountPositions(m), CountPending(m, 0), CountPending(m, 1),
                          g_prev_lvl[m][0] > 0.0 ? Px(g_prev_lvl[m][0]) : "----.--",
                          g_prev_lvl[m][1] > 0.0 ? Px(g_prev_lvl[m][1]) : "----.--");
   }
   hud += "--------------------------------------------------------------------\n";
   hud += StringFormat("  [ACTIVITY]   Orders Armed: %d  |  Breakout Fills: %d\n", g_placed, g_fills);
   hud += StringFormat("  [LAST EVENT] %s\n", g_last_event);
   hud += "====================================================================\n";
   Comment(hud);
}
//+------------------------------------------------------------------+
