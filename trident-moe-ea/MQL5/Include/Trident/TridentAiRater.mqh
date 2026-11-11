//+------------------------------------------------------------------+
//| TridentAiRater.mqh - Dual ONNX Meta-Labeler (Prong 2 & Prong 3)  |
//|                                                                  |
//| Embeds BOTH Strict-OOS (2017-2023 SEEN Only) 16-Feature ONNX     |
//| Meta-Labelers inside the compiled .ex5:                          |
//|  * Prong 2 (Corner #2 - 16Runes):        16runes_meta.onnx       |
//|  * Prong 3 (Corner #4 - ImpulseCascade): impulse_cascade_meta.onnx|
//+------------------------------------------------------------------+
#ifndef TRIDENT_AIRATER_MQH
#define TRIDENT_AIRATER_MQH

#include "TridentStreams.mqh"

#resource "\\Files\\models\\16runes_meta.onnx"         as uchar TridentRunesOnnx[]
#resource "\\Files\\models\\impulse_cascade_meta.onnx" as uchar TridentCascadeOnnx[]

#define TRIDENT_AI_FEATURES       16
#define TRIDENT_R16_THR_HTF       0.32000000
#define TRIDENT_R16_THR_M5        0.36000000
#define TRIDENT_R16_THR_HIGH      0.62049085

#define TRIDENT_CAS_THR_HTF       0.29720000
#define TRIDENT_CAS_THR_M5        0.47300000
#define TRIDENT_CAS_THR_HIGH      0.61870000

