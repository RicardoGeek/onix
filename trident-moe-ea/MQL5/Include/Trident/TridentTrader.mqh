//+------------------------------------------------------------------+
//| TridentTrader.mqh - Multi-Prong Wave Execution & Risk Engine     |
//|                                                                  |
//| Executes & manages Prong 2 (16Runes, Magic 16016001) and         |
//| Prong 3 (ImpulseCascade, Magic 16016004) with distinct Magic     |
//| Numbers and Order Comments while harmonizing with Prong 1        |
//| (Sniper, Magic 20260401).                                        |
//+------------------------------------------------------------------+
#ifndef TRIDENT_TRADER_MQH
#define TRIDENT_TRADER_MQH

#include <Trade\Trade.mqh>
#include <16Runes\RiskEngine.mqh>
#include "TridentStreams.mqh"

#define TRIDENT_MAX_SLOTS 16

struct STridentSlot
  {
   bool              active;
   ulong             ticket;
   long              magic;
   int               corner;         // 2 = 16Runes, 4 = ImpulseCascade
   int               stream;         // 0..4
   int               runeId;         // 0..15
   int               dir;            // +1 or -1
   bool              isAdd;
   ulong             parentTicket;
   bool              isWhale;
   bool              isProtected;
   bool              added;
   bool              added2;
   double            convMult;
   double            entryPx;
   double            initR;
   double            slPx;
   double            tpPx;
   double            trailDist;
   double            extremePx;
   double            mfeFavUsd;
   double            maeAdvUsd;
   datetime          openSrv;
   datetime          lastTrailM1;
  };

class CTridentRisk : public CR16Risk
  {
public:
   bool              m_moeGapFillMode;
   double            m_gapFillRiskPct;

                     CTridentRisk(void) : CR16Risk(), m_moeGapFillMode(true), m_gapFillRiskPct(0.35) {}

   void              ConfigureMoE(bool moeGapFillMode, double gapFillRiskPct, double dailyProfitLockPct = 15.00)
     {
      m_moeGapFillMode = moeGapFillMode;
      m_gapFillRiskPct = MathMax(0.10, MathMin(1.20, gapFillRiskPct));
      if(m_mode == R16_PROP_FIRM && dailyProfitLockPct > 0.0)
         m_dayProfitLockPct = dailyProfitLockPct;
     }

   //--- Unified Trident Tracker Sync: Prevents unrealized floating MFE spikes from
   //--- ratcheting m_hwm and causing a false permanent totalHalted lockout after BE closes.
   bool              UpdateTrackersTrident(datetime srvNow, const CR16Clock &clk, const SRiskStateSnapshot &sniperSnap)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

      if(m_moeGapFillMode && m_mode == R16_PROP_FIRM)
         m_hwm = (m_initBalance > 0.0) ? m_initBalance : bal;
      else if(bal > m_hwm)
         m_hwm = bal;

      long dk = clk.TradingDayKey(srvNow);
      if(dk != m_curDayKey)
        {
         m_curDayKey   = dk;
         m_dayRef      = (sniperSnap.dayStartReference > 0.0)
                         ? sniperSnap.dayStartReference
                         : ((m_mode == R16_PROP_FIRM) ? MathMax(bal, eq) : bal);
         m_dayStartBal = bal;
         m_dayHalted   = false;
         m_dayLocked   = false;
         m_totalHalted = false;
         m_dayStartedAboveTotalTrip = true;
        }
      else if(sniperSnap.dayStartReference > 0.0)
        {
         m_dayRef = sniperSnap.dayStartReference;
        }

      MqlDateTime dtUtc;
      TimeToStruct(clk.ToUtc(srvNow), dtUtc);
      long mk = (long)dtUtc.year * 100 + (long)dtUtc.mon;
      if(mk != m_curMonthKey)
        {
         m_curMonthKey   = mk;
         m_monthStartBal = bal;
        }

      double ddd = (sniperSnap.dayStartReference > 0.0) ? sniperSnap.dailyDrawdownPct : DailyDdPct();
      double tdd = (sniperSnap.highWaterMark     > 0.0) ? sniperSnap.totalDrawdownPct : TotalDdPct();

      m_dayHalted   = (ddd >= m_dailyCeilPct || sniperSnap.tradingHaltedToday);
      m_totalHalted = (m_mode == R16_PROP_FIRM && (tdd >= m_totalCeilPct || sniperSnap.permanentLockout));

      if(m_mode == R16_PROP_FIRM && m_dayStartBal > 0.0)
        {
         double dayGainPct = 100.0 * (bal - m_dayStartBal) / m_dayStartBal;
         if(dayGainPct >= m_dayProfitLockPct)
            m_dayLocked = true;
        }
      return (ddd >= m_dailyCeilPct || (m_mode == R16_PROP_FIRM && tdd >= m_totalCeilPct));
     }

   double            OrderLotsTrident(int dir, double entryPx, double slPx, double effectiveWeight,
                                      double openStopRiskUsd, double openMarginUsed) const
     {
      if(!m_moeGapFillMode)
         return OrderLots(dir, entryPx, slPx, effectiveWeight, openStopRiskUsd, openMarginUsed);

      if(!CanOpenNew())
         return 0.0;

      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double base = MathMin(bal, eq);

      double dRoomUsd = MathMax(0.0, m_dayRef * (m_dailyHardPct / 100.0) - MathMax(0.0, m_dayRef - eq) - openStopRiskUsd);
      double tRoomUsd = MathMax(0.0, m_hwm    * (m_totalHardPct / 100.0) - MathMax(0.0, m_hwm    - eq) - openStopRiskUsd);
      double roomUsd  = MathMin(dRoomUsd, tRoomUsd);

      bool   inHouseMoney = (bal >= m_initBalance * 1.04 && TotalDdPct() < 1.80 && DailyDdPct() < 1.00);
      bool   inStartup    = (m_initBalance > 0.0 && bal < m_initBalance * 1.01);
      double effBasePct   = inHouseMoney ? (m_gapFillRiskPct * 1.35)
                                         : (inStartup ? (m_gapFillRiskPct * 0.55) : m_gapFillRiskPct);
      double byRoom       = roomUsd * 0.28;
      double byBase       = base * (effBasePct / 100.0) * effectiveWeight;
      double riskUsd      = MathMin(byRoom, byBase);
      if(riskUsd <= 0.0)
         return 0.0;

      double lpl = LossPerLot(dir, entryPx, slPx);
      if(lpl <= 0.0)
         return 0.0;

      double minLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(minLot <= 0.0)  minLot  = 0.01;
      if(stepLot <= 0.0) stepLot = 0.01;

      double rawLots = riskUsd / lpl;
      ENUM_ORDER_TYPE ot = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double mar1 = 0.0;
      if(!OrderCalcMargin(ot, m_sym, 1.0, entryPx, mar1) || mar1 <= 0.0)
        {
         double cSize = SymbolInfoDouble(m_sym, SYMBOL_TRADE_CONTRACT_SIZE);
         long   lev   = AccountInfoInteger(ACCOUNT_LEVERAGE);
         mar1 = (cSize > 0.0 ? cSize : 100.0) * entryPx / (double)MathMax((int)lev, 1);
        }
      double freeMar = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxMarAvail = MathMax(0.0, MathMin(freeMar * 0.80, eq * 0.75 - openMarginUsed));
      if(mar1 > 0.0)
         rawLots = MathMin(rawLots, maxMarAvail / mar1);

      double lots = MathFloor(rawLots / stepLot + 1e-9) * stepLot;
      if(lots < minLot)
        {
         if(minLot * lpl <= roomUsd * 0.45 && minLot * mar1 <= maxMarAvail)
            lots = minLot;
         else
            return 0.0;
        }
      int digits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);
      return NormalizeDouble(MathMin(lots, maxLot), digits);
     }
  };

