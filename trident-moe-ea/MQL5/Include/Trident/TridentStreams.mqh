//+------------------------------------------------------------------+
//| TridentStreams.mqh - Hourly AI Regime Router & 5-Stream Engine   |
//|                                                                  |
//| Routes each structure bar close across 5 streams (H1, H2, M30,   |
//| M15, M5) into strictly mutually-exclusive market corners:        |
//|  * Corner #2 (Prong 2 - 16Runes):                                |
//|      Active when H4 7-EMA stack == D1 stack (and H1 stack for    |
//|      M15/M5).                                                    |
//|  * Corner #4 (Prong 3 - ImpulseCascade):                         |
//|      Active ONLY when Corner #2 is OFF (GateRunesDir == 0) AND   |
//|      H4 Top-3 EMA stack == H1 Top-5 EMA stack AND H1 volatility  |
//|      regime >= 0.85x 20-day mean ATR.                            |
//|  * Corner #3 (Tangled Chop):                                     |
//|      Both gates return 0 -> sits out.                            |
//+------------------------------------------------------------------+
#ifndef TRIDENT_STREAMS_MQH
#define TRIDENT_STREAMS_MQH

#include <16Runes\Market.mqh>
#include <16Runes\Streams.mqh>

enum ENUM_TRIDENT_CORNER
  {
   TRIDENT_CORNER_NONE    = 0,  // Corner #3: Tangled Chop (Sit Out)
   TRIDENT_CORNER_16RUNES = 2,  // Corner #2: Macro Trend Coils (Prong 2)
   TRIDENT_CORNER_CASCADE = 4   // Corner #4: Fast V-Reversal Cascade (Prong 3)
  };

