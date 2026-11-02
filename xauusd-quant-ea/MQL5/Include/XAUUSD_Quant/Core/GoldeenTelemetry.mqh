//+------------------------------------------------------------------+
//|                                             GoldeenTelemetry.mqh |
//|                     Goldeen.io Instant Redis Telemetry Reporter  |
//|      Zero-Tick-Latency Timer-Driven Heartbeat & Trade Sync       |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property strict

#ifndef GOLDEEN_TELEMETRY_MQH
#define GOLDEEN_TELEMETRY_MQH

class CGoldeenTelemetry
  {
private:
   string            m_token;
   string            m_endpointUrl;
   string            m_eaName;
   string            m_eaVersion;
   string            m_eaType;
   string            m_symbol;
   ulong             m_magicMin;
   ulong             m_magicMax;
   bool              m_enabled;
   bool              m_forceReport;
   bool              m_initialHistorySent;
   datetime          m_lastReportTime;
   datetime          m_lastHistorySyncTime;
   bool              m_warnedWebRequest;

   string EscapeJson(const string raw) const
     {
      string out = raw;
      StringReplace(out, "\\", "\\\\");
      StringReplace(out, "\"", "\\\"");
      StringReplace(out, "\r", " ");
      StringReplace(out, "\n", " ");
      StringReplace(out, "\t", " ");
      return out;
     }

   bool IsMagicMatch(const ulong magic) const
     {
      return (magic >= m_magicMin && magic <= m_magicMax);
     }

public:
                     CGoldeenTelemetry()
     {
      m_token              = "";
      m_endpointUrl        = "https://api.goldeen.io/api/v1/ea/report";
      m_eaName             = "";
      m_eaVersion          = "";
      m_eaType             = "";
      m_symbol             = "";
      m_magicMin           = 0;
      m_magicMax           = 0;
      m_enabled            = false;
      m_forceReport        = false;
      m_initialHistorySent = false;
      m_lastReportTime     = 0;
      m_lastHistorySyncTime = 0;
      m_warnedWebRequest   = false;
     }

   void Init(const string token,
             const string endpointUrl,
             const string eaName,
             const string eaVersion,
             const string eaType,
             const string symbol,
             const ulong  magicMin,
             const ulong  magicMax)
     {
      m_token = token;
      StringTrimLeft(m_token);
      StringTrimRight(m_token);

      m_endpointUrl = endpointUrl;
      StringTrimLeft(m_endpointUrl);
      StringTrimRight(m_endpointUrl);
      if(m_endpointUrl == "")
         m_endpointUrl = "https://api.goldeen.io/api/v1/ea/report";

      m_eaName    = eaName;
      m_eaVersion = eaVersion;
      m_eaType    = eaType;
      m_symbol    = symbol;
      m_magicMin  = magicMin;
      m_magicMax  = magicMax;

      if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION) || m_token == "")
        {
         m_enabled = false;
         return;
        }

      m_enabled            = true;
      m_forceReport        = true;
      m_initialHistorySent = false;
      m_lastReportTime     = 0;
      m_lastHistorySyncTime = 0;
      m_warnedWebRequest   = false;
     }

   bool IsEnabled() const { return m_enabled; }

   void RequestImmediateReport()
     {
      if(m_enabled)
         m_forceReport = true;
     }

   void OnTradeTransactionWatch(const MqlTradeTransaction &trans)
     {
      if(!m_enabled)
         return;
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
         trans.type == TRADE_TRANSACTION_ORDER_ADD ||
         trans.type == TRADE_TRANSACTION_ORDER_DELETE)
        {
         m_forceReport = true;
        }
     }

   void OnTimerCheck(const double initialBalance,
                     const double dailyPnL,
                     const double dailyPnLPct,
                     const double dailyDDPct,
                     const double maxDailyDDLimitPct,
                     const double totalDDPct,
                     const double maxTotalDDLimitPct,
                     const string lastAiDecision,
                     const string statusMessage)
     {
      if(!m_enabled)
         return;

      datetime now = TimeCurrent();
      if(!m_forceReport && (now - m_lastReportTime) < 60)
         return;

      m_forceReport    = false;
      m_lastReportTime = now;

      SendSnapshot(initialBalance,
                   dailyPnL,
                   dailyPnLPct,
                   dailyDDPct,
                   maxDailyDDLimitPct,
                   totalDDPct,
                   maxTotalDDLimitPct,
                   lastAiDecision,
                   statusMessage);
     }

