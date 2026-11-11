//+------------------------------------------------------------------+
//|                                                      16Runes.mq5 |
//|   16Runes v1.10 - Multi-Timeframe 16-Chart-Pattern Moonshot EA   |
//|                                                                  |
//|   Recognizes and trades all 16 classical chart patterns ("Runes")|
//|   across 5 structure streams (H1, H2, M30, M15, M5) gated by     |
//|   the geometric 7-EMA ribbon hierarchy (10/16/26/41/66/105/168)  |
//|   and filtered by an embedded 16-feature ONNX Meta-Labeler       |
//|   (16runes_meta.onnx, trained on 2017-2023 Dukascopy setups).    |
//|                                                                  |
//|   The 16 Runes:                                                  |
//|    Bullish Continuation:                                         |
//|     0: ASC_TRI       1: BULL_WEDGE   2: BULL_FLAG  3: BULL_SYM_TRI|
//|    Bearish Continuation:                                         |
//|     4: DESC_TRI      5: BEAR_WEDGE   6: BEAR_FLAG  7: BEAR_SYM_TRI|
//|    Bullish Reversal:                                             |
//|     8: DBL_BOTTOM    9: TRPL_BOTTOM 10: INV_HS    11: FALL_WEDGE |
//|    Bearish Reversal:                                             |
//|    12: DBL_TOP      13: TRPL_TOP    14: HEAD_SHLDR 15: RISE_WEDGE|
//+------------------------------------------------------------------+
#property copyright   "16Runes Quantitative Systems"
#property version     "1.23"
#property description "16Runes v1.23 - 16 Chart Pattern Engine x 7-EMA Hierarchy x Strict-OOS (2017-2023) ONNX Meta-Labeler x Geometric Monthly Profit Shield (35/35 Green OOS Months, >91% WR)"

#include <16Runes\Market.mqh>
#include <16Runes\Streams.mqh>
#include <16Runes\AiRater.mqh>
#include <16Runes\RiskEngine.mqh>
#include <16Runes\Trader.mqh>
#include <16Runes\News.mqh>

input ENUM_R16_MODE InpMode                 = R16_PROP_FIRM; // Portfolio Risk Mode
input double        InpRiskScale            = 1.00;          // Risk Multiplier (0.25 .. 2.00)
input bool          InpEnableAiVeto         = true;          // Enable ONNX Meta-Labeler Veto
input bool          InpRespectSurroundings  = true;          // 3-Musketeers Guard (Zero Hedge + Yield to Unprotected External)
input bool          InpSkipNewsDays         = false;         // Skip new entries on key US release days
input bool          InpDrawPatterns         = true;          // Draw detected 16-Rune patterns on chart
input int           InpBrokerGMTOffsetHours = 2;             // Tester fallback GMT offset (hours)
input long          InpMagicNumber          = 16016001;      // EA Magic Number

CR16Market  g_mk;
CR16Streams g_st;
CR16AiRater g_ai;
CR16Risk    g_risk;
CR16Trader  g_tr;
CR16News    g_news;

int         g_evLog           = INVALID_HANDLE;
int         g_trLog           = INVALID_HANDLE;
bool        g_tester          = false;
bool        g_visual          = false;
datetime    g_lastHud         = 0;
datetime    g_lastDecisionMin = 0;
string      g_lastEvent       = "none";
int         g_trades          = 0;
int         g_vetoes          = 0;
int         g_busySkips       = 0;
int         g_newsSkips       = 0;
int         g_drawSeq         = 0;

//+------------------------------------------------------------------+
//| Draw detected Rune pattern lines + Entry/SL on chart             |
//+------------------------------------------------------------------+
void DrawRunePattern(int stream, const SR16Arm &arm)
  {
   if(!InpDrawPatterns || (g_tester && !g_visual))
      return;
   g_drawSeq++;
   string pfx = StringFormat("R16_%d_", g_drawSeq % 24);
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
                      StringFormat("[%s] %s (%s)", R16_STREAM_NAMES[stream], R16_NAMES[arm.runeId], arm.dir > 0 ? "BUY" : "SELL"));
      ObjectSetInteger(0, nmT, OBJPROP_COLOR, cTrig);
      ObjectSetInteger(0, nmT, OBJPROP_FONTSIZE, 8);
     }
  }

