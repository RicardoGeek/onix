//+------------------------------------------------------------------+
//|                                                VolumeProfile.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 1 Signal: Rolling Intraday M1 Volume Profile Engine       |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_VOLUME_PROFILE_MQH
#define XAUUSD_QUANT_VOLUME_PROFILE_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"

#define VP_MAX_BINS                      4096

//+------------------------------------------------------------------+
//| CVolumeProfile: Rolling Intraday M1 Volume Profile Calculator    |
//+------------------------------------------------------------------+
class CVolumeProfile
  {
private:
   string                 m_symbol;
   int                    m_brokerGMTOffset;
   double                 m_binSizeUSD;
   double                 m_valueAreaRatio;
   double                 m_lvnThresholdRatio;

   CQuantLogger          *m_logger;
   SVolumeProfileSnapshot m_snapshot;
   double                 m_binVolumes[];
   datetime               m_lastM1BarTimeProcessed;

public:
                          CVolumeProfile()
     {
      m_symbol                 = _Symbol;
      m_brokerGMTOffset        = 2;
      m_binSizeUSD             = VP_DEFAULT_BIN_SIZE_USD;
      m_valueAreaRatio         = VP_VALUE_AREA_PCT;
      m_lvnThresholdRatio      = VP_LVN_THRESHOLD_RATIO;
      m_logger                 = NULL;
      m_lastM1BarTimeProcessed = 0;
      m_snapshot.Reset();
     }

                         ~CVolumeProfile() {}

   //--- Initialize Rolling Intraday Volume Profile Engine
   bool                   Init(const string symbol,
                               const int brokerGMTOffsetHours,
                               CQuantLogger *logger,
                               const double binSizeUSD = VP_DEFAULT_BIN_SIZE_USD,
                               const double valueAreaRatio = VP_VALUE_AREA_PCT,
                               const double lvnThresholdRatio = VP_LVN_THRESHOLD_RATIO)
     {
      m_symbol            = symbol;
      m_brokerGMTOffset   = brokerGMTOffsetHours;
      m_logger            = logger;
      m_binSizeUSD        = (binSizeUSD >= 0.05 ? binSizeUSD : VP_DEFAULT_BIN_SIZE_USD);
      m_valueAreaRatio    = (valueAreaRatio > 0.10 && valueAreaRatio < 0.99 ? valueAreaRatio : VP_VALUE_AREA_PCT);
      m_lvnThresholdRatio = (lvnThresholdRatio > 0.05 && lvnThresholdRatio < 0.90 ? lvnThresholdRatio : VP_LVN_THRESHOLD_RATIO);

      m_snapshot.Reset();
      m_lastM1BarTimeProcessed = 0;
      Update(true);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Update                                                           |
   //| Recomputes intraday Volume Profile from 00:00 UTC up to the      |
   //| latest closed M1 bar when a new M1 bar closes (or forceRebuild). |
   //+------------------------------------------------------------------+
   bool                   Update(const bool forceRebuild = false)
     {
      datetime currentM1BarTime = iTime(m_symbol, PERIOD_M1, 1);
      if(currentM1BarTime == 0)
         return false;

      if(!forceRebuild && m_snapshot.isValid && currentM1BarTime == m_lastM1BarTimeProcessed)
         return true;

      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);
      MqlDateTime dtUTC;
      TimeToStruct(utcNow, dtUTC);
      dtUTC.hour = 0;
      dtUTC.min  = 0;
      dtUTC.sec  = 0;
      datetime dayStartUTC    = StructToTime(dtUTC);
      datetime serverDayStart = UTCTimeToServer(dayStartUTC, m_brokerGMTOffset);
      datetime serverNow      = TimeCurrent();

      MqlRates m1Rates[];
      int copied = CopyRates(m_symbol, PERIOD_M1, serverDayStart, serverNow, m1Rates);
      if(copied < 5)
        {
         // Fallback during the very first 5 minutes of the UTC day: include prior 60 M1 bars
         copied = CopyRates(m_symbol, PERIOD_M1, 1, 60, m1Rates);
         if(copied < 5)
            return false;
        }

      // 1. Find Session High and Low across M1 bars
      double sessionLow  =  DBL_MAX;
      double sessionHigh = -DBL_MAX;

      for(int i = 0; i < copied; i++)
        {
         if(m1Rates[i].low  < sessionLow  && m1Rates[i].low  > 0.0) sessionLow  = m1Rates[i].low;
         if(m1Rates[i].high > sessionHigh && m1Rates[i].high > 0.0) sessionHigh = m1Rates[i].high;
        }

      if(sessionHigh <= sessionLow || sessionLow <= 0.0)
         return false;

      // Align grid anchor to clean $0.25 increments for deterministic bin edges
      double gridLow  = MathFloor(sessionLow / m_binSizeUSD) * m_binSizeUSD;
      double gridHigh = MathCeil(sessionHigh / m_binSizeUSD) * m_binSizeUSD;
      int    numBins  = (int)MathRound((gridHigh - gridLow) / m_binSizeUSD) + 1;

      if(numBins < 3)
         numBins = 3;
      if(numBins > VP_MAX_BINS)
         numBins = VP_MAX_BINS;

      ArrayResize(m_binVolumes, numBins);
      ArrayInitialize(m_binVolumes, 0.0);

      double totalVolume = 0.0;

      // 2. Distribute each M1 bar's volume uniformly across all touched $0.25 price bins
      for(int i = 0; i < copied; i++)
        {
         double barVol = (m1Rates[i].real_volume > 0)
                         ? (double)m1Rates[i].real_volume
                         : (double)m1Rates[i].tick_volume;
         if(barVol <= 0.0)
            continue;

         int startBin = (int)MathFloor((m1Rates[i].low  - gridLow + QUANT_EPSILON) / m_binSizeUSD);
         int endBin   = (int)MathFloor((m1Rates[i].high - gridLow + QUANT_EPSILON) / m_binSizeUSD);

         startBin = MathMax(0, MathMin(numBins - 1, startBin));
         endBin   = MathMax(startBin, MathMin(numBins - 1, endBin));

         int touchedCount = (endBin - startBin) + 1;
         double volPerBin = barVol / (double)touchedCount;

         for(int b = startBin; b <= endBin; b++)
            m_binVolumes[b] += volPerBin;

         totalVolume += barVol;
        }

      if(totalVolume <= 0.0)
         return false;

      // 3. Identify VPOC (bin with maximum accumulated volume)
      int    vpocBinIdx = 0;
      double maxBinVol  = -1.0;
      for(int b = 0; b < numBins; b++)
        {
         if(m_binVolumes[b] > maxBinVol)
           {
            maxBinVol  = m_binVolumes[b];
            vpocBinIdx = b;
           }
        }

      double vpocPrice = gridLow + ((double)vpocBinIdx + 0.5) * m_binSizeUSD;

      // 4. Compute 70% Value Area [VAL, VAH] expanding outward from VPOC bin
      double targetValueAreaVol = totalVolume * m_valueAreaRatio;
      double accumVol           = m_binVolumes[vpocBinIdx];
      int    lowIdx             = vpocBinIdx;
      int    highIdx            = vpocBinIdx;

      while(accumVol < targetValueAreaVol && (lowIdx > 0 || highIdx < (numBins - 1)))
        {
         double nextUpVol   = (highIdx < (numBins - 1)) ? m_binVolumes[highIdx + 1] : -1.0;
         double nextDownVol = (lowIdx  > 0)             ? m_binVolumes[lowIdx  - 1] : -1.0;

         if(nextUpVol >= nextDownVol && highIdx < (numBins - 1))
           {
            highIdx++;
            accumVol += m_binVolumes[highIdx];
           }
         else if(lowIdx > 0)
           {
            lowIdx--;
            accumVol += m_binVolumes[lowIdx];
           }
         else if(highIdx < (numBins - 1))
           {
            highIdx++;
            accumVol += m_binVolumes[highIdx];
           }
         else
           {
            break;
           }
        }

      double valPrice = gridLow + ((double)lowIdx) * m_binSizeUSD;
      double vahPrice = gridLow + ((double)(highIdx + 1)) * m_binSizeUSD;

      // Ensure VAL < VPOC < VAH with at least 1 bin width on each side
      if(valPrice >= vpocPrice)
         valPrice = vpocPrice - m_binSizeUSD;
      if(vahPrice <= vpocPrice)
         vahPrice = vpocPrice + m_binSizeUSD;

      // 5. Identify External Low Volume Nodes (LVNs):
      // Local volume minima below 30% of average bin volume outside [VAL, VAH]
      double avgBinVolume = totalVolume / (double)numBins;
      double lvnMaxCutoff = m_lvnThresholdRatio * avgBinVolume;

      m_snapshot.Reset();
      m_snapshot.profileDayStartUTC = dayStartUTC;
      m_snapshot.lastUpdatedBarTime = currentM1BarTime;
      m_snapshot.sessionHigh        = sessionHigh;
      m_snapshot.sessionLow         = sessionLow;
      m_snapshot.binSizeUSD         = m_binSizeUSD;
      m_snapshot.totalBins          = numBins;
      m_snapshot.totalSessionVolume = totalVolume;
      m_snapshot.vpoc               = NormalizeSymbolPrice(m_symbol, vpocPrice);
      m_snapshot.vah                = NormalizeSymbolPrice(m_symbol, vahPrice);
      m_snapshot.val                = NormalizeSymbolPrice(m_symbol, valPrice);

      int lvnFound = 0;
      for(int b = 1; b < numBins - 1 && lvnFound < MAX_LVN_COUNT; b++)
        {
         // Must be strictly outside the Value Area [lowIdx, highIdx]
         if(b >= lowIdx && b <= highIdx)
            continue;

         double vPrev = m_binVolumes[b - 1];
         double vCurr = m_binVolumes[b];
         double vNext = m_binVolumes[b + 1];

         bool isLocalMinimum = (vCurr <= vPrev && vCurr <= vNext && (vCurr < vPrev || vCurr < vNext));
         if(isLocalMinimum && vCurr <= lvnMaxCutoff)
           {
            double lvnCenterPrice = gridLow + ((double)b + 0.5) * m_binSizeUSD;
            m_snapshot.lvnPrices[lvnFound] = NormalizeSymbolPrice(m_symbol, lvnCenterPrice);
            lvnFound++;
           }
        }

      m_snapshot.lvnCount  = lvnFound;
      m_snapshot.isValid   = true;
      m_lastM1BarTimeProcessed = currentM1BarTime;
      return true;
     }

   //--- Snapshot & Scalar Accessors
   void                   GetSnapshot(SVolumeProfileSnapshot &outSnapshot) const { outSnapshot = m_snapshot; }
   bool                   IsValid()  const { return m_snapshot.isValid; }
   double                 GetVPOC()  const { return m_snapshot.vpoc;    }
   double                 GetVAH()   const { return m_snapshot.vah;     }
   double                 GetVAL()   const { return m_snapshot.val;     }
  };

#endif // XAUUSD_QUANT_VOLUME_PROFILE_MQH
