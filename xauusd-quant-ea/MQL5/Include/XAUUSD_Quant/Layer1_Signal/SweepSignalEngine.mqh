//+------------------------------------------------------------------+
//|                                            SweepSignalEngine.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 1 Signal: 4-State FSM (Sweep -> Reclaim/MSS -> FVG Limit) |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_SWEEP_SIGNAL_ENGINE_MQH
#define XAUUSD_QUANT_SWEEP_SIGNAL_ENGINE_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "SessionLevels.mqh"
#include "VolumeProfile.mqh"

//+------------------------------------------------------------------+
//| Internal Active Sweep Tracking Context                           |
//+------------------------------------------------------------------+
struct SActiveSweepTracker
  {
   bool                  active;
   datetime              sweepM5BarTime;
   int                   m5BarsElapsed;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_LIQUIDITY_TYPE   poolType;
   double                levelPrice;
   double                extremePrice;
   double                maxSweepDepthUSD;
   double                sweepBarTickVol;
   double                sma20TickVol;
   double                sweepBarWickUSD;
   double                sweepBarRangeUSD;

   void Reset()
     {
      active           = false;
      sweepM5BarTime   = 0;
      m5BarsElapsed    = 0;
      direction        = SIGNAL_NONE;
      poolType         = LIQ_NONE;
      levelPrice       = 0.0;
      extremePrice     = 0.0;
      maxSweepDepthUSD = 0.0;
      sweepBarTickVol  = 0.0;
      sma20TickVol     = 0.0;
      sweepBarWickUSD  = 0.0;
      sweepBarRangeUSD = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| CSweepSignalEngine: Deterministic 4-State Institutional Engine   |
//+------------------------------------------------------------------+
class CSweepSignalEngine
  {
private:
   string               m_symbol;
   int                  m_brokerGMTOffset;
   double               m_minSweepAtrRatio;
   double               m_maxSweepAtrRatio;
   double               m_minRelVolumeRatio;
   int                  m_maxReclaimBarsM5;
   int                  m_limitExpiryBarsM5;

   CSessionLevels      *m_sessionLevels;
   CVolumeProfile      *m_volumeProfile;
   CQuantLogger        *m_logger;

   ENUM_SWEEP_STATE     m_state;
   SActiveSweepTracker  m_tracker;
   SSweepCandidateSetup m_latestSetup;
   ulong                m_nextSetupSequenceId;
   datetime             m_lastEvaluatedM5BarTime;

   //--- Compute 20-bar Simple Moving Average of M5 Tick Volume (at bar shift)
   double               ComputeM5TickVolumeSMA20(const int startShift = 1) const
     {
      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, startShift, 20, m5);
      if(copied <= 0)
         return 1.0;

      double sumVol = 0.0;
      for(int i = 0; i < copied; i++)
         sumVol += (double)m5[i].tick_volume;

      return MathMax(1.0, sumVol / (double)copied);
     }

   //--- Count number of M1 bars that traded beyond the swept liquidity level over the last 20 minutes
   int                  CountM1BarsBeyondLevel(const ENUM_SIGNAL_DIRECTION direction,
                                               const double sweptLevelPrice,
                                               const datetime sinceM5BarTime) const
     {
      MqlRates m1[];
      ArraySetAsSeries(m1, true);
      int copied = CopyRates(m_symbol, PERIOD_M1, 1, 25, m1);
      if(copied <= 0)
         return 1;

      int count = 0;
      for(int i = 0; i < copied; i++)
        {
         if(m1[i].time < (sinceM5BarTime - 300))
            break;

         if(direction == SIGNAL_LONG && m1[i].low < sweptLevelPrice)
            count++;
         else if(direction == SIGNAL_SHORT && m1[i].high > sweptLevelPrice)
            count++;
        }
      return MathMax(1, count);
     }

   //--- Detect 3-Candle Fair Value Gap (FVG) & Minor Market Structure Shift (MSS) on M5 or M1
   bool                 DetectReversalFVGAndMSS(const ENUM_SIGNAL_DIRECTION direction,
                                                const double sweptLevelPrice,
                                                const SVolumeProfileSnapshot &vp,
                                                bool &outHasFVG,
                                                double &outFvgProximal,
                                                double &outFvgDistal,
                                                bool &outHasMSS,
                                                double &outMssLevel) const
     {
      outHasFVG      = false;
      outFvgProximal = 0.0;
      outFvgDistal   = 0.0;
      outHasMSS      = false;
      outMssLevel    = 0.0;

      // 1. Inspect M5 bars [1..4] for 3-candle FVG and structural displacement
      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      int copiedM5 = CopyRates(m_symbol, PERIOD_M5, 1, 6, m5);
      if(copiedM5 >= 4)
        {
         if(direction == SIGNAL_LONG)
           {
            // Bullish M5 3-candle FVG: Low of bar[1] > High of bar[3]
            if(m5[1].low > m5[3].high)
              {
               outHasFVG      = true;
               outFvgProximal = m5[1].low;
               outFvgDistal   = m5[3].high;
              }
            // Bullish Minor MSS on M5: bar[1] closes above high of prior down-candle
            double priorHigh = MathMax(m5[2].high, m5[3].high);
            if(m5[1].close > m5[2].high || m5[1].close > sweptLevelPrice)
              {
               outHasMSS   = true;
               outMssLevel = priorHigh;
              }
           }
         else if(direction == SIGNAL_SHORT)
           {
            // Bearish M5 3-candle FVG: High of bar[1] < Low of bar[3]
            if(m5[1].high < m5[3].low)
              {
               outHasFVG      = true;
               outFvgProximal = m5[1].high;
               outFvgDistal   = m5[3].low;
              }
            // Bearish Minor MSS on M5: bar[1] closes below low of prior up-candle
            double priorLow = MathMin(m5[2].low, m5[3].low);
            if(m5[1].close < m5[2].low || m5[1].close < sweptLevelPrice)
              {
               outHasMSS   = true;
               outMssLevel = priorLow;
              }
           }
        }

      // 2. Inspect M1 bars [1..12] for intrabar M1 3-candle FVG & M1 micro-MSS if M5 FVG not yet formed
      MqlRates m1[];
      ArraySetAsSeries(m1, true);
      int copiedM1 = CopyRates(m_symbol, PERIOD_M1, 1, 12, m1);
      if(copiedM1 >= 6)
        {
         for(int i = 0; i <= copiedM1 - 4; i++)
           {
            if(direction == SIGNAL_LONG)
              {
               if(!outHasFVG && m1[i].low > m1[i + 2].high && m1[i + 1].close > m1[i + 1].open)
                 {
                  outHasFVG      = true;
                  outFvgProximal = m1[i].low;
                  outFvgDistal   = m1[i + 2].high;
                 }
               if(m1[0].close > m1[i + 1].high && m1[i + 1].close < m1[i + 1].open)
                 {
                  outHasMSS   = true;
                  outMssLevel = m1[i + 1].high;
                 }
              }
            else if(direction == SIGNAL_SHORT)
              {
               if(!outHasFVG && m1[i].high < m1[i + 2].low && m1[i + 1].close < m1[i + 1].open)
                 {
                  outHasFVG      = true;
                  outFvgProximal = m1[i].high;
                  outFvgDistal   = m1[i + 2].low;
                 }
               if(m1[0].close < m1[i + 1].low && m1[i + 1].close > m1[i + 1].open)
                 {
                  outHasMSS   = true;
                  outMssLevel = m1[i + 1].low;
                 }
              }
           }
        }

      // 3. Also check clean Value Area Reclaim (reclaim of VAL for Long or VAH for Short)
      bool cleanValueAreaReclaim = false;
      if(vp.isValid && copiedM5 >= 2)
        {
         if(direction == SIGNAL_LONG && m5[0].close >= vp.val && m_tracker.extremePrice < vp.val)
            cleanValueAreaReclaim = true;
         else if(direction == SIGNAL_SHORT && m5[0].close <= vp.vah && m_tracker.extremePrice > vp.vah)
            cleanValueAreaReclaim = true;
        }

      return (outHasFVG || (outHasMSS && cleanValueAreaReclaim) || outHasMSS);
     }

   //--- Construct Sniper Entry, Structural SL [$1.20, $4.00], TP1 @ VPOC, and TP2 @ Opposing Liquidity
   bool                 BuildSniperOrderGeometry(const SVolumeProfileSnapshot &vp,
                                                 const bool hasFVG,
                                                 const double fvgProximal,
                                                 const double fvgDistal,
                                                 const double reclaimClosePrice,
                                                 const int m1BarsOutside,
                                                 const double rejectionWickUSD,
                                                 const double reclaimCandleRangeUSD,
                                                 SSweepCandidateSetup &outSetup)
     {
      outSetup.Reset();

      double atrM5 = m_sessionLevels.GetAtrM5();
      // Structural Stop Loss Buffer: 0.15 + 0.20 * ATR(M5, 14)
      double slBufferUSD = 0.15 + (0.20 * atrM5);

      double structuralSL = (m_tracker.direction == SIGNAL_LONG)
                            ? (m_tracker.extremePrice - slBufferUSD)
                            : (m_tracker.extremePrice + slBufferUSD);
      structuralSL = NormalizeSymbolPrice(m_symbol, structuralSL);

      // Candidate Entry Limit Price: Proximal edge of FVG or reclaimed VAL/VAH / swept level
      double candidateEntry = reclaimClosePrice;
      if(hasFVG && fvgProximal > 0.0)
        {
         candidateEntry = fvgProximal;
        }
      else if(vp.isValid)
        {
         if(m_tracker.direction == SIGNAL_LONG && vp.val > structuralSL && vp.val <= reclaimClosePrice)
            candidateEntry = vp.val;
         else if(m_tracker.direction == SIGNAL_SHORT && vp.vah < structuralSL && vp.vah >= reclaimClosePrice)
            candidateEntry = vp.vah;
         else
            candidateEntry = m_tracker.levelPrice;
        }

      candidateEntry = NormalizeSymbolPrice(m_symbol, candidateEntry);

      // Compute Stop Loss Distance in Dollars
      double slDistanceUSD = (m_tracker.direction == SIGNAL_LONG)
                             ? (candidateEntry - structuralSL)
                             : (structuralSL - candidateEntry);

      // If entry at FVG proximal makes SL wider than $3.50 (or $4.00), refine entry toward distal FVG / swept level
      if(slDistanceUSD > IDEAL_MAX_SL_DISTANCE_USD)
        {
         double refinedEntry = m_tracker.levelPrice;
         if(hasFVG && fvgDistal > 0.0)
            refinedEntry = 0.50 * (fvgProximal + fvgDistal);

         double refinedSLDist = (m_tracker.direction == SIGNAL_LONG)
                                ? (refinedEntry - structuralSL)
                                : (structuralSL - refinedEntry);

         if(refinedSLDist >= IDEAL_MIN_SL_DISTANCE_USD && refinedSLDist <= HARD_MAX_SL_DISTANCE_USD)
           {
            candidateEntry = NormalizeSymbolPrice(m_symbol, refinedEntry);
            slDistanceUSD  = MathAbs(candidateEntry - structuralSL);
           }
        }

      // If SL distance is slightly below $1.20 (too tight for Gold noise), pad structural SL to $1.50 sniper floor
      if(slDistanceUSD > 0.40 && slDistanceUSD < HARD_MIN_SL_DISTANCE_USD)
        {
         slDistanceUSD = IDEAL_MIN_SL_DISTANCE_USD;
         structuralSL  = (m_tracker.direction == SIGNAL_LONG)
                         ? NormalizeSymbolPrice(m_symbol, candidateEntry - slDistanceUSD)
                         : NormalizeSymbolPrice(m_symbol, candidateEntry + slDistanceUSD);
        }

      // Enforce Hard Filter (Section 4.3): Discard if total SL distance < $1.20 or > $4.00
      if(slDistanceUSD < (HARD_MIN_SL_DISTANCE_USD - 1e-5) ||
         slDistanceUSD > (HARD_MAX_SL_DISTANCE_USD + 1e-5))
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat(
               "Candidate setup discarded: SL distance $%.2f outside hard bounds [$%.2f, $%.2f]",
               slDistanceUSD, HARD_MIN_SL_DISTANCE_USD, HARD_MAX_SL_DISTANCE_USD));
         return false;
        }

      // Compute TP1: Session VPOC (must offer at least 1.5R; otherwise use 2.0R fixed)
      double tp1Price = 0.0;
      if(m_tracker.direction == SIGNAL_LONG)
        {
         double vpocRewardUSD = vp.vpoc - candidateEntry;
         if(vp.isValid && vpocRewardUSD >= (1.50 * slDistanceUSD) && vpocRewardUSD <= (4.00 * slDistanceUSD))
            tp1Price = NormalizeSymbolPrice(m_symbol, vp.vpoc);
         else
            tp1Price = NormalizeSymbolPrice(m_symbol, candidateEntry + 2.00 * slDistanceUSD);
        }
      else
        {
         double vpocRewardUSD = candidateEntry - vp.vpoc;
         if(vp.isValid && vpocRewardUSD >= (1.50 * slDistanceUSD) && vpocRewardUSD <= (4.00 * slDistanceUSD))
            tp1Price = NormalizeSymbolPrice(m_symbol, vp.vpoc);
         else
            tp1Price = NormalizeSymbolPrice(m_symbol, candidateEntry - 2.00 * slDistanceUSD);
        }

      // Compute TP2: Opposing session liquidity boundary or structural 3.5R to 5.0R target
      double opposingTarget = m_sessionLevels.GetOpposingLiquidityTarget(
         m_tracker.direction, m_tracker.poolType, candidateEntry, slDistanceUSD);
      double tp2Price = NormalizeSymbolPrice(m_symbol, opposingTarget);

      // Ensure TP2 is strictly beyond TP1
      if(m_tracker.direction == SIGNAL_LONG && tp2Price <= tp1Price)
         tp2Price = NormalizeSymbolPrice(m_symbol, candidateEntry + 3.50 * slDistanceUSD);
      else if(m_tracker.direction == SIGNAL_SHORT && tp2Price >= tp1Price)
         tp2Price = NormalizeSymbolPrice(m_symbol, candidateEntry - 3.50 * slDistanceUSD);

      m_nextSetupSequenceId++;
      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);

      outSetup.setupId                = (ulong)utcNow * 100 + (m_nextSetupSequenceId % 100);
      outSetup.sweepBarTime           = m_tracker.sweepM5BarTime;
      outSetup.reclaimBarTime         = iTime(m_symbol, PERIOD_M5, 1);
      outSetup.signalTimeUTC          = utcNow;
      outSetup.direction              = m_tracker.direction;
      outSetup.sweptPoolType          = m_tracker.poolType;
      outSetup.sweptLevelPrice        = m_tracker.levelPrice;
      outSetup.sweepExtremePrice      = m_tracker.extremePrice;
      outSetup.sweepDepthUSD          = m_tracker.maxSweepDepthUSD;
      outSetup.rejectionWickUSD       = rejectionWickUSD;
      outSetup.reclaimCandleRangeUSD  = MathMax(0.01, reclaimCandleRangeUSD);
      outSetup.m1BarsOutsideLevel     = m1BarsOutside;
      outSetup.sweepM5TickVolume      = m_tracker.sweepBarTickVol;
      outSetup.sma20M5TickVolume      = m_tracker.sma20TickVol;
      outSetup.hasFVG                 = hasFVG;
      outSetup.fvgProximalPrice       = fvgProximal;
      outSetup.fvgDistalPrice         = fvgDistal;
      outSetup.hasMSS                 = true;
      outSetup.entryLimitPrice        = candidateEntry;
      outSetup.stopLossPrice          = structuralSL;
      outSetup.slDistanceUSD          = slDistanceUSD;
      outSetup.tp1Price               = tp1Price;
      outSetup.tp2Price               = tp2Price;
      outSetup.vpocAtSignal           = vp.vpoc;
      outSetup.vahAtSignal            = vp.vah;
      outSetup.valAtSignal            = vp.val;
      outSetup.opposingLiquidityPrice = opposingTarget;
      outSetup.expiryM5Bars           = m_limitExpiryBarsM5;
      outSetup.isValid                = true;

      return true;
     }

