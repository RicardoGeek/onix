//+------------------------------------------------------------------+
//| Series.mqh - 16Runes closed-bar series + 16-Rune pattern engine  |
//|                                                                  |
//| Holds CLOSED bars only with:                                     |
//|  * Geometric 7-EMA ribbon 10/16/26/41/66/105/168                 |
//|  * Wilder ATR(14)                                                |
//|  * Causal 16-Rune detector (exact parity to detect_16runes_v4)   |
//+------------------------------------------------------------------+
#ifndef RUNES16_SERIES_MQH
#define RUNES16_SERIES_MQH

#include "Clock.mqh"

#define R16_NEMA 7
#define R16_NRUNES 16

const double R16_PERIODS[R16_NEMA] = {10.0, 16.0, 26.0, 41.0, 66.0, 105.0, 168.0};

const string R16_NAMES[R16_NRUNES] =
  {
   "ASC_TRI",      "BULL_WEDGE",   "BULL_FLAG",    "BULL_SYM_TRI",
   "DESC_TRI",     "BEAR_WEDGE",   "BEAR_FLAG",    "BEAR_SYM_TRI",
   "DBL_BOTTOM",   "TRPL_BOTTOM",  "INV_HS",       "FALL_WEDGE",
   "DBL_TOP",      "TRPL_TOP",     "HEAD_SHLDR",   "RISE_WEDGE"
  };

const string R16_FULL_TITLES[R16_NRUNES] =
  {
   "Ascending Triangle (Bull Cont)",
   "Bullish Wedge (Bull Cont)",
   "Bullish Flag (Bull Cont)",
   "Bullish Symmetrical Triangle (Bull Cont)",
   "Descending Triangle (Bear Cont)",
   "Bearish Wedge (Bear Cont)",
   "Bearish Flag (Bear Cont)",
   "Bearish Symmetrical Triangle (Bear Cont)",
   "Double Bottom (Bull Rev)",
   "Triple Bottom (Bull Rev)",
   "Inverted Head & Shoulders (Bull Rev)",
   "Falling Wedge (Bull Rev)",
   "Double Top (Bear Rev)",
   "Triple Top (Bear Rev)",
   "Head & Shoulders (Bear Rev)",
   "Rising Wedge (Bear Rev)"
  };

