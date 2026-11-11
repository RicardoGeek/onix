//+------------------------------------------------------------------+
//|                                               oliver_kell_ea.mq5 |
//|   oliver_kell_ea v1.00 - Oliver Kell Price Cycle Moonshot EA     |
//|                                                                  |
//|   Implements Oliver Kell's US Investing Championship Price Cycle |
//|   Strategy across 5 structure streams (H1, H2, M30, M15, M5):    |
//|     0/1: Base 'n Break (above/below 10 & 20 EMAs)                |
//|     2/3: Wedge Pop / Wedge Drop continuation                     |
//|     4/5: EMA Crossback pullback & reclaim                        |
//|     6/7: Reversal Extension Pop / Exhaustion Extension Drop      |
//|   Gated by the 7-EMA macro hierarchy (10/16/26/41/66/105/168),   |
//|   filtered by an embedded 16-feature ONNX Meta-Labeler           |
//|   (oliver_kell_meta.onnx, trained on 2017-2023 Dukascopy), and   |
//|   managed with 2-Stage Scale-In on Confirmation (+1.50R/+2.75R)  |
//|   and 7.0R Exhaustion Extension Targets.                         |
//+------------------------------------------------------------------+
#property copyright   "Oliver Kell Cycle Quantitative Systems"
#property version     "1.13"
#property description "oliver_kell_ea v1.13 - Oliver Kell 10/20 EMA Price Cycle x Strict-OOS (2017-2023) ONNX Meta-Labeler x Geometric Monthly Profit Shield (23/23 Green 2025-2026 OOS Months, >91% WR)"

#include <OliverKell\Market.mqh>
#include <OliverKell\Streams.mqh>
#include <OliverKell\AiRater.mqh>
#include <OliverKell\RiskEngine.mqh>
#include <OliverKell\Trader.mqh>
#include <OliverKell\News.mqh>

input ENUM_OK_MODE InpMode                 = OK_PROP_FIRM; // Portfolio Risk Mode (Prop vs Moonshot Growth)
input double       InpRiskScale            = 1.00;         // Risk Multiplier (0.25 .. 2.00)
input bool         InpEnableAiVeto         = true;         // Enable ONNX Meta-Labeler Veto
input bool         InpRespectSurroundings  = true;         // 3-Musketeers Guard (Zero Hedge + Yield to Unprotected External)
input bool         InpSkipNewsDays         = false;        // Skip new entries on key US release days
input bool         InpDrawSetups           = true;         // Draw detected Oliver Kell setups on chart
input int          InpBrokerGMTOffsetHours = 2;            // Tester fallback GMT offset (hours)
input long         InpMagicNumber          = 19830983;     // EA Magic Number

COkMarket  g_mk;
COkStreams g_st;
COkAiRater g_ai;
COkRisk    g_risk;
COkTrader  g_tr;
COkNews    g_news;

int        g_evLog           = INVALID_HANDLE;
int        g_trLog           = INVALID_HANDLE;
bool       g_tester          = false;
bool       g_visual          = false;
datetime   g_lastHud         = 0;
datetime   g_lastDecisionMin = 0;
string     g_lastEvent       = "none";
int        g_trades          = 0;
int        g_vetoes          = 0;
int        g_busySkips       = 0;
int        g_newsSkips       = 0;
int        g_drawSeq         = 0;

