//+------------------------------------------------------------------+
//|                                           USDJPY_Sniper_ONNX.mq5 |
//|                     USDJPY Hybrid Quantitative Sniper EA (ONNX)  |
//|  Production Institutional EA: Sweep + VP + ONNX Meta-Labeler     |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "USDJPY Institutional Liquidity Sweep + M1 Volume Profile + Native ONNX Meta-Labeling EA"
#property description "3 Active Killzones (Tokyo/London/NY) | 1:100 Prop Forex Ready | 3.0% Daily / 6.0% Total DD Ceiling"
#property strict

//--- Embed Compiled float32[1,12] ONNX Meta-Labeler Binary inside .ex5
#resource "\\Files\\models\\usdjpy_meta_model.onnx" as uchar ExtOnnxModel[]

//--- Modular Architecture Includes
#include "../Include/USDJPY_Quant/Core/Definitions.mqh"
#include "../Include/USDJPY_Quant/Core/Logger.mqh"
#include "../Include/USDJPY_Quant/Layer1_Signal/SessionLevels.mqh"
#include "../Include/USDJPY_Quant/Layer1_Signal/VolumeProfile.mqh"
#include "../Include/USDJPY_Quant/Layer1_Signal/SweepSignalEngine.mqh"
#include "../Include/USDJPY_Quant/Layer2_AI/FeatureExtractor.mqh"
#include "../Include/USDJPY_Quant/Layer2_AI/OnnxMetaLabeler.mqh"
#include "../Include/USDJPY_Quant/Layer3_Risk/EquityGuard.mqh"
#include "../Include/USDJPY_Quant/Layer3_Risk/PositionSizer.mqh"
#include "../Include/USDJPY_Quant/Layer3_Risk/ExecutionManager.mqh"

//+------------------------------------------------------------------+
//| Expert Advisor Input Parameters                                  |
//+------------------------------------------------------------------+
input group "=== [1] LAYER 3: RISK MODE & DRAWDOWN PROTECTION ==="
input ENUM_RISK_MODE InpRiskMode                  = MODE_PROP_GUARD;    // Operating Risk Mode ($50k Prop vs Growth)
input ENUM_DD_TYPE   InpDrawdownType              = DD_TRAILING_HWM;    // Max Drawdown Reference (Trailing HWM vs Static)
input double         InpCommissionPerLotRoundTurn = 7.00;               // Round-Turn ECN Commission per Lot (USD)
input double         InpPropTier2RiskPct          = 1.05;               // Prop Mode Tier-2 Risk % (0.58 <= P < 0.72)
input double         InpPropTier1RiskPct          = 1.88;               // Prop Mode Tier-1 Risk % (P >= 0.72)
input double         InpGrowthTier2RiskPct        = 1.10;               // Growth Mode Tier-2 Base Risk % (0.58 <= P < 0.72)
input double         InpGrowthTier1RiskPct        = 1.92;               // Growth Mode Tier-1 Base Risk % (P >= 0.72)

input group "=== [2] LAYER 2: NATIVE ONNX META-LABELER ==="
input bool           InpUseOnnxModel              = true;               // Enable Native ONNX Model (false = Deterministic / Data Export)
input double         InpOnnxTier2Threshold        = 0.58;               // Minimum ONNX Win Probability Threshold (Tier 2)
input double         InpOnnxTier1Threshold        = 0.72;               // High-Conviction ONNX Win Probability (Tier 1)

input group "=== [3] LAYER 1: SWEEP & VOLUME PROFILE ENGINE ==="
input int            InpBrokerGMTOffsetHours      = 2;                  // Tester Fallback GMT Offset (Live/VPS Auto-Detects via TimeGMT)
input double         InpVPBinSizeUSD              = 0.020;              // Intraday M1 Volume Profile Bin Width (0.020 JPY = 2 pips)
input double         InpMinSweepAtrRatio          = 0.15;               // Minimum Liquidity Sweep Depth (x ATR_M15)
input double         InpMaxSweepAtrRatio          = 0.65;               // Maximum Liquidity Sweep Depth (x ATR_M15)
input double         InpMinAbsorptionVolRatio     = 1.50;               // Minimum Tick Volume Absorption (x SMA20)
input int            InpMaxReclaimBarsM5          = 3;                  // Maximum M5 Bars Allowed for Level Reclaim
input int            InpLimitExpiryBarsM5         = 3;                  // Pending Sniper Limit Expiry (M5 Bars = 15m)
input bool           InpEnableVerticalTimeBarrier = true;               // Enforce 4-Hour Vertical Time Barrier on Open Trades
input int            InpVerticalBarrierHours      = 4;                  // Vertical Time Barrier Duration (Hours)

