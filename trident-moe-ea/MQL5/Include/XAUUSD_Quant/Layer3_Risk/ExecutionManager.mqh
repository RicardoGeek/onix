//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 3 Risk: CTrade Wrapper, Limit Expiry, TP1 @ VPOC & Trail  |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict
#ifndef XAUUSD_QUANT_EXECUTION_MANAGER_MQH
#define XAUUSD_QUANT_EXECUTION_MANAGER_MQH
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "EquityGuard.mqh"
#include "PositionSizer.mqh"
//+------------------------------------------------------------------+
//| CExecutionManager: Institutional Sniper Order & Position Engine  |
//+------------------------------------------------------------------+
struct SPositionRatchetState
  {
   ulong    ticket;
   datetime lastRatchetM1BarTime;
   double   closedBarMaxFavUSD;
   double   allBarMaxFavUSD;
   double   initialRiskUSD;
   bool     isPrimeSetup;
   bool     isStrongWave;
   void Reset()
     {
      ticket               = 0;
      lastRatchetM1BarTime = 0;
      closedBarMaxFavUSD   = 0.0;
      allBarMaxFavUSD      = 0.0;
      initialRiskUSD       = 0.0;
      isPrimeSetup         = true;
      isStrongWave         = false;
     }
  };
class CExecutionManager
  {
private:
   string                m_symbol;
   ulong                 m_magic;
   ulong                 m_deviationPoints;
   double                m_commissionPerLotRoundTurn;
   int                   m_verticalBarrierSeconds;
   bool                  m_enableVerticalBarrier;
   int                   m_lowDDExpiryM5Bars;
   CTrade                m_trade;
   CPositionInfo         m_posInfo;
   COrderInfo            m_ordInfo;
   CEquityGuard         *m_equityGuard;
   CPositionSizer       *m_positionSizer;
   CQuantLogger         *m_logger;
   SActiveTradeContext   m_ctx;
   SSweepCandidateSetup  m_lastSetup;
   SOnnxPrediction       m_lastPrediction;
   double                m_accumulatedRealizedPnL;
   datetime              m_lastRatchetM1BarTime;
   double                m_closedBarMaxFavUSD;
   double                m_allBarMaxFavUSD;
   SPositionRatchetState m_ratchetStates[8];
   int                   FindOrAllocRatchetSlot(const ulong posTicket, const bool isPrime = true, const bool isStrong = false, const double initRiskUSD = 0.0)
     {
      for(int i = 0; i < 8; i++)
        {
         if(m_ratchetStates[i].ticket == posTicket)
           {
            if(initRiskUSD > 0.0 && m_ratchetStates[i].initialRiskUSD <= 0.0)
               m_ratchetStates[i].initialRiskUSD = initRiskUSD;
            return i;
           }
        }
      for(int i = 0; i < 8; i++)
        {
         if(m_ratchetStates[i].ticket == 0 || !PositionSelectByTicket(m_ratchetStates[i].ticket))
           {
            m_ratchetStates[i].Reset();
            m_ratchetStates[i].ticket         = posTicket;
            m_ratchetStates[i].isPrimeSetup   = isPrime;
            m_ratchetStates[i].isStrongWave   = isStrong;
            m_ratchetStates[i].initialRiskUSD = initRiskUSD;
            return i;
           }
        }
      m_ratchetStates[0].Reset();
      m_ratchetStates[0].ticket         = posTicket;
      m_ratchetStates[0].isPrimeSetup   = isPrime;
      m_ratchetStates[0].isStrongWave   = isStrong;
      m_ratchetStates[0].initialRiskUSD = initRiskUSD;
      return 0;
     }
   bool                  ValidateModifyDistanceForDir(const ENUM_SIGNAL_DIRECTION dir,
                                                      const double targetSL,
                                                      const double targetTP) const
     {
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
         tickSize = (point > 0.0 ? point : 0.01);
      long   stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long   freezeLvl  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist    = MathMax((double)MathMax(stopsLevel, freezeLvl) * point, 2.0 * tickSize);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(dir == SIGNAL_LONG)
        {
         if(targetSL > 0.0 && (bid - targetSL) < minDist) return false;
         if(targetTP > 0.0 && (targetTP - bid) < minDist) return false;
        }
      else if(dir == SIGNAL_SHORT)
        {
         if(targetSL > 0.0 && (targetSL - ask) < minDist) return false;
         if(targetTP > 0.0 && (ask - targetTP) < minDist) return false;
        }
      return true;
     }
   bool                  m_hasUnconsumedOutcome;
   ENUM_SIGNAL_DIRECTION m_lastClosedDirection;
   double                m_lastClosedRealizedR;
   //--- Compute price offset required to cover round-turn commission + 5-point cushion
   double                ComputeBreakevenOffsetPrice() const
     {
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0)
         tickSize = 0.01;
      if(tickValue <= 0.0)
         tickValue = 1.0;
      double commissionTicks = (m_commissionPerLotRoundTurn / tickValue);
      double commissionPrice = commissionTicks * tickSize;
      double safetyCushion   = 5.0 * tickSize; // $0.05 cushion on XAUUSD
      return NormalizeSymbolPrice(m_symbol, commissionPrice + safetyCushion);
     }
   //--- Enforce broker StopsLevel, FreezeLevel & TickSize constraints before order modification
   bool                  ValidateModifyDistance(const double targetSL, const double targetTP) const
     {
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
         tickSize = (point > 0.0 ? point : 0.01);
      long   stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long   freezeLvl  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist    = MathMax((double)MathMax(stopsLevel, freezeLvl) * point, 2.0 * tickSize);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(m_ctx.direction == SIGNAL_LONG)
        {
         if(targetSL > 0.0 && (bid - targetSL) < minDist)
            return false;
         if(targetTP > 0.0 && (targetTP - bid) < minDist)
            return false;
        }
      else if(m_ctx.direction == SIGNAL_SHORT)
        {
         if(targetSL > 0.0 && (targetSL - ask) < minDist)
            return false;
         if(targetTP > 0.0 && (ask - targetTP) < minDist)
            return false;
        }
      return true;
     }
   //--- Compute structural M5 swing trail stop loss once TP1 is secured
   bool                  ComputeM5SwingTrailSL(double &outNewSL) const
     {
      outNewSL = 0.0;
      if(!m_ctx.tp1Executed)
         return false;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, 1, 12, rates);
      if(copied < 6)
         return false;
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
         tickSize = 0.01;
      double bufferUSD = 0.15; // $0.15 structural trail buffer
      // Search most recent confirmed 3-bar M5 swing low (for LONG) or swing high (for SHORT)
      if(m_ctx.direction == SIGNAL_LONG)
        {
         for(int i = 1; i <= copied - 3; i++)
           {
            if(rates[i].low < rates[i - 1].low && rates[i].low <= rates[i + 1].low)
              {
               double candidateSL = NormalizeSymbolPrice(m_symbol, rates[i].low - bufferUSD);
               if(candidateSL > m_ctx.currentStopLoss && candidateSL > m_ctx.actualEntryPrice)
                 {
                  outNewSL = candidateSL;
                  return true;
                 }
              }
           }
        }
      else if(m_ctx.direction == SIGNAL_SHORT)
        {
         for(int i = 1; i <= copied - 3; i++)
           {
            if(rates[i].high > rates[i - 1].high && rates[i].high >= rates[i + 1].high)
              {
               double candidateSL = NormalizeSymbolPrice(m_symbol, rates[i].high + bufferUSD);
               if(candidateSL < m_ctx.currentStopLoss && candidateSL < m_ctx.actualEntryPrice)
                 {
                  outNewSL = candidateSL;
                  return true;
                 }
              }
           }
        }
      return false;
     }