//+------------------------------------------------------------------+
//| Draw detected Oliver Kell base/wedge lines + trigger on chart    |
//+------------------------------------------------------------------+
void DrawKellSetup(int stream, const SOkArm &arm)
  {
   if(!InpDrawSetups || (g_tester && !g_visual))
      return;
   g_drawSeq++;
   string pfx = StringFormat("OK_%d_", g_drawSeq % 24);
   ObjectsDeleteAll(0, pfx);

   color cLine = (arm.dir > 0) ? clrDodgerBlue : clrCrimson;
   color cTrig = (arm.dir > 0) ? clrLime       : clrOrangeRed;

   if(arm.u1t > 0 && arm.u2t > 0 && arm.u2t >= arm.u1t)
     {
      string nmU = pfx + "UPPER";
      if(ObjectCreate(0, nmU, OBJ_TREND, 0, arm.u1t, arm.u1p, arm.u2t, arm.u2p))
        {
         ObjectSetInteger(0, nmU, OBJPROP_COLOR, cLine);
         ObjectSetInteger(0, nmU, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, nmU, OBJPROP_RAY_RIGHT, false);
        }
     }
   if(arm.l1t > 0 && arm.l2t > 0 && arm.l2t >= arm.l1t)
     {
      string nmL = pfx + "LOWER";
      if(ObjectCreate(0, nmL, OBJ_TREND, 0, arm.l1t, arm.l1p, arm.l2t, arm.l2p))
        {
         ObjectSetInteger(0, nmL, OBJPROP_COLOR, cLine);
         ObjectSetInteger(0, nmL, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, nmL, OBJPROP_RAY_RIGHT, false);
        }
     }
   string nmT = pfx + "LABEL";
   datetime lblT = (arm.u2t > arm.l2t) ? arm.u2t : arm.l2t;
   if(lblT <= 0) lblT = TimeCurrent();
   if(ObjectCreate(0, nmT, OBJ_TEXT, 0, lblT, arm.level))
     {
      ObjectSetString(0, nmT, OBJPROP_TEXT,
                      StringFormat("[%s] %s (%s)", OK_STREAM_NAMES[stream], OK_SETUP_NAMES[arm.setupId], arm.dir > 0 ? "BUY" : "SELL"));
      ObjectSetInteger(0, nmT, OBJPROP_COLOR, cTrig);
      ObjectSetInteger(0, nmT, OBJPROP_FONTSIZE, 8);
     }
  }

