//+------------------------------------------------------------------+
//|                                           XAUUSD_Trident_MoE.mq5 |
//|     XAUUSD Trident Mixture-of-Experts (MoE) 3-Prong Master EA    |
//|                                                                  |
//|   "Three Prongs, One Strike" — Harmonizes 3 Orthogonal Regime    |
//|   Specialists inside a single .ex5 with 3 embedded ONNX models:  |
//|                                                                  |
//|   * Prong #1 (Corner 1 - Sniper, Magic 20260401):                |
//|       London & NY Killzone Liquidity Sweep + M1 Volume Profile   |
//|       Reversals gated by xauusd_meta_model.onnx (12 features).   |
//|   * Prong #2 (Corner 2 - 16Runes, Magic 16016001):               |
//|       Multi-Timeframe 16-Chart-Pattern Trend Coils when H4 & D1  |
//|       7-EMA stacks align, gated by 16runes_meta.onnx (16 feats). |
//|   * Prong #3 (Corner 4 - ImpulseCascade, Magic 16016004):        |
//|       Fast H4 Top-3 + H1 Top-5 V-Reversal Cascades when 16Runes  |
//|       is OFF (0/16 Runes), gated by impulse_cascade_meta.onnx.   |
//|   * Corner #3 (Dead-Flat Tangled Chop):                          |
//|       Automatically sits out to preserve capital and Sniper slot.|
//+------------------------------------------------------------------+
#property copyright   "Onix Quantitative Systems — Trident Mixture-of-Experts"
#property link        "https://www.mql5.com"
#property version     "1.01"
#property description "XAUUSD Trident MoE v1.01 — 3-Prong Mixture-of-Experts (Sniper + 16Runes + ImpulseCascade)"
#property description "3 Embedded Strict-OOS ONNX Models | Hourly AI Regime Router | <3% Daily / <6% Total DD Ceiling"
#property strict

#define TRIDENT_EA_VERSION "1.01"

//--- Embed Prong #1 float32[1,12] ONNX Meta-Labeler Binary inside .ex5
//--- (Prong #2 16runes_meta.onnx & Prong #3 impulse_cascade_meta.onnx are embedded via TridentAiRater.mqh)
#resource "\\Files\\models\\xauusd_meta_model.onnx" as uchar ExtOnnxModel[]

//--- Prong #1 (Sniper) Modular Architecture Includes
#include <XAUUSD_Quant\Core\Definitions.mqh>
#include <XAUUSD_Quant\Core\Logger.mqh>
#include <XAUUSD_Quant\Core\GoldeenTelemetry.mqh>
#include <XAUUSD_Quant\Layer1_Signal\SessionLevels.mqh>
#include <XAUUSD_Quant\Layer1_Signal\VolumeProfile.mqh>
#include <XAUUSD_Quant\Layer1_Signal\SweepSignalEngine.mqh>
#include <XAUUSD_Quant\Layer2_AI\FeatureExtractor.mqh>
#include <XAUUSD_Quant\Layer2_AI\OnnxMetaLabeler.mqh>
#include <XAUUSD_Quant\Layer3_Risk\EquityGuard.mqh>
#include <XAUUSD_Quant\Layer3_Risk\PositionSizer.mqh>
#include <XAUUSD_Quant\Layer3_Risk\ExecutionManager.mqh>

//--- Prong #2 (16Runes) & Prong #3 (ImpulseCascade) MoE Architecture Includes
#include <16Runes\News.mqh>
#include <Trident\TridentStreams.mqh>
#include <Trident\TridentAiRater.mqh>
#include <Trident\TridentTrader.mqh>

