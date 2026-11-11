//+------------------------------------------------------------------+
//|                                             XAUUSD_SevenWave.mq5 |
//|  SevenWave v1.33: geometric 7-EMA ribbon (10/16/26/41/66/105/168) |
//|  trend hierarchy (H1/H4/D1)  x  liquidity-pool breakouts on       |
//|  M15/H1/H2  x  AI quality score (ONNX, logged)  x  risk engine    |
//|  with up to 2 (Prop) / 3 (Growth) concurrent positions and the    |
//|  Prop consistency lock.                                           |
//|  v1.20: whale pyramid in House Money Growth mode - a trade that   |
//|  reaches +1.5R gets ONE add of the same size, stop at the first   |
//|  entry, same 3R target (Prop mode never pyramids).                |
//|  v1.30: whale extension - that trade and its add then aim for 5R  |
//|  and may run 72h instead of 24h (Growth only).                    |
//|  v1.31: whales trail 3 ATR(H1) once secured at break-even, and    |
//|  Prop gets the same whale handling (secure + extend, never adds). |
//|  v1.32: optional news-day filter (InpSkipNewsDays, default off):   |
//|  no new first positions on key US release days (NFP, CPI, PCE,    |
//|  GDP, Retail Sales, Fed decision).                                |
//|  v1.33: the AI no longer vetoes. Its model was trained on        |
//|  2017-2023, and on unseen 2024-26 the vetoed setups did better   |
//|  than the traded ones (+0.43R vs +0.29R), so every setup trades.  |
//|  Growth now bets at most 25% of the trailing room (Kelly-safe):   |
//|  at 50% the honest 2018-23 account froze at its 30% floor.        |
//|                                                                    |
//|  Attach to an XAUUSD chart (any timeframe).  No timezone, DST or  |
//|  symbol settings: the broker clock, contract specs, filling mode, |
//|  tick size and stop levels are detected automatically.             |
//+------------------------------------------------------------------+
#property copyright   "SevenWave"
#property version     "1.33"
#property description "XAUUSD SevenWave v1.33 - geometric 7-EMA hierarchy x liquidity-pool breakouts x optional key-news-day filter x portfolio risk engine x whale handling (AI score logged, no veto)"

#include <SevenWave\Market.mqh>
#include <SevenWave\Streams.mqh>
#include <SevenWave\AiRater.mqh>
#include <SevenWave\RiskEngine.mqh>
#include <SevenWave\Trader.mqh>
#include <SevenWave\News.mqh>

#define SW_PYR_AT_R  1.5   // add when the probe first reaches +1.5R (research: +0.382R vs +0.258R per attempt, 10/10 years)
#define SW_PYR_MAX_R 2.0   // first seen beyond +2.0R (gap / restart): no add
#define SW_WHALE_TP_R 5.0  // v1.30: a trade that reached +1.5R (and its add) aims for 5R ...
#define SW_WHALE_MIN 4320  // ... and may run 72h (research: Growth $10k 1% 2018-23 +248% -> +457%, 2024-26 +928% -> +1271%)
#define SW_WHALE_TRAIL_K 3.0 // v1.31: whales trail 3.0 x ATR(H1) instead of 2.0 once they are secured at break-even
#define SW_PROP_WHALE  true  // v1.31: Prop also secures + extends whales, never adds (MT5 $50k: +44%->+51% 2018-23, +31%->+50% 2024-26)
#define SW_AI_VETO     false // v1.33: no veto. The ONNX rater saw 2017-2023; on unseen 2024-26 its vetoed setups beat the traded ones

input ENUM_SW_MODE InpMode    = SW_PROP_FIRM;  // Mode
input double       InpRiskPct = 0.0;           // Risk per trade % (0 = auto: Prop 0.5 / Growth 1.0)
input double       InpDailyDD = 0.0;           // Daily drawdown limit % (0 = auto: Prop 3 / Growth 10)
input double       InpMaxDD   = 0.0;           // Trailing max drawdown limit % (0 = auto: Prop 6 / Growth 30)
input long         InpMagic   = 7072026;       // Magic number
input bool         InpSkipNewsDays = false;    // Skip new trades on key US news days (smoother, lower DD; gave up 2024-26 return)

