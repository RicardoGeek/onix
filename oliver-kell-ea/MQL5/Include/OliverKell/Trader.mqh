//+------------------------------------------------------------------+
//| Trader.mqh - OliverKell v1.00 Multi-Slot Execution & Scale-In    |
//|                                                                  |
//| Implements:                                                      |
//|  * Up to 3 concurrent stream probes (H1, H2, M30, M15, M5)       |
//|    with 2 slots reserved for HTF (H1/H2/M30/M15) in Prop mode    |
//|    and 1 reserved in Growth Moonshot mode.                       |
//|  * Completed-M1-bar ATR trailing stop (2.0 ATR(H1), widening     |
//|    to 3.0 ATR(H1) after +1.50R Whale promotion) across EVERY     |
//|    active ticket (probes, scale-in adds, and >50 lot splits).    |
//|  * Stage-1 Scale-In at +1.50R (probe SL -> BE+0.05R, TP ->       |
//|    5.0R Prop / 7.0R Growth Moonshot; Add #1 with SL at 0.0R).    |
//|  * Stage-2 Scale-In at +2.75R (probe & Add #1 SL -> +1.60R,      |
//|    Add #2 with 0.5x weight and SL at +1.50R).                    |
//+------------------------------------------------------------------+
#ifndef OLIVERKELL_TRADER_MQH
#define OLIVERKELL_TRADER_MQH

#include <Trade\Trade.mqh>
#include "Clock.mqh"
#include "Streams.mqh"
#include "RiskEngine.mqh"

#define OK_MAX_SLOTS 16