class CR16Series
  {
public:
   string   name;
   bool     withRunes;
   double   offAtr;
   int      n;
   datetime t[];      // bar open (server)
   datetime tc[];     // bar known-closed time (server)
   double   o[], h[], l[], c[];
   double   ema[];    // n * 7
   double   atr[];
   int      stackd[];
   int      order[];

   //--- Per-bar detected Rune telemetry (structure series only)
   int      runeId[];
   int      runeDir[];
   double   trigPx[];
   double   slPx[];
   double   patH[];
   int      pivIdx[];
   double   qual[];
   int      patSpan[];
   double   compRat[];
   double   impVal[];

   //--- Latest detected Rune drawing coordinates (bar indices & prices)
   int      lastU1Idx, lastU2Idx, lastL1Idx, lastL2Idx;
   double   lastU1Px,  lastU2Px,  lastL1Px,  lastL2Px;

   //--- Ring buffer of last 6 confirmed (3,3) fractal swing highs and swing lows
   double   m_shv[6]; int m_shi[6]; int m_nsh;
   double   m_slv[6]; int m_sli[6]; int m_nsl;
   double   m_trSum;
   int      m_cap;

                     CR16Series(void) : n(0), withRunes(false), offAtr(0.12), m_nsh(0), m_nsl(0), m_trSum(0.0), m_cap(0),
                                        lastU1Idx(-1), lastU2Idx(-1), lastL1Idx(-1), lastL2Idx(-1),
                                        lastU1Px(0.0), lastU2Px(0.0), lastL1Px(0.0), lastL2Px(0.0) {}

   void              Init(const string nm, bool runes, double off, int reserve)
     {
      name = nm; withRunes = runes; offAtr = off;
      n = 0; m_nsh = 0; m_nsl = 0; m_trSum = 0.0; m_cap = 0;
      for(int k = 0; k < 6; k++)
        {
         m_shv[k] = 0.0; m_shi[k] = -1;
         m_slv[k] = 0.0; m_sli[k] = -1;
        }
      Reserve(reserve);
     }

   void              Reserve(int cap)
     {
      if(cap <= m_cap)
         return;
      m_cap = cap;
      ArrayResize(t, cap); ArrayResize(tc, cap); ArrayResize(o, cap); ArrayResize(h, cap); ArrayResize(l, cap);
      ArrayResize(c, cap); ArrayResize(ema, cap * R16_NEMA); ArrayResize(atr, cap); ArrayResize(stackd, cap);
      ArrayResize(order, cap);
      if(withRunes)
        {
         ArrayResize(runeId, cap); ArrayResize(runeDir, cap); ArrayResize(trigPx, cap); ArrayResize(slPx, cap);
         ArrayResize(patH, cap);   ArrayResize(pivIdx, cap);  ArrayResize(qual, cap);   ArrayResize(patSpan, cap);
         ArrayResize(compRat, cap); ArrayResize(impVal, cap);
        }
     }

   double            E(int i, int k) const { return ema[i * R16_NEMA + k]; }
   int               Last(void) const { return n - 1; }

   int               StackTop5(int i) const
     {
      if(i < 0 || i >= n)
         return 0;
      bool bull5 = true, bear5 = true;
      for(int k = 0; k < 4; k++)   // 4 adjacent pairs of Top-5 EMAs: 10, 16, 26, 41, 66
        {
         double d = ema[i * R16_NEMA + k + 1] - ema[i * R16_NEMA + k];
         if(!(d < 0.0)) bull5 = false;
         if(!(d > 0.0)) bear5 = false;
        }
      return bull5 ? 1 : (bear5 ? -1 : 0);
     }

   int               StackTop3(int i) const
     {
      if(i < 0 || i >= n)
         return 0;
      bool bull3 = true, bear3 = true;
      for(int k = 0; k < 2; k++)   // 2 adjacent pairs of Top-3 EMAs: 10, 16, 26
        {
         double d = ema[i * R16_NEMA + k + 1] - ema[i * R16_NEMA + k];
         if(!(d < 0.0)) bull3 = false;
         if(!(d > 0.0)) bear3 = false;
        }
      return bull3 ? 1 : (bear3 ? -1 : 0);
     }

   int               LastClosedAt(datetime when) const
     {
      int lo = 0, hi = n - 1, ans = -1;
      while(lo <= hi)
        {
         int mid = (lo + hi) >> 1;
         if(tc[mid] <= when) { ans = mid; lo = mid + 1; }
         else hi = mid - 1;
        }
      return ans;
     }

   void              Append(datetime bt, datetime btc, double bo, double bh, double bl, double bc)
     {
      if(n > 0 && bt <= t[n - 1])
         return;
      if(n >= m_cap)
         Reserve(MathMax(1024, m_cap * 2));
      int i = n;
      t[i] = bt; tc[i] = btc; o[i] = bo; h[i] = bh; l[i] = bl; c[i] = bc;
      for(int k = 0; k < R16_NEMA; k++)
        {
         double a = 2.0 / (R16_PERIODS[k] + 1.0);
         ema[i * R16_NEMA + k] = (i == 0) ? bc : bc * a + ema[(i - 1) * R16_NEMA + k] * (1.0 - a);
        }
      double tr = (i == 0) ? (bh - bl) : MathMax(bh - bl, MathMax(MathAbs(bh - c[i - 1]), MathAbs(bl - c[i - 1])));
      if(i < 14)
        {
         m_trSum += tr;
         atr[i] = m_trSum / (i + 1);
        }
      else
         atr[i] = atr[i - 1] + (tr - atr[i - 1]) / 14.0;

      bool bull = true, bear = true;
      int sc = 0;
      for(int k = 0; k < R16_NEMA - 1; k++)
        {
         double d = ema[i * R16_NEMA + k + 1] - ema[i * R16_NEMA + k];
         if(!(d < 0.0)) bull = false;
         if(!(d > 0.0)) bear = false;
         if(d < 0.0) sc++;
         else if(d > 0.0) sc--;
        }
      stackd[i] = bull ? 1 : (bear ? -1 : 0);
      order[i] = sc;
      n++;
      if(withRunes)
         UpdateRunes(i);
     }

private:
   void              UpdateRunes(int i)
     {
      runeId[i] = -1; runeDir[i] = 0; trigPx[i] = 0.0; slPx[i] = 0.0; patH[i] = 0.0;
      pivIdx[i] = -1; qual[i] = 0.0; patSpan[i] = 0; compRat[i] = 1.0; impVal[i] = 0.0;

      const int L = 3, R = 3, maxSpan = 72;
      if(i < L + R + 30)
         return;

      int p = i - R;
      bool isH = true, isL = true;
      double hp = h[p], lp = l[p];
      for(int q = p - L; q <= p + R; q++)
        {
         if(q == p) continue;
         if(h[q] >= hp) isH = false;
         if(l[q] <= lp) isL = false;
        }
      if(isH)
        {
         for(int k = 0; k < 5; k++) { m_shv[k] = m_shv[k + 1]; m_shi[k] = m_shi[k + 1]; }
         m_shv[5] = hp; m_shi[5] = p;
         if(m_nsh < 6) m_nsh++;
        }
      if(isL)
        {
         for(int k = 0; k < 5; k++) { m_slv[k] = m_slv[k + 1]; m_sli[k] = m_sli[k + 1]; }
         m_slv[5] = lp; m_sli[5] = p;
         if(m_nsl < 6) m_nsl++;
        }

      if(m_nsh < 3 || m_nsl < 3)
         return;
      double a = atr[i];
      if(a <= 1e-9)
         return;

      double h1 = m_shv[3], h2 = m_shv[4], h3 = m_shv[5];
      int   ih1 = m_shi[3], ih2 = m_shi[4], ih3 = m_shi[5];
      double l1 = m_slv[3], l2 = m_slv[4], l3 = m_slv[5];
      int   il1 = m_sli[3], il2 = m_sli[4], il3 = m_sli[5];

      double ha = h2, hb = h3;
      int   iha = ih2, ihb = ih3;
      double la = l2, lb = l3;
      int   ila = il2, ilb = il3;

      int start2 = MathMin(iha, ila);
      int end2   = MathMax(ihb, ilb);
      int span2  = end2 - start2;
      if(span2 < 5 || (i - end2) > 36)
         return;

      int lookPre = MathMax(0, start2 - 24);
      double imp = (c[start2] - c[lookPre]) / a;
      double poleLo = l[lookPre], poleHi = h[lookPre];
      for(int q = lookPre; q <= start2; q++)
        {
         if(l[q] < poleLo) poleLo = l[q];
         if(h[q] > poleHi) poleHi = h[q];
        }
      double bullPole = (ha - poleLo) / a;
      double bearPole = (poleHi - la) / a;

      bool unbrokenHiB = true, coilAboveLb = true;
      double floorCoil = lb + 0.20 * (hb - lb);
      for(int q = ihb + 1; q <= i; q++)
        {
         if(h[q] > hb) { unbrokenHiB = false; break; }
         if(l[q] < floorCoil) coilAboveLb = false;
        }
      double top2 = MathMax(ha, hb);
      bool unbrokenTop2 = true;
      for(int q = ihb + 1; q <= i; q++)
         if(h[q] > top2) { unbrokenTop2 = false; break; }

      bool unbrokenLoB = true, coilBelowHb = true;
      double ceilCoil = hb - 0.20 * (hb - lb);
      for(int q = ilb + 1; q <= i; q++)
        {
         if(l[q] < lb) { unbrokenLoB = false; break; }
         if(h[q] > ceilCoil) coilBelowHb = false;
        }
      double bot2 = MathMin(la, lb);
      bool unbrokenBot2 = true;
      for(int q = ilb + 1; q <= i; q++)
         if(l[q] < bot2) { unbrokenBot2 = false; break; }

      double dh  = (hb - ha) / a;
      double dl  = (lb - la) / a;
      double wA  = (ha - la) / a;
      double wB  = (hb - lb) / a;
      double cr2 = wB / MathMax(wA, 1e-6);

      int    bestR = -1, bestD = 0, bestPiv = -1, bestSp = span2;
      double bestTrig = 0.0, bestSl = 0.0, bestH = 0.0, bestQ = -1.0, bestCr = cr2;
      int    u1i = iha, u2i = ihb, l1i = ila, l2i = ilb;
      double u1p = ha,  u2p = hb,  l1p = la,  l2p = lb;

      //--- 3-TROUGH / 3-PEAK REVERSALS (Runes 9, 10, 13, 14)
      int span3L = il3 - il1;
      if(span3L >= 8 && span3L <= maxSpan && (i - il3) <= 24)
        {
         double neckH = -1e18;
         int neckIh = -1;
         for(int k = 3; k < 6; k++)
            if(il1 < m_shi[k] && m_shi[k] < il3 && m_shv[k] > neckH)
              {
               neckH = m_shv[k]; neckIh = m_shi[k];
              }
         if(neckIh >= 0)
           {
            bool unbrokenNh = true;
            for(int q = neckIh + 1; q <= i; q++)
               if(h[q] > neckH) { unbrokenNh = false; break; }
            double minL3 = MathMin(l1, MathMin(l2, l3));
            if(unbrokenNh && (neckH - minL3) >= 0.85 * a)
              {
               double minSh = MathMin(l1, l3);
               if(l2 <= minSh - 0.20 * a && MathAbs(l3 - l1) <= 0.85 * a)
                 {
                  double qscore = 1.60 + 0.25 * (minSh - l2) / a - 0.3 * MathAbs(l3 - l1) / a;
                  if(qscore > bestQ)
                    {
                     bestR = 10; bestD = 1; bestTrig = neckH - offAtr * a;
                     bestSl = l3; bestH = neckH - l2; bestPiv = neckIh; bestQ = qscore;
                     bestSp = span3L; bestCr = (neckH - l3) / MathMax(neckH - l2, 1e-6);
                     u1i = il1; u2i = il3; u1p = neckH; u2p = neckH;
                     l1i = il1; l2i = il3; l1p = l1;    l2p = l3;
                    }
                 }
               double spread3L = MathMax(l1, MathMax(l2, l3)) - minL3;
               if(spread3L <= 0.60 * a)
                 {
                  double qscore = 1.55 - 0.5 * spread3L / a;
                  if(qscore > bestQ)
                    {
                     bestR = 9; bestD = 1; bestTrig = neckH - offAtr * a;
                     bestSl = MathMin(l2, l3); bestH = neckH - minL3; bestPiv = neckIh;
                     bestQ = qscore; bestSp = span3L; bestCr = 0.85;
                     u1i = il1; u2i = il3; u1p = neckH; u2p = neckH;
                     l1i = il1; l2i = il3; l1p = minL3; l2p = minL3;
                    }
                 }
              }
           }
        }

      int span3H = ih3 - ih1;
      if(span3H >= 8 && span3H <= maxSpan && (i - ih3) <= 24)
        {
         double neckL = 1e18;
         int neckIl = -1;
         for(int k = 3; k < 6; k++)
            if(ih1 < m_sli[k] && m_sli[k] < ih3 && m_slv[k] < neckL)
              {
               neckL = m_slv[k]; neckIl = m_sli[k];
              }
         if(neckIl >= 0)
           {
            bool unbrokenNl = true;
            for(int q = neckIl + 1; q <= i; q++)
               if(l[q] < neckL) { unbrokenNl = false; break; }
            double maxH3 = MathMax(h1, MathMax(h2, h3));
            if(unbrokenNl && (maxH3 - neckL) >= 0.85 * a)
              {
               double maxSh = MathMax(h1, h3);
               if(h2 >= maxSh + 0.20 * a && MathAbs(h3 - h1) <= 0.85 * a)
                 {
                  double qscore = 1.60 + 0.25 * (h2 - maxSh) / a - 0.3 * MathAbs(h3 - h1) / a;
                  if(qscore > bestQ)
                    {
                     bestR = 14; bestD = -1; bestTrig = neckL + offAtr * a;
                     bestSl = h3; bestH = h2 - neckL; bestPiv = neckIl; bestQ = qscore;
                     bestSp = span3H; bestCr = (h3 - neckL) / MathMax(h2 - neckL, 1e-6);
                     u1i = ih1; u2i = ih3; u1p = h1;    u2p = h3;
                     l1i = ih1; l2i = ih3; l1p = neckL; l2p = neckL;
                    }
                 }
               double spread3H = maxH3 - MathMin(h1, MathMin(h2, h3));
               if(spread3H <= 0.60 * a)
                 {
                  double qscore = 1.55 - 0.5 * spread3H / a;
                  if(qscore > bestQ)
                    {
                     bestR = 13; bestD = -1; bestTrig = neckL + offAtr * a;
                     bestSl = MathMax(h2, h3); bestH = maxH3 - neckL; bestPiv = neckIl;
                     bestQ = qscore; bestSp = span3H; bestCr = 0.85;
                     u1i = ih1; u2i = ih3; u1p = maxH3; u2p = maxH3;
                     l1i = ih1; l2i = ih3; l1p = neckL; l2p = neckL;
                    }
                 }
              }
           }
        }

      //--- 2-PEAK / 2-TROUGH PATTERNS (Runes 0..8, 11, 12, 15)
      if(span2 <= maxSpan && wA >= 0.70 && wB >= 0.35)
        {
         if(ila < ihb && ihb < ilb && MathAbs(dl) <= 0.45 && (hb - MathMin(la, lb)) >= 0.90 * a && unbrokenHiB)
           {
            double qscore = 1.45 - 0.5 * MathAbs(dl);
            if(qscore > bestQ)
              {
               bestR = 8; bestD = 1; bestTrig = hb - offAtr * a;
               bestSl = lb; bestH = hb - MathMin(la, lb); bestPiv = ihb; bestQ = qscore; bestSp = span2; bestCr = cr2;
               u1i = ila; u2i = ilb; u1p = hb; u2p = hb;
               l1i = ila; l2i = ilb; l1p = la; l2p = lb;
              }
           }
         if(iha < ilb && ilb < ihb && MathAbs(dh) <= 0.45 && (MathMax(ha, hb) - lb) >= 0.90 * a && unbrokenLoB)
           {
            double qscore = 1.45 - 0.5 * MathAbs(dh);
            if(qscore > bestQ)
              {
               bestR = 12; bestD = -1; bestTrig = lb + offAtr * a;
               bestSl = hb; bestH = MathMax(ha, hb) - lb; bestPiv = ilb; bestQ = qscore; bestSp = span2; bestCr = cr2;
               u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
               l1i = iha; l2i = ihb; l1p = lb; l2p = lb;
              }
           }
         if(MathAbs(dh) <= 0.40 && dl >= 0.20 && wB < 0.90 * wA && unbrokenTop2 && coilAboveLb)
           {
            double qscore = 1.40 - 0.5 * MathAbs(dh) + 0.2 * MathMin(dl, 2.0);
            if(qscore > bestQ)
              {
               bestR = 0; bestD = 1; bestTrig = top2 - offAtr * a;
               bestSl = lb; bestH = top2 - la; bestPiv = ihb; bestQ = qscore; bestSp = span2; bestCr = cr2;
               u1i = iha; u2i = ihb; u1p = top2; u2p = top2;
               l1i = ila; l2i = ilb; l1p = la;   l2p = lb;
              }
           }
         if(MathAbs(dl) <= 0.40 && dh <= -0.20 && wB < 0.90 * wA && unbrokenBot2 && coilBelowHb)
           {
            double qscore = 1.40 - 0.5 * MathAbs(dl) + 0.2 * MathMin(-dh, 2.0);
            if(qscore > bestQ)
              {
               bestR = 4; bestD = -1; bestTrig = bot2 + offAtr * a;
               bestSl = hb; bestH = ha - bot2; bestPiv = ilb; bestQ = qscore; bestSp = span2; bestCr = cr2;
               u1i = iha; u2i = ihb; u1p = ha;   u2p = hb;
               l1i = ila; l2i = ilb; l1p = bot2; l2p = bot2;
              }
           }
         if(dh <= -0.18 && dl >= 0.18 && wB <= 0.80 * wA)
           {
            double symQ = 1.30 + 0.3 * (1.0 - cr2);
            if(unbrokenHiB && coilAboveLb && imp >= -0.2 && symQ > bestQ)
              {
               bestR = 3; bestD = 1; bestTrig = hb - offAtr * a;
               bestSl = lb; bestH = ha - la; bestPiv = ihb; bestQ = symQ; bestSp = span2; bestCr = cr2;
               u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
               l1i = ila; l2i = ilb; l1p = la; l2p = lb;
              }
            if(unbrokenLoB && coilBelowHb && imp <= 0.2 && symQ > bestQ)
              {
               bestR = 7; bestD = -1; bestTrig = lb + offAtr * a;
               bestSl = hb; bestH = ha - la; bestPiv = ilb; bestQ = symQ; bestSp = span2; bestCr = cr2;
               u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
               l1i = ila; l2i = ilb; l1p = la; l2p = lb;
              }
           }
         if(dh < -0.12 && dl < -0.02 && unbrokenHiB && coilAboveLb)
           {
            double slopeDiff = MathAbs((-dh) - (-dl));
            if(bullPole >= 2.0 && slopeDiff <= 0.70 && (ha - lb) <= 0.65 * (ha - poleLo))
              {
               double qscore = 1.35 + 0.15 * MathMin(bullPole, 5.0) - 0.3 * slopeDiff;
               if(qscore > bestQ)
                 {
                  bestR = 2; bestD = 1; bestTrig = hb - offAtr * a;
                  bestSl = lb; bestH = ha - poleLo; bestPiv = ihb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                  u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                  l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                 }
              }
            if((-dh) > (-dl) + 0.10 && wB < 0.85 * wA)
              {
               double qscore = 1.25 + 0.3 * (1.0 - cr2);
               if(imp >= 0.2)
                 {
                  if(qscore > bestQ)
                    {
                     bestR = 1; bestD = 1; bestTrig = hb - offAtr * a;
                     bestSl = lb; bestH = ha - lb; bestPiv = ihb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                     u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                     l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                    }
                 }
               else if(wB < 0.72 * wA)
                 {
                  if(qscore > bestQ)
                    {
                     bestR = 11; bestD = 1; bestTrig = hb - offAtr * a;
                     bestSl = lb; bestH = ha - lb; bestPiv = ihb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                     u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                     l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                    }
                 }
              }
           }
         if(dh > 0.02 && dl > 0.12 && unbrokenLoB && coilBelowHb)
           {
            double slopeDiff = MathAbs(dl - dh);
            if(bearPole >= 2.0 && slopeDiff <= 0.70 && (hb - la) <= 0.65 * (poleHi - la))
              {
               double qscore = 1.35 + 0.15 * MathMin(bearPole, 5.0) - 0.3 * slopeDiff;
               if(qscore > bestQ)
                 {
                  bestR = 6; bestD = -1; bestTrig = lb + offAtr * a;
                  bestSl = hb; bestH = poleHi - la; bestPiv = ilb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                  u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                  l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                 }
              }
            if(dl > dh + 0.10 && wB < 0.85 * wA)
              {
               double qscore = 1.25 + 0.3 * (1.0 - cr2);
               if(imp <= -0.2)
                 {
                  if(qscore > bestQ)
                    {
                     bestR = 5; bestD = -1; bestTrig = lb + offAtr * a;
                     bestSl = hb; bestH = hb - la; bestPiv = ilb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                     u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                     l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                    }
                 }
               else if(wB < 0.72 * wA)
                 {
                  if(qscore > bestQ)
                    {
                     bestR = 15; bestD = -1; bestTrig = lb + offAtr * a;
                     bestSl = hb; bestH = hb - la; bestPiv = ilb; bestQ = qscore; bestSp = span2; bestCr = cr2;
                     u1i = iha; u2i = ihb; u1p = ha; u2p = hb;
                     l1i = ila; l2i = ilb; l1p = la; l2p = lb;
                    }
                 }
              }
           }
        }

      if(bestR >= 0)
        {
         runeId[i]  = bestR;
         runeDir[i] = bestD;
         trigPx[i]  = bestTrig;
         slPx[i]    = bestSl;
         patH[i]    = bestH;
         pivIdx[i]  = bestPiv;
         qual[i]    = bestQ;
         patSpan[i] = bestSp;
         compRat[i] = bestCr;
         impVal[i]  = imp * bestD;
         lastU1Idx  = u1i; lastU2Idx = u2i; lastL1Idx = l1i; lastL2Idx = l2i;
         lastU1Px   = u1p; lastU2Px  = u2p; lastL1Px  = l1p; lastL2Px  = l2p;
        }
     }
  };

