//+------------------------------------------------------------------+
//|                                          btcusd_chrysalis_ea.mq5 |
//|                                  Copyright 2026, Goldie Service |
//|                                      https://github.com/goldie  |
//+------------------------------------------------------------------+
//| BTCUSD CHRYSALIS v2.00 — 24/7 SATOSHI SUPERNOVA MOONSHOT EDITION |
//| Bitcoin 9-Module H1 Unbroken Swing-Breakout + SuperTrend Engine  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Goldie Service"
#property link      "https://github.com/goldie"
#property version   "2.00"
#property description "BTCUSD Chrysalis v2.00 (24/7 Satoshi Supernova Moonshot Edition) - Bitcoin H1 Swing + SuperTrend Overdrive Engine."
#property description "Engineered for 24/7 Crypto Liquidation Cascades, 3-Gear Overdrive Transmission, 37-Lot Book Manager & $300 Moonshot Scaling."

#include <Trade\Trade.mqh>

const int    N_MOD         = 9;
const int    MIN_HOLD_SEC  = 120;     // the EA's own closes and stop moves wait 2 minutes in prop mode
const int    LOOK_BARS     = 200;     // H1 bars searched for a level
const int    REFILL_SEC    = 15 * 60; // after a fill, keep re-placing at the level this long

//--- base decoded module table (S1..S4 Drought Breakers + S5..S9 Core Supernova) calibrated for BTCUSD % volatility
const int    MOD_ID[9]       = {      1,        2,        3,        4,        5,        6,        7,        8,        9 };
const int    MOD_GAPFILL[9]  = {      1,        1,        1,        1,        0,        0,        0,        0,        0 };
const int    MOD_LEFT[9]     = {     18,       20,       22,       24,       28,       26,       30,       32,       28 };
const int    MOD_RIGHT[9]    = {      9,       10,       11,       11,       13,       13,       14,       13,       14 };
const double MOD_OFF_B_V1[9] = {0.000850, 0.000900, 0.000950, 0.001000, 0.000920, 0.000850, 0.001150, 0.000950, 0.001180};
const double MOD_OFF_S_V1[9] = {0.000850, 0.000900, 0.000950, 0.001000, 0.000920, 0.001080, 0.001150, 0.000950, 0.001160};
const double MOD_TP_V1[9]    = {0.00680,  0.00720,  0.00760,  0.00820,  0.00820,  0.00720,  0.01180,  0.00880,  0.01280};
const double MOD_BE_AT_V1[9] = {0.00175,  0.00180,  0.00185,  0.00190,  0.00185,  0.00210,  0.00180,  0.00185,  0.00180};
const double MOD_BE_LK_V1[9] = {0.00075,  0.00078,  0.00080,  0.00082,  0.00080,  0.00085,  0.00080,  0.00082,  0.00078};
const int    MOD_EXP_H[9]    = {     18,       18,       20,       20,       20,       18,       15,       18,       15 };
const int    MOD_CHECK[9]    = {     15,       15,       15,       15,       15,        5,       15,       15,       15 };
const int    MOD_MAXOPN[9]   = {      1,        1,        1,        1,        6,        6,        4,        4,        8 };
const int    MOD_MAXPND[9]   = {      1,        1,        1,        1,        2,        2,        1,        1,        2 };

//--- active runtime module parameters (populated in OnInit)
double       MOD_OFF_B[9];
double       MOD_OFF_S[9];
double       MOD_TP[9];
double       MOD_BE_AT[9];
double       MOD_BE_LK[9];

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== 9-Module H1 Unbroken Swing Matrix (S1 - S9) ==="
input bool   InpRun1            = true;    // Run Module S1 (Drought Breaker 18/9, Target 0.61%)
input bool   InpRun2            = true;    // Run Module S2 (Drought Breaker 20/10, Target 0.65%)
input bool   InpRun3            = true;    // Run Module S3 (Drought Breaker 22/11, Target 0.68%)
input bool   InpRun4            = true;    // Run Module S4 (Drought Breaker 24/11, Target 0.74%)
input bool   InpRun5            = true;    // Run Module S5 (Swing 28/13, Target 0.74%)
input bool   InpRun6            = true;    // Run Module S6 (Swing 26/13, Target 0.65%)
input bool   InpRun7            = true;    // Run Module S7 (Macro 30/14, Target 1.06%)
input bool   InpRun8            = true;    // Run Module S8 (Macro 32/13, Target 0.79%)
input bool   InpRun9            = true;    // Run Module S9 (Swing 28/14, Target 1.15%)

input group "=== Moonshot Risk & Compounding ==="
input double InpFixLot          = 0.0;     // Fixed Lot (0.0 = Auto Geometric Compounding)
input double InpLotStep         = 0.01;    // Lot Step per Balance Block (0.01 = 0.01 BTC)
input double InpBalanceStep     = 125.0;   // Balance Step ($125 w/ $360 Seed Shield = Supernova, $300 = Moderate)
input int    InpMaxPositions    = 6;       // Max Open Core Positions (S5-S9)
input double InpStopDist        = 900.0;   // Fallback Stop Distance ($ USD per BTC if InpStopPct == 0)
input double InpMaxOrderLot     = 6.00;    // Max Lot per Single Order (Respects 37-Lot Symbol Volume Limit)
input bool   InpAllowOpposite   = false;   // Allow Hedging (Buy & Sell Open Together)

