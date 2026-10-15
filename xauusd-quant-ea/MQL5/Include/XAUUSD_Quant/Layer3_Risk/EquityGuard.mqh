//+------------------------------------------------------------------+
//|                                                  EquityGuard.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 3 Risk: OnTick Watchdog, HWM Tracker, News & Spread Guard |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_EQUITY_GUARD_MQH
#define XAUUSD_QUANT_EQUITY_GUARD_MQH

#include <Trade\Trade.mqh>
#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"

#define SPREAD_RING_BUFFER_SIZE          300
#define NEWS_CACHE_REFRESH_SECONDS       300

//+------------------------------------------------------------------+
//| Cached High-Impact USD Economic Calendar Event Window            |
//+------------------------------------------------------------------+
struct SUsdNewsEvent
  {
   datetime eventTimeUTC;
   string   eventName;
  };

//+------------------------------------------------------------------+
//| CEquityGuard: Institutional Drawdown & Microstructure Guard      |
//+------------------------------------------------------------------+
class CEquityGuard
  {
private:
   string             m_symbol;
   ulong              m_magic;
   ENUM_RISK_MODE     m_riskMode;
   ENUM_DD_TYPE       m_ddType;
   int                m_brokerGMTOffset;
   bool               m_enableCalendarFilter;
   double             m_maxSpreadMultiplier;
   double             m_hardMaxSpreadUSD;

   CQuantLogger      *m_logger;
   CTrade             m_emergencyTrade;

   //--- Core Equity & Drawdown State
   double             m_initialBalance;
   double             m_highWaterMark;
   double             m_dayStartReference;
   double             m_weekStartBalance;
   double             m_dailyRealizedPnLUSD;
   double             m_weeklyRealizedProfitUSD;
   double             m_dampenerPeakDrawdownPct;
   bool               m_growthDampenerActive;

   int                m_consecutiveLossesToday;
   bool               m_tradingHaltedToday;
   bool               m_permanentLockout;
   ENUM_BREACH_REASON m_activeBreachReason;

   int                m_lastResetYearDay;
   int                m_lastResetWeekId;

   //--- 5-Minute Rolling Spread Ring Buffer (1 sample per second, 300s window)
   double             m_spreadSamplesUSD[SPREAD_RING_BUFFER_SIZE];
   int                m_spreadSampleCount;
   int                m_spreadWriteIndex;
   datetime           m_lastSpreadSampleTime;
   double             m_currentSpreadUSD;
   double             m_rollingAvgSpreadUSD;

   //--- High-Impact USD News Cache
   SUsdNewsEvent      m_cachedNewsEvents[];
   datetime           m_lastNewsCacheUpdateUTC;
   string             m_activeNewsTitle;

   //--- GlobalVariable Key Builder for crash-resilient state persistence
   string             BuildGVKey(const string suffix) const
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      return StringFormat("XAUQ_%I64d_%I64u_%s", login, m_magic, suffix);
     }

   //--- Persist critical state to MT5 terminal GlobalVariables (live/demo only)
   void               SavePersistentState()
     {
      if((bool)MQLInfoInteger(MQL_TESTER))
         return;

      GlobalVariableSet(BuildGVKey("INIT_BAL"),    m_initialBalance);
      GlobalVariableSet(BuildGVKey("HWM"),         m_highWaterMark);
      GlobalVariableSet(BuildGVKey("DAY_REF"),     m_dayStartReference);
      GlobalVariableSet(BuildGVKey("WEEK_BAL"),    m_weekStartBalance);
      GlobalVariableSet(BuildGVKey("DAY_PNL"),     m_dailyRealizedPnLUSD);
      GlobalVariableSet(BuildGVKey("WEEK_PNL"),    m_weeklyRealizedProfitUSD);
      GlobalVariableSet(BuildGVKey("DAMP_PEAK"),   m_dampenerPeakDrawdownPct);
      GlobalVariableSet(BuildGVKey("DAMP_ACT"),    (m_growthDampenerActive ? 1.0 : 0.0));
      GlobalVariableSet(BuildGVKey("CONSEC_L"),    (double)m_consecutiveLossesToday);
      GlobalVariableSet(BuildGVKey("HALT_TODAY"),  (m_tradingHaltedToday ? 1.0 : 0.0));
      GlobalVariableSet(BuildGVKey("PERM_LOCK"),   (m_permanentLockout ? 1.0 : 0.0));
      GlobalVariableSet(BuildGVKey("LAST_YDAY"),   (double)m_lastResetYearDay);
      GlobalVariableSet(BuildGVKey("LAST_WKID"),   (double)m_lastResetWeekId);
     }

   //--- Restore persistent state if terminal restarted mid-session
   void               LoadPersistentState()
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double ref = MathMax(bal, eq);

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int currentYearDay = dt.year * 1000 + dt.day_of_year;
      int currentWeekId  = ComputeISOWeekId(TimeCurrent());

      if((bool)MQLInfoInteger(MQL_TESTER) || !GlobalVariableCheck(BuildGVKey("HWM")))
        {
         m_initialBalance          = bal;
         m_highWaterMark           = ref;
         m_dayStartReference       = ref;
         m_weekStartBalance        = bal;
         m_dailyRealizedPnLUSD     = 0.0;
         m_weeklyRealizedProfitUSD = 0.0;
         m_dampenerPeakDrawdownPct = 0.0;
         m_growthDampenerActive    = false;
         m_consecutiveLossesToday  = 0;
         m_tradingHaltedToday      = false;
         m_permanentLockout        = false;
         m_lastResetYearDay        = currentYearDay;
         m_lastResetWeekId         = currentWeekId;
         SavePersistentState();
         return;
        }

      m_initialBalance          = GlobalVariableGet(BuildGVKey("INIT_BAL"));
      m_highWaterMark           = MathMax(GlobalVariableGet(BuildGVKey("HWM")), ref);
      m_dayStartReference       = GlobalVariableGet(BuildGVKey("DAY_REF"));
      m_weekStartBalance        = GlobalVariableGet(BuildGVKey("WEEK_BAL"));
      m_dailyRealizedPnLUSD     = GlobalVariableGet(BuildGVKey("DAY_PNL"));
      m_weeklyRealizedProfitUSD = GlobalVariableGet(BuildGVKey("WEEK_PNL"));
      m_dampenerPeakDrawdownPct = GlobalVariableGet(BuildGVKey("DAMP_PEAK"));
      m_growthDampenerActive    = (GlobalVariableGet(BuildGVKey("DAMP_ACT")) > 0.5);
      m_consecutiveLossesToday  = (int)GlobalVariableGet(BuildGVKey("CONSEC_L"));
      m_tradingHaltedToday      = (GlobalVariableGet(BuildGVKey("HALT_TODAY")) > 0.5);
      m_permanentLockout        = (GlobalVariableGet(BuildGVKey("PERM_LOCK")) > 0.5);
      m_lastResetYearDay        = (int)GlobalVariableGet(BuildGVKey("LAST_YDAY"));
      m_lastResetWeekId         = (int)GlobalVariableGet(BuildGVKey("LAST_WKID"));

      if(m_initialBalance <= 0.0)
         m_initialBalance = bal;
      if(m_dayStartReference <= 0.0)
         m_dayStartReference = ref;
     }

   //--- Compute deterministic week identifier for weekly house-money tracking
   int                ComputeISOWeekId(const datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      int daysSinceEpoch = (int)(t / 86400);
      // 1970-01-01 was Thursday (day 4); shift so Monday starts a new week
      int weekIndex = (daysSinceEpoch + 3) / 7;
      return weekIndex;
     }

   //--- Emergency Liquidation: Close all open positions and delete all pending orders
   void               ExecuteEmergencyLiquidation(const ENUM_BREACH_REASON reason, const string detailMsg)
     {
      m_activeBreachReason = reason;
      m_tradingHaltedToday = true;
      if(reason == BREACH_MAX_TOTAL_DRAWDOWN)
         m_permanentLockout = true;

      // 1. Delete all pending orders for this symbol and magic
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong orderTicket = OrderGetTicket(i);
         if(orderTicket == 0)
            continue;
         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
           {
            m_emergencyTrade.OrderDelete(orderTicket);
           }
        }

      // 2. Immediately flatten any open position for this symbol and magic
      for(int attempt = 0; attempt < 3; attempt++)
        {
         bool anyOpen = false;
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong posTicket = PositionGetTicket(i);
            if(posTicket == 0)
               continue;
            if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
               (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
              {
               anyOpen = true;
               m_emergencyTrade.PositionClose(posTicket, 50);
              }
           }
         if(!anyOpen)
            break;
        }

      SavePersistentState();

      if(m_logger != NULL)
        {
         m_logger.Critical(StringFormat("EMERGENCY CIRCUIT BREAKER TRIPPED [%s]: %s",
                                        BreachReasonToString(reason), detailMsg));
         SRiskStateSnapshot snap;
         GetRiskStateSnapshot(snap);
         m_logger.WriteRiskStateCSV(snap, detailMsg);
        }
     }

   //--- Update 5-minute rolling spread ring buffer
   void               UpdateSpreadTelemetry()
     {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(ask <= 0.0 || bid <= 0.0 || ask < bid)
         return;

      m_currentSpreadUSD = ask - bid;

      datetime now = TimeCurrent();
      if(now != m_lastSpreadSampleTime)
        {
         m_lastSpreadSampleTime = now;
         m_spreadSamplesUSD[m_spreadWriteIndex] = m_currentSpreadUSD;
         m_spreadWriteIndex = (m_spreadWriteIndex + 1) % SPREAD_RING_BUFFER_SIZE;
         if(m_spreadSampleCount < SPREAD_RING_BUFFER_SIZE)
            m_spreadSampleCount++;
        }

      if(m_spreadSampleCount > 0)
        {
         double sum = 0.0;
         for(int i = 0; i < m_spreadSampleCount; i++)
            sum += m_spreadSamplesUSD[i];
         m_rollingAvgSpreadUSD = sum / (double)m_spreadSampleCount;
        }
      else
        {
         m_rollingAvgSpreadUSD = m_currentSpreadUSD;
        }
     }

   //--- Check if keyword matches high-impact USD macro catalysts
   bool               IsHighImpactMacroCatalyst(const string eventName) const
     {
      string upper = eventName;
      StringToUpper(upper);

      if(StringFind(upper, "CPI") >= 0 ||
         StringFind(upper, "CONSUMER PRICE") >= 0 ||
         StringFind(upper, "NONFARM") >= 0 ||
         StringFind(upper, "NON-FARM") >= 0 ||
         StringFind(upper, "PAYROLL") >= 0 ||
         StringFind(upper, "FOMC") >= 0 ||
         StringFind(upper, "FEDERAL FUNDS") >= 0 ||
         StringFind(upper, "INTEREST RATE") >= 0 ||
         StringFind(upper, "POWELL") >= 0 ||
         StringFind(upper, "FED CHAIR") >= 0 ||
         StringFind(upper, "PCE") >= 0 ||
         StringFind(upper, "UNEMPLOYMENT") >= 0 ||
         StringFind(upper, "RETAIL SALES") >= 0 ||
         StringFind(upper, "ISM") >= 0 ||
         StringFind(upper, "GDP") >= 0)
        {
         return true;
        }
      return true; // All CALENDAR_IMPORTANCE_HIGH USD events are treated with caution
     }

   //--- Refresh today's High-Impact USD Calendar Events from MQL5 Economic Calendar
   void               RefreshUsdCalendarCache(const datetime utcNow)
     {
      if(!m_enableCalendarFilter || (bool)MQLInfoInteger(MQL_TESTER))
         return;

      if(m_lastNewsCacheUpdateUTC > 0 && (utcNow - m_lastNewsCacheUpdateUTC) < NEWS_CACHE_REFRESH_SECONDS)
         return;

      m_lastNewsCacheUpdateUTC = utcNow;
      ArrayResize(m_cachedNewsEvents, 0);

      datetime serverNow  = TimeCurrent();
      datetime windowFrom = serverNow - 3600;
      datetime windowTo   = serverNow + 86400;

      MqlCalendarValue values[];
      ResetLastError();
      int count = CalendarValueHistory(values, windowFrom, windowTo, NULL, "USD");
      if(count <= 0)
         return;

      for(int i = 0; i < count; i++)
        {
         MqlCalendarEvent eventInfo;
         if(!CalendarEventById(values[i].event_id, eventInfo))
            continue;

         if(eventInfo.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;

         if(!IsHighImpactMacroCatalyst(eventInfo.name))
            continue;

         int idx = ArraySize(m_cachedNewsEvents);
         ArrayResize(m_cachedNewsEvents, idx + 1);
         m_cachedNewsEvents[idx].eventTimeUTC = ServerTimeToUTC(values[i].time, m_brokerGMTOffset);
         m_cachedNewsEvents[idx].eventName    = eventInfo.name;
        }
     }

   //--- Check for Daily (00:00 Server Time) and Weekly Rollovers
   void               CheckSessionResets()
     {
      datetime serverNow = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(serverNow, dt);

      int currentYearDay = dt.year * 1000 + dt.day_of_year;
      int currentWeekId  = ComputeISOWeekId(serverNow);

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

      // Weekly Reset (Monday 00:00 Server Time)
      if(currentWeekId != m_lastResetWeekId)
        {
         m_lastResetWeekId         = currentWeekId;
         m_weekStartBalance        = balance;
         m_weeklyRealizedProfitUSD = 0.0;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("Weekly House-Money Tracker Reset [WeekStartBalance=$%.2f]",
                                       m_weekStartBalance));
        }

      // Daily Reset (00:00 Server Time)
      if(currentYearDay != m_lastResetYearDay)
        {
         m_lastResetYearDay       = currentYearDay;
         m_dayStartReference      = MathMax(balance, equity);
         m_dailyRealizedPnLUSD    = 0.0;
         m_consecutiveLossesToday = 0;

         if(!m_permanentLockout)
           {
            m_tradingHaltedToday = false;
            m_activeBreachReason = BREACH_NONE;
           }

         SavePersistentState();

         if(m_logger != NULL)
           {
            m_logger.Info(StringFormat("Daily Risk Reference Reset at 00:00 Server Time [DayStartRef=$%.2f | HWM=$%.2f]",
                                       m_dayStartReference, m_highWaterMark));
            SRiskStateSnapshot snap;
            GetRiskStateSnapshot(snap);
            m_logger.WriteRiskStateCSV(snap, "DAILY_RESET_0000_SERVER");
           }
        }
     }

