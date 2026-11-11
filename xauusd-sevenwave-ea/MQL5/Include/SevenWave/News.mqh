//+------------------------------------------------------------------+
//| News.mqh - SevenWave v1.32 key-release-day filter                  |
//|                                                                    |
//| On the UTC day of a key US release (NFP, CPI family, Core PCE,     |
//| GDP, Retail Sales, Fed rate decision) liquidity-pool breakouts     |
//| fake out: 2017-2026 setups on those days averaged -0.09R vs +0.37R |
//| on other days (python_pipeline/sw_study43.py / sw_study44.py).     |
//| No new first positions on those days; open trades keep running.   |
//| Days come from the embedded table (the tester has no calendar);   |
//| live, the terminal's MQL5 calendar is also asked by event id, so   |
//| future releases beyond the table are covered in any language.      |
//+------------------------------------------------------------------+
#ifndef SEVENWAVE_NEWS_MQH
#define SEVENWAVE_NEWS_MQH

#include "NewsDays.mqh"

class CSwNews
  {
public:
   int               m_cacheDay;
   bool              m_cacheVal;
   datetime          m_lastLive;

                     CSwNews(void) : m_cacheDay(-1), m_cacheVal(false), m_lastLive(0) {}

   static bool       InTable(int day)
     {
      int lo = 0, hi = SW_NEWS_NDAYS - 1;
      while(lo <= hi)
        {
         int mid = (lo + hi) / 2;
         if(SW_NEWS_DAYS[mid] == day) return true;
         if(SW_NEWS_DAYS[mid] < day) lo = mid + 1; else hi = mid - 1;
        }
      return false;
     }

   static bool       IsKeyId(ulong id)
     {
      for(int i = 0; i < SW_NEWS_NIDS; i++) if((ulong)SW_NEWS_IDS[i] == id) return true;
      return false;
     }

   //--- true on the UTC day of a key US release
   bool              IsKeyDay(datetime utcNow, datetime srvNow)
     {
      int day = (int)(utcNow / 86400);
      if(InTable(day)) return true;
      if(MQLInfoInteger(MQL_TESTER)) return false;
      if(day == m_cacheDay && srvNow - m_lastLive < 3600) return m_cacheVal;
      m_cacheDay = day; m_lastLive = srvNow; m_cacheVal = false;
      datetime from = (datetime)((long)day * 86400);          // calendar values are stamped in UTC (verified: NFP minute = 15x M1 range)
      MqlCalendarValue v[];
      int n = CalendarValueHistory(v, from, from + 86400, "US");
      for(int i = 0; i < n; i++)
         if(IsKeyId(v[i].event_id)) { m_cacheVal = true; break; }
      return m_cacheVal;
     }
  };

#endif
