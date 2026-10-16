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

   ENUM_SWEEP_STATE      m_state;
   SActiveSweepTracker   m_tracker;
   SSweepCandidateSetup  m_latestSetup;
   ulong                 m_nextSetupSequenceId;
   datetime              m_lastEvaluatedM5BarTime;
   ENUM_SIGNAL_DIRECTION m_lastClosedDirection;
   datetime              m_lastClosedTimeUTC;
   int                   m_lastClosedCooldownSec;

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

   //--- Compute H1 / H4 Macro Trend Bias (+1 = Bullish, -1 = Bearish, 0 = Neutral) per Clause 1
   int                  GetMacroTrendBias() const
     {
      MqlRates h1[], h4[];
      ArraySetAsSeries(h1, true);
      ArraySetAsSeries(h4, true);

      int copiedH1 = CopyRates(m_symbol, PERIOD_H1, 1, 34, h1);
      int copiedH4 = CopyRates(m_symbol, PERIOD_H4, 1, 20, h4);
      if(copiedH1 < 34 || copiedH4 < 20)
         return 0;

      double sumH1 = 0.0;
      for(int i = 0; i < 34; i++)
         sumH1 += h1[i].close;
      double sma34H1 = sumH1 / 34.0;

      double sumH4 = 0.0;
      for(int i = 0; i < 20; i++)
         sumH4 += h4[i].close;
      double sma20H4 = sumH4 / 20.0;

      bool h4Bull = (h4[0].close >= sma20H4);
      bool h1Bull = (h1[0].close >= sma34H1);
      bool h4Bear = (h4[0].close < sma20H4 && h4[0].close < h4[5].close);
      bool h1Bear = (h1[0].close < sma34H1 && h1[0].close < h1[8].close);

      if(h4Bull || h1Bull)
         return 1;
      if(h4Bear && h1Bear)
         return -1;
      return 0;
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

      // 1. Inspect M5 bars [0..3] (shift 1..4) for 3-candle FVG and structural displacement
      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      int copiedM5 = CopyRates(m_symbol, PERIOD_M5, 1, 6, m5);
      if(copiedM5 < 4)
         return false;

      double bar0Range = MathMax(0.01, m5[0].high - m5[0].low);
      double lowerWick = MathMin(m5[0].open, m5[0].close) - m5[0].low;
      double upperWick = m5[0].high - MathMax(m5[0].open, m5[0].close);

      // Check H1/H4 Macro Regime & UTC Hour alignment
      int macroBias = GetMacroTrendBias();
      bool isCounterTrend = ((direction == SIGNAL_SHORT && macroBias >= 0) ||
                             (direction == SIGNAL_LONG  && macroBias == -1));

      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);
      MqlDateTime dtUTC;
      TimeToStruct(utcNow, dtUTC);
      int  minOfDay          = dtUTC.hour * 60 + dtUTC.min;
      bool isInternalFractal = (m_tracker.poolType == LIQ_M15_SWING_LOW ||
                                m_tracker.poolType == LIQ_M15_SWING_HIGH);

      // During 14:20-14:59 UTC (pre-London Close fixing chop), only trade primary session pools (ASIAN_LOW, PDL, EQUAL_LOWS, EQUAL_HIGHS)
      if(isInternalFractal && minOfDay >= (14 * 60 + 20) && minOfDay < (15 * 60))
         return false;

      if(direction == SIGNAL_LONG)
        {
         // Exclude low-expectancy external LVN long spikes; focus on structural liquidity pools
         if(m_tracker.poolType == LIQ_EXTERNAL_LVN_LOW)
            return false;

         // Reclaim bar must close bullishly (close > open)
         if(m5[0].close <= m5[0].open)
            return false;

         double bestLowerWickRatio = MathMax(lowerWick / bar0Range,
                                             m_tracker.sweepBarWickUSD / MathMax(0.01, m_tracker.sweepBarRangeUSD));

         // In Early London (06:30-09:59 UTC), internal M15_SWING_LOW requires a strong rejection wick (>= 45%)
         // so we don't buy minor internal liquidity on the way down to sweep ASIAN_LOW / PDL
         if(m_tracker.poolType == LIQ_M15_SWING_LOW && dtUTC.hour <= 9 && bestLowerWickRatio < 0.45)
            return false;

         // If fading a confirmed H1/H4 Bearish trend, require strong rejection wick >= 50% and M5 close above bar[1].high
         if(isCounterTrend && (bestLowerWickRatio < 0.50 || m5[0].close <= m5[1].high))
            return false;

         // For M15_SWING_LOW pullback sweeps, require fast 1-2 bar rejection or strong lower wick >= 40%
         if(m_tracker.poolType == LIQ_M15_SWING_LOW && m_tracker.m5BarsElapsed > 2 && bestLowerWickRatio < 0.40)
            return false;

         // Bullish M5 3-candle FVG: Low of bar[0] (shift 1) > High of bar[2] (shift 3)
         if(m5[0].low > m5[2].high)
           {
            outHasFVG      = true;
            outFvgProximal = m5[0].low;
            outFvgDistal   = m5[2].high;
           }
         // Bullish Minor MSS / Reclaim on M5: bar[0] closes above bar[1].high or shows rejection wick >= 28%
         if(m5[0].close > m5[1].high || (m5[0].close > sweptLevelPrice && (lowerWick / bar0Range) >= 0.28))
           {
            outHasMSS   = true;
            outMssLevel = m5[1].high;
           }
        }
      else if(direction == SIGNAL_SHORT)
        {
         // Reclaim bar must close bearishly (close < open)
         if(m5[0].close >= m5[0].open)
            return false;

         double bestUpperWickRatio = MathMax(upperWick / bar0Range,
                                             m_tracker.sweepBarWickUSD / MathMax(0.01, m_tracker.sweepBarRangeUSD));

         // In Early London (06:30-09:59 UTC), internal M15_SWING_HIGH requires strong rejection wick >= 55%
         if(m_tracker.poolType == LIQ_M15_SWING_HIGH && dtUTC.hour <= 9 && bestUpperWickRatio < 0.55)
            return false;

         // Across Gold's macro bull regime, avoid fading single-touch highs (PDH, ASIAN_HIGH, EXTERNAL_LVN_HIGH, M15_SWING_HIGH);
         // restrict shorts strictly to Clustered Equal Highs (LIQ_EQUAL_HIGHS) double/triple-top stop-hunts
         if(m_tracker.poolType != LIQ_EQUAL_HIGHS)
            return false;

         // Bearish M5 3-candle FVG: High of bar[0] (shift 1) < Low of bar[2] (shift 3)
         if(m5[0].high < m5[2].low)
           {
            outHasFVG      = true;
            outFvgProximal = m5[0].high;
            outFvgDistal   = m5[2].low;
           }
         // Bearish Minor MSS / Reclaim on M5: bar[0] closes below bar[1].low or shows rejection wick >= 28%
         if(m5[0].close < m5[1].low || (m5[0].close < sweptLevelPrice && (upperWick / bar0Range) >= 0.28))
           {
            outHasMSS   = true;
            outMssLevel = m5[1].low;
           }
        }

      // 2. Inspect M1 bars [0..11] (shift 1..12) for intrabar M1 3-candle FVG & M1 micro-MSS
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
               if(m1[0].close < m1[i + 1].low && m1[i + 1].open < m1[i + 1].close)
                 {
                  outHasMSS   = true;
                  outMssLevel = m1[i + 1].low;
                 }
              }
           }
        }

      // 3. Also check clean Value Area Reclaim (reclaim of VAL for Long or VAH for Short)
      bool cleanValueAreaReclaim = false;
      if(vp.isValid)
        {
         if(direction == SIGNAL_LONG && m5[0].close >= vp.val && m_tracker.extremePrice < vp.val)
            cleanValueAreaReclaim = true;
         else if(direction == SIGNAL_SHORT && m5[0].close <= vp.vah && m_tracker.extremePrice > vp.vah)
            cleanValueAreaReclaim = true;
        }

      if(isCounterTrend)
         return (outHasMSS && outHasFVG && cleanValueAreaReclaim);

      if(m_tracker.poolType == LIQ_EXTERNAL_LVN_HIGH || m_tracker.poolType == LIQ_EXTERNAL_LVN_LOW)
         return (outHasMSS && cleanValueAreaReclaim && outHasFVG);

      return (outHasMSS && (outHasFVG || cleanValueAreaReclaim));
     }

   //--- Construct Sniper Entry, Structural SL outside sweep extreme, TP1 @ +0.62R, and TP2 @ +2.45R
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

      double atrM5 = MathMax(1.50, m_sessionLevels.GetAtrM5());
      // Structural Stop Loss Buffer: 0.12 + 0.15 * ATR(M5, 14) strictly beyond sweep extreme
      double slBufferUSD = 0.12 + (0.15 * atrM5);

      double structuralSL = (m_tracker.direction == SIGNAL_LONG)
                            ? (m_tracker.extremePrice - slBufferUSD)
                            : (m_tracker.extremePrice + slBufferUSD);
      structuralSL = NormalizeSymbolPrice(m_symbol, structuralSL);

      int  macroBias       = GetMacroTrendBias();
      bool isCounterTrend  = ((m_tracker.direction == SIGNAL_SHORT && macroBias == 1) ||
                              (m_tracker.direction == SIGNAL_LONG  && macroBias == -1));

      // Volatility-stationary sniper SL ceiling: scales with ATR(M5, 14) across $2,600 (2025) to $5,140 (2026)
      double maxImmediateSL = isCounterTrend
                              ? MathMin(HARD_MAX_SL_DISTANCE_USD, MathMax(2.80, 1.35 * atrM5))
                              : MathMin(HARD_MAX_SL_DISTANCE_USD, MathMax(3.80, 1.85 * atrM5));

      // Evaluate SL distance at immediate reclaim close
      double candidateEntry = NormalizeSymbolPrice(m_symbol, reclaimClosePrice);
      double slDistanceUSD  = (m_tracker.direction == SIGNAL_LONG)
                              ? (candidateEntry - structuralSL)
                              : (structuralSL - candidateEntry);

      // Pad structural SL to $1.50 sniper floor if sweep was very tight
      if(slDistanceUSD > 0.30 && slDistanceUSD < IDEAL_MIN_SL_DISTANCE_USD)
        {
         slDistanceUSD = IDEAL_MIN_SL_DISTANCE_USD;
         structuralSL  = (m_tracker.direction == SIGNAL_LONG)
                         ? NormalizeSymbolPrice(m_symbol, candidateEntry - slDistanceUSD)
                         : NormalizeSymbolPrice(m_symbol, candidateEntry + slDistanceUSD);
        }
      else if(slDistanceUSD > maxImmediateSL)
        {
         // Reclaim bar displaced beyond maxImmediateSL (1.85 * ATR_M5).
         // Place a Sniper Pullback Limit Order at FVG proximal / swept level or 1.30 * ATR_M5 from structuralSL
         double pullbackEntry = m_tracker.levelPrice;
         if(hasFVG && fvgProximal > 0.0)
            pullbackEntry = fvgProximal;

         double pullbackSLDist = (m_tracker.direction == SIGNAL_LONG)
                                 ? (pullbackEntry - structuralSL)
                                 : (structuralSL - pullbackEntry);

         if(pullbackSLDist >= IDEAL_MIN_SL_DISTANCE_USD && pullbackSLDist <= maxImmediateSL)
           {
            candidateEntry = NormalizeSymbolPrice(m_symbol, pullbackEntry);
            slDistanceUSD  = pullbackSLDist;
           }
         else
           {
            double targetPullbackSL = isCounterTrend
                                      ? MathMax(2.20, 1.05 * atrM5)
                                      : MathMax(2.65, 1.30 * atrM5);
            slDistanceUSD  = MathMin(maxImmediateSL, targetPullbackSL);
            candidateEntry = (m_tracker.direction == SIGNAL_LONG)
                             ? NormalizeSymbolPrice(m_symbol, structuralSL + slDistanceUSD)
                             : NormalizeSymbolPrice(m_symbol, structuralSL - slDistanceUSD);
           }
        }

      // Enforce Hard Filter: Discard if total SL distance < $1.20 or > $10.50
      if(slDistanceUSD < (HARD_MIN_SL_DISTANCE_USD - 1e-5) ||
         slDistanceUSD > (HARD_MAX_SL_DISTANCE_USD + 1e-5))
        {
         if(m_logger != NULL)
            m_logger.Debug(StringFormat(
               "Candidate setup discarded: SL distance $%.2f outside hard bounds [$%.2f, $%.2f]",
               slDistanceUSD, HARD_MIN_SL_DISTANCE_USD, HARD_MAX_SL_DISTANCE_USD));
         return false;
        }

      // Compute TP1: High-Win-Rate +0.62R Sniper Partial Target (or Session VPOC if within [0.60R, 0.72R])
      double tp1Price = 0.0;
      if(m_tracker.direction == SIGNAL_LONG)
        {
         double vpocRewardUSD = vp.vpoc - candidateEntry;
         if(vp.isValid && vpocRewardUSD >= (0.60 * slDistanceUSD) && vpocRewardUSD <= (0.72 * slDistanceUSD))
            tp1Price = NormalizeSymbolPrice(m_symbol, vp.vpoc);
         else
            tp1Price = NormalizeSymbolPrice(m_symbol, candidateEntry + 0.62 * slDistanceUSD);
        }
      else
        {
         double vpocRewardUSD = candidateEntry - vp.vpoc;
         if(vp.isValid && vpocRewardUSD >= (0.60 * slDistanceUSD) && vpocRewardUSD <= (0.72 * slDistanceUSD))
            tp1Price = NormalizeSymbolPrice(m_symbol, vp.vpoc);
         else
            tp1Price = NormalizeSymbolPrice(m_symbol, candidateEntry - 0.62 * slDistanceUSD);
        }

      // Compute TP2: Opposing session liquidity boundary or structural +3.50R target
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
      m_lastClosedDirection    = SIGNAL_NONE;
      m_lastClosedTimeUTC      = 0;
      m_lastClosedCooldownSec  = 0;
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
      m_symbol                = symbol;
      m_brokerGMTOffset       = brokerGMTOffsetHours;
      m_sessionLevels         = sessionLevels;
      m_volumeProfile         = volumeProfile;
      m_logger                = logger;

      m_minSweepAtrRatio      = (minSweepAtrRatio  > 0.01 ? minSweepAtrRatio  : 0.15);
      m_maxSweepAtrRatio      = (maxSweepAtrRatio  > m_minSweepAtrRatio ? maxSweepAtrRatio : 0.65);
      m_minRelVolumeRatio     = (minRelVolumeRatio > 0.50 ? minRelVolumeRatio : 1.50);
      m_maxReclaimBarsM5      = (maxReclaimBarsM5  >= 1 ? maxReclaimBarsM5 : 3);
      m_limitExpiryBarsM5     = (limitExpiryBarsM5 >= 1 ? limitExpiryBarsM5 : 3);
      m_lastClosedDirection   = SIGNAL_NONE;
      m_lastClosedTimeUTC     = 0;
      m_lastClosedCooldownSec = 0;

      m_state = STATE_IDLE;
      m_tracker.Reset();
      m_latestSetup.Reset();
      return (m_sessionLevels != NULL && m_volumeProfile != NULL);
     }

   //--- Record closed trade outcome to enforce same-direction falling-knife / failed-runner cooldown
   void                 NotifyTradeOutcome(const ENUM_SIGNAL_DIRECTION direction,
                                           const double realizedR,
                                           const datetime closedTimeUTC)
     {
      if(realizedR < 0.0)
        {
         m_lastClosedDirection   = direction;
         m_lastClosedTimeUTC     = closedTimeUTC;
         m_lastClosedCooldownSec = 9000; // 2.5-hour same-direction cooldown after a stop-out loss
        }
      else if(realizedR < 0.40)
        {
         m_lastClosedDirection   = direction;
         m_lastClosedTimeUTC     = closedTimeUTC;
         m_lastClosedCooldownSec = 5400; // 1.5-hour same-direction cooldown after a runner reversal at breakeven
        }
      else
        {
         m_lastClosedDirection   = SIGNAL_NONE;
         m_lastClosedTimeUTC     = 0;
         m_lastClosedCooldownSec = 0;
        }
     }

   //--- Check if same-direction cooldown is currently active
   bool                 IsDirectionInCooldown(const ENUM_SIGNAL_DIRECTION direction,
                                              const datetime utcNow) const
     {
      if(m_lastClosedDirection == SIGNAL_NONE || m_lastClosedTimeUTC <= 0 || m_lastClosedCooldownSec <= 0)
         return false;
      if(direction != m_lastClosedDirection)
         return false;
      return ((utcNow - m_lastClosedTimeUTC) <= m_lastClosedCooldownSec);
     }

   //--- Synchronize FSM state with ExecutionManager's pending order / open position status
   void                 NotifyPendingOrderState(const bool hasPendingOrOpenTrade)
     {
      if(hasPendingOrOpenTrade)
        {
         m_state = STATE_PENDING_LIMIT;
         datetime curBarTime = iTime(m_symbol, PERIOD_M5, 0);
         if(curBarTime > 0)
            m_lastEvaluatedM5BarTime = curBarTime;
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

      // Stand down outside active London and New York Killzones
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
      double minPierceUSD = MathMax(0.15, 0.08 * atrM15);
      double maxPierceUSD = MathMax(m_maxSweepAtrRatio * atrM15, 0.90 * atrM15);

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

         if(m_tracker.direction == SIGNAL_LONG && closedLow < m_tracker.extremePrice)
           {
            double newDepth = m_tracker.levelPrice - closedLow;
            if(newDepth > maxPierceUSD)
              {
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
      // ================================================================
      if(m_state == STATE_SWEEP_DETECTED && m_tracker.active)
        {
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

         // Condition B: Sweep or reclaim bar exhibits institutional volume participation (ONNX weighs exact f3_rel_tick_volume)
         double maxVolObserved = MathMax(m_tracker.sweepBarTickVol, closedVol);
         double relTickVolume  = maxVolObserved / MathMax(1.0, m_tracker.sma20TickVol);
         bool   hasAbsorption  = (relTickVolume >= 1.05);

         // Condition C: Minor Market Structure Shift (MSS) + 3-Candle FVG or clean VAH/VAL reclaim
         bool   hasFVG      = false;
         double fvgProximal = 0.0;
         double fvgDistal   = 0.0;
         bool   hasMSS      = false;
         double mssLevel    = 0.0;
         bool   hasStructureShift = false;

         if(closedBackInside && hasAbsorption)
           {
            if(IsDirectionInCooldown(m_tracker.direction, utcNow))
              {
               m_state = STATE_IDLE;
               m_tracker.Reset();
               return false;
              }
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
