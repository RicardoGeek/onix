//+------------------------------------------------------------------+
//|                                                SessionLevels.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 1 Signal: Asian Range, PDH/PDL, M15 Fractals & Killzones  |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_SESSION_LEVELS_MQH
#define XAUUSD_QUANT_SESSION_LEVELS_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"

#define M15_BARS_20_DAYS                 1920
#define M15_FRACTAL_LOOKBACK_BARS        120

//+------------------------------------------------------------------+
//| CSessionLevels: Institutional Reference & Liquidity Pool Tracker |
//+------------------------------------------------------------------+
class CSessionLevels
  {
private:
   string            m_symbol;
   int               m_brokerGMTOffset;
   double            m_equalLevelAtrRatio;
   double            m_asianExhaustionAdrMult;

   CQuantLogger     *m_logger;

   //--- Native MQL5 Indicator Handles
   int               m_handleAtrM5;
   int               m_handleAtrM15;
   int               m_handleAtrH1;
   int               m_handleAtrH4;

   //--- Cached State
   SSessionReference m_ref;
   SLiquidityPool    m_pools[MAX_FRACTAL_POOLS];
   int               m_poolCount;
   datetime          m_lastM15UpdateBarTime;
   datetime          m_lastM5UpdateBarTime;
   datetime          m_currentDayStartUTC;

   //--- Helper to read single indicator value safely
   double            ReadIndicatorScalar(const int handle, const int bufferIndex = 0, const int shift = 1) const
     {
      if(handle == INVALID_HANDLE)
         return 0.0;
      double buf[1];
      if(CopyBuffer(handle, bufferIndex, shift, 1, buf) == 1)
         return buf[0];
      return 0.0;
     }

   //--- Compute 20-Day Average Daily Range (ADR 20)
   double            ComputeADR20() const
     {
      MqlRates d1Rates[];
      ArraySetAsSeries(d1Rates, true);
      int copied = CopyRates(m_symbol, PERIOD_D1, 1, 20, d1Rates);
      if(copied <= 0)
         return 0.0;

      double sumRange = 0.0;
      for(int i = 0; i < copied; i++)
         sumRange += (d1Rates[i].high - d1Rates[i].low);

      return sumRange / (double)copied;
     }

   //--- Compute 5th Percentile of M15 ATR(14) over the last 20 trading days
   double            ComputeAtrM15Percentile5th() const
     {
      if(m_handleAtrM15 == INVALID_HANDLE)
         return 0.0;

      double atrHistory[];
      int copied = CopyBuffer(m_handleAtrM15, 0, 1, M15_BARS_20_DAYS, atrHistory);
      if(copied < 40)
         return 0.0;

      ArraySort(atrHistory);
      int idx5th = (int)MathFloor(0.05 * (double)(copied - 1));
      idx5th     = MathMax(0, MathMin(copied - 1, idx5th));
      return atrHistory[idx5th];
     }

   //--- Compute Asian Session High/Low (00:00 - 07:00 UTC) and Previous Day High/Low
   void              UpdateDailyAndAsianBoundaries(const datetime utcNow)
     {
      MqlDateTime dtUTC;
      TimeToStruct(utcNow, dtUTC);
      dtUTC.hour = 0;
      dtUTC.min  = 0;
      dtUTC.sec  = 0;
      datetime todayStartUTC = StructToTime(dtUTC);
      datetime asianEndUTC   = todayStartUTC + 7 * 3600; // 07:00 UTC

      m_currentDayStartUTC = todayStartUTC;
      m_ref.sessionDateUTC = todayStartUTC;
      m_ref.asianComplete  = (utcNow >= asianEndUTC);

      // Convert UTC Asian window to Broker Server Time for CopyRates
      datetime serverTodayStart = UTCTimeToServer(todayStartUTC, m_brokerGMTOffset);
      datetime serverAsianEnd   = UTCTimeToServer(MathMin(utcNow, asianEndUTC), m_brokerGMTOffset);

      MqlRates m5Rates[];
      int copiedAsian = CopyRates(m_symbol, PERIOD_M5, serverTodayStart, serverAsianEnd, m5Rates);
      if(copiedAsian > 0)
        {
         double aHigh = -DBL_MAX;
         double aLow  =  DBL_MAX;
         for(int i = 0; i < copiedAsian; i++)
           {
            if(m5Rates[i].high > aHigh) aHigh = m5Rates[i].high;
            if(m5Rates[i].low  < aLow)  aLow  = m5Rates[i].low;
           }
         if(aHigh > aLow && aLow > 0.0)
           {
            m_ref.asianHigh  = aHigh;
            m_ref.asianLow   = aLow;
            m_ref.asianRange = aHigh - aLow;
           }
        }

      // Compute PDH and PDL from previous trading day
      MqlRates d1Rates[];
      ArraySetAsSeries(d1Rates, true);
      if(CopyRates(m_symbol, PERIOD_D1, 1, 2, d1Rates) >= 1)
        {
         m_ref.pdh = d1Rates[0].high;
         m_ref.pdl = d1Rates[0].low;
        }
     }

   //--- Append a liquidity pool to the internal table
   void              AddLiquidityPool(const double price,
                                      const datetime formedTime,
                                      const ENUM_LIQUIDITY_TYPE poolType,
                                      const int touchCount = 1,
                                      const bool isEqualCluster = false)
     {
      if(price <= 0.0 || m_poolCount >= MAX_FRACTAL_POOLS)
         return;

      m_pools[m_poolCount].Reset();
      m_pools[m_poolCount].price          = price;
      m_pools[m_poolCount].formedTime     = formedTime;
      m_pools[m_poolCount].poolType       = poolType;
      m_pools[m_poolCount].touchCount     = touchCount;
      m_pools[m_poolCount].isSwept        = false;
      m_pools[m_poolCount].sweptTime      = 0;
      m_pools[m_poolCount].isEqualCluster = isEqualCluster;
      m_poolCount++;
     }

   //--- Rebuild Institutional Liquidity Pools (Asian H/L, PDH/PDL, M15 5-bar Fractals & Equal H/L)
   void              RebuildLiquidityPools()
     {
      m_poolCount = 0;

      // 1. Primary Session Levels (Asian High/Low, PDH, PDL)
      if(m_ref.asianHigh > 0.0 && m_ref.asianLow > 0.0)
        {
         AddLiquidityPool(m_ref.asianHigh, m_currentDayStartUTC, LIQ_ASIAN_HIGH, 2, false);
         AddLiquidityPool(m_ref.asianLow,  m_currentDayStartUTC, LIQ_ASIAN_LOW,  2, false);
        }

      if(m_ref.pdh > 0.0 && m_ref.pdl > 0.0)
        {
         AddLiquidityPool(m_ref.pdh, m_currentDayStartUTC - 86400, LIQ_PDH, 2, false);
         AddLiquidityPool(m_ref.pdl, m_currentDayStartUTC - 86400, LIQ_PDL, 2, false);
        }

      // 2. Scan M15 5-Bar Fractal Swing Highs/Lows and Clustered Equal Highs/Lows
      MqlRates m15[];
      ArraySetAsSeries(m15, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 1, M15_FRACTAL_LOOKBACK_BARS, m15);
      if(copied < 10)
         return;

      double equalToleranceUSD = m_equalLevelAtrRatio * MathMax(m_ref.atrM15Current, 1.0);

      // Extract raw 5-bar fractals from M15 series (shift 2..copied-3)
      // Maintain only fractals that have NOT been invalidated by subsequent M15 closes prior to bar 1
      for(int i = 2; i < copied - 2; i++)
        {
         // --- Check 5-Bar Fractal Swing High ---
         bool isFractalHigh = (m15[i].high >  m15[i - 1].high &&
                               m15[i].high >  m15[i - 2].high &&
                               m15[i].high >= m15[i + 1].high &&
                               m15[i].high >= m15[i + 2].high);

         if(isFractalHigh)
           {
            double fHigh = m15[i].high;
            bool alreadyBrokenBeforeNow = false;
            // Check bars more recent than i (down to index 2) to see if price already closed well above fHigh
            for(int j = i - 1; j >= 2; j--)
              {
               if(m15[j].close > fHigh + equalToleranceUSD)
                 {
                  alreadyBrokenBeforeNow = true;
                  break;
                 }
              }

            if(!alreadyBrokenBeforeNow)
              {
               // Check if this fractal clusters with an existing M15 swing high within 0.15 * ATR(M15, 14)
               bool mergedCluster = false;
               for(int p = 0; p < m_poolCount; p++)
                 {
                  if(m_pools[p].poolType == LIQ_M15_SWING_HIGH || m_pools[p].poolType == LIQ_EQUAL_HIGHS)
                    {
                     if(MathAbs(m_pools[p].price - fHigh) <= equalToleranceUSD)
                       {
                        m_pools[p].price          = MathMax(m_pools[p].price, fHigh);
                        m_pools[p].touchCount++;
                        m_pools[p].poolType       = LIQ_EQUAL_HIGHS;
                        m_pools[p].isEqualCluster = true;
                        mergedCluster             = true;
                        break;
                       }
                    }
                 }
               if(!mergedCluster)
                  AddLiquidityPool(fHigh, m15[i].time, LIQ_M15_SWING_HIGH, 1, false);
              }
           }

         // --- Check 5-Bar Fractal Swing Low ---
         bool isFractalLow = (m15[i].low <  m15[i - 1].low &&
                              m15[i].low <  m15[i - 2].low &&
                              m15[i].low <= m15[i + 1].low &&
                              m15[i].low <= m15[i + 2].low);

         if(isFractalLow)
           {
            double fLow = m15[i].low;
            bool alreadyBrokenBeforeNow = false;
            for(int j = i - 1; j >= 2; j--)
              {
               if(m15[j].close < fLow - equalToleranceUSD)
                 {
                  alreadyBrokenBeforeNow = true;
                  break;
                 }
              }

            if(!alreadyBrokenBeforeNow)
              {
               bool mergedCluster = false;
               for(int p = 0; p < m_poolCount; p++)
                 {
                  if(m_pools[p].poolType == LIQ_M15_SWING_LOW || m_pools[p].poolType == LIQ_EQUAL_LOWS)
                    {
                     if(MathAbs(m_pools[p].price - fLow) <= equalToleranceUSD)
                       {
                        m_pools[p].price          = MathMin(m_pools[p].price, fLow);
                        m_pools[p].touchCount++;
                        m_pools[p].poolType       = LIQ_EQUAL_LOWS;
                        m_pools[p].isEqualCluster = true;
                        mergedCluster             = true;
                        break;
                       }
                    }
                 }
               if(!mergedCluster)
                  AddLiquidityPool(fLow, m15[i].time, LIQ_M15_SWING_LOW, 1, false);
              }
           }
        }
     }

public:
                     CSessionLevels()
     {
      m_symbol                 = _Symbol;
      m_brokerGMTOffset        = 2;
      m_equalLevelAtrRatio     = 0.15;
      m_asianExhaustionAdrMult = 1.50;
      m_logger                 = NULL;

      m_handleAtrM5            = INVALID_HANDLE;
      m_handleAtrM15           = INVALID_HANDLE;
      m_handleAtrH1            = INVALID_HANDLE;
      m_handleAtrH4            = INVALID_HANDLE;

      m_poolCount              = 0;
      m_lastM15UpdateBarTime   = 0;
      m_lastM5UpdateBarTime    = 0;
      m_currentDayStartUTC     = 0;
      m_ref.Reset();
     }

                    ~CSessionLevels()
     {
      Deinit();
     }

   //--- Initialize ATR indicator handles and initial session state
   bool              Init(const string symbol,
                          const int brokerGMTOffsetHours,
                          CQuantLogger *logger,
                          const double equalLevelAtrRatio = 0.15,
                          const double asianExhaustionAdrMult = 1.50)
     {
      m_symbol                 = symbol;
      m_brokerGMTOffset        = brokerGMTOffsetHours;
      m_logger                 = logger;
      m_equalLevelAtrRatio     = (equalLevelAtrRatio > 0.0 ? equalLevelAtrRatio : 0.15);
      m_asianExhaustionAdrMult = (asianExhaustionAdrMult > 0.5 ? asianExhaustionAdrMult : 1.50);

      m_handleAtrM5  = iATR(m_symbol, PERIOD_M5,  14);
      m_handleAtrM15 = iATR(m_symbol, PERIOD_M15, 14);
      m_handleAtrH1  = iATR(m_symbol, PERIOD_H1,  14);
      m_handleAtrH4  = iATR(m_symbol, PERIOD_H4,  14);

      if(m_handleAtrM5  == INVALID_HANDLE ||
         m_handleAtrM15 == INVALID_HANDLE ||
         m_handleAtrH1  == INVALID_HANDLE ||
         m_handleAtrH4  == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error("CSessionLevels::Init failed to create ATR(14) indicator handles.");
         return false;
        }

      Update();
      return true;
     }

   //--- Release indicator handles
   void              Deinit()
     {
      if(m_handleAtrM5  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrM5);  m_handleAtrM5  = INVALID_HANDLE; }
      if(m_handleAtrM15 != INVALID_HANDLE) { IndicatorRelease(m_handleAtrM15); m_handleAtrM15 = INVALID_HANDLE; }
      if(m_handleAtrH1  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrH1);  m_handleAtrH1  = INVALID_HANDLE; }
      if(m_handleAtrH4  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrH4);  m_handleAtrH4  = INVALID_HANDLE; }
     }

   //+------------------------------------------------------------------+
   //| ClassifyKillzoneSession                                          |
   //| Evaluates exact UTC time against London & New York Killzones     |
   //+------------------------------------------------------------------+
   ENUM_KILLZONE_SESSION ClassifyKillzoneSession(const datetime utcNow) const
     {
      MqlDateTime dt;
      TimeToStruct(utcNow, dt);
      int minOfDay = dt.hour * 60 + dt.min;

      // Rollover Blackout: 20:55 - 22:10 UTC (1255 - 1330)
      if(minOfDay >= (20 * 60 + 55) && minOfDay <= (22 * 60 + 10))
         return SESSION_ROLLOVER_BLACKOUT;

      // Asian Session Accumulation: 00:00 - 07:00 UTC (0 - 419)
      if(minOfDay >= 0 && minOfDay < (7 * 60))
         return SESSION_ASIAN_ACCUMULATION;

      // London Killzone: 07:00 - 10:30 UTC (420 - 630)
      if(minOfDay >= (7 * 60) && minOfDay <= (10 * 60 + 30))
         return SESSION_LONDON_KILLZONE;

      // New York Killzone: 12:30 - 16:00 UTC (750 - 960)
      if(minOfDay >= (12 * 60 + 30) && minOfDay <= (16 * 60))
         return SESSION_NY_KILLZONE;

      return SESSION_OUTSIDE_KILLZONE;
     }

   //--- Return true if currently inside London (07:00-10:30 UTC) or NY (12:30-16:00 UTC) Killzone
   bool              IsInActiveKillzone(const datetime utcNow) const
     {
      ENUM_KILLZONE_SESSION s = ClassifyKillzoneSession(utcNow);
      return (s == SESSION_LONDON_KILLZONE || s == SESSION_NY_KILLZONE);
     }

   //+------------------------------------------------------------------+
   //| Update                                                           |
   //| Refreshes ATR values, Asian Range, PDH/PDL, M15 fractals, and    |
   //| Flat/Exhausted Market Filter state.                              |
   //+------------------------------------------------------------------+
   void              Update()
     {
      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);
      m_ref.currentSession = ClassifyKillzoneSession(utcNow);

      datetime m5BarTime  = iTime(m_symbol, PERIOD_M5,  0);
      datetime m15BarTime = iTime(m_symbol, PERIOD_M15, 0);

      if(m5BarTime != m_lastM5UpdateBarTime || m_ref.atrM5Current <= 0.0)
        {
         m_lastM5UpdateBarTime = m5BarTime;
         m_ref.atrM5Current    = ReadIndicatorScalar(m_handleAtrM5,  0, 1);
         m_ref.atrM15Current   = ReadIndicatorScalar(m_handleAtrM15, 0, 1);
         m_ref.atrH1Current    = ReadIndicatorScalar(m_handleAtrH1,  0, 1);
         m_ref.atrH4Current    = ReadIndicatorScalar(m_handleAtrH4,  0, 1);

         UpdateDailyAndAsianBoundaries(utcNow);
        }

      if(m15BarTime != m_lastM15UpdateBarTime || m_poolCount == 0)
        {
         m_lastM15UpdateBarTime    = m15BarTime;
         m_ref.adr20               = ComputeADR20();
         m_ref.atrM15Percentile5th = ComputeAtrM15Percentile5th();

         // Evaluate Flat / Exhausted Market Filter (Section 4.1):
         // 1) Stand down if Asian Range > 1.5 * ADR(20)
         // 2) Stand down if current M15 ATR is below 5th percentile of last 20 days
         m_ref.isAsianExhausted = (m_ref.adr20 > 0.0 &&
                                   m_ref.asianRange > (m_asianExhaustionAdrMult * m_ref.adr20));

         m_ref.isVolatilityCompressed = (m_ref.atrM15Percentile5th > 0.0 &&
                                         m_ref.atrM15Current > 0.0 &&
                                         m_ref.atrM15Current < m_ref.atrM15Percentile5th);

         m_ref.isTradableRegime = (!m_ref.isAsianExhausted && !m_ref.isVolatilityCompressed);

         RebuildLiquidityPools();
        }
     }

   //+------------------------------------------------------------------+
   //| FindSweptLiquidityPool                                           |
   //| Checks if a bar's [barLow, barHigh] pierced any unswept primary  |
   //| liquidity pool by a distance in [0.15 * ATR_M15, 0.65 * ATR_M15] |
   //+------------------------------------------------------------------+
   bool              FindSweptLiquidityPool(const double barHigh,
                                            const double barLow,
                                            const double minPierceUSD,
                                            const double maxPierceUSD,
                                            SLiquidityPool &outPool,
                                            ENUM_SIGNAL_DIRECTION &outDirection,
                                            double &outSweepDepthUSD) const
     {
      outPool.Reset();
      outDirection     = SIGNAL_NONE;
      outSweepDepthUSD = 0.0;

      // Priority ranking: Equal Highs/Lows & Session High/Low & PDH/PDL take precedence
      int    bestIndex    = -1;
      int    bestPriority = -1;

      for(int i = 0; i < m_poolCount; i++)
        {
         if(m_pools[i].isSwept || m_pools[i].price <= 0.0)
            continue;

         ENUM_LIQUIDITY_TYPE pType = m_pools[i].poolType;
         bool isUpperPool = (pType == LIQ_ASIAN_HIGH ||
                             pType == LIQ_PDH ||
                             pType == LIQ_EQUAL_HIGHS ||
                             pType == LIQ_M15_SWING_HIGH);

         bool isLowerPool = (pType == LIQ_ASIAN_LOW ||
                             pType == LIQ_PDL ||
                             pType == LIQ_EQUAL_LOWS ||
                             pType == LIQ_M15_SWING_LOW);

         int priority = 1;
         if(pType == LIQ_ASIAN_HIGH || pType == LIQ_ASIAN_LOW) priority = 4;
         else if(pType == LIQ_PDH || pType == LIQ_PDL)         priority = 3;
         else if(pType == LIQ_EQUAL_HIGHS || pType == LIQ_EQUAL_LOWS) priority = 3;
         else                                                  priority = 2;

         if(isUpperPool)
           {
            double pierce = barHigh - m_pools[i].price;
            if(pierce >= minPierceUSD && pierce <= maxPierceUSD)
              {
               if(priority > bestPriority)
                 {
                  bestPriority     = priority;
                  bestIndex        = i;
                  outDirection     = SIGNAL_SHORT; // Bearish sweep of high -> Short setup
                  outSweepDepthUSD = pierce;
                 }
              }
           }
         else if(isLowerPool)
           {
            double pierce = m_pools[i].price - barLow;
            if(pierce >= minPierceUSD && pierce <= maxPierceUSD)
              {
               if(priority > bestPriority)
                 {
                  bestPriority     = priority;
                  bestIndex        = i;
                  outDirection     = SIGNAL_LONG;  // Bullish sweep of low -> Long setup
                  outSweepDepthUSD = pierce;
                 }
              }
           }
        }

      if(bestIndex >= 0)
        {
         outPool = m_pools[bestIndex];
         return true;
        }
      return false;
     }

   //--- Mark a liquidity pool as swept so it is not re-triggered repeatedly
   void              MarkPoolSwept(const ENUM_LIQUIDITY_TYPE poolType, const double poolPrice, const datetime sweptTime)
     {
      for(int i = 0; i < m_poolCount; i++)
        {
         if(m_pools[i].poolType == poolType && MathAbs(m_pools[i].price - poolPrice) < 0.10)
           {
            m_pools[i].isSwept   = true;
            m_pools[i].sweptTime = sweptTime;
           }
        }
     }

   //+------------------------------------------------------------------+
   //| GetOpposingLiquidityTarget                                       |
   //| Returns opposing session liquidity boundary for TP2 targeting    |
   //| (e.g., Asian High if sweeping Asian Low, or nearest opposing M15 |
   //| fractal pool offering 3.5R to 5.0R).                             |
   //+------------------------------------------------------------------+
   double            GetOpposingLiquidityTarget(const ENUM_SIGNAL_DIRECTION direction,
                                                const ENUM_LIQUIDITY_TYPE sweptType,
                                                const double entryPrice,
                                                const double slDistanceUSD) const
     {
      double minTargetDist = 3.50 * slDistanceUSD;
      double maxTargetDist = 5.00 * slDistanceUSD;
      double defaultTP2    = (direction == SIGNAL_LONG)
                             ? (entryPrice + 4.00 * slDistanceUSD)
                             : (entryPrice - 4.00 * slDistanceUSD);

      if(direction == SIGNAL_LONG)
        {
         // If sweeping Asian Low, check if Asian High offers at least 3.0R
         if(sweptType == LIQ_ASIAN_LOW && m_ref.asianHigh > (entryPrice + 3.0 * slDistanceUSD))
            return MathMin(m_ref.asianHigh, entryPrice + maxTargetDist);

         if(sweptType == LIQ_PDL && m_ref.pdh > (entryPrice + 3.0 * slDistanceUSD))
            return MathMin(m_ref.pdh, entryPrice + maxTargetDist);

         // Search opposing upper pools within [3.5R, 5.0R]
         for(int i = 0; i < m_poolCount; i++)
           {
            double dist = m_pools[i].price - entryPrice;
            if(dist >= minTargetDist && dist <= maxTargetDist)
               return m_pools[i].price;
           }
        }
      else if(direction == SIGNAL_SHORT)
        {
         // If sweeping Asian High, check if Asian Low offers at least 3.0R
         if(sweptType == LIQ_ASIAN_HIGH && m_ref.asianLow > 0.0 &&
            (entryPrice - m_ref.asianLow) > (3.0 * slDistanceUSD))
            return MathMax(m_ref.asianLow, entryPrice - maxTargetDist);

         if(sweptType == LIQ_PDH && m_ref.pdl > 0.0 &&
            (entryPrice - m_ref.pdl) > (3.0 * slDistanceUSD))
            return MathMax(m_ref.pdl, entryPrice - maxTargetDist);

         // Search opposing lower pools within [3.5R, 5.0R]
         for(int i = 0; i < m_poolCount; i++)
           {
            double dist = entryPrice - m_pools[i].price;
            if(dist >= minTargetDist && dist <= maxTargetDist)
               return m_pools[i].price;
           }
        }

      return defaultTP2;
     }

   //--- Snapshot & Indicator Accessors
   void              GetSessionReference(SSessionReference &outRef) const { outRef = m_ref; }
   double            GetAtrM5()  const { return (m_ref.atrM5Current  > 0.0 ? m_ref.atrM5Current  : 1.50); }
   double            GetAtrM15() const { return (m_ref.atrM15Current > 0.0 ? m_ref.atrM15Current : 3.00); }
   double            GetAtrH1()  const { return (m_ref.atrH1Current  > 0.0 ? m_ref.atrH1Current  : 6.00); }
   double            GetAtrH4()  const { return (m_ref.atrH4Current  > 0.0 ? m_ref.atrH4Current  : 12.0); }
  };

#endif // XAUUSD_QUANT_SESSION_LEVELS_MQH
