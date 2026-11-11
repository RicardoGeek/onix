//+------------------------------------------------------------------+
//| RiskEngine.mqh - OliverKell v1.00 Prop & Growth Moonshot Risk    |
//|                                                                  |
//| Modes:                                                           |
//|  * OK_PROP_FIRM:                                                 |
//|      <3.0% daily DD (2.45% emergency liquidator), <6.0% total DD |
//|      (5.35% emergency liquidator), 0.15 room fraction, +2.4%     |
//|      daily consistency lock, 3 slots (2 reserved for HTF).       |
//|  * OK_GROWTH_MOONSHOT:                                           |
//|      Full geometric equity compounding (1.35% base / 2.75% cap), |
//|      50% daily room share, 25% Kelly-safe trailing room share    |
//|      above 28% HWM floor (immune to HWM drawdown lockout),       |
//|      2-Stage Scale-In Pyramid (+1.50R & +2.75R) with 7.0R        |
//|      Exhaustion Extension Target and >50 lot multi-ticket split. |
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_RISKENGINE_MQH
#define OLIVERKELL_RISKENGINE_MQH

#include "Clock.mqh"

enum ENUM_OK_MODE
  {
   OK_PROP_FIRM          = 0,  // Prop Firm (<3% daily, <6% total, consistency lock)
   OK_HOUSE_MONEY_GROWTH = 1   // Personal Growth (Moonshot compounding + 2-Stage Scale-In)
  };