struct SOkSlot
  {
   bool              active;
   ulong             ticket;
   int               stream;
   int               setupId;
   int               dir;
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

class COkTrader
  {
private:
   CTrade            m_trade;
   string            m_sym;
   ulong             m_magic;
   double            m_slAtrMult;
   double            m_trailAtrMult;
   double            m_tpR;
   double            m_whaleTpR;
   double            m_growthWhaleTpR;
   double            m_beAtR;
   double            m_beLockR;
   double            m_stage2AtR;
   double            m_stage2LockR;
   double            m_whaleTrailMult;
   double            m_trailActR;
   int               m_maxHoldMin;
   int               m_whaleHoldMin;

public:
   int               m_logH;
   SOkSlot           m_slots[OK_MAX_SLOTS];

                     COkTrader(void) : m_logH(INVALID_HANDLE),
                                       m_slAtrMult(2.50), m_trailAtrMult(2.00),
                                       m_tpR(3.00), m_whaleTpR(6.00), m_growthWhaleTpR(7.00),
                                       m_beAtR(0.85), m_beLockR(0.55),
                                       m_stage2AtR(1.80), m_stage2LockR(1.40),
                                       m_whaleTrailMult(1.50), m_trailActR(0.85),
                                       m_maxHoldMin(2880), m_whaleHoldMin(2880) {}

   void              Init(const string sym, ulong magic)
     {
      m_sym   = sym;
      m_magic = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(30);
      m_trade.SetTypeFillingBySymbol(sym);

      for(int i = 0; i < OK_MAX_SLOTS; i++)
         ClearSlot(i);
     }

   void              ClearSlot(int idx)
     {
      m_slots[idx].active       = false;
      m_slots[idx].ticket       = 0;
      m_slots[idx].stream       = -1;
      m_slots[idx].setupId      = -1;
      m_slots[idx].dir          = 0;
      m_slots[idx].isAdd        = false;
      m_slots[idx].parentTicket = 0;
      m_slots[idx].isWhale      = false;
      m_slots[idx].isProtected  = false;
      m_slots[idx].added        = false;
      m_slots[idx].added2       = false;
      m_slots[idx].convMult     = 1.0;
      m_slots[idx].entryPx      = 0.0;
      m_slots[idx].initR        = 0.0;
      m_slots[idx].slPx         = 0.0;
      m_slots[idx].tpPx         = 0.0;
      m_slots[idx].trailDist    = 0.0;
      m_slots[idx].extremePx    = 0.0;
      m_slots[idx].mfeFavUsd    = 0.0;
      m_slots[idx].maeAdvUsd    = 0.0;
      m_slots[idx].openSrv      = 0;
      m_slots[idx].lastTrailM1  = 0;
     }

   double            NormPrice(double px) const
     {
      double tickSz = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      int    digits = (int)SymbolInfoInteger(m_sym, SYMBOL_DIGITS);
      if(tickSz <= 0.0)
         return NormalizeDouble(px, digits);
      return NormalizeDouble(MathRound(px / tickSz) * tickSz, digits);
     }

   void              LogClosed(const SOkSlot &s)
     {
      if(m_logH == INVALID_HANDLE || s.ticket == 0)
         return;
      if(!HistorySelectByPosition(s.ticket))
         return;

      int n = HistoryDealsTotal();
      double net = 0.0, lots = 0.0, exitPx = s.entryPx;
      datetime exitTm = TimeCurrent();
      int outs = 0, winOuts = 0;

      for(int i = 0; i < n; i++)
        {
         ulong dTk = HistoryDealGetTicket(i);
         if(dTk == 0) continue;
         long entryType = HistoryDealGetInteger(dTk, DEAL_ENTRY);
         double dVol    = HistoryDealGetDouble(dTk, DEAL_VOLUME);
         double dPnL    = HistoryDealGetDouble(dTk, DEAL_PROFIT)
                        + HistoryDealGetDouble(dTk, DEAL_COMMISSION)
                        + HistoryDealGetDouble(dTk, DEAL_SWAP);
         net += dPnL;
         if(entryType == DEAL_ENTRY_IN)
            lots += dVol;
         else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
           {
            outs++;
            if(dPnL > 0.0) winOuts++;
            exitPx = HistoryDealGetDouble(dTk, DEAL_PRICE);
            exitTm = (datetime)HistoryDealGetInteger(dTk, DEAL_TIME);
           }
        }
      if(outs == 0) return;

      string sName = (s.stream >= 0 && s.stream < OK_NSTREAMS) ? OK_STREAM_NAMES[s.stream] : "UNK";
      if(s.isAdd) sName += "+";
      string rName = (s.setupId >= 0 && s.setupId < OK_NSETUPS) ? OK_SETUP_NAMES[s.setupId] : "UNK";
      double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
      double rReal = (s.initR > 0.0) ? ((exitPx - s.entryPx) * s.dir / s.initR) : 0.0;

      FileWrite(m_logH,
                s.ticket,
                sName, rName, s.dir,
                TimeToString(s.openSrv, TIME_DATE | TIME_SECONDS),
                TimeToString(exitTm, TIME_DATE | TIME_SECONDS),
                DoubleToString(lots, 2),
                DoubleToString(rReal, 2),
                DoubleToString(net, 2),
                outs, winOuts,
                DoubleToString(bal, 2));
      FileFlush(m_logH);
     }

   void              ReconcileWithBroker(void)
     {
      for(int i = 0; i < OK_MAX_SLOTS; i++)
        {
         if(!m_slots[i].active) continue;
         if(!PositionSelectByTicket(m_slots[i].ticket))
           {
            LogClosed(m_slots[i]);
            ClearSlot(i);
           }
        }
     }

   int               Probes(void) const
     {
      int c = 0;
      for(int i = 0; i < OK_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd) c++;
      return c;
     }

   int               UnprotectedProbes(void) const
     {
      int c = 0;
      for(int i = 0; i < OK_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd && !m_slots[i].isProtected) c++;
      return c;
     }

   bool              StreamHasProbe(int s) const
     {
      if(UnprotectedProbes() >= 1)
         return true;
      for(int i = 0; i < OK_MAX_SLOTS; i++)
         if(m_slots[i].active && !m_slots[i].isAdd && m_slots[i].stream == s && !m_slots[i].isProtected)
            return true;
      return false;
     }

   //--- Magic-Number-Agnostic Surroundings Guard (The 3 Musketeers Co-Existence)
   //--- 1. Blocks ANY opposite-direction position or pending order on m_sym (0% hedging)
   //--- 2. When respectExternal is true, yields if another EA (Sniper/16Runes) has an
   //---    unprotected position on m_sym or opened a position within the last 180s.
   bool              CheckSurroundings(int dir, bool respectExternal, datetime srvNow, string &outReason) const
     {
      outReason = "";
      int totalPos = PositionsTotal();
      for(int p = 0; p < totalPos; p++)
        {
         ulong tk = PositionGetTicket(p);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         ulong  mgk   = (ulong)PositionGetInteger(POSITION_MAGIC);
         int    pDir  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         double opx   = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         datetime pTm = (datetime)PositionGetInteger(POSITION_TIME);
         if(pDir != dir)
           {
            outReason = (mgk == m_magic) ? "own-opposite" : "ext-opposite-no-hedge";
            return false;
           }
         if(mgk != m_magic && respectExternal)
           {
            bool isExtProt = (sl > 0.0 && pDir * (sl - opx) > 0.02);
            if(!isExtProt || (srvNow - pTm) < 180)
              {
               outReason = "ext-musketeer-active";
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
            outReason = "ext-pending-opposite";
            return false;
           }
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic && respectExternal)
           {
            outReason = "ext-pending-active";
            return false;
           }
        }
      return true;
     }

   void              OpenExposure(const COkRisk &risk, double &openStopRiskUsd, double &openMarginUsed) const
     {
      openStopRiskUsd = 0.0;
      openMarginUsed  = 0.0;
      int totalPos = PositionsTotal();
      for(int p = 0; p < totalPos; p++)
        {
         ulong tk = PositionGetTicket(p);
         if(tk == 0 || !PositionSelectByTicket(tk))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym)
            continue;
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
      for(int i = 0; i < OK_MAX_SLOTS; i++)
        {
         if(!m_slots[i].active) continue;
         if(PositionSelectByTicket(m_slots[i].ticket))
           {
            PrintFormat("[oliver_kell_ea] Liquidating #%I64u (%s)", m_slots[i].ticket, reason);
            m_trade.PositionClose(m_slots[i].ticket, 50);
           }
         LogClosed(m_slots[i]);
         ClearSlot(i);
        }
     }

   bool              ExecuteMarketTicket(int dir, double lots, double slPx, double tpPx,
                                         const string cmt, ulong &outPosTk, double &outFillPx)
     {
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

   bool              OpenProbe(int stream, int setupId, int dir, double h1Atr, double convMult,
                               const COkRisk &risk, datetime srvNow)
     {
      if(!risk.CanOpenStream(stream, Probes()))
         return false;
      if(StreamHasProbe(stream))
         return false;
      if(h1Atr <= 0.1)
         return false;

      int slot = -1;
      for(int i = 0; i < OK_MAX_SLOTS; i++)
         if(!m_slots[i].active) { slot = i; break; }
      if(slot < 0)
         return false;

      double ask = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double fillEst = (dir == 1) ? ask : bid;

      double R     = MathMax(1.50, m_slAtrMult * h1Atr);
      double tdist = m_trailAtrMult * h1Atr;
      double slPx  = NormPrice(fillEst - dir * R);
      double tpPx  = NormPrice(fillEst + dir * m_tpR * R);

      double openRisk = 0.0, openMar = 0.0;
      OpenExposure(risk, openRisk, openMar);
      double effWeight = OK_STREAM_WEIGHTS[stream] * convMult;
      double totalLots = risk.OrderLots(dir, fillEst, slPx, effWeight, openRisk, openMar);
      if(totalLots <= 0.0)
         return false;

      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double minLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(maxLot <= 0.0)  maxLot  = 50.0;
      if(minLot <= 0.0)  minLot  = 0.01;
      if(stepLot <= 0.0) stepLot = 0.01;
      int lotDigits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);

      double lots1 = NormalizeDouble(MathMin(totalLots, maxLot), lotDigits);
      string cmt   = StringFormat("OK_%s_%s", OK_STREAM_NAMES[stream], OK_SETUP_NAMES[setupId]);
      ulong  posTk = 0;
      double actualFill = 0.0;
      if(!ExecuteMarketTicket(dir, lots1, slPx, tpPx, cmt, posTk, actualFill))
         return false;

      double realSl = NormPrice(actualFill - dir * R);
      double realTp = NormPrice(actualFill + dir * m_tpR * R);
      if(PositionSelectByTicket(posTk))
        {
         if(MathAbs(realSl - slPx) >= SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE) ||
            MathAbs(realTp - tpPx) >= SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE))
            m_trade.PositionModify(posTk, realSl, realTp);
        }

      m_slots[slot].active       = true;
      m_slots[slot].ticket       = posTk;
      m_slots[slot].stream       = stream;
      m_slots[slot].setupId      = setupId;
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

      double remLots = NormalizeDouble(MathMin(totalLots - lots1, maxLot), lotDigits);
      if(remLots >= minLot)
        {
         int slot2 = -1;
         for(int i = 0; i < OK_MAX_SLOTS; i++)
            if(!m_slots[i].active) { slot2 = i; break; }
         if(slot2 >= 0)
           {
            ulong  posTk2 = 0;
            double fill2  = 0.0;
            if(ExecuteMarketTicket(dir, remLots, realSl, realTp, cmt + "_B", posTk2, fill2))
              {
               m_slots[slot2].active       = true;
               m_slots[slot2].ticket       = posTk2;
               m_slots[slot2].stream       = stream;
               m_slots[slot2].setupId      = setupId;
               m_slots[slot2].dir          = dir;
               m_slots[slot2].isAdd        = true;
               m_slots[slot2].parentTicket = posTk;
               m_slots[slot2].isWhale      = false;
               m_slots[slot2].isProtected  = false;
               m_slots[slot2].added        = true;
               m_slots[slot2].added2       = true;
               m_slots[slot2].convMult     = convMult;
               m_slots[slot2].entryPx      = actualFill;
               m_slots[slot2].initR        = R;
               m_slots[slot2].slPx         = realSl;
               m_slots[slot2].tpPx         = realTp;
               m_slots[slot2].trailDist    = tdist;
               m_slots[slot2].extremePx    = actualFill;
               m_slots[slot2].mfeFavUsd    = 0.0;
               m_slots[slot2].openSrv      = srvNow;
               m_slots[slot2].lastTrailM1  = iTime(m_sym, PERIOD_M1, 1);
              }
           }
        }
      return true;
     }

   bool              OpenWhaleAdd(int parentIdx, int stage, const COkRisk &risk, datetime srvNow)
     {
      if(!risk.m_allowPyramid || !risk.CanOpenNew())
         return false;
      int slot = -1;
      for(int i = 0; i < OK_MAX_SLOTS; i++)
         if(!m_slots[i].active) { slot = i; break; }
      if(slot < 0)
         return false;

      int    d       = m_slots[parentIdx].dir;
      int    stm     = m_slots[parentIdx].stream;
      int    sid     = m_slots[parentIdx].setupId;
      double R       = m_slots[parentIdx].initR;
      double px0     = m_slots[parentIdx].entryPx;
      double fillEst = (d == 1) ? SymbolInfoDouble(m_sym, SYMBOL_ASK) : SymbolInfoDouble(m_sym, SYMBOL_BID);

      double slPx = (stage == 1) ? NormPrice(px0 + d * MathMax(0.25, m_beLockR * R)) : NormPrice(px0 + d * m_stage2LockR * R);
      double tpPx = m_slots[parentIdx].tpPx;
      if(d * (fillEst - slPx) <= R * 0.25)
         return false;

      double openRisk = 0.0, openMar = 0.0;
      OpenExposure(risk, openRisk, openMar);
      double stageScale = (stage == 1) ? 0.85 : 0.55;
      double effWeight  = OK_STREAM_WEIGHTS[stm] * m_slots[parentIdx].convMult * stageScale;
      double totalLots  = risk.OrderLots(d, fillEst, slPx, effWeight, openRisk, openMar);
      if(totalLots <= 0.0)
         return false;

      double maxLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      double minLot  = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double stepLot = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      if(maxLot <= 0.0)  maxLot  = 50.0;
      if(minLot <= 0.0)  minLot  = 0.01;
      if(stepLot <= 0.0) stepLot = 0.01;
      int lotDigits = (stepLot >= 1.0) ? 0 : ((stepLot >= 0.1) ? 1 : 2);

      double lots1 = NormalizeDouble(MathMin(totalLots, maxLot), lotDigits);
      string cmt   = StringFormat("OK_%s_ADD%d", OK_STREAM_NAMES[stm], stage);
      ulong  posTk = 0;
      double actualFill = 0.0;
      if(!ExecuteMarketTicket(d, lots1, slPx, tpPx, cmt, posTk, actualFill))
         return false;

      m_slots[slot].active       = true;
      m_slots[slot].ticket       = posTk;
      m_slots[slot].stream       = stm;
      m_slots[slot].setupId      = sid;
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

      double remLots = NormalizeDouble(MathMin(totalLots - lots1, maxLot), lotDigits);
      if(remLots >= minLot)
        {
         int slot2 = -1;
         for(int i = 0; i < OK_MAX_SLOTS; i++)
            if(!m_slots[i].active) { slot2 = i; break; }
         if(slot2 >= 0)
           {
            ulong  posTk2 = 0;
            double fill2  = 0.0;
            if(ExecuteMarketTicket(d, remLots, slPx, tpPx, cmt + "B", posTk2, fill2))
              {
               m_slots[slot2].active       = true;
               m_slots[slot2].ticket       = posTk2;
               m_slots[slot2].stream       = stm;
               m_slots[slot2].setupId      = sid;
               m_slots[slot2].dir          = d;
               m_slots[slot2].isAdd        = true;
               m_slots[slot2].parentTicket = m_slots[parentIdx].ticket;
               m_slots[slot2].isWhale      = true;
               m_slots[slot2].isProtected  = true;
               m_slots[slot2].added        = true;
               m_slots[slot2].added2       = true;
               m_slots[slot2].convMult     = m_slots[parentIdx].convMult;
               m_slots[slot2].entryPx      = fill2;
               m_slots[slot2].initR        = R;
               m_slots[slot2].slPx         = slPx;
               m_slots[slot2].tpPx         = tpPx;
               m_slots[slot2].trailDist    = m_slots[parentIdx].trailDist;
               m_slots[slot2].extremePx    = fill2;
               m_slots[slot2].mfeFavUsd    = 0.0;
               m_slots[slot2].openSrv      = srvNow;
               m_slots[slot2].lastTrailM1  = iTime(m_sym, PERIOD_M1, 1);
              }
           }
        }
      return true;
     }

   void              Manage(const COkRisk &risk, datetime srvNow)
     {
      ReconcileWithBroker();
      double bid   = SymbolInfoDouble(m_sym, SYMBOL_BID);
      double ask   = SymbolInfoDouble(m_sym, SYMBOL_ASK);
      double tickSz = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      if(tickSz <= 0.0) tickSz = 0.01;
      int stopsLvl = (int)SymbolInfoInteger(m_sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = MathMax(tickSz * 2.0, stopsLvl * SymbolInfoDouble(m_sym, SYMBOL_POINT));

      datetime closedM1 = iTime(m_sym, PERIOD_M1, 1);
      MqlRates m1Bar[];
      bool hasM1 = (closedM1 > 0 && CopyRates(m_sym, PERIOD_M1, 1, 1, m1Bar) == 1);

      for(int i = 0; i < OK_MAX_SLOTS; i++)
        {
         if(!m_slots[i].active) continue;
         if(!PositionSelectByTicket(m_slots[i].ticket))
           {
            LogClosed(m_slots[i]);
            ClearSlot(i);
            continue;
           }

         int    d       = m_slots[i].dir;
         double R       = MathMax(1.50, m_slots[i].initR);
         double px0     = m_slots[i].entryPx;
         double favor   = (d == 1) ? bid : ask;
         double cushUsd = MathMax(0.25, MathMax(minStopDist + 0.05, 0.035 * R));

         if(d * (favor - m_slots[i].extremePx) > 0.0)
            m_slots[i].extremePx = favor;

         //--- 1a. Stage-1 Whale Promotion at +1.40R
         if(!m_slots[i].isWhale && d * (favor - px0) >= m_beAtR * R)
           {
            m_slots[i].isWhale   = true;
            m_slots[i].trailDist = m_slots[i].trailDist * m_whaleTrailMult;
            double targetTpR = (risk.m_mode == OK_HOUSE_MONEY_GROWTH) ? m_growthWhaleTpR : m_whaleTpR;
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

         //--- 1b. Stage-2 Scale-In at +2.60R
         if(m_slots[i].isWhale && !m_slots[i].isAdd && !m_slots[i].added2 &&
            risk.m_allowTwoStagePyr && d * (favor - px0) >= m_stage2AtR * R)
           {
            m_slots[i].added2 = true;
            double lockSl = NormPrice(px0 + d * m_stage2LockR * R);
            if(d * (lockSl - m_slots[i].slPx) > tickSz && d * (favor - lockSl) >= cushUsd)
              {
               if(m_trade.PositionModify(m_slots[i].ticket, lockSl, m_slots[i].tpPx))
                 {
                  m_slots[i].slPx        = lockSl;
                  m_slots[i].isProtected = true;
                 }
              }
            for(int k = 0; k < OK_MAX_SLOTS; k++)
              {
               if(m_slots[k].active && m_slots[k].isAdd && m_slots[k].parentTicket == m_slots[i].ticket)
                 {
                  if(d * (lockSl - m_slots[k].slPx) > tickSz && d * (favor - lockSl) >= cushUsd)
                    {
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

         //--- 2. Completed-M1-bar PureBE Harvester (Stage 0) & ATR trailing stop
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

            //--- Underwater Escape: if unprotected probe dips >= 0.15R (and >= $2.80), lower TP to +0.06R
            if(!m_slots[i].isProtected && maeR >= 0.15 && m_slots[i].maeAdvUsd >= 2.80)
              {
               double escTp = NormPrice(px0 + d * MathMax(0.25, 0.06 * R));
               if(((d == 1 && escTp < m_slots[i].tpPx - tickSz) ||
                   (d == -1 && escTp > m_slots[i].tpPx + tickSz)) &&
                  d * (escTp - favor) >= cushUsd)
                 {
                  if(m_trade.PositionModify(m_slots[i].ticket, m_slots[i].slPx, escTp))
                     m_slots[i].tpPx = escTp;
                 }
              }

            if(mfeR >= 0.45 && clFavUsd >= 0.25 * R)
               targetLockUsd = MathMax(0.25, 0.25 * R);
            else if(elapsedSec >= 300 && mfeR >= 0.22)
               targetLockUsd = MathMax(0.22, 0.10 * R);
            else if(elapsedSec >= 900 && mfeR >= 0.16)
               targetLockUsd = MathMax(0.22, 0.08 * R);
            else if(elapsedSec >= 2100 && mfeR >= 0.12)
               targetLockUsd = MathMax(0.22, 0.06 * R);

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
               double candSl = NormPrice(m_slots[i].extremePx - d * m_slots[i].trailDist);
               if(d * (candSl - m_slots[i].slPx) > tickSz &&
                  d * (m1Cl - candSl) >= cushUsd &&
                  d * (favor - candSl) >= cushUsd)
                 {
                  if(m_trade.PositionModify(m_slots[i].ticket, candSl, m_slots[i].tpPx))
                    {
                     m_slots[i].slPx = candSl;
                     if(d * (candSl - px0) > 0.15)
                        m_slots[i].isProtected = true;
                    }
                 }
              }
           }

         //--- 3. Time stop (12h unprotected / 48h Protected & Whale)
         int maxMin = (m_slots[i].isWhale || m_slots[i].isProtected) ? m_whaleHoldMin : m_maxHoldMin;
         if(maxMin > 0 && (srvNow - m_slots[i].openSrv) >= maxMin * 60)
           {
            m_trade.PositionClose(m_slots[i].ticket, 50);
            LogClosed(m_slots[i]);
            ClearSlot(i);
           }
        }
     }
  };

#endif // OLIVERKELL_TRADER_MQH