input group "=== [4] MICROSTRUCTURE, ROLLOVER & NEWS GUARDS ==="
input bool           InpEnableCalendarFilter      = true;               // Block Entries +/- 15m Around High-Impact USD/JPY News
input double         InpMaxSpreadMultiplier       = 1.80;               // Max Allowed Spread vs 5-Min Rolling Average
input double         InpHardMaxSpreadUSD          = 0.035;              // Hard Absolute Spread Ceiling on USDJPY (0.035 JPY = 3.5 pips)

input group "=== [5] EXECUTION, TELEMETRY & DIAGNOSTICS ==="
input ulong          InpMagicNumber               = QUANT_DEFAULT_MAGIC;// Unique EA Magic Number
input ulong          InpMaxSlippagePoints         = 30;                 // Maximum Allowed Slippage (Points)
input bool           InpEnableCsvTelemetry        = true;               // Write Setup & Trade Telemetry CSVs
input bool           InpCsvUseCommonFolder        = false;              // Write CSVs to Terminal FILE_COMMON Directory
input ENUM_LOG_LEVEL InpLogLevel                  = LOG_INFO;           // Minimum Journal Logging Verbosity
input bool           InpShowChartHUD              = true;               // Render Real-Time Institutional HUD on Chart

//+------------------------------------------------------------------+
//| Global Modular Subsystem Instances                               |
//+------------------------------------------------------------------+
CQuantLogger       g_logger;
CSessionLevels     g_sessionLevels;
CVolumeProfile     g_volumeProfile;
CSweepSignalEngine g_sweepEngine;
CFeatureExtractor  g_featureExtractor;
COnnxMetaLabeler   g_onnxLabeler;
CEquityGuard       g_equityGuard;
CPositionSizer     g_positionSizer;
CExecutionManager  g_executionManager;

datetime           g_lastHudUpdateTime = 0;