input group "=== v2.00 Satoshi Supernova Alpha Enhancements ==="
input double InpScaleMult       = 0.90;    // Volatility Scale Multiplier for Offsets/BE/TP (0.90 = Calibrated)
input double InpStopPct         = 1.20;    // Dynamic Stop Loss % of BTC Price (1.20% = Regime-Invariant)
input int    InpRegimeGateMode  = 11;      // BTC Regime Mode (11=SuperTrend Overdrive, 9=Low-DD Cap, 0=v1.0)
input double InpMinRng12        = 0.0145;  // Min 12h Range Expansion % for Core Breakouts (0.0145 = 1.45%)
input double InpJITProximityPct = 0.0;     // JIT Proximity Arming % When Lots >= 0.50 (0.0 = Off, 0.85 = 0.85%)
input double InpSmoothSeed      = 0.0;     // Smooth Seed Mode (0.0 = Direct Turbo)
input double InpBoostMult       = 0.80;    // Supernova Overdrive Step Mult When DD<=10% (0.80 = +25% Lots)
input double InpBoostCapBal     = 16000.0; // Max Balance for Stage-2 Overdrive (Above Uses Base $125 Step)
input double InpMaxSlotRiskPct  = 8.20;    // Max Per-Slot SL Risk % of Balance (Prevents High-BTC-Price Overleverage)
input bool   InpRolloverShield  = true;    // Daily Rollover Shield (Skip 23:55-00:05 Server Maintenance Window)
input int    InpSessionMode     = 6;       // Session Mode (6=Active Judas/Vacuum Shield, 5=NoPlace H04/21/23)
input bool   InpSkipHour11      = false;   // Optional Server Hour 11 Shield
input int    InpDroughtHours    = 72;      // Idle H1 Bars Before S1-S4 Drought Breakers Activate
input int    InpMaxDroughtPos   = 1;       // Max Concurrent S1-S4 Drought-Breaker Positions (Non-Dilutive)
input bool   InpStage2Ratchet   = true;    // 3-Stage Crypto Profit Ratchet (42% TP -> 20%, 68% TP -> 40%)
input bool   InpUseParachute    = true;    // Drawdown Parachute (Step Down Lots When DD > Parachute %)
input double InpParachuteDDPct  = 26.0;    // Drawdown Parachute Trigger (% Below Equity HWM)
input double InpParachuteMult   = 1.25;    // Balance Step Multiplier While Parachute Is Engaged
input bool   InpExportH1CSV     = false;   // Export H1 History CSV on Tester Deinit (R&D Only)

input group "=== Prop Firm Mode (Optional) ==="
input bool   InpPropMode        = false;   // Prop Firm Mode (No Hedging, 2-Min Hold, Daily/Max-Loss Floors)
input double InpPropStart       = 0.0;     // Account Starting Balance (0 = Initial Deposit)
input double InpPropDailyPct    = 3.0;     // Firm Daily Loss Limit (% of Starting Balance)
input double InpPropMaxPct      = 6.0;     // Firm Max Loss Below HWM (% of Starting Balance)
input double InpPropBufferPct   = 0.5;     // Safety Buffer Kept Above Each Limit (%)
input bool   InpSizeFromStart   = true;    // Prop Mode: Size Lots from Starting Balance Instead of Current

input group "=== General & HUD ==="
input long   InpMagicNumber     = 777900;  // Magic Number Base (Module N uses Base + N)
input bool   InpShowHUD         = true;    // Show Satoshi Supernova HUD Panel

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
CTrade   g_trade;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;
bool     g_run[9];
int      g_trig[9][2];
datetime g_refill[9][2];
double   g_prev_lvl[9][2];
double   g_filled_lvl[9][2];
datetime g_last_check[9];
datetime g_last_h1      = 0;
datetime g_last_fill_t  = 0;
long     g_cur_day      = -1;
ulong    g_seen[];
int      g_placed       = 0;
int      g_fills        = 0;
string   g_last_event   = "Waiting for first market tick...";
bool     g_shield_paused = false;
bool     g_parachute_on = false;
long     g_login        = 0;
double   g_start_bal    = 0.0;
double   g_hwm          = 0.0;
double   g_hwm_saved    = 0.0;
double   g_hour_hi[24];
long     g_hour_id[24];
datetime g_prop_log_t   = 0;
double   g_c0           = 0.0;
double   g_ret6         = 0.0;
double   g_ret12        = 0.0;
double   g_rng12        = 0.02;
double   g_sma50        = 0.0;
double   g_sma100       = 0.0;
double   g_sma200       = 0.0;
double   g_first_c0     = 0.0;
bool     g_overdrive_latched = false;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   bool runs[9];
   runs[0] = InpRun1; runs[1] = InpRun2; runs[2] = InpRun3; runs[3] = InpRun4;
   runs[4] = InpRun5; runs[5] = InpRun6; runs[6] = InpRun7; runs[7] = InpRun8; runs[8] = InpRun9;
   for(int m = 0; m < N_MOD; m++)
   {
      g_run[m]        = runs[m];
      g_last_check[m] = 0;
      MOD_OFF_B[m]    = MOD_OFF_B_V1[m] * InpScaleMult;
      MOD_OFF_S[m]    = MOD_OFF_S_V1[m] * InpScaleMult;
      MOD_TP[m]       = MOD_TP_V1[m] * InpScaleMult;
      MOD_BE_AT[m]    = MOD_BE_AT_V1[m] * InpScaleMult;
      MOD_BE_LK[m]    = MOD_BE_LK_V1[m] * InpScaleMult;
      for(int s = 0; s < 2; s++) { g_trig[m][s] = 0; g_refill[m][s] = 0; g_prev_lvl[m][s] = 0.0; g_filled_lvl[m][s] = 0.0; }
   }

   g_trade.SetDeviationInPoints(100);
   g_filling = DetectFilling();
   ArrayResize(g_seen, 0);
   g_last_fill_t = TimeCurrent();
   g_shield_paused = false;
   g_first_c0 = 0.0;
   g_overdrive_latched = false;
   PropInit();

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double testMargin = 0.0;
   OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 0.01, ask > 0.0 ? ask : 70000.0, testMargin);
   double testProfit = 0.0;
   OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 0.01, 70000.0, 69000.0, testProfit);

   string mods = "";
   for(int m = 0; m < N_MOD; m++) if(g_run[m]) mods += "S" + IntegerToString(MOD_ID[m]) + " ";
   PrintFormat("--> [INIT] BTCUSD Chrysalis v2.00 on %s | Modules: %s| SL: %.2f%% | 0.01 Lot Margin: $%.2f | $1000 Move on 0.01 Lot: $%.2f | VolLimit: %.1f",
               _Symbol, mods, InpStopPct, testMargin, testProfit, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT));

   if(!MQLInfoInteger(MQL_TESTER))
   {
      for(int m = 0; m < N_MOD; m++)
         if(g_run[m])
            for(int s = 0; s < 2; s++)
               g_prev_lvl[m][s] = FindLevel(m, s == 0);
      if(InpShowHUD) UpdateHUD();
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpExportH1CSV && MQLInfoInteger(MQL_TESTER))
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      int got = CopyRates(_Symbol, PERIOD_H1, D'2024.01.01 00:00', TimeCurrent(), rates);
      int fh = FileOpen("btcusd_h1.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(fh != INVALID_HANDLE)
      {
         FileWrite(fh, "time", "open", "high", "low", "close", "tick_volume", "spread");
         for(int i = 0; i < got; i++)
            FileWrite(fh, TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES),
                      DoubleToString(rates[i].open, 2), DoubleToString(rates[i].high, 2),
                      DoubleToString(rates[i].low, 2), DoubleToString(rates[i].close, 2),
                      IntegerToString(rates[i].tick_volume), IntegerToString(rates[i].spread));
         FileClose(fh);
         PrintFormat("--> [EXPORT] Wrote %d H1 bars to Common\\Files\\btcusd_h1.csv", got);
      }
   }
   PropSave();
   Comment("");
}