//+------------------------------------------------------------------+
//| Builds bars of a coarser timeframe from closed H1 bars           |
//+------------------------------------------------------------------+
class CR16Aggregator
  {
public:
   int      hours;
   int      mode;
   long     curKey;
   bool     open;
   datetime bt, lastT;
   double   bo, bh, bl, bc;

                     CR16Aggregator(void) : hours(4), mode(1), curKey(LONG_MIN), open(false), bt(0), lastT(0), bo(0), bh(0), bl(0), bc(0) {}
   void              Init(int hrs, int md) { hours = hrs; mode = md; curKey = LONG_MIN; open = false; }

   long              KeyOf(datetime srv, const CR16Clock &clk) const
     {
      if(mode == 0)
        {
         datetime u = clk.ToUtc(srv);
         return (long)u / (long)(hours * 3600);
        }
      datetime ny = clk.ToNy(srv);
      long x = (long)ny - 17 * 3600;
      long hsec = (long)hours * 3600;
      return (x >= 0) ? x / hsec : -((-x + hsec - 1) / hsec);
     }

   bool              Feed(datetime srvT, double o1, double h1, double l1, double c1, const CR16Clock &clk, CR16Series &out)
     {
      long key = KeyOf(srvT, clk);
      bool emitted = false;
      if(open && key != curKey)
        {
         out.Append(bt, lastT + 3600, bo, bh, bl, bc);
         emitted = true;
         open = false;
        }
      if(!open)
        {
         open = true; curKey = key; bt = srvT; bo = o1; bh = h1; bl = l1; bc = c1; lastT = srvT;
        }
      else
        {
         bh = MathMax(bh, h1); bl = MathMin(bl, l1); bc = c1; lastT = srvT;
        }
      return emitted;
     }

   bool              FlushIfDone(datetime nextBarSrv, const CR16Clock &clk, CR16Series &out)
     {
      if(!open)
         return false;
      if(KeyOf(nextBarSrv, clk) != curKey)
        {
         out.Append(bt, lastT + 3600, bo, bh, bl, bc);
         open = false;
         return true;
        }
      return false;
     }
  };

#endif