//+------------------------------------------------------------------+
//| Log breakout decision to oliver_kell_events.csv in tester        |
//+------------------------------------------------------------------+
void LogEvent(datetime srvNow, int s, const SOkArm &arm, double fillPx, double p,
              const string dec, const float &f[])
  {
   if(g_evLog == INVALID_HANDLE)
      return;
   string fStr = "";
   int nf = ArraySize(f);
   for(int i = 0; i < nf; i++)
      fStr += (i == 0 ? "" : ",") + DoubleToString(f[i], 5);
   FileWrite(g_evLog,
             TimeToString(srvNow, TIME_DATE | TIME_SECONDS),
             TimeToString(g_mk.m_clk.ToUtc(srvNow), TIME_DATE | TIME_SECONDS),
             OK_STREAM_NAMES[s],
             (arm.setupId >= 0 && arm.setupId < OK_NSETUPS) ? OK_SETUP_NAMES[arm.setupId] : "?",
             arm.dir,
             DoubleToString(arm.level, 2),
             DoubleToString(fillPx, 2),
             DoubleToString(p, 6),
             dec,
             fStr);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_visual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   if(!g_mk.Init(_Symbol, InpBrokerGMTOffsetHours, true))
     {
      Print("[oliver_kell_ea] Market initialization failed.");
      return INIT_FAILED;
     }
   g_st.Reset();
   if(!g_ai.Init())
      Print("[oliver_kell_ea] WARNING: ONNX Meta-Labeler failed to initialize; running unvetoed.");

   g_risk.Init(_Symbol, InpMode, InpRiskScale, g_mk.m_clk);
   g_tr.Init(_Symbol, InpMagicNumber);

   if(g_tester)
     {
      g_evLog = FileOpen("oliver_kell_events.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_evLog != INVALID_HANDLE)
         FileWrite(g_evLog, "srv", "utc", "stream", "setup", "dir", "trig_lvl", "px", "p", "decision", "features");

      g_trLog = FileOpen("oliver_kell_trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_trLog != INVALID_HANDLE)
        {
         FileWrite(g_trLog, "ticket", "stream", "setup", "dir", "entry", "exit", "lots", "R", "net", "outs", "win_outs", "balance");
         g_tr.m_logH = g_trLog;
        }
     }

   PrintFormat("[oliver_kell_ea v1.10] Initialized on %s | Mode=%s | Surroundings=%s | AI=%s (thrHTF=%.4f, thrM5=%.4f, thrHigh=%.4f) | Ready=%s",
               _Symbol, EnumToString(InpMode), InpRespectSurroundings ? "ON" : "NO-HEDGE", OK_AI_STAMP, OK_AI_THR_HTF, OK_AI_THR_M5, OK_AI_THR_HIGH,
               g_mk.Ready() ? "YES" : "WARMING_UP");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_tr.ReconcileWithBroker();
   if(g_evLog != INVALID_HANDLE) { FileClose(g_evLog); g_evLog = INVALID_HANDLE; }
   if(g_trLog != INVALID_HANDLE) { FileClose(g_trLog); g_trLog = INVALID_HANDLE; }
   g_tr.m_logH = INVALID_HANDLE;
   g_ai.Release();
   Comment("");
   PrintFormat("[oliver_kell_ea v1.10] Deinit: trades=%d vetoed=%d busySkips=%d newsSkips=%d",
               g_trades, g_vetoes, g_busySkips, g_newsSkips);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime srvNow = TimeCurrent();
   g_mk.m_clk.RefreshOffset(srvNow);

   bool newM5 = false, newM15 = false, newM30 = false, newH1 = false, newH2 = false;
   g_mk.SyncClosedBars(newM5, newM15, newM30, newH1, newH2);

   if(g_risk.UpdateTrackers(srvNow, g_mk.m_clk))
      g_tr.CloseAll("Drawdown Ceiling Breached");

   g_tr.Manage(g_risk, srvNow);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   g_st.OnNewBars(g_mk, newM5, newM15, newM30, newH1, newH2, bid);

   //--- Check armed Oliver Kell Cycle triggers across all 5 streams (priority: H1 -> H2 -> M30 -> M15 -> M5)
   for(int s = 0; s < OK_NSTREAMS; s++)
     {
      if(!g_st.st[s].armed)
         continue;
      SOkArm armSnap = g_st.st[s];
      int    d       = 0;
      double trigPx  = 0.0;
      if(!g_st.CheckBreak(s, bid, ask, d, trigPx))
         continue;

      //--- Consume any simultaneous lower-priority breakouts on this exact tick
      for(int q = s + 1; q < OK_NSTREAMS; q++)
        {
         int dq = 0; double tq = 0.0;
         g_st.CheckBreak(q, bid, ask, dq, tq);
        }

      datetime nowMin = srvNow - (srvNow % 60);
      bool sameMinute = (nowMin == g_lastDecisionMin);

      float fVec[];
      double p = g_ai.Score(s, armSnap, g_mk, srvNow, fVec);
      double fillEst = (d == 1) ? ask : bid;

      if(sameMinute)
        {
         LogEvent(srvNow, s, armSnap, fillEst, p, "dup-minute", fVec);
         break;
        }
      g_lastDecisionMin = nowMin;

      if(!g_mk.Ready())
        {
         LogEvent(srvNow, s, armSnap, fillEst, p, "warmup", fVec);
         break;
        }
      if(InpSkipNewsDays && g_news.IsKeyDay(g_mk.m_clk.ToUtc(srvNow), srvNow))
        {
         g_newsSkips++;
         LogEvent(srvNow, s, armSnap, fillEst, p, "news-day", fVec);
         break;
        }
      if(!g_risk.CanOpenStream(s, g_tr.Probes()) || g_tr.StreamHasProbe(s))
        {
         g_busySkips++;
         LogEvent(srvNow, s, armSnap, fillEst, p, "busy-or-reserved", fVec);
         break;
        }
      string surrReason = "";
      if(!g_tr.CheckSurroundings(d, InpRespectSurroundings, srvNow, surrReason))
        {
         g_busySkips++;
         LogEvent(srvNow, s, armSnap, fillEst, p, surrReason, fVec);
         break;
        }
      int kdNow = g_mk.d1.LastClosedAt(srvNow);
      bool isD1Trans = (kdNow >= 0 && g_mk.d1.stackd[kdNow] == 0);
      double effThr = g_ai.Threshold(s) + (isD1Trans ? 0.02 : 0.0);
      if(InpEnableAiVeto && p >= 0.0 && p < effThr)
        {
         g_vetoes++;
         g_lastEvent = StringFormat("%s %s %s p=%.3f VETO",
                                    TimeToString(srvNow, TIME_DATE | TIME_MINUTES),
                                    OK_STREAM_NAMES[s], OK_SETUP_NAMES[armSnap.setupId], p);
         LogEvent(srvNow, s, armSnap, fillEst, p, "veto", fVec);
         break;
        }

      int kh1 = g_mk.h1.LastClosedAt(srvNow);
      double h1Atr = (kh1 >= 0) ? g_mk.h1.atr[kh1] : 0.0;
      double convMult = g_ai.ConvictionMult(p, InpMode == OK_HOUSE_MONEY_GROWTH);
      if(g_tr.OpenProbe(s, armSnap.setupId, d, h1Atr, convMult, g_risk, srvNow))
        {
         g_trades++;
         g_lastEvent = StringFormat("%s %s %s (%s) p=%.3f (x%.2f) OPEN",
                                    TimeToString(srvNow, TIME_DATE | TIME_MINUTES),
                                    OK_STREAM_NAMES[s], OK_SETUP_NAMES[armSnap.setupId],
                                    d > 0 ? "BUY" : "SELL", p, convMult);
         DrawKellSetup(s, armSnap);
         LogEvent(srvNow, s, armSnap, fillEst, p, "trade", fVec);
        }
      else
        {
         LogEvent(srvNow, s, armSnap, fillEst, p, "risk-skip", fVec);
        }
      break;
     }

   //--- Live / Visual HUD
   if((!g_tester || g_visual) && TimeLocal() != g_lastHud)
     {
      g_lastHud = TimeLocal();
      string armedStr = "";
      for(int s = 0; s < OK_NSTREAMS; s++)
         if(g_st.st[s].armed)
            armedStr += StringFormat(" [%s:%s %s@%.2f]",
                                     OK_STREAM_NAMES[s], OK_SETUP_NAMES[g_st.st[s].setupId],
                                     g_st.st[s].dir > 0 ? "BUY" : "SELL", g_st.st[s].level);
      if(armedStr == "") armedStr = " none";

      int k1 = g_mk.h1.Last(), k4 = g_mk.h4.Last(), kd = g_mk.d1.Last();
      Comment(StringFormat("oliver_kell_ea v1.11 | Mode: %s | Ready: %s | Probes: %d/%d (Unprot: %d)\n"
                           "7-EMA Stacks  H1:%+d  H4:%+d  D1:%+d (5E:%+d) | Daily DD: %.2f%% | Total DD: %.2f%%\n"
                           "Armed Setups:%s\n"
                           "Last Model Call: %s\n"
                           "Last Model Decision: %s\n"
                           "Last Action: %s | Trades: %d | AI Vetoes: %d",
                           EnumToString(InpMode), g_mk.Ready() ? "YES" : "WARMUP",
                           g_tr.Probes(), g_risk.m_maxProbeSlots, g_tr.UnprotectedProbes(),
                           k1 >= 0 ? g_mk.h1.stackd[k1] : 0,
                           k4 >= 0 ? g_mk.h4.stackd[k4] : 0,
                           kd >= 0 ? g_mk.d1.stackd[kd] : 0,
                           kd >= 0 ? g_mk.d1.StackTop5(kd) : 0,
                           g_risk.DailyDdPct(), g_risk.TotalDdPct(),
                           armedStr,
                           g_ai.LastCallStr(),
                           g_ai.LastDecisionStr(),
                           g_lastEvent, g_trades, g_vetoes));
     }
  }
//+------------------------------------------------------------------+
