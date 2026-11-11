//+------------------------------------------------------------------+
//| Market.mqh - 16Runes multi-timeframe closed-bar manager          |
//|                                                                  |
//| Maintains closed-bar series M5, M15, M30, H1, H2, H4, D1:        |
//|  * M5, M15, M30, H1 from broker native bars (closed bars only)   |
//|  * H2 aggregated from closed H1 on even UTC hours                |
//|  * H4 and D1 aggregated from closed H1 on 17:00 NY boundaries    |
//+------------------------------------------------------------------+
#ifndef RUNES16_MARKET_MQH
#define RUNES16_MARKET_MQH

#include "Series.mqh"

class CR16Market
  {
public:
   string            m_sym;
   CR16Clock         m_clk;
   CR16Series        m5, m15, m30, h1, h2, h4, d1;
   CR16Aggregator    aggH2, aggH4, aggD1;
   datetime          lastM5, lastM15, lastM30, lastH1;

                     CR16Market(void) : lastM5(0), lastM15(0), lastM30(0), lastH1(0) {}

   bool              Init(const string sym, int fallbackOffHours, bool autoOff)
     {
      m_sym = sym;
      m_clk.Init(fallbackOffHours, autoOff);
      m_clk.RefreshOffset(TimeCurrent());

      m5.Init("M5",   true,  0.12, 120000);
      m15.Init("M15", true,  0.12, 50000);
      m30.Init("M30", true,  0.12, 30000);
      h1.Init("H1",   true,  0.12, 16000);
      h2.Init("H2",   true,  0.08, 9000);
      h4.Init("H4",   false, 0.12, 5000);
      d1.Init("D1",   false, 0.12, 2000);

      aggH2.Init(2,  0);   // 2h on even UTC hours
      aggH4.Init(4,  1);   // 4h on 17:00 NY
      aggD1.Init(24, 1);   // 24h on 17:00 NY

      lastM5 = 0; lastM15 = 0; lastM30 = 0; lastH1 = 0;

      if(!LoadNative(PERIOD_M5,  105000, m5,  lastM5,  300))  return false;
      if(!LoadNative(PERIOD_M15, 45000,  m15, lastM15, 900))  return false;
      if(!LoadNative(PERIOD_M30, 25000,  m30, lastM30, 1800)) return false;
      if(!LoadH1(16000))                                      return false;
      return true;
     }

   bool              LoadNative(ENUM_TIMEFRAMES tf, int count, CR16Series &dst, datetime &lastT, int barSec)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int got = CopyRates(m_sym, tf, 1, count, r);   // start_pos=1 -> strictly CLOSED bars
      if(got <= 0)
         return false;
      for(int i = 0; i < got; i++)
        {
         dst.Append(r[i].time, r[i].time + barSec, r[i].open, r[i].high, r[i].low, r[i].close);
         lastT = r[i].time;
        }
      return true;
     }

   bool              LoadH1(int count)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int got = CopyRates(m_sym, PERIOD_H1, 1, count, r);
      if(got <= 0)
         return false;
      for(int i = 0; i < got; i++)
         FeedClosedH1(r[i]);
      MqlRates cur[];
      if(CopyRates(m_sym, PERIOD_H1, 0, 1, cur) == 1)
        {
         aggH2.FlushIfDone(cur[0].time, m_clk, h2);
         aggH4.FlushIfDone(cur[0].time, m_clk, h4);
         aggD1.FlushIfDone(cur[0].time, m_clk, d1);
        }
      return true;
     }

   void              FeedClosedH1(const MqlRates &b, bool &newH2Out)
     {
      h1.Append(b.time, b.time + 3600, b.open, b.high, b.low, b.close);
      bool e2 = aggH2.Feed(b.time, b.open, b.high, b.low, b.close, m_clk, h2);
      aggH4.Feed(b.time, b.open, b.high, b.low, b.close, m_clk, h4);
      aggD1.Feed(b.time, b.open, b.high, b.low, b.close, m_clk, d1);
      if(e2) newH2Out = true;
      lastH1 = b.time;
     }

   void              FeedClosedH1(const MqlRates &b)
     {
      bool dummy = false;
      FeedClosedH1(b, dummy);
     }

   void              SyncClosedBars(bool &newM5, bool &newM15, bool &newM30, bool &newH1, bool &newH2)
     {
      newM5  = SyncNative(PERIOD_M5,  m5,  lastM5,  300);
      newM15 = SyncNative(PERIOD_M15, m15, lastM15, 900);
      newM30 = SyncNative(PERIOD_M30, m30, lastM30, 1800);
      SyncH1(newH1, newH2);
     }

   bool              SyncNative(ENUM_TIMEFRAMES tf, CR16Series &dst, datetime &lastT, int barSec)
     {
      datetime closedT = iTime(m_sym, tf, 1);
      if(closedT <= 0 || closedT <= lastT)
         return false;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int got = CopyRates(m_sym, tf, 1, 16, r);
      if(got <= 0)
         return false;
      bool added = false;
      for(int i = 0; i < got; i++)
         if(r[i].time > lastT)
           {
            dst.Append(r[i].time, r[i].time + barSec, r[i].open, r[i].high, r[i].low, r[i].close);
            lastT = r[i].time;
            added = true;
           }
      return added;
     }

   void              SyncH1(bool &newH1, bool &newH2)
     {
      newH1 = false; newH2 = false;
      datetime closedT = iTime(m_sym, PERIOD_H1, 1);
      if(closedT <= 0 || closedT <= lastH1)
         return;
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int got = CopyRates(m_sym, PERIOD_H1, 1, 16, r);
      if(got <= 0)
         return;
      for(int i = 0; i < got; i++)
         if(r[i].time > lastH1)
           {
            FeedClosedH1(r[i], newH2);
            newH1 = true;
           }
      datetime curOpen = iTime(m_sym, PERIOD_H1, 0);
      if(curOpen > lastH1)
        {
         if(aggH2.FlushIfDone(curOpen, m_clk, h2)) newH2 = true;
         aggH4.FlushIfDone(curOpen, m_clk, h4);
         aggD1.FlushIfDone(curOpen, m_clk, d1);
        }
     }

   bool              Ready(void) const
     {
      return (m5.n >= 200 && m15.n >= 200 && m30.n >= 200 && h1.n >= 481 && h2.n >= 170 && h4.n >= 170 && d1.n >= 50);
     }
  };

#endif
