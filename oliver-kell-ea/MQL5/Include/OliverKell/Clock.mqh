//+------------------------------------------------------------------+
//| Clock.mqh - OliverKell broker-clock model (no user timezone input|
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_CLOCK_MQH
#define OLIVERKELL_CLOCK_MQH

enum ENUM_OK_CLOCK { OK_CLOCK_NY = 0, OK_CLOCK_EU = 1, OK_CLOCK_FIXED = 2 };

class COkClock
  {
private:
   int      m_regime;
   int      m_k;
   double   m_fit;
   int      m_samples;
   datetime m_lastDetect;

   static datetime NthSunday(int year, int month, int n)
     {
      MqlDateTime d; ZeroMemory(d);
      d.year = year; d.mon = month; d.day = 1;
      datetime first = StructToTime(d);
      MqlDateTime f; TimeToStruct(first, f);
      int add = (7 - f.day_of_week) % 7;
      if(n > 0)
         return first + (datetime)((add + 7 * (n - 1)) * 86400);
      int ny = (month == 12) ? year + 1 : year;
      int nm = (month == 12) ? 1 : month + 1;
      return NthSunday(ny, nm, 1) - 7 * 86400;
     }

public:
                     COkClock(void) : m_regime(OK_CLOCK_NY), m_k(7), m_fit(0.0), m_samples(0), m_lastDetect(0) {}

   static bool       UsDst(datetime utc)
     {
      MqlDateTime d; TimeToStruct(utc, d);
      datetime st = NthSunday(d.year, 3, 2) + 7 * 3600;
      datetime en = NthSunday(d.year, 11, 1) + 6 * 3600;
      return (utc >= st && utc < en);
     }

   static bool       EuDst(datetime utc)
     {
      MqlDateTime d; TimeToStruct(utc, d);
      datetime st = NthSunday(d.year, 3, -1) + 3600;
      datetime en = NthSunday(d.year, 10, -1) + 3600;
      return (utc >= st && utc < en);
     }

   static datetime   ToUtcModel(datetime srv, int regime, int k)
     {
      if(regime == OK_CLOCK_NY)
        {
         datetime nyl = srv - (datetime)(k * 3600);
         datetime guess = nyl + 5 * 3600;
         return UsDst(guess) ? nyl + 4 * 3600 : guess;
        }
      if(regime == OK_CLOCK_EU)
        {
         datetime guess = srv - (datetime)(k * 3600);
         return EuDst(guess - 3600) ? guess - 3600 : guess;
        }
      return srv - (datetime)(k * 3600);
     }

   static datetime   UtcToNy(datetime utc) { return UsDst(utc) ? utc - 4 * 3600 : utc - 5 * 3600; }

   datetime          ToUtc(datetime srv) const { return ToUtcModel(srv, m_regime, m_k); }
   datetime          ToNy(datetime srv)  const { return UtcToNy(ToUtc(srv)); }
   long              TradingDayKey(datetime srv) const
     {
      datetime ny = ToNy(srv);
      long x = (long)ny - 17 * 3600;
      return (x >= 0) ? x / 86400 : -((-x + 86399) / 86400);
     }
   void              Init(int fallbackOffHours, bool autoOff, const string sym = "")
     {
      if(sym != "")
         Detect(sym);
     }
   void              RefreshOffset(datetime srvNow)
     {
      if(m_samples == 0 || (srvNow - m_lastDetect) > 86400 * 7)
         Detect(_Symbol);
     }
   string            Describe(void) const
     {
      string r = (m_regime == OK_CLOCK_NY) ? StringFormat("NY%+d", m_k) :
                 (m_regime == OK_CLOCK_EU) ? StringFormat("UTC%+d+EU-DST", m_k) : StringFormat("UTC%+d fixed", m_k);
      return StringFormat("%s (fit %.0f%% of %d daily breaks)", r, m_fit * 100.0, m_samples);
     }

   bool              Detect(const string sym)
     {
      MqlRates r[];
      ArraySetAsSeries(r, false);
      int n = CopyRates(sym, PERIOD_H1, 1, 24 * 260, r);
      if(n < 200)
         return false;
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
      int regs[3] = {OK_CLOCK_NY, OK_CLOCK_EU, OK_CLOCK_FIXED};
      for(int ri = 0; ri < 3; ri++)
        {
         int reg = regs[ri];
         int k0 = (reg == OK_CLOCK_NY) ? 3 : -3;
         int k1 = (reg == OK_CLOCK_NY) ? 11 : 5;
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
                  fit -= 0.5;
              }
            if(fit > bestFit + 1e-9)
              {
               bestFit = fit; bestR = reg; bestK = k;
              }
           }
        }
      if(bestFit < 0.5 && haveLive)
        {
         bestR = OK_CLOCK_FIXED; bestK = (int)(liveOff / 3600); bestFit = 0.5;
        }
      m_regime = bestR; m_k = bestK; m_fit = bestFit; m_samples = ns;
      m_lastDetect = TimeCurrent();
      return bestFit >= 0.5;
     }

   datetime          LastDetect(void) const { return m_lastDetect; }
  };

#endif