class CTridentStreams : public CR16Streams
  {
public:
   int               stCorner[R16_NSTREAMS];
   int               usedPivCascade[R16_NSTREAMS][R16_NRUNES];

                     CTridentStreams(void) : CR16Streams() { ResetAll(); }

   void              ResetAll(void)
     {
      Reset();
      for(int s = 0; s < R16_NSTREAMS; s++)
        {
         stCorner[s] = TRIDENT_CORNER_NONE;
         for(int r = 0; r < R16_NRUNES; r++)
            usedPivCascade[s][r] = -1;
        }
     }

   //--- Corner #4 Gate: Fast H4 Top-3 + H1 Top-5 Cascade when Corner #2 (16Runes) is OFF
   int               GateCascadeDir(int s, const CR16Market &mkt, datetime tc) const
     {
      int i4 = mkt.h4.LastClosedAt(tc);
      int i1 = mkt.h1.LastClosedAt(tc);
      if(i4 < 10 || i1 < 480)
         return 0;

      int st3_h4 = mkt.h4.StackTop3(i4);
      int st5_h1 = mkt.h1.StackTop5(i1);
      if(st3_h4 == 0 || st5_h1 != st3_h4)
         return 0;

      double a1 = mkt.h1.atr[i1];
      if(a1 <= 1e-9)
         return 0;
      int loI = MathMax(0, i1 - 479);
      double sumA1 = 0.0;
      for(int k = loI; k <= i1; k++)
         sumA1 += mkt.h1.atr[k];
      double meanA1 = sumA1 / (double)(i1 - loI + 1);
      double volReg = a1 / MathMax(meanA1, 1e-9);
      if(volReg < 0.85)
         return 0;

      return st3_h4;
     }

   //--- Current macro regime label for HUD display
   string            CurrentRegimeSummary(const CR16Market &mkt, datetime srvNow,
                                          bool enableSniper, bool enableRunes, bool enableCascade) const
     {
      int gR_htf = GateDir(0, mkt, srvNow);
      int gC_htf = (gR_htf == 0) ? GateCascadeDir(0, mkt, srvNow) : 0;
      string s1  = enableSniper ? "P1:SNIPER[ON]" : "P1:SNIPER[OFF]";
      string s2  = (!enableRunes)   ? "P2:16RUNES[DISABLED]"
                   : (gR_htf != 0   ? StringFormat("P2:16RUNES[ACTIVE %s]", gR_htf > 0 ? "BULL" : "BEAR")
                                    : "P2:16RUNES[SLEEP]");
      string s3  = (!enableCascade) ? "P3:CASCADE[DISABLED]"
                   : (gC_htf != 0   ? StringFormat("P3:CASCADE[ACTIVE %s]", gC_htf > 0 ? "BULL" : "BEAR")
                                    : "P3:CASCADE[SLEEP]");
      return s1 + " | " + s2 + " | " + s3;
     }

   //--- Arm stream s on completed bar close for either Prong 2 (16Runes) or Prong 3 (ImpulseCascade)
   void              ArmTrident(int s, const CR16Series &S, const CR16Market &mkt, double bidOpen,
                                bool enableRunes, bool enableCascade)
     {
      st[s].armed = false;
      stCorner[s] = TRIDENT_CORNER_NONE;

      int p = S.Last();
      if(p < 50)
         return;
      int rid = S.runeId[p];
      if(rid < 0 || rid >= R16_NRUNES)
         return;
      int d   = S.runeDir[p];
      int piv = S.pivIdx[p];
      if(piv < 0)
         return;

      int gRunes = GateDir(s, mkt, S.tc[p]);
      int chosenCorner = TRIDENT_CORNER_NONE;

      if(gRunes != 0)
        {
         // Corner #2 regime: only 16Runes is eligible
         if(!enableRunes || gRunes != d || piv == usedPiv[s][rid])
            return;
         chosenCorner = TRIDENT_CORNER_16RUNES;
        }
      else
        {
         // Corner #2 is OFF (0/16 Runes): check Corner #4 (ImpulseCascade)
         if(!enableCascade)
            return;
         int gCasc = GateCascadeDir(s, mkt, S.tc[p]);
         if(gCasc == 0 || gCasc != d || piv == usedPivCascade[s][rid])
            return;
         chosenCorner = TRIDENT_CORNER_CASCADE;
        }

      double L = S.trigPx[p];
      double a = S.atr[p];
      if(L <= 0.0 || a <= 0.0)
         return;

      if(d == 1)
        {
         if((L - bidOpen) > maxDistAtr * a || (bidOpen - L) > 0.5 * a)
            return;
        }
      else
        {
         if((bidOpen - L) > maxDistAtr * a || (L - bidOpen) > 0.5 * a)
            return;
        }

      st[s].armed   = true;
      st[s].dir     = d;
      st[s].level   = L;
      st[s].runeId  = rid;
      st[s].pivIdx  = piv;
      st[s].barIdx  = p;
      st[s].armedAt = S.tc[p];
      st[s].slPx    = S.slPx[p];
      st[s].patHAtr = S.patH[p] / a;
      st[s].qual    = S.qual[p];
      st[s].patSpan = S.patSpan[p];
      st[s].compRat = S.compRat[p];
      st[s].impVal  = S.impVal[p];
      stCorner[s]   = chosenCorner;

      if(S.lastU1Idx >= 0 && S.lastU1Idx < S.n) st[s].u1t = S.t[S.lastU1Idx];
      if(S.lastU2Idx >= 0 && S.lastU2Idx < S.n) st[s].u2t = S.t[S.lastU2Idx];
      if(S.lastL1Idx >= 0 && S.lastL1Idx < S.n) st[s].l1t = S.t[S.lastL1Idx];
      if(S.lastL2Idx >= 0 && S.lastL2Idx < S.n) st[s].l2t = S.t[S.lastL2Idx];
      st[s].u1p = S.lastU1Px; st[s].u2p = S.lastU2Px;
      st[s].l1p = S.lastL1Px; st[s].l2p = S.lastL2Px;
     }

   void              OnNewBarsTrident(const CR16Market &mkt, bool newM5, bool newM15, bool newM30, bool newH1, bool newH2,
                                      double bidNow, bool enableRunes, bool enableCascade)
     {
      if(newH1)  ArmTrident(0, mkt.h1,  mkt, bidNow, enableRunes, enableCascade);
      if(newH2)  ArmTrident(1, mkt.h2,  mkt, bidNow, enableRunes, enableCascade);
      if(newM30) ArmTrident(2, mkt.m30, mkt, bidNow, enableRunes, enableCascade);
      if(newM15) ArmTrident(3, mkt.m15, mkt, bidNow, enableRunes, enableCascade);
      if(newM5)  ArmTrident(4, mkt.m5,  mkt, bidNow, enableRunes, enableCascade);
     }

   bool              CheckBreakTrident(int s, double bid, double ask, int &outDir, double &outTrig, int &outCorner)
     {
      if(!st[s].armed)
         return false;
      if(st[s].dir == 1 && ask >= st[s].level)
        {
         outDir    = 1;
         outTrig   = MathMax(ask, st[s].level);
         outCorner = stCorner[s];
         st[s].armed = false;
         if(outCorner == TRIDENT_CORNER_CASCADE)
            usedPivCascade[s][st[s].runeId] = st[s].pivIdx;
         else
            usedPiv[s][st[s].runeId] = st[s].pivIdx;
         return true;
        }
      if(st[s].dir == -1 && bid <= st[s].level)
        {
         outDir    = -1;
         outTrig   = MathMin(bid, st[s].level);
         outCorner = stCorner[s];
         st[s].armed = false;
         if(outCorner == TRIDENT_CORNER_CASCADE)
            usedPivCascade[s][st[s].runeId] = st[s].pivIdx;
         else
            usedPiv[s][st[s].runeId] = st[s].pivIdx;
         return true;
        }
      return false;
     }
  };

#endif