//+------------------------------------------------------------------+
//| Main loop                                                        |
//+------------------------------------------------------------------+
void OnTick()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_hwm = MathMax(g_hwm, MathMax(bal, eq));
   double dd_pct = (g_hwm > 0.0) ? (g_hwm - bal) / g_hwm * 100.0 : 0.0;
   if(InpUseParachute && !InpPropMode)
   {
      double paraTrig = g_overdrive_latched ? 26.0 : InpParachuteDDPct;
      if(!g_parachute_on && dd_pct >= paraTrig)
         g_parachute_on = true;
      else if(g_parachute_on && dd_pct <= paraTrig * 0.70)
         g_parachute_on = false;
   }
   else
      g_parachute_on = false;

   PropGuard();
   HandleNewPositions();

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   bool inRollover = InpRolloverShield && ((dt.hour == 23 && dt.min >= 55) || (dt.hour == 0 && dt.min <= 5));
   if(!inRollover)
      ManagePositions();
   EnforceCaps();

   bool inChopHour  = (dt.hour >= 19 || dt.hour <= 1);
   bool inMode3Hour = ((dt.hour >= 19 && dt.hour <= 22) || dt.hour == 14 || dt.hour == 15 || dt.hour == 0 || dt.hour == 1);
   bool inMode4Hour = (dt.hour == 4 || dt.hour == 21 || dt.hour == 23);
   bool inMode6Hour = !g_overdrive_latched && (dt.hour == 1 || dt.hour == 4 || dt.hour == 6 || dt.hour == 8 || dt.hour == 9 || dt.hour == 15 || dt.hour == 16 || dt.hour == 17 || dt.hour == 21 || dt.hour == 22 || dt.hour == 23);
   bool inShieldHour = (InpSkipHour11 && dt.hour == 11)
                       || (InpSessionMode == 2 && inChopHour)
                       || (InpSessionMode == 3 && inMode3Hour)
                       || (InpSessionMode == 4 && inMode4Hour)
                       || (InpSessionMode == 6 && inMode6Hour);
   bool noPlaceHour  = inShieldHour || (InpSessionMode == 1 && inChopHour) || ((InpSessionMode == 5 || (InpSessionMode == 6 && g_overdrive_latched)) && inMode4Hour);
   if(InpSkipHour11 || InpSessionMode >= 2)
   {
      if(inShieldHour)
      {
         if(!g_shield_paused)
         {
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
            g_shield_paused = true;
            g_last_event = "SHIELD ACTIVE: Paused pending stops for chop window";
         }
      }
      else if(g_shield_paused)
      {
         g_shield_paused = false;
         g_last_event = "SHIELD CLEARED: Liquidity wave open — re-arming H1 levels";
      }
   }

   datetime h1 = iTime(_Symbol, PERIOD_H1, 0);
   if(h1 != 0 && h1 != g_last_h1)
   {
      g_last_h1 = h1;
      UpdateH1RegimeCache();
      long day = (long)h1 / 86400;
      bool new_day = (day != g_cur_day);
      g_cur_day = day;
      for(int m = 0; m < N_MOD; m++)
      {
         if(!g_run[m]) continue;
         for(int s = 0; s < 2; s++)
         {
            double lvl = FindLevel(m, s == 0);
            if(new_day)
            {
               g_filled_lvl[m][s] = 0.0;
               if(g_trig[m][s] < 1) g_trig[m][s] = 1;
            }
            else if(lvl > 0.0 && MathAbs(lvl - g_prev_lvl[m][s]) > _Point / 2.0)
            {
               g_trig[m][s] = 2;
            }
            else if(g_overdrive_latched && InpRegimeGateMode > 0 && lvl > 0.0 && CountPending(m, s) == 0 && MathAbs(lvl - g_filled_lvl[m][s]) > 1.0)
            {
               if(InpRegimeGateMode == 7)
               {
                  if(MOD_GAPFILL[m] > 0 && CountCorePositions() == 0 && IsBtcStyleAligned(m, s == 0))
                     if(g_trig[m][s] < 1) g_trig[m][s] = 1;
               }
               else if(InpRegimeGateMode >= 8)
               {
                  bool is_b = (s == 0);
                  bool superTrend = (g_rng12 >= 0.0220 && (is_b ? (g_c0 > g_sma50 && g_sma50 > g_sma200 && g_ret6 > 0.0 && g_ret12 > 0.008)
                                                                : (g_c0 < g_sma50 && g_sma50 < g_sma200 && g_ret6 < 0.0 && g_ret12 < -0.008)));
                  bool allowGapRearm = (InpRegimeGateMode == 8 && MOD_GAPFILL[m] > 0 && IsBtcStyleAligned(m, is_b));
                  if(CountCorePositions() == 0 && (allowGapRearm || (MOD_GAPFILL[m] == 0 && superTrend)))
                     if(g_trig[m][s] < 1) g_trig[m][s] = 1;
               }
               else if(InpRegimeGateMode < 7 && IsBtcStyleAligned(m, s == 0))
               {
                  if(g_trig[m][s] < 1) g_trig[m][s] = 1;
               }
            }
            g_prev_lvl[m][s] = lvl;
            if((InpRegimeGateMode == 2 || InpRegimeGateMode == 4) && CountPending(m, s) > 0)
            {
               bool is_b = (s == 0);
               bool oppMom = is_b ? (g_ret6 < 0.0 && g_ret12 < 0.0) : (g_ret6 > 0.0 && g_ret12 > 0.0);
               if(oppMom || (MOD_GAPFILL[m] > 0 && !IsBtcStyleAligned(m, is_b)))
                  DeletePending(m, s);
            }
         }
      }
      for(int gm = 0; gm < 4; gm++)
      {
         if(!g_run[gm]) continue;
         for(int s = 0; s < 2; s++)
         {
            if(CountPending(gm, s) == 0) continue;
            for(int cm = 4; cm < N_MOD; cm++)
            {
               if(g_run[cm] && g_prev_lvl[gm][s] > 0.0 && g_prev_lvl[cm][s] > 0.0 && MathAbs(g_prev_lvl[gm][s] - g_prev_lvl[cm][s]) <= 10.0)
               {
                  DeletePending(gm, s);
                  break;
               }
            }
         }
      }
      int macroMods[2] = {6, 7};
      int primMods[3]  = {4, 5, 8};
      for(int mi = 0; mi < 2; mi++)
      {
         int mm = macroMods[mi];
         if(!g_run[mm]) continue;
         for(int s = 0; s < 2; s++)
         {
            if(CountPending(mm, s) == 0) continue;
            for(int pi = 0; pi < 3; pi++)
            {
               int pm = primMods[pi];
               if(g_run[pm] && g_prev_lvl[mm][s] > 0.0 && g_prev_lvl[pm][s] > 0.0 && MathAbs(g_prev_lvl[mm][s] - g_prev_lvl[pm][s]) <= 10.0)
               {
                  DeletePending(mm, s);
                  break;
               }
            }
         }
      }
   }

   bool expired[9];
   for(int m = 0; m < N_MOD; m++) expired[m] = false;
   ExpireOrders(now, expired);

   if(!noPlaceHour && !inRollover)
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
//| Bitcoin H1 Regime Cache & Multi-Strategy Alignment               |
//+------------------------------------------------------------------+
void UpdateH1RegimeCache()
{
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, PERIOD_H1, 1, 205, r);
   if(got < 200) return;
   g_c0    = r[0].close;
   if(g_first_c0 <= 0.0 && g_c0 > 0.0)
   {
      g_first_c0 = g_c0;
      g_overdrive_latched = (!InpPropMode && InpRegimeGateMode > 0 && (EffectiveStopDist(g_first_c0) * InpLotStep) < InpBalanceStep * 0.0712);
   }
   g_ret6  = (r[6].close > 0.0)  ? (r[0].close - r[6].close)  / r[6].close  : 0.0;
   g_ret12 = (r[12].close > 0.0) ? (r[0].close - r[12].close) / r[12].close : 0.0;
   double hi12 = r[0].high, lo12 = r[0].low;
   for(int i = 1; i < 12; i++)
   {
      if(r[i].high > hi12) hi12 = r[i].high;
      if(r[i].low  < lo12) lo12 = r[i].low;
   }
   g_rng12 = (g_c0 > 0.0) ? (hi12 - lo12) / g_c0 : 0.02;
   double sum = 0.0;
   for(int i = 0; i < 200; i++)
   {
      sum += r[i].close;
      if(i == 49)  g_sma50  = sum / 50.0;
      if(i == 99)  g_sma100 = sum / 100.0;
      if(i == 199) g_sma200 = sum / 200.0;
   }
}