class CTridentAiRater
  {
private:
   long              m_hRunes;
   long              m_hCascade;
   bool              m_readyRunes;
   bool              m_readyCascade;
   string            m_lastCallStr;
   string            m_lastDecStr;

   static double     Clamp(double x, double lo, double hi)
     {
      return (x < lo) ? lo : ((x > hi) ? hi : x);
     }

   bool              InitSingleModel(const uchar &buf[], const string tag, long &outHandle)
     {
      outHandle = OnnxCreateFromBuffer(buf, ONNX_DEFAULT);
      if(outHandle == INVALID_HANDLE)
        {
         PrintFormat("[Trident-AI] OnnxCreateFromBuffer(%s) failed (err=%d)", tag, GetLastError());
         return false;
        }
      const ulong inShape[]  = {1, TRIDENT_AI_FEATURES};
      const ulong outLabel[] = {1};
      const ulong outProbs[] = {1, 2};
      if(!OnnxSetInputShape(outHandle, 0, inShape) ||
         !OnnxSetOutputShape(outHandle, 0, outLabel) ||
         !OnnxSetOutputShape(outHandle, 1, outProbs))
        {
         PrintFormat("[Trident-AI] OnnxSetShape(%s) failed (err=%d)", tag, GetLastError());
         OnnxRelease(outHandle);
         outHandle = INVALID_HANDLE;
         return false;
        }
      return true;
     }

public:
                     CTridentAiRater(void) : m_hRunes(INVALID_HANDLE), m_hCascade(INVALID_HANDLE),
                                             m_readyRunes(false), m_readyCascade(false),
                                             m_lastCallStr("none"), m_lastDecStr("none") {}
                    ~CTridentAiRater(void) { Release(); }

   bool              Init(void)
     {
      Release();
      m_readyRunes   = InitSingleModel(TridentRunesOnnx,   "Prong2_16Runes",   m_hRunes);
      m_readyCascade = InitSingleModel(TridentCascadeOnnx, "Prong3_Cascade",   m_hCascade);
      return (m_readyRunes && m_readyCascade);
     }

   void              Release(void)
     {
      if(m_hRunes != INVALID_HANDLE)
        {
         OnnxRelease(m_hRunes);
         m_hRunes = INVALID_HANDLE;
        }
      if(m_hCascade != INVALID_HANDLE)
        {
         OnnxRelease(m_hCascade);
         m_hCascade = INVALID_HANDLE;
        }
      m_readyRunes   = false;
      m_readyCascade = false;
     }

   bool              ReadyRunes(void)   const { return m_readyRunes; }
   bool              ReadyCascade(void) const { return m_readyCascade; }
   string            LastCallStr(void)  const { return m_lastCallStr; }
   string            LastDecisionStr(void) const { return m_lastDecStr; }

   double            Threshold(int corner, int stream) const
     {
      if(corner == TRIDENT_CORNER_CASCADE)
         return (stream == 4) ? TRIDENT_CAS_THR_M5 : TRIDENT_CAS_THR_HTF;
      return (stream == 4) ? TRIDENT_R16_THR_M5 : TRIDENT_R16_THR_HTF;
     }

   double            ConvictionMult(int corner, double p, bool growthMode) const
     {
      double hi = (corner == TRIDENT_CORNER_CASCADE) ? TRIDENT_CAS_THR_HIGH : TRIDENT_R16_THR_HIGH;
      if(p >= hi)
         return growthMode ? 1.30 : 1.15;
      return 1.00;
     }

   bool              BuildFeatures(int stream, const SR16Arm &arm, const CR16Market &mkt,
                                   datetime nowSrv, float &f[]) const
     {
      ArrayResize(f, TRIDENT_AI_FEATURES);
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

      int rid = arm.runeId;
      f[0]  = (float)((double)stream / 4.0);
      f[1]  = (float)arm.dir;
      f[2]  = (float)((rid == 9 || rid == 10 || rid == 13 || rid == 14) ? 1.0 : 0.0);
      f[3]  = (float)((rid == 0 || rid == 4) ? 1.0 : 0.0);
      f[4]  = (float)((rid == 3 || rid == 7) ? 1.0 : 0.0);
      f[5]  = (float)((rid == 2 || rid == 6) ? 1.0 : 0.0);
      f[6]  = (float)((rid == 4 || rid == 6 || rid == 11) ? 1.0 : 0.0);
      f[7]  = (float)arm.qual;
      f[8]  = (float)Clamp(arm.patHAtr, 0.5, 10.0);
      f[9]  = (float)Clamp(arm.compRat, 0.2, 1.2);
      f[10] = (float)Clamp(arm.impVal, -6.0, 6.0);
      f[11] = (float)volU;
      f[12] = (float)volReg;
      f[13] = (float)Clamp(cost / a1, 0.0, 0.5);
      f[14] = (float)Clamp(h4RibSp, -6.0, 6.0);
      f[15] = (float)liqSess;
      return true;
     }

   double            ScoreCorner(int corner, int stream, const SR16Arm &arm,
                                 const CR16Market &mkt, datetime nowSrv, float &fOut[])
     {
      if(!BuildFeatures(stream, arm, mkt, nowSrv, fOut))
         return -1.0;

      long h = (corner == TRIDENT_CORNER_CASCADE) ? m_hCascade : m_hRunes;
      bool rdy = (corner == TRIDENT_CORNER_CASCADE) ? m_readyCascade : m_readyRunes;
      if(!rdy || h == INVALID_HANDLE)
         return 0.5;

      long  label[1];
      float probs[2];
      if(!OnnxRun(h, ONNX_NO_CONVERSION, fOut, label, probs))
         return 0.5;

      double p    = (double)probs[1];
      double thr  = Threshold(corner, stream);
      bool   keep = (p >= thr);
      string cTag = (corner == TRIDENT_CORNER_CASCADE) ? "P3:CASCADE" : "P2:16RUNES";
      m_lastCallStr = StringFormat("[%s] %s %s %s (%s)",
                                   cTag,
                                   TimeToString(mkt.m_clk.ToUtc(nowSrv), TIME_DATE|TIME_MINUTES),
                                   R16_STREAM_NAMES[stream],
                                   R16_NAMES[arm.runeId],
                                   arm.dir > 0 ? "LONG" : "SHORT");
      m_lastDecStr  = StringFormat("p=%.3f vs thr=%.3f -> %s", p, thr, keep ? "ALLOW" : "VETO");
      return p;
     }
  };

#endif
