//+------------------------------------------------------------------+
//| Series.mqh - SevenWave closed-bar series per timeframe             |
//|                                                                    |
//| Each series holds CLOSED bars only (never the forming bar) with:   |
//|  * the 7-EMA ribbon 10/16/26/41/66/105/168 (seed = first close,    |
//|    a = 2/(n+1) - identical to sw_engine.ema_nb)                     |
//|  * ATR(14) Wilder seeded by the running mean of the first 14 TRs    |
//|    (identical to sw_engine.atr_nb)                                  |
//|  * stack state (+1 all EMAs ordered fast>slow, -1 reversed, 0 mixed)|
//|  * optional liquidity pools: confirmed 3/3 fractal swing highs/lows |
//|    that no later bar has traded through (sw_study17.pools_nb)       |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_SERIES_MQH
#define SEVENWAVE_SERIES_MQH

#include "Clock.mqh"

#define SW_NEMA 7
#define SW_POOL_MAX 4096
const double SW_PERIODS[SW_NEMA] = {10.0, 16.0, 26.0, 41.0, 66.0, 105.0, 168.0};   // v1.10 geometric ribbon (ratio 1.6)

class CSwSeries
  {
public:
   string   name;
   bool     withPools;
   int      n;
   datetime t[];      // bar open (server)
   datetime tc[];     // bar known-closed time (server)
   double   o[], h[], l[], c[];
   double   ema[];    // n * 7
   double   atr[];
   int      stackd[];
   int      order[];
   //--- pools (structure series only): nearest unbroken levels as of each bar
   double   ph[], pl[];
   int      phi[], pli[];
   //--- private pool stacks
   double   m_shv[]; int m_shi[]; int m_nsh;
   double   m_slv[]; int m_sli[]; int m_nsl;
   double   m_trSum;
   int      m_cap;

                     CSwSeries(void) : n(0), withPools(false), m_nsh(0), m_nsl(0), m_trSum(0.0), m_cap(0) {}

   void              Init(const string nm, bool pools, int reserve)
     {
      name = nm; withPools = pools; n = 0; m_nsh = 0; m_nsl = 0; m_trSum = 0.0; m_cap = 0;
      Reserve(reserve);
      if(pools)
        {
         ArrayResize(m_shv, SW_POOL_MAX); ArrayResize(m_shi, SW_POOL_MAX);
         ArrayResize(m_slv, SW_POOL_MAX); ArrayResize(m_sli, SW_POOL_MAX);
        }
     }

   void              Reserve(int cap)
     {
      if(cap <= m_cap)
         return;
      m_cap = cap;
      ArrayResize(t, cap); ArrayResize(tc, cap); ArrayResize(o, cap); ArrayResize(h, cap); ArrayResize(l, cap);
      ArrayResize(c, cap); ArrayResize(ema, cap * SW_NEMA); ArrayResize(atr, cap); ArrayResize(stackd, cap);
      ArrayResize(order, cap);
      if(withPools)
        {
         ArrayResize(ph, cap); ArrayResize(pl, cap); ArrayResize(phi, cap); ArrayResize(pli, cap);
        }
     }

   double            E(int i, int k) const { return ema[i * SW_NEMA + k]; }
   int               Last(void) const { return n - 1; }

   //--- index of the last bar closed at or before server time `when` (-1 if none)
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
         return;                                                     // never re-append
      if(n >= m_cap)
         Reserve(MathMax(1024, m_cap * 2));
      int i = n;
      t[i] = bt; tc[i] = btc; o[i] = bo; h[i] = bh; l[i] = bl; c[i] = bc;
      //--- EMA ribbon
      for(int k = 0; k < SW_NEMA; k++)
        {
         double a = 2.0 / (SW_PERIODS[k] + 1.0);
         ema[i * SW_NEMA + k] = (i == 0) ? bc : bc * a + ema[(i - 1) * SW_NEMA + k] * (1.0 - a);
        }
      //--- ATR(14) Wilder
      double tr = (i == 0) ? (bh - bl) : MathMax(bh - bl, MathMax(MathAbs(bh - c[i - 1]), MathAbs(bl - c[i - 1])));
      if(i < 14)
        {
         m_trSum += tr;
         atr[i] = m_trSum / (i + 1);
        }
      else
         atr[i] = atr[i - 1] + (tr - atr[i - 1]) / 14.0;
      //--- stack state + order score
      bool bull = true, bear = true;
      int sc = 0;
      for(int k = 0; k < SW_NEMA - 1; k++)
        {
         double d = ema[i * SW_NEMA + k + 1] - ema[i * SW_NEMA + k];   // slow - fast
         if(!(d < 0.0)) bull = false;
         if(!(d > 0.0)) bear = false;
         if(d < 0.0) sc++;
         else if(d > 0.0) sc--;
        }
      stackd[i] = bull ? 1 : (bear ? -1 : 0);
      order[i] = sc;
      n++;
      if(withPools)
         UpdatePools(i);
     }