bool IsBtcStyleAligned(const int m, const bool is_buy)
{
   if(InpRegimeGateMode <= 0 || g_c0 <= 0.0) return true;
   bool r6  = is_buy ? (g_ret6  > 0.0) : (g_ret6  < 0.0);
   bool r12 = is_buy ? (g_ret12 > 0.0) : (g_ret12 < 0.0);
   bool a50  = is_buy ? (g_c0 > g_sma50)  : (g_c0 < g_sma50);
   bool a100 = is_buy ? (g_c0 > g_sma100) : (g_c0 < g_sma100);
   bool e50_200 = is_buy ? (g_sma50 > g_sma200) : (g_sma50 < g_sma200);

   if(MOD_GAPFILL[m] > 0)
   {
      if(InpRegimeGateMode < 3 || InpRegimeGateMode >= 9) return true;
      // Active Bitcoin-Native Strategy Modules S1..S4 (High-Conviction Cascade & ETF Impulse Ladder):
      if(m == 0) // S1: 18/9 Liquidation Squeeze (high expansion + macro trend + dual momentum)
         return (g_rng12 >= 0.0185 && a50 && e50_200 && r6 && r12);
      if(m == 1) // S2: 20/10 ETF Momentum Continuation (macro trend + expansion + strong 12h impulse)
         return (g_rng12 >= 0.0165 && a50 && e50_200 && r6 && (is_buy ? g_ret12 >= 0.0055 : g_ret12 <= -0.0055));
      if(m == 2) // S3: 22/11 Liquidation Cascade Hunter (high 12h expansion + SMA100 + dual momentum)
         return (g_rng12 >= 0.0180 && a100 && r6 && r12);
      if(m == 3) // S4: 24/11 Whale Swing Breakout (high expansion + macro trend + dual momentum)
         return (g_rng12 >= 0.0180 && a50 && a100 && r6 && r12);
   }

   // Core Supernova Quintet (S5..S9)
   if(InpRegimeGateMode >= 5)
      return true; // Full unfiltered S5-S9 velocity + Active S1-S4 Bitcoin-Native Engines
   return (g_rng12 >= InpMinRng12 && r6 && r12);
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

   if(!IsBtcStyleAligned(m, is_buy)) return;

   if(MOD_GAPFILL[m] > 0)
   {
      if(InpRegimeGateMode < 3 || InpRegimeGateMode >= 7)
      {
         int reqHours = (InpRegimeGateMode == 7 || InpRegimeGateMode == 8) ? 18 : InpDroughtHours;
         int barsSinceFill = (g_last_fill_t > 0) ? iBarShift(_Symbol, PERIOD_H1, g_last_fill_t, false) : 0;
         bool inDrought = (barsSinceFill >= reqHours);
         if(!inDrought || CountCorePositions() > 0 || (CountGapFillPositions() + CountGapFillPending(is_buy ? 0 : 1)) >= InpMaxDroughtPos)
         {
            if(CountPending(m, is_buy ? 0 : 1) > 0) DeletePending(m, is_buy ? 0 : 1);
            return;
         }
      }
      else
      {
         if(CountCorePositions() >= InpMaxPositions || (CountGapFillPositions() + CountGapFillPending(is_buy ? 0 : 1)) >= InpMaxDroughtPos)
         {
            if(CountPending(m, is_buy ? 0 : 1) > 0) DeletePending(m, is_buy ? 0 : 1);
            return;
         }
      }
      for(int cm = 4; cm < N_MOD; cm++)
      {
         if(!g_run[cm]) continue;
         double coreLvl = FindLevel(cm, is_buy);
         if(coreLvl > 0.0 && MathAbs(lvl - coreLvl) <= 15.0)
         {
            if(CountPending(m, is_buy ? 0 : 1) > 0) DeletePending(m, is_buy ? 0 : 1);
            return;
         }
      }
   }
   else if(m == 6 || m == 7)
   {
      // S7 (30/14) and S8 (32/13) only arm when their macro level is distinct from primary core modules S5, S6, S9
      int checkMods[3] = {4, 5, 8};
      for(int k = 0; k < 3; k++)
      {
         int cm = checkMods[k];
         if(!g_run[cm]) continue;
         double coreLvl = FindLevel(cm, is_buy);
         if(coreLvl > 0.0 && MathAbs(lvl - coreLvl) <= 10.0)
         {
            if(CountPending(m, is_buy ? 0 : 1) > 0) DeletePending(m, is_buy ? 0 : 1);
            return;
         }
      }
   }
   if(why != 2 && CountPending(m, is_buy ? 0 : 1) > 0) return;
   if(CountPositions(m) >= MOD_MAXOPN[m]) return;
   if(MOD_GAPFILL[m] == 0 && CountCorePositions() >= InpMaxPositions) return;
   if(!InpAllowOpposite || InpPropMode)
      if(HasOpposite(is_buy, MOD_GAPFILL[m] > 0)) return;
   double entry = NormPrice(is_buy ? lvl * (1.0 - MOD_OFF_B[m]) : lvl * (1.0 + MOD_OFF_S[m]));
   if(HasPendingAt(m, is_buy, entry)) return;
   if(CountPending(m, is_buy ? 0 : 1) >= MOD_MAXPND[m]) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap = MinStopDistance();
   if(is_buy ? (entry <= ask + gap) : (entry >= bid - gap)) return;

   double slDist = EffectiveStopDist(entry);
   double sl = NormPrice(is_buy ? entry - slDist : entry + slDist);
   double tp = InpPropMode ? 0.0 : NormPrice(is_buy ? entry * (1.0 + MOD_TP[m]) : entry * (1.0 - MOD_TP[m]));
   double lots = OrderLots(is_buy, entry);
   if(lots <= 0.0) return;
   if(MOD_GAPFILL[m] > 0 && (InpRegimeGateMode < 3 || InpRegimeGateMode >= 7) && lots > 2.50)
   {
      if(CountPending(m, is_buy ? 0 : 1) > 0) DeletePending(m, is_buy ? 0 : 1);
      return;
   }
   // When order size is large (lots >= 1.50) and a new H1 swing level formed (why == 2), replace superseded pending order to save 37-lot book capacity
   if(g_overdrive_latched && why == 2 && lots >= 1.50 && CountPending(m, is_buy ? 0 : 1) > 0)
      DeletePending(m, is_buy ? 0 : 1);
   if(InpJITProximityPct > 0.0 && lots >= 0.50)
   {
      double mid = (ask + bid) * 0.5;
      if(MathAbs(entry - mid) > mid * (InpJITProximityPct / 100.0))
      {
         g_trig[m][is_buy ? 0 : 1] = 1; // keep armed in memory until price approaches within JIT proximity
         return;
      }
   }

   // Respect Pepperstone 37.0-lot SYMBOL_VOLUME_LIMIT by freeing distant pending stops only if new order is closer to market
   double vol_limit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(vol_limit > 0.0 && CurrentBookVolume() + lots > vol_limit - 0.01)
   {
      FreeDistantPendingVolume(lots, entry, ask, bid, vol_limit);
      double rem_vol = vol_limit - 0.01 - CurrentBookVolume();
      double vstep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double vmin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(vstep <= 0.0) vstep = 0.01;
      if(vmin <= 0.0) vmin = vstep;
      int vdigits = (int)MathMax(0.0, MathCeil(-MathLog10(vstep)));
      double clamped = NormalizeDouble(MathFloor(rem_vol / vstep) * vstep, vdigits);
      if(clamped < vmin) return;
      lots = MathMin(lots, clamped);
   }

   if(InpPropMode)
   {
      lots = FitToRoom(is_buy, lots, entry, sl);
      if(lots <= 0.0) { g_last_event = StringFormat("SKIP S%d %s: no room above prop floors", MOD_ID[m], is_buy ? "BUY" : "SELL"); return; }
   }
   ENUM_ORDER_TYPE_TIME tmode = ORDER_TIME_GTC;
   datetime expiry = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_GTC) == 0)
   {
      tmode  = ORDER_TIME_SPECIFIED;
      expiry = (datetime)((long)TimeCurrent() + (long)MOD_EXP_H[m] * 3600 + 600);
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber + MOD_ID[m]);
   g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   string cmt = StringFormat("BTC S%d", MOD_ID[m]);
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
   }
}