class COkRisk
  {
public:
   string            m_sym;
   ENUM_OK_MODE      m_mode;
   double            m_initBalance;
   double            m_hwm;
   double            m_dayRef;
   double            m_dayStartBal;
   double            m_monthStartBal;
   long              m_curDayKey;
   long              m_curMonthKey;
   bool              m_dayHalted;
   bool              m_dayLocked;
   bool              m_totalHalted;
   bool              m_dayStartedAboveTotalTrip;

   double            m_dailyCeilPct;
   double            m_dailyHardPct;
   double            m_totalCeilPct;
   double            m_totalHardPct;
   double            m_roomFracDay;
   double            m_roomFracTot;
   double            m_baseRiskPct;
   double            m_maxRiskPct;
   double            m_dayProfitLockPct;
   int               m_maxProbeSlots;
   int               m_reserveHtfSlots;
   bool              m_allowPyramid;
   bool              m_allowTwoStagePyr;

                     COkRisk(void) : m_mode(OK_PROP_FIRM), m_initBalance(0), m_hwm(0), m_dayRef(0),
                                     m_dayStartBal(0), m_monthStartBal(0), m_curDayKey(LONG_MIN), m_curMonthKey(LONG_MIN),
                                     m_dayHalted(false), m_dayLocked(false), m_totalHalted(false),
                                     m_dayStartedAboveTotalTrip(true),
                                     m_dailyCeilPct(2.45), m_dailyHardPct(2.25),
                                     m_totalCeilPct(5.35), m_totalHardPct(5.00),
                                     m_roomFracDay(0.15), m_roomFracTot(0.15),
                                     m_baseRiskPct(0.30), m_maxRiskPct(0.55),
                                     m_dayProfitLockPct(2.40), m_maxProbeSlots(3), m_reserveHtfSlots(2),
                                     m_allowPyramid(false), m_allowTwoStagePyr(false) {}

   void              Init(const string sym, ENUM_OK_MODE mode, double riskScale, const COkClock &clk)
     {
      m_sym  = sym;
      m_mode = mode;
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_initBalance   = MathMax(bal, 100.0);
      m_hwm           = MathMax(bal, eq);
      m_dayRef        = m_hwm;
      m_dayStartBal   = bal;
      m_monthStartBal = bal;
      m_curDayKey     = clk.TradingDayKey(TimeCurrent());
      MqlDateTime dtInit;
      TimeToStruct(clk.ToUtc(TimeCurrent()), dtInit);
      m_curMonthKey   = (long)dtInit.year * 100 + (long)dtInit.mon;
      m_dayHalted     = false;
      m_dayLocked   = false;
      m_totalHalted = false;
      m_dayStartedAboveTotalTrip = true;

      double sc = MathMax(0.25, MathMin(3.0, riskScale));
      if(mode == OK_PROP_FIRM)
        {
         m_dailyCeilPct     = 2.45;
         m_dailyHardPct     = 2.25;
         m_totalCeilPct     = 5.35;
         m_totalHardPct     = 5.00;
         m_roomFracDay      = 0.22 * sc;
         m_roomFracTot      = 0.22 * sc;
         m_baseRiskPct      = 0.45 * sc;
         m_maxRiskPct       = 0.95 * sc;
         m_dayProfitLockPct = 2.65;
         m_maxProbeSlots    = 6;
         m_reserveHtfSlots  = 1;
         m_allowPyramid     = true;
         m_allowTwoStagePyr = false;
        }
      else
        {
         m_dailyCeilPct     = 14.0;
         m_dailyHardPct     = 12.0;
         m_totalCeilPct     = 29.0;
         m_totalHardPct     = 27.5;
         m_roomFracDay      = 0.50;
         m_roomFracTot      = 0.25;
         m_baseRiskPct      = 1.55 * sc;
         m_maxRiskPct       = 3.00 * sc;
         m_dayProfitLockPct = 999.0;
         m_maxProbeSlots    = 6;
         m_reserveHtfSlots  = 1;
         m_allowPyramid     = true;
         m_allowTwoStagePyr = true;
        }
     }

   bool              UpdateTrackers(datetime srvNow, const COkClock &clk)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(bal > m_hwm) m_hwm = bal;

      long dk = clk.TradingDayKey(srvNow);
      if(dk != m_curDayKey)
        {
         m_curDayKey   = dk;
         m_dayRef      = (m_mode == OK_PROP_FIRM) ? MathMax(bal, eq) : bal;
         m_dayStartBal = bal;
         m_dayHalted   = false;
         m_dayLocked   = false;
         if(m_mode == OK_HOUSE_MONEY_GROWTH || TotalDdPct() < m_totalHardPct)
           {
            m_totalHalted = false;
            m_dayStartedAboveTotalTrip = true;
           }
        }
      MqlDateTime dtUtc;
      TimeToStruct(clk.ToUtc(srvNow), dtUtc);
      long mk = (long)dtUtc.year * 100 + (long)dtUtc.mon;
      if(mk != m_curMonthKey)
        {
         m_curMonthKey   = mk;
         m_monthStartBal = bal;
        }

      double ddd = DailyDdPct();
      double tdd = TotalDdPct();
      if(ddd >= m_dailyCeilPct) m_dayHalted = true;
      if(m_mode == OK_PROP_FIRM)
        {
         if(tdd >= m_totalCeilPct) m_totalHalted = true;
        }

      if(m_mode == OK_PROP_FIRM && m_dayStartBal > 0.0)
        {
         double dayGainPct = 100.0 * (bal - m_dayStartBal) / m_dayStartBal;
         if(dayGainPct >= m_dayProfitLockPct)
            m_dayLocked = true;
        }
      return (m_dayHalted || m_totalHalted);
     }

   double            DailyDdPct(void) const
     {
      if(m_dayRef <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return MathMax(0.0, 100.0 * (m_dayRef - eq) / m_dayRef);
     }

   double            TotalDdPct(void) const
     {
      if(m_hwm <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return MathMax(0.0, 100.0 * (m_hwm - eq) / m_hwm);
     }

   bool              CanOpenNew(void) const
     {
      if(m_dayHalted || m_dayLocked || m_totalHalted)
         return false;
      if(DailyDdPct() >= m_dailyHardPct)
         return false;
      if(m_mode == OK_PROP_FIRM && TotalDdPct() >= m_totalHardPct)
         return false;
      return true;
     }

   bool              CanOpenStream(int stream, int openProbes) const
     {
      if(!CanOpenNew())
         return false;
      if(openProbes >= m_maxProbeSlots)
         return false;
      if(stream == 4 && openProbes >= (m_maxProbeSlots - m_reserveHtfSlots))
         return false;
      return true;
     }

   //--- 100% Causal Geometric Monthly Profit Shield + Intraday 2-Win Guard + Deficit Recovery
   double            MonthlyShieldScale(double openStopRiskUsd) const
     {
      double bal     = AccountInfoDouble(ACCOUNT_BALANCE);
      double baseRef = MathMax(100.0, m_monthStartBal);
      double oneRUsd = MathMax(10.0, baseRef * (m_baseRiskPct / 100.0));
      double monthClosedR = (bal - m_monthStartBal) / oneRUsd;
      double dayClosedR   = (bal - m_dayStartBal)   / oneRUsd;

      if(monthClosedR > 0.005)
        {
         if(dayClosedR >= 0.12)
            return MathMax(0.015, MathMin(0.35, 0.20 * monthClosedR));
         return MathMax(0.015, MathMin(1.60, 0.35 * monthClosedR));
        }
      if(monthClosedR < -0.001)
        {
         double deficit = -monthClosedR;
         return MathMin(2.50, MathMax(1.40, 1.0 + 1.25 * deficit));
        }
      return (openStopRiskUsd > 0.0) ? 0.015 : 1.00;
     }

   double            NextRiskUsd(double effectiveWeight, double openStopRiskUsd) const
     {
      if(!CanOpenNew())
         return 0.0;
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double mScale = MonthlyShieldScale(openStopRiskUsd);

      if(m_mode == OK_PROP_FIRM)
        {
         double base         = MathMin(bal, eq);
         double dRoomUsd     = MathMax(0.0, m_dayRef * (m_dailyHardPct / 100.0) - MathMax(0.0, m_dayRef - eq) - openStopRiskUsd);
         double tRoomUsd     = MathMax(0.0, m_hwm    * (m_totalHardPct / 100.0) - MathMax(0.0, m_hwm    - eq) - openStopRiskUsd);
         double roomUsd      = MathMin(dRoomUsd, tRoomUsd);
         bool   inHouseMoney = (bal >= m_initBalance * 1.04 && TotalDdPct() < 1.80 && DailyDdPct() < 1.00);
         double effRoomFrac  = inHouseMoney ? (m_roomFracDay * 1.35) : m_roomFracDay;
         double effBasePct   = inHouseMoney ? (m_baseRiskPct * 1.55) : m_baseRiskPct;
         double byRoom       = roomUsd * effRoomFrac;
         double byBase       = base * (effBasePct / 100.0) * mScale;
         double byCap        = base * (m_maxRiskPct  / 100.0) * MathMax(1.0, mScale * 0.70);
         double riskUsd      = MathMin(byRoom, MathMin(byBase, byCap)) * effectiveWeight;
         if(bal > m_monthStartBal + 1.0)
            riskUsd = MathMin(riskUsd, (bal - m_monthStartBal) * 0.42);
         if(riskUsd > roomUsd * 0.85)
            riskUsd = roomUsd * 0.85;
         return MathMax(0.0, riskUsd);
        }

      //--- OK_GROWTH_MOONSHOT (geometric equity compounding, immune to HWM lockout)
      double dFloor   = m_dayRef * (1.0 - m_dailyHardPct / 100.0);
      double tFloor   = m_hwm    * (1.0 - 0.28);
      double dRoomUsd = MathMax(0.0, eq - dFloor);
      double tRoomUsd = MathMax(eq * 0.10, eq - tFloor);
      double budget   = MathMin(dRoomUsd * m_roomFracDay, tRoomUsd * m_roomFracTot) - openStopRiskUsd;
      if(budget <= 0.0)
         return 0.0;

      double ddScale = 1.0;
      double tdd = TotalDdPct();
      if(tdd >= 18.0)      ddScale = 0.50;
      else if(tdd >= 12.0) ddScale = 0.72;

      double desired = eq * (m_baseRiskPct / 100.0) * effectiveWeight * ddScale * mScale;
      double capUsd  = eq * (m_maxRiskPct  / 100.0) * MathMax(1.0, effectiveWeight) * ddScale * MathMax(1.0, mScale * 0.70);
      double riskUsd = MathMin(budget, MathMin(desired, capUsd));
      if(bal > m_monthStartBal + 1.0)
         riskUsd = MathMin(riskUsd, (bal - m_monthStartBal) * 0.42);
      return MathMax(0.0, riskUsd);
     }

   double            LossPerLot(int dir, double entryPx, double slPx) const
     {
      double dist = MathAbs(entryPx - slPx);
      if(dist <= 0.0)
         return 1e9;
      double slipBuf = (m_mode == OK_PROP_FIRM) ? 0.25 : 0.12;
      double effSl   = (dir == 1) ? (entryPx - (dist + slipBuf)) : (entryPx + (dist + slipBuf));
      ENUM_ORDER_TYPE ot = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double calcPl = 0.0;
      double loss1  = 0.0;
      if(OrderCalcProfit(ot, m_sym, 1.0, entryPx, effSl, calcPl) && calcPl < 0.0)
         loss1 = MathAbs(calcPl);

      double tickSz  = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      double tickVal = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickVal <= 0.0) tickVal = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE);
      double loss2 = (tickSz > 0.0 && tickVal > 0.0) ? ((dist + slipBuf) / tickSz) * tickVal : 0.0;

      double cSize = SymbolInfoDouble(m_sym, SYMBOL_TRADE_CONTRACT_SIZE);
      if(cSize <= 0.0) cSize = 100.0;
      double loss3 = cSize * (dist + slipBuf);

      return MathMax(loss1, MathMax(loss2, loss3));
     }

   double            OrderLots(int dir, double entryPx, double slPx, double effectiveWeight,
                               double openStopRiskUsd, double openMarginUsed) const
     {
      double riskUsd = NextRiskUsd(effectiveWeight, openStopRiskUsd);
      if(riskUsd <= 0.0)
         return 0.0;
      double lpl = LossPerLot(dir, entryPx, slPx);
      if(lpl <= 0.0)
         return 0.0;

      double rawLots = riskUsd / lpl;
      double minLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(minLot  <= 0.0) minLot  = 0.01;
      if(maxLot  <= 0.0) maxLot  = 50.0;
      if(stepLot <= 0.0) stepLot = 0.01;
      double capLots = (m_mode == OK_HOUSE_MONEY_GROWTH) ? (maxLot * 2.0) : maxLot;

      ENUM_ORDER_TYPE ot = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double mar1 = 0.0;
      if(!OrderCalcMargin(ot, m_sym, 1.0, entryPx, mar1) || mar1 <= 0.0)
         mar1 = entryPx * 100.0 / 30.0;

      double eq      = AccountInfoDouble(ACCOUNT_EQUITY);
      double freeMar = MathMax(0.0, eq - openMarginUsed);
      double maxMar  = freeMar * 0.80;
      if(mar1 > 0.0 && rawLots * mar1 > maxMar)
         rawLots = maxMar / mar1;

      double lots = MathFloor(rawLots / stepLot + 1e-9) * stepLot;
      if(lots < minLot)
        {
         double minLoss = minLot * lpl;
         double dRoom = MathMax(0.0, m_dayRef * (m_dailyCeilPct / 100.0) - MathMax(0.0, m_dayRef - eq) - openStopRiskUsd);
         double tRoom = (m_mode == OK_PROP_FIRM)
                        ? MathMax(0.0, m_hwm * (m_totalCeilPct / 100.0) - MathMax(0.0, m_hwm - eq) - openStopRiskUsd)
                        : dRoom;
         if(minLoss <= MathMin(dRoom, tRoom) - 5.0 && minLot * mar1 <= maxMar)
            lots = minLot;
         else
            return 0.0;
        }
      lots = MathMin(lots, capLots);
      int digits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);
      return NormalizeDouble(lots, digits);
     }
  };

#endif // OLIVERKELL_RISKENGINE_MQH