private:
   void              UpdatePools(int i)
     {
      const int L = 3, R = 3;
      int p = i - R;
      if(p - L >= 0)
        {
         bool okh = true, okl = true;
         for(int q = p - L; q <= p + R; q++)
           {
            if(q == p) continue;
            if(h[q] >= h[p]) okh = false;
            if(l[q] <= l[p]) okl = false;
           }
         if(okh && m_nsh < SW_POOL_MAX) { m_shv[m_nsh] = h[p]; m_shi[m_nsh] = p; m_nsh++; }
         if(okl && m_nsl < SW_POOL_MAX) { m_slv[m_nsl] = l[p]; m_sli[m_nsl] = p; m_nsl++; }
        }
      //--- drop pools traded through by bar i
      int k = 0;
      for(int q = 0; q < m_nsh; q++)
         if(h[i] <= m_shv[q] || m_shi[q] > i - 1) { m_shv[k] = m_shv[q]; m_shi[k] = m_shi[q]; k++; }
      m_nsh = k;
      k = 0;
      for(int q = 0; q < m_nsl; q++)
         if(l[i] >= m_slv[q] || m_sli[q] > i - 1) { m_slv[k] = m_slv[q]; m_sli[k] = m_sli[q]; k++; }
      m_nsl = k;
      //--- nearest unbroken pool above this bar's high / below its low
      double best = DBL_MAX; int bi = -1;
      for(int q = 0; q < m_nsh; q++)
         if(m_shv[q] > h[i] && m_shv[q] < best) { best = m_shv[q]; bi = q; }
      ph[i] = (bi >= 0) ? m_shv[bi] : 0.0;
      phi[i] = (bi >= 0) ? m_shi[bi] : -1;
      best = -DBL_MAX; bi = -1;
      for(int q = 0; q < m_nsl; q++)
         if(m_slv[q] < l[i] && m_slv[q] > best) { best = m_slv[q]; bi = q; }
      pl[i] = (bi >= 0) ? m_slv[bi] : 0.0;
      pli[i] = (bi >= 0) ? m_sli[bi] : -1;
     }
  };

//+------------------------------------------------------------------+
//| Builds bars of a coarser timeframe from closed H1 bars             |
//| mode 0: UTC-aligned buckets of `hours` (H2 = even UTC hours)       |
//| mode 1: New-York-anchored buckets starting 17:00 NY (H4, D1)       |
//+------------------------------------------------------------------+
class CSwAggregator
  {
public:
   int      hours;
   int      mode;
   long     curKey;
   bool     open;
   datetime bt, lastT;
   double   bo, bh, bl, bc;

                     CSwAggregator(void) : hours(4), mode(1), curKey(LONG_MIN), open(false), bt(0), lastT(0), bo(0), bh(0), bl(0), bc(0) {}
   void              Init(int hrs, int md) { hours = hrs; mode = md; curKey = LONG_MIN; open = false; }

   long              KeyOf(datetime srv, const CSwClock &clk) const
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

   //--- feed one closed H1 bar; returns true and fills `out` when a bucket is finalised by this bar's arrival
   bool              Feed(datetime srvT, double o1, double h1, double l1, double c1, const CSwClock &clk, CSwSeries &out)
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

   //--- finalise the open bucket if `nextBarSrv` (the forming H1 bar) belongs to a later bucket
   bool              FlushIfDone(datetime nextBarSrv, const CSwClock &clk, CSwSeries &out)
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


