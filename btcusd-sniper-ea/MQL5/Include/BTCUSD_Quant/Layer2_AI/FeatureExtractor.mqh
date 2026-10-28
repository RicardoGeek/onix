//+------------------------------------------------------------------+
//|                                             FeatureExtractor.mqh |
//|                     BTCUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 2 AI: Exact 12-Feature Stationary Vector Computation      |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef BTCUSD_QUANT_FEATURE_EXTRACTOR_MQH
#define BTCUSD_QUANT_FEATURE_EXTRACTOR_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "../Layer1_Signal/SessionLevels.mqh"
#include "../Layer1_Signal/VolumeProfile.mqh"

#define HURST_WINDOW_BARS                100

//+------------------------------------------------------------------+
//| CFeatureExtractor: Zero-Skew 12-Feature Stationary Calculator    |
//+------------------------------------------------------------------+
class CFeatureExtractor
  {
private:
   string           m_symbol;
   int              m_brokerGMTOffset;
   int              m_handleAdxH1;

   CSessionLevels  *m_sessionLevels;
   CVolumeProfile  *m_volumeProfile;
   CQuantLogger    *m_logger;

   double           ReadAdxH1() const
     {
      if(m_handleAdxH1 == INVALID_HANDLE)
         return 25.0;
      double buf[1];
      if(CopyBuffer(m_handleAdxH1, 0, 1, 1, buf) == 1)
         return buf[0];
      return 25.0;
     }

   double           SafeClamp(const double val, const double minVal, const double maxVal, const double fallback) const
     {
      if(!MathIsValidNumber(val))
         return fallback;
      if(val < minVal)
         return minVal;
      if(val > maxVal)
         return maxVal;
      return val;
     }

public:
                    CFeatureExtractor()
     {
      m_symbol          = _Symbol;
      m_brokerGMTOffset = 2;
      m_handleAdxH1     = INVALID_HANDLE;
      m_sessionLevels   = NULL;
      m_volumeProfile   = NULL;
      m_logger          = NULL;
     }

                   ~CFeatureExtractor()
     {
      Deinit();
     }

   bool             Init(const string symbol,
                         const int brokerGMTOffsetHours,
                         CSessionLevels *sessionLevels,
                         CVolumeProfile *volumeProfile,
                         CQuantLogger *logger)
     {
      m_symbol          = symbol;
      m_brokerGMTOffset = brokerGMTOffsetHours;
      m_sessionLevels   = sessionLevels;
      m_volumeProfile   = volumeProfile;
      m_logger          = logger;

      m_handleAdxH1 = iADX(m_symbol, PERIOD_H1, 14);
      if(m_handleAdxH1 == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error("CFeatureExtractor::Init failed to create iADX(H1, 14) indicator handle.");
         return false;
        }
      return true;
     }

   void             Deinit()
     {
      if(m_handleAdxH1 != INVALID_HANDLE)
        {
         IndicatorRelease(m_handleAdxH1);
         m_handleAdxH1 = INVALID_HANDLE;
        }
     }

   double           ComputeRollingM5HurstExponent() const
     {
      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, 1, HURST_WINDOW_BARS, m5);
      if(copied < HURST_WINDOW_BARS)
         return 0.50;

      double logPrices[HURST_WINDOW_BARS];
      for(int i = 0; i < HURST_WINDOW_BARS; i++)
        {
         double c = m5[HURST_WINDOW_BARS - 1 - i].close;
         logPrices[i] = (c > 0.0) ? MathLog(c) : 0.0;
        }

      const int lags[5] = {2, 4, 8, 16, 32};
      double logLags[5];
      double logStdDevs[5];
      int    validLags = 0;

      for(int l = 0; l < 5; l++)
        {
         int tau   = lags[l];
         int count = HURST_WINDOW_BARS - tau;
         if(count <= 2)
            continue;

         double sumDiff = 0.0;
         for(int i = 0; i < count; i++)
            sumDiff += (logPrices[i + tau] - logPrices[i]);
         double meanDiff = sumDiff / (double)count;

         double sumSq = 0.0;
         for(int i = 0; i < count; i++)
           {
            double d = (logPrices[i + tau] - logPrices[i]) - meanDiff;
            sumSq += d * d;
           }

         double stdDev = MathSqrt(sumSq / (double)count);
         if(stdDev <= 1e-12)
            continue;

         logLags[validLags]    = MathLog((double)tau);
         logStdDevs[validLags] = MathLog(stdDev);
         validLags++;
        }

      if(validLags < 3)
         return 0.50;

      double meanX = 0.0;
      double meanY = 0.0;
      for(int i = 0; i < validLags; i++)
        {
         meanX += logLags[i];
         meanY += logStdDevs[i];
        }
      meanX /= (double)validLags;
      meanY /= (double)validLags;

      double covXY = 0.0;
      double varX  = 0.0;
      for(int i = 0; i < validLags; i++)
        {
         double dx = logLags[i] - meanX;
         double dy = logStdDevs[i] - meanY;
         covXY += dx * dy;
         varX  += dx * dx;
        }

      if(varX <= 1e-12)
         return 0.50;

      double hurst = covXY / varX;
      return SafeClamp(hurst, 0.05, 0.95, 0.50);
     }

   bool             ExtractFeatures(const SSweepCandidateSetup &setup,
                                    const double currentSpreadUSD,
                                    SStationaryFeatures &outFeatures) const
     {
      outFeatures.Reset();
      if(!setup.isValid || m_sessionLevels == NULL)
         return false;

      double atrM15 = MathMax(100.0, m_sessionLevels.GetAtrM15());
      double atrH1  = MathMax(200.0, m_sessionLevels.GetAtrH1());
      double atrH4  = MathMax(400.0, m_sessionLevels.GetAtrH4());

      // [0] f0_sweep_depth_norm : (Sweep_Extreme_Distance_Beyond_Level) / ATR_M15(14)
      double f0 = setup.sweepDepthUSD / atrM15;
      outFeatures.f0_sweep_depth_norm = SafeClamp(f0, 0.0, 5.0, 0.30);

      // [1] f1_wick_body_ratio : Rejection_Wick_Size / MathMax(Candle_Range, 1.0)
      double f1 = setup.rejectionWickUSD / MathMax(setup.reclaimCandleRangeUSD, 1.0);
      outFeatures.f1_wick_body_ratio = SafeClamp(f1, 0.0, 1.0, 0.50);

      // [2] f2_bars_outside_level : Number of M1 bars spent beyond swept level before reclaim / 15.0
      double f2 = (double)setup.m1BarsOutsideLevel / 15.0;
      outFeatures.f2_bars_outside_level = SafeClamp(f2, 0.0, 3.0, 0.20);

      // [3] f3_rel_tick_volume : Sweep_M5_TickVol / SMA(M5_TickVol, 20)
      double f3 = setup.sweepM5TickVolume / MathMax(setup.sma20M5TickVolume, 1.0);
      outFeatures.f3_rel_tick_volume = SafeClamp(f3, 0.1, 10.0, 1.50);

      // [4] f4_vpoc_distance_norm : MathAbs(Entry_Price - Session_VPOC) / ATR_M15(14)
      double f4 = MathAbs(setup.entryLimitPrice - setup.vpocAtSignal) / atrM15;
      outFeatures.f4_vpoc_distance_norm = SafeClamp(f4, 0.0, 10.0, 1.0);

      // [5] f5_value_area_width_norm : (Session_VAH - Session_VAL) / ATR_H1(14)
      double vaWidth = MathMax(20.0, setup.vahAtSignal - setup.valAtSignal);
      double f5      = vaWidth / atrH1;
      outFeatures.f5_value_area_width_norm = SafeClamp(f5, 0.05, 10.0, 1.0);

      // [6] f6_h1_adx : ADX(H1, 14) / 100.0
      double f6 = ReadAdxH1() / 100.0;
      outFeatures.f6_h1_adx = SafeClamp(f6, 0.0, 1.0, 0.25);

      // [7] f7_hurst_exponent : Rolling 100-bar M5 Hurst Exponent H in [0, 1]
      double f7 = ComputeRollingM5HurstExponent();
      outFeatures.f7_hurst_exponent = SafeClamp(f7, 0.0, 1.0, 0.50);

      // [8] f8_volatility_ratio : ATR_M15(14) / ATR_H4(14)
      double f8 = atrM15 / atrH4;
      outFeatures.f8_volatility_ratio = SafeClamp(f8, 0.05, 3.0, 0.25);

      // [9] & [10] Cyclical UTC Hour Encoding: sin(2*pi*hour/24), cos(2*pi*hour/24)
      datetime utcSignal = (setup.signalTimeUTC > 0)
                           ? setup.signalTimeUTC
                           : ResolveCurrentUTCTime(m_brokerGMTOffset);
      MqlDateTime dtUTC;
      TimeToStruct(utcSignal, dtUTC);
      double currentUtcHour = (double)dtUTC.hour + ((double)dtUTC.min / 60.0);
      double angleRad       = 2.0 * M_PI * currentUtcHour / 24.0;

      outFeatures.f9_hour_sin  = SafeClamp(MathSin(angleRad), -1.0, 1.0, 0.0);
      outFeatures.f10_hour_cos = SafeClamp(MathCos(angleRad), -1.0, 1.0, 1.0);

      // [11] f11_spread_to_sl_ratio : Institutional $25.00 baseline spread floor / Stop_Loss_Distance_In_USD
      // Ensures zero feature skew between Model=1, Model=4 (Real Ticks), and live prop accounts
      double slDistUSD          = MathMax(HARD_MIN_SL_DISTANCE_USD, setup.slDistanceUSD);
      double effectiveSpreadUSD = MathMax(25.0, currentSpreadUSD);
      double f11                = effectiveSpreadUSD / slDistUSD;
      outFeatures.f11_spread_to_sl_ratio = SafeClamp(f11, 0.0, 1.0, 0.08);

      outFeatures.SyncTensor();
      return true;
     }
  };

#endif // BTCUSD_QUANT_FEATURE_EXTRACTOR_MQH
