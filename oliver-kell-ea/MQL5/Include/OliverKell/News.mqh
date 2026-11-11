//+------------------------------------------------------------------+
//| News.mqh - OliverKell optional key-release-day filter            |
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_NEWS_MQH
#define OLIVERKELL_NEWS_MQH

#include "NewsDays.mqh"

class COkNews
  {
public:
   int               m_cacheDay;
   bool              m_cacheVal;
   datetime          m_lastLive;

                     COkNews(void) : m_cacheDay(-1), m_cacheVal(false), m_lastLive(0) {}

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
      for(int i = 0; i < SW_NEWS_NIDS; i++)
         if((ulong)SW_NEWS_IDS[i] == id) return true;
      return false;
     }

   bool              IsKeyDay(datetime utcNow, datetime srvNow)
     {
      int day = (int)(utcNow / 86400);
      if(InTable(day)) return true;
      if(MQLInfoInteger(MQL_TESTER)) return false;
      if(day == m_cacheDay && srvNow - m_lastLive < 3600) return m_cacheVal;
      m_cacheDay = day; m_lastLive = srvNow; m_cacheVal = false;
      datetime from = (datetime)((long)day * 86400);
      MqlCalendarValue v[];
      int n = CalendarValueHistory(v, from, from + 86400, "US");
      for(int i = 0; i < n; i++)
         if(IsKeyId(v[i].event_id)) { m_cacheVal = true; break; }
      return m_cacheVal;
     }
  };

#endif
