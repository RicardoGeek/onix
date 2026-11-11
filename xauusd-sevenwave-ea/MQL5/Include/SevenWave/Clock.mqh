//+------------------------------------------------------------------+
//| Clock.mqh - SevenWave broker-clock model (no user timezone input)  |
//|                                                                    |
//| Spot gold stops trading every day at 17:00 New York.  The server   |
//| hour of that daily break, seen across the H1 history, reveals the  |
//| broker's clock: NY-locked (server = NY + k, e.g. Pepperstone /     |
//| GetLeveraged NY+7), EU-DST (server = UTC + k + EU summer time,     |
//| e.g. Upcomers CET/CEST) or a fixed UTC offset.  The best-fitting   |
//| model converts ANY historical or live server time to UTC and to    |
//| New-York time with the real US / EU DST calendars - identical in   |
//| the Strategy Tester, on a VPS and on a live terminal.  Live, the   |
//| model is cross-checked against TimeTradeServer() - TimeGMT().      |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_CLOCK_MQH
#define SEVENWAVE_CLOCK_MQH

enum ENUM_SW_CLOCK { SW_CLOCK_NY = 0, SW_CLOCK_EU = 1, SW_CLOCK_FIXED = 2 };

class CSwClock
  {
private:
   int      m_regime;
   int      m_k;
   double   m_fit;
   int      m_samples;
   datetime m_lastDetect;

   static datetime NthSunday(int year, int month, int n)          // n>=1: n-th Sunday, n=-1: last Sunday
     {
      MqlDateTime d; ZeroMemory(d);
      d.year = year; d.mon = month; d.day = 1;
      datetime first = StructToTime(d);
      MqlDateTime f; TimeToStruct(first, f);
      int add = (7 - f.day_of_week) % 7;                           // days to the first Sunday
      if(n > 0)
         return first + (datetime)((add + 7 * (n - 1)) * 86400);
      // last Sunday: first Sunday of next month - 7 days
      int ny = (month == 12) ? year + 1 : year;
      int nm = (month == 12) ? 1 : month + 1;
      return NthSunday(ny, nm, 1) - 7 * 86400;
     }

public:
                     CSwClock(void) : m_regime(SW_CLOCK_NY), m_k(7), m_fit(0.0), m_samples(0), m_lastDetect(0) {}

   //--- US daylight time at a UTC instant: 2nd Sunday of March 07:00 UTC .. 1st Sunday of November 06:00 UTC
   static bool       UsDst(datetime utc)
     {
      MqlDateTime d; TimeToStruct(utc, d);
      datetime st = NthSunday(d.year, 3, 2) + 7 * 3600;
      datetime en = NthSunday(d.year, 11, 1) + 6 * 3600;
      return (utc >= st && utc < en);
     }
   //--- EU summer time at a UTC instant: last Sunday of March 01:00 UTC .. last Sunday of October 01:00 UTC
   static bool       EuDst(datetime utc)
     {
      MqlDateTime d; TimeToStruct(utc, d);
      datetime st = NthSunday(d.year, 3, -1) + 3600;
      datetime en = NthSunday(d.year, 10, -1) + 3600;
      return (utc >= st && utc < en);
     }

   //--- model-specific conversion server -> UTC
   static datetime   ToUtcModel(datetime srv, int regime, int k)
     {
      if(regime == SW_CLOCK_NY)
        {
         datetime nyl = srv - (datetime)(k * 3600);                  // NY local
         datetime guess = nyl + 5 * 3600;                            // EST
         return UsDst(guess) ? nyl + 4 * 3600 : guess;
        }
      if(regime == SW_CLOCK_EU)
        {
         datetime guess = srv - (datetime)(k * 3600);
         return EuDst(guess - 3600) ? guess - 3600 : guess;
        }
      return srv - (datetime)(k * 3600);
     }
   static datetime   UtcToNy(datetime utc) { return UsDst(utc) ? utc - 4 * 3600 : utc - 5 * 3600; }

   datetime          ToUtc(datetime srv) const { return ToUtcModel(srv, m_regime, m_k); }
   datetime          ToNy(datetime srv)  const { return UtcToNy(ToUtc(srv)); }
   int               Regime(void) const { return m_regime; }
   int               K(void) const { return m_k; }
   double            Fit(void) const { return m_fit; }
   int               Samples(void) const { return m_samples; }
   string            Describe(void) const
     {
      string r = (m_regime == SW_CLOCK_NY) ? StringFormat("NY%+d", m_k) :
                 (m_regime == SW_CLOCK_EU) ? StringFormat("UTC%+d+EU-DST", m_k) : StringFormat("UTC%+d fixed", m_k);
      return StringFormat("%s (fit %.0f%% of %d daily breaks)", r, m_fit * 100.0, m_samples);
     }

   //--- detect from H1 history; call at init and once a day
   bool              Detect(const string sym)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int n = CopyRates(sym, PERIOD_H1, 1, 24 * 260, r);
      if(n < 200)
         return false;
      //--- daily break samples: a single missing H1 bar between two weekday bars
      datetime miss[];
      int ns = 0;
      ArrayResize(miss, n);
      for(int i = 1; i < n; i++)
        {
         long gap = (long)(r[i].time - r[i - 1].time);
         if(gap == 7200)
           {
            datetime m = r[i - 1].time + 3600;
            MqlDateTime d; TimeToStruct(m, d);
            if(d.day_of_week >= 1 && d.day_of_week <= 5)
               miss[ns++] = m;
           }
        }
      if(ns < 5)
         return false;
      ArrayResize(miss, ns);
      //--- live reference offset (exact on a live terminal, meaningless in the tester)
      bool live = !(bool)MQLInfoInteger(MQL_TESTER) && !(bool)MQLInfoInteger(MQL_OPTIMIZATION);
      long liveOff = 0;
      bool haveLive = false;
      if(live)
        {
         datetime gmt = TimeGMT();
         datetime srvNow = TimeTradeServer();
         if(gmt > 0 && srvNow > 0)
           {
            liveOff = (long)MathRound((double)(srvNow - gmt) / 900.0) * 900;
            haveLive = true;
           }
        }
      int bestR = m_regime, bestK = m_k;
      double bestFit = -1.0;
      int regs[3] = {SW_CLOCK_NY, SW_CLOCK_EU, SW_CLOCK_FIXED};
      for(int ri = 0; ri < 3; ri++)
        {
         int reg = regs[ri];
         int k0 = (reg == SW_CLOCK_NY) ? 3 : -3;
         int k1 = (reg == SW_CLOCK_NY) ? 11 : 5;
         for(int k = k0; k <= k1; k++)
           {
            int hit = 0;
            for(int s = 0; s < ns; s++)
              {
               datetime nyl = UtcToNy(ToUtcModel(miss[s], reg, k));
               MqlDateTime d; TimeToStruct(nyl, d);
               if(d.hour == 17)
                  hit++;
              }
            double fit = (double)hit / ns;
            if(haveLive)
              {
               datetime srvNow = TimeTradeServer();
               long off = (long)(srvNow - ToUtcModel(srvNow, reg, k));
               if(off != liveOff)
                  fit -= 0.5;                                         // must also explain the live clock
              }
            // ties: keep the earlier (NY-locked first, then EU, then fixed) model
            if(fit > bestFit + 1e-9)
              {
               bestFit = fit; bestR = reg; bestK = k;
              }
           }
        }
      if(bestFit < 0.5 && haveLive)
        {
         // history inconclusive (exotic sessions) -> trust the live clock as a fixed offset
         bestR = SW_CLOCK_FIXED; bestK = (int)(liveOff / 3600); bestFit = 0.5;
        }
      m_regime = bestR; m_k = bestK; m_fit = bestFit; m_samples = ns;
      m_lastDetect = TimeCurrent();
      return bestFit >= 0.5;
     }

   datetime          LastDetect(void) const { return m_lastDetect; }
  };

#endif