void FreeDistantPendingVolume(const double neededLots, const double newEntryPrice, const double ask, const double bid, const double volLimit)
{
   double mid = (ask + bid) * 0.5;
   double newDist = MathAbs(newEntryPrice - mid);
   while(CurrentBookVolume() + neededLots > volLimit - 0.01)
   {
      ulong worstTicket = 0;
      double worstDist = -1.0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong t = OrderGetTicket(i);
         if(t == 0 || OrderModule() < 0) continue;
         double dist = MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - mid);
         if(dist > worstDist) { worstDist = dist; worstTicket = t; }
      }
      if(worstTicket == 0 || worstDist <= newDist + 5.0 || !g_trade.OrderDelete(worstTicket)) break;
   }
}

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
   int totalPos = PositionsTotal();
   if(totalPos == 0 && ArraySize(g_seen) == 0) return;
   for(int i = totalPos - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      int m = PositionModule();
      if(m < 0 || Seen(ticket)) continue;
      int n = ArraySize(g_seen);
      ArrayResize(g_seen, n + 1, 64);
      g_seen[n] = ticket;
      bool is_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      int sideIdx = is_buy ? 0 : 1;
      g_refill[m][sideIdx] = (datetime)((long)posTime + REFILL_SEC);
      if(g_prev_lvl[m][sideIdx] > 0.0)
         g_filled_lvl[m][sideIdx] = g_prev_lvl[m][sideIdx];
      g_last_fill_t = posTime;
      g_fills++;
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double slDist = EffectiveStopDist(open);
      double sl   = NormPrice(is_buy ? open - slDist : open + slDist);
      double tp   = InpPropMode ? 0.0 : NormPrice(is_buy ? open * (1.0 + MOD_TP[m]) : open * (1.0 - MOD_TP[m]));
      double curSl = PositionGetDouble(POSITION_SL);
      double curTp = PositionGetDouble(POSITION_TP);
      if(curSl <= 0.0 || (!InpPropMode && curTp <= 0.0))
         g_trade.PositionModify(ticket, sl, tp);
      if(!InpAllowOpposite || InpPropMode)
      {
         int opp = is_buy ? 1 : 0;
         if(MOD_GAPFILL[m] > 0)
         {
            for(int gm = 0; gm < 4; gm++)
               if(CountPending(gm, opp) > 0) DeletePending(gm, opp);
         }
         else
         {
            DeletePending(-1, opp);
            if(!InpPropMode)
            {
               g_trade.SetTypeFilling(g_filling);
               for(int p = PositionsTotal() - 1; p >= 0; p--)
               {
                  ulong pt = PositionGetTicket(p);
                  if(pt == 0) continue;
                  int pm = PositionModule();
                  if(pm < 0 || pm >= 4) continue;
                  bool p_buy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
                  if(p_buy != is_buy) g_trade.PositionClose(pt);
               }
            }
         }
      }
      if(MOD_GAPFILL[m] == 0 && (InpRegimeGateMode < 3 || InpRegimeGateMode >= 7))
      {
         for(int gm = 0; gm < 4; gm++)
            if(CountPending(gm, -1) > 0) DeletePending(gm, -1);
      }
   }
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