private:
   void SendSnapshot(const double initialBalance,
                     const double dailyPnL,
                     const double dailyPnLPct,
                     const double dailyDDPct,
                     const double maxDailyDDLimitPct,
                     const double totalDDPct,
                     const double maxTotalDDLimitPct,
                     const string lastAiDecision,
                     const string statusMessage)
     {
      if(!m_enabled)
         return;

      string broker        = EscapeJson(AccountInfoString(ACCOUNT_COMPANY));
      long   accountLogin  = AccountInfoInteger(ACCOUNT_LOGIN);
      string accountServer = EscapeJson(AccountInfoString(ACCOUNT_SERVER));
      string currency      = EscapeJson(AccountInfoString(ACCOUNT_CURRENCY));
      double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity        = AccountInfoDouble(ACCOUNT_EQUITY);
      double freeMargin    = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      int    digits        = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      if(digits <= 0)
         digits = 2;

      // 1. Collect Open Positions for this EA
      double floatingPnL = 0.0;
      string openJson    = "[";
      bool   firstOpen   = true;

      int totalPos = PositionsTotal();
      for(int i = 0; i < totalPos; i++)
        {
         ulong posTicket = PositionGetTicket(i);
         if(posTicket == 0 || !PositionSelectByTicket(posTicket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
         if(!IsMagicMatch(magic))
            continue;

         ENUM_POSITION_TYPE pType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         string side    = (pType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         double vol     = PositionGetDouble(POSITION_VOLUME);
         double openPx  = PositionGetDouble(POSITION_PRICE_OPEN);
         double curPx   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double sl      = PositionGetDouble(POSITION_SL);
         double tp      = PositionGetDouble(POSITION_TP);
         double profit  = PositionGetDouble(POSITION_PROFIT);
         double swap    = PositionGetDouble(POSITION_SWAP);
         datetime oTime = (datetime)PositionGetInteger(POSITION_TIME);
         string comment = EscapeJson(PositionGetString(POSITION_COMMENT));

         floatingPnL += (profit + swap);

         if(!firstOpen)
            openJson += ",";
         firstOpen = false;

         openJson += StringFormat(
            "{\"ticket\":%I64u,\"symbol\":\"%s\",\"side\":\"%s\",\"volume\":%.2f,"
            "\"open_price\":%.*f,\"current_price\":%.*f,\"sl\":%.*f,\"tp\":%.*f,"
            "\"profit\":%.2f,\"swap\":%.2f,\"commission\":0.00,"
            "\"open_time\":\"%s\",\"comment\":\"%s\"}",
            posTicket,
            EscapeJson(m_symbol),
            side,
            vol,
            digits, openPx,
            digits, curPx,
            digits, sl,
            digits, tp,
            profit,
            swap,
            TimeToString(oTime, TIME_DATE|TIME_SECONDS),
            comment
         );
        }
      openJson += "]";

      // 2. Collect Closed Deals for this EA
      string   closedJson  = "[";
      bool     firstClosed = true;
      datetime fromTime    = m_initialHistorySent ? (m_lastHistorySyncTime - 600) : 0;
      datetime toTime      = TimeCurrent() + 86400;

      if(HistorySelect(fromTime, toTime))
        {
         int totalDeals = HistoryDealsTotal();
         int maxCollect = m_initialHistorySent ? 25 : 60;
         int collected  = 0;

         for(int i = totalDeals - 1; i >= 0 && collected < maxCollect; i--)
           {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0)
               continue;
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != m_symbol)
               continue;
            ulong magic = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(!IsMagicMatch(magic))
               continue;

            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
               continue;

            ENUM_DEAL_TYPE dType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            if(dType != DEAL_TYPE_BUY && dType != DEAL_TYPE_SELL)
               continue;

            // An exit BUY deal closed a SELL position; an exit SELL deal closed a BUY position
            string side       = (dType == DEAL_TYPE_SELL) ? "BUY" : "SELL";
            long   posId      = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
            double vol        = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            double closePx    = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double openPx     = closePx;
            double sl         = HistoryDealGetDouble(dealTicket, DEAL_SL);
            double tp         = HistoryDealGetDouble(dealTicket, DEAL_TP);
            double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double comm       = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double fee        = HistoryDealGetDouble(dealTicket, DEAL_FEE);
            double totalComm  = comm + fee;
            double netPnL     = profit + swap + totalComm;
            datetime closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            datetime openTime  = closeTime;
            string comment     = EscapeJson(HistoryDealGetString(dealTicket, DEAL_COMMENT));

            // Scan backward for the opening DEAL_ENTRY_IN of this position to get true open price & time
            for(int j = i - 1; j >= 0 && (i - j) < 500; j--)
              {
               ulong inTicket = HistoryDealGetTicket(j);
               if(inTicket == 0)
                  continue;
               if(HistoryDealGetInteger(inTicket, DEAL_POSITION_ID) == posId &&
                  (ENUM_DEAL_ENTRY)HistoryDealGetInteger(inTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                 {
                  openPx    = HistoryDealGetDouble(inTicket, DEAL_PRICE);
                  openTime  = (datetime)HistoryDealGetInteger(inTicket, DEAL_TIME);
                  totalComm += HistoryDealGetDouble(inTicket, DEAL_COMMISSION) + HistoryDealGetDouble(inTicket, DEAL_FEE);
                  netPnL    = profit + swap + totalComm;
                  break;
                 }
              }

            if(!firstClosed)
               closedJson += ",";
            firstClosed = false;

            closedJson += StringFormat(
               "{\"ticket\":%I64u,\"position_id\":%I64d,\"symbol\":\"%s\",\"side\":\"%s\","
               "\"volume\":%.2f,\"open_price\":%.*f,\"close_price\":%.*f,\"sl\":%.*f,\"tp\":%.*f,"
               "\"profit\":%.2f,\"swap\":%.2f,\"commission\":%.2f,\"net_pnl\":%.2f,"
               "\"open_time\":\"%s\",\"close_time\":\"%s\",\"comment\":\"%s\"}",
               dealTicket,
               posId,
               EscapeJson(m_symbol),
               side,
               vol,
               digits, openPx,
               digits, closePx,
               digits, sl,
               digits, tp,
               profit,
               swap,
               totalComm,
               netPnL,
               TimeToString(openTime, TIME_DATE|TIME_SECONDS),
               TimeToString(closeTime, TIME_DATE|TIME_SECONDS),
               comment
            );
            collected++;
           }
        }
      closedJson += "]";

      // 3. Build Master Telemetry JSON Payload
      double initBal = (initialBalance > 0.0) ? initialBalance : balance;
      string jsonPayload = StringFormat(
         "{\"token\":\"%s\",\"broker\":\"%s\",\"account_login\":%I64d,\"account_server\":\"%s\","
         "\"currency\":\"%s\",\"symbol\":\"%s\",\"ea_name\":\"%s\",\"ea_version\":\"%s\","
         "\"ea_type\":\"%s\",\"magic_number\":%I64u,\"initial_balance\":%.2f,\"balance\":%.2f,"
         "\"equity\":%.2f,\"free_margin\":%.2f,\"floating_pnl\":%.2f,\"daily_pnl\":%.2f,"
         "\"daily_pnl_pct\":%.4f,\"daily_drawdown_pct\":%.4f,\"max_daily_drawdown_limit_pct\":%.2f,"
         "\"total_drawdown_pct\":%.4f,\"max_total_drawdown_limit_pct\":%.2f,"
         "\"last_ai_decision\":\"%s\",\"status_message\":\"%s\","
         "\"open_positions\":%s,\"closed_trades\":%s}",
         EscapeJson(m_token),
         broker,
         accountLogin,
         accountServer,
         currency,
         EscapeJson(m_symbol),
         EscapeJson(m_eaName),
         EscapeJson(m_eaVersion),
         EscapeJson(m_eaType),
         m_magicMin,
         initBal,
         balance,
         equity,
         freeMargin,
         floatingPnL,
         dailyPnL,
         dailyPnLPct,
         dailyDDPct,
         maxDailyDDLimitPct,
         totalDDPct,
         maxTotalDDLimitPct,
         EscapeJson(lastAiDecision),
         EscapeJson(statusMessage),
         openJson,
         closedJson
      );

      char   postData[];
      char   resultData[];
      string resultHeaders;
      string headers = "Content-Type: application/json\r\nX-EA-Token: " + m_token + "\r\n";

      int len = StringToCharArray(jsonPayload, postData, 0, WHOLE_ARRAY, CP_UTF8);
      if(len > 0)
         ArrayResize(postData, len - 1); // Strip trailing null byte

      ResetLastError();
      int res = WebRequest("POST", m_endpointUrl, headers, 1200, postData, resultData, resultHeaders);
      if(res == 200 || res == 201 || res == 202)
        {
         m_initialHistorySent  = true;
         m_lastHistorySyncTime = TimeCurrent();
        }
      else if(!m_warnedWebRequest)
        {
         m_warnedWebRequest = true;
         PrintFormat("[GOLDEEN-TELEMETRY] WebRequest status=%d err=%d. Ensure %s is added under Tools -> Options -> Expert Advisors -> Allow WebRequest.",
                     res, GetLastError(), m_endpointUrl);
        }
     }
  };

#endif // GOLDEEN_TELEMETRY_MQH