public:
                        CSweepSignalEngine()
     {
      m_symbol                 = _Symbol;
      m_brokerGMTOffset        = 2;
      m_minSweepAtrRatio       = 0.15;
      m_maxSweepAtrRatio       = 0.65;
      m_minRelVolumeRatio      = 1.50;
      m_maxReclaimBarsM5       = 3;
      m_limitExpiryBarsM5      = 3;

      m_sessionLevels          = NULL;
      m_volumeProfile          = NULL;
      m_logger                 = NULL;

      m_state                  = STATE_IDLE;
      m_nextSetupSequenceId    = 0;
      m_lastEvaluatedM5BarTime = 0;
      m_tracker.Reset();
      m_latestSetup.Reset();
     }

                       ~CSweepSignalEngine() {}

   //--- Initialize Layer 1 Sweep Signal Engine
   bool                 Init(const string symbol,
                             const int brokerGMTOffsetHours,
                             CSessionLevels *sessionLevels,
                             CVolumeProfile *volumeProfile,
                             CQuantLogger *logger,
                             const double minSweepAtrRatio  = 0.15,
                             const double maxSweepAtrRatio  = 0.65,
                             const double minRelVolumeRatio = 1.50,
                             const int maxReclaimBarsM5     = 3,
                             const int limitExpiryBarsM5    = 3)
     {
      m_symbol            = symbol;
      m_brokerGMTOffset   = brokerGMTOffsetHours;
      m_sessionLevels     = sessionLevels;
      m_volumeProfile     = volumeProfile;
      m_logger            = logger;

      m_minSweepAtrRatio  = (minSweepAtrRatio  > 0.01 ? minSweepAtrRatio  : 0.15);
      m_maxSweepAtrRatio  = (maxSweepAtrRatio  > m_minSweepAtrRatio ? maxSweepAtrRatio : 0.65);
      m_minRelVolumeRatio = (minRelVolumeRatio > 0.50 ? minRelVolumeRatio : 1.50);
      m_maxReclaimBarsM5  = (maxReclaimBarsM5  >= 1 ? maxReclaimBarsM5 : 3);
      m_limitExpiryBarsM5 = (limitExpiryBarsM5 >= 1 ? limitExpiryBarsM5 : 3);

      m_state = STATE_IDLE;
      m_tracker.Reset();
      m_latestSetup.Reset();
      return (m_sessionLevels != NULL && m_volumeProfile != NULL);
     }

   //--- Synchronize FSM state with ExecutionManager's pending order / open position status
   void                 NotifyPendingOrderState(const bool hasPendingOrOpenTrade)
     {
      if(hasPendingOrOpenTrade)
        {
         m_state = STATE_PENDING_LIMIT;
        }
      else if(m_state == STATE_PENDING_LIMIT || m_state == STATE_RECLAIM_CONFIRMED)
        {
         m_state = STATE_IDLE;
         m_tracker.Reset();
        }
     }

   //+------------------------------------------------------------------+
   //| EvaluateOnM5BarClose                                             |
   //| Executes the 4-state deterministic state machine on each new     |
   //| M5 bar close (with intrabar M1 Volume Profile & FVG precision).  |
   //| Returns true when STATE_RECLAIM_CONFIRMED produces a valid       |
   //| SSweepCandidateSetup ready for Layer 2 ONNX Meta-Labeling.       |
   //+------------------------------------------------------------------+
   bool                 EvaluateOnM5BarClose(const bool hasActiveExposure,
                                             SSweepCandidateSetup &outCandidateSetup)
     {
      outCandidateSetup.Reset();

      if(m_sessionLevels == NULL || m_volumeProfile == NULL)
         return false;

      // Keep state synced with active broker exposure
      NotifyPendingOrderState(hasActiveExposure);
      if(hasActiveExposure)
         return false;

      // Only evaluate once per closed M5 bar
      datetime currentM5BarTime = iTime(m_symbol, PERIOD_M5, 0);
      if(currentM5BarTime == 0 || currentM5BarTime == m_lastEvaluatedM5BarTime)
         return false;

      m_lastEvaluatedM5BarTime = currentM5BarTime;

      // Refresh Layer 1 Reference Levels and Intraday M1 Volume Profile
      m_sessionLevels.Update();
      m_volumeProfile.Update(false);

      SSessionReference      sessionRef;
      SVolumeProfileSnapshot vpSnap;
      m_sessionLevels.GetSessionReference(sessionRef);
      m_volumeProfile.GetSnapshot(vpSnap);

      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);

      // Stand down outside London (07:00-10:30 UTC) and New York (12:30-16:00 UTC) Killzones
      // or when Flat/Exhausted Market Filter is triggered
      if(!m_sessionLevels.IsInActiveKillzone(utcNow) || !sessionRef.isTradableRegime)
        {
         if(m_state == STATE_SWEEP_DETECTED)
           {
            m_state = STATE_IDLE;
            m_tracker.Reset();
           }
         return false;
        }

      // Copy the just-closed M5 bar (shift 1) and prior bars
      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      if(CopyRates(m_symbol, PERIOD_M5, 1, 5, m5) < 4)
         return false;

      double closedHigh   = m5[0].high;
      double closedLow    = m5[0].low;
      double closedOpen   = m5[0].open;
      double closedClose  = m5[0].close;
      double closedRange  = MathMax(0.01, closedHigh - closedLow);
      double closedVol    = (double)m5[0].tick_volume;
      double sma20Vol     = ComputeM5TickVolumeSMA20(1);

      double atrM15       = m_sessionLevels.GetAtrM15();
      double minPierceUSD = m_minSweepAtrRatio * atrM15;
      double maxPierceUSD = m_maxSweepAtrRatio * atrM15;

      // ================================================================
      // STEP 1: STATE_IDLE -> Check for Liquidity Pool or External LVN Sweep
      // ================================================================
      if(m_state == STATE_IDLE)
        {
         SLiquidityPool        sweptPool;
         ENUM_SIGNAL_DIRECTION sweepDir   = SIGNAL_NONE;
         double                sweepDepth = 0.0;

         bool foundPoolSweep = m_sessionLevels.FindSweptLiquidityPool(
            closedHigh, closedLow, minPierceUSD, maxPierceUSD,
            sweptPool, sweepDir, sweepDepth);

         // If no primary pool swept, check for spike into an external LVN outside [VAL, VAH]
         if(!foundPoolSweep && vpSnap.isValid)
           {
            double extLvnPrice = 0.0;
            // Check Bearish spike above VAH into upper external LVN
            if(closedHigh > vpSnap.vah &&
               vpSnap.FindNearestExternalLVN(closedHigh, true, extLvnPrice))
              {
               double lvnPierce = closedHigh - extLvnPrice;
               if(lvnPierce >= minPierceUSD && lvnPierce <= maxPierceUSD)
                 {
                  sweptPool.Reset();
                  sweptPool.price    = extLvnPrice;
                  sweptPool.poolType = LIQ_EXTERNAL_LVN_HIGH;
                  sweepDir           = SIGNAL_SHORT;
                  sweepDepth         = lvnPierce;
                  foundPoolSweep     = true;
                 }
              }
            // Check Bullish spike below VAL into lower external LVN
            if(!foundPoolSweep && closedLow < vpSnap.val &&
               vpSnap.FindNearestExternalLVN(closedLow, false, extLvnPrice))
              {
               double lvnPierce = extLvnPrice - closedLow;
               if(lvnPierce >= minPierceUSD && lvnPierce <= maxPierceUSD)
                 {
                  sweptPool.Reset();
                  sweptPool.price    = extLvnPrice;
                  sweptPool.poolType = LIQ_EXTERNAL_LVN_LOW;
                  sweepDir           = SIGNAL_LONG;
                  sweepDepth         = lvnPierce;
                  foundPoolSweep     = true;
                 }
              }
           }

         if(foundPoolSweep && sweepDir != SIGNAL_NONE)
           {
            m_tracker.Reset();
            m_tracker.active           = true;
            m_tracker.sweepM5BarTime   = m5[0].time;
            m_tracker.m5BarsElapsed    = 1;
            m_tracker.direction        = sweepDir;
            m_tracker.poolType         = sweptPool.poolType;
            m_tracker.levelPrice       = sweptPool.price;
            m_tracker.extremePrice     = (sweepDir == SIGNAL_LONG) ? closedLow : closedHigh;
            m_tracker.maxSweepDepthUSD = sweepDepth;
            m_tracker.sweepBarTickVol  = closedVol;
            m_tracker.sma20TickVol     = sma20Vol;
            m_tracker.sweepBarRangeUSD = closedRange;
            m_tracker.sweepBarWickUSD  = (sweepDir == SIGNAL_LONG)
                                         ? (MathMin(closedOpen, closedClose) - closedLow)
                                         : (closedHigh - MathMax(closedOpen, closedClose));

            m_state = STATE_SWEEP_DETECTED;

            if(m_logger != NULL)
               m_logger.Debug(StringFormat(
                  "FSM -> STATE_SWEEP_DETECTED [%s | Level=%s @ %.2f | Extreme=%.2f | Depth=$%.2f | RelVol=%.2fx]",
                  DirectionToString(sweepDir), LiquidityTypeToString(sweptPool.poolType),
                  sweptPool.price, m_tracker.extremePrice, sweepDepth, closedVol / sma20Vol));
           }
        }
      // ================================================================
      // Update Ongoing Sweep if already in STATE_SWEEP_DETECTED
      // ================================================================
      else if(m_state == STATE_SWEEP_DETECTED)
        {
         m_tracker.m5BarsElapsed++;

         // Update extreme wick if current bar extends sweep slightly while remaining <= 0.65 * ATR(M15, 14)
         if(m_tracker.direction == SIGNAL_LONG && closedLow < m_tracker.extremePrice)
           {
            double newDepth = m_tracker.levelPrice - closedLow;
            if(newDepth > maxPierceUSD)
              {
               // Price blew straight through the level (> 0.65 * ATR_M15) -> breakout, abort sweep
               m_sessionLevels.MarkPoolSwept(m_tracker.poolType, m_tracker.levelPrice, m5[0].time);
               m_state = STATE_IDLE;
               m_tracker.Reset();
               return false;
              }
            m_tracker.extremePrice     = closedLow;
            m_tracker.maxSweepDepthUSD = newDepth;
           }
         else if(m_tracker.direction == SIGNAL_SHORT && closedHigh > m_tracker.extremePrice)
           {
            double newDepth = closedHigh - m_tracker.levelPrice;
            if(newDepth > maxPierceUSD)
              {
               m_sessionLevels.MarkPoolSwept(m_tracker.poolType, m_tracker.levelPrice, m5[0].time);
               m_state = STATE_IDLE;
               m_tracker.Reset();
               return false;
              }
            m_tracker.extremePrice     = closedHigh;
            m_tracker.maxSweepDepthUSD = newDepth;
           }

         if(closedVol > m_tracker.sweepBarTickVol)
           {
            m_tracker.sweepBarTickVol = closedVol;
            m_tracker.sma20TickVol    = sma20Vol;
           }
        }

      // ================================================================
      // STEP 2: STATE_SWEEP_DETECTED -> Evaluate Institutional Absorption & Reclaim
      // (May confirm on the sweep bar itself if it closed back inside, or within 3 M5 bars)
      // ================================================================
      if(m_state == STATE_SWEEP_DETECTED && m_tracker.active)
        {
         // Expire sweep if no reclaim within 3 M5 bars
         if(m_tracker.m5BarsElapsed > m_maxReclaimBarsM5)
           {
            m_sessionLevels.MarkPoolSwept(m_tracker.poolType, m_tracker.levelPrice, m5[0].time);
            m_state = STATE_IDLE;
            m_tracker.Reset();
            return false;
           }

         // Condition A: M5 candle closes back inside the swept liquidity level / Value Area
         bool closedBackInside = false;
         if(m_tracker.direction == SIGNAL_LONG)
           {
            closedBackInside = (closedClose > m_tracker.levelPrice) ||
                               (vpSnap.isValid && closedClose > vpSnap.val && m_tracker.extremePrice < vpSnap.val);
           }
         else if(m_tracker.direction == SIGNAL_SHORT)
           {
            closedBackInside = (closedClose < m_tracker.levelPrice) ||
                               (vpSnap.isValid && closedClose < vpSnap.vah && m_tracker.extremePrice > vpSnap.vah);
           }

         // Condition B: Sweep or reclaim bar exhibits TickVolume >= 1.5 * SMA(TickVolume, 20)
         double maxVolObserved = MathMax(m_tracker.sweepBarTickVol, closedVol);
         double relTickVolume  = maxVolObserved / MathMax(1.0, m_tracker.sma20TickVol);
         bool   hasAbsorption  = (relTickVolume >= m_minRelVolumeRatio);

         // Condition C: Minor Market Structure Shift (MSS) + 3-Candle FVG or clean VAH/VAL reclaim
         bool   hasFVG      = false;
         double fvgProximal = 0.0;
         double fvgDistal   = 0.0;
         bool   hasMSS      = false;
         double mssLevel    = 0.0;
         bool   hasStructureShift = false;

         if(closedBackInside && hasAbsorption)
           {
            hasStructureShift = DetectReversalFVGAndMSS(
               m_tracker.direction, m_tracker.levelPrice, vpSnap,
               hasFVG, fvgProximal, fvgDistal, hasMSS, mssLevel);
           }

         if(closedBackInside && hasAbsorption && hasStructureShift)
           {
            m_state = STATE_RECLAIM_CONFIRMED;

            int m1BarsOutside = CountM1BarsBeyondLevel(
               m_tracker.direction, m_tracker.levelPrice, m_tracker.sweepM5BarTime);

            double currentWickUSD = (m_tracker.direction == SIGNAL_LONG)
                                    ? (MathMin(closedOpen, closedClose) - closedLow)
                                    : (closedHigh - MathMax(closedOpen, closedClose));
            double bestWickUSD    = MathMax(m_tracker.sweepBarWickUSD, currentWickUSD);
            double bestRangeUSD   = (bestWickUSD == m_tracker.sweepBarWickUSD)
                                    ? m_tracker.sweepBarRangeUSD
                                    : closedRange;

            // Mark liquidity pool as swept so it won't fire duplicate signals today
            m_sessionLevels.MarkPoolSwept(m_tracker.poolType, m_tracker.levelPrice, m5[0].time);

            // Build Sniper Limit Order Geometry
            if(BuildSniperOrderGeometry(vpSnap, hasFVG, fvgProximal, fvgDistal,
                                        closedClose, m1BarsOutside, bestWickUSD, bestRangeUSD,
                                        m_latestSetup))
              {
               outCandidateSetup = m_latestSetup;
               if(m_logger != NULL)
                  m_logger.Info(StringFormat(
                     "FSM -> STATE_RECLAIM_CONFIRMED [SetupID=%I64u | %s | Pool=%s | Entry=%.2f | SL=%.2f ($%.2f) | TP1=%.2f | TP2=%.2f]",
                     outCandidateSetup.setupId,
                     DirectionToString(outCandidateSetup.direction),
                     LiquidityTypeToString(outCandidateSetup.sweptPoolType),
                     outCandidateSetup.entryLimitPrice,
                     outCandidateSetup.stopLossPrice,
                     outCandidateSetup.slDistanceUSD,
                     outCandidateSetup.tp1Price,
                     outCandidateSetup.tp2Price));

               m_tracker.Reset();
               return true;
              }
            else
              {
               // Geometry rejected by hard SL distance bounds [$1.20, $4.00] -> return to STATE_IDLE
               m_state = STATE_IDLE;
               m_tracker.Reset();
               return false;
              }
           }
        }

      return false;
     }

   //--- Accessors
   ENUM_SWEEP_STATE     GetCurrentState() const { return m_state; }
  };

#endif // XAUUSD_QUANT_SWEEP_SIGNAL_ENGINE_MQH
