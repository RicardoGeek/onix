//+------------------------------------------------------------------+
//|                                             ExecutionManager.mqh |
//|                     BTCUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 3 Risk: CTrade Wrapper, Limit Expiry, TP1 @ VPOC & Trail  |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef BTCUSD_QUANT_EXECUTION_MANAGER_MQH
#define BTCUSD_QUANT_EXECUTION_MANAGER_MQH

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
class CExecutionManager
  {
private:
   string                m_symbol;
   ulong                 m_magic;
   ulong                 m_deviationPoints;
   double                m_commissionPerLotRoundTurn;
   int                   m_verticalBarrierSeconds;
   bool                  m_enableVerticalBarrier;

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
   bool                  m_hasUnconsumedOutcome;
   ENUM_SIGNAL_DIRECTION m_lastClosedDirection;
   double                m_lastClosedRealizedR;

   double                ComputeBreakevenOffsetPrice() const
     {
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0)
         tickSize = 0.01;
      if(tickValue <= 0.0)
         tickValue = 0.01;

      double commissionTicks = (m_commissionPerLotRoundTurn / tickValue);
      double commissionPrice = commissionTicks * tickSize;
      double safetyCushion   = 18.0; // $18.00 spread/slippage cushion on BTCUSD
      return NormalizeSymbolPrice(m_symbol, commissionPrice + safetyCushion);
     }

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

      double bufferUSD = MathMax(18.0, 0.10 * m_ctx.initialRiskDistanceUSD);

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
      m_deviationPoints           = 500;
      m_commissionPerLotRoundTurn = 0.0;
      m_verticalBarrierSeconds    = 4 * 3600;
      m_enableVerticalBarrier     = true;
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

   void                  SyncBrokerState()
     {
      ulong foundOrderTicket = 0;
      ulong foundPosTicket   = 0;

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
         if(m_posInfo.SelectByTicket(foundPosTicket))
           {
            m_ctx.positionTicket  = foundPosTicket;
            m_ctx.remainingLots   = m_posInfo.Volume();
            m_ctx.currentStopLoss = m_posInfo.StopLoss();
           }
        }
      else if(foundPosTicket > 0 && !m_ctx.hasOpenPosition)
        {
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
                                           ? (m_ctx.actualEntryPrice + 0.62 * m_ctx.initialRiskDistanceUSD)
                                           : (m_ctx.actualEntryPrice - 0.62 * m_ctx.initialRiskDistanceUSD);
            m_ctx.initialLots            = m_posInfo.Volume();
            m_ctx.remainingLots          = m_posInfo.Volume();
           }
        }
      else if(foundOrderTicket > 0 && foundPosTicket == 0)
        {
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

   bool                  HasActiveExposure()
     {
      SyncBrokerState();
      return (m_ctx.hasPendingOrder || m_ctx.hasOpenPosition);
     }

   bool                  HasPendingLimitOrder() const { return m_ctx.hasPendingOrder; }
   bool                  HasOpenPosition()      const { return m_ctx.hasOpenPosition; }

   bool                  PlaceSniperLimitOrder(const SSweepCandidateSetup &setup,
                                               const SStationaryFeatures &features,
                                               const SOnnxPrediction &prediction,
                                               const SLotCalculationResult &lotResult)
     {
      SyncBrokerState();

      if(m_ctx.hasPendingOrder || m_ctx.hasOpenPosition)
        {
         if(m_logger != NULL)
            m_logger.Warn("PlaceSniperLimitOrder rejected: active order or position already exists.");
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

      string comment = StringFormat("BTCQ_%I64u_P%.0f", setup.setupId, prediction.winProbability * 100.0);
      bool   placed  = false;
      bool   filledImmediately = false;

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
      chkReq.deviation = 500;
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

      // Instant Market Execution when within max($45.00, 0.25 * SL distance)
      double maxMarketSlipUSD = MathMax(45.0, 0.25 * setup.slDistanceUSD);

      if(setup.direction == SIGNAL_LONG)
        {
         if(MathAbs(ask - entryPrice) <= maxMarketSlipUSD)
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
         if(MathAbs(entryPrice - bid) <= maxMarketSlipUSD)
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

      m_ctx.Reset();
      m_lastSetup                     = setup;
      m_lastPrediction                = prediction;
      m_accumulatedRealizedPnL        = 0.0;

      m_ctx.setupId                   = setup.setupId;
      m_ctx.direction                 = setup.direction;
      m_ctx.sweptPoolType             = setup.sweptPoolType;
      m_ctx.orderPlacedTime           = TimeCurrent();
      m_ctx.orderPlacedM5BarTime      = iTime(m_symbol, PERIOD_M5, 0);
      m_ctx.expiryM5Bars              = (setup.expiryM5Bars > 0 ? setup.expiryM5Bars : 3);
      m_ctx.plannedEntryPrice         = entryPrice;
      double fillPx                   = (filledImmediately && m_trade.ResultPrice() > 0.0) ? m_trade.ResultPrice() : entryPrice;
      m_ctx.actualEntryPrice          = fillPx;
      m_ctx.initialRiskDistanceUSD    = MathMax(HARD_MIN_SL_DISTANCE_USD, setup.slDistanceUSD);
      if(filledImmediately && MathAbs(fillPx - entryPrice) > 0.01)
        {
         tp1Price = (setup.direction == SIGNAL_LONG)
                    ? NormalizeSymbolPrice(m_symbol, fillPx + MathAbs(setup.tp1Price - setup.entryLimitPrice))
                    : NormalizeSymbolPrice(m_symbol, fillPx - MathAbs(setup.entryLimitPrice - setup.tp1Price));
        }
      m_ctx.initialStopLoss           = slPrice;
      m_ctx.currentStopLoss           = slPrice;
      m_ctx.tp1Price                  = tp1Price;
      m_ctx.tp2Price                  = tp2Price;
      m_ctx.initialLots               = lots;
      m_ctx.remainingLots             = lots;
      m_ctx.riskCapitalUSD            = lotResult.totalRiskCapitalUSD;
      m_ctx.tp1Executed               = false;
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

   void                  ManageActiveTradesOnTick()
     {
      SyncBrokerState();

      if(m_ctx.hasPendingOrder && m_ctx.pendingOrderTicket > 0)
        {
         bool   shouldCancel = false;
         string cancelReason = "";

         int barShift = iBarShift(m_symbol, PERIOD_M5, m_ctx.orderPlacedM5BarTime, false);
         if(barShift >= m_ctx.expiryM5Bars ||
            (TimeCurrent() - m_ctx.orderPlacedTime) >= (m_ctx.expiryM5Bars * 300))
           {
            shouldCancel = true;
            cancelReason = StringFormat("Expired after %d M5 bars without fill", m_ctx.expiryM5Bars);
           }

         if(!shouldCancel && m_ctx.initialRiskDistanceUSD > 0.0)
           {
            double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            double runawayDist = 1.50 * m_ctx.initialRiskDistanceUSD;

            if(m_ctx.direction == SIGNAL_LONG && (bid - m_ctx.plannedEntryPrice) >= runawayDist)
              {
               shouldCancel = true;
               cancelReason = "Price reached +1.5R target before limit fill";
              }
            else if(m_ctx.direction == SIGNAL_SHORT && (m_ctx.plannedEntryPrice - ask) >= runawayDist)
              {
               shouldCancel = true;
               cancelReason = "Price reached +1.5R target before limit fill";
              }
           }

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
                  m_logger.Info(StringFormat("Pending Limit Order #%I64u Cancelled: %s",
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

      if(m_ctx.hasOpenPosition && m_ctx.positionTicket > 0)
        {
         if(!m_posInfo.SelectByTicket(m_ctx.positionTicket))
           {
            m_ctx.hasOpenPosition = false;
            return;
           }

         double bid     = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ask     = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double markPx  = (m_ctx.direction == SIGNAL_LONG) ? bid : ask;
         double riskUSD = (m_ctx.initialRiskDistanceUSD > 0.0 ? m_ctx.initialRiskDistanceUSD : 250.0);

         double favorableUSD = (m_ctx.direction == SIGNAL_LONG)
                               ? (bid - m_ctx.actualEntryPrice)
                               : (m_ctx.actualEntryPrice - ask);
         double adverseUSD   = (m_ctx.direction == SIGNAL_LONG)
                               ? (m_ctx.actualEntryPrice - bid)
                               : (ask - m_ctx.actualEntryPrice);

         double currentR = favorableUSD / riskUSD;
         double adverseR = MathMax(0.0, adverseUSD / riskUSD);

         if(currentR > m_ctx.maxFavorableExcursionR)
            m_ctx.maxFavorableExcursionR = currentR;
         if(adverseR > m_ctx.maxAdverseExcursionR)
            m_ctx.maxAdverseExcursionR = adverseR;

         if(m_enableVerticalBarrier && m_ctx.positionOpenTime > 0)
           {
            if((TimeCurrent() - m_ctx.positionOpenTime) >= m_verticalBarrierSeconds)
              {
               ulong closingTicket = m_ctx.positionTicket;
               if(m_trade.PositionClose(closingTicket, m_deviationPoints))
                 {
                  if(m_logger != NULL)
                     m_logger.Info(StringFormat("Position #%I64u closed at 4-Hour Vertical Time Barrier [R=%.2f]",
                                                closingTicket, currentR));
                  return;
                 }
              }
           }

         bool tp1Reached = (m_ctx.direction == SIGNAL_LONG && bid >= m_ctx.tp1Price) ||
                           (m_ctx.direction == SIGNAL_SHORT && ask <= m_ctx.tp1Price);

         if(!m_ctx.tp1Executed && tp1Reached)
           {
            double currentVol = m_posInfo.Volume();
            double minVol     = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            double partVol    = NormalizeSymbolLots(m_symbol, currentVol * 0.42);
            if(partVol < minVol && currentVol >= (2.0 * minVol - QUANT_EPSILON))
               partVol = minVol;
            double remainVol  = currentVol - partVol;

            if(partVol >= minVol && remainVol >= (minVol - QUANT_EPSILON))
              {
               if(m_trade.PositionClosePartial(m_ctx.positionTicket, partVol, m_deviationPoints))
                 {
                  m_ctx.tp1Executed   = true;
                  m_ctx.remainingLots = remainVol;
                  if(m_logger != NULL)
                    {
                     m_logger.Info(StringFormat(
                        "TP1 Reached @ %.2f: Closed 42%% (%.2f lots) of Position #%I64u; tightening 58%% runner SL to -0.30R",
                        markPx, partVol, m_ctx.positionTicket));
                     m_logger.WriteTradeLifecycleCSV(
                        m_ctx.setupId, m_ctx.positionTicket, "TP1_PARTIAL_50PCT", m_ctx.direction,
                        partVol, markPx, m_ctx.currentStopLoss, m_ctx.tp1Price, m_ctx.tp2Price,
                        m_ctx.onnxProbability, 0.0, m_ctx.riskCapitalUSD, 0.0, 0.0, "TP1 Partial Close (42%)");
                    }
                 }
              }
            else
              {
               m_ctx.tp1Executed = true;
               double shield015R = (m_ctx.direction == SIGNAL_LONG)
                                   ? NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice - 0.15 * riskUSD)
                                   : NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice + 0.15 * riskUSD);
               if(ValidateModifyDistance(shield015R, m_ctx.tp2Price))
                 {
                  if(m_trade.PositionModify(m_ctx.positionTicket, shield015R, m_ctx.tp2Price))
                    {
                     m_ctx.currentStopLoss  = shield015R;
                     m_ctx.movedToBreakeven = true;
                    }
                 }
              }

            SyncBrokerState();

            if(m_ctx.hasOpenPosition && !m_ctx.movedToBreakeven)
              {
               double shieldOffset = 0.30 * riskUSD;
               double newSL        = (m_ctx.direction == SIGNAL_LONG)
                                     ? NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice - shieldOffset)
                                     : NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice + shieldOffset);

               bool isImprovement = (m_ctx.direction == SIGNAL_LONG && newSL > m_ctx.currentStopLoss) ||
                                    (m_ctx.direction == SIGNAL_SHORT && newSL < m_ctx.currentStopLoss);

               if(isImprovement && ValidateModifyDistance(newSL, m_ctx.tp2Price))
                 {
                  if(m_trade.PositionModify(m_ctx.positionTicket, newSL, m_ctx.tp2Price))
                    {
                     m_ctx.currentStopLoss  = newSL;
                     m_ctx.movedToBreakeven = true;
                     if(m_logger != NULL)
                        m_logger.Info(StringFormat("Position #%I64u Runner SL tightened to -0.30R (%.2f) [Net Position Risk-Free]",
                                                   m_ctx.positionTicket, newSL));
                    }
                 }
              }
           }

         if(m_ctx.tp1Executed && !m_ctx.movedToBreakeven && m_ctx.hasOpenPosition)
           {
            double shieldOffset = 0.30 * riskUSD;
            double newSL        = (m_ctx.direction == SIGNAL_LONG)
                                  ? NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice - shieldOffset)
                                  : NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice + shieldOffset);

            if(ValidateModifyDistance(newSL, m_ctx.tp2Price))
              {
               if(m_trade.PositionModify(m_ctx.positionTicket, newSL, m_ctx.tp2Price))
                 {
                  m_ctx.currentStopLoss  = newSL;
                  m_ctx.movedToBreakeven = true;
                 }
              }
           }

         if(m_ctx.tp1Executed && m_ctx.movedToBreakeven && currentR >= 0.95)
           {
            double minBeR  = MathMax(0.10, ComputeBreakevenOffsetPrice() / riskUSD);
            double lockedR = minBeR;
            if(currentR >= 2.80)
               lockedR = 2.10;
            else if(currentR >= 2.25)
               lockedR = 1.45;
            else if(currentR >= 1.65)
               lockedR = 0.85;
            else if(currentR >= 1.32)
               lockedR = 0.42;

            double ratchetSL = (m_ctx.direction == SIGNAL_LONG)
                               ? NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice + lockedR * riskUSD)
                               : NormalizeSymbolPrice(m_symbol, m_ctx.actualEntryPrice - lockedR * riskUSD);

            double bestTrailSL = ratchetSL;
            if(currentR >= 2.25)
              {
               double swingSL = 0.0;
               if(ComputeM5SwingTrailSL(swingSL))
                 {
                  if(m_ctx.direction == SIGNAL_LONG && swingSL > bestTrailSL)
                     bestTrailSL = swingSL;
                  else if(m_ctx.direction == SIGNAL_SHORT && swingSL < bestTrailSL)
                     bestTrailSL = swingSL;
                 }
              }

            double minTrailStep    = MathMax(1.0, SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE));
            bool   improvesCurrent = (m_ctx.direction == SIGNAL_LONG && bestTrailSL >= (m_ctx.currentStopLoss + minTrailStep - QUANT_EPSILON)) ||
                                     (m_ctx.direction == SIGNAL_SHORT && bestTrailSL <= (m_ctx.currentStopLoss - minTrailStep + QUANT_EPSILON));

            if(improvesCurrent && ValidateModifyDistance(bestTrailSL, m_ctx.tp2Price))
              {
               if(m_trade.PositionModify(m_ctx.positionTicket, bestTrailSL, m_ctx.tp2Price))
                 {
                  m_ctx.currentStopLoss = bestTrailSL;
                  if(m_logger != NULL)
                     m_logger.Debug(StringFormat("Position #%I64u Runner Trail SL updated to %.2f [CurrentR=%.2f]",
                                                 m_ctx.positionTicket, bestTrailSL, currentR));
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

      m_accumulatedRealizedPnL += netDealPnL;

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

         if(m_equityGuard != NULL)
            m_equityGuard.OnClosedTradeResult(totalNetPnL);

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
         if(!m_ctx.hasPendingOrder)
            m_ctx.Reset();
         SyncBrokerState();
        }
     }

   bool                  ConsumeClosedOutcome(ENUM_SIGNAL_DIRECTION &outDirection, double &outRealizedR)
     {
      if(!m_hasUnconsumedOutcome)
         return false;
      outDirection           = m_lastClosedDirection;
      outRealizedR           = m_lastClosedRealizedR;
      m_hasUnconsumedOutcome = false;
      return true;
     }

   void                  GetActiveContext(SActiveTradeContext &outCtx) const
     {
      outCtx = m_ctx;
     }
  };

#endif // BTCUSD_QUANT_EXECUTION_MANAGER_MQH
