//+------------------------------------------------------------------+
//| Streams.mqh - OliverKell 5-stream structure + HTF ribbon gate    |
//|                                                                  |
//| Streams (exact parity with kell_study8.py / kell_export.py):     |
//|   0: H1  Oliver Kell Cycle gated by H4 + D1        weight = 1.00 |
//|   1: H2  Oliver Kell Cycle gated by H4 + D1        weight = 1.00 |
//|   2: M30 Oliver Kell Cycle gated by H4 + D1        weight = 0.90 |
//|   3: M15 Oliver Kell Cycle gated by H1 + H4 + D1   weight = 0.80 |
//|   4: M5  Oliver Kell Cycle gated by H1 + H4 + D1   weight = 0.60 |
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_STREAMS_MQH
#define OLIVERKELL_STREAMS_MQH

#include "Market.mqh"

#define OK_NSTREAMS 5

const string OK_STREAM_NAMES[OK_NSTREAMS]   = {"H1", "H2", "M30", "M15", "M5"};
const double OK_STREAM_WEIGHTS[OK_NSTREAMS] = {1.00, 1.00, 0.90, 0.80, 0.60};

struct SOkArm
  {
   bool              armed;
   int               dir;          // +1 buy stop, -1 sell stop
   double            level;        // trigger price
   int               setupId;      // 0..7
   int               pivIdx;       // pivot index in structure series
   int               barIdx;       // structure bar index p that armed this level
   datetime          armedAt;      // server time when armed
   double            slPx;         // structural SL price (below breakout base)
   double            baseHAtr;     // base height / structure ATR
   double            qual;         // geometric quality score
   int               patSpan;      // pattern span in structure bars
   double            compRat;      // base compression wB / wA
   double            impVal;       // prior impulse aligned with dir
   double            emaExt;       // distance from EMA20 in ATRs aligned with dir
   datetime          u1t, u2t, l1t, l2t;
   double            u1p, u2p, l1p, l2p;
  };

class COkStreams
  {
public:
   SOkArm            st[OK_NSTREAMS];
   int               usedPiv[OK_NSTREAMS][OK_NSETUPS];
   double            maxDistAtr;

                     COkStreams(void) : maxDistAtr(3.0) { Reset(); }

   void              Reset(void)
     {
      for(int s = 0; s < OK_NSTREAMS; s++)
        {
         st[s].armed    = false;
         st[s].dir      = 0;
         st[s].level    = 0.0;
         st[s].setupId  = -1;
         st[s].pivIdx   = -1;
         st[s].barIdx   = -1;
         st[s].armedAt  = 0;
         st[s].slPx     = 0.0;
         st[s].baseHAtr = 0.0;
         st[s].qual     = 0.0;
         st[s].patSpan  = 0;
         st[s].compRat  = 1.0;
         st[s].impVal   = 0.0;
         st[s].emaExt   = 0.0;
         st[s].u1t = 0; st[s].u2t = 0; st[s].l1t = 0; st[s].l2t = 0;
         st[s].u1p = 0; st[s].u2p = 0; st[s].l1p = 0; st[s].l2p = 0;
         for(int r = 0; r < OK_NSETUPS; r++)
            usedPiv[s][r] = -1;
        }
     }

   //--- Higher-timeframe ribbon stack gate at structure bar close time tc
   int               GateDir(int s, const COkMarket &mkt, datetime tc) const
     {
      int i4 = mkt.h4.LastClosedAt(tc);
      int id = mkt.d1.LastClosedAt(tc);
      if(i4 < 0 || id < 0)
         return 0;
      int g4 = mkt.h4.stackd[i4];
      int gd = mkt.d1.stackd[id];
      if(gd == 0)
         gd = mkt.d1.StackTop5(id);
      if(gd == 0)
         gd = mkt.d1.StackTop3(id);
      if(g4 == 0 || g4 != gd)
         return 0;
      if(s >= 3)   // M15 (3) and M5 (4) also require H1 stack agreement
        {
         int i1 = mkt.h1.LastClosedAt(tc);
         if(i1 < 0 || mkt.h1.stackd[i1] != g4)
            return 0;
        }
      return g4;
     }

   //--- Called when stream s's structure timeframe closes a new bar (exact match to kell_events_nb)
   void              Arm(int s, const COkSeries &S, const COkMarket &mkt, double bidOpen)
     {
      st[s].armed = false;
      int p = S.Last();
      if(p < 50)
         return;
      int sid = S.setupId[p];
      if(sid < 0 || sid >= OK_NSETUPS)
         return;
      int d = S.setupDir[p];
      if(d == -1 && sid != 7)
         return;
      if(sid == 2 && s == 4)
         return;
      if(sid == 4 && (s == 2 || s == 3))
         return;
      int g = GateDir(s, mkt, S.tc[p]);
      if(g == 0 || g != d)
         return;
      int piv = S.pivIdx[p];
      if(piv < 0 || piv == usedPiv[s][sid])
         return;

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

      st[s].armed    = true;
      st[s].dir      = d;
      st[s].level    = L;
      st[s].setupId  = sid;
      st[s].pivIdx   = piv;
      st[s].barIdx   = p;
      st[s].armedAt  = S.tc[p];
      st[s].slPx     = S.slPx[p];
      st[s].baseHAtr = S.baseH[p] / a;
      st[s].qual     = S.qual[p];
      st[s].patSpan  = S.patSpan[p];
      st[s].compRat  = S.compRat[p];
      st[s].impVal   = S.impVal[p];
      st[s].emaExt   = S.emaExt[p];

      if(S.lastU1Idx >= 0 && S.lastU1Idx < S.n) st[s].u1t = S.t[S.lastU1Idx];
      if(S.lastU2Idx >= 0 && S.lastU2Idx < S.n) st[s].u2t = S.t[S.lastU2Idx];
      if(S.lastL1Idx >= 0 && S.lastL1Idx < S.n) st[s].l1t = S.t[S.lastL1Idx];
      if(S.lastL2Idx >= 0 && S.lastL2Idx < S.n) st[s].l2t = S.t[S.lastL2Idx];
      st[s].u1p = S.lastU1Px; st[s].u2p = S.lastU2Px;
      st[s].l1p = S.lastL1Px; st[s].l2p = S.lastL2Px;
     }

   void              OnNewBars(const COkMarket &mkt, bool newM5, bool newM15, bool newM30, bool newH1, bool newH2, double bidNow)
     {
      if(newH1)  Arm(0, mkt.h1,  mkt, bidNow);
      if(newH2)  Arm(1, mkt.h2,  mkt, bidNow);
      if(newM30) Arm(2, mkt.m30, mkt, bidNow);
      if(newM15) Arm(3, mkt.m15, mkt, bidNow);
      if(newM5)  Arm(4, mkt.m5,  mkt, bidNow);
     }

   //--- Tick check: returns true if stream s crosses its armed Oliver Kell trigger level
   bool              CheckBreak(int s, double bid, double ask, int &outDir, double &outTrig)
     {
      if(!st[s].armed)
         return false;
      if(st[s].dir == 1 && ask >= st[s].level)
        {
         outDir  = 1;
         outTrig = MathMax(ask, st[s].level);
         st[s].armed = false;
         usedPiv[s][st[s].setupId] = st[s].pivIdx;
         return true;
        }
      if(st[s].dir == -1 && bid <= st[s].level)
        {
         outDir  = -1;
         outTrig = MathMin(bid, st[s].level);
         st[s].armed = false;
         usedPiv[s][st[s].setupId] = st[s].pivIdx;
         return true;
        }
      return false;
     }
  };

#endif
