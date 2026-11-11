//+------------------------------------------------------------------+
//| AiRater.mqh - SevenWave AI quality rater (native MT5 ONNX)         |
//|                                                                    |
//| 17 scale-free features, identical order and definitions to         |
//| python_pipeline/sw_final.FEATS (computed from bars CLOSED at the   |
//| decision time).  Contract: input float32[1,17] -> label int64[1],  |
//| probabilities float32[1,2] (zipmap=False).  The model is a light   |
//| VETO: setups scoring below SW_AI_THRESHOLD (the 25th percentile of |
//| the training validation slice) are skipped.                        |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_AIRATER_MQH
#define SEVENWAVE_AIRATER_MQH

#include "Market.mqh"
#include "AiModelMeta.mqh"

#resource "\\Files\\models\\sevenwave_rater.onnx" as uchar SwOnnxModel[]

class CSwAiRater
  {
private:
   long   m_h;
public:
   float  feat[SW_AI_FEATURES];
   double lastP;
   bool   ok;

                     CSwAiRater(void) : m_h(INVALID_HANDLE), lastP(-1.0), ok(false) {}
                    ~CSwAiRater(void) { Release(); }

   bool              Init(void)
     {
      Release();
      m_h = OnnxCreateFromBuffer(SwOnnxModel, ONNX_DEFAULT);
      if(m_h == INVALID_HANDLE)
        {
         Print("SevenWave AI: OnnxCreateFromBuffer failed ", GetLastError());
         return false;
        }
      const long ishape[] = {1, SW_AI_FEATURES};
      const long lshape[] = {1};
      const long pshape[] = {1, 2};
      if(!OnnxSetInputShape(m_h, 0, ishape) || !OnnxSetOutputShape(m_h, 0, lshape) || !OnnxSetOutputShape(m_h, 1, pshape))
        {
         Print("SevenWave AI: shape setup failed ", GetLastError());
         Release();
         return false;
        }
      ok = true;
      return true;
     }

   void              Release(void)
     {
      if(m_h != INVALID_HANDLE)
         OnnxRelease(m_h);
      m_h = INVALID_HANDLE;
      ok = false;
     }

   //--- build the feature vector; px = expected fill (ask for buys, bid for sells), now = server time
   bool              Build(CSwMarket &mk, int stream, int dir, int age, double px, datetime now)
     {
      double d = (double)dir;
      int k1 = mk.h1.LastClosedAt(now);
      int k4 = mk.h4.LastClosedAt(now);
      int kd = mk.d1.LastClosedAt(now);
      if(k1 < 480 || k4 < 1 || kd < 1)
         return false;
      double a1 = MathMax(mk.h1.atr[k1], 1e-9);
      double a4 = MathMax(mk.h4.atr[k4], 1e-9);
      double ad = MathMax(mk.d1.atr[kd], 1e-9);
      //--- volatility regime: ATR / mean ATR of the last 480 closed H1 bars
      double sa = 0.0;
      for(int i = k1 - 479; i <= k1; i++) sa += mk.h1.atr[i];
      double volreg = mk.h1.atr[k1] / (sa / 480.0);
      //--- cost model identical to the Dukascopy training feed: $0.30 ($0.60 in the 21-22 UTC rollover hours)
      datetime utc = mk.clock.ToUtc(now);
      datetime utcMin = utc - (utc % 60);
      MqlDateTime u; TimeToStruct(utcMin, u);
      double cost = (u.hour == 21 || u.hour == 22) ? 0.60 : 0.30;
      double hr = (double)(utcMin % 86400) / 3600.0;
      //--- 24 H1-bar context
      double hi = -DBL_MAX, lo = DBL_MAX;
      for(int i = k1 - 23; i <= k1; i++) { hi = MathMax(hi, mk.h1.h[i]); lo = MathMin(lo, mk.h1.l[i]); }
      double c1 = mk.h1.c[k1];
      feat[0]  = (float)stream;
      feat[1]  = (float)dir;
      feat[2]  = 0.0f;                                   // v1.10 model: pool age not used (constant in training)
      feat[3]  = (float)(mk.h1.order[k1] * d);
      feat[4]  = (float)(mk.h4.order[k4] * d);
      feat[5]  = (float)(mk.d1.order[kd] * d);
      feat[6]  = (float)((mk.h1.E(k1, 0) - mk.h1.E(k1, 6)) / a1 * d);
      feat[7]  = (float)((mk.h4.E(k4, 0) - mk.h4.E(k4, 6)) / a4 * d);
      feat[8]  = (float)((mk.d1.E(kd, 0) - mk.d1.E(kd, 6)) / ad * d);
      feat[9]  = (float)((px - mk.h1.E(k1, 0)) / a1 * d);
      feat[10] = (float)((px - mk.h4.E(k4, 0)) / a4 * d);
      feat[11] = (float)volreg;
      feat[12] = (float)(cost / a1);
      feat[13] = (float)MathSin(2.0 * M_PI * hr / 24.0);
      feat[14] = (float)MathCos(2.0 * M_PI * hr / 24.0);
      feat[15] = (float)((c1 - mk.h1.c[k1 - 24]) / a1 * d);
      feat[16] = (float)(((c1 - lo) / MathMax(hi - lo, 1e-9) - 0.5) * d);
      return true;
     }

   //--- probability of a winning trade; -1 on failure (caller then trusts the rules)
   double            Score(void)
     {
      lastP = -1.0;
      if(!ok)
         return -1.0;
      long  lab[1];
      float pr[2];
      lab[0] = 0; pr[0] = 0.0f; pr[1] = 0.0f;
      if(!OnnxRun(m_h, ONNX_NO_CONVERSION, feat, lab, pr))
        {
         Print("SevenWave AI: OnnxRun failed ", GetLastError());
         return -1.0;
        }
      double p = (double)pr[1];
      if(!MathIsValidNumber(p))
         return -1.0;
      lastP = MathMax(0.0, MathMin(1.0, p));
      return lastP;
     }

   string            FeatureCsv(void) const
     {
      string s = "";
      for(int i = 0; i < SW_AI_FEATURES; i++)
         s += (i ? "," : "") + DoubleToString(feat[i], 6);
      return s;
     }
  };

#endif
