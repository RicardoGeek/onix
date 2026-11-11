//+------------------------------------------------------------------+
//| AiRater.mqh - OliverKell ONNX Meta-Labeler (16 features)         |
//|                                                                  |
//| Evaluates the embedded oliver_kell_meta.onnx (StandardScaler +   |
//| LogisticRegression C=0.05 trained on 2017-2023 Dukascopy setups) |
//| to discard fake breakouts and boost high-conviction setups.      |
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_AIRATER_MQH
#define OLIVERKELL_AIRATER_MQH

#include "Streams.mqh"
#include "AiModelMeta.mqh"

#resource "\\Files\\models\\oliver_kell_meta.onnx" as uchar OkOnnxModel[]

class COkAiRater
  {
private:
   long              m_handle;
   bool              m_ready;
   string            m_lastCallStr;
   string            m_lastDecStr;

   static double     Clamp(double x, double lo, double hi)
     {
      return (x < lo) ? lo : ((x > hi) ? hi : x);
     }

public:
                     COkAiRater(void) : m_handle(INVALID_HANDLE), m_ready(false),
                                        m_lastCallStr("none"), m_lastDecStr("none") {}
                    ~COkAiRater(void) { Release(); }

   bool              Init(void)
     {
      Release();
      m_handle = OnnxCreateFromBuffer(OkOnnxModel, ONNX_DEFAULT);
      if(m_handle == INVALID_HANDLE)
        {
         PrintFormat("[OliverKell-AI] OnnxCreateFromBuffer failed (err=%d)", GetLastError());
         return false;
        }
      const ulong inShape[]  = {1, OK_AI_FEATURES};
      const ulong outLabel[] = {1};
      const ulong outProbs[] = {1, 2};
      if(!OnnxSetInputShape(m_handle, 0, inShape) ||
         !OnnxSetOutputShape(m_handle, 0, outLabel) ||
         !OnnxSetOutputShape(m_handle, 1, outProbs))
        {
         PrintFormat("[OliverKell-AI] OnnxSetShape failed (err=%d)", GetLastError());
         Release();
         return false;
        }
      m_ready = true;
      return true;
     }

   void              Release(void)
     {
      if(m_handle != INVALID_HANDLE)
        {
         OnnxRelease(m_handle);
         m_handle = INVALID_HANDLE;
        }
      m_ready = false;
     }

   bool              Ready(void) const { return m_ready; }
   string            LastCallStr(void) const { return m_lastCallStr; }
   string            LastDecisionStr(void) const { return m_lastDecStr; }

   double            Threshold(int stream) const
     {
      return (stream == 4) ? OK_AI_THR_M5 : OK_AI_THR_HTF;
     }

   double            ConvictionMult(double p, bool growthMode) const
     {
      if(p >= OK_AI_THR_HIGH)
         return growthMode ? 1.30 : 1.15;
      return 1.00;
     }

   //--- Build the exact 16 features matching extract_final_features() in kell_study8.py
   bool              BuildFeatures(int stream, const SOkArm &arm, const COkMarket &mkt,
                                   datetime nowSrv, float &f[]) const
     {
      ArrayResize(f, OK_AI_FEATURES);
      int kh1 = mkt.h1.LastClosedAt(nowSrv);
      int kh4 = mkt.h4.LastClosedAt(nowSrv);
      if(kh1 < 480 || kh4 < 10)
         return false;

      double a1 = mkt.h1.atr[kh1];
      if(a1 <= 1e-9)
         return false;

      int loI = MathMax(0, kh1 - 479);
      double sumA1 = 0.0;
      for(int k = loI; k <= kh1; k++)
         sumA1 += mkt.h1.atr[k];
      double meanA1 = sumA1 / (double)(kh1 - loI + 1);
      double volReg = Clamp(a1 / MathMax(meanA1, 1e-9), 0.3, 3.5);
      double volU   = MathAbs(volReg - 1.0);

      datetime nowUtc = mkt.m_clk.ToUtc(nowSrv);
      int hrUtc = (int)(((long)nowUtc / 3600) % 24);
      double cost = (hrUtc == 21 || hrUtc == 22) ? 0.60 : 0.30;
      double liqSess = (hrUtc >= 6 && hrUtc <= 16) ? 1.0 : ((hrUtc >= 17 && hrUtc <= 22) ? -1.0 : 0.0);

      double a4 = MathMax(mkt.h4.atr[kh4], 1e-9);
      double h4RibSp = ((mkt.h4.E(kh4, 0) - mkt.h4.E(kh4, 6)) / a4) * (double)arm.dir;

      int sid = arm.setupId;
      f[0]  = (float)((double)stream / 4.0);
      f[1]  = (float)arm.dir;
      f[2]  = (float)((sid >= 6 && arm.qual >= 1.50) ? 1.0 : 0.0);
      f[3]  = (float)((sid == 0 || sid == 1) ? 1.0 : 0.0);
      f[4]  = (float)((sid == 2 || sid == 3) ? 1.0 : 0.0);
      f[5]  = (float)((sid == 4 || sid == 5) ? 1.0 : 0.0);
      f[6]  = (float)((sid == 1 || sid == 5) ? 1.0 : 0.0);
      f[7]  = (float)arm.qual;
      f[8]  = (float)Clamp(arm.baseHAtr, 0.5, 10.0);
      f[9]  = (float)Clamp(arm.compRat, 0.2, 1.2);
      f[10] = (float)Clamp(arm.impVal, -6.0, 6.0);
      f[11] = (float)(Clamp(arm.emaExt, -4.0, 4.0) + 0.25 * liqSess);
      f[12] = (float)volU;
      f[13] = (float)volReg;
      f[14] = (float)Clamp(cost / a1, 0.0, 0.5);
      f[15] = (float)Clamp(h4RibSp, -6.0, 6.0);
      return true;
     }

   double            Score(int stream, const SOkArm &arm, const COkMarket &mkt, datetime nowSrv, float &fOut[])
     {
      if(!BuildFeatures(stream, arm, mkt, nowSrv, fOut))
         return -1.0;
      if(!m_ready)
         return 0.5;
      long  label[1];
      float probs[2];
      if(!OnnxRun(m_handle, ONNX_NO_CONVERSION, fOut, label, probs))
         return 0.5;
      double p = (double)probs[1];
      double thr = Threshold(stream);
      bool keep = (p >= thr);
      m_lastCallStr = StringFormat("%s %s %s (%s)",
                                   TimeToString(mkt.m_clk.ToUtc(nowSrv), TIME_DATE|TIME_MINUTES),
                                   OK_STREAM_NAMES[stream],
                                   OK_SETUP_NAMES[arm.setupId],
                                   arm.dir > 0 ? "LONG" : "SHORT");
      m_lastDecStr  = StringFormat("p=%.3f vs thr=%.3f -> %s", p, thr, keep ? "ALLOW" : "VETO");
      return p;
     }
  };

#endif