//+------------------------------------------------------------------+
//| Render Real-Time Institutional Telemetry HUD                     |
//+------------------------------------------------------------------+
void UpdateChartHUD()
  {
   if(!InpShowChartHUD || ((bool)MQLInfoInteger(MQL_TESTER) && (bool)MQLInfoInteger(MQL_OPTIMIZATION)))
      return;

   datetime now = TimeCurrent();
   if(now == g_lastHudUpdateTime)
      return;
   g_lastHudUpdateTime = now;

   SRiskStateSnapshot     riskSnap;
   SSessionReference      sessRef;
   SVolumeProfileSnapshot vpSnap;
   SActiveTradeContext    tradeCtx;

   g_equityGuard.GetRiskStateSnapshot(riskSnap);
   g_sessionLevels.GetSessionReference(sessRef);
   g_volumeProfile.GetSnapshot(vpSnap);
   g_executionManager.GetActiveContext(tradeCtx);

   double   effOffsetHrs = ResolveEffectiveGMTOffsetHours(InpBrokerGMTOffsetHours);
   datetime utcNow       = ResolveCurrentUTCTime(InpBrokerGMTOffsetHours);

   string hud = StringFormat(
      "========================================================\n"
      " USDJPY HYBRID QUANTITATIVE SNIPER EA v%s (ONNX)\n"
      "========================================================\n"
      " [MODE]       : %s (%s)\n"
      " [ONNX AI]    : %s | Ready: %s\n"
      " [CLOCK / GMT]: UTC%+.2f (%s) | Server: %s | UTC: %s\n"
      " [SESSION]    : %s | Tradable Regime: %s\n"
      "--------------------------------------------------------\n"
      " [EQUITY]     : $%.2f | Balance: $%.2f\n"
      " [DAY REF]    : $%.2f | HWM: $%.2f\n"
      " [DAILY DD]   : %.2f%% / %.2f%% (Hard Ceiling 3.00%%)\n"
      " [TOTAL DD]   : %.2f%% / %.2f%% (Hard Ceiling 6.00%%)\n"
      " [REALIZED]   : Day: $%.2f (%.2f%%) | Week: $%.2f\n"
      " [STATUS]     : %s (Losses Today: %d)\n"
      "--------------------------------------------------------\n"
      " [ASIAN RNG]  : %.3f - %.3f (%.3f JPY) | ADR20: %.3f JPY\n"
      " [PDH / PDL]  : %.3f / %.3f | ATR(M15): %.3f JPY\n"
      " [VOL PROFILE]: VPOC: %.3f | VAH: %.3f | VAL: %.3f | LVNs: %d\n"
      " [SPREAD]     : %.3f JPY (5m Avg: %.3f JPY)\n"
      "--------------------------------------------------------\n"
      " [FSM STATE]  : %s\n"
      " [EXPOSURE]   : %s | Ticket: #%I64u | Lots: %.2f\n"
      "========================================================",
      QUANT_EA_VERSION,
      RiskModeToString(riskSnap.riskMode),
      (riskSnap.ddType == DD_TRAILING_HWM ? "TRAILING_HWM" : "STATIC_INITIAL"),
      (InpUseOnnxModel ? "NATIVE_ONNX" : "DETERMINISTIC_COLLECTION"),
      (g_onnxLabeler.IsModelReady() ? "YES" : "FALLBACK"),
      effOffsetHrs,
      (MQLInfoInteger(MQL_TESTER) ? "TESTER_CFG" : "AUTO_GMT"),
      TimeToString(now, TIME_MINUTES),
      TimeToString(utcNow, TIME_MINUTES),
      KillzoneSessionToString(sessRef.currentSession),
      (sessRef.isTradableRegime ? "YES" : "NO (FLAT/EXHAUSTED)"),
      riskSnap.currentEquity,
      riskSnap.currentBalance,
      riskSnap.dayStartReference,
      riskSnap.highWaterMark,
      riskSnap.dailyDrawdownPct,
      riskSnap.dailyBreakerLimitPct,
      riskSnap.totalDrawdownPct,
      riskSnap.totalBreakerLimitPct,
      riskSnap.dailyRealizedPnLUSD,
      riskSnap.dailyRealizedPnLPct,
      riskSnap.weeklyRealizedProfitUSD,
      (riskSnap.tradingHaltedToday || riskSnap.permanentLockout)
         ? ("HALTED: " + BreachReasonToString(riskSnap.activeBreachReason))
         : "ACTIVE_NOMINAL",
      riskSnap.consecutiveLossesToday,
      sessRef.asianLow,
      sessRef.asianHigh,
      sessRef.asianRange,
      sessRef.adr20,
      sessRef.pdh,
      sessRef.pdl,
      sessRef.atrM15Current,
      vpSnap.vpoc,
      vpSnap.vah,
      vpSnap.val,
      vpSnap.lvnCount,
      riskSnap.currentSpreadUSD,
      riskSnap.rollingAvgSpreadUSD,
      SweepStateToString(g_sweepEngine.GetCurrentState()),
      (tradeCtx.hasOpenPosition ? "OPEN_POSITION" : (tradeCtx.hasPendingOrder ? "PENDING_LIMIT" : "FLAT")),
      (tradeCtx.hasOpenPosition ? tradeCtx.positionTicket : tradeCtx.pendingOrderTicket),
      tradeCtx.remainingLots
   );

   Comment(hud);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_logger.Init(_Symbol,
                     InpMagicNumber,
                     InpLogLevel,
                     InpEnableCsvTelemetry,
                     InpBrokerGMTOffsetHours,
                     InpCsvUseCommonFolder,
                     "usdjpy"))
     {
      Print("[USDJPY-SNIPER][ERROR] Logger initialization failed.");
      return INIT_FAILED;
     }

   if(!g_equityGuard.Init(_Symbol,
                          InpMagicNumber,
                          InpRiskMode,
                          InpDrawdownType,
                          InpBrokerGMTOffsetHours,
                          InpEnableCalendarFilter,
                          InpMaxSpreadMultiplier,
                          InpHardMaxSpreadUSD,
                          &g_logger))
     {
      g_logger.Critical("Layer 3 EquityGuard initialization failed.");
      return INIT_FAILED;
     }

   if(!g_positionSizer.Init(_Symbol,
                            InpRiskMode,
                            InpCommissionPerLotRoundTurn,
                            &g_equityGuard,
                            &g_logger,
                            InpPropTier2RiskPct,
                            InpPropTier1RiskPct,
                            InpGrowthTier2RiskPct,
                            InpGrowthTier1RiskPct))
     {
      g_logger.Critical("Layer 3 PositionSizer initialization failed.");
      return INIT_FAILED;
     }

   if(!g_executionManager.Init(_Symbol,
                               InpMagicNumber,
                               InpMaxSlippagePoints,
                               InpCommissionPerLotRoundTurn,
                               InpEnableVerticalTimeBarrier,
                               InpVerticalBarrierHours,
                               &g_equityGuard,
                               &g_positionSizer,
                               &g_logger))
     {
      g_logger.Critical("Layer 3 ExecutionManager initialization failed.");
      return INIT_FAILED;
     }

   if(!g_sessionLevels.Init(_Symbol,
                            InpBrokerGMTOffsetHours,
                            &g_logger,
                            0.15,
                            1.50))
     {
      g_logger.Critical("Layer 1 SessionLevels initialization failed.");
      return INIT_FAILED;
     }

   if(!g_volumeProfile.Init(_Symbol,
                            InpBrokerGMTOffsetHours,
                            &g_logger,
                            InpVPBinSizeUSD,
                            VP_VALUE_AREA_PCT,
                            VP_LVN_THRESHOLD_RATIO))
     {
      g_logger.Critical("Layer 1 VolumeProfile initialization failed.");
      return INIT_FAILED;
     }

   if(!g_sweepEngine.Init(_Symbol,
                          InpBrokerGMTOffsetHours,
                          &g_sessionLevels,
                          &g_volumeProfile,
                          &g_logger,
                          InpMinSweepAtrRatio,
                          InpMaxSweepAtrRatio,
                          InpMinAbsorptionVolRatio,
                          InpMaxReclaimBarsM5,
                          InpLimitExpiryBarsM5))
     {
      g_logger.Critical("Layer 1 SweepSignalEngine initialization failed.");
      return INIT_FAILED;
     }

   if(!g_featureExtractor.Init(_Symbol,
                               InpBrokerGMTOffsetHours,
                               &g_sessionLevels,
                               &g_volumeProfile,
                               &g_logger))
     {
      g_logger.Critical("Layer 2 FeatureExtractor initialization failed.");
      return INIT_FAILED;
     }

   if(!g_onnxLabeler.InitFromBuffer(ExtOnnxModel,
                                    InpUseOnnxModel,
                                    &g_logger,
                                    InpOnnxTier2Threshold,
                                    InpOnnxTier1Threshold))
     {
      if(InpUseOnnxModel)
         g_logger.Warn("ONNX initialization returned warning; deterministic fallback scorer active.");
     }

   datetime srvTime = (TimeTradeServer() > 0) ? TimeTradeServer() : TimeCurrent();
   datetime gmtTime = ResolveCurrentUTCTime(InpBrokerGMTOffsetHours);
   double   effOff  = ResolveEffectiveGMTOffsetHours(InpBrokerGMTOffsetHours);
   g_logger.Info(StringFormat(
      "Server Time: %s | GMT Time: %s | Effective GMT Offset (hours): %+.2f [%s]",
      TimeToString(srvTime, TIME_DATE|TIME_SECONDS),
      TimeToString(gmtTime, TIME_DATE|TIME_SECONDS),
      effOff,
      (MQLInfoInteger(MQL_TESTER) ? "StrategyTesterFallback" : "AutoDetectedLive")));

   g_logger.Info(StringFormat(
      "USDJPY_Sniper_ONNX v%s Initialized Successfully [Mode=%s | UseONNX=%s]",
      QUANT_EA_VERSION, RiskModeToString(InpRiskMode), (InpUseOnnxModel ? "TRUE" : "FALSE")));

   UpdateChartHUD();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_onnxLabeler.Deinit();
   g_featureExtractor.Deinit();
   g_sessionLevels.Deinit();

   if(InpShowChartHUD)
      Comment("");

   g_logger.Info(StringFormat("USDJPY_Sniper_ONNX deinitialized (reason=%d).", reason));
  }

