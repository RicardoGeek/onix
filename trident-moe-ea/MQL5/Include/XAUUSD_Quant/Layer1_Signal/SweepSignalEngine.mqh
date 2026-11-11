//+------------------------------------------------------------------+
//|                                            SweepSignalEngine.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|    Layer 1 Signal: 14-Pattern Multi-Timeframe Asymmetric Engine  |
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

#define PAT1_TIERS   6
#define PAT2_TIERS   4
#define PAT3_TIERS   3
#define PAT4_TIERS   4
#define PAT5_TIERS   4
#define PAT7_TIERS   3
#define PAT8_TIERS   6
#define PAT9_TIERS   5
#define PAT10_TIERS  4
#define PAT30_TIERS  6
#define PAT45_TIERS  6
#define PAT60_TIERS  6
#define PAT61_TIERS  4
#define PAT81_TIERS  6
#define PAT82_TIERS  6
#define PAT90_TIERS  4
#define PAT91_TIERS  4
#define PAT92_TIERS  3
#define PAT93_TIERS  6
#define PAT94_TIERS  5

//+------------------------------------------------------------------+
//| CSweepSignalEngine: 14-Pattern Structural Swing & Regime Engine  |
//+------------------------------------------------------------------+
class CSweepSignalEngine
  {
private:
   string                m_symbol;
   int                   m_brokerGMTOffset;
   ulong                 m_magic;
   CSessionLevels       *m_sessionLevels;
   CVolumeProfile       *m_volumeProfile;
   CQuantLogger         *m_logger;

   double                m_minSweepAtrRatio;
   double                m_maxSweepAtrRatio;
   double                m_minAbsorptionVolRatio;
   int                   m_maxReclaimBarsM5;
   int                   m_limitExpiryBarsM5;

   ENUM_SWEEP_STATE      m_state;
   bool                  m_hasPendingOrder;
   ulong                 m_nextSetupSequenceId;

   //--- Cached Bar Timestamps
   datetime              m_lastH1BarTime;
   datetime              m_lastM30BarTime;
   long                  m_lastM45Bucket;
   datetime              m_lastH2BarTime;
   datetime              m_lastH4BarTime;
   datetime              m_lastD1BarTime;
   datetime              m_lastM15BarTime;
   datetime              m_lastM5BarTime;
   datetime              m_lastM1BarTime;
   bool                  m_triggeredThisM5Bar;
   bool                  m_triggeredThisM1Bar;
   int                   m_m5BarCounter;

   //--- Pat 1: Primary H1 Unbroken Swings (28/13, 26/13, 22/11, 18/9, 15/7, 12/6)
   double                m_p1Buy[PAT1_TIERS];
   double                m_p1Sell[PAT1_TIERS];
   double                m_p1UsedBuy[PAT1_TIERS];
   double                m_p1UsedSell[PAT1_TIERS];

   //--- Pat 2: Extended H1 Unbroken Swings (34/14, 30/13, 24/11, 20/10)
   double                m_p2Buy[PAT2_TIERS];
   double                m_p2Sell[PAT2_TIERS];
   double                m_p2UsedBuy[PAT2_TIERS];
   double                m_p2UsedSell[PAT2_TIERS];

   //--- Pat 3: M30 Core Unbroken Swings (28/13, 24/11, 20/9)
   double                m_p3Buy[PAT3_TIERS];
   double                m_p3Sell[PAT3_TIERS];
   double                m_p3UsedBuy[PAT3_TIERS];
   double                m_p3UsedSell[PAT3_TIERS];

   //--- Pat 4 (m=0: PDH/PDL) & Pat 11 (m=1..3: 2D/3D/5D Rolling High/Low)
   double                m_p4Buy[PAT4_TIERS];
   double                m_p4Sell[PAT4_TIERS];
   double                m_p4UsedBuy[PAT4_TIERS];
   double                m_p4UsedSell[PAT4_TIERS];

   //--- Pat 5: Fast H1 Continuation Swings (10/5, 9/4, 8/4, 7/3)
   double                m_p5Buy[PAT5_TIERS];
   double                m_p5Sell[PAT5_TIERS];
   double                m_p5UsedBuy[PAT5_TIERS];
   double                m_p5UsedSell[PAT5_TIERS];

   //--- Pat 7: M30 Low-Vol Precision Swings (34/14, 30/13, 16/8)
   double                m_p7Buy[PAT7_TIERS];
   double                m_p7Sell[PAT7_TIERS];
   double                m_p7UsedBuy[PAT7_TIERS];
   double                m_p7UsedSell[PAT7_TIERS];

   //--- Pat 8: H2 2-Hour Unbroken Swings (20/9, 16/8, 14/7, 12/6, 10/5, 8/4)
   double                m_p8Buy[PAT8_TIERS];
   double                m_p8Sell[PAT8_TIERS];
   double                m_p8UsedBuy[PAT8_TIERS];
   double                m_p8UsedSell[PAT8_TIERS];

   //--- Pat 9: H4 4-Hour Unbroken Swings (14/6, 12/5, 10/4, 8/3, 6/3)
   double                m_p9Buy[PAT9_TIERS];
   double                m_p9Sell[PAT9_TIERS];
   double                m_p9UsedBuy[PAT9_TIERS];
   double                m_p9UsedSell[PAT9_TIERS];

   //--- Pat 10: Intermediate H1 Swings (16/8, 14/7, 13/6, 11/5)
   double                m_p10Buy[PAT10_TIERS];
   double                m_p10Sell[PAT10_TIERS];
   double                m_p10UsedBuy[PAT10_TIERS];
   double                m_p10UsedSell[PAT10_TIERS];

   //--- Pat 30: Full 6-Tier M30 Unbroken Swings (34/14, 30/13, 28/13, 26/12, 24/11, 22/11)
   double                m_p30Buy[PAT30_TIERS];
   double                m_p30Sell[PAT30_TIERS];
   double                m_p30UsedBuy[PAT30_TIERS];
   double                m_p30UsedSell[PAT30_TIERS];

   //--- Pat 45: Full 6-Tier M45 Unbroken Swings (28/13, 26/12, 22/11, 18/9, 16/8, 14/7)
   double                m_p45Buy[PAT45_TIERS];
   double                m_p45Sell[PAT45_TIERS];
   double                m_p45UsedBuy[PAT45_TIERS];
   double                m_p45UsedSell[PAT45_TIERS];

   //--- Pat 60: Asymmetric H1 Same-Day Continuation Swings (28/5, 24/5, 24/4, 20/4, 20/3, 16/3)
   double                m_p60Buy[PAT60_TIERS];
   double                m_p60Sell[PAT60_TIERS];
   double                m_p60UsedBuy[PAT60_TIERS];
   double                m_p60UsedSell[PAT60_TIERS];

   //--- Pat 61: Asymmetric M30 Same-Day Continuation Swings (36/9, 32/8, 28/7, 24/6)
   double                m_p61Buy[PAT61_TIERS];
   double                m_p61Sell[PAT61_TIERS];
   double                m_p61UsedBuy[PAT61_TIERS];
   double                m_p61UsedSell[PAT61_TIERS];

   //--- Pat 81: M30 Fast 6-Tier Ladder (18/8, 16/7, 14/6, 12/5, 10/4, 8/3)
   double                m_p81Buy[PAT81_TIERS];
   double                m_p81Sell[PAT81_TIERS];
   double                m_p81UsedBuy[PAT81_TIERS];
   double                m_p81UsedSell[PAT81_TIERS];

   //--- Pat 82: H2 Full 6-Tier Ladder (24/11, 20/9, 16/8, 14/7, 12/6, 10/5)
   double                m_p82Buy[PAT82_TIERS];
   double                m_p82Sell[PAT82_TIERS];
   double                m_p82UsedBuy[PAT82_TIERS];
   double                m_p82UsedSell[PAT82_TIERS];

   //--- Pat 90: H1 1-3h High-Tight Flag Continuation (W = 3, 4, 5, 6)
   double                m_p90Buy[PAT90_TIERS];
   double                m_p90UsedBuy[PAT90_TIERS];

   //--- Pat 91: H1 3-6h Volatility Coil Box Breakout (W = 3, 4, 5, 6)
   double                m_p91Buy[PAT91_TIERS];
   double                m_p91UsedBuy[PAT91_TIERS];

   //--- Pat 92: H1 Trend Pullback Hook Reclaim Below 14h High (W = 2, 3, 4)
   double                m_p92Buy[PAT92_TIERS];
   double                m_p92UsedBuy[PAT92_TIERS];

   //--- Pat 93: H1 2-5h Pause Donchian Breakout (W = 6, 9, 12, 16, 20, 24)
   double                m_p93Buy[PAT93_TIERS];
   double                m_p93UsedBuy[PAT93_TIERS];

   //--- Pat 94: M30 Pullback Hook Reclaim & M30 Fast Flag (5 Tiers)
   double                m_p94Buy[PAT94_TIERS];
   double                m_p94UsedBuy[PAT94_TIERS];

   //--- Secondary M15 10/4 Minor Fractal Levels (Tier 7 off-peak telemetry)
   double                m_secBuy;
   double                m_secSell;
   double                m_secUsedBuy;
   double                m_secUsedSell;

   //--- Cached Regime & Volatility Context
   double                m_atrH1;
   double                m_atr120H1;
   double                m_atrM15;
   double                m_sma34H1;
   double                m_sma80H1;
   double                m_sma200H1;
   double                m_sma480H1;
   double                m_closeH1Prev8;
   double                m_curM5Open;
   double                m_curM1Open;
   double                m_prevM5Body;
   double                m_prevM5Range;
   double                m_prevM5Vol;
   double                m_sma20Vol;
   double                m_vaWidthUSD;

   SSweepCandidateSetup  m_latestSetup;

   //--- Generic Unbroken Structural Swing Finder on MqlRates[] (Series: index 0 = most recently closed bar)
   void                  FindUnbrokenSwingOnRates(const MqlRates &rates[],
                                                  const int copied,
                                                  const int leftBars,
                                                  const int rightBars,
                                                  const int maxLookback,
                                                  double &outBuyLvl,
                                                  double &outSellLvl) const
     {
      outBuyLvl  = 0.0;
      outSellLvl = 0.0;
      int limit  = MathMin(copied - leftBars - 1, maxLookback - 1);
      if(limit <= rightBars)
         return;

      double bestHi = -1e18;
      for(int s = 0; s <= limit; s++)
        {
         double x = rates[s].high;
         if(s > rightBars)
           {
            bool isPeak = true;
            int wStart  = MathMax(0, s - rightBars);
            int wEnd    = s + leftBars;
            for(int k = wStart; k <= wEnd; k++)
              {
               if(rates[k].high > x)
                 {
                  isPeak = false;
                  break;
                 }
              }
            if(isPeak && x > bestHi)
              {
               outBuyLvl = x;
               break;
              }
           }
         if(x > bestHi)
            bestHi = x;
        }

      double bestLo = -1e18;
      for(int s = 0; s <= limit; s++)
        {
         double x = -rates[s].low;
         if(s > rightBars)
           {
            bool isTrough = true;
            int wStart    = MathMax(0, s - rightBars);
            int wEnd      = s + leftBars;
            for(int k = wStart; k <= wEnd; k++)
              {
               if((-rates[k].low) > x)
                 {
                  isTrough = false;
                  break;
                 }
              }
            if(isTrough && x > bestLo)
              {
               outSellLvl = rates[s].low;
               break;
              }
           }
         if(x > bestLo)
            bestLo = x;
        }
     }

   //--- Update H1 Structural Swings (Pat 1, Pat 2, Pat 5, Pat 10, Pat 60) + Exact H1 Indicators
   void                  UpdateH1Levels()
     {
      datetime curH1 = iTime(m_symbol, PERIOD_H1, 0);
      if(curH1 <= 0 || curH1 == m_lastH1BarTime)
         return;
      m_lastH1BarTime = curH1;

      MqlRates h1[];
      ArraySetAsSeries(h1, true);
      int copied = CopyRates(m_symbol, PERIOD_H1, 1, 485, h1);
      if(copied < 40)
         return;

      // 14-bar and 120-bar H1 range means (exact match with h1['high'] - h1['low'] in Python)
      double rng14 = 0.0;
      int n14 = MathMin(14, copied);
      for(int i = 0; i < n14; i++)
         rng14 += (h1[i].high - h1[i].low);
      m_atrH1 = MathMax(0.50, rng14 / (double)n14);

      double rng120 = 0.0;
      int n120 = MathMin(120, copied);
      for(int i = 0; i < n120; i++)
         rng120 += (h1[i].high - h1[i].low);
      m_atr120H1 = MathMax(0.50, rng120 / (double)n120);

      // 34, 80, 200, 480-hour Close SMAs
      double sum34 = 0.0;
      for(int i = 0; i < 34; i++)
         sum34 += h1[i].close;
      m_sma34H1 = sum34 / 34.0;

      int n80 = MathMin(80, copied);
      double sum80 = 0.0;
      for(int i = 0; i < n80; i++)
         sum80 += h1[i].close;
      m_sma80H1 = sum80 / (double)n80;

      int n200 = MathMin(200, copied);
      double sum200 = 0.0;
      for(int i = 0; i < n200; i++)
         sum200 += h1[i].close;
      m_sma200H1 = sum200 / (double)n200;

      int n480 = MathMin(480, copied);
      double sum480 = 0.0;
      for(int i = 0; i < n480; i++)
         sum480 += h1[i].close;
      m_sma480H1 = sum480 / (double)n480;

      m_closeH1Prev8 = (copied > 7 ? h1[7].close : h1[0].close);

      // Pat 1: 6-Tier Core H1 Ladder
      const int p1L[PAT1_TIERS] = {28, 26, 22, 18, 15, 12};
      const int p1R[PAT1_TIERS] = {13, 13, 11,  9,  7,  6};
      for(int m = 0; m < PAT1_TIERS; m++)
         FindUnbrokenSwingOnRates(h1, copied, p1L[m], p1R[m], 220, m_p1Buy[m], m_p1Sell[m]);

      // Pat 2: Extended H1 Swings
      const int p2L[PAT2_TIERS] = {34, 30, 24, 20};
      const int p2R[PAT2_TIERS] = {14, 13, 11, 10};
      const int p2K[PAT2_TIERS] = {240, 240, 220, 220};
      for(int m = 0; m < PAT2_TIERS; m++)
         FindUnbrokenSwingOnRates(h1, copied, p2L[m], p2R[m], p2K[m], m_p2Buy[m], m_p2Sell[m]);

      // Pat 5: Fast H1 Continuation Swings (10/5, 9/4, 8/4, 7/3)
      const int p5L[PAT5_TIERS] = {10, 9, 8, 7};
      const int p5R[PAT5_TIERS] = { 5, 4, 4, 3};
      for(int m = 0; m < PAT5_TIERS; m++)
         FindUnbrokenSwingOnRates(h1, copied, p5L[m], p5R[m], 180, m_p5Buy[m], m_p5Sell[m]);

      // Pat 10: Intermediate H1 Swings (16/8, 14/7, 13/6, 11/5)
      const int p10L[PAT10_TIERS] = {16, 14, 13, 11};
      const int p10R[PAT10_TIERS] = { 8,  7,  6,  5};
      for(int m = 0; m < PAT10_TIERS; m++)
         FindUnbrokenSwingOnRates(h1, copied, p10L[m], p10R[m], 200, m_p10Buy[m], m_p10Sell[m]);

      // Pat 60: Asymmetric H1 Same-Day Continuation Swings
      const int p60L[PAT60_TIERS] = {28, 24, 24, 20, 20, 16};
      const int p60R[PAT60_TIERS] = { 5,  5,  4,  4,  3,  3};
      for(int m = 0; m < PAT60_TIERS; m++)
         FindUnbrokenSwingOnRates(h1, copied, p60L[m], p60R[m], 180, m_p60Buy[m], m_p60Sell[m]);

      // Pat 90 (1-3h High-Tight Flag) & Pat 91 (3-6h Volatility Coil Box)
      const int p90W[PAT90_TIERS] = {3, 4, 5, 6};
      for(int ti = 0; ti < PAT90_TIERS; ti++)
        {
         int w = p90W[ti];
         m_p90Buy[ti] = 0.0;
         m_p91Buy[ti] = 0.0;
         if(copied > w + 4)
           {
            double maxH = -1e18, minL = 1e18;
            int    barsSinceH = 1;
            for(int i = 0; i < w; i++)
              {
               if(h1[i].high >= maxH) { maxH = h1[i].high; barsSinceH = i + 1; }
               if(h1[i].low  <  minL) { minL = h1[i].low; }
              }
            if(barsSinceH >= 1 && barsSinceH <= 3)
              {
               double minSinceH = 1e18;
               for(int i = 0; i < barsSinceH; i++)
                  if(h1[i].low < minSinceH) minSinceH = h1[i].low;
               double minPrior = 1e18;
               for(int i = barsSinceH - 1; i < w + 4; i++)
                  if(h1[i].low < minPrior) minPrior = h1[i].low;
               if((maxH - minSinceH) <= 1.25 * m_atrH1 && (maxH - minPrior) >= 1.60 * m_atrH1)
                  m_p90Buy[ti] = maxH;
              }
            if((maxH - minL) <= (1.10 + 0.14 * (double)w) * m_atrH1)
               m_p91Buy[ti] = maxH;
           }
        }

      // Pat 92: H1 Pullback Hook Reclaim (0.35..2.50 * ATR below 14h high)
      double h14 = -1e18;
      for(int i = 0; i < 14 && i < copied; i++)
         if(h1[i].high > h14) h14 = h1[i].high;
      const int p92W[PAT92_TIERS] = {2, 3, 4};
      for(int ti = 0; ti < PAT92_TIERS; ti++)
        {
         int w = p92W[ti];
         m_p92Buy[ti] = 0.0;
         double mh = -1e18;
         for(int i = 0; i < w && i < copied; i++)
            if(h1[i].high > mh) mh = h1[i].high;
         if((h14 - mh) >= 0.35 * m_atrH1 && (h14 - mh) <= 2.50 * m_atrH1 && h1[0].high < mh)
            m_p92Buy[ti] = mh;
        }

      // Pat 93: H1 2-5h Pause Donchian Breakout (W = 6, 9, 12, 16, 20, 24)
      const int p93W[PAT93_TIERS] = {6, 9, 12, 16, 20, 24};
      for(int ti = 0; ti < PAT93_TIERS; ti++)
        {
         int w = p93W[ti];
         m_p93Buy[ti] = 0.0;
         if(copied > w)
           {
            double maxH = -1e18;
            int    barsSinceH = 1;
            for(int i = 0; i < w; i++)
              {
               if(h1[i].high >= maxH) { maxH = h1[i].high; barsSinceH = i + 1; }
              }
            if(barsSinceH >= 2 && barsSinceH <= 5)
               m_p93Buy[ti] = maxH;
           }
        }
     }

   //--- Update M30 Structural Swings (Pat 3, Pat 7, Pat 30, Pat 61)
   void                  UpdateM30Levels()
     {
      datetime curM30 = iTime(m_symbol, PERIOD_M30, 0);
      if(curM30 <= 0 || curM30 == m_lastM30BarTime)
         return;
      m_lastM30BarTime = curM30;

      MqlRates m30[];
      ArraySetAsSeries(m30, true);
      int copied = CopyRates(m_symbol, PERIOD_M30, 1, 250, m30);
      if(copied < 55)
         return;

      // Pat 3: (28/13, 24/11, 20/9)
      const int p3L[PAT3_TIERS] = {28, 24, 20};
      const int p3R[PAT3_TIERS] = {13, 11,  9};
      for(int m = 0; m < PAT3_TIERS; m++)
         FindUnbrokenSwingOnRates(m30, copied, p3L[m], p3R[m], 220, m_p3Buy[m], m_p3Sell[m]);

      // Pat 7: (34/14, 30/13, 16/8)
      const int p7L[PAT7_TIERS] = {34, 30, 16};
      const int p7R[PAT7_TIERS] = {14, 13,  8};
      const int p7K[PAT7_TIERS] = {220, 220, 200};
      for(int m = 0; m < PAT7_TIERS; m++)
         FindUnbrokenSwingOnRates(m30, copied, p7L[m], p7R[m], p7K[m], m_p7Buy[m], m_p7Sell[m]);

      // Pat 30: (34/14, 30/13, 28/13, 26/12, 24/11, 22/11)
      const int p30L[PAT30_TIERS] = {34, 30, 28, 26, 24, 22};
      const int p30R[PAT30_TIERS] = {14, 13, 13, 12, 11, 11};
      for(int m = 0; m < PAT30_TIERS; m++)
         FindUnbrokenSwingOnRates(m30, copied, p30L[m], p30R[m], 220, m_p30Buy[m], m_p30Sell[m]);

      // Pat 61: Asymmetric M30 Same-Day Swings (36/9, 32/8, 28/7, 24/6)
      const int p61L[PAT61_TIERS] = {36, 32, 28, 24};
      const int p61R[PAT61_TIERS] = { 9,  8,  7,  6};
      for(int m = 0; m < PAT61_TIERS; m++)
         FindUnbrokenSwingOnRates(m30, copied, p61L[m], p61R[m], 200, m_p61Buy[m], m_p61Sell[m]);

      // Pat 81: M30 Fast 6-Tier Ladder (18/8, 16/7, 14/6, 12/5, 10/4, 8/3)
      const int p81L[PAT81_TIERS] = {18, 16, 14, 12, 10, 8};
      const int p81R[PAT81_TIERS] = { 8,  7,  6,  5,  4, 3};
      for(int m = 0; m < PAT81_TIERS; m++)
         FindUnbrokenSwingOnRates(m30, copied, p81L[m], p81R[m], 160, m_p81Buy[m], m_p81Sell[m]);

      // Pat 94: M30 Pullback Hook Reclaim (Tiers 0..2) & M30 Fast Flag (Tiers 3..4)
      double h24 = -1e18;
      for(int i = 0; i < 24 && i < copied; i++)
         if(m30[i].high > h24) h24 = m30[i].high;
      const int p94HookW[3] = {3, 4, 6};
      for(int ti = 0; ti < 3; ti++)
        {
         int w = p94HookW[ti];
         m_p94Buy[ti] = 0.0;
         double mh = -1e18;
         for(int i = 0; i < w && i < copied; i++)
            if(m30[i].high > mh) mh = m30[i].high;
         if((h24 - mh) >= 0.35 * m_atrH1 && (h24 - mh) <= 2.40 * m_atrH1 && m30[0].high < mh)
            m_p94Buy[ti] = mh;
        }
      const int p94FlagW[2] = {4, 6};
      for(int idxW = 0; idxW < 2; idxW++)
        {
         int ti = 3 + idxW;
         int w  = p94FlagW[idxW];
         m_p94Buy[ti] = 0.0;
         double mh = -1e18;
         int    bsH = 1;
         for(int i = 0; i < w && i < copied; i++)
           {
            if(m30[i].high >= mh) { mh = m30[i].high; bsH = i + 1; }
           }
         if(bsH >= 1 && bsH <= 3 && copied > w + 6)
           {
            double minPb = 1e18;
            for(int i = 0; i < bsH; i++)
               if(m30[i].low < minPb) minPb = m30[i].low;
            double minImp = 1e18;
            for(int i = bsH - 1; i < w + 6; i++)
               if(m30[i].low < minImp) minImp = m30[i].low;
            if((mh - minPb) <= 1.10 * m_atrH1 && (mh - minImp) >= 1.55 * m_atrH1)
               m_p94Buy[ti] = mh;
           }
        }
     }

   //--- Update M45 Structural Swings (Pat 45 synthesized from M15 bars grouped by 2700s buckets)
   void                  UpdateM45Levels()
     {
      datetime nowSrv = TimeCurrent();
      if(nowSrv <= 0)
         return;
      long curBucket = (long)nowSrv / 2700;
      if(curBucket == m_lastM45Bucket)
         return;
      m_lastM45Bucket = curBucket;

      MqlRates m15[];
      ArraySetAsSeries(m15, false); // chronological: oldest -> newest
      int copied = CopyRates(m_symbol, PERIOD_M15, 0, 750, m15);
      if(copied < 180)
         return;

      MqlRates m45Chrono[260];
      int      m45Count   = 0;
      long     activeBuck = -1;

      for(int i = 0; i < copied; i++)
        {
         long b = (long)m15[i].time / 2700;
         if(b >= curBucket)
            break; // exclude currently forming M45 bucket
         if(b != activeBuck)
           {
            if(m45Count >= 255)
               break;
            activeBuck = b;
            m45Chrono[m45Count] = m15[i];
            m45Count++;
           }
         else
           {
            int idx = m45Count - 1;
            if(m15[i].high > m45Chrono[idx].high)
               m45Chrono[idx].high = m15[i].high;
            if(m15[i].low < m45Chrono[idx].low)
               m45Chrono[idx].low = m15[i].low;
            m45Chrono[idx].close = m15[i].close;
           }
        }

      if(m45Count < 50)
         return;

      MqlRates m45Series[];
      ArrayResize(m45Series, m45Count);
      for(int i = 0; i < m45Count; i++)
         m45Series[i] = m45Chrono[m45Count - 1 - i];

      const int p45L[PAT45_TIERS] = {28, 26, 22, 18, 16, 14};
      const int p45R[PAT45_TIERS] = {13, 12, 11,  9,  8,  7};
      for(int m = 0; m < PAT45_TIERS; m++)
         FindUnbrokenSwingOnRates(m45Series, m45Count, p45L[m], p45R[m], 220, m_p45Buy[m], m_p45Sell[m]);
     }

   //--- Update H2 Structural Swings (Pat 8)
   void                  UpdateH2Levels()
     {
      datetime curH2 = iTime(m_symbol, PERIOD_H2, 0);
      if(curH2 <= 0 || curH2 == m_lastH2BarTime)
         return;
      m_lastH2BarTime = curH2;

      MqlRates h2[];
      ArraySetAsSeries(h2, true);
      int copied = CopyRates(m_symbol, PERIOD_H2, 1, 230, h2);
      if(copied < 35)
         return;

      const int p8L[PAT8_TIERS] = {20, 16, 14, 12, 10, 8};
      const int p8R[PAT8_TIERS] = { 9,  8,  7,  6,  5, 4};
      for(int m = 0; m < PAT8_TIERS; m++)
         FindUnbrokenSwingOnRates(h2, copied, p8L[m], p8R[m], 200, m_p8Buy[m], m_p8Sell[m]);

      const int p82L[PAT82_TIERS] = {24, 20, 16, 14, 12, 10};
      const int p82R[PAT82_TIERS] = {11,  9,  8,  7,  6,  5};
      for(int m = 0; m < PAT82_TIERS; m++)
         FindUnbrokenSwingOnRates(h2, copied, p82L[m], p82R[m], 160, m_p82Buy[m], m_p82Sell[m]);
     }

   //--- Update H4 Structural Swings (Pat 9)
   void                  UpdateH4Levels()
     {
      datetime curH4 = iTime(m_symbol, PERIOD_H4, 0);
      if(curH4 <= 0 || curH4 == m_lastH4BarTime)
         return;
      m_lastH4BarTime = curH4;

      MqlRates h4[];
      ArraySetAsSeries(h4, true);
      int copied = CopyRates(m_symbol, PERIOD_H4, 1, 190, h4);
      if(copied < 25)
         return;

      const int p9L[PAT9_TIERS] = {14, 12, 10, 8, 6};
      const int p9R[PAT9_TIERS] = { 6,  5,  4, 3, 3};
      for(int m = 0; m < PAT9_TIERS; m++)
         FindUnbrokenSwingOnRates(h4, copied, p9L[m], p9R[m], 160, m_p9Buy[m], m_p9Sell[m]);
     }

   //--- Update Daily Levels (Pat 4: PDH/PDL, Pat 11: 2D/3D/5D Rolling High/Low)
   void                  UpdateD1Levels()
     {
      datetime curD1 = iTime(m_symbol, PERIOD_D1, 0);
      if(curD1 <= 0 || curD1 == m_lastD1BarTime)
         return;
      m_lastD1BarTime = curD1;

      MqlRates d1[];
      ArraySetAsSeries(d1, true);
      int copied = CopyRates(m_symbol, PERIOD_D1, 1, 10, d1);
      if(copied < 5)
         return;

      m_p4Buy[0]  = d1[0].high;
      m_p4Sell[0] = d1[0].low;

      m_p4Buy[1]  = MathMax(d1[0].high, d1[1].high);
      m_p4Sell[1] = MathMin(d1[0].low,  d1[1].low);

      m_p4Buy[2]  = MathMax(m_p4Buy[1],  d1[2].high);
      m_p4Sell[2] = MathMin(m_p4Sell[1], d1[2].low);

      double hi5 = m_p4Buy[2];
      double lo5 = m_p4Sell[2];
      for(int k = 3; k < 5 && k < copied; k++)
        {
         if(d1[k].high > hi5) hi5 = d1[k].high;
         if(d1[k].low  < lo5) lo5 = d1[k].low;
        }
      m_p4Buy[3]  = hi5;
      m_p4Sell[3] = lo5;
     }

   //--- Update M15 Minor Fractal Levels (Tier 7 off-peak telemetry)
   void                  UpdateM15Levels()
     {
      datetime curM15 = iTime(m_symbol, PERIOD_M15, 0);
      if(curM15 <= 0 || curM15 == m_lastM15BarTime)
         return;
      m_lastM15BarTime = curM15;

      MqlRates m15[];
      ArraySetAsSeries(m15, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 1, 90, m15);
      if(copied < 25)
         return;

      double trSum = 0.0;
      for(int i = 0; i < 14; i++)
        {
         double tr = m15[i].high - m15[i].low;
         tr = MathMax(tr, MathAbs(m15[i].high - m15[i + 1].close));
         tr = MathMax(tr, MathAbs(m15[i].low  - m15[i + 1].close));
         trSum += tr;
        }
      m_atrM15 = MathMax(0.25, trSum / 14.0);

      FindUnbrokenSwingOnRates(m15, copied, 10, 4, 80, m_secBuy, m_secSell);
     }

   //--- Update M5 Bar Context
   void                  UpdateM5Context(const datetime curM5)
     {
      if(curM5 <= 0 || curM5 == m_lastM5BarTime)
         return;
      m_lastM5BarTime      = curM5;
      m_triggeredThisM5Bar = false;
      m_m5BarCounter++;

      MqlRates m5[];
      ArraySetAsSeries(m5, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, 0, 26, m5);
      if(copied < 22)
         return;

      m_curM5Open   = m5[0].open;
      m_prevM5Body  = m5[1].close - m5[1].open;
      m_prevM5Range = MathMax(0.10, m5[1].high - m5[1].low);
      m_prevM5Vol   = (double)m5[1].tick_volume;

      double vSum = 0.0;
      double rSum = 0.0;
      for(int i = 1; i <= 20; i++)
        {
         vSum += (double)m5[i].tick_volume;
         rSum += (m5[i].high - m5[i].low);
        }
      m_sma20Vol   = MathMax(1.0, vSum / 20.0);
      m_vaWidthUSD = MathMax(0.50, (rSum / 20.0) * 3.2);
     }

   ENUM_LIQUIDITY_TYPE   MapTierToPoolType(const int tier, const ENUM_SIGNAL_DIRECTION dir) const
     {
      if(dir == SIGNAL_LONG)
        {
         if(tier <= 1) return LIQ_PDL;
         if(tier <= 3) return LIQ_ASIAN_LOW;
         if(tier <= 5) return LIQ_EQUAL_LOWS;
         return LIQ_M15_SWING_LOW;
        }
      else
        {
         if(tier <= 1) return LIQ_PDH;
         if(tier <= 3) return LIQ_ASIAN_HIGH;
         if(tier <= 5) return LIQ_EQUAL_HIGHS;
         return LIQ_M15_SWING_HIGH;
        }
     }

   double                MinDistFromPat1(const double lvl, const ENUM_SIGNAL_DIRECTION dir) const
     {
      double minDist = 1e9;
      for(int k = 0; k < PAT1_TIERS; k++)
        {
         double ref = (dir == SIGNAL_LONG ? m_p1Buy[k] : m_p1Sell[k]);
         if(ref > 0.0)
           {
            double d = MathAbs(lvl - ref);
            if(d < minDist)
               minDist = d;
           }
        }
      return minDist;
     }

   double                MinDistFromPat30(const double lvl, const ENUM_SIGNAL_DIRECTION dir) const
     {
      double minDist = 1e9;
      for(int k = 0; k < PAT30_TIERS; k++)
        {
         double ref = (dir == SIGNAL_LONG ? m_p30Buy[k] : m_p30Sell[k]);
         if(ref > 0.0)
           {
            double d = MathAbs(lvl - ref);
            if(d < minDist)
               minDist = d;
           }
        }
      return minDist;
     }

   double                MinDistFromPat60(const double lvl, const ENUM_SIGNAL_DIRECTION dir) const
     {
      double minDist = 1e9;
      for(int k = 0; k < PAT60_TIERS; k++)
        {
         double ref = (dir == SIGNAL_LONG ? m_p60Buy[k] : m_p60Sell[k]);
         if(ref > 0.0)
           {
            double d = MathAbs(lvl - ref);
            if(d < minDist)
               minDist = d;
           }
        }
      return minDist;
     }

   //--- Co-Existence Guard: Up to 4 Same-Direction Positions (>= 10m apart, >= $0.40 separated, unprot < 2)
   bool                  CanOpenSameDirPosition(const ENUM_SIGNAL_DIRECTION candDir,
                                                const double candidateEntryPx,
                                                int &outProtectedCount,
                                                int &outUnprotectedCount) const
     {
      outProtectedCount   = 0;
      outUnprotectedCount = 0;
      if(m_hasPendingOrder)
         return false;

      int      openCount = 0;
      datetime now       = TimeCurrent();

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         openCount++;
         if(openCount >= 5)
            return false;

         ENUM_SIGNAL_DIRECTION posDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                        ? SIGNAL_LONG : SIGNAL_SHORT;
         if(posDir != candDir)
            return false;

         datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
         if((now - posTime) < 480)
            return false;

         double posOpenPx = PositionGetDouble(POSITION_PRICE_OPEN);
         if(MathAbs(candidateEntryPx - posOpenPx) < 0.35)
            return false;

         double posSL = PositionGetDouble(POSITION_SL);
         bool isProtected = (posDir == SIGNAL_LONG)
                            ? (posSL > posOpenPx + 0.01)
                            : (posSL > 0.0 && posSL < posOpenPx - 0.01);
         if(isProtected)
            outProtectedCount++;
         else
            outUnprotectedCount++;
        }

      if(outUnprotectedCount >= 2)
         return false;

      return true;
     }

   //--- Evaluate Pattern & Regime Eligibility for Candidate Signal
   bool                  IsCandidateEligible(const int pat,
                                             const ENUM_SIGNAL_DIRECTION candDir,
                                             const int tier,
                                             const int cf,
                                             const double lvlPx,
                                             const double tbOrTsPx,
                                             const double bidPx,
                                             const double execPx,
                                             const int hr,
                                             const double c15,
                                             const double c60,
                                             double &outTrend80,
                                             double &outMom8,
                                             double &outTrend200) const
     {
      int    protTmp = 0, unprotTmp = 0;
      if(!CanOpenSameDirPosition(candDir, execPx, protTmp, unprotTmp))
         return false;

      // 1. Maximum M1 intrabar overshoot guard (matches v4.50 & Python trigger mechanics)
      double maxOvershoot = MathMin(m_atrM15, lvlPx * 0.00045);
      if(candDir == SIGNAL_LONG  && (bidPx - tbOrTsPx) > maxOvershoot) return false;
      if(candDir == SIGNAL_SHORT && (tbOrTsPx - bidPx) > maxOvershoot) return false;

      // 2. Base Hour Filter (skip 0, 1, 2, 4, 6, 14, 18, 21, 23)
      if(hr == 0 || hr == 1 || hr == 2 || hr == 4 || hr == 6 || hr == 14 || hr == 18 || hr == 21 || hr == 23)
         return false;

      double sig     = (candDir == SIGNAL_LONG ? 1.0 : -1.0);
      double vel60m  = (c60 > 0.0 && m_atrH1 > 0.0)  ? (((tbOrTsPx - c60) * sig) / m_atrH1)  : 0.0;
      double vel15m  = (c15 > 0.0 && m_atrM15 > 0.0) ? (((tbOrTsPx - c15) * sig) / m_atrM15) : 0.0;

      if(vel60m > 2.10 || (vel15m > 2.38 && vel60m > 1.48))
         return false;

      double atrH1Pct   = m_atrH1 / tbOrTsPx;
      double atr120Pct  = (m_atr120H1 > 0.0 ? m_atr120H1 / tbOrTsPx : atrH1Pct);
      double bull200h   = (m_sma200H1 > 0.0 ? (tbOrTsPx - m_sma200H1) / m_atrH1 : 0.0);
      double bull480h   = (m_sma480H1 > 0.0 ? (tbOrTsPx - m_sma480H1) / m_atrH1 : 0.0);
      double trend200h  = bull200h * sig;
      bool   isBear200h = (bull200h <= -0.50);
      bool   low5dVol   = (atr120Pct <= 0.0023 && atrH1Pct <= 0.0024);

      double trend34    = (m_sma34H1 > 0.0 ? ((tbOrTsPx - m_sma34H1) * sig) / m_atrH1 : 0.0);
      double trend80    = (m_sma80H1 > 0.0 ? ((tbOrTsPx - m_sma80H1) * sig) / m_atrH1 : 0.0);
      double mom8       = (m_closeH1Prev8 > 0.0 ? ((tbOrTsPx - m_closeH1Prev8) * sig) / m_atrH1 : 0.0);
      outTrend80        = trend80;
      outMom8           = mom8;
      outTrend200       = trend200h;

      if(trend34 > 3.80)
         return false;

      if((hr == 9 || hr == 11) && (trend80 < 0.25 || mom8 < 0.15 || vel60m > 1.40))
         return false;

      // 3. Pattern-Specific Structural & Orthogonal Regime Gates (v4.60)
      if(pat == 1)
        {
         if(candDir == SIGNAL_LONG)
           {
            if(tier == 5 && cf == 1 && (trend80 < -0.15 || mom8 < -0.25))
               return false;
            if(tier == 3 && trend80 < 0.0)
               return false;
            return true;
           }
         else
           {
            if(tier > 4)
               return false;
            return (isBear200h ||
                    (cf >= 3 && bull480h > 0.0 && atrH1Pct <= 0.0026) ||
                    (cf >= 2 && trend200h > 0.25 && trend80 > 0.20 && mom8 > 0.10 && vel60m < 1.45 && trend34 > 0.20 && trend34 < 2.80));
           }
        }
      if(pat == 2)
         return false;

      if(pat == 3)
        {
         if(candDir == SIGNAL_LONG)
            return (tier <= 1 && cf >= 1 && trend34 > 0.20 && trend34 < 2.80 && atrH1Pct <= 0.0032 &&
                    (cf >= 2 || (trend200h > 0.20 && trend80 > 0.15 && mom8 > 0.10 && vel60m < 1.50)));
         else
            return (cf >= 2 && trend200h > 0.25 && trend80 > 0.20 && mom8 > 0.10 && vel60m < 1.45 && trend34 > 0.20 && trend34 < 2.80);
        }

      if(pat == 4)
         return (tier == 0 && trend80 > 0.10 && vel60m > 0.05 && (candDir == SIGNAL_LONG || bull200h <= -0.30));

      if(pat == 5)
        {
         if(candDir != SIGNAL_LONG || cf < 2 || trend80 <= 0.25 || mom8 <= 0.15 || vel60m >= 1.40)
            return false;
         if(tier == 0 && atrH1Pct <= 0.0032)
            return true;
         if(tier >= 1 && trend200h > 0.25 && (atrH1Pct <= 0.0024 || cf >= 3 || low5dVol))
            return true;
         return false;
        }

      if(pat == 7)
         return false;

      if(pat == 8)
         return false;

      if(pat == 9)
         return (candDir == SIGNAL_SHORT && isBear200h && trend80 > 0.20 && mom8 > 0.10);

      if(pat == 10)
         return false;

      if(pat == 11)
         return (candDir == SIGNAL_LONG && trend34 > 0.20 && vel60m < 1.50);

      if(pat == 30)
         return (candDir == SIGNAL_LONG && cf >= 1 && trend34 > 0.20 && trend34 < 2.80 && trend80 > 0.15);

      if(pat == 45)
         return (cf >= 1 && trend34 > 0.20 && trend34 < 2.80 && trend80 > 0.15 && atrH1Pct <= 0.0032 && (candDir == SIGNAL_LONG || isBear200h));

      if(pat == 60)
        {
         if(candDir != SIGNAL_LONG || tier > 3 || cf < 2 || trend80 <= 0.20 || mom8 <= 0.10 || vel60m >= 1.50)
            return false;
         if(tier <= 1 && atrH1Pct <= 0.0032)
            return true;
         if(trend200h > 0.25 && (atrH1Pct <= 0.0025 || low5dVol))
            return true;
         return false;
        }

      if(pat == 61)
         return (candDir == SIGNAL_LONG && cf >= 2 && trend200h > 0.25 && trend34 > 0.25 && trend34 < 2.50 && atrH1Pct <= 0.0028);

      if(pat == 81)
         return (((cf >= 5 && (candDir == SIGNAL_LONG || isBear200h)) || (candDir == SIGNAL_LONG && tier == 5)) &&
                 trend200h > 0.25 && trend80 > 0.20 && mom8 > 0.10 && vel60m < 1.45 && trend34 > 0.20 && trend34 < 2.80);

      if(pat == 82)
         return (candDir == SIGNAL_LONG && (tier >= 1 && tier <= 3) &&
                 trend200h > 0.25 && trend80 > 0.20 && mom8 > 0.10 && vel60m < 1.45 && trend34 > 0.20 && trend34 < 2.80);

      if(pat == 90)
         return (candDir == SIGNAL_LONG && vel60m > 0.10 && vel60m <= 1.60 && trend34 > 0.20 && trend34 <= 2.90 && trend80 > 0.20 && mom8 > 0.10 &&
                 (tier == 1 || (cf == 3 && trend200h > 0.25 && vel60m < 1.40)));

      if(pat == 91)
         return (candDir == SIGNAL_LONG && vel60m > 0.10 && vel60m <= 1.30 && trend34 > 0.20 && trend34 <= 2.90 && trend80 > 0.20 && mom8 > 0.10 &&
                 (tier == 3 || cf == 3) && trend200h > 0.35);

      if(pat == 92)
         return (candDir == SIGNAL_LONG && vel60m > 0.10 && vel60m < 1.35 && trend34 > 0.20 && trend34 <= 2.90 && trend80 > 0.20 && mom8 > 0.10 &&
                 cf >= 2 && tier <= 1 && trend200h > 0.30);

      if(pat == 93)
         return (candDir == SIGNAL_LONG && vel60m > 0.10 && vel60m <= 1.60 && trend34 > 0.20 && trend34 <= 2.90 && trend80 > 0.20 && mom8 > 0.10 &&
                 cf == 4 && trend200h > 0.25);

      if(pat == 94)
         return (candDir == SIGNAL_LONG && vel60m > 0.10 && vel60m < 1.30 && trend34 > 0.20 && trend34 <= 2.85 && trend80 > 0.20 && mom8 > 0.10 &&
                 trend200h > 0.30 && ((tier == 1 && cf >= 2) || cf == 5 || (cf == 3 && tier <= 2)));

      return false;
     }

