//+------------------------------------------------------------------+
//| Streams.mqh - SevenWave v1.10 "Liquidity-Wave" setup streams       |
//|                                                                    |
//| A setup = a virtual stop order resting just inside an AGED,        |
//| UNBROKEN swing high (buy) / swing low (sell) of a structure        |
//| timeframe, armed ONLY when the higher-timeframe 7-EMA ribbon       |
//| stacks (10/16/26/41/66/105/168) agree.  Re-armed at every          |
//| structure-bar close, valid for the next structure bar, one shot    |
//| per pool (python_pipeline/sw_v110.py semantics).                   |
//|                                                                    |
//|  id stream  structure  trend gate          offset    pool age      |
//|  0  A       H1         H4 + D1 stacks      0.15 ATR  12-48 bars    |
//|  1  B       H2         H4 + D1 stacks      0.00 ATR   6-48 bars    |
//|  2  G       H1         H4 + D1 stacks      0.15 ATR   3-12 bars    |
//|  3  P       M15        H1 + H4 + D1 stacks 0.15 ATR  12-96 bars    |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_STREAMS_MQH
#define SEVENWAVE_STREAMS_MQH

#include "Market.mqh"

#define SW_NSTREAMS 4

struct SwTrigger
  {
   bool     armed;
   int      dir;          // +1 buy stop, -1 sell stop
   double   price;        // trigger level
   int      pivot;        // pivot bar index in the structure series (one shot per pool)
   int      barIdx;       // structure bar p the trigger was armed on
   double   level;        // the pool price
  };

class CSwStreams
  {
public:
   SwTrigger trg[SW_NSTREAMS];
   int       usedH[SW_NSTREAMS];
   int       usedL[SW_NSTREAMS];
   string    names[SW_NSTREAMS];
   double    weights[SW_NSTREAMS];

                     CSwStreams(void)
     {
      string nm[SW_NSTREAMS] = {"A", "B", "G", "P"};
      double w[SW_NSTREAMS] = {1.0, 1.0, 0.6, 0.8};
      for(int s = 0; s < SW_NSTREAMS; s++)
        {
         names[s] = nm[s]; weights[s] = w[s]; usedH[s] = -1; usedL[s] = -1; trg[s].armed = false;
        }
     }

   CSwSeries        *Structure(CSwMarket &mk, int s)
     {
      if(s == 1) return GetPointer(mk.h2);
      if(s == 3) return GetPointer(mk.m15);
      return GetPointer(mk.h1);
     }

   int               Trend(CSwMarket &mk, int s, datetime when)
     {
      int a = mk.StackAt(mk.h4, when), b = mk.StackAt(mk.d1, when);
      int hd = (a == b) ? a : 0;
      if(s == 3)
        {
         int c = mk.StackAt(mk.h1, when);
         return (c == hd) ? hd : 0;
        }
      return hd;
     }

   void              AgeWindow(int s, int &amin, int &amax, double &off)
     {
      switch(s)
        {
         case 0: amin = 12; amax = 48; off = 0.15; break;
         case 1: amin = 6;  amax = 48; off = 0.0;  break;
         case 2: amin = 3;  amax = 12; off = 0.15; break;
         default: amin = 12; amax = 96; off = 0.15; break;
        }
     }

   //--- (re)arm stream s at the close of its structure bar; bidOpen = first price of the new bar
   void              Arm(CSwMarket &mk, int s, double bidOpen)
     {
      CSwSeries *S = Structure(mk, s);
      trg[s].armed = false;
      int p = S.n - 1;
      if(p < 10)
         return;
      int amin, amax; double off;
      AgeWindow(s, amin, amax, off);
      int tr = Trend(mk, s, S.tc[p]);
      double a = S.atr[p];
      if(tr == 1 && S.phi[p] >= 0 && S.phi[p] != usedH[s])
        {
         int age = p - S.phi[p];
         double L = S.ph[p] - off * a;
         if(age >= amin && age <= amax && (L - bidOpen) <= 3.0 * a)
           {
            trg[s].armed = true; trg[s].dir = 1; trg[s].price = L; trg[s].pivot = S.phi[p]; trg[s].barIdx = p;
            trg[s].level = S.ph[p];
           }
        }
      else if(tr == -1 && S.pli[p] >= 0 && S.pli[p] != usedL[s])
        {
         int age = p - S.pli[p];
         double L = S.pl[p] + off * a;
         if(age >= amin && age <= amax && (bidOpen - L) <= 3.0 * a)
           {
            trg[s].armed = true; trg[s].dir = -1; trg[s].price = L; trg[s].pivot = S.pli[p]; trg[s].barIdx = p;
            trg[s].level = S.pl[p];
           }
        }
     }

   void              MarkUsed(int s)
     {
      if(!trg[s].armed)
         return;
      if(trg[s].dir == 1) usedH[s] = trg[s].pivot; else usedL[s] = trg[s].pivot;
      trg[s].armed = false;
     }

   bool              IsHit(int s, double bid, double ask) const
     {
      if(!trg[s].armed) return false;
      return (trg[s].dir == 1 && ask >= trg[s].price) || (trg[s].dir == -1 && bid <= trg[s].price);
     }

   //--- first stream (priority order) whose trigger is hit by the current quotes, -1 if none
   int               Hit(double bid, double ask)
     {
      for(int s = 0; s < SW_NSTREAMS; s++)
         if(IsHit(s, bid, ask)) return s;
      return -1;
     }
  };

#endif
