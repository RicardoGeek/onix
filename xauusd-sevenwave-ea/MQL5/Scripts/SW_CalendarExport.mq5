//+------------------------------------------------------------------+
//| SW_CalendarExport.mq5 - read-only export of the MQL5 economic      |
//| calendar (US, moderate + high importance) to Common\Files for the |
//| SevenWave research pipeline.  Trades nothing.                     |
//+------------------------------------------------------------------+
#property script_show_inputs false

void OnStart()
  {
   MqlCalendarValue v[];
   datetime from = D'2016.12.01';
   datetime to = TimeCurrent() + 45 * 86400;
   int n = CalendarValueHistory(v, from, to, "US");
   if(n <= 0)
     {
      PrintFormat("SW_CalendarExport: no values (%d), error %d", n, GetLastError());
      return;
     }
   int fh = FileOpen("sw_calendar_us.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("SW_CalendarExport: cannot open file, error %d", GetLastError());
      return;
     }
   FileWrite(fh, "time_srv", "event_id", "event", "importance", "actual", "forecast", "prev", "revised_prev", "impact", "unit", "multiplier");
   int written = 0;
   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(v[i].event_id, ev))
         continue;
      if(ev.importance < CALENDAR_IMPORTANCE_MODERATE)
         continue;
      string a = v[i].HasActualValue() ? DoubleToString(v[i].GetActualValue(), 6) : "";
      string f = v[i].HasForecastValue() ? DoubleToString(v[i].GetForecastValue(), 6) : "";
      string p = v[i].HasPreviousValue() ? DoubleToString(v[i].GetPreviousValue(), 6) : "";
      string r = v[i].HasRevisedValue() ? DoubleToString(v[i].GetRevisedValue(), 6) : "";
      string nm = ev.name;
      StringReplace(nm, ",", " ");
      FileWrite(fh, (long)v[i].time, (long)v[i].event_id, nm, (int)ev.importance, a, f, p, r, (int)v[i].impact_type, (int)ev.unit, (int)ev.multiplier);
      written++;
     }
   FileClose(fh);
   PrintFormat("SW_CalendarExport: %d values, %d moderate/high US events written to Common\\Files\\sw_calendar_us.csv", n, written);
  }
//+------------------------------------------------------------------+