public:
                         CSweepSignalEngine()
     {
      m_symbol                = _Symbol;
      m_brokerGMTOffset       = 2;
      m_magic                 = QUANT_DEFAULT_MAGIC;
      m_sessionLevels         = NULL;
      m_volumeProfile         = NULL;
      m_logger                = NULL;
      m_minSweepAtrRatio      = 0.15;
      m_maxSweepAtrRatio      = 1.50;
      m_minAbsorptionVolRatio = 1.15;
      m_maxReclaimBarsM5      = 3;
      m_limitExpiryBarsM5     = 3;
      m_state                 = STATE_IDLE;
      m_hasPendingOrder       = false;
      m_nextSetupSequenceId   = 0;

      m_lastH1BarTime         = 0;
      m_lastM30BarTime        = 0;
      m_lastM45Bucket         = -1;
      m_lastH2BarTime         = 0;
      m_lastH4BarTime         = 0;
      m_lastD1BarTime         = 0;
      m_lastM15BarTime        = 0;
      m_lastM5BarTime         = 0;
      m_lastM1BarTime         = 0;
      m_triggeredThisM5Bar    = false;
      m_triggeredThisM1Bar    = false;
      m_m5BarCounter          = 0;

      ArrayInitialize(m_p1Buy, 0.0);      ArrayInitialize(m_p1Sell, 0.0);
      ArrayInitialize(m_p1UsedBuy, 0.0);  ArrayInitialize(m_p1UsedSell, 0.0);
      ArrayInitialize(m_p2Buy, 0.0);      ArrayInitialize(m_p2Sell, 0.0);
      ArrayInitialize(m_p2UsedBuy, 0.0);  ArrayInitialize(m_p2UsedSell, 0.0);
      ArrayInitialize(m_p3Buy, 0.0);      ArrayInitialize(m_p3Sell, 0.0);
      ArrayInitialize(m_p3UsedBuy, 0.0);  ArrayInitialize(m_p3UsedSell, 0.0);
      ArrayInitialize(m_p4Buy, 0.0);      ArrayInitialize(m_p4Sell, 0.0);
      ArrayInitialize(m_p4UsedBuy, 0.0);  ArrayInitialize(m_p4UsedSell, 0.0);
      ArrayInitialize(m_p5Buy, 0.0);      ArrayInitialize(m_p5Sell, 0.0);
      ArrayInitialize(m_p5UsedBuy, 0.0);  ArrayInitialize(m_p5UsedSell, 0.0);
      ArrayInitialize(m_p7Buy, 0.0);      ArrayInitialize(m_p7Sell, 0.0);
      ArrayInitialize(m_p7UsedBuy, 0.0);  ArrayInitialize(m_p7UsedSell, 0.0);
      ArrayInitialize(m_p8Buy, 0.0);      ArrayInitialize(m_p8Sell, 0.0);
      ArrayInitialize(m_p8UsedBuy, 0.0);  ArrayInitialize(m_p8UsedSell, 0.0);
      ArrayInitialize(m_p9Buy, 0.0);      ArrayInitialize(m_p9Sell, 0.0);
      ArrayInitialize(m_p9UsedBuy, 0.0);  ArrayInitialize(m_p9UsedSell, 0.0);
      ArrayInitialize(m_p10Buy, 0.0);     ArrayInitialize(m_p10Sell, 0.0);
      ArrayInitialize(m_p10UsedBuy, 0.0); ArrayInitialize(m_p10UsedSell, 0.0);
      ArrayInitialize(m_p30Buy, 0.0);     ArrayInitialize(m_p30Sell, 0.0);
      ArrayInitialize(m_p30UsedBuy, 0.0); ArrayInitialize(m_p30UsedSell, 0.0);
      ArrayInitialize(m_p45Buy, 0.0);     ArrayInitialize(m_p45Sell, 0.0);
      ArrayInitialize(m_p45UsedBuy, 0.0); ArrayInitialize(m_p45UsedSell, 0.0);
      ArrayInitialize(m_p60Buy, 0.0);     ArrayInitialize(m_p60Sell, 0.0);
      ArrayInitialize(m_p60UsedBuy, 0.0); ArrayInitialize(m_p60UsedSell, 0.0);
      ArrayInitialize(m_p61Buy, 0.0);     ArrayInitialize(m_p61Sell, 0.0);
      ArrayInitialize(m_p61UsedBuy, 0.0); ArrayInitialize(m_p61UsedSell, 0.0);
      ArrayInitialize(m_p81Buy, 0.0);     ArrayInitialize(m_p81Sell, 0.0);
      ArrayInitialize(m_p81UsedBuy, 0.0); ArrayInitialize(m_p81UsedSell, 0.0);
      ArrayInitialize(m_p82Buy, 0.0);     ArrayInitialize(m_p82Sell, 0.0);
      ArrayInitialize(m_p82UsedBuy, 0.0); ArrayInitialize(m_p82UsedSell, 0.0);
      ArrayInitialize(m_p90Buy, 0.0);     ArrayInitialize(m_p90UsedBuy, 0.0);
      ArrayInitialize(m_p91Buy, 0.0);     ArrayInitialize(m_p91UsedBuy, 0.0);
      ArrayInitialize(m_p92Buy, 0.0);     ArrayInitialize(m_p92UsedBuy, 0.0);
      ArrayInitialize(m_p93Buy, 0.0);     ArrayInitialize(m_p93UsedBuy, 0.0);
      ArrayInitialize(m_p94Buy, 0.0);     ArrayInitialize(m_p94UsedBuy, 0.0);

      m_secBuy                = 0.0;
      m_secSell               = 0.0;
      m_secUsedBuy            = 0.0;
      m_secUsedSell           = 0.0;
      m_atrH1                 = 5.0;
      m_atr120H1              = 5.0;
      m_atrM15                = 2.0;
      m_sma34H1               = 0.0;
      m_sma80H1               = 0.0;
      m_sma200H1              = 0.0;
      m_sma480H1              = 0.0;
      m_closeH1Prev8          = 0.0;
      m_curM5Open             = 0.0;
      m_curM1Open             = 0.0;
      m_prevM5Body            = 0.0;
      m_prevM5Range           = 1.0;
      m_prevM5Vol             = 100.0;
      m_sma20Vol              = 100.0;
      m_vaWidthUSD            = 4.0;
      m_latestSetup.Reset();
     }

                        ~CSweepSignalEngine() {}

   bool                  Init(const string symbol,
                              const int brokerGMTOffsetHours,
                              CSessionLevels *sessionLevels,
                              CVolumeProfile *volumeProfile,
                              CQuantLogger *logger,
                              const double minSweepAtrRatio      = 0.15,
                              const double maxSweepAtrRatio      = 1.50,
                              const double minAbsorptionVolRatio = 1.15,
                              const int maxReclaimBarsM5         = 3,
                              const int limitExpiryBarsM5        = 3,
                              const ulong magic                  = QUANT_DEFAULT_MAGIC)
     {
      m_symbol                = symbol;
      m_brokerGMTOffset       = brokerGMTOffsetHours;
      m_magic                 = magic;
      m_sessionLevels         = sessionLevels;
      m_volumeProfile         = volumeProfile;
      m_logger                = logger;
      m_minSweepAtrRatio      = minSweepAtrRatio;
      m_maxSweepAtrRatio      = maxSweepAtrRatio;
      m_minAbsorptionVolRatio = minAbsorptionVolRatio;
      m_maxReclaimBarsM5      = maxReclaimBarsM5;
      m_limitExpiryBarsM5     = limitExpiryBarsM5;
      m_state                 = STATE_IDLE;
      return (m_sessionLevels != NULL && m_volumeProfile != NULL);
     }

   void                  NotifyPendingOrderState(const bool hasPendingOrOpenTrade)
     {
      m_hasPendingOrder = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t > 0 && OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
           {
            m_hasPendingOrder = true;
            break;
           }
        }
      if(hasPendingOrOpenTrade)
         m_state = STATE_PENDING_LIMIT;
      else if(m_state == STATE_PENDING_LIMIT)
         m_state = STATE_IDLE;
     }

   void                  NotifyTradeOutcome(const ENUM_SIGNAL_DIRECTION closedDir,
                                            const double realizedR,
                                            const datetime closeTimeUTC)
     {
     }

   //+------------------------------------------------------------------+
   //| EvaluateOnM5BarClose                                             |
   //| Evaluates all 14 structural swing pattern families on M1 bars    |
   //| while keeping broken levels marked in real time.                 |
   //+------------------------------------------------------------------+
   bool                  EvaluateOnM5BarClose(const bool hasActiveExposure,
                                              SSweepCandidateSetup &outCandidateSetup)
     {
      outCandidateSetup.Reset();

      datetime currentM5BarTime = iTime(m_symbol, PERIOD_M5, 0);
      if(currentM5BarTime <= 0)
         return false;

      // 1. Refresh Multi-Timeframe Unbroken Swing Ladders
      UpdateH1Levels();
      UpdateM30Levels();
      UpdateM45Levels();
      UpdateH2Levels();
      UpdateH4Levels();
      UpdateD1Levels();
      datetime prevM15 = m_lastM15BarTime;
      UpdateM15Levels();
      if(m_lastM15BarTime != prevM15 && m_sessionLevels != NULL)
         m_sessionLevels.Update();
      UpdateM5Context(currentM5BarTime);

      datetime currentM1BarTime = iTime(m_symbol, PERIOD_M1, 0);
      if(currentM1BarTime > 0 && currentM1BarTime != m_lastM1BarTime)
        {
         m_lastM1BarTime      = currentM1BarTime;
         m_triggeredThisM1Bar = false;
         m_curM1Open          = iOpen(m_symbol, PERIOD_M1, 0);
        }

      if(m_hasPendingOrder || m_triggeredThisM1Bar || m_sma34H1 <= 0.0)
         return false;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0 || m_curM5Open <= 0.0)
         return false;
      if(m_curM1Open <= 0.0)
         m_curM1Open = m_curM5Open;

      MqlDateTime dtSrv;
      TimeToStruct(currentM5BarTime, dtSrv);
      int hr = dtSrv.hour;

      ENUM_SIGNAL_DIRECTION sig      = SIGNAL_NONE;
      double                levelPx  = 0.0;
      double                trigPx   = 0.0;
      int                   pat_used = 0;
      int                   t_used   = -1;
      int                   conf     = 0;
      double                winT80   = 0.0;
      double                winMom8  = 0.0;
      double                winT200  = 0.0;

      // 3. Evaluate All Prime Pattern Families on Every M1 Bar (marking crossed levels even in skip hours)
      if(!m_triggeredThisM1Bar)
        {
         double c60     = iClose(m_symbol, PERIOD_M1, 60);
         if(c60 <= 0.0) c60 = iClose(m_symbol, PERIOD_M5, 12);
         double c15     = iClose(m_symbol, PERIOD_M1, 15);
         if(c15 <= 0.0) c15 = iClose(m_symbol, PERIOD_M5, 3);
         double off     = 0.00045;
         double t80Tmp  = 0.0, mom8Tmp = 0.0, t200Tmp = 0.0;

         bool s1Fired = false;
         bool s2Fired = false;
         bool s3Fired = false;

         // --- PAT 1: Core H1 6-Tier Ladder (28/13..12/6) ---
         for(int m = 0; m < PAT1_TIERS; m++)
           {
            double bl = m_p1Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p1UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT1_TIERS; mm++)
                    {
                     if(MathAbs(m_p1Buy[mm] - bl) <= 0.25)
                       {
                        m_p1UsedBuy[mm] = m_p1Buy[mm];
                        cf++;
                       }
                    }
                  s1Fired = true;
                  if(sig == SIGNAL_NONE &&
                     IsCandidateEligible(1, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 1; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p1Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p1UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT1_TIERS; mm++)
                    {
                     if(MathAbs(m_p1Sell[mm] - sl) <= 0.25)
                       {
                        m_p1UsedSell[mm] = m_p1Sell[mm];
                        cf++;
                       }
                    }
                  s1Fired = true;
                  if(sig == SIGNAL_NONE &&
                     IsCandidateEligible(1, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 1; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 2: Extended H1 Swings (34/14, 30/13, 24/11, 20/10) ---
         for(int m = 0; m < PAT2_TIERS; m++)
           {
            double bl = m_p2Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p2UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT2_TIERS; mm++)
                    {
                     if(MathAbs(m_p2Buy[mm] - bl) <= 0.25)
                       {
                        m_p2UsedBuy[mm] = m_p2Buy[mm];
                        cf++;
                       }
                    }
                  if(!s1Fired && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50)
                    {
                     s2Fired = true;
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(2, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 2; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                    }
                  break;
                 }
              }
            double sl = m_p2Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p2UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT2_TIERS; mm++)
                    {
                     if(MathAbs(m_p2Sell[mm] - sl) <= 0.25)
                       {
                        m_p2UsedSell[mm] = m_p2Sell[mm];
                        cf++;
                       }
                    }
                  if(!s1Fired && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50)
                    {
                     s2Fired = true;
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(2, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 2; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                    }
                  break;
                 }
              }
           }

         // --- PAT 3: M30 Core Swings (28/13, 24/11, 20/9) ---
         for(int m = 0; m < PAT3_TIERS; m++)
           {
            double bl = m_p3Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p3UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT3_TIERS; mm++)
                    {
                     if(MathAbs(m_p3Buy[mm] - bl) <= 0.25)
                       {
                        m_p3UsedBuy[mm] = m_p3Buy[mm];
                        cf++;
                       }
                    }
                  if(!s1Fired && !s2Fired && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50)
                    {
                     s3Fired = true;
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(3, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 3; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                    }
                  break;
                 }
              }
            double sl = m_p3Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p3UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT3_TIERS; mm++)
                    {
                     if(MathAbs(m_p3Sell[mm] - sl) <= 0.25)
                       {
                        m_p3UsedSell[mm] = m_p3Sell[mm];
                        cf++;
                       }
                    }
                  if(!s1Fired && !s2Fired && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50)
                    {
                     s3Fired = true;
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(3, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 3; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                    }
                  break;
                 }
              }
           }

         // --- PAT 4: Daily PDH / PDL Breakout (m = 0) ---
         double bl4 = m_p4Buy[0];
         if(bl4 > 0.0 && MathAbs(bl4 - m_p4UsedBuy[0]) > 0.20)
           {
            double tb = bl4 * (1.0 - off);
            if(m_curM1Open < tb && bid >= tb)
              {
               m_p4UsedBuy[0] = bl4;
               if(!s1Fired && !s2Fired && !s3Fired && sig == SIGNAL_NONE && MinDistFromPat1(bl4, SIGNAL_LONG) > 0.50 &&
                  IsCandidateEligible(4, SIGNAL_LONG, 0, 1, bl4, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                 {
                  sig = SIGNAL_LONG; levelPx = bl4; trigPx = ask; pat_used = 4; t_used = 0; conf = 1; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                 }
              }
           }
         double sl4 = m_p4Sell[0];
         if(sl4 > 0.0 && MathAbs(sl4 - m_p4UsedSell[0]) > 0.20)
           {
            double ts_px = sl4 * (1.0 + off);
            if(m_curM1Open > ts_px && bid <= ts_px)
              {
               m_p4UsedSell[0] = sl4;
               if(!s1Fired && !s2Fired && !s3Fired && sig == SIGNAL_NONE && MinDistFromPat1(sl4, SIGNAL_SHORT) > 0.50 &&
                  IsCandidateEligible(4, SIGNAL_SHORT, 0, 1, sl4, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                 {
                  sig = SIGNAL_SHORT; levelPx = sl4; trigPx = bid; pat_used = 4; t_used = 0; conf = 1; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                 }
              }
           }

         // --- PAT 5: Fast H1 Continuation Swings (10/5, 9/4, 8/4, 7/3) ---
         for(int m = 0; m < PAT5_TIERS; m++)
           {
            double bl = m_p5Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p5UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT5_TIERS; mm++)
                    {
                     if(MathAbs(m_p5Buy[mm] - bl) <= 0.25)
                       {
                        m_p5UsedBuy[mm] = m_p5Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(5, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 5; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p5Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p5UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT5_TIERS; mm++)
                    {
                     if(MathAbs(m_p5Sell[mm] - sl) <= 0.25)
                       {
                        m_p5UsedSell[mm] = m_p5Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(5, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 5; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 7: M30 Low-Vol Precision Swings (34/14, 30/13, 16/8) ---
         for(int m = 0; m < PAT7_TIERS; m++)
           {
            double bl = m_p7Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p7UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT7_TIERS; mm++)
                    {
                     if(MathAbs(m_p7Buy[mm] - bl) <= 0.25)
                       {
                        m_p7UsedBuy[mm] = m_p7Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(7, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 7; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p7Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p7UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT7_TIERS; mm++)
                    {
                     if(MathAbs(m_p7Sell[mm] - sl) <= 0.25)
                       {
                        m_p7UsedSell[mm] = m_p7Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(7, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 7; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 8: H2 2-Hour Structural Swings (20/9..8/4) ---
         for(int m = 0; m < PAT8_TIERS; m++)
           {
            double bl = m_p8Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p8UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT8_TIERS; mm++)
                    {
                     if(MathAbs(m_p8Buy[mm] - bl) <= 0.25)
                       {
                        m_p8UsedBuy[mm] = m_p8Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(8, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 8; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p8Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p8UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT8_TIERS; mm++)
                    {
                     if(MathAbs(m_p8Sell[mm] - sl) <= 0.25)
                       {
                        m_p8UsedSell[mm] = m_p8Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(8, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 8; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 9: H4 4-Hour Structural Swings (14/6..6/3) ---
         for(int m = 0; m < PAT9_TIERS; m++)
           {
            double bl = m_p9Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p9UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT9_TIERS; mm++)
                    {
                     if(MathAbs(m_p9Buy[mm] - bl) <= 0.25)
                       {
                        m_p9UsedBuy[mm] = m_p9Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(9, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 9; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p9Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p9UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT9_TIERS; mm++)
                    {
                     if(MathAbs(m_p9Sell[mm] - sl) <= 0.25)
                       {
                        m_p9UsedSell[mm] = m_p9Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(9, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 9; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 10: Intermediate H1 Swings (16/8, 14/7, 13/6, 11/5) ---
         for(int m = 0; m < PAT10_TIERS; m++)
           {
            double bl = m_p10Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p10UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT10_TIERS; mm++)
                    {
                     if(MathAbs(m_p10Buy[mm] - bl) <= 0.25)
                       {
                        m_p10UsedBuy[mm] = m_p10Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(10, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 10; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p10Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p10UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT10_TIERS; mm++)
                    {
                     if(MathAbs(m_p10Sell[mm] - sl) <= 0.25)
                       {
                        m_p10UsedSell[mm] = m_p10Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(10, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 10; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 11: Multi-Day Rolling High/Low (2D, 3D, 5D: m = 1..3 in m_p4) ---
         for(int m = 1; m < PAT4_TIERS; m++)
           {
            double bl = m_p4Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p4UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  m_p4UsedBuy[m] = bl;
                  bool distinctFromPDH = (MathAbs(bl - m_p4Buy[0]) > 0.50);
                  if(sig == SIGNAL_NONE && distinctFromPDH && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(11, SIGNAL_LONG, m - 1, 1, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 11; t_used = m - 1; conf = 1; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p4Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p4UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  m_p4UsedSell[m] = sl;
                  bool distinctFromPDL = (MathAbs(sl - m_p4Sell[0]) > 0.50);
                  if(sig == SIGNAL_NONE && distinctFromPDL && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(11, SIGNAL_SHORT, m - 1, 1, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 11; t_used = m - 1; conf = 1; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 30: Full 6-Tier M30 Unbroken Swings (34/14..22/11) ---
         for(int m = 0; m < PAT30_TIERS; m++)
           {
            double bl = m_p30Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p30UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT30_TIERS; mm++)
                    {
                     if(MathAbs(m_p30Buy[mm] - bl) <= 0.25)
                       {
                        m_p30UsedBuy[mm] = m_p30Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(30, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 30; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p30Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p30UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT30_TIERS; mm++)
                    {
                     if(MathAbs(m_p30Sell[mm] - sl) <= 0.25)
                       {
                        m_p30UsedSell[mm] = m_p30Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(30, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 30; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 45: Full 6-Tier M45 Unbroken Swings (28/13..14/7) ---
         for(int m = 0; m < PAT45_TIERS; m++)
           {
            double bl = m_p45Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p45UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT45_TIERS; mm++)
                    {
                     if(MathAbs(m_p45Buy[mm] - bl) <= 0.25)
                       {
                        m_p45UsedBuy[mm] = m_p45Buy[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 && MinDistFromPat30(bl, SIGNAL_LONG) > 0.50 &&
                     IsCandidateEligible(45, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 45; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
            double sl = m_p45Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p45UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT45_TIERS; mm++)
                    {
                     if(MathAbs(m_p45Sell[mm] - sl) <= 0.25)
                       {
                        m_p45UsedSell[mm] = m_p45Sell[mm];
                        cf++;
                       }
                    }
                  if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 && MinDistFromPat30(sl, SIGNAL_SHORT) > 0.50 &&
                     IsCandidateEligible(45, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                    {
                     sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 45; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                    }
                  break;
                 }
              }
           }

         // --- PAT 60: Asymmetric H1 Same-Day Continuation Swings (28/5..16/3) ---
         for(int m = 0; m < PAT60_TIERS; m++)
           {
            double bl = m_p60Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p60UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT60_TIERS; mm++)
                    {
                     if(MathAbs(m_p60Buy[mm] - bl) <= 0.25)
                       {
                        m_p60UsedBuy[mm] = m_p60Buy[mm];
                        cf++;
                       }
                    }
                  if(MinDistFromPat1(bl, SIGNAL_LONG) > 0.50)
                    {
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(60, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 60; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                     break;
                    }
                 }
              }
            double sl = m_p60Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p60UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT60_TIERS; mm++)
                    {
                     if(MathAbs(m_p60Sell[mm] - sl) <= 0.25)
                       {
                        m_p60UsedSell[mm] = m_p60Sell[mm];
                        cf++;
                       }
                    }
                  if(MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50)
                    {
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(60, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 60; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                     break;
                    }
                 }
              }
           }

         // --- PAT 61: Asymmetric M30 Same-Day Continuation Swings (36/9..24/6) ---
         for(int m = 0; m < PAT61_TIERS; m++)
           {
            double bl = m_p61Buy[m];
            if(bl > 0.0 && MathAbs(bl - m_p61UsedBuy[m]) > 0.20)
              {
               double tb = bl * (1.0 - off);
               if(m_curM1Open < tb && bid >= tb)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT61_TIERS; mm++)
                    {
                     if(MathAbs(m_p61Buy[mm] - bl) <= 0.25)
                       {
                        m_p61UsedBuy[mm] = m_p61Buy[mm];
                        cf++;
                       }
                    }
                  if(MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 && MinDistFromPat60(bl, SIGNAL_LONG) > 0.50)
                    {
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(61, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 61; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                     break;
                    }
                 }
              }
            double sl = m_p61Sell[m];
            if(sl > 0.0 && MathAbs(sl - m_p61UsedSell[m]) > 0.20)
              {
               double ts_px = sl * (1.0 + off);
               if(m_curM1Open > ts_px && bid <= ts_px)
                 {
                  int cf = 0;
                  for(int mm = 0; mm < PAT61_TIERS; mm++)
                    {
                     if(MathAbs(m_p61Sell[mm] - sl) <= 0.25)
                       {
                        m_p61UsedSell[mm] = m_p61Sell[mm];
                        cf++;
                       }
                    }
                  if(MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 && MinDistFromPat60(sl, SIGNAL_SHORT) > 0.50)
                    {
                     if(sig == SIGNAL_NONE &&
                        IsCandidateEligible(61, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                       {
                        sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 61; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                       }
                     break;
                    }
                 }
              }
           }

          // --- PAT 81: M30 Fast 6-Tier Ladder (18/8..8/3) ---
          for(int m = 0; m < PAT81_TIERS; m++)
            {
             double bl = m_p81Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p81UsedBuy[m]) > 0.20)
               {
                double tb = bl * (1.0 - off);
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT81_TIERS; mm++)
                      if(MathAbs(m_p81Buy[mm] - bl) <= 0.25) { m_p81UsedBuy[mm] = m_p81Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                      IsCandidateEligible(81, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 81; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
             double sl = m_p81Sell[m];
             if(sl > 0.0 && MathAbs(sl - m_p81UsedSell[m]) > 0.20)
               {
                double ts_px = sl * (1.0 + off);
                if(m_curM1Open > ts_px && bid <= ts_px)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT81_TIERS; mm++)
                      if(MathAbs(m_p81Sell[mm] - sl) <= 0.25) { m_p81UsedSell[mm] = m_p81Sell[mm]; cf++; }
                   if(sig == SIGNAL_NONE && MinDistFromPat1(sl, SIGNAL_SHORT) > 0.50 &&
                      IsCandidateEligible(81, SIGNAL_SHORT, m, cf, sl, ts_px, bid, bid, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_SHORT; levelPx = sl; trigPx = bid; pat_used = 81; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          // --- PAT 82: H2 Full 6-Tier Ladder (24/11..10/5) ---
          for(int m = 0; m < PAT82_TIERS; m++)
            {
             double bl = m_p82Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p82UsedBuy[m]) > 0.20)
               {
                double tb = bl * (1.0 - off);
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT82_TIERS; mm++)
                      if(MathAbs(m_p82Buy[mm] - bl) <= 0.25) { m_p82UsedBuy[mm] = m_p82Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE && MinDistFromPat1(bl, SIGNAL_LONG) > 0.50 &&
                      IsCandidateEligible(82, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 82; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          // --- PAT 90, 91, 92, 93, 94: Orthogonal Short-Horizon Flag, Coil, Hook Reclaim & Pause Breakouts ---
          for(int m = 0; m < PAT92_TIERS; m++)
            {
             double bl = m_p92Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p92UsedBuy[m]) > 0.20)
               {
                double tb = bl * 1.00040;
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT92_TIERS; mm++)
                      if(m_p92Buy[mm] > 0.0 && MathAbs(m_p92Buy[mm] - bl) <= 0.25) { m_p92UsedBuy[mm] = m_p92Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE &&
                      IsCandidateEligible(92, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 92; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          for(int m = 0; m < PAT93_TIERS; m++)
            {
             double bl = m_p93Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p93UsedBuy[m]) > 0.20)
               {
                double tb = bl * 1.00048;
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT93_TIERS; mm++)
                      if(m_p93Buy[mm] > 0.0 && MathAbs(m_p93Buy[mm] - bl) <= 0.25) { m_p93UsedBuy[mm] = m_p93Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE &&
                      IsCandidateEligible(93, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 93; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          for(int m = 0; m < PAT90_TIERS; m++)
            {
             double bl = m_p90Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p90UsedBuy[m]) > 0.20)
               {
                double tb = bl * 1.00045;
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT90_TIERS; mm++)
                      if(m_p90Buy[mm] > 0.0 && MathAbs(m_p90Buy[mm] - bl) <= 0.25) { m_p90UsedBuy[mm] = m_p90Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE &&
                      IsCandidateEligible(90, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 90; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          for(int m = 0; m < PAT91_TIERS; m++)
            {
             double bl = m_p91Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p91UsedBuy[m]) > 0.20)
               {
                double tb = bl * 1.00045;
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT91_TIERS; mm++)
                      if(m_p91Buy[mm] > 0.0 && MathAbs(m_p91Buy[mm] - bl) <= 0.25) { m_p91UsedBuy[mm] = m_p91Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE &&
                      IsCandidateEligible(91, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 91; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

          for(int m = 0; m < PAT94_TIERS; m++)
            {
             double bl = m_p94Buy[m];
             if(bl > 0.0 && MathAbs(bl - m_p94UsedBuy[m]) > 0.20)
               {
                double tb = bl * (m < 3 ? 1.00040 : 1.00042);
                if(m_curM1Open < tb && bid >= tb)
                  {
                   int cf = 0;
                   for(int mm = 0; mm < PAT94_TIERS; mm++)
                      if(m_p94Buy[mm] > 0.0 && MathAbs(m_p94Buy[mm] - bl) <= 0.25) { m_p94UsedBuy[mm] = m_p94Buy[mm]; cf++; }
                   if(sig == SIGNAL_NONE &&
                      IsCandidateEligible(94, SIGNAL_LONG, m, cf, bl, tb, bid, ask, hr, c15, c60, t80Tmp, mom8Tmp, t200Tmp))
                     {
                      sig = SIGNAL_LONG; levelPx = bl; trigPx = ask; pat_used = 94; t_used = m; conf = cf; winT80 = t80Tmp; winMom8 = mom8Tmp; winT200 = t200Tmp;
                     }
                   break;
                  }
               }
            }

         if(sig != SIGNAL_NONE)
            m_triggeredThisM1Bar = true;
        }

      // 4. Secondary Minor Fractal (Tier 7: M15 10/4 fade) in off-peak hours (for Pass-1 telemetry mode)
      bool isOffPeakHr = (hr == 1 || hr == 2 || hr == 4 || hr == 6 || hr == 14 || hr == 18 || hr == 21);
      if(sig == SIGNAL_NONE && !hasActiveExposure && isOffPeakHr && !m_triggeredThisM5Bar &&
         (m_m5BarCounter % 3) == 0)
        {
         double bl = m_secBuy;
         if(bl > 0.0 && MathAbs(bl - m_secUsedBuy) > 0.20)
           {
            if(m_curM5Open < bl && bid >= bl && (bid - bl) <= m_atrM15)
              {
               sig          = SIGNAL_SHORT;
               levelPx      = bl;
               trigPx       = bid;
               pat_used     = 99;
               t_used       = 7;
               conf         = 1;
               m_secUsedBuy = bl;
              }
           }
         if(sig == SIGNAL_NONE)
           {
            double sl = m_secSell;
            if(sl > 0.0 && MathAbs(sl - m_secUsedSell) > 0.20)
              {
               if(m_curM5Open > sl && ask <= sl && (sl - ask) <= m_atrM15)
                 {
                  sig           = SIGNAL_LONG;
                  levelPx       = sl;
                  trigPx        = ask;
                  pat_used      = 99;
                  t_used        = 7;
                  conf          = 1;
                  m_secUsedSell = sl;
                 }
              }
           }
        }

      if(sig == SIGNAL_NONE)
         return false;

      if(pat_used == 99)
         m_triggeredThisM5Bar = true;
      m_state = STATE_RECLAIM_CONFIRMED;

      bool   isPrime      = (pat_used != 99);
      double atrH1Pct     = m_atrH1 / trigPx;
      bool   isStrongWave = (isPrime && atrH1Pct > 0.0026 && winT200 > 1.50 && winMom8 > 0.30);

      double confRiskMult = 1.0;
      if(isPrime)
        {
         // v4.60 True Expectancy Tiering (Wave-2/3 Continuation vs Wave-1 Range Breakout)
         if(pat_used == 9 || pat_used == 61 || pat_used == 82 || pat_used == 92 || pat_used == 93 ||
            (pat_used == 30 && conf >= 2) ||
            (pat_used == 1 && (t_used == 1 || t_used == 2 || t_used == 4 || conf == 2 || conf == 5)))
            confRiskMult = 1.24;
         else if(pat_used == 45 || pat_used == 60 || pat_used == 90 || pat_used == 91 || pat_used == 94 || conf >= 4)
            confRiskMult = 1.13;
         else if(conf >= 2)
            confRiskMult = 1.03;
         else
            confRiskMult = 0.85;
        }

      double atr120Pct = (m_atr120H1 > 0.0 ? (m_atr120H1 / trigPx) : atrH1Pct);
      double slAdapt   = (pat_used == 1 && t_used == 0)
                         ? MathMin(0.00352, MathMax(0.00185, 1.30 * atr120Pct))
                         : MathMin(0.00350, MathMax(0.00150, 1.15 * atr120Pct));
      double slPct     = (isPrime ? slAdapt : 0.0022);
      double tpPct     = (isPrime ? 0.03000 : 0.0018);
      double slDist    = MathMax(1.25, trigPx * slPct);
      double tpDist    = MathMax(2.40, trigPx * tpPct);

      double entryPx  = NormalizeSymbolPrice(m_symbol, trigPx);
      double slPx     = NormalizeSymbolPrice(m_symbol, (sig == SIGNAL_LONG ? entryPx - slDist : entryPx + slDist));
      double tp1Px    = NormalizeSymbolPrice(m_symbol, (sig == SIGNAL_LONG ? entryPx + entryPx * 0.00190 : entryPx - entryPx * 0.00190));
      double tp2Px    = NormalizeSymbolPrice(m_symbol, (sig == SIGNAL_LONG ? entryPx + tpDist - 0.18 : entryPx - tpDist));

      double sigNum        = (sig == SIGNAL_LONG ? 1.0 : -1.0);
      double curMoveSigned = (trigPx - m_curM5Open) * sigNum;
      double rngBar        = MathMax(0.10, MathMax(MathAbs(trigPx - m_curM5Open), m_prevM5Range));
      double signedBodyUSD = 0.65 * curMoveSigned + 0.35 * (m_prevM5Body * sigNum);

      m_nextSetupSequenceId++;
      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);
      int mappedTier  = (isPrime ? MathMin(5, MathMax(0, t_used)) : 7);

      outCandidateSetup.setupId                = (ulong)utcNow * 100 + (m_nextSetupSequenceId % 100);
      outCandidateSetup.sweepBarTime           = currentM5BarTime;
      outCandidateSetup.reclaimBarTime         = currentM5BarTime;
      outCandidateSetup.signalTimeUTC          = utcNow;
      outCandidateSetup.direction              = sig;
      outCandidateSetup.sweptPoolType          = MapTierToPoolType(mappedTier, sig);
      outCandidateSetup.sweptLevelPrice        = levelPx;
      outCandidateSetup.sweepExtremePrice      = trigPx;
      outCandidateSetup.sweepDepthUSD          = MathAbs(levelPx - trigPx);
      outCandidateSetup.rejectionWickUSD       = signedBodyUSD;
      outCandidateSetup.reclaimCandleRangeUSD  = rngBar;
      outCandidateSetup.m1BarsOutsideLevel     = MathMax(1, 28 - mappedTier * 3);
      outCandidateSetup.sweepM5TickVolume      = m_prevM5Vol;
      outCandidateSetup.sma20M5TickVolume      = m_sma20Vol;
      outCandidateSetup.hasFVG                 = isPrime;
      outCandidateSetup.fvgProximalPrice       = entryPx;
      outCandidateSetup.fvgDistalPrice         = levelPx;
      outCandidateSetup.hasMSS                 = true;
      outCandidateSetup.mssBreakLevel          = levelPx;
      outCandidateSetup.entryLimitPrice        = entryPx;
      outCandidateSetup.stopLossPrice          = slPx;
      outCandidateSetup.slDistanceUSD          = MathAbs(entryPx - slPx);
      outCandidateSetup.tp1Price               = tp1Px;
      outCandidateSetup.tp2Price               = tp2Px;
      outCandidateSetup.vpocAtSignal           = m_sma34H1;
      outCandidateSetup.vahAtSignal            = entryPx + 0.5 * m_vaWidthUSD;
      outCandidateSetup.valAtSignal            = entryPx - 0.5 * m_vaWidthUSD;
      outCandidateSetup.opposingLiquidityPrice = tp2Px;
      outCandidateSetup.expiryM5Bars           = m_limitExpiryBarsM5;
      outCandidateSetup.structuralTier         = mappedTier;
      outCandidateSetup.confluenceCount        = MathMax(1, conf);
      outCandidateSetup.isPrimeSetup           = isPrime;
      outCandidateSetup.isStrongWave           = isStrongWave;
      outCandidateSetup.confRiskMultiplier     = confRiskMult;
      outCandidateSetup.sma34H1AtSignal        = m_sma34H1;
      outCandidateSetup.sma80H1AtSignal        = m_sma80H1;
      outCandidateSetup.closeH1Prev8AtSignal   = m_closeH1Prev8;
      outCandidateSetup.isValid                = true;

      m_latestSetup = outCandidateSetup;
      return true;
     }

   //--- Accessors
   ENUM_SWEEP_STATE     GetCurrentState() const { return m_state; }
   double               GetCachedAtrM15() const { return m_atrM15; }
   double               GetCachedAtrH1()  const { return m_atrH1;  }
  };

#endif // XAUUSD_QUANT_SWEEP_SIGNAL_ENGINE_MQH