//+------------------------------------------------------------------+
//| Expert Advisor Input Parameters                                  |
//+------------------------------------------------------------------+
input group "=== [0] TRIDENT MIXTURE-OF-EXPERTS (MoE) PRONG SWITCHES ==="
input bool           InpEnableProng1_Sniper       = true;               // Enable Prong #1 (Corner 1): Sniper Killzone Reversals
input bool           InpEnableProng2_16Runes      = true;               // Enable Prong #2 (Corner 2): 16Runes Macro Trend Coils
input bool           InpEnableProng3_Cascade      = true;               // Enable Prong #3 (Corner 4): ImpulseCascade Fast V-Reversals
input double         InpMoEGapFillRiskPct         = 0.35;               // Prong #2/#3 Gap-Fill Base Risk % (when Sniper is ON)
input ulong          InpMagicProng1_Sniper        = 20260401;           // Magic Number — Prong #1 (Sniper)
input long           InpMagicProng2_16Runes       = 16016001;           // Magic Number — Prong #2 (16Runes)
input long           InpMagicProng3_Cascade       = 16016004;           // Magic Number — Prong #3 (ImpulseCascade)

input group "=== [1] UNIFIED RISK MODE & DRAWDOWN PROTECTION ==="
input ENUM_RISK_MODE InpRiskMode                  = MODE_PROP_GUARD;    // Operating Risk Mode ($50k Prop vs Growth)
input ENUM_DD_TYPE   InpDrawdownType              = DD_TRAILING_HWM;    // Max Drawdown Reference (Trailing HWM vs Static)
input double         InpCommissionPerLotRoundTurn = 7.00;               // Round-Turn ECN Commission per Lot (USD)
input double         InpPropTier2RiskPct          = 1.05;               // Prong #1 Prop Tier-2 Risk % (0.58 <= P < 0.72)
input double         InpPropTier1RiskPct          = 1.88;               // Prong #1 Prop Tier-1 Risk % (P >= 0.72)
input double         InpGrowthTier2RiskPct        = 1.10;               // Prong #1 Growth Tier-2 Risk % (0.58 <= P < 0.72)
input double         InpGrowthTier1RiskPct        = 1.92;               // Prong #1 Growth Tier-1 Risk % (P >= 0.72)
input double         InpWaveSoloRiskScale         = 1.00;               // Prong #2/#3 Solo Risk Scale (when Sniper is OFF)

input group "=== [2] NATIVE ONNX META-LABELERS (ALL 3 PRONGS) ==="
input bool           InpUseOnnxModel              = true;               // Enable Embedded ONNX Meta-Labelers Across All Prongs
input double         InpOnnxTier2Threshold        = 0.58;               // Prong #1 Sniper Minimum ONNX Win Prob (Tier 2)
input double         InpOnnxTier1Threshold        = 0.72;               // Prong #1 Sniper High-Conviction ONNX Prob (Tier 1)

input group "=== [3] PRONG #1: SWEEP & VOLUME PROFILE ENGINE ==="
input int            InpBrokerGMTOffsetHours      = 2;                  // Tester Fallback GMT Offset (Live/VPS Auto-Detects)
input double         InpVPBinSizeUSD              = 0.25;               // Intraday M1 Volume Profile Bin Width ($0.25)
input double         InpMinSweepAtrRatio          = 0.15;               // Minimum Liquidity Sweep Depth (x ATR_M15)
input double         InpMaxSweepAtrRatio          = 0.65;               // Maximum Liquidity Sweep Depth (x ATR_M15)
input double         InpMinAbsorptionVolRatio     = 1.50;               // Minimum Tick Volume Absorption (x SMA20)
input int            InpMaxReclaimBarsM5          = 3;                  // Maximum M5 Bars Allowed for Level Reclaim
input int            InpLimitExpiryBarsM5         = 3;                  // Pending Sniper Limit Expiry (M5 Bars = 15m)
input bool           InpEnableVerticalTimeBarrier = true;               // Enforce 4-Hour Vertical Time Barrier on Sniper Trades
input int            InpVerticalBarrierHours      = 4;                  // Vertical Time Barrier Duration (Hours)