class CTridentTrader
  {
public:
   string            m_sym;
   long              m_magicSniper;
   long              m_magicRunes;
   long              m_magicCascade;
   CTrade            m_trade;
   STridentSlot      m_slots[TRIDENT_MAX_SLOTS];

   double            m_slAtrMult;       // 1.35 * (1.5 * ATR14(H1)) in MoE mode, 2.50 in Solo Runes mode
   double            m_trailAtrMult;    // 2.00 * ATR14(H1)
   double            m_beAtR;           // 1.40R Stage-1 Whale in MoE, 0.85R in Solo
   double            m_beLockR;         // 0.25R Stage-1 lock in MoE, 0.55R in Solo
   double            m_pyr2AtR;         // 2.60R Stage-2 Whale
   double            m_pyr2LockR;       // 1.50R Stage-2 lock
   double            m_pyr2SlR;         // 1.50R Stage-2 SL
   double            m_trailActR;       // 1.00R
   double            m_tpR;             // 3.00R
   double            m_whaleTpR;        // 6.00R
   double            m_growthWhaleTpR;  // 7.00R
   double            m_whaleTrailMult;  // 1.50x
   int               m_maxHoldMin;      // 720 (12h)
   int               m_whaleHoldMin;    // 2880 (48h)

   int               m_tradesRunes;
   int               m_tradesCascade;

                     CTridentTrader(void) : m_magicSniper(20260401), m_magicRunes(16016001), m_magicCascade(16016004),
                                            m_slAtrMult(2.025), m_trailAtrMult(2.00),
                                            m_beAtR(1.40), m_beLockR(0.25),
                                            m_pyr2AtR(2.60), m_pyr2LockR(1.50), m_pyr2SlR(1.50),
                                            m_trailActR(1.00), m_tpR(3.00),
                                            m_whaleTpR(6.00), m_growthWhaleTpR(7.00),
                                            m_whaleTrailMult(1.50),
                                            m_maxHoldMin(720), m_whaleHoldMin(2880),
                                            m_tradesRunes(0), m_tradesCascade(0)
     {
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         ClearSlot(i);
     }

   void              ClearSlot(int i)
     {
      m_slots[i].active       = false;
      m_slots[i].ticket       = 0;
      m_slots[i].magic        = 0;
      m_slots[i].corner       = TRIDENT_CORNER_NONE;
      m_slots[i].stream       = -1;
      m_slots[i].runeId       = -1;
      m_slots[i].dir          = 0;
      m_slots[i].isAdd        = false;
      m_slots[i].parentTicket = 0;
      m_slots[i].isWhale      = false;
      m_slots[i].isProtected  = false;
      m_slots[i].added        = false;
      m_slots[i].added2       = false;
      m_slots[i].convMult     = 1.0;
      m_slots[i].entryPx      = 0.0;
      m_slots[i].initR        = 0.0;
      m_slots[i].slPx         = 0.0;
      m_slots[i].tpPx         = 0.0;
      m_slots[i].trailDist    = 0.0;
      m_slots[i].extremePx    = 0.0;
      m_slots[i].mfeFavUsd    = 0.0;
      m_slots[i].maeAdvUsd    = 0.0;
      m_slots[i].openSrv      = 0;
      m_slots[i].lastTrailM1  = 0;
     }

   void              Init(const string sym, long magicSniper, long magicRunes, long magicCascade, bool moeMode)
     {
      m_sym          = sym;
      m_magicSniper  = magicSniper;
      m_magicRunes   = magicRunes;
      m_magicCascade = magicCascade;
      m_trade.SetExpertMagicNumber(magicRunes);
      m_trade.SetDeviationInPoints(35);
      m_trade.SetTypeFillingBySymbol(sym);

      if(moeMode)
        {
         // SEEN-Calibrated (2017-2023) Breathing Harvester + Whale parameters (2.025 * ATR14(H1))
         m_slAtrMult   = 2.025;
         m_beAtR       = 1.25;
         m_beLockR     = 0.35;
         m_pyr2AtR     = 2.60;
         m_pyr2LockR   = 1.50;
         m_pyr2SlR     = 1.50;
         m_trailActR   = 1.00;
         m_maxHoldMin  = 720;
         m_whaleHoldMin= 2880;
        }
      else
        {
         // Standalone 16Runes v1.23 parameters
         m_slAtrMult   = 2.50;
         m_beAtR       = 0.85;
         m_beLockR     = 0.55;
         m_pyr2AtR     = 1.80;
         m_pyr2LockR   = 1.40;
         m_pyr2SlR     = 1.40;
         m_trailActR   = 0.85;
         m_maxHoldMin  = 2880;
         m_whaleHoldMin= 2880;
        }

      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         ClearSlot(i);
      ReconcileWithBroker();
     }

   bool              IsWaveMagic(long mgk) const
     {
      return (mgk == m_magicRunes || mgk == m_magicCascade);
     }

   double            NormPrice(double p) const
     {
      double ts = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      int    dg = (int)SymbolInfoInteger(m_sym, SYMBOL_DIGITS);
      if(ts <= 0.0)
         return NormalizeDouble(p, dg);
      return NormalizeDouble(MathRound(p / ts) * ts, dg);
     }

   void              ReconcileWithBroker(void)
     {
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(m_slots[i].active && !PositionSelectByTicket(m_slots[i].ticket))
            ClearSlot(i);

      int total = PositionsTotal();
      for(int p = 0; p < total; p++)
        {
         ulong tk = PositionGetTicket(p);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         long mgk = PositionGetInteger(POSITION_MAGIC);
         if(!IsWaveMagic(mgk)) continue;

         bool known = false;
         for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
            if(m_slots[i].active && m_slots[i].ticket == tk) { known = true; break; }
         if(known) continue;

         for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
            if(!m_slots[i].active)
              {
               int    d   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
               double opx = PositionGetDouble(POSITION_PRICE_OPEN);
               double sl  = PositionGetDouble(POSITION_SL);
               double tp  = PositionGetDouble(POSITION_TP);
               double r0  = (sl > 0.0 && MathAbs(opx - sl) > 0.5) ? MathAbs(opx - sl) : 15.0;
               string cmt = PositionGetString(POSITION_COMMENT);
               int    stm = 0;
               if(StringFind(cmt, "S1") >= 0) stm = 1;
               else if(StringFind(cmt, "S2") >= 0) stm = 2;
               else if(StringFind(cmt, "S3") >= 0) stm = 3;
               else if(StringFind(cmt, "S4") >= 0) stm = 4;

               m_slots[i].active       = true;
               m_slots[i].ticket       = tk;
               m_slots[i].magic        = mgk;
               m_slots[i].corner       = (mgk == m_magicCascade) ? TRIDENT_CORNER_CASCADE : TRIDENT_CORNER_16RUNES;
               m_slots[i].stream       = stm;
               m_slots[i].runeId       = 0;
               m_slots[i].dir          = d;
               m_slots[i].isAdd        = (StringFind(cmt, "ADD") >= 0);
               m_slots[i].parentTicket = 0;
               m_slots[i].isWhale      = false;
               m_slots[i].isProtected  = (sl > 0.0 && d * (sl - opx) > 0.05);
               m_slots[i].added        = m_slots[i].isAdd;
               m_slots[i].added2       = m_slots[i].isAdd;
               m_slots[i].convMult     = 1.0;
               m_slots[i].entryPx      = opx;
               m_slots[i].initR        = r0;
               m_slots[i].slPx         = sl;
               m_slots[i].tpPx         = tp;
               m_slots[i].trailDist    = r0 * (m_trailAtrMult / m_slAtrMult);
               m_slots[i].extremePx    = opx;
               m_slots[i].mfeFavUsd    = 0.0;
               m_slots[i].maeAdvUsd    = 0.0;
               m_slots[i].openSrv      = (datetime)PositionGetInteger(POSITION_TIME);
               m_slots[i].lastTrailM1  = 0;
               break;
              }
        }
     }

   int               Probes(void) const
     {
      int c = 0;
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd) c++;
      return c;
     }

   int               UnprotectedProbes(void) const
     {
      int c = 0;
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd && !m_slots[i].isProtected) c++;
      return c;
     }

   bool              StreamHasProbe(int s) const
     {
      if(UnprotectedProbes() >= 2)
         return true;
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd && m_slots[i].stream == s && !m_slots[i].isProtected)
            return true;
      return false;
     }

   //--- Surroundings Guard:
   //--- 1. Zero opposite-direction hedging across all 3 Prongs (or external positions).
   //--- 2. Yields to Prong 1 (Sniper) whenever Sniper has an unprotected position or pending limit order.
   bool              CheckSurroundings(int dir, bool respectExternal, datetime srvNow, string &outReason) const
     {
      outReason = "";
      int totalPos = PositionsTotal();
      for(int p = 0; p < totalPos; p++)
        {
         ulong tk = PositionGetTicket(p);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         long   mgk   = PositionGetInteger(POSITION_MAGIC);
         int    pDir  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double opx   = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         datetime pTm = (datetime)PositionGetInteger(POSITION_TIME);
         if(pDir != dir)
           {
            outReason = IsWaveMagic(mgk) ? "own-opposite" : "sniper-or-ext-opposite-no-hedge";
            return false;
           }
         if(!IsWaveMagic(mgk) && respectExternal)
           {
            bool isExtProt = (sl > 0.0 && pDir * (sl - opx) > 0.02);
            if(!isExtProt || (srvNow - pTm) < 180)
              {
               outReason = (mgk == m_magicSniper) ? "prong1-sniper-active" : "ext-musketeer-active";
               return false;
              }
           }
        }
      int totalOrd = OrdersTotal();
      for(int o = 0; o < totalOrd; o++)
        {
         ulong otk = OrderGetTicket(o);
         if(otk == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_sym) continue;
         ENUM_ORDER_TYPE oType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         int oDir = (oType == ORDER_TYPE_BUY || oType == ORDER_TYPE_BUY_LIMIT ||
                     oType == ORDER_TYPE_BUY_STOP || oType == ORDER_TYPE_BUY_STOP_LIMIT) ? 1 : -1;
         if(oDir != dir)
           {
            outReason = "pending-opposite";
            return false;
           }
         if(!IsWaveMagic(OrderGetInteger(ORDER_MAGIC)) && respectExternal)
           {
            outReason = "prong1-sniper-limit-active";
            return false;
           }
        }
      return true;
     }

   void              OpenExposure(const CTridentRisk &risk, double &openStopRiskUsd, double &openMarginUsed) const
     {
      openStopRiskUsd = 0.0;
      openMarginUsed  = 0.0;
      int totalPos = PositionsTotal();
      for(int p = 0; p < totalPos; p++)
        {
         ulong tk = PositionGetTicket(p);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         double vol = PositionGetDouble(POSITION_VOLUME);
         double opx = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl  = PositionGetDouble(POSITION_SL);
         int    d   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         if(sl > 0.0 && d * (opx - sl) > 0.0)
            openStopRiskUsd += vol * risk.LossPerLot(d, opx, sl);
         ENUM_ORDER_TYPE ot = (d == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double m1 = 0.0;
         if(OrderCalcMargin(ot, m_sym, vol, opx, m1) && m1 > 0.0)
            openMarginUsed += m1;
        }
     }

   void              CloseAll(const string reason)
     {
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
        {
         if(!m_slots[i].active) continue;
         if(PositionSelectByTicket(m_slots[i].ticket))
           {
            PrintFormat("[Trident-MoE] Liquidating #%I64u (%s)", m_slots[i].ticket, reason);
            m_trade.SetExpertMagicNumber(m_slots[i].magic);
            m_trade.PositionClose(m_slots[i].ticket, 50);
           }
         ClearSlot(i);
        }
     }

   bool              ExecuteMarketTicket(long slotMagic, int dir, double lots, double slPx, double tpPx,
                                         const string cmt, ulong &outPosTk, double &outFillPx)
     {
      m_trade.SetExpertMagicNumber(slotMagic);
      double fillEst = (dir == 1) ? SymbolInfoDouble(m_sym, SYMBOL_ASK) : SymbolInfoDouble(m_sym, SYMBOL_BID);
      bool ok = (dir == 1) ? m_trade.Buy(lots, m_sym, 0.0, slPx, tpPx, cmt)
                           : m_trade.Sell(lots, m_sym, 0.0, slPx, tpPx, cmt);
      if(!ok || (m_trade.ResultRetcode() != TRADE_RETCODE_DONE && m_trade.ResultRetcode() != TRADE_RETCODE_PLACED))
         return false;

      ulong dealTk = m_trade.ResultDeal();
      outPosTk     = m_trade.ResultOrder();
      if(dealTk > 0 && HistoryDealSelect(dealTk))
        {
         ulong pId = (ulong)HistoryDealGetInteger(dealTk, DEAL_POSITION_ID);
         if(pId > 0) outPosTk = pId;
        }
      outFillPx = m_trade.ResultPrice();
      if(outFillPx <= 0.0) outFillPx = fillEst;
      return true;
     }

   bool              OpenProbe(int corner, int stream, int runeId, int dir, double h1Atr, double convMult,
                               const CTridentRisk &risk, datetime srvNow)
     {
      if(!risk.CanOpenStream(stream, Probes()))
         return false;
      if(StreamHasProbe(stream))
         return false;
      if(h1Atr <= 0.1)
         return false;

      int slot = -1;
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(!m_slots[i].active) { slot = i; break; }
      if(slot < 0)
         return false;

      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double fillEst = (dir == 1) ? ask : bid;

      double slMultNow = (corner == TRIDENT_CORNER_CASCADE) ? 2.025 : m_slAtrMult;
      double R     = MathMax(1.50, slMultNow * h1Atr);
      double tdist = m_trailAtrMult * h1Atr;
      double slPx  = NormPrice(fillEst - dir * R);
      double tpPx  = NormPrice(fillEst + dir * m_tpR * R);

      double openRisk = 0.0, openMar = 0.0;
      OpenExposure(risk, openRisk, openMar);
      double effWeight = R16_STREAM_WEIGHTS[stream] * convMult;
      double totalLots = risk.OrderLotsTrident(dir, fillEst, slPx, effWeight, openRisk, openMar);
      if(totalLots <= 0.0)
         return false;

      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(maxLot <= 0.0)  maxLot  = 50.0;
      if(stepLot <= 0.0) stepLot = 0.01;
      int lotDigits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);

      long   slotMagic = (corner == TRIDENT_CORNER_CASCADE) ? m_magicCascade : m_magicRunes;
      string pfx       = (corner == TRIDENT_CORNER_CASCADE) ? "P3_CAS" : "P2_R16";
      double lots1     = NormalizeDouble(MathMin(totalLots, maxLot), lotDigits);
      string cmt       = StringFormat("%s_S%d_%s", pfx, stream, R16_NAMES[runeId]);
      ulong  posTk     = 0;
      double actualFill= 0.0;
      if(!ExecuteMarketTicket(slotMagic, dir, lots1, slPx, tpPx, cmt, posTk, actualFill))
         return false;

      double realSl = NormPrice(actualFill - dir * R);
      double realTp = NormPrice(actualFill + dir * m_tpR * R);
      if(PositionSelectByTicket(posTk))
        {
         if(MathAbs(realSl - slPx) >= SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE) ||
            MathAbs(realTp - tpPx) >= SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE))
           {
            m_trade.SetExpertMagicNumber(slotMagic);
            m_trade.PositionModify(posTk, realSl, realTp);
           }
        }

      m_slots[slot].active       = true;
      m_slots[slot].ticket       = posTk;
      m_slots[slot].magic        = slotMagic;
      m_slots[slot].corner       = corner;
      m_slots[slot].stream       = stream;
      m_slots[slot].runeId       = runeId;
      m_slots[slot].dir          = dir;
      m_slots[slot].isAdd        = false;
      m_slots[slot].parentTicket = 0;
      m_slots[slot].isWhale      = false;
      m_slots[slot].isProtected  = false;
      m_slots[slot].added        = false;
      m_slots[slot].added2       = false;
      m_slots[slot].convMult     = convMult;
      m_slots[slot].entryPx      = actualFill;
      m_slots[slot].initR        = R;
      m_slots[slot].slPx         = realSl;
      m_slots[slot].tpPx         = realTp;
      m_slots[slot].trailDist    = tdist;
      m_slots[slot].extremePx    = actualFill;
      m_slots[slot].mfeFavUsd    = 0.0;
      m_slots[slot].maeAdvUsd    = 0.0;
      m_slots[slot].openSrv      = srvNow;
      m_slots[slot].lastTrailM1  = iTime(m_sym, PERIOD_M1, 1);

      if(corner == TRIDENT_CORNER_CASCADE) m_tradesCascade++;
      else                                 m_tradesRunes++;
      return true;
     }

   bool              OpenWhaleAdd(int parentIdx, int stage, const CTridentRisk &risk, datetime srvNow)
     {
      if(!risk.m_allowPyramid || !risk.CanOpenNew())
         return false;
      int slot = -1;
      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
         if(!m_slots[i].active) { slot = i; break; }
      if(slot < 0)
         return false;

      int    d         = m_slots[parentIdx].dir;
      int    stm       = m_slots[parentIdx].stream;
      int    rid       = m_slots[parentIdx].runeId;
      int    corner    = m_slots[parentIdx].corner;
      long   slotMagic = m_slots[parentIdx].magic;
      double R         = m_slots[parentIdx].initR;
      double px0       = m_slots[parentIdx].entryPx;
      double ask       = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid       = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double fillEst   = (d == 1) ? ask : bid;

      double slPx = (stage == 1)
                    ? NormPrice(px0 + d * MathMax(0.25, m_beLockR * R))
                    : NormPrice(px0 + d * m_pyr2SlR * R);
      double tpPx = m_slots[parentIdx].tpPx;
      if(d * (fillEst - slPx) <= SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE) * 10.0)
         return false;

      double openRisk = 0.0, openMar = 0.0;
      OpenExposure(risk, openRisk, openMar);

      double distR      = MathMax(0.50, MathMin(2.00, MathAbs(fillEst - slPx) / R));
      double stageScale = (stage == 1) ? 1.00 : 0.50;
      double effWeight  = R16_STREAM_WEIGHTS[stm] * m_slots[parentIdx].convMult * distR * stageScale;
      double totalLots  = risk.OrderLotsTrident(d, fillEst, slPx, effWeight, openRisk, openMar);
      if(totalLots <= 0.0)
         return false;

      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(maxLot <= 0.0)  maxLot  = 50.0;
      if(stepLot <= 0.0) stepLot = 0.01;
      int lotDigits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);

      string pfx   = (corner == TRIDENT_CORNER_CASCADE) ? "P3_CAS" : "P2_R16";
      double lots1 = NormalizeDouble(MathMin(totalLots, maxLot), lotDigits);
      string cmt   = StringFormat("%s_S%d_ADD%d", pfx, stm, stage);
      ulong  posTk = 0;
      double actualFill = 0.0;
      if(!ExecuteMarketTicket(slotMagic, d, lots1, slPx, tpPx, cmt, posTk, actualFill))
         return false;

      m_slots[slot].active       = true;
      m_slots[slot].ticket       = posTk;
      m_slots[slot].magic        = slotMagic;
      m_slots[slot].corner       = corner;
      m_slots[slot].stream       = stm;
      m_slots[slot].runeId       = rid;
      m_slots[slot].dir          = d;
      m_slots[slot].isAdd        = true;
      m_slots[slot].parentTicket = m_slots[parentIdx].ticket;
      m_slots[slot].isWhale      = true;
      m_slots[slot].isProtected  = true;
      m_slots[slot].added        = true;
      m_slots[slot].added2       = true;
      m_slots[slot].convMult     = m_slots[parentIdx].convMult;
      m_slots[slot].entryPx      = actualFill;
      m_slots[slot].initR        = R;
      m_slots[slot].slPx         = slPx;
      m_slots[slot].tpPx         = tpPx;
      m_slots[slot].trailDist    = m_slots[parentIdx].trailDist;
      m_slots[slot].extremePx    = actualFill;
      m_slots[slot].mfeFavUsd    = 0.0;
      m_slots[slot].maeAdvUsd    = 0.0;
      m_slots[slot].openSrv      = srvNow;
      m_slots[slot].lastTrailM1  = iTime(m_sym, PERIOD_M1, 1);
      return true;
     }

   void              Manage(const CTridentRisk &risk, datetime srvNow)
     {
      ReconcileWithBroker();
      double bid    = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double ask    = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double tickSz = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickSz <= 0.0) tickSz = 0.01;
      int stopsLvl = (int)SymbolInfoInteger(m_sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = MathMax(tickSz * 2.0, stopsLvl * SymbolInfoDouble(m_sym, SYMBOL_POINT));

      datetime closedM1 = iTime(m_sym, PERIOD_M1, 1);
      MqlRates m1Bar[];
      bool hasM1 = (closedM1 > 0 && CopyRates(m_sym, PERIOD_M1, 1, 1, m1Bar) == 1);

      for(int i = 0; i < TRIDENT_MAX_SLOTS; i++)
        {
         if(!m_slots[i].active) continue;
         if(!PositionSelectByTicket(m_slots[i].ticket))
           {
            ClearSlot(i);
            continue;
           }

         m_trade.SetExpertMagicNumber(m_slots[i].magic);
         int    d       = m_slots[i].dir;
         double R       = MathMax(1.50, m_slots[i].initR);
         double px0     = m_slots[i].entryPx;
         double favor   = (d == 1) ? bid : ask;
         double cushUsd = MathMax(0.25, MathMax(minStopDist + 0.05, 0.035 * R));

         if(d * (favor - m_slots[i].extremePx) > 0.0)
            m_slots[i].extremePx = favor;

         //--- 1a. Stage-1 Whale Promotion
         if(!m_slots[i].isWhale && d * (favor - px0) >= m_beAtR * R)
           {
            m_slots[i].isWhale   = true;
            m_slots[i].trailDist = m_slots[i].trailDist * m_whaleTrailMult;
            double targetTpR = (risk.m_mode == R16_HOUSE_MONEY_GROWTH) ? m_growthWhaleTpR : m_whaleTpR;
            double beSl      = NormPrice(px0 + d * MathMax(0.25, m_beLockR * R));
            double whaleTp   = NormPrice(px0 + d * targetTpR * R);
            double newSl     = m_slots[i].slPx;
            if(d * (beSl - newSl) > tickSz && d * (favor - beSl) >= cushUsd)
               newSl = beSl;
            if(m_trade.PositionModify(m_slots[i].ticket, newSl, whaleTp))
              {
               m_slots[i].slPx = newSl;
               m_slots[i].tpPx = whaleTp;
               if(d * (newSl - px0) > 0.05)
                  m_slots[i].isProtected = true;
              }
            if(!m_slots[i].isAdd && !m_slots[i].added && risk.m_allowPyramid)
              {
               m_slots[i].added = true;
               OpenWhaleAdd(i, 1, risk, srvNow);
              }
           }

         //--- 1b. Stage-2 Whale Pyramid & Ratchet
         if(!m_slots[i].isAdd && m_slots[i].isWhale && !m_slots[i].added2 &&
            risk.m_allowTwoStagePyr && d * (favor - px0) >= m_pyr2AtR * R)
           {
            m_slots[i].added2 = true;
            double lockSl = NormPrice(px0 + d * m_pyr2LockR * R);
            for(int k = 0; k < TRIDENT_MAX_SLOTS; k++)
              {
               if(!m_slots[k].active) continue;
               if(k == i || m_slots[k].parentTicket == m_slots[i].ticket)
                 {
                  if(PositionSelectByTicket(m_slots[k].ticket) &&
                     d * (lockSl - m_slots[k].slPx) > tickSz &&
                     d * (favor - lockSl) >= cushUsd)
                    {
                     m_trade.SetExpertMagicNumber(m_slots[k].magic);
                     if(m_trade.PositionModify(m_slots[k].ticket, lockSl, m_slots[k].tpPx))
                       {
                        m_slots[k].slPx        = lockSl;
                        m_slots[k].isProtected = true;
                       }
                    }
                 }
              }
            OpenWhaleAdd(i, 2, risk, srvNow);
           }

         //--- 2. Completed M1 bar-close PureBE Harvester & ATR trailing stop
         if(hasM1 && closedM1 > m_slots[i].lastTrailM1 && closedM1 > m_slots[i].openSrv)
           {
            m_slots[i].lastTrailM1 = closedM1;
            double sp    = (double)m1Bar[0].spread * SymbolInfoDouble(m_sym, SYMBOL_POINT);
            double m1Fav = (d == 1) ? m1Bar[0].high : (m1Bar[0].low + sp);
            double m1Adv = (d == 1) ? m1Bar[0].low  : (m1Bar[0].high + sp);
            double m1Cl  = (d == 1) ? m1Bar[0].close : (m1Bar[0].close + sp);
            if(d * (m1Fav - m_slots[i].extremePx) > 0.0)
               m_slots[i].extremePx = m1Fav;

            double barFavUsd = d * (m1Fav - px0) + (d == 1 ? 0.18 : 0.0);
            double barAdvUsd = d * (px0 - m1Adv);
            if(barFavUsd > m_slots[i].mfeFavUsd)
               m_slots[i].mfeFavUsd = barFavUsd;
            if(barAdvUsd > m_slots[i].maeAdvUsd)
               m_slots[i].maeAdvUsd = barAdvUsd;

            long   elapsedSec    = (long)(srvNow - m_slots[i].openSrv);
            double mfeR          = m_slots[i].mfeFavUsd / R;
            double maeR          = m_slots[i].maeAdvUsd / R;
            double clFavUsd      = d * (m1Cl - px0);
            double targetLockUsd = -1.0;

            if(!risk.m_moeGapFillMode && !m_slots[i].isProtected && maeR >= 0.15 && m_slots[i].maeAdvUsd >= 2.80)
              {
               double escTp = NormPrice(px0 + d * MathMax(0.25, 0.05 * R));
               if(((d == 1 && escTp < m_slots[i].tpPx - tickSz) ||
                   (d == -1 && escTp > m_slots[i].tpPx + tickSz)) &&
                  d * (escTp - favor) >= cushUsd)
                 {
                  if(m_trade.PositionModify(m_slots[i].ticket, m_slots[i].slPx, escTp))
                     m_slots[i].tpPx = escTp;
                 }
              }

            if(risk.m_moeGapFillMode)
              {
               // SEEN-Calibrated Breathing Harvester: lets coils develop into true >= 0.25R..6.0R runners
               long htfMult = (m_slots[i].stream <= 2) ? 2 : 1;
               if(mfeR >= 0.60 && clFavUsd >= 0.28 * R)
                  targetLockUsd = MathMax(0.25, 0.28 * R);
               else if(elapsedSec >= (900 * htfMult) && mfeR >= 0.32)
                  targetLockUsd = MathMax(0.22, 0.10 * R);
               else if(elapsedSec >= (1800 * htfMult) && mfeR >= 0.22)
                  targetLockUsd = MathMax(0.22, 0.08 * R);
               else if(elapsedSec >= (3600 * htfMult) && mfeR >= 0.16)
                  targetLockUsd = MathMax(0.22, 0.06 * R);
              }
            else
              {
               if(mfeR >= 0.45 && clFavUsd >= 0.25 * R)
                  targetLockUsd = MathMax(0.25, 0.25 * R);
               else if(elapsedSec >= 300 && mfeR >= 0.22)
                  targetLockUsd = MathMax(0.22, 0.08 * R);
               else if(elapsedSec >= 900 && mfeR >= 0.16)
                  targetLockUsd = MathMax(0.22, 0.06 * R);
               else if(elapsedSec >= 2100 && mfeR >= 0.11)
                  targetLockUsd = MathMax(0.22, 0.05 * R);
              }

            if(targetLockUsd > 0.0 && clFavUsd >= (targetLockUsd + cushUsd) && d * (favor - px0) >= (targetLockUsd + cushUsd))
              {
               double candBeSl = NormPrice(px0 + d * targetLockUsd);
               if(d * (candBeSl - m_slots[i].slPx) > tickSz)
                 {
                  if(m_trade.PositionModify(m_slots[i].ticket, candBeSl, m_slots[i].tpPx))
                    {
                     m_slots[i].slPx        = candBeSl;
                     m_slots[i].isProtected = true;
                    }
                 }
              }

            if(d * (m_slots[i].extremePx - px0) >= m_trailActR * R && m_slots[i].trailDist > 0.0)
              {
               double lvl = NormPrice(m_slots[i].extremePx - d * m_slots[i].trailDist);
               if(d * (lvl - m_slots[i].slPx) > tickSz &&
                  d * (m1Cl - lvl) >= cushUsd &&
                  d * (favor - lvl) >= cushUsd)
                 {
                  if(m_trade.PositionModify(m_slots[i].ticket, lvl, m_slots[i].tpPx))
                    {
                     m_slots[i].slPx = lvl;
                     if(d * (lvl - px0) > 0.15)
                        m_slots[i].isProtected = true;
                    }
                 }
              }
           }

         //--- 3. Time stop
         int maxMin = (m_slots[i].isWhale || m_slots[i].isProtected) ? m_whaleHoldMin : m_maxHoldMin;
         if(maxMin > 0 && (srvNow - m_slots[i].openSrv) >= maxMin * 60)
           {
            m_trade.SetExpertMagicNumber(m_slots[i].magic);
            m_trade.PositionClose(m_slots[i].ticket, 50);
            ClearSlot(i);
           }
        }
     }
  };

#endif
