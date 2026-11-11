//+------------------------------------------------------------------+
//| Market.mqh - SevenWave multi-timeframe hierarchy                   |
//|                                                                    |
//|  M15, M30, H1 : broker bars (identical on whole-hour-offset feeds)  |
//|  H2      : built from H1, aligned to even UTC hours                 |
//|  H4      : built from H1, anchored to the 17:00 New-York close      |
//|  D1      : broker daily bars (NY-close days on NY+7 / CET feeds)    |
//| Only CLOSED bars are ever used.                                    |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_MARKET_MQH
#define SEVENWAVE_MARKET_MQH

#include "Clock.mqh"
#include "Series.mqh"

class CSwMarket
  {
public:
   string        sym;
   CSwClock      clock;
   CSwSeries     m15, m30, h1, h2, h4, d1;
   CSwAggregator agH2, agH4;
   datetime      lastM15, lastM30, lastH1, lastD1;
   bool          newM15, newM30, newH1, newH2, newH4, newD1;
   bool          ready;
   string        status;

                     CSwMarket(void) : lastM15(0), lastM30(0), lastH1(0), lastD1(0), ready(false) {}

   bool              Init(const string s)
     {
      sym = s;
      m15.Init("M15", true, 80000);
      m30.Init("M30", true, 40000);
      h1.Init("H1", true, 40000);
      h2.Init("H2", true, 20000);
      h4.Init("H4", false, 10000);
      d1.Init("D1", false, 4000);
      agH2.Init(2, 0);
      agH4.Init(4, 1);
      lastM15 = 0; lastM30 = 0; lastH1 = 0; lastD1 = 0;
      if(!clock.Detect(sym))
         Print("SevenWave: clock detection inconclusive yet - assuming ", clock.Describe());
      //--- deep history load (as much as the terminal/tester provides)
      int gotD1 = LoadNative(PERIOD_D1, 3000, d1, lastD1, 86400);
      int gotH1 = LoadH1(30000);
      int gotM30 = LoadNative(PERIOD_M30, 30000, m30, lastM30, 1800);
      int gotM15 = LoadNative(PERIOD_M15, 60000, m15, lastM15, 900);
      status = StringFormat("history D1=%d H1=%d M30=%d M15=%d H4=%d H2=%d clock=%s", gotD1, gotH1, gotM30, gotM15, h4.n, h2.n,
                            clock.Describe());
      Print("SevenWave: ", status);
      ready = (d1.n >= 210 && h4.n >= 210 && h1.n >= 600 && m15.n >= 300 && h2.n >= 300);
      return true;
     }

   //--- call every tick; sets the newXX flags
   void              Update(void)
     {
      newM15 = newM30 = newH1 = newH2 = newH4 = newD1 = false;
      //--- daily clock re-check (catches DST switches of the broker clock)
      if(TimeCurrent() - clock.LastDetect() > 86400)
         clock.Detect(sym);
      datetime d1t = iTime(sym, PERIOD_D1, 1);
      if(d1t > lastD1)
         newD1 = (AppendNative(PERIOD_D1, d1, lastD1, 86400) > 0);
      datetime h1t = iTime(sym, PERIOD_H1, 1);
      if(h1t > lastH1)
        {
         MqlRates r[];
         ArraySetAsSeries(r, false);
         int cnt = CopyRates(sym, PERIOD_H1, lastH1 + 1, h1t, r);
         int nh2 = h2.n, nh4 = h4.n;
         for(int i = 0; i < cnt; i++)
            if(r[i].time > lastH1 && r[i].time <= h1t)
               FeedH1(r[i]);
         datetime forming = iTime(sym, PERIOD_H1, 0);
         if(forming > 0)
           {
            agH2.FlushIfDone(forming, clock, h2);
            agH4.FlushIfDone(forming, clock, h4);
           }
         newH1 = (cnt > 0);
         newH2 = (h2.n > nh2);
         newH4 = (h4.n > nh4);
        }
      datetime m30t = iTime(sym, PERIOD_M30, 1);
      if(m30t > lastM30)
         newM30 = (AppendNative(PERIOD_M30, m30, lastM30, 1800) > 0);
      datetime m15t = iTime(sym, PERIOD_M15, 1);
      if(m15t > lastM15)
         newM15 = (AppendNative(PERIOD_M15, m15, lastM15, 900) > 0);
      if(!ready)
         ready = (d1.n >= 210 && h4.n >= 210 && h1.n >= 600 && m15.n >= 300 && h2.n >= 300);
     }

   //--- combined stack direction of a set of series as of server time `when` (0 if they disagree)
   int               StackAt(CSwSeries &s, datetime when)
     {
      int k = s.LastClosedAt(when);
      return (k >= 0) ? s.stackd[k] : 0;
     }

private:
   void              FeedH1(const MqlRates &b)
     {
      h1.Append(b.time, b.time + 3600, b.open, b.high, b.low, b.close);
      agH2.Feed(b.time, b.open, b.high, b.low, b.close, clock, h2);
      agH4.Feed(b.time, b.open, b.high, b.low, b.close, clock, h4);
      lastH1 = b.time;
     }

   int               LoadH1(int maxBars)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int cnt = CopyRates(sym, PERIOD_H1, 1, maxBars, r);
      for(int i = 0; i < cnt; i++)
         FeedH1(r[i]);
      datetime forming = iTime(sym, PERIOD_H1, 0);
      if(forming > 0)
        {
         agH2.FlushIfDone(forming, clock, h2);
         agH4.FlushIfDone(forming, clock, h4);
        }
      return MathMax(cnt, 0);
     }

   int               LoadNative(ENUM_TIMEFRAMES tf, int maxBars, CSwSeries &s, datetime &last, int secs)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int cnt = CopyRates(sym, tf, 1, maxBars, r);
      for(int i = 0; i < cnt; i++)
        {
         s.Append(r[i].time, r[i].time + secs, r[i].open, r[i].high, r[i].low, r[i].close);
         last = r[i].time;
        }
      return MathMax(cnt, 0);
     }

   int               AppendNative(ENUM_TIMEFRAMES tf, CSwSeries &s, datetime &last, int secs)
     {
      datetime upto = iTime(sym, tf, 1);
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int cnt = CopyRates(sym, tf, last + 1, upto, r);
      int added = 0;
      for(int i = 0; i < cnt; i++)
         if(r[i].time > last && r[i].time <= upto)
           {
            s.Append(r[i].time, r[i].time + secs, r[i].open, r[i].high, r[i].low, r[i].close);
            last = r[i].time;
            added++;
           }
      return added;
     }
  };

#endif