input group "=== [4] MICROSTRUCTURE, ROLLOVER, NEWS & HUD ==="
input bool           InpEnableCalendarFilter      = true;               // Block Sniper Entries +/- 15m Around High-Impact News
input bool           InpSkipWaveNewsDays          = false;              // Skip Prong #2/#3 Entries on Key US Release Days
input double         InpMaxSpreadMultiplier       = 1.80;               // Max Allowed Spread vs 5-Min Rolling Average
input double         InpHardMaxSpreadUSD          = 0.80;               // Hard Absolute Spread Ceiling on XAUUSD ($)
input ulong          InpMaxSlippagePoints         = 30;                 // Maximum Allowed Slippage (Points)
input bool           InpDrawPatterns              = true;               // Draw Detected Prong #2/#3 Chart Patterns
input bool           InpShowChartHUD              = true;               // Render Real-Time Trident MoE HUD on Chart
input bool           InpEnableCsvTelemetry        = false;              // Write Setup & Trade Telemetry CSVs
input bool           InpCsvUseCommonFolder        = false;              // Write CSVs to Terminal FILE_COMMON Directory
input ENUM_LOG_LEVEL InpLogLevel                  = LOG_INFO;           // Minimum Journal Logging Verbosity

input group "=== [5] GOLDEEN.IO FLEET TELEMETRY (REDIS INSTANT QUEUE) ==="
input string         InpGoldeenToken              = "";                 // Goldeen.io EA Token (gld_ea_... | Empty = Disabled)
input string         InpGoldeenUrl                = "https://api.goldeen.io/api/v1/ea/report"; // Goldeen Telemetry Endpoint

//+------------------------------------------------------------------+
//| Global Modular Subsystem Instances                               |
//+------------------------------------------------------------------+
//--- Prong #1 (Sniper) Instances
CQuantLogger       g_logger;
CSessionLevels     g_sessionLevels;
CVolumeProfile     g_volumeProfile;
CSweepSignalEngine g_sweepEngine;
CFeatureExtractor  g_featureExtractor;
COnnxMetaLabeler   g_onnxLabeler;
CEquityGuard       g_equityGuard;
CPositionSizer     g_positionSizer;
CExecutionManager  g_executionManager;
CGoldeenTelemetry  g_goldeen;

//--- Prong #2 (16Runes) & Prong #3 (ImpulseCascade) Instances
CR16Market         g_trMkt;
CTridentStreams    g_trStreams;
CTridentAiRater    g_trAi;
CTridentRisk       g_trRisk;
CTridentTrader     g_trTrader;
CR16News           g_trNews;

bool               g_tester               = false;
bool               g_visual               = false;
datetime           g_lastHudUpdateTime    = 0;
datetime           g_lastWaveDecisionMin  = 0;
string             g_lastSniperCallStr    = "NONE YET";
string             g_lastSniperDecStr     = "N/A";
string             g_lastWaveEventStr     = "NONE YET";
int                g_tradesSniper         = 0;
int                g_vetoesWave           = 0;
int                g_busySkipsWave        = 0;
int                g_drawSeq              = 0;

//+------------------------------------------------------------------+
//| Draw detected Prong #2 / Prong #3 pattern lines on chart         |
//+------------------------------------------------------------------+
void DrawTridentPattern(int corner, int stream, const SR16Arm &arm)
  {
   if(!InpDrawPatterns || (g_tester && !g_visual))
      return;
   g_drawSeq++;
   string pfx = StringFormat("TRD_%d_", g_drawSeq % 24);
   ObjectsDeleteAll(0, pfx);

   color cLine = (corner == TRIDENT_CORNER_CASCADE)
                 ? ((arm.dir > 0) ? clrAqua : clrMagenta)
                 : ((arm.dir > 0) ? clrDodgerBlue : clrCrimson);
   color cTrig = (arm.dir > 0) ? clrLime : clrOrangeRed;

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
   string cName = (corner == TRIDENT_CORNER_CASCADE) ? "P3:CAS" : "P2:R16";
   if(ObjectCreate(0, nmT, OBJ_TEXT, 0, lblT, arm.level))
     {
      ObjectSetString(0, nmT, OBJPROP_TEXT,
                      StringFormat("[%s %s] %s (%s)", cName, R16_STREAM_NAMES[stream],
                                   R16_NAMES[arm.runeId], arm.dir > 0 ? "BUY" : "SELL"));
      ObjectSetInteger(0, nmT, OBJPROP_COLOR, cTrig);
      ObjectSetInteger(0, nmT, OBJPROP_FONTSIZE, 8);
     }
  }