CSwMarket  g_mk;
CSwStreams g_st;
CSwAiRater g_ai;
CSwRisk    g_risk;
CSwTrader  g_tr;
CSwNews    g_news;
int        g_log = INVALID_HANDLE;
int        g_tlog = INVALID_HANDLE;
bool       g_tester = false;
bool       g_pyramid = false;
bool       g_whale = false;      // whale extension active (Growth always; Prop when SW_PROP_WHALE)
int        g_maxPos = 2;
datetime   g_lastHud = 0, g_lastDecisionMin = 0;
string     g_lastEvent = "-";
int        g_trades = 0, g_vetoes = 0, g_busy = 0, g_adds = 0, g_addSkips = 0, g_newsSkips = 0;

SwMgmt TrendTailMgmt(void)
  {
   SwMgmt m;   // research "growth" management: no partial, ratchet 2.0 ATR(H1) after +1R, target 3R, 24h
   m.slK = 1.5; m.tp1R = 0.5; m.tp1Frac = 0.0; m.beR = 0.05; m.actR = 1.0; m.trailK = 2.0; m.tp2R = 3.0; m.maxMin = 1440;
   return m;
  }

int OnInit()
  {
   g_tester = (bool)MQLInfoInteger(MQL_TESTER);
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("SevenWave WARNING: designed for spot gold (XAUUSD); attached to ", _Symbol);
   PrintFormat("SevenWave v1.33 | %s contract=%.2f digits=%d tick=%.5f vmin=%.2f step=%.2f stops=%d fill=%d | mode=%s",
               _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE), (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
               SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE), EnumToString(InpMode));
   g_mk.Init(_Symbol);
   if(!g_ai.Init())
      Print("SevenWave: AI rater unavailable - trading on rules only");
   g_risk.Init(_Symbol, (int)InpMode, InpRiskPct, InpDailyDD, InpMaxDD, InpMagic);
   g_maxPos = (InpMode == SW_PROP_FIRM) ? 2 : 3;
   g_pyramid = (InpMode == SW_HOUSE_MONEY_GROWTH);
   for(int s = 0; s < SW_NSTREAMS; s++) g_tr.names[s] = g_st.names[s];   // needed to re-adopt tagged positions after a restart
   g_whale = g_pyramid || SW_PROP_WHALE;
   g_tr.whaleMaxMin = g_whale ? SW_WHALE_MIN : 0;                         // set before Init: re-adopted whales keep 72h
   g_tr.whaleTrailMult = g_whale ? SW_WHALE_TRAIL_K / 2.0 : 1.0;          // ... and their wide trail (2.0 = TrendTailMgmt trailK)
   g_tr.Init(_Symbol, InpMagic, TrendTailMgmt());
   PrintFormat("SevenWave risk: %.2f%%/trade, daily %.1f%%, trailing max %.1f%%, %d slots, consistency lock %.1f%%, pyramid %s | AI %s thr %.4f, veto %s",
               g_risk.riskPct, g_risk.dailyPct, g_risk.maxPct, g_maxPos, g_risk.LockPct(),
               g_pyramid ? StringFormat("ON (+%.1fR, stop at first entry, whales aim %.0fR / %dh)", SW_PYR_AT_R, SW_WHALE_TP_R, SW_WHALE_MIN / 60) : "off",
               SW_AI_TRAIN_STAMP, SW_AI_THRESHOLD, SW_AI_VETO ? "ON" : "off (score logged only)");
   if(g_tester)
     {
      g_log = FileOpen("sevenwave_events.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_log != INVALID_HANDLE)
         FileWrite(g_log, "srv", "utc", "stream", "dir", "trigger", "level", "px", "age", "p", "decision", "lots",
                   "f0", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15", "f16");
      g_tlog = FileOpen("sevenwave_trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_tlog != INVALID_HANDLE)
        {
         FileWrite(g_tlog, "ticket", "stream", "dir", "entry", "exit", "lots", "R", "net", "outs", "win_outs", "balance");
         g_tr.logH = g_tlog;
        }
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_log != INVALID_HANDLE)
      FileClose(g_log);
   g_log = INVALID_HANDLE;
   if(g_tlog != INVALID_HANDLE)
      FileClose(g_tlog);
   g_tlog = INVALID_HANDLE;
   g_tr.logH = INVALID_HANDLE;
   Comment("");
   PrintFormat("SevenWave stats: trades=%d vetoed=%d skipped-busy=%d news-day=%d pyramid-adds=%d pyramid-skipped=%d | %s",
               g_trades, g_vetoes, g_busy, g_newsSkips, g_adds, g_addSkips, g_mk.status);
  }

void LogEvent(int s, int d, double trig, double lvl, double px, int age, double p, string dec, double lots, string tag = "")
  {
   if(g_log == INVALID_HANDLE)
      return;
   datetime now = TimeCurrent();
   string nm = (tag != "") ? tag : ((s >= 0 && s < SW_NSTREAMS) ? g_st.names[s] : "?");
   FileWrite(g_log, TimeToString(now, TIME_DATE | TIME_SECONDS), TimeToString(g_mk.clock.ToUtc(now), TIME_DATE | TIME_SECONDS),
             nm, d, DoubleToString(trig, 2), DoubleToString(lvl, 2), DoubleToString(px, 2), age,
             DoubleToString(p, 5), dec, DoubleToString(lots, 2), g_ai.FeatureCsv());
  }

//--- v1.20 whale pyramid (Growth only): one add per probe at its first touch of +1.5R
void Pyramid(void)
  {
   if(!g_whale)
      return;
   int i = g_tr.DueForAdd(SW_PYR_AT_R, SW_PYR_MAX_R);
   if(i < 0)
      return;
   int d = g_tr.pos[i].dir, s = g_tr.pos[i].stream;
   double entry = g_tr.pos[i].entry, R = g_tr.pos[i].R, trailD = g_tr.pos[i].trailDist;
   double px = (d > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tpAbs = entry + d * SW_WHALE_TP_R * R;
   string nm = ((s >= 0 && s < SW_NSTREAMS) ? g_st.names[s] : "?") + "+";
   if(d * (tpAbs - px) <= 0.0 || d * (px - entry) <= 0.0)
      return;
   g_tr.ExtendWhale(i, SW_WHALE_TP_R);                             // v1.30: the probe now aims for 5R / 72h
   g_tr.SecureProbe(i);                                            // the probe now risks nothing
   trailD *= SW_WHALE_TRAIL_K / g_tr.mg.trailK;                    // whales get room to breathe (probe and add)
   g_tr.pos[i].trailDist = trailD;
   if(!g_pyramid)
      return;                                                      // Prop: secured + extended, never an add
   double w = (s >= 0 && s < SW_NSTREAMS) ? g_st.weights[s] : 1.0;
   string why = "";
   double lots = g_risk.Lots(d, px, entry, w * SW_PYR_AT_R, why);  // 1.5x the risk over a 1.5R stop = the probe's size
   if(lots > 0.0 && g_tr.Open(d, lots, d * (px - entry), trailD, s, -1.0, nm, entry, tpAbs, true, SW_WHALE_MIN))
     {
      g_adds++;
      g_lastEvent = StringFormat("%s %s %s ADD %.2f lots (+%.1fR, stop at %.2f)", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                                 nm, d > 0 ? "BUY" : "SELL", lots, SW_PYR_AT_R, entry);
      LogEvent(s, d, entry + d * SW_PYR_AT_R * R, entry, px, 0, -1.0, "pyramid", lots, nm);
     }
   else
     {
      g_addSkips++;
      LogEvent(s, d, entry + d * SW_PYR_AT_R * R, entry, px, 0, -1.0, "pyramid-risk:" + why, 0.0, nm);
     }
  }

void OnTick()
  {
   g_mk.Update();
   if(g_risk.OnTick())
      g_tr.CloseAll(g_risk.haltWhy);
   g_tr.ManageAll();
   Pyramid();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;
   //--- (re)arm the streams whose structure bar just closed
   if(g_mk.newH1)  { g_st.Arm(g_mk, 0, bid); g_st.Arm(g_mk, 2, bid); }
   if(g_mk.newH2)  g_st.Arm(g_mk, 1, bid);
   if(g_mk.newM15) g_st.Arm(g_mk, 3, bid);

   int s = g_st.Hit(bid, ask);
   if(s >= 0)
     {
      int d = g_st.trg[s].dir;
      double trig = g_st.trg[s].price, lvl = g_st.trg[s].level;
      int age = g_st.trg[s].barIdx - g_st.trg[s].pivot;
      datetime nowMin = TimeCurrent() - (TimeCurrent() % 60);
      bool sameMinute = (nowMin == g_lastDecisionMin);
      //--- every stream touched on this tick is consumed (one decision per minute, like the research de-dup)
      for(int q = 0; q < SW_NSTREAMS; q++)
         if(g_st.IsHit(q, bid, ask))
            g_st.MarkUsed(q);
      double px = (d > 0) ? ask : bid;
      double p = -1.0;
      if(g_ai.Build(g_mk, s, d, age, px, TimeCurrent()))
         p = g_ai.Score();
      if(sameMinute)
         LogEvent(s, d, trig, lvl, px, age, p, "dup-minute", 0.0);
      else
        {
         g_lastDecisionMin = nowMin;
         if(!g_mk.ready)
            LogEvent(s, d, trig, lvl, px, age, p, "warmup", 0.0);
         else if(InpSkipNewsDays && g_news.IsKeyDay(g_mk.clock.ToUtc(TimeCurrent()), TimeCurrent()))
           {
            g_newsSkips++;                                         // v1.32: no new first positions on key US release days
            LogEvent(s, d, trig, lvl, px, age, p, "news-day", 0.0);
           }
         else if(g_tr.Probes() >= g_maxPos)
           {
            g_busy++;
            LogEvent(s, d, trig, lvl, px, age, p, "busy", 0.0);
           }
         else if(SW_AI_VETO && p >= 0.0 && p < SW_AI_THRESHOLD)
           {
            g_vetoes++;
            g_lastEvent = StringFormat("%s %s %s p=%.3f VETO", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                                       g_st.names[s], d > 0 ? "BUY" : "SELL", p);
            LogEvent(s, d, trig, lvl, px, age, p, "veto", 0.0);
           }
         else
           {
            int k1 = g_mk.h1.LastClosedAt(TimeCurrent());
            double a1 = (k1 >= 0) ? g_mk.h1.atr[k1] : 0.0;
            double R = g_tr.mg.slK * a1, trailD = g_tr.mg.trailK * a1;
            string why = "";
            double lots = (R > 0.0) ? g_risk.Lots(d, px, px - d * R, g_st.weights[s], why) : 0.0;
            if(lots > 0.0 && g_tr.Open(d, lots, R, trailD, s, p, g_st.names[s]))
              {
               g_trades++;
               g_lastEvent = StringFormat("%s %s %s %.2f lots p=%.3f", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                                          g_st.names[s], d > 0 ? "BUY" : "SELL", lots, p);
               LogEvent(s, d, trig, lvl, px, age, p, "trade", lots);
              }
            else
               LogEvent(s, d, trig, lvl, px, age, p, "risk:" + why, 0.0);
           }
        }
     }
   //--- HUD (live only, once per second)
   if(!g_tester && TimeLocal() != g_lastHud)
     {
      g_lastHud = TimeLocal();
      string mode = (InpMode == SW_PROP_FIRM) ? "PROP FIRM" : "HOUSE MONEY GROWTH (whale pyramid on)";
      string armed = "";
      for(int q = 0; q < SW_NSTREAMS; q++)
         if(g_st.trg[q].armed)
            armed += StringFormat(" %s:%s@%.2f", g_st.names[q], g_st.trg[q].dir > 0 ? "BUY" : "SELL", g_st.trg[q].price);
      int k4 = g_mk.h4.n - 1, kd = g_mk.d1.n - 1, k1 = g_mk.h1.n - 1;
      int adds = g_tr.Adds();
      Comment(StringFormat("SevenWave v1.33 | %s | clock %s\n"
                           "Ribbon stacks  H1:%+d  H4:%+d  D1:%+d   %s   positions %d/%d%s\n"
                           "Armed:%s\n"
                           "Last: %s\n"
                           "Today %+.2f%% (lock %.1f%%)   Drawdown %.2f%% / %.1f%%   %s",
                           mode, g_mk.clock.Describe(),
                           k1 >= 0 ? g_mk.h1.stackd[k1] : 0, k4 >= 0 ? g_mk.h4.stackd[k4] : 0, kd >= 0 ? g_mk.d1.stackd[kd] : 0,
                           g_mk.ready ? "ready" : "warming up", g_tr.np - adds, g_maxPos,
                           adds > 0 ? StringFormat(" + %d add%s", adds, adds > 1 ? "s" : "") : "",
                           armed == "" ? " none" : armed, g_lastEvent,
                           g_risk.DayPnlPct(), g_risk.LockPct(), g_risk.DDPct(), g_risk.maxPct,
                           (g_risk.halted ? "HALTED: " + g_risk.haltWhy : "") +
                           ((InpSkipNewsDays && g_news.IsKeyDay(g_mk.clock.ToUtc(TimeCurrent()), TimeCurrent())) ? "   KEY US NEWS DAY: no new entries" : "")));
     }
  }
//+------------------------------------------------------------------+