void ManagePositions()
{
   int totalPos = PositionsTotal();
   if(totalPos == 0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double gap = MinStopDistance();
   for(int i = totalPos - 1; i >= 0; i--)
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

      if(at_be)
      {
         if(InpStage2Ratchet)
         {
            double lockPct = 0.0;
            if(fav >= open * (MOD_TP[m] * 0.68))
               lockPct = MOD_TP[m] * 0.40;
            else if(fav >= open * (MOD_TP[m] * 0.42))
               lockPct = MOD_TP[m] * 0.20;
            if(lockPct > 0.0)
            {
               double lockPx = NormPrice(is_buy ? open * (1.0 + lockPct) : open * (1.0 - lockPct));
               bool   better = is_buy ? (lockPx > sl + _Point) : (lockPx < sl - _Point);
               if(better && (is_buy ? (bid - lockPx > gap) : (lockPx - ask > gap)))
                  g_trade.PositionModify(ticket, lockPx, tp);
            }
         }
         continue;
      }

      int    sideIdx      = is_buy ? 0 : 1;
      double fLvl         = (g_filled_lvl[m][sideIdx] > 0.0) ? g_filled_lvl[m][sideIdx] : g_prev_lvl[m][sideIdx];
      double intendedOpen = (fLvl > 0.0) ? NormPrice(is_buy ? fLvl * (1.0 - MOD_OFF_B[m]) : fLvl * (1.0 + MOD_OFF_S[m])) : open;
      double slip         = is_buy ? MathMax(0.0, open - intendedOpen) : MathMax(0.0, intendedOpen - open);
      double effFav       = g_overdrive_latched ? fav : (fav + MathMin(slip, open * 0.00095));
      if(effFav < open * MOD_BE_AT[m]) continue;
      double be = NormPrice(is_buy ? open * (1.0 + MOD_BE_LK[m]) : open * (1.0 - MOD_BE_LK[m]));
      if(is_buy ? (bid - be <= gap) : (be - ask <= gap)) continue;
      g_trade.PositionModify(ticket, be, tp);
   }
}