//+------------------------------------------------------------------+
//| Render Real-Time Trident Mixture-of-Experts HUD                  |
//+------------------------------------------------------------------+
void UpdateChartHUD()
  {
   if(!InpShowChartHUD || (g_tester && !g_visual))
      return;

   datetime now = TimeCurrent();
   if(now == g_lastHudUpdateTime)
      return;
   g_lastHudUpdateTime = now;

   SRiskStateSnapshot riskSnap;
   SSessionReference  sessRef;
   SActiveTradeContext tradeCtx;

   g_equityGuard.GetRiskStateSnapshot(riskSnap);
   g_sessionLevels.GetSessionReference(sessRef);
   g_executionManager.GetActiveContext(tradeCtx);

   string regimeBar = g_trStreams.CurrentRegimeSummary(g_trMkt, now,
                                                       InpEnableProng1_Sniper,
                                                       InpEnableProng2_16Runes,
                                                       InpEnableProng3_Cascade);
   int k1 = g_trMkt.h1.Last(), k4 = g_trMkt.h4.Last(), kd = g_trMkt.d1.Last();

   string hud = StringFormat(
      "====================================================================\n"
      " XAUUSD TRIDENT MIXTURE-OF-EXPERTS (MoE) EA v%s — 3 PRONGS, 1 STRIKE\n"
      "====================================================================\n"
      " [MOE ROUTER] : %s\n"
      " [ONNX READY] : P1(Sniper):%s | P2(16Runes):%s | P3(Cascade):%s\n"
      " [EMA STACKS] : H1(7E:%+d 5E:%+d) | H4(7E:%+d 3E:%+d) | D1(7E:%+d 5E:%+d)\n"
      "--------------------------------------------------------------------\n"
      " [EQUITY]     : $%.2f | Balance: $%.2f | HWM: $%.2f\n"
      " [DAILY DD]   : %.2f%% / %.2f%% (Hard Ceiling <3.00%%)\n"
      " [TOTAL DD]   : %.2f%% / %.2f%% (Hard Ceiling <6.00%%)\n"
      "--------------------------------------------------------------------\n"
      " [PRONG #1]   : %s | Session: %s | Last: %s (%s)\n"
      " [PRONG #2/#3]: Active Probes: %d (Unprot: %d) | Last: %s\n"
      " [TRADE CNT]  : P1(Sniper): %d | P2(16Runes): %d | P3(Cascade): %d\n"
      "====================================================================",
      TRIDENT_EA_VERSION,
      regimeBar,
      (g_onnxLabeler.IsModelReady() ? "YES" : "NO"),
      (g_trAi.ReadyRunes()          ? "YES" : "NO"),
      (g_trAi.ReadyCascade()        ? "YES" : "NO"),
      (k1 >= 0 ? g_trMkt.h1.stackd[k1] : 0), (k1 >= 0 ? g_trMkt.h1.StackTop5(k1) : 0),
      (k4 >= 0 ? g_trMkt.h4.stackd[k4] : 0), (k4 >= 0 ? g_trMkt.h4.StackTop3(k4) : 0),
      (kd >= 0 ? g_trMkt.d1.stackd[kd] : 0), (kd >= 0 ? g_trMkt.d1.StackTop5(kd) : 0),
      riskSnap.currentEquity, riskSnap.currentBalance, riskSnap.highWaterMark,
      MathMax(riskSnap.dailyDrawdownPct, g_trRisk.DailyDdPct()), riskSnap.dailyBreakerLimitPct,
      MathMax(riskSnap.totalDrawdownPct, g_trRisk.TotalDdPct()), riskSnap.totalBreakerLimitPct,
      (tradeCtx.hasOpenPosition ? "OPEN_POS" : (tradeCtx.hasPendingOrder ? "PENDING_LMT" : "FLAT")),
      KillzoneSessionToString(sessRef.currentSession),
      g_lastSniperCallStr, g_lastSniperDecStr,
      g_trTrader.Probes(), g_trTrader.UnprotectedProbes(), g_lastWaveEventStr,
      g_tradesSniper, g_trTrader.m_tradesRunes, g_trTrader.m_tradesCascade
   );

   Comment(hud);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tester = (bool)MQLInfoInteger(MQL_TESTER);
   g_visual = (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   // 1. Initialize Prong #1 (Sniper) Subsystem
   if(!g_logger.Init(_Symbol, InpMagicProng1_Sniper, InpLogLevel, InpEnableCsvTelemetry,
                     InpBrokerGMTOffsetHours, InpCsvUseCommonFolder, "trident_sniper"))
     {
      Print("[TRIDENT-MoE][ERROR] Logger initialization failed.");
      return INIT_FAILED;
     }

   if(!g_equityGuard.Init(_Symbol, InpMagicProng1_Sniper, InpRiskMode, InpDrawdownType,
                          InpBrokerGMTOffsetHours, InpEnableCalendarFilter,
                          InpMaxSpreadMultiplier, InpHardMaxSpreadUSD, &g_logger))
     {
      g_logger.Critical("Trident EquityGuard initialization failed.");
      return INIT_FAILED;
     }

   if(!g_positionSizer.Init(_Symbol, InpRiskMode, InpCommissionPerLotRoundTurn,
                            &g_equityGuard, &g_logger,
                            InpPropTier2RiskPct, InpPropTier1RiskPct,
                            InpGrowthTier2RiskPct, InpGrowthTier1RiskPct))
     {
      g_logger.Critical("Trident PositionSizer initialization failed.");
      return INIT_FAILED;
     }

   if(!g_executionManager.Init(_Symbol, InpMagicProng1_Sniper, InpMaxSlippagePoints,
                               InpCommissionPerLotRoundTurn, InpEnableVerticalTimeBarrier,
                               InpVerticalBarrierHours, &g_equityGuard, &g_positionSizer, &g_logger))
     {
      g_logger.Critical("Trident ExecutionManager initialization failed.");
      return INIT_FAILED;
     }

   if(!g_sessionLevels.Init(_Symbol, InpBrokerGMTOffsetHours, &g_logger, 0.15, 1.50) ||
      !g_volumeProfile.Init(_Symbol, InpBrokerGMTOffsetHours, &g_logger, InpVPBinSizeUSD,
                            VP_VALUE_AREA_PCT, VP_LVN_THRESHOLD_RATIO) ||
      !g_sweepEngine.Init(_Symbol, InpBrokerGMTOffsetHours, &g_sessionLevels, &g_volumeProfile,
                          &g_logger, InpMinSweepAtrRatio, InpMaxSweepAtrRatio,
                          InpMinAbsorptionVolRatio, InpMaxReclaimBarsM5, InpLimitExpiryBarsM5) ||
      !g_featureExtractor.Init(_Symbol, InpBrokerGMTOffsetHours, &g_sessionLevels,
                               &g_volumeProfile, &g_logger))
     {
      g_logger.Critical("Trident Prong #1 Layer 1/2 initialization failed.");
      return INIT_FAILED;
     }

   g_onnxLabeler.InitFromBuffer(ExtOnnxModel, InpUseOnnxModel, &g_logger,
                                InpOnnxTier2Threshold, InpOnnxTier1Threshold);

   // 2. Initialize Prong #2 (16Runes) & Prong #3 (ImpulseCascade) Subsystems
   if(!g_trMkt.Init(_Symbol, InpBrokerGMTOffsetHours, true))
     {
      Print("[TRIDENT-MoE][ERROR] Multi-Timeframe Wave Market initialization failed.");
      return INIT_FAILED;
     }
   g_trStreams.ResetAll();
   if(!g_trAi.Init())
      Print("[TRIDENT-MoE][WARN] One or more Wave ONNX Meta-Labelers failed to init.");

   ENUM_R16_MODE waveMode = (InpRiskMode == MODE_PROP_GUARD) ? R16_PROP_FIRM : R16_HOUSE_MONEY_GROWTH;
   g_trRisk.Init(_Symbol, waveMode, InpWaveSoloRiskScale, g_trMkt.m_clk);
   g_trRisk.ConfigureMoE(InpEnableProng1_Sniper, InpMoEGapFillRiskPct);
   g_trTrader.Init(_Symbol, (long)InpMagicProng1_Sniper, InpMagicProng2_16Runes,
                   InpMagicProng3_Cascade, InpEnableProng1_Sniper);

   g_goldeen.Init(InpGoldeenToken, InpGoldeenUrl, "XAUUSD_Trident_MoE", TRIDENT_EA_VERSION,
                  "Trident MoE 3-Prong", _Symbol, InpMagicProng1_Sniper, InpMagicProng1_Sniper);
   if(g_goldeen.IsEnabled())
      EventSetTimer(2);

   PrintFormat("[XAUUSD_Trident_MoE v%s] Initialized on %s | P1(Sniper)=%s [Magic=%I64u] | P2(16Runes)=%s [Magic=%I64d] | P3(Cascade)=%s [Magic=%I64d]",
               TRIDENT_EA_VERSION, _Symbol,
               InpEnableProng1_Sniper  ? "ON" : "OFF", InpMagicProng1_Sniper,
               InpEnableProng2_16Runes ? "ON" : "OFF", InpMagicProng2_16Runes,
               InpEnableProng3_Cascade ? "ON" : "OFF", InpMagicProng3_Cascade);

   UpdateChartHUD();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_goldeen.IsEnabled())
      EventKillTimer();
   g_trTrader.ReconcileWithBroker();
   g_trAi.Release();
   g_onnxLabeler.Deinit();
   g_featureExtractor.Deinit();
   g_sessionLevels.Deinit();

   if(InpShowChartHUD)
      Comment("");

   PrintFormat("[XAUUSD_Trident_MoE v%s] Deinit (reason=%d) | Trades -> P1(Sniper):%d P2(16Runes):%d P3(Cascade):%d | WaveVetoes:%d",
               TRIDENT_EA_VERSION, reason, g_tradesSniper, g_trTrader.m_tradesRunes, g_trTrader.m_tradesCascade, g_vetoesWave);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime srvNow = TimeCurrent();
   g_trMkt.m_clk.RefreshOffset(srvNow);

   bool newM5 = false, newM15 = false, newM30 = false, newH1 = false, newH2 = false;
   g_trMkt.SyncClosedBars(newM5, newM15, newM30, newH1, newH2);

   // ================================================================
   // PRIORITY 0: Unified Real-Time Drawdown Circuit Breaker Watchdog
   // Enforces <3.0% Daily & <6.0% Total DD across all 3 Prongs.
   // ================================================================
   bool sniperBreach = g_equityGuard.CheckEmergencyBreach();
   SRiskStateSnapshot rSnap;
   g_equityGuard.GetRiskStateSnapshot(rSnap);
   bool waveBreach   = g_trRisk.UpdateTrackersTrident(srvNow, g_trMkt.m_clk, rSnap);
   if(sniperBreach || waveBreach)
     {
      g_trTrader.CloseAll("Unified Trident Drawdown Breaker Tripped");
      UpdateChartHUD();
      return;
     }

   // ================================================================
   // PRIORITY 1: Manage Active Positions & Orders Across All 3 Prongs
   // ================================================================
   g_executionManager.ManageActiveTradesOnTick();
   g_trTrader.Manage(g_trRisk, srvNow);

   bool hasSniperExposure = g_executionManager.HasActiveExposure();
   g_sweepEngine.NotifyPendingOrderState(hasSniperExposure);

   // ================================================================
   // PRIORITY 2: PRONG #1 (Corner 1 — Sniper Killzone Stop-Hunt Sweep)
   // Always evaluate M5 bar close to keep broken H1 levels fresh.
   // ================================================================
   SSweepCandidateSetup candidateSetup;
   bool hasCandidateSignal = g_sweepEngine.EvaluateOnM5BarClose(hasSniperExposure, candidateSetup);

   if(InpEnableProng1_Sniper && hasCandidateSignal &&
      g_executionManager.CanOpenNewPosition(candidateSetup.direction, candidateSetup.entryLimitPrice))
     {
      SStationaryFeatures features;
      double currentSpreadUSD = g_equityGuard.GetCurrentSpreadUSD();
      if(g_featureExtractor.ExtractFeatures(candidateSetup, currentSpreadUSD, features))
        {
         SOnnxPrediction prediction;
         g_onnxLabeler.PredictProbability(features, prediction);
         g_lastSniperCallStr = StringFormat("%s %s@%.2f",
                                            DirectionToString(candidateSetup.direction),
                                            LiquidityTypeToString(candidateSetup.sweptPoolType),
                                            candidateSetup.sweptLevelPrice);
         g_lastSniperDecStr  = StringFormat("P=%.3f (T%d)", prediction.winProbability, prediction.riskTier);

         if(prediction.riskTier > 0 && prediction.winProbability >= InpOnnxTier2Threshold)
           {
            ENUM_BREACH_REASON blockReason = BREACH_NONE;
            if(g_equityGuard.IsNewEntryPermitted(blockReason))
              {
               SLotCalculationResult lotResult;
               if(g_positionSizer.CalculateSniperLots(candidateSetup.direction,
                                                      candidateSetup.entryLimitPrice,
                                                      candidateSetup.stopLossPrice,
                                                      prediction.winProbability,
                                                      lotResult,
                                                      candidateSetup.confRiskMultiplier))
                 {
                  if(g_executionManager.PlaceSniperLimitOrder(candidateSetup, features, prediction, lotResult))
                    {
                     g_sweepEngine.NotifyPendingOrderState(true);
                     g_tradesSniper++;
                     UpdateChartHUD();
                     return;
                    }
                 }
              }
           }
        }
     }

   // ================================================================
   // PRIORITY 3: PRONG #2 (16Runes) & PRONG #3 (ImpulseCascade)
   // Hourly AI Regime Router activates Corner #2 when HTF EMAs stack,
   // or Corner #4 when 16Runes is OFF and H4 Top-3 + H1 Top-5 cascade.
   // ================================================================
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
     {
      UpdateChartHUD();
      return;
     }

   g_trStreams.OnNewBarsTrident(g_trMkt, newM5, newM15, newM30, newH1, newH2,
                                bid, InpEnableProng2_16Runes, InpEnableProng3_Cascade);

   if(!InpEnableProng2_16Runes && !InpEnableProng3_Cascade)
     {
      UpdateChartHUD();
      return;
     }

   for(int s = 0; s < R16_NSTREAMS; s++)
     {
      if(!g_trStreams.st[s].armed)
         continue;
      SR16Arm armSnap  = g_trStreams.st[s];
      int     d        = 0;
      double  trigPx   = 0.0;
      int     corner   = TRIDENT_CORNER_NONE;
      if(!g_trStreams.CheckBreakTrident(s, bid, ask, d, trigPx, corner))
         continue;

      // Consume any simultaneous lower-priority breakouts on this exact tick
      for(int q = s + 1; q < R16_NSTREAMS; q++)
        {
         int dq = 0, cq = 0; double tq = 0.0;
         g_trStreams.CheckBreakTrident(q, bid, ask, dq, tq, cq);
        }

      datetime nowMin = srvNow - (srvNow % 60);
      if(nowMin == g_lastWaveDecisionMin)
         break;
      g_lastWaveDecisionMin = nowMin;

      if(!g_trMkt.Ready())
         break;
      if(InpSkipWaveNewsDays && g_trNews.IsKeyDay(g_trMkt.m_clk.ToUtc(srvNow), srvNow))
         break;
      if(!g_trRisk.CanOpenStream(s, g_trTrader.Probes()) || g_trTrader.StreamHasProbe(s))
        {
         g_busySkipsWave++;
         break;
        }
      string surrReason = "";
      if(!g_trTrader.CheckSurroundings(d, true, srvNow, surrReason))
        {
         g_busySkipsWave++;
         break;
        }

      float  fVec[];
      double p = g_trAi.ScoreCorner(corner, s, armSnap, g_trMkt, srvNow, fVec);
      int    kdNow = g_trMkt.d1.LastClosedAt(srvNow);
      bool   isD1Trans = (corner == TRIDENT_CORNER_16RUNES && kdNow >= 0 && g_trMkt.d1.stackd[kdNow] == 0);
      double effThr = g_trAi.Threshold(corner, s) + (isD1Trans ? 0.02 : 0.0);

      if(InpUseOnnxModel && p >= 0.0 && p < effThr)
        {
         g_vetoesWave++;
         g_lastWaveEventStr = StringFormat("[%s] %s %s p=%.3f VETO",
                                           corner == TRIDENT_CORNER_CASCADE ? "P3:CAS" : "P2:R16",
                                           R16_STREAM_NAMES[s], R16_NAMES[armSnap.runeId], p);
         break;
        }

      int    kh1      = g_trMkt.h1.LastClosedAt(srvNow);
      double h1Atr    = (kh1 >= 0) ? g_trMkt.h1.atr[kh1] : 0.0;
      double convMult = g_trAi.ConvictionMult(corner, p, InpRiskMode != MODE_PROP_GUARD);
      if(g_trTrader.OpenProbe(corner, s, armSnap.runeId, d, h1Atr, convMult, g_trRisk, srvNow))
        {
         g_lastWaveEventStr = StringFormat("[%s] %s %s (%s) p=%.3f OPEN",
                                           corner == TRIDENT_CORNER_CASCADE ? "P3:CAS" : "P2:R16",
                                           R16_STREAM_NAMES[s], R16_NAMES[armSnap.runeId],
                                           d > 0 ? "BUY" : "SELL", p);
         DrawTridentPattern(corner, s, armSnap);
        }
      break;
     }

   UpdateChartHUD();
  }

