//+------------------------------------------------------------------+
//|                                                SessionLevels.mqh |
//|                     BTCUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 1 Signal: Asian/London/ETF Ranges, PDH/PDL, Fractals      |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef BTCUSD_QUANT_SESSION_LEVELS_MQH
#define BTCUSD_QUANT_SESSION_LEVELS_MQH

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

   double            ReadIndicatorScalar(const int handle, const int bufferIndex = 0, const int shift = 1) const
     {
      if(handle == INVALID_HANDLE)
         return 0.0;
      double buf[1];
      if(CopyBuffer(handle, bufferIndex, shift, 1, buf) == 1)
         return buf[0];
      return 0.0;
     }

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

   double            m_preTokyoHigh;
   double            m_preTokyoLow;
   bool              m_preTokyoComplete;
   double            m_londonHigh;
   double            m_londonLow;
   bool              m_londonComplete;
   bool              m_asianHighSweptToday;
   bool              m_asianLowSweptToday;
   bool              m_londonHighSweptToday;
   bool              m_londonLowSweptToday;
   bool              m_pdhSweptToday;
   bool              m_pdlSweptToday;
   double            m_sweptPricesToday[MAX_FRACTAL_POOLS];
   int               m_sweptCountToday;

   bool              WasPriceSweptToday(const double price) const
     {
      for(int i = 0; i < m_sweptCountToday; i++)
        {
         if(MathAbs(m_sweptPricesToday[i] - price) < 15.0)
            return true;
        }
      return false;
     }

   //--- Compute Pre-Asia Range (20:00 prior day - 00:30 UTC), Asian Range (00:00 - 06:30 UTC), London H/L (06:30 - 12:00 UTC), and PDH/PDL
   void              UpdateDailyAndAsianBoundaries(const datetime utcNow)
     {
      MqlDateTime dtUTC;
      TimeToStruct(utcNow, dtUTC);
      dtUTC.hour = 0;
      dtUTC.min  = 0;
      dtUTC.sec  = 0;
      datetime todayStartUTC = StructToTime(dtUTC);
      datetime tokyoOpenUTC  = todayStartUTC + 30 * 60;             // 00:30 UTC
      datetime asianEndUTC   = todayStartUTC + 6 * 3600 + 30 * 60;  // 06:30 UTC

      if(todayStartUTC != m_currentDayStartUTC)
        {
         m_sweptCountToday      = 0;
         m_preTokyoHigh         = 0.0;
         m_preTokyoLow          = 0.0;
         m_preTokyoComplete     = false;
         m_londonHigh           = 0.0;
         m_londonLow            = 0.0;
         m_londonComplete       = false;
         m_asianHighSweptToday  = false;
         m_asianLowSweptToday   = false;
         m_londonHighSweptToday = false;
         m_londonLowSweptToday  = false;
         m_pdhSweptToday        = false;
         m_pdlSweptToday        = false;
        }

      m_currentDayStartUTC = todayStartUTC;
      m_ref.sessionDateUTC = todayStartUTC;
      m_ref.asianComplete  = (utcNow >= asianEndUTC);

      // 1. Pre-Asia Range (20:00 UTC yesterday to 00:30 UTC today) for Asian/Tokyo Killzone (00:30 - 04:25 UTC)
      m_preTokyoComplete = (utcNow >= tokyoOpenUTC);
      if(m_preTokyoComplete && m_preTokyoHigh <= 0.0)
        {
         datetime preTokyoStartSrv = UTCTimeToServer(todayStartUTC - 4 * 3600, m_brokerGMTOffset);
         datetime preTokyoEndSrv   = UTCTimeToServer(tokyoOpenUTC, m_brokerGMTOffset);
         MqlRates ptRates[];
         int copiedPT = CopyRates(m_symbol, PERIOD_M5, preTokyoStartSrv, preTokyoEndSrv, ptRates);
         if(copiedPT > 0)
           {
            double ptH = -DBL_MAX, ptL = DBL_MAX;
            for(int i = 0; i < copiedPT; i++)
              {
               if(ptRates[i].high > ptH) ptH = ptRates[i].high;
               if(ptRates[i].low  < ptL) ptL = ptRates[i].low;
              }
            if(ptH > ptL && ptL > 0.0)
              {
               m_preTokyoHigh = ptH;
               m_preTokyoLow  = ptL;
              }
           }
        }

      // 2. Asian Session Range (00:00 - 06:30 UTC)
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

      // 3. Completed London Session High/Low (06:30 - 12:00 UTC) once NY/ETF Killzone begins
      datetime londonEndUTC = todayStartUTC + 12 * 3600;
      m_londonComplete      = (utcNow >= londonEndUTC);
      if(m_londonComplete)
        {
         datetime serverLondonStart = UTCTimeToServer(asianEndUTC, m_brokerGMTOffset);
         datetime serverLondonEnd   = UTCTimeToServer(londonEndUTC, m_brokerGMTOffset);
         MqlRates lonRates[];
         int copiedLon = CopyRates(m_symbol, PERIOD_M5, serverLondonStart, serverLondonEnd, lonRates);
         if(copiedLon > 0)
           {
            double lHigh = -DBL_MAX;
            double lLow  =  DBL_MAX;
            for(int i = 0; i < copiedLon; i++)
              {
               if(lonRates[i].high > lHigh) lHigh = lonRates[i].high;
               if(lonRates[i].low  < lLow)  lLow  = lonRates[i].low;
              }
            if(lHigh > lLow && lLow > 0.0)
              {
               m_londonHigh = lHigh;
               m_londonLow  = lLow;
              }
           }
        }

      // 4. PDH and PDL from previous trading day
      MqlRates d1Rates[];
      ArraySetAsSeries(d1Rates, true);
      if(CopyRates(m_symbol, PERIOD_D1, 1, 2, d1Rates) >= 1)
        {
         m_ref.pdh = d1Rates[0].high;
         m_ref.pdl = d1Rates[0].low;
        }
     }

   void              AddLiquidityPool(const double price,
                                      const datetime formedTime,
                                      const ENUM_LIQUIDITY_TYPE poolType,
                                      const int touchCount = 1,
                                      const bool isEqualCluster = false,
                                      const bool forceSwept = false)
     {
      if(price <= 0.0 || m_poolCount >= MAX_FRACTAL_POOLS)
         return;

      m_pools[m_poolCount].Reset();
      m_pools[m_poolCount].price          = price;
      m_pools[m_poolCount].formedTime     = formedTime;
      m_pools[m_poolCount].poolType       = poolType;
      m_pools[m_poolCount].touchCount     = touchCount;
      m_pools[m_poolCount].isSwept        = (forceSwept || WasPriceSweptToday(price));
      m_pools[m_poolCount].sweptTime      = 0;
      m_pools[m_poolCount].isEqualCluster = isEqualCluster;
      m_poolCount++;
     }

   void              RebuildLiquidityPools()
     {
      m_poolCount = 0;

      // 1a. During Asian/Tokyo Killzone (00:30 - 04:25 UTC), add Pre-Asia High/Low as Asian Session Pool
      if(!m_ref.asianComplete && m_preTokyoComplete && m_preTokyoHigh > 0.0 && m_preTokyoLow > 0.0)
        {
         AddLiquidityPool(m_preTokyoHigh, m_currentDayStartUTC, LIQ_ASIAN_HIGH, 2, false, m_asianHighSweptToday);
         AddLiquidityPool(m_preTokyoLow,  m_currentDayStartUTC, LIQ_ASIAN_LOW,  2, false, m_asianLowSweptToday);
        }

      // 1b. Primary Session Levels (Completed Asian High/Low after 06:30 UTC, London High/Low after 12:00 UTC, PDH, PDL)
      if(m_ref.asianComplete && m_ref.asianHigh > 0.0 && m_ref.asianLow > 0.0)
        {
         AddLiquidityPool(m_ref.asianHigh, m_currentDayStartUTC, LIQ_ASIAN_HIGH, 2, false, m_asianHighSweptToday);
         AddLiquidityPool(m_ref.asianLow,  m_currentDayStartUTC, LIQ_ASIAN_LOW,  2, false, m_asianLowSweptToday);
        }

      if(m_londonComplete && m_londonHigh > 0.0 && m_londonLow > 0.0)
        {
         if(MathAbs(m_londonHigh - m_ref.asianHigh) > 25.0)
            AddLiquidityPool(m_londonHigh, m_currentDayStartUTC + 7 * 3600, LIQ_ASIAN_HIGH, 2, false, m_londonHighSweptToday);
         if(MathAbs(m_londonLow - m_ref.asianLow) > 25.0)
            AddLiquidityPool(m_londonLow,  m_currentDayStartUTC + 7 * 3600, LIQ_ASIAN_LOW,  2, false, m_londonLowSweptToday);
        }

      if(m_ref.pdh > 0.0 && m_ref.pdl > 0.0)
        {
         AddLiquidityPool(m_ref.pdh, m_currentDayStartUTC - 86400, LIQ_PDH, 2, false, m_pdhSweptToday);
         AddLiquidityPool(m_ref.pdl, m_currentDayStartUTC - 86400, LIQ_PDL, 2, false, m_pdlSweptToday);
        }

      // 2. Scan M15 5-Bar Fractal Swing Highs/Lows and Clustered Equal Highs/Lows
      MqlRates m15[];
      ArraySetAsSeries(m15, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 1, M15_FRACTAL_LOOKBACK_BARS, m15);
      if(copied < 10)
         return;

      double equalToleranceUSD = m_equalLevelAtrRatio * MathMax(m_ref.atrM15Current, 120.0);

      double asianMid       = (m_ref.asianComplete && m_ref.asianHigh > 0.0 && m_ref.asianLow > 0.0)
                              ? (0.50 * (m_ref.asianHigh + m_ref.asianLow)) : 0.0;
      double asianInnerHalf = 0.25 * m_ref.asianRange;

      for(int i = 2; i < copied - 2; i++)
        {
         bool isFractalHigh = (m15[i].high >  m15[i - 1].high &&
                               m15[i].high >  m15[i - 2].high &&
                               m15[i].high >= m15[i + 1].high &&
                               m15[i].high >= m15[i + 2].high);

         if(isFractalHigh)
           {
            double fHigh = m15[i].high;
            bool alreadyBrokenBeforeNow = false;
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
                        m_pools[p].isSwept        = (m_pools[p].isSwept || WasPriceSweptToday(m_pools[p].price));
                        mergedCluster             = true;
                        break;
                       }
                    }
                 }
               if(!mergedCluster)
                 {
                  bool outsideAsianCore = (asianMid <= 0.0 || MathAbs(fHigh - asianMid) >= asianInnerHalf);
                  if(outsideAsianCore)
                     AddLiquidityPool(fHigh, m15[i].time, LIQ_M15_SWING_HIGH, 1, false);
                 }
              }
           }

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
                        m_pools[p].isSwept        = (m_pools[p].isSwept || WasPriceSweptToday(m_pools[p].price));
                        mergedCluster             = true;
                        break;
                       }
                    }
                 }
               if(!mergedCluster)
                 {
                  bool outsideAsianCore = (asianMid <= 0.0 || MathAbs(fLow - asianMid) >= asianInnerHalf);
                  if(outsideAsianCore)
                     AddLiquidityPool(fLow, m15[i].time, LIQ_M15_SWING_LOW, 1, false);
                 }
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
      m_asianExhaustionAdrMult = 1.65;
      m_logger                 = NULL;

      m_handleAtrM5            = INVALID_HANDLE;
      m_handleAtrM15           = INVALID_HANDLE;
      m_handleAtrH1            = INVALID_HANDLE;
      m_handleAtrH4            = INVALID_HANDLE;

      m_poolCount              = 0;
      m_preTokyoHigh           = 0.0;
      m_preTokyoLow            = 0.0;
      m_preTokyoComplete       = false;
      m_londonHigh             = 0.0;
      m_londonLow              = 0.0;
      m_sweptCountToday        = 0;
      m_lastM15UpdateBarTime   = 0;
      m_lastM5UpdateBarTime    = 0;
      m_currentDayStartUTC     = 0;
      m_ref.Reset();
     }

                    ~CSessionLevels()
     {
      Deinit();
     }

   bool              Init(const string symbol,
                          const int brokerGMTOffsetHours,
                          CQuantLogger *logger,
                          const double equalLevelAtrRatio = 0.15,
                          const double asianExhaustionAdrMult = 1.65)
     {
      m_symbol                 = symbol;
      m_brokerGMTOffset        = brokerGMTOffsetHours;
      m_logger                 = logger;
      m_equalLevelAtrRatio     = (equalLevelAtrRatio > 0.0 ? equalLevelAtrRatio : 0.15);
      m_asianExhaustionAdrMult = (asianExhaustionAdrMult > 0.5 ? asianExhaustionAdrMult : 1.65);

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

      const ENUM_TIMEFRAMES tfs[6] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
      for(int t = 0; t < 6; t++)
        {
         MqlRates warmRates[];
         CopyRates(m_symbol, tfs[t], 0, 500, warmRates);
        }

      Update();
      return true;
     }

   void              Deinit()
     {
      if(m_handleAtrM5  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrM5);  m_handleAtrM5  = INVALID_HANDLE; }
      if(m_handleAtrM15 != INVALID_HANDLE) { IndicatorRelease(m_handleAtrM15); m_handleAtrM15 = INVALID_HANDLE; }
      if(m_handleAtrH1  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrH1);  m_handleAtrH1  = INVALID_HANDLE; }
      if(m_handleAtrH4  != INVALID_HANDLE) { IndicatorRelease(m_handleAtrH4);  m_handleAtrH4  = INVALID_HANDLE; }
     }

   //+------------------------------------------------------------------+
   //| ClassifyKillzoneSession                                          |
   //| Evaluates exact UTC time against Asian, London & Wall St ETF KZs |
   //+------------------------------------------------------------------+
   ENUM_KILLZONE_SESSION ClassifyKillzoneSession(const datetime utcNow) const
     {
      MqlDateTime dt;
      TimeToStruct(utcNow, dt);
      int minOfDay = dt.hour * 60 + dt.min;

      // Rollover Blackout: 20:55 - 22:10 UTC (1255 - 1330)
      if(minOfDay >= (20 * 60 + 55) && minOfDay <= (22 * 60 + 10))
         return SESSION_ROLLOVER_BLACKOUT;

      // Asian / Tokyo Crypto Reversal Killzone: 00:30 - 04:25 UTC
      if(minOfDay >= 30 && minOfDay <= (4 * 60 + 25))
         return SESSION_TOKYO_KILLZONE;

      // Late-Asian Accumulation: 04:26 - 06:29 UTC
      if(minOfDay > (4 * 60 + 25) && minOfDay < (6 * 60 + 30))
         return SESSION_ASIAN_ACCUMULATION;

      // London / European Crypto Killzone: 06:30 - 11:30 UTC
      if(minOfDay >= (6 * 60 + 30) && minOfDay <= (11 * 60 + 30))
         return SESSION_LONDON_KILLZONE;

      // New York / Wall Street Spot ETF Killzone: 12:30 - 20:00 UTC
      if(minOfDay >= (12 * 60 + 30) && minOfDay <= (20 * 60))
         return SESSION_NY_KILLZONE;

      return SESSION_OUTSIDE_KILLZONE;
     }

   //--- Return true if currently inside Asian, London, or NY/ETF Killzone
   bool              IsInActiveKillzone(const datetime utcNow) const
     {
      ENUM_KILLZONE_SESSION s = ClassifyKillzoneSession(utcNow);
      return (s == SESSION_TOKYO_KILLZONE || s == SESSION_LONDON_KILLZONE || s == SESSION_NY_KILLZONE);
     }

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

         m_ref.isAsianExhausted = (m_ref.adr20 > 0.0 &&
                                   m_ref.asianRange > (m_asianExhaustionAdrMult * m_ref.adr20));

         m_ref.isVolatilityCompressed = (m_ref.atrM15Percentile5th > 0.0 &&
                                         m_ref.atrM15Current > 0.0 &&
                                         m_ref.atrM15Current < m_ref.atrM15Percentile5th);

         m_ref.isTradableRegime = (!m_ref.isAsianExhausted && !m_ref.isVolatilityCompressed);

         RebuildLiquidityPools();
        }
     }

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
                  outDirection     = SIGNAL_SHORT;
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
                  outDirection     = SIGNAL_LONG;
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

   void              MarkPoolSwept(const ENUM_LIQUIDITY_TYPE poolType, const double poolPrice, const datetime sweptTime)
     {
      if(poolType == LIQ_ASIAN_HIGH)
        {
         if(MathAbs(poolPrice - m_ref.asianHigh) < 12.0 || MathAbs(poolPrice - m_preTokyoHigh) < 12.0)
            m_asianHighSweptToday = true;
         if(MathAbs(poolPrice - m_londonHigh) < 12.0)
            m_londonHighSweptToday = true;
        }
      else if(poolType == LIQ_ASIAN_LOW)
        {
         if(MathAbs(poolPrice - m_ref.asianLow) < 12.0 || MathAbs(poolPrice - m_preTokyoLow) < 12.0)
            m_asianLowSweptToday = true;
         if(MathAbs(poolPrice - m_londonLow) < 12.0)
            m_londonLowSweptToday = true;
        }
      else if(poolType == LIQ_PDH) m_pdhSweptToday = true;
      else if(poolType == LIQ_PDL) m_pdlSweptToday = true;

      if(!WasPriceSweptToday(poolPrice) && m_sweptCountToday < MAX_FRACTAL_POOLS)
        {
         m_sweptPricesToday[m_sweptCountToday] = poolPrice;
         m_sweptCountToday++;
        }
      for(int i = 0; i < m_poolCount; i++)
        {
         if(MathAbs(m_pools[i].price - poolPrice) < 15.0)
           {
            m_pools[i].isSwept   = true;
            m_pools[i].sweptTime = sweptTime;
           }
        }
     }

   double            GetOpposingLiquidityTarget(const ENUM_SIGNAL_DIRECTION direction,
                                                const ENUM_LIQUIDITY_TYPE sweptType,
                                                const double entryPrice,
                                                const double slDistanceUSD) const
     {
      double minTargetDist = 2.80 * slDistanceUSD;
      double maxTargetDist = 3.60 * slDistanceUSD;
      double defaultTP2    = (direction == SIGNAL_LONG)
                             ? (entryPrice + 3.50 * slDistanceUSD)
                             : (entryPrice - 3.50 * slDistanceUSD);

      if(direction == SIGNAL_LONG)
        {
         if(sweptType == LIQ_ASIAN_LOW && m_ref.asianHigh > (entryPrice + 2.80 * slDistanceUSD))
            return MathMin(m_ref.asianHigh, entryPrice + maxTargetDist);

         if(sweptType == LIQ_PDL && m_ref.pdh > (entryPrice + 2.80 * slDistanceUSD))
            return MathMin(m_ref.pdh, entryPrice + maxTargetDist);

         for(int i = 0; i < m_poolCount; i++)
           {
            double dist = m_pools[i].price - entryPrice;
            if(dist >= minTargetDist && dist <= maxTargetDist)
               return m_pools[i].price;
           }
        }
      else if(direction == SIGNAL_SHORT)
        {
         if(sweptType == LIQ_ASIAN_HIGH && m_ref.asianLow > 0.0 &&
            (entryPrice - m_ref.asianLow) > (2.80 * slDistanceUSD))
            return MathMax(m_ref.asianLow, entryPrice - maxTargetDist);

         if(sweptType == LIQ_PDH && m_ref.pdl > 0.0 &&
            (entryPrice - m_ref.pdl) > (2.80 * slDistanceUSD))
            return MathMax(m_ref.pdl, entryPrice - maxTargetDist);

         for(int i = 0; i < m_poolCount; i++)
           {
            double dist = entryPrice - m_pools[i].price;
            if(dist >= minTargetDist && dist <= maxTargetDist)
               return m_pools[i].price;
           }
        }

      return defaultTP2;
     }

   void              GetSessionReference(SSessionReference &outRef) const { outRef = m_ref; }
   double            GetAtrM5()  const { return (m_ref.atrM5Current  > 0.0 ? m_ref.atrM5Current  : 220.0); }
   double            GetAtrM15() const { return (m_ref.atrM15Current > 0.0 ? m_ref.atrM15Current : 420.0); }
   double            GetAtrH1()  const { return (m_ref.atrH1Current  > 0.0 ? m_ref.atrH1Current  : 850.0); }
   double            GetAtrH4()  const { return (m_ref.atrH4Current  > 0.0 ? m_ref.atrH4Current  : 1700.0); }
  };

#endif // BTCUSD_QUANT_SESSION_LEVELS_MQH