void EnforceCaps()
{
   if(PositionsTotal() == 0 || OrdersTotal() == 0) return;
   if(CountGapFillPositions() >= InpMaxDroughtPos)
   {
      for(int gm = 0; gm < 4; gm++)
         if(g_run[gm]) DeletePending(gm, -1);
   }
   if(CountCorePositions() >= InpMaxPositions)
   {
      DeletePending(-1, -1);
      return;
   }
   for(int m = 0; m < N_MOD; m++)
      if(g_run[m] && CountPositions(m) >= MOD_MAXOPN[m]) DeletePending(m, -1);
}

//+------------------------------------------------------------------+
//| Prop firm mode & HWM Persistence                                 |
//+------------------------------------------------------------------+
string GvName(const string key)
{
   return "BTCCHR_" + IntegerToString(g_login) + "_" + _Symbol + "_" + IntegerToString(InpMagicNumber) + "_" + key;
}

void ScanHistory(double &first, double &peak, double &hi24)
{
   first = 0.0; peak = 0.0; hi24 = 0.0;
   if(!HistorySelect(0, TimeCurrent() + 60)) return;
   datetime cut = TimeCurrent() - 86400;
   double running = 0.0;
   datetime last_in = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      datetime dt = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      double amount = HistoryDealGetDouble(deal, DEAL_PROFIT);
      if(first <= 0.0 && (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BALANCE && amount > 0.0)
      {
         first = amount;
         if(last_in == 0) last_in = dt;
      }
      if(HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
         ModuleOfMagic(HistoryDealGetInteger(deal, DEAL_MAGIC)) >= 0 &&
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         last_in = dt;
      }
      bool in_window = (dt >= cut);
      if(in_window) hi24 = MathMax(hi24, running);
      running += amount + HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_SWAP);
      peak = MathMax(peak, running);
      if(in_window) hi24 = MathMax(hi24, running);
   }
   if(MQLInfoInteger(MQL_TESTER) == 0 && last_in > 0)
      g_last_fill_t = last_in;
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
   if(login > 0 && login != g_login) { PropSave(); PropInit(); }
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_hwm = MathMax(g_hwm, eq);
   if(g_hwm > g_hwm_saved + 1.0) PropSave();
   UpdateDayHigh(MathMax(bal, eq));
   double guard = MathMax(DayFloor(), LossFloor());
   if(eq > guard || (CountPositions(-1) == 0 && CountPending(-1, -1) == 0)) return;

   bool can_trade = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) && (MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
   if(can_trade)
   {
      DeletePending(-1, -1);
      g_trade.SetTypeFilling(g_filling);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionModule() < 0) continue;
         if((long)TimeCurrent() - (long)PositionGetInteger(POSITION_TIME) < MIN_HOLD_SEC) continue;
         g_trade.PositionClose(ticket);
      }
   }
   g_last_event = StringFormat("PROP GUARD: equity %.2f at floor %.2f", eq, guard);
}

double EffectiveStopDist(const double price)
{
   if(InpStopPct > 0.0 && price > 0.0)
      return NormPrice(price * (InpStopPct / 100.0));
   return InpStopDist;
}

double StopCash(const bool is_buy, const double lots, const double open, const double stop)
{
   double profit = 0.0;
   double csize  = MathMax(1.0, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
   double floorLoss = MathAbs(open - stop) * lots * csize;
   if(OrderCalcProfit(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, open, stop, profit) && profit < 0.0)
      return MathMax(floorLoss, -profit);
   return floorLoss;
}

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
      if(sl <= 0.0) sl = is_buy ? open - EffectiveStopDist(open) : open + EffectiveStopDist(open);
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

double EffectiveBalanceStep(const double price = 0.0)
{
   if(g_parachute_on && InpUseParachute && !InpPropMode)
      return InpBalanceStep * MathMax(1.0, InpParachuteMult);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd_pct = (g_hwm > 0.0) ? (g_hwm - bal) / g_hwm * 100.0 : 0.0;
   double refPx = (price > 0.0) ? price : g_c0;
   if(InpRegimeGateMode == 10 && refPx >= 88000.0)
      return InpBalanceStep;
   if(InpBoostMult > 0.0 && InpBoostMult < 1.0 && !InpPropMode && bal >= 550.0 && bal <= InpBoostCapBal && dd_pct <= 10.0)
      return InpBalanceStep * InpBoostMult;
   return InpBalanceStep;
}

double OrderLots(const bool is_buy, const double price)
{
   double lots = InpFixLot;
   double base = (InpPropMode && InpSizeFromStart && g_start_bal > 0.0) ? g_start_bal : AccountInfoDouble(ACCOUNT_BALANCE);
   double refPx = (price > 0.0) ? price : g_c0;
   if(lots <= 0.0)
   {
      if(InpLotStep <= 0.0 || InpBalanceStep <= 0.0) return 0.0;
      double eff_step = EffectiveBalanceStep(refPx);
      double blocks   = (base < 360.0) ? 1.0 : MathMax(1.0, MathRound(base / eff_step));
      lots = blocks * InpLotStep;
   }
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   if(min_lot <= 0.0) min_lot = step;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step)));
   double dd_pct = (g_hwm > 0.0) ? (g_hwm - base) / g_hwm * 100.0 : 0.0;
   if(!InpPropMode && InpMaxSlotRiskPct > 0.0 && refPx > 0.0 && base > 0.0)
   {
      double slDist = EffectiveStopDist(refPx);
      double csize  = MathMax(1.0, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
      double effRiskPct = g_overdrive_latched ? ((InpRegimeGateMode == 11 && base >= 440.0 && dd_pct <= 12.0) ? (InpMaxSlotRiskPct * 1.15) : InpMaxSlotRiskPct)
                                              : 9.50;
      double maxRiskUSD = base * (effRiskPct / 100.0);
      if(slDist > 0.0 && lots * slDist * csize > maxRiskUSD)
         lots = NormalizeDouble(MathFloor((maxRiskUSD / (slDist * csize)) / step) * step, digits);
   }
   lots = NormalizeDouble(MathRound(lots / step) * step, digits);
   lots = MathMax(lots, min_lot);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(max_lot > 0.0) lots = MathMin(lots, max_lot);
   if(InpMaxOrderLot > 0.0) lots = MathMin(lots, InpMaxOrderLot);
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

int CountCorePositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0) continue;
      int pm = PositionModule();
      if(pm >= 4 && pm < N_MOD) n++;
   }
   return n;
}

int CountGapFillPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0) continue;
      int pm = PositionModule();
      if(pm >= 0 && pm < 4) n++;
   }
   return n;
}

int CountGapFillPending(const int s)
{
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderGetTicket(i) == 0) continue;
      int om = OrderModule();
      if(om < 0 || om >= 4) continue;
      int os = (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) ? 0 : 1;
      if(s < 0 || os == s) n++;
   }
   return n;
}

double CurrentBookVolume()
{
   double vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
         vol += PositionGetDouble(POSITION_VOLUME);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol)
         vol += OrderGetDouble(ORDER_VOLUME_CURRENT);
   return vol;
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

bool HasOpposite(const bool is_buy, const bool checkAllModules)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int pm = ModuleOfMagic(PositionGetInteger(POSITION_MAGIC));
      if(!InpPropMode && pm < 0) continue;
      if(!InpPropMode && !checkAllModules && pm >= 0 && pm < 4) continue;
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
//| Satoshi Supernova On-Chart HUD                                   |
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
   double blocks   = (bal < 360.0) ? 1.0 : MathMax(1.0, MathRound(bal / eff_step));
   double next_bal = (bal < 360.0) ? 360.0 : (blocks + 0.5) * eff_step;
   double to_next  = MathMax(0.0, next_bal - bal);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool inVacHour = (InpSessionMode == 5 && (dt.hour == 4 || dt.hour == 21 || dt.hour == 23));
   string shield_state = (InpSkipHour11 && dt.hour == 11)
                         ? "PAUSED (HOUR 11 SHIELD)"
                         : (inVacHour
                            ? "HOLDING BOOK (LIQUIDITY VACUUM FILTER H04/H21/H23)"
                            : "24/7 ARMED & HUNTING 9-MODULE BTC H1 BREAKOUTS");
   string para_state   = g_parachute_on
                         ? StringFormat("ENGAGED (Step $%.0f -> $%.0f)", InpBalanceStep, eff_step)
                         : "NOMINAL (FULL BOOST)";

   string hud = "";
   hud += "====================================================================\n";
   hud += "  BTCUSD CHRYSALIS v2.00 — 24/7 SATOSHI SUPERNOVA ENGINE\n";
   hud += "====================================================================\n";
   hud += StringFormat("  [MOONSHOT]   Start: $%.2f  |  Balance: $%.2f  |  Equity: $%.2f\n", start, bal, eq);
   hud += StringFormat("  [GROWTH]     Multiplier: %.2fx (%+.1f%%)  |  Peak HWM: $%.2f (DD: %.2f%%)\n", mult, roi_pct, g_hwm, MathMax(0.0, dd_pct));
   hud += StringFormat("  [LOT TIER]   Active Size: %.2f BTC/order   |  Next Step-Up (+%.2f): $%.2f away\n", cur_lots, InpLotStep, to_next);
   hud += StringFormat("  [PARACHUTE]  %s  |  Book Vol: %.2f / 37.0 BTC\n", para_state, CurrentBookVolume());
   hud += StringFormat("  [SHIELD]     Server %02d:%02d  |  %s\n", dt.hour, dt.min, shield_state);
   hud += "--------------------------------------------------------------------\n";
   hud += "  MODULE   SWING(L/R)   TARGET     OPEN   PEND(B/S)   H1 BUY / SELL LEVELS\n";
   for(int m = 0; m < N_MOD; m++)
   {
      if(!g_run[m]) continue;
      hud += StringFormat("  BTC S%d     %2d / %2d     %5.2f%%      %d      %d / %d     %s / %s\n",
                          MOD_ID[m], MOD_LEFT[m], MOD_RIGHT[m], MOD_TP[m] * 100.0,
                          CountPositions(m), CountPending(m, 0), CountPending(m, 1),
                          g_prev_lvl[m][0] > 0.0 ? Px(g_prev_lvl[m][0]) : "-----.--",
                          g_prev_lvl[m][1] > 0.0 ? Px(g_prev_lvl[m][1]) : "-----.--");
   }
   hud += "--------------------------------------------------------------------\n";
   hud += StringFormat("  [ACTIVITY]   Orders Armed: %d  |  Breakout Fills: %d\n", g_placed, g_fills);
   hud += StringFormat("  [LAST EVENT] %s\n", g_last_event);
   hud += "====================================================================\n";
   Comment(hud);
}
//+------------------------------------------------------------------+