public:
                      CEquityGuard()
     {
      m_symbol                  = _Symbol;
      m_magic                   = QUANT_DEFAULT_MAGIC;
      m_riskMode                = MODE_PROP_GUARD;
      m_ddType                  = DD_TRAILING_HWM;
      m_brokerGMTOffset         = 2;
      m_enableCalendarFilter    = true;
      m_maxSpreadMultiplier     = 1.80;
      m_hardMaxSpreadUSD        = 0.80;
      m_logger                  = NULL;

      m_initialBalance          = 0.0;
      m_highWaterMark           = 0.0;
      m_dayStartReference       = 0.0;
      m_weekStartBalance        = 0.0;
      m_dailyRealizedPnLUSD     = 0.0;
      m_weeklyRealizedProfitUSD = 0.0;
      m_dampenerPeakDrawdownPct = 0.0;
      m_growthDampenerActive    = false;
      m_consecutiveLossesToday  = 0;
      m_tradingHaltedToday      = false;
      m_permanentLockout        = false;
      m_activeBreachReason      = BREACH_NONE;
      m_lastResetYearDay        = 0;
      m_lastResetWeekId         = 0;

      ArrayInitialize(m_spreadSamplesUSD, 0.0);
      m_spreadSampleCount       = 0;
      m_spreadWriteIndex        = 0;
      m_lastSpreadSampleTime    = 0;
      m_currentSpreadUSD        = 0.0;
      m_rollingAvgSpreadUSD     = 0.0;
      m_lastNewsCacheUpdateUTC  = 0;
      m_activeNewsTitle         = "";
     }

                     ~CEquityGuard() {}

   //--- Initialize Equity Guard
   bool               Init(const string symbol,
                           const ulong magic,
                           const ENUM_RISK_MODE riskMode,
                           const ENUM_DD_TYPE ddType,
                           const int brokerGMTOffsetHours,
                           const bool enableCalendarFilter,
                           const double maxSpreadMultiplier,
                           const double hardMaxSpreadUSD,
                           CQuantLogger *logger)
     {
      m_symbol               = symbol;
      m_magic                = magic;
      m_riskMode             = riskMode;
      m_ddType               = ddType;
      m_brokerGMTOffset      = brokerGMTOffsetHours;
      m_enableCalendarFilter = enableCalendarFilter;
      m_maxSpreadMultiplier  = (maxSpreadMultiplier > 1.0 ? maxSpreadMultiplier : 1.80);
      m_hardMaxSpreadUSD     = (hardMaxSpreadUSD > 0.10 ? hardMaxSpreadUSD : 0.80);
      m_logger               = logger;

      m_emergencyTrade.SetExpertMagicNumber(m_magic);
      m_emergencyTrade.SetDeviationInPoints(50);
      m_emergencyTrade.SetTypeFillingBySymbol(m_symbol);

      LoadPersistentState();
      UpdateSpreadTelemetry();

      if(m_logger != NULL)
        {
         m_logger.Info(StringFormat(
            "EquityGuard Initialized [Mode=%s | DDType=%s | DayStartRef=$%.2f | HWM=$%.2f | DailyBreaker=%.2f%% | MaxBreaker=%.2f%%]",
            RiskModeToString(m_riskMode),
            (m_ddType == DD_TRAILING_HWM ? "TRAILING_HWM" : "STATIC_INITIAL"),
            m_dayStartReference,
            m_highWaterMark,
            GetDailyBreakerLimitPct(),
            GetTotalBreakerLimitPct()));
        }
      return true;
     }

   //--- Daily Drawdown Breaker Limit (%) based on Mode
   double             GetDailyBreakerLimitPct() const
     {
      return (m_riskMode == MODE_PROP_GUARD)
             ? PROP_DAILY_DD_BREAKER_PCT
             : GROWTH_DAILY_DD_BREAKER_PCT;
     }

   //--- Max Total Drawdown Breaker Limit (%) based on Mode
   double             GetTotalBreakerLimitPct() const
     {
      return (m_riskMode == MODE_PROP_GUARD)
             ? PROP_TOTAL_DD_BREAKER_PCT
             : GROWTH_TOTAL_DD_BREAKER_PCT;
     }

   //--- Current Daily Drawdown Percentage against MathMax(DayStartBalance, DayStartEquity)
   double             GetCurrentDailyDrawdownPct() const
     {
      if(m_dayStartReference <= 0.0)
         return 0.0;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double ddUSD  = MathMax(0.0, m_dayStartReference - equity);
      return (ddUSD / m_dayStartReference) * 100.0;
     }

   //--- Remaining Daily Drawdown Capacity Percentage before internal breaker
   double             GetRemainingDailyDrawdownCapacityPct() const
     {
      double rem = GetDailyBreakerLimitPct() - GetCurrentDailyDrawdownPct();
      return MathMax(0.0, rem);
     }

   //--- Current Total Drawdown Percentage against HWM or Static Initial Balance
   double             GetCurrentTotalDrawdownPct() const
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double anchor = (m_ddType == DD_TRAILING_HWM || m_riskMode == MODE_ASYMMETRIC_GROWTH)
                      ? m_highWaterMark
                      : m_initialBalance;
      if(anchor <= 0.0)
         return 0.0;
      double ddUSD = MathMax(0.0, anchor - equity);
      return (ddUSD / anchor) * 100.0;
     }

   //--- Remaining Total Drawdown Capacity Percentage before internal breaker
   double             GetRemainingTotalDrawdownCapacityPct() const
     {
      double rem = GetTotalBreakerLimitPct() - GetCurrentTotalDrawdownPct();
      return MathMax(0.0, rem);
     }

   //--- Check whether any open position or pending order exists for this symbol and magic
   bool               HasAnyOwnBrokerExposure() const
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t > 0 && PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            return true;
        }
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(t > 0 && OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
            return true;
        }
      return false;
     }

   //+------------------------------------------------------------------+
   //| CheckEmergencyBreach                                             |
   //| Top-of-OnTick() Priority Watchdog. Must execute on every tick    |
   //| BEFORE any indicator, state machine, or execution logic.         |
   //| Returns true if an emergency breach or daily lock is active.     |
   //+------------------------------------------------------------------+
   bool               CheckEmergencyBreach()
     {
      // 1. Check 00:00 Server Time daily/weekly resets
      CheckSessionResets();

      // 2. Update spread telemetry ring buffer
      UpdateSpreadTelemetry();

      // 3. Fast exit if already halted/locked out and all positions/orders are flat
      if((m_permanentLockout || m_tradingHaltedToday) && !HasAnyOwnBrokerExposure())
         return true;

      // 4. Update Account High-Water Mark (track realized balance and flat equity peaks)
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double peakNow = (!HasAnyOwnBrokerExposure()) ? MathMax(balance, equity) : balance;

      if(peakNow > m_highWaterMark)
        {
         m_highWaterMark = peakNow;
         // High-Water Mark recovered -> clear dampener state
         m_dampenerPeakDrawdownPct = 0.0;
         m_growthDampenerActive    = false;
         SavePersistentState();
        }

      // 5. Maintain Growth Mode Drawdown Dampener state (clamps risk to 0.50% if DD > 3.0% until half recovered)
      double currentTotalDDPct = GetCurrentTotalDrawdownPct();
      if(m_riskMode == MODE_ASYMMETRIC_GROWTH)
        {
         if(currentTotalDDPct >= GROWTH_DD_DAMPENER_TRIGGER_PCT)
           {
            m_growthDampenerActive = true;
            if(currentTotalDDPct > m_dampenerPeakDrawdownPct)
               m_dampenerPeakDrawdownPct = currentTotalDDPct;
           }
         else if(m_growthDampenerActive)
           {
            // Recover once current drawdown drops to or below 50% of the peak drawdown experienced
            if(currentTotalDDPct <= (0.50 * m_dampenerPeakDrawdownPct))
              {
               m_growthDampenerActive    = false;
               m_dampenerPeakDrawdownPct = 0.0;
               SavePersistentState();
              }
           }
        }

      // 6. Evaluate Hard Daily Drawdown Breaker (2.25% Prop / 2.40% Growth)
      double currentDailyDDPct = GetCurrentDailyDrawdownPct();
      double dailyLimitPct     = GetDailyBreakerLimitPct();
      if(currentDailyDDPct >= dailyLimitPct)
        {
         string msg = StringFormat(
            "Floating Equity ($%.2f) breached Daily Drawdown Breaker (%.2f%% >= %.2f%% of DayStartRef $%.2f)",
            equity, currentDailyDDPct, dailyLimitPct, m_dayStartReference);
         ExecuteEmergencyLiquidation(BREACH_DAILY_DRAWDOWN, msg);
         return true;
        }

      // 7. Evaluate Hard Max Total Drawdown Breaker (5.20% Prop / 5.40% Growth)
      double totalLimitPct = GetTotalBreakerLimitPct();
      if(currentTotalDDPct >= totalLimitPct)
        {
         double anchor = (m_ddType == DD_TRAILING_HWM || m_riskMode == MODE_ASYMMETRIC_GROWTH)
                         ? m_highWaterMark
                         : m_initialBalance;
         string msg = StringFormat(
            "Floating Equity ($%.2f) breached Max Total Drawdown Breaker (%.2f%% >= %.2f%% of Reference $%.2f)",
            equity, currentTotalDDPct, totalLimitPct, anchor);
         ExecuteEmergencyLiquidation(BREACH_MAX_TOTAL_DRAWDOWN, msg);
         return true;
        }

      if(m_permanentLockout || m_tradingHaltedToday)
         return true;

      return false;
     }

   //+------------------------------------------------------------------+
   //| OnClosedTradeResult                                              |
   //| Updates realized PnL, consecutive losses, weekly house-money     |
   //| buffer, and triggers Prop Mode daily circuit breakers.           |
   //+------------------------------------------------------------------+
   void               OnClosedTradeResult(const double netRealizedPnLUSD)
     {
      m_dailyRealizedPnLUSD     += netRealizedPnLUSD;
      m_weeklyRealizedProfitUSD += netRealizedPnLUSD;

      double scratchFloorUSD = (m_dayStartReference > 0.0 ? m_dayStartReference * 0.0015 : 5.0);
      if(netRealizedPnLUSD < -scratchFloorUSD)
         m_consecutiveLossesToday++;
      else if(netRealizedPnLUSD > scratchFloorUSD)
         m_consecutiveLossesToday = 0;

      // Update High-Water Mark after realized balance change
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(MathMax(bal, eq) > m_highWaterMark)
         m_highWaterMark = MathMax(bal, eq);

      // Mode A (MODE_PROP_GUARD) Daily Circuit Breakers:
      // 1) Lock trading until next day after 2 consecutive losses
      // 2) Lock trading until next day once daily realized profit exceeds +2.0%
      if(m_riskMode == MODE_PROP_GUARD && m_dayStartReference > 0.0)
        {
         double dailyRealizedPct = (m_dailyRealizedPnLUSD / m_dayStartReference) * 100.0;

         if(m_consecutiveLossesToday >= PROP_MAX_CONSECUTIVE_LOSSES)
           {
            m_tradingHaltedToday = true;
            m_activeBreachReason = BREACH_CONSECUTIVE_LOSSES;
            if(m_logger != NULL)
              {
               string note = StringFormat("Prop Guard Daily Lock: %d consecutive losses reached today.",
                                          m_consecutiveLossesToday);
               m_logger.Warn(note);
               SRiskStateSnapshot snap;
               GetRiskStateSnapshot(snap);
               m_logger.WriteRiskStateCSV(snap, note);
              }
           }
         else if(dailyRealizedPct >= PROP_DAILY_PROFIT_LOCK_PCT)
           {
            m_tradingHaltedToday = true;
            m_activeBreachReason = BREACH_DAILY_PROFIT_TARGET;
            if(m_logger != NULL)
              {
               string note = StringFormat("Prop Guard Daily Profit Lock: Realized +%.2f%% ($%.2f) >= +%.2f%% target.",
                                          dailyRealizedPct, m_dailyRealizedPnLUSD, PROP_DAILY_PROFIT_LOCK_PCT);
               m_logger.Info(note);
               SRiskStateSnapshot snap;
               GetRiskStateSnapshot(snap);
               m_logger.WriteRiskStateCSV(snap, note);
              }
           }
        }

      SavePersistentState();
     }

   //+------------------------------------------------------------------+
   //| IsRolloverBlackoutUTC                                            |
   //| Blocks trading and pending orders between 20:55 and 22:10 UTC    |
   //+------------------------------------------------------------------+
   bool               IsRolloverBlackoutUTC(const datetime utcNow) const
     {
      MqlDateTime dt;
      TimeToStruct(utcNow, dt);
      int minuteOfDay = dt.hour * 60 + dt.min;

      // 20:55 UTC = 1255 minutes; 22:10 UTC = 1330 minutes
      const int rolloverStartMin = 20 * 60 + 55;
      const int rolloverEndMin   = 22 * 60 + 10;

      return (minuteOfDay >= rolloverStartMin && minuteOfDay <= rolloverEndMin);
     }

   //+------------------------------------------------------------------+
   //| IsHighImpactNewsWindowUTC                                        |
   //| Blocks trading within +/- 15 minutes of High-Impact USD Events   |
   //+------------------------------------------------------------------+
   bool               IsHighImpactNewsWindowUTC(const datetime utcNow, string &outEventName)
     {
      outEventName = "";
      if(!m_enableCalendarFilter || (bool)MQLInfoInteger(MQL_TESTER))
         return false;

      RefreshUsdCalendarCache(utcNow);

      int total = ArraySize(m_cachedNewsEvents);
      for(int i = 0; i < total; i++)
        {
         long diffSeconds = MathAbs((long)(utcNow - m_cachedNewsEvents[i].eventTimeUTC));
         if(diffSeconds <= 15 * 60) // +/- 15 minutes (900 seconds)
           {
            outEventName = m_cachedNewsEvents[i].eventName;
            return true;
           }
        }
      return false;
     }

   //+------------------------------------------------------------------+
   //| IsSpreadDislocated                                               |
   //| Blocks entries when currentSpread > 1.8 * RollingAverageSpread   |
   //+------------------------------------------------------------------+
   bool               IsSpreadDislocated() const
     {
      if(m_currentSpreadUSD <= 0.0)
         return true;
      if(m_currentSpreadUSD > m_hardMaxSpreadUSD)
         return true;

      // Apply a realistic baseline floor ($0.12) so 1-tick tight spreads don't false-trigger at $0.18
      double baselineAvg = MathMax(m_rollingAvgSpreadUSD, 0.12);
      if(m_spreadSampleCount >= 10 && m_currentSpreadUSD > (m_maxSpreadMultiplier * baselineAvg))
         return true;

      return false;
     }

   //+------------------------------------------------------------------+
   //| IsNewEntryPermitted                                              |
   //| Comprehensive gate for new entries and pending order persistence |
   //+------------------------------------------------------------------+
   bool               IsNewEntryPermitted(ENUM_BREACH_REASON &outBlockReason)
     {
      outBlockReason = BREACH_NONE;

      if(m_permanentLockout)
        {
         outBlockReason = BREACH_MAX_TOTAL_DRAWDOWN;
         return false;
        }

      if(m_tradingHaltedToday)
        {
         outBlockReason = (m_activeBreachReason != BREACH_NONE)
                          ? m_activeBreachReason
                          : BREACH_DAILY_DRAWDOWN;
         return false;
        }

      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);

      // 1. Check Rollover Blackout (20:55 - 22:10 UTC)
      if(IsRolloverBlackoutUTC(utcNow))
        {
         outBlockReason = BREACH_ROLLOVER_WINDOW;
         return false;
        }

      // 2. Check High-Impact USD Calendar Window (+/- 15 minutes)
      string newsTitle = "";
      if(IsHighImpactNewsWindowUTC(utcNow, newsTitle))
        {
         m_activeNewsTitle = newsTitle;
         outBlockReason    = BREACH_HIGH_IMPACT_NEWS;
         return false;
        }
      m_activeNewsTitle = "";

      // 3. Check 1.8x 5-Minute Rolling Average Spread Guard
      if(IsSpreadDislocated())
        {
         outBlockReason = BREACH_SPREAD_WIDENING;
         return false;
        }

      return true;
     }

   //---Determine whether Drawdown Dampener is currently active
   bool               IsDrawdownDampenerActive() const
     {
      if(m_riskMode == MODE_PROP_GUARD)
        {
         // Prop Guard: If current drawdown from HWM exceeds 2.50%, multiply risk % by 0.50 until HWM recovered
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         if(m_highWaterMark <= 0.0)
            return false;
         double hwmDDPct = (MathMax(0.0, m_highWaterMark - equity) / m_highWaterMark) * 100.0;
         return (hwmDDPct > PROP_DD_DAMPENER_TRIGGER_PCT);
        }
      else
        {
         // Asymmetric Growth: If trailing drawdown exceeds 3.00%, clamp risk to 0.50% until half recovered
         return m_growthDampenerActive;
        }
     }

   //--- Accessors for PositionSizer & Telemetry
   ENUM_RISK_MODE     GetRiskMode()                const { return m_riskMode;                  }
   ENUM_DD_TYPE       GetDDType()                  const { return m_ddType;                    }
   double             GetInitialBalance()          const { return m_initialBalance;            }
   double             GetHighWaterMark()           const { return m_highWaterMark;             }
   double             GetDayStartReference()       const { return m_dayStartReference;         }
   double             GetDailyRealizedPnLUSD()     const { return m_dailyRealizedPnLUSD;       }
   double             GetWeeklyRealizedProfitUSD() const { return m_weeklyRealizedProfitUSD;   }
   int                GetConsecutiveLossesToday()  const { return m_consecutiveLossesToday;    }
   bool               IsTradingHaltedToday()       const { return m_tradingHaltedToday;        }
   bool               IsPermanentLockout()         const { return m_permanentLockout;          }
   double             GetCurrentSpreadUSD()        const { return m_currentSpreadUSD;          }
   double             GetRollingAvgSpreadUSD()     const { return m_rollingAvgSpreadUSD;       }

   //--- Populate complete SRiskStateSnapshot struct
   void               GetRiskStateSnapshot(SRiskStateSnapshot &outSnap)
     {
      outSnap.Reset();
      double bal    = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq     = AccountInfoDouble(ACCOUNT_EQUITY);
      datetime utc  = ResolveCurrentUTCTime(m_brokerGMTOffset);
      string news   = "";
      bool isNews   = IsHighImpactNewsWindowUTC(utc, news);

      outSnap.riskMode                  = m_riskMode;
      outSnap.ddType                    = m_ddType;
      outSnap.initialBalance            = m_initialBalance;
      outSnap.highWaterMark             = m_highWaterMark;
      outSnap.dayStartReference         = m_dayStartReference;
      outSnap.weekStartBalance          = m_weekStartBalance;
      outSnap.currentBalance            = bal;
      outSnap.currentEquity             = eq;
      outSnap.dailyDrawdownUSD          = MathMax(0.0, m_dayStartReference - eq);
      outSnap.dailyDrawdownPct          = GetCurrentDailyDrawdownPct();
      outSnap.dailyBreakerLimitPct      = GetDailyBreakerLimitPct();
      double totalAnchor                = (m_ddType == DD_TRAILING_HWM || m_riskMode == MODE_ASYMMETRIC_GROWTH)
                                          ? m_highWaterMark : m_initialBalance;
      outSnap.totalDrawdownUSD          = MathMax(0.0, totalAnchor - eq);
      outSnap.totalDrawdownPct          = GetCurrentTotalDrawdownPct();
      outSnap.totalBreakerLimitPct      = GetTotalBreakerLimitPct();
      outSnap.dailyRealizedPnLUSD       = m_dailyRealizedPnLUSD;
      outSnap.dailyRealizedPnLPct       = (m_dayStartReference > 0.0)
                                          ? (m_dailyRealizedPnLUSD / m_dayStartReference) * 100.0 : 0.0;
      outSnap.weeklyRealizedProfitUSD   = m_weeklyRealizedProfitUSD;
      outSnap.recoveryAnchorDrawdownPct = m_dampenerPeakDrawdownPct;
      outSnap.consecutiveLossesToday    = m_consecutiveLossesToday;
      outSnap.tradingHaltedToday        = m_tradingHaltedToday;
      outSnap.permanentLockout          = m_permanentLockout;
      outSnap.activeBreachReason        = m_activeBreachReason;
      outSnap.currentSpreadUSD          = m_currentSpreadUSD;
      outSnap.rollingAvgSpreadUSD       = m_rollingAvgSpreadUSD;
      outSnap.spreadGuardTripped        = IsSpreadDislocated();
      outSnap.newsWindowBlocked         = isNews;
      outSnap.rolloverWindowBlocked     = IsRolloverBlackoutUTC(utc);
      outSnap.activeNewsEventTitle      = news;
     }
  };

#endif // XAUUSD_QUANT_EQUITY_GUARD_MQH
