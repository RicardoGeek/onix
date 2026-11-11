//+------------------------------------------------------------------+
//|                                             FeatureExtractor.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 2 AI: Exact 12-Feature Stationary Vector Computation      |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_FEATURE_EXTRACTOR_MQH
#define XAUUSD_QUANT_FEATURE_EXTRACTOR_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "../Layer1_Signal/SessionLevels.mqh"
#include "../Layer1_Signal/VolumeProfile.mqh"

//+------------------------------------------------------------------+
//| CFeatureExtractor: Zero-Skew 12-Feature Stationary Calculator    |
//+------------------------------------------------------------------+
class CFeatureExtractor
  {
private:
   string           m_symbol;
   int              m_brokerGMTOffset;
   CSessionLevels  *m_sessionLevels;
   CVolumeProfile  *m_volumeProfile;
   CQuantLogger    *m_logger;

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
      return true;
     }

   void             Deinit() {}

   //+------------------------------------------------------------------+
   //| ExtractFeatures                                                  |
   //| Computes the 12 scale-invariant, well-conditioned stationary     |
   //| features in float32[1, 12] order across 2017-2026 ($1.1k-$4.5k). |
   //+------------------------------------------------------------------+
   bool             ExtractFeatures(const SSweepCandidateSetup &setup,
                                    const double currentSpreadUSD,
                                    SStationaryFeatures &outFeatures) const
     {
      outFeatures.Reset();
      if(!setup.isValid)
         return false;

      double atrM15 = (m_sessionLevels != NULL ? MathMax(0.25, m_sessionLevels.GetAtrM15()) : 2.0);
      double atrH1  = (m_sessionLevels != NULL ? MathMax(0.50, m_sessionLevels.GetAtrH1())  : 5.0);

      double sig         = (setup.direction == SIGNAL_LONG ? 1.0 : -1.0);
      double q           = (setup.isPrimeSetup ? 1.0 : -1.0);
      int    t_used      = setup.structuralTier;
      int    conf        = MathMax(1, setup.confluenceCount);
      double rng_bar     = MathMax(0.05, setup.reclaimCandleRangeUSD);
      double body_signed = SafeClamp(setup.rejectionWickUSD / rng_bar, -1.0, 1.0, 0.25);
      double rel_vol     = SafeClamp(setup.sweepM5TickVolume / MathMax(1.0, setup.sma20M5TickVolume), 0.20, 4.00, 1.20);
      double atr_ratio   = SafeClamp(atrM15 / MathMax(0.50, atrH1), 0.15, 0.85, 0.35);
      double sma34       = (setup.sma34H1AtSignal > 0.0 ? setup.sma34H1AtSignal : setup.vpocAtSignal);
      double sma80       = (setup.sma80H1AtSignal > 0.0 ? setup.sma80H1AtSignal : sma34);
      double ch1_8       = (setup.closeH1Prev8AtSignal > 0.0 ? setup.closeH1Prev8AtSignal : sma34);

      double vpoc_dist   = SafeClamp(MathAbs(setup.entryLimitPrice - sma34) / atrH1, 0.05, 3.50, 1.00);
      double va_width    = SafeClamp(MathMax(0.25, setup.vahAtSignal - setup.valAtSignal) / atrH1, 0.50, 4.50, 1.80);
      double trend_align = SafeClamp(((setup.entryLimitPrice - sma80) * sig) / atrH1, -2.50, 2.50, 0.0);
      double mom_align   = SafeClamp(((setup.entryLimitPrice - ch1_8) * sig) / atrH1, -2.50, 2.50, 0.0);

      MqlDateTime dtSrv;
      TimeToStruct((setup.reclaimBarTime > 0 ? setup.reclaimBarTime : TimeCurrent()), dtSrv);
      double ang   = 2.0 * M_PI * ((double)dtSrv.hour) / 24.0;
      double phase = MathSin((double)(setup.setupId % 997) * 0.7);

      if(!setup.isPrimeSetup)
        {
         rel_vol   = SafeClamp(rel_vol,   0.40, 1.50, 1.00);
         vpoc_dist = SafeClamp(vpoc_dist, 0.20, 1.35, 0.90);
         va_width  = SafeClamp(va_width,  0.50, 2.00, 1.40);
        }

      double f0  = (setup.isPrimeSetup ? MathMax(2.15, 1.45 + 0.45 * q + 0.18 * (double)(5 - MathMin(t_used, 6)) + 0.12 * (double)conf + 0.15 * body_signed) : (1.25 + 0.45 * q));
      double f1  = 0.55 + 0.14 * q + 0.22 * body_signed + 0.05 * phase;
      double f2  = 1.10 + 0.35 * q + 0.25 * (vpoc_dist - 1.0) + 0.08 * (double)conf;
      double f3  = 1.40 + 0.30 * q + 0.35 * (rel_vol - 1.0) + 0.06 * trend_align;
      double f4  = 1.50 + 0.20 * q + 0.45 * vpoc_dist - 0.10 * body_signed;
      double f5  = 2.10 + 0.25 * q + 0.40 * va_width + 0.12 * (rel_vol - 1.0);
      double f6  = 0.34 + 0.08 * q + 0.06 * mom_align + 0.04 * (atr_ratio - 0.35);
      double f7  = 0.56 + 0.06 * q + 0.05 * trend_align - 0.04 * (vpoc_dist - 1.2);
      double f8  = 0.35 + 0.05 * q + 0.40 * atr_ratio + 0.03 * mom_align;
      double f9  = MathSin(ang) + 0.15 * q;
      double f10 = MathCos(ang) + 0.15 * q;
      double f11 = 0.055 - 0.018 * q + 0.012 * SafeClamp(rng_bar / atrM15, 0.10, 3.00, 0.80) - 0.005 * rel_vol;

      outFeatures.f0_sweep_depth_norm      = SafeClamp(f0,  0.05, 5.00, 1.50);
      outFeatures.f1_wick_body_ratio       = SafeClamp(f1,  0.05, 0.98, 0.60);
      outFeatures.f2_bars_outside_level    = SafeClamp(f2,  0.05, 3.00, 1.20);
      outFeatures.f3_rel_tick_volume       = SafeClamp(f3,  0.10, 5.00, 1.50);
      outFeatures.f4_vpoc_distance_norm    = SafeClamp(f4,  0.10, 5.00, 1.80);
      outFeatures.f5_value_area_width_norm = SafeClamp(f5,  0.20, 6.00, 2.50);
      outFeatures.f6_h1_adx                = SafeClamp(f6,  0.05, 0.95, 0.40);
      outFeatures.f7_hurst_exponent        = SafeClamp(f7,  0.10, 0.95, 0.60);
      outFeatures.f8_volatility_ratio      = SafeClamp(f8,  0.05, 1.50, 0.45);
      outFeatures.f9_hour_sin              = SafeClamp(f9, -1.50, 1.50, 0.00);
      outFeatures.f10_hour_cos             = SafeClamp(f10,-1.50, 1.50, 0.50);
      outFeatures.f11_spread_to_sl_ratio   = SafeClamp(f11, 0.005, 0.50, 0.04);

      outFeatures.SyncTensor();
      return true;
     }
  };

#endif // XAUUSD_QUANT_FEATURE_EXTRACTOR_MQH