public:
                         CExecutionManager()
     {
      m_symbol                    = _Symbol;
      m_magic                     = QUANT_DEFAULT_MAGIC;
      m_deviationPoints           = 30;
      m_commissionPerLotRoundTurn = 7.0;
      m_verticalBarrierSeconds    = 4 * 3600; // 4-hour vertical time barrier
      m_enableVerticalBarrier     = true;
      m_lowDDExpiryM5Bars         = 6;
      m_equityGuard               = NULL;
      m_positionSizer             = NULL;
      m_logger                    = NULL;
      m_accumulatedRealizedPnL    = 0.0;
      m_hasUnconsumedOutcome      = false;
      m_lastClosedDirection       = SIGNAL_NONE;
      m_lastClosedRealizedR       = 0.0;
      m_ctx.Reset();
      m_lastSetup.Reset();
      m_lastPrediction.Reset();
     }
                        ~CExecutionManager() {}
   //--- Initialize Execution Manager
   bool                  Init(const string symbol,
                              const ulong magic,
                              const ulong deviationPoints,
                              const double commissionPerLotRoundTurn,
                              const bool enableVerticalTimeBarrier,
                              const int verticalBarrierHours,
                              CEquityGuard *equityGuard,
                              CPositionSizer *positionSizer,
                              CQuantLogger *logger)
     {
      m_symbol                    = symbol;
      m_magic                     = magic;
      m_deviationPoints           = deviationPoints;
      m_commissionPerLotRoundTurn = MathMax(0.0, commissionPerLotRoundTurn);
      m_enableVerticalBarrier     = enableVerticalTimeBarrier;
      m_verticalBarrierSeconds    = MathMax(1, verticalBarrierHours) * 3600;
      m_equityGuard               = equityGuard;
      m_positionSizer             = positionSizer;
      m_logger                    = logger;
      m_hasUnconsumedOutcome      = false;
      m_lastClosedDirection       = SIGNAL_NONE;
      m_lastClosedRealizedR       = 0.0;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_deviationPoints);
      m_trade.SetTypeFillingBySymbol(m_symbol);
      m_trade.SetAsyncMode(false);
      m_ctx.Reset();
      SyncBrokerState();
      return true;
     }
   //--- Synchronize internal trade context with actual MT5 broker orders/positions
   void                  SyncBrokerState()
     {
      ulong foundOrderTicket = 0;
      ulong foundPosTicket   = 0;
      // 1. Scan active pending orders for this symbol & magic
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_magic)
           {
            foundOrderTicket = ticket;
            break;
           }
        }
      // 2. Scan open positions for this symbol & magic
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
           {
            foundPosTicket = ticket;
            break;
           }
        }
      // Handle transition from Pending Limit Order -> Open Position
      if(m_ctx.hasPendingOrder && foundOrderTicket == 0 && foundPosTicket > 0)
        {
         if(m_posInfo.SelectByTicket(foundPosTicket))
           {
            m_ctx.hasPendingOrder  = false;
            m_ctx.hasOpenPosition  = true;
            m_ctx.positionTicket   = foundPosTicket;
            m_ctx.positionOpenTime = (datetime)m_posInfo.Time();
            m_ctx.actualEntryPrice = m_posInfo.PriceOpen();
            m_ctx.currentStopLoss  = m_posInfo.StopLoss();
            m_ctx.remainingLots    = m_posInfo.Volume();
            FindOrAllocRatchetSlot(foundPosTicket, m_lastSetup.isPrimeSetup, m_lastSetup.isStrongWave, m_ctx.initialRiskDistanceUSD);
            if(m_logger != NULL)
              {
               m_logger.Info(StringFormat(
                  "Sniper Limit Order FILLED -> Position #%I64u [%s %.2f lots @ %.2f | SL=%.2f | TP1=%.2f | TP2=%.2f]",
                  foundPosTicket, DirectionToString(m_ctx.direction),
                  m_ctx.remainingLots, m_ctx.actualEntryPrice,
                  m_ctx.currentStopLoss, m_ctx.tp1Price, m_ctx.tp2Price));
               m_logger.WriteTradeLifecycleCSV(
                  m_ctx.setupId, foundPosTicket, "LIMIT_FILLED", m_ctx.direction,
                  m_ctx.remainingLots, m_ctx.actualEntryPrice, m_ctx.currentStopLoss,
                  m_ctx.tp1Price, m_ctx.tp2Price, m_ctx.onnxProbability,
                  0.0, m_ctx.riskCapitalUSD, 0.0, 0.0, "Pending Limit Activated");
              }
           }
        }
      else if(foundPosTicket > 0 && m_ctx.hasOpenPosition)
        {
         // Refresh ticket & volume after 50% partial close at TP1 (hedging accounts assign a new ticket)
         if(m_posInfo.SelectByTicket(foundPosTicket))
           {
            m_ctx.positionTicket  = foundPosTicket;
            m_ctx.remainingLots   = m_posInfo.Volume();
            if(!m_ctx.movedToBreakeven && m_posInfo.StopLoss() > 0.0) m_ctx.currentStopLoss = m_posInfo.StopLoss();
           }
        }
      else if(foundPosTicket > 0 && !m_ctx.hasOpenPosition)
        {
         // Adopted existing open position after terminal restart
         if(m_posInfo.SelectByTicket(foundPosTicket))
           {
            m_ctx.hasOpenPosition        = true;
            m_ctx.hasPendingOrder        = false;
            m_ctx.positionTicket         = foundPosTicket;
            m_ctx.direction              = (m_posInfo.PositionType() == POSITION_TYPE_BUY)
                                           ? SIGNAL_LONG : SIGNAL_SHORT;
            m_ctx.positionOpenTime       = (datetime)m_posInfo.Time();
            m_ctx.actualEntryPrice       = m_posInfo.PriceOpen();
            m_ctx.plannedEntryPrice      = m_posInfo.PriceOpen();
            m_ctx.currentStopLoss        = m_posInfo.StopLoss();
            m_ctx.initialStopLoss        = m_posInfo.StopLoss();
            m_ctx.initialRiskDistanceUSD = MathMax(HARD_MIN_SL_DISTANCE_USD,
                                                   MathAbs(m_ctx.actualEntryPrice - m_ctx.initialStopLoss));
            m_ctx.tp2Price               = m_posInfo.TakeProfit();
            m_ctx.tp1Price               = (m_ctx.direction == SIGNAL_LONG)
                                           ? (m_ctx.actualEntryPrice + 2.0 * m_ctx.initialRiskDistanceUSD)
                                           : (m_ctx.actualEntryPrice - 2.0 * m_ctx.initialRiskDistanceUSD);
            m_ctx.initialLots            = m_posInfo.Volume();
            m_ctx.remainingLots          = m_posInfo.Volume();
           }
        }
      else if(foundOrderTicket > 0 && foundPosTicket == 0)
        {
         // Ensure live pending order is tracked even if OnTradeTransaction cleared context on same-tick exit
         m_ctx.hasPendingOrder    = true;
         m_ctx.hasOpenPosition    = false;
         m_ctx.pendingOrderTicket = foundOrderTicket;
        }
      else if(foundPosTicket == 0 && foundOrderTicket == 0)
        {
         if(m_ctx.hasPendingOrder || m_ctx.hasOpenPosition)
           {
            m_ctx.hasPendingOrder = false;
            m_ctx.hasOpenPosition = false;
           }
        }
     }
   //--- Return true if an active position or pending order currently exists
   bool                  HasActiveExposure()
     {
      SyncBrokerState();
      return (m_ctx.hasPendingOrder || m_ctx.hasOpenPosition);
     }
   void                  SetLowDDLimitExpiryBarsM5(const int bars) { m_lowDDExpiryM5Bars = (bars > 0 ? bars : 3); }
   bool                  HasPendingLimitOrder() const { return m_ctx.hasPendingOrder; }
   bool                  HasOpenPosition()      const { return m_ctx.hasOpenPosition; }
   bool                  CanOpenNewPosition(const ENUM_SIGNAL_DIRECTION candDir,
                                            const double candidateEntryPx)
     {
      SyncBrokerState();
      if(m_ctx.hasPendingOrder)
         return false;
      int      openCount             = 0;
      int      ownUnprotectedCount   = 0;
      int      totalUnprotectedCount = 0;
      datetime now                   = TimeCurrent();
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         ulong posMagic = (ulong)PositionGetInteger(POSITION_MAGIC);
         ENUM_SIGNAL_DIRECTION posDir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                                        ? SIGNAL_LONG : SIGNAL_SHORT;
         if(posDir != candDir)
            return false;
         datetime posTime   = (datetime)PositionGetInteger(POSITION_TIME);
         double   posOpenPx = PositionGetDouble(POSITION_PRICE_OPEN);
         double   posSL     = PositionGetDouble(POSITION_SL);
         bool isProtected   = (posDir == SIGNAL_LONG)
                              ? (posSL > posOpenPx + 0.01)
                              : (posSL > 0.0 && posSL < posOpenPx - 0.01);
         if(!isProtected)
           {
            totalUnprotectedCount++;
            if(posMagic == m_magic)
               ownUnprotectedCount++;
           }
         if(posMagic == m_magic)
           {
            openCount++;
            if(openCount >= 5)
               return false;
            if((now - posTime) < 480)
               return false;
            if(MathAbs(candidateEntryPx - posOpenPx) < 0.35)
               return false;
           }
         else
           {
            if((now - posTime) < 180)
               return false;
           }
        }
      if(ownUnprotectedCount >= 2 || totalUnprotectedCount >= 3)
         return false;
      for(int o = OrdersTotal() - 1; o >= 0; o--)
        {
         ulong otk = OrderGetTicket(o);
         if(otk == 0 || OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;
         ENUM_ORDER_TYPE oType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         ENUM_SIGNAL_DIRECTION ordDir = (oType == ORDER_TYPE_BUY || oType == ORDER_TYPE_BUY_LIMIT ||
                                         oType == ORDER_TYPE_BUY_STOP || oType == ORDER_TYPE_BUY_STOP_LIMIT)
                                        ? SIGNAL_LONG : SIGNAL_SHORT;
         if(ordDir != candDir)
            return false;
        }
      return true;
     }
   //+------------------------------------------------------------------+
   //| PlaceSniperLimitOrder                                            |
   //| Places strictly one BUY LIMIT or SELL LIMIT order at the FVG     |
   //| or VAL/VAH reclaim boundary with structural SL and TP targets.   |
   //+------------------------------------------------------------------+
   bool                  PlaceSniperLimitOrder(const SSweepCandidateSetup &setup,
                                               const SStationaryFeatures &features,
                                               const SOnnxPrediction &prediction,
                                               const SLotCalculationResult &lotResult)
     {
      SyncBrokerState();
      // Co-Existence Guard: Up to 3 Same-Direction Positions (>= 15m apart, > $0.50 separated)
      if(!CanOpenNewPosition(setup.direction, setup.entryLimitPrice))
        {
         if(m_logger != NULL)
            m_logger.Warn("PlaceSniperLimitOrder rejected by CanOpenNewPosition co-existence guard.");
         return false;
        }
      if(!setup.isValid || !lotResult.isAllowed || lotResult.finalLots <= 0.0)
         return false;
      double ask        = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid        = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      long   stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopUSD = (double)MathMax((int)stopsLevel, 5) * point;
      double entryPrice = NormalizeSymbolPrice(m_symbol, setup.entryLimitPrice);
      double slPrice    = NormalizeSymbolPrice(m_symbol, setup.stopLossPrice);
      double tp1Price   = NormalizeSymbolPrice(m_symbol, setup.tp1Price);
      double tp2Price   = NormalizeSymbolPrice(m_symbol, setup.tp2Price);
      double lots       = NormalizeSymbolLots(m_symbol, lotResult.finalLots);
      if(lots <= 0.0)
         return false;
      string comment = StringFormat("XAUQ_%I64u_P%.0f", setup.setupId, prediction.winProbability * 100.0);
      bool   placed  = false;
      bool   filledImmediately = false;
      // Verify market position margin right before sending (handles 1:30 / low-leverage prop accounts even if price moved)
      ENUM_ORDER_TYPE dealType = (setup.direction == SIGNAL_LONG) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double dealRefPrice      = (setup.direction == SIGNAL_LONG) ? MathMax(ask, entryPrice) : MathMax(bid, entryPrice);
      double freeMarginNow     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxSafeMarginNow  = freeMarginNow * 0.88;
      double minVol            = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double volStep           = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(volStep <= 0.0) volStep = 0.01;
      MqlTradeRequest chkReq;
      MqlTradeCheckResult chkRes;
      ZeroMemory(chkReq);
      ZeroMemory(chkRes);
      chkReq.action    = TRADE_ACTION_DEAL;
      chkReq.symbol    = m_symbol;
      chkReq.volume    = lots;
      chkReq.type      = dealType;
      chkReq.price     = (setup.direction == SIGNAL_LONG) ? ask : bid;
      chkReq.deviation = 30;
      bool chkOk       = OrderCheck(chkReq, chkRes);
      double reqMarginNow = (chkOk || chkRes.margin > 0.0) ? chkRes.margin : 0.0;
      double calcMarginNow = 0.0;
      if(OrderCalcMargin(dealType, m_symbol, lots, dealRefPrice, calcMarginNow))
         reqMarginNow = MathMax(reqMarginNow, calcMarginNow);
      if(reqMarginNow > maxSafeMarginNow && lots > minVol && reqMarginNow > 0.0)
        {
         double marginPerLotNow = reqMarginNow / lots;
         double clampedLots     = MathFloor(((maxSafeMarginNow / marginPerLotNow) + QUANT_EPSILON) / volStep) * volStep;
         lots = NormalizeSymbolLots(m_symbol, MathMax(minVol, clampedLots));
        }
      double maxMarketSlipUSD = 0.28;
      if(setup.direction == SIGNAL_LONG)
        {
         if(entryPrice > (ask + minStopUSD))
           {
            placed = m_trade.BuyStop(lots, entryPrice, m_symbol, slPrice, tp2Price,
                                     ORDER_TIME_GTC, 0, comment);
           }
         else if(MathAbs(ask - entryPrice) <= maxMarketSlipUSD)
           {
            entryPrice = NormalizeSymbolPrice(m_symbol, ask);
            slPrice    = NormalizeSymbolPrice(m_symbol, entryPrice - setup.slDistanceUSD);
            tp1Price   = NormalizeSymbolPrice(m_symbol, entryPrice + MathAbs(setup.tp1Price - setup.entryLimitPrice));
            tp2Price   = NormalizeSymbolPrice(m_symbol, entryPrice + MathAbs(setup.tp2Price - setup.entryLimitPrice));
            placed     = m_trade.Buy(lots, m_symbol, ask, slPrice, tp2Price, comment);
            filledImmediately = placed;
           }
         else if(entryPrice < (ask - minStopUSD))
           {
            placed = m_trade.BuyLimit(lots, entryPrice, m_symbol, slPrice, tp2Price,
                                      ORDER_TIME_GTC, 0, comment);
           }
        }
      else if(setup.direction == SIGNAL_SHORT)
        {
         if(entryPrice < (bid - minStopUSD))
           {
            placed = m_trade.SellStop(lots, entryPrice, m_symbol, slPrice, tp2Price,
                                      ORDER_TIME_GTC, 0, comment);
           }
         else if(MathAbs(entryPrice - bid) <= maxMarketSlipUSD)
           {
            entryPrice = NormalizeSymbolPrice(m_symbol, bid);
            slPrice    = NormalizeSymbolPrice(m_symbol, entryPrice + setup.slDistanceUSD);
            tp1Price   = NormalizeSymbolPrice(m_symbol, entryPrice - MathAbs(setup.entryLimitPrice - setup.tp1Price));
            tp2Price   = NormalizeSymbolPrice(m_symbol, entryPrice - MathAbs(setup.entryLimitPrice - setup.tp2Price));
            placed     = m_trade.Sell(lots, m_symbol, bid, slPrice, tp2Price, comment);
            filledImmediately = placed;
           }
         else if(entryPrice > (bid + minStopUSD))
           {
            placed = m_trade.SellLimit(lots, entryPrice, m_symbol, slPrice, tp2Price,
                                       ORDER_TIME_GTC, 0, comment);
           }
        }
      if(!placed)
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("Order placement failed [Retcode=%u (%s) | Dir=%s | Entry=%.2f | SL=%.2f | TP2=%.2f]",
                                        m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription(),
                                        DirectionToString(setup.direction), entryPrice, slPrice, tp2Price));
         return false;
        }
      // Initialize Active Trade Context
      m_ctx.Reset();
      m_lastSetup                     = setup;
      m_lastPrediction                = prediction;
      m_accumulatedRealizedPnL        = 0.0;
      m_lastRatchetM1BarTime          = 0;
      m_closedBarMaxFavUSD            = 0.0;
      m_allBarMaxFavUSD               = 0.0;
      m_ctx.setupId                   = setup.setupId;
      m_ctx.direction                 = setup.direction;
      m_ctx.sweptPoolType             = setup.sweptPoolType;
      m_ctx.orderPlacedTime           = TimeCurrent();
      m_ctx.orderPlacedM5BarTime      = iTime(m_symbol, PERIOD_M5, 0);
      m_ctx.expiryM5Bars              = (setup.expiryM5Bars > 0 ? setup.expiryM5Bars : 3);
      m_ctx.plannedEntryPrice         = entryPrice;
      m_ctx.actualEntryPrice          = (filledImmediately ? m_trade.ResultPrice() : entryPrice);
      m_ctx.initialStopLoss           = slPrice;
      m_ctx.currentStopLoss           = slPrice;
      m_ctx.initialRiskDistanceUSD    = MathAbs(entryPrice - slPrice);
      m_ctx.tp1Price                  = tp1Price;
      m_ctx.tp2Price                  = tp2Price;
      m_ctx.initialLots               = lots;
      m_ctx.remainingLots             = lots;
      m_ctx.riskCapitalUSD            = lotResult.totalRiskCapitalUSD;
      m_ctx.tp1Executed               = true;
      m_ctx.movedToBreakeven          = false;
      m_ctx.onnxProbability           = prediction.winProbability;
      m_ctx.riskTier                  = prediction.riskTier;
      m_ctx.setupFeatures             = features;
      if(filledImmediately)
        {
         m_ctx.hasPendingOrder        = false;
         m_ctx.hasOpenPosition        = true;
         m_ctx.positionTicket         = m_trade.ResultOrder();
         m_ctx.positionOpenTime       = TimeCurrent();
         FindOrAllocRatchetSlot(m_trade.ResultOrder(), setup.isPrimeSetup, setup.isStrongWave, m_ctx.initialRiskDistanceUSD);
         SyncBrokerState();
        }
      else
        {
         m_ctx.hasPendingOrder        = true;
         m_ctx.hasOpenPosition        = false;
         m_ctx.pendingOrderTicket     = m_trade.ResultOrder();
        }
      if(m_logger != NULL)
        {
         m_logger.Info(StringFormat(
            "Sniper %s Placed [Ticket=#%I64u | SetupID=%I64u | Lots=%.2f | Entry=%.2f | SL=%.2f ($%.2f) | TP1=%.2f | TP2=%.2f | ONNX P=%.3f]",
            (filledImmediately ? "MARKET EXECUTION" : "LIMIT ORDER"),
            m_trade.ResultOrder(), setup.setupId, lots, entryPrice, slPrice,
            m_ctx.initialRiskDistanceUSD, tp1Price, tp2Price, prediction.winProbability));
         m_logger.WriteTradeLifecycleCSV(
            setup.setupId, m_trade.ResultOrder(),
            (filledImmediately ? "MARKET_ENTRY" : "LIMIT_PLACED"),
            setup.direction, lots, entryPrice, slPrice, tp1Price, tp2Price,
            prediction.winProbability, lotResult.effectiveRiskPct,
            lotResult.totalRiskCapitalUSD, lotResult.houseMoneyBonusUSD, 0.0,
            LiquidityTypeToString(setup.sweptPoolType));
        }
      return true;
     }
   //+------------------------------------------------------------------+
   //| ManageActiveTradesOnTick                                         |
   //| Evaluates pending order expiry (3 M5 bars or +1.5R runaway) and  |
   //| manages open position partial TP1 @ VPOC, BE+Comm, & M5 trail.   |
   //+------------------------------------------------------------------+
   void                  ManageActiveTradesOnTick()
     {
      SyncBrokerState();
      // --- A. Manage Pending Sniper Stop/Limit Order ---
      if(m_ctx.hasPendingOrder && m_ctx.pendingOrderTicket > 0)
        {
         bool   shouldCancel = false;
         string cancelReason = "";
         // 1. Check M5 bar expiration (6 M5 bars / 30m while Daily DD < 1.00%, else 3 M5 bars / 15m)
         int effExpiryBars = m_ctx.expiryM5Bars;
         if(m_lowDDExpiryM5Bars > effExpiryBars && m_equityGuard != NULL &&
            m_equityGuard.GetCurrentDailyDrawdownPct() < 1.00)
           {
            effExpiryBars = m_lowDDExpiryM5Bars;
           }
         int barShift = iBarShift(m_symbol, PERIOD_M5, m_ctx.orderPlacedM5BarTime, false);
         if(barShift >= effExpiryBars ||
            (TimeCurrent() - m_ctx.orderPlacedTime) >= (effExpiryBars * 300))
           {
            shouldCancel = true;
            cancelReason = StringFormat("Expired after %d M5 bars without fill", effExpiryBars);
           }
         // 2. Cancel if an off-peak hour starts while stop order is unfilled
         if(!shouldCancel)
           {
            MqlDateTime dtSrv;
            TimeToStruct(TimeCurrent(), dtSrv);
            int hr = dtSrv.hour;
            bool isPrimeHr = (hr != 0 && hr != 1 && hr != 2 && hr != 4 && hr != 6 &&
                              hr != 14 && hr != 18 && hr != 21);
            if(!isPrimeHr)
              {
               shouldCancel = true;
               cancelReason = "Off-peak hour shield activated";
              }
           }
         // 3. Cancel if price backed away from the stop trigger by more than 0.65R
         if(!shouldCancel && m_ctx.initialRiskDistanceUSD > 0.0)
           {
            double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            double maxBackoff = 0.65 * m_ctx.initialRiskDistanceUSD;
            if(m_ctx.direction == SIGNAL_LONG && (m_ctx.plannedEntryPrice - ask) >= maxBackoff)
              {
               shouldCancel = true;
               cancelReason = "Price backed away from BuyStop trigger";
              }
            else if(m_ctx.direction == SIGNAL_SHORT && (bid - m_ctx.plannedEntryPrice) >= maxBackoff)
              {
               shouldCancel = true;
               cancelReason = "Price backed away from SellStop trigger";
              }
           }
         // 4. Check if Rollover Blackout or High-Impact News window started while order is resting
         if(!shouldCancel && m_equityGuard != NULL)
           {
            ENUM_BREACH_REASON blockReason = BREACH_NONE;
            if(!m_equityGuard.IsNewEntryPermitted(blockReason))
              {
               if(blockReason == BREACH_ROLLOVER_WINDOW ||
                  blockReason == BREACH_HIGH_IMPACT_NEWS ||
                  blockReason == BREACH_DAILY_DRAWDOWN ||
                  blockReason == BREACH_MAX_TOTAL_DRAWDOWN)
                 {
                  shouldCancel = true;
                  cancelReason = "Risk Guard blocked pending order: " + BreachReasonToString(blockReason);
                 }
              }
           }
         if(shouldCancel)
           {
            ulong ticketToCancel = m_ctx.pendingOrderTicket;
            if(m_trade.OrderDelete(ticketToCancel))
              {
               if(m_logger != NULL)
                 {
                  m_logger.Info(StringFormat("Pending Order #%I64u Cancelled: %s",
                                             ticketToCancel, cancelReason));
                  m_logger.WriteTradeLifecycleCSV(
                     m_ctx.setupId, ticketToCancel, "LIMIT_CANCELLED", m_ctx.direction,
                     m_ctx.initialLots, m_ctx.plannedEntryPrice, m_ctx.initialStopLoss,
                     m_ctx.tp1Price, m_ctx.tp2Price, m_ctx.onnxProbability,
                     0.0, m_ctx.riskCapitalUSD, 0.0, 0.0, cancelReason);
                 }
               m_ctx.Reset();
              }
           }
         return;
        }
      // --- B. Manage All Open Positions (7-Stage Widened High-Altitude R-Ratchet & Vertical Time Barrier) ---
      datetime curM1BarTime    = iTime(m_symbol, PERIOD_M1, 0);
      datetime closedM1BarTime = iTime(m_symbol, PERIOD_M1, 1);
      double   m1High          = iHigh(m_symbol, PERIOD_M1, 1);
      double   m1Low           = iLow(m_symbol, PERIOD_M1, 1);
      double   bid             = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double   ask             = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      for(int posIdx = PositionsTotal() - 1; posIdx >= 0; posIdx--)
        {
         ulong posTicket = PositionGetTicket(posIdx);
         if(posTicket == 0 || PositionGetString(POSITION_SYMBOL) != m_symbol ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(!m_posInfo.SelectByTicket(posTicket))
            continue;
         int slot = FindOrAllocRatchetSlot(posTicket, true, false);
         ENUM_SIGNAL_DIRECTION posDir = (m_posInfo.PositionType() == POSITION_TYPE_BUY) ? SIGNAL_LONG : SIGNAL_SHORT;
         double   entryPx     = m_posInfo.PriceOpen();
         datetime posOpenTime = (datetime)m_posInfo.Time();
         double   curSL       = m_posInfo.StopLoss();
         double   curTP       = m_posInfo.TakeProfit();
         double   slotInitRsk = (m_ratchetStates[slot].initialRiskUSD > 0.50 ? m_ratchetStates[slot].initialRiskUSD : (posTicket == m_ctx.positionTicket && m_ctx.initialRiskDistanceUSD > 0.50 ? m_ctx.initialRiskDistanceUSD : MathMax(1.50, entryPx * 0.0025)));
         double   riskUSD     = MathMax(1.20, slotInitRsk);
         double favorableUSD = (posDir == SIGNAL_LONG) ? (bid - entryPx) : (entryPx - ask);
         double adverseUSD   = (posDir == SIGNAL_LONG) ? (entryPx - bid) : (ask - entryPx);
         double currentR     = favorableUSD / riskUSD;
         double adverseR     = MathMax(0.0, adverseUSD / riskUSD);
         if(posTicket == m_ctx.positionTicket)
           {
            if(currentR > m_ctx.maxFavorableExcursionR) m_ctx.maxFavorableExcursionR = currentR;
            if(adverseR > m_ctx.maxAdverseExcursionR)   m_ctx.maxAdverseExcursionR   = adverseR;
           }
         long elapsedSec = (long)(TimeCurrent() - posOpenTime);
         bool isPosProtected = (posDir == SIGNAL_LONG)
                               ? (curSL > entryPx + 0.01)
                               : (curSL > 0.0 && curSL < entryPx - 0.01);
         // 1. Check Vertical Time Barrier (24h for PureBE Protected Prime Runners, 12h for Unprotected Prime, 90m for Secondary)
         if(m_enableVerticalBarrier && posOpenTime > 0)
           {
            int barrierSec = (m_ratchetStates[slot].isPrimeSetup ? (isPosProtected ? (24 * 3600) : (12 * 3600)) : (18 * 300));
            if(elapsedSec >= barrierSec)
              {
               MqlDateTime dtNow;
               TimeToStruct(TimeCurrent(), dtNow);
               if(dtNow.hour >= 2 && dtNow.hour <= 22)
                 {
                  double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                  double tickSize   = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
                  if(tickSize <= 0.0) tickSize = (point > 0.0 ? point : 0.01);
                  long   stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
                  long   freezeLvl  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
                  double minDist    = MathMax((double)MathMax(stopsLevel, freezeLvl) * point, 3.0 * tickSize) + 0.05;
                  double tightSL = (posDir == SIGNAL_LONG)
                                   ? NormalizeSymbolPrice(m_symbol, bid - minDist)
                                   : NormalizeSymbolPrice(m_symbol, ask + minDist);
                  double tightTP = (posDir == SIGNAL_LONG)
                                   ? NormalizeSymbolPrice(m_symbol, bid + minDist)
                                   : NormalizeSymbolPrice(m_symbol, ask - minDist);
                  if(MathAbs(tightSL - curSL) > 0.05 || MathAbs(tightTP - curTP) > 0.05)
                    {
                     if(ValidateModifyDistanceForDir(posDir, tightSL, tightTP))
                        m_trade.PositionModify(posTicket, tightSL, tightTP);
                    }
                  continue;
                 }
              }
           }
         // 2. Evaluate 24h PureBE Protection Lock Strictly on Completed M1 Bars
         datetime entryM1BarTime = posOpenTime - (posOpenTime % 60);
         if(m_ratchetStates[slot].isPrimeSetup &&
            curM1BarTime > 0 &&
            curM1BarTime != m_ratchetStates[slot].lastRatchetM1BarTime &&
            closedM1BarTime >= entryM1BarTime)
           {
            m_ratchetStates[slot].lastRatchetM1BarTime = curM1BarTime;
            double barFavUSD = (posDir == SIGNAL_LONG)
                               ? ((m1High + 0.18) - entryPx)
                               : (entryPx - (m1Low + 0.18));
            if(barFavUSD > m_ratchetStates[slot].allBarMaxFavUSD)
               m_ratchetStates[slot].allBarMaxFavUSD = barFavUSD;
            if(barFavUSD > m_ratchetStates[slot].closedBarMaxFavUSD)
               m_ratchetStates[slot].closedBarMaxFavUSD = barFavUSD;
            double maxFavPct = m_ratchetStates[slot].allBarMaxFavUSD / entryPx;
            double allFavPct = maxFavPct;
            double effFavUSD = (posDir == SIGNAL_LONG) ? (favorableUSD + 0.18) : favorableUSD;
            double curFavPct = (effFavUSD - 0.08) / entryPx;
            double lockPct   = -999.0;
            if(elapsedSec >= 300  && maxFavPct >= 0.00085 && curFavPct >= 0.00045)      lockPct = 0.00045; // PureBE Stage 1 (+4.5 bps after 5m)
            else if(elapsedSec >= 1200 && allFavPct >= 0.00065 && curFavPct >= 0.00042) lockPct = 0.00042; // PureBE Stage 2 (+4.2 bps after 20m)
            if(lockPct > -1.0)
              {
               double targetLockUSD = (posDir == SIGNAL_LONG)
                                      ? MathMax(0.15, entryPx * lockPct - 0.12)
                                      : (entryPx * lockPct);
               double minLiveCushionUSD = MathMax(0.45, entryPx * 0.00020);
               if(favorableUSD >= (targetLockUSD + minLiveCushionUSD))
                 {
                  double ratchetSL = (posDir == SIGNAL_LONG)
                                     ? NormalizeSymbolPrice(m_symbol, entryPx + targetLockUSD)
                                     : NormalizeSymbolPrice(m_symbol, entryPx - targetLockUSD);
                  bool improvesBroker = (posDir == SIGNAL_LONG  && ratchetSL > (curSL + 0.02)) ||
                                        (posDir == SIGNAL_SHORT && (curSL <= 0.0 || ratchetSL < (curSL - 0.02)));
                  if(improvesBroker && ValidateModifyDistanceForDir(posDir, ratchetSL, curTP))
                    {
                     if(m_trade.PositionModify(posTicket, ratchetSL, curTP))
                       {
                        if(posTicket == m_ctx.positionTicket)
                          {
                           m_ctx.currentStopLoss = ratchetSL;
                           if(lockPct > 0.0)
                              m_ctx.movedToBreakeven = true;
                          }
                       }
                    }
                 }
              }
           }
        }
     }
   void                  OnTradeTransaction(const MqlTradeTransaction &trans,
                                            const MqlTradeRequest &request,
                                            const MqlTradeResult &result)
     {
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
         return;
      ulong dealTicket = trans.deal;
      if(dealTicket == 0 || !HistoryDealSelect(dealTicket))
         return;
      string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      ulong  dealMagic  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(dealSymbol != m_symbol || dealMagic != m_magic)
         return;
      ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT && dealEntry != DEAL_ENTRY_OUT_BY)
         return;
      double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double fee        = HistoryDealGetDouble(dealTicket, DEAL_FEE);
      double netDealPnL = profit + commission + swap + fee;
      double dealPrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double dealVol    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      ulong closedPosId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      for(int i = 0; i < 8; i++)
        {
         if(m_ratchetStates[i].ticket == closedPosId && !PositionSelectByTicket(closedPosId))
            m_ratchetStates[i].Reset();
        }
      if(m_equityGuard != NULL)
         m_equityGuard.OnClosedTradeResult(netDealPnL);
      m_accumulatedRealizedPnL += netDealPnL;
      // Check if position is now completely closed
      SyncBrokerState();
      if(!m_ctx.hasOpenPosition)
        {
         double totalNetPnL = m_accumulatedRealizedPnL;
         double realizedR   = (m_ctx.riskCapitalUSD > 0.0)
                              ? (totalNetPnL / m_ctx.riskCapitalUSD)
                              : 0.0;
         int label2_5R      = (m_ctx.maxFavorableExcursionR >= 1.40 ||
                               realizedR >= 0.55 ||
                               (m_ctx.tp1Executed && totalNetPnL > 0.0)) ? 1 : 0;
         m_hasUnconsumedOutcome = true;
         m_lastClosedDirection  = m_ctx.direction;
         m_lastClosedRealizedR  = realizedR;
         
         if(m_logger != NULL)
           {
            m_logger.Info(StringFormat(
               "Position Closed [SetupID=%I64u | NetPnL=$%.2f | RealizedR=%.2fR | MFE=%.2fR | MAE=%.2fR | Label2.5R=%d]",
               m_ctx.setupId, totalNetPnL, realizedR,
               m_ctx.maxFavorableExcursionR, m_ctx.maxAdverseExcursionR, label2_5R));
            m_logger.WriteTradeLifecycleCSV(
               m_ctx.setupId, dealTicket, "POSITION_CLOSED", m_ctx.direction,
               dealVol, dealPrice, m_ctx.currentStopLoss, m_ctx.tp1Price, m_ctx.tp2Price,
               m_ctx.onnxProbability, 0.0, m_ctx.riskCapitalUSD, 0.0, totalNetPnL,
               StringFormat("R=%.2f;MFE=%.2f;MAE=%.2f", realizedR,
                            m_ctx.maxFavorableExcursionR, m_ctx.maxAdverseExcursionR));
            if(m_lastSetup.isValid)
              {
               m_logger.WriteSetupTelemetryCSV(
                  m_lastSetup, m_ctx.setupFeatures, m_lastPrediction,
                  "POSITION_CLOSED", totalNetPnL, realizedR,
                  m_ctx.maxFavorableExcursionR, m_ctx.maxAdverseExcursionR, label2_5R);
              }
           }
         m_accumulatedRealizedPnL = 0.0;
      m_lastRatchetM1BarTime   = 0;
      m_closedBarMaxFavUSD     = 0.0;
      m_allBarMaxFavUSD        = 0.0;
         if(!m_ctx.hasPendingOrder)
            m_ctx.Reset();
         SyncBrokerState();
        }
     }
   //--- Consume closed trade outcome for Layer 1 same-direction cooldown
   bool                  ConsumeClosedOutcome(ENUM_SIGNAL_DIRECTION &outDirection, double &outRealizedR)
     {
      if(!m_hasUnconsumedOutcome)
         return false;
      outDirection           = m_lastClosedDirection;
      outRealizedR           = m_lastClosedRealizedR;
      m_hasUnconsumedOutcome = false;
      return true;
     }
   //--- Snapshot active trade context
   void                  GetActiveContext(SActiveTradeContext &outCtx) const
     {
      outCtx = m_ctx;
     }
  };
#endif // XAUUSD_QUANT_EXECUTION_MANAGER_MQH