//+------------------------------------------------------------------+
//| TradeTransaction event handler (Prong #1 Sniper Deal Tracking)   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_executionManager.OnTradeTransaction(trans, request, result);
   g_goldeen.OnTradeTransactionWatch(trans);

   ENUM_SIGNAL_DIRECTION closedDir = SIGNAL_NONE;
   double closedR = 0.0;
   if(g_executionManager.ConsumeClosedOutcome(closedDir, closedR))
      g_sweepEngine.NotifyTradeOutcome(closedDir, closedR, ResolveCurrentUTCTime(InpBrokerGMTOffsetHours));
  }

//+------------------------------------------------------------------+
//| Timer event handler (Goldeen Telemetry)                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_goldeen.IsEnabled())
      return;

   SRiskStateSnapshot riskSnap;
   g_equityGuard.GetRiskStateSnapshot(riskSnap);

   string statusStr = (riskSnap.tradingHaltedToday || riskSnap.permanentLockout)
                      ? ("HALTED: " + BreachReasonToString(riskSnap.activeBreachReason))
                      : SweepStateToString(g_sweepEngine.GetCurrentState());

   g_goldeen.OnTimerCheck(riskSnap.highWaterMark,
                          riskSnap.dailyRealizedPnLUSD,
                          riskSnap.dailyRealizedPnLPct,
                          riskSnap.dailyDrawdownPct,
                          3.00,
                          riskSnap.totalDrawdownPct,
                          HARD_MAX_TOTAL_DD_CEILING_PCT,
                          g_lastSniperDecStr,
                          statusStr);
  }
//+------------------------------------------------------------------+