//+------------------------------------------------------------------+
//| Expert tick function (Sub-Millisecond Hot Path)                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_equityGuard.CheckEmergencyBreach())
     {
      UpdateChartHUD();
      return;
     }

   g_executionManager.ManageActiveTradesOnTick();

   bool hasActiveExposure = g_executionManager.HasActiveExposure();
   g_sweepEngine.NotifyPendingOrderState(hasActiveExposure);

   if(hasActiveExposure)
     {
      UpdateChartHUD();
      return;
     }

   SSweepCandidateSetup candidateSetup;
   if(!g_sweepEngine.EvaluateOnM5BarClose(false, candidateSetup))
     {
      UpdateChartHUD();
      return;
     }

   SStationaryFeatures features;
   double currentSpreadUSD = g_equityGuard.GetCurrentSpreadUSD();

   if(!g_featureExtractor.ExtractFeatures(candidateSetup, currentSpreadUSD, features))
     {
      g_logger.Warn("FeatureExtractor failed to compute 12 stationary features for candidate setup.");
      UpdateChartHUD();
      return;
     }

   SOnnxPrediction prediction;
   g_onnxLabeler.PredictProbability(features, prediction);

   g_logger.WriteSetupTelemetryCSV(candidateSetup, features, prediction, "SIGNAL_TRIGGERED");

   if(prediction.riskTier == 0 || prediction.winProbability < InpOnnxTier2Threshold)
     {
      g_logger.Info(StringFormat(
         "Setup #%I64u Filtered by ONNX Meta-Labeler [P(Win)=%.4f < %.2f threshold]",
         candidateSetup.setupId, prediction.winProbability, InpOnnxTier2Threshold));
      UpdateChartHUD();
      return;
     }

   ENUM_BREACH_REASON blockReason = BREACH_NONE;
   if(!g_equityGuard.IsNewEntryPermitted(blockReason))
     {
      g_logger.Warn(StringFormat(
         "Setup #%I64u Blocked by EquityGuard [%s]",
         candidateSetup.setupId, BreachReasonToString(blockReason)));
      UpdateChartHUD();
      return;
     }

   SLotCalculationResult lotResult;
   if(!g_positionSizer.CalculateSniperLots(candidateSetup.direction,
                                           candidateSetup.entryLimitPrice,
                                           candidateSetup.stopLossPrice,
                                           prediction.winProbability,
                                           lotResult))
     {
      g_logger.Warn(StringFormat(
         "Setup #%I64u Rejected by PositionSizer: %s",
         candidateSetup.setupId, lotResult.diagnosticNote));
      UpdateChartHUD();
      return;
     }

   if(g_executionManager.PlaceSniperLimitOrder(candidateSetup, features, prediction, lotResult))
     {
      g_sweepEngine.NotifyPendingOrderState(true);
     }

   UpdateChartHUD();
  }

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_executionManager.OnTradeTransaction(trans, request, result);

   ENUM_SIGNAL_DIRECTION closedDir = SIGNAL_NONE;
   double closedR = 0.0;
   if(g_executionManager.ConsumeClosedOutcome(closedDir, closedR))
      g_sweepEngine.NotifyTradeOutcome(closedDir, closedR, ResolveCurrentUTCTime(InpBrokerGMTOffsetHours));
  }

//+------------------------------------------------------------------+
//| Tester function: Institutional Prop-Safe Optimization Criterion  |
//+------------------------------------------------------------------+
double OnTester()
  {
   double netProfit      = TesterStatistics(STAT_PROFIT);
   double profitFactor   = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpeRatio    = TesterStatistics(STAT_SHARPE_RATIO);
   double maxEquityDDPct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double totalTrades    = TesterStatistics(STAT_TRADES);

   if(maxEquityDDPct >= HARD_MAX_TOTAL_DD_CEILING_PCT || totalTrades < 10.0 || netProfit <= 0.0)
      return 0.0;

   double ddPenalty = (maxEquityDDPct > PROP_TOTAL_DD_BREAKER_PCT) ? 0.25 : 1.0;
   double score     = (netProfit * MathMin(profitFactor, 5.0) * MathMax(sharpeRatio, 0.5)) /
                      MathMax(maxEquityDDPct, 0.50);

   return score * ddPenalty;
  }
//+------------------------------------------------------------------+