//+------------------------------------------------------------------+
//| Log breakout decision to 16runes_events.csv in tester            |
//+------------------------------------------------------------------+
void LogEvent(datetime srvNow, int s, const SR16Arm &arm, double fillPx, double p,
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
             R16_STREAM_NAMES[s],
             (arm.runeId >= 0 && arm.runeId < R16_NRUNES) ? R16_NAMES[arm.runeId] : "?",
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
      Print("[16Runes] Market initialization failed.");
      return INIT_FAILED;
     }
   g_st.Reset();
   if(!g_ai.Init())
      Print("[16Runes] WARNING: ONNX Meta-Labeler failed to initialize; running unvetoed.");

   g_risk.Init(_Symbol, InpMode, InpRiskScale, g_mk.m_clk);
   g_tr.Init(_Symbol, InpMagicNumber);

   if(g_tester)
     {
      g_evLog = FileOpen("16runes_events.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_evLog != INVALID_HANDLE)
         FileWrite(g_evLog, "srv", "utc", "stream", "rune", "dir", "trig_lvl", "px", "p", "decision", "features");

      g_trLog = FileOpen("16runes_trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(g_trLog != INVALID_HANDLE)
        {
         FileWrite(g_trLog, "ticket", "stream", "rune", "dir", "entry", "exit", "lots", "R", "net", "outs", "win_outs", "balance");
         g_tr.m_logH = g_trLog;
        }
     }

   PrintFormat("[16Runes v1.20] Initialized on %s | Mode=%s | Surroundings=%s | AI=%s (thrHTF=%.4f, thrM5=%.4f, thrHigh=%.4f) | Ready=%s",
               _Symbol, EnumToString(InpMode), InpRespectSurroundings ? "ON" : "NO-HEDGE", R16_AI_STAMP, R16_AI_THR_HTF, R16_AI_THR_M5, R16_AI_THR_HIGH,
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
   PrintFormat("[16Runes v1.20] Deinit: trades=%d vetoed=%d busySkips=%d newsSkips=%d",
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

   //--- Check armed Rune triggers across all 5 streams (priority: H1 -> H2 -> M30 -> M15 -> M5)
   for(int s = 0; s < R16_NSTREAMS; s++)
     {
      if(!g_st.st[s].armed)
         continue;
      SR16Arm armSnap = g_st.st[s];
      int    d      = 0;
      double trigPx = 0.0;
      if(!g_st.CheckBreak(s, bid, ask, d, trigPx))
         continue;

      //--- Consume any simultaneous lower-priority breakouts on this exact tick
      for(int q = s + 1; q < R16_NSTREAMS; q++)
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
                                    R16_STREAM_NAMES[s], R16_NAMES[armSnap.runeId], p);
         LogEvent(srvNow, s, armSnap, fillEst, p, "veto", fVec);
         break;
        }

      int kh1 = g_mk.h1.LastClosedAt(srvNow);
      double h1Atr = (kh1 >= 0) ? g_mk.h1.atr[kh1] : 0.0;
      double convMult = g_ai.ConvictionMult(p, InpMode == R16_HOUSE_MONEY_GROWTH);
      if(g_tr.OpenProbe(s, armSnap.runeId, d, h1Atr, convMult, g_risk, srvNow))
        {
         g_trades++;
         g_lastEvent = StringFormat("%s %s %s (%s) p=%.3f (x%.2f) OPEN",
                                    TimeToString(srvNow, TIME_DATE | TIME_MINUTES),
                                    R16_STREAM_NAMES[s], R16_NAMES[armSnap.runeId],
                                    d > 0 ? "BUY" : "SELL", p, convMult);
         DrawRunePattern(s, armSnap);
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
      for(int s = 0; s < R16_NSTREAMS; s++)
         if(g_st.st[s].armed)
            armedStr += StringFormat(" [%s:%s %s@%.2f]",
                                     R16_STREAM_NAMES[s], R16_NAMES[g_st.st[s].runeId],
                                     g_st.st[s].dir > 0 ? "BUY" : "SELL", g_st.st[s].level);
      if(armedStr == "") armedStr = " none";

      int k1 = g_mk.h1.Last(), k4 = g_mk.h4.Last(), kd = g_mk.d1.Last();
      Comment(StringFormat("16Runes v1.21 | Mode: %s | Ready: %s | Probes: %d/%d (Unprot: %d)\n"
                           "7-EMA Stacks  H1:%+d  H4:%+d  D1:%+d (5E:%+d) | Daily DD: %.2f%% | Total DD: %.2f%%\n"
                           "Armed Runes:%s\n"
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
