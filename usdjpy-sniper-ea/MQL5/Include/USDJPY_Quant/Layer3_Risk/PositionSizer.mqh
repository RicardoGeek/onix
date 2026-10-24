//+------------------------------------------------------------------+
//|                                                PositionSizer.mqh |
//|                     USDJPY Hybrid Quantitative Sniper EA (ONNX)  |
//|   Layer 3 Risk: Dual-Mode Lot Sizing, Commission & Margin Engine |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef USDJPY_QUANT_POSITION_SIZER_MQH
#define USDJPY_QUANT_POSITION_SIZER_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "EquityGuard.mqh"

//+------------------------------------------------------------------+
//| CPositionSizer: Precision USDJPY Lot & House-Money Calculator    |
//+------------------------------------------------------------------+
class CPositionSizer
  {
private:
   string         m_symbol;
   ENUM_RISK_MODE m_riskMode;
   double         m_commissionPerLotRoundTurn;
   double         m_propTier2RiskPct;
   double         m_propTier1RiskPct;
   double         m_growthTier2RiskPct;
   double         m_growthTier1RiskPct;
   double         m_freeMarginSafetyRatio;

   CEquityGuard  *m_equityGuard;
   CQuantLogger  *m_logger;

   //--- Resolve accurate USD loss tick value for USDJPY across broker specs
   double         ResolveLossTickValue(const double tickSize, const double refPrice) const
     {
      double tickValLoss = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValLoss > 0.0)
         return tickValLoss;

      double tickVal = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickVal > 0.0)
         return tickVal;

      // Fallback using contract size (100,000 USD on USDJPY -> convert JPY tick value to USD by dividing by refPrice)
      double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize <= 0.0)
         contractSize = 100000.0;
      double px = (refPrice > 10.0) ? refPrice : 150.0;
      return (contractSize * tickSize) / px;
     }

   int            GetVolumeDigits(const double step) const
     {
      if(step >= 1.0)   return 0;
      if(step >= 0.1)   return 1;
      if(step >= 0.01)  return 2;
      if(step >= 0.001) return 3;
      return 2;
     }

public:
                  CPositionSizer()
     {
      m_symbol                    = _Symbol;
      m_riskMode                  = MODE_PROP_GUARD;
      m_commissionPerLotRoundTurn = 7.0;
      m_propTier2RiskPct          = PROP_TIER2_RISK_PCT;
      m_propTier1RiskPct          = PROP_TIER1_RISK_PCT;
      m_growthTier2RiskPct        = GROWTH_TIER2_RISK_PCT;
      m_growthTier1RiskPct        = GROWTH_TIER1_RISK_PCT;
      m_freeMarginSafetyRatio     = 0.90;
      m_equityGuard               = NULL;
      m_logger                    = NULL;
     }

                 ~CPositionSizer() {}

   bool           Init(const string symbol,
                       const ENUM_RISK_MODE riskMode,
                       const double commissionPerLotRoundTurn,
                       CEquityGuard *equityGuard,
                       CQuantLogger *logger,
                       const double propTier2RiskPct   = PROP_TIER2_RISK_PCT,
                       const double propTier1RiskPct   = PROP_TIER1_RISK_PCT,
                       const double growthTier2RiskPct = GROWTH_TIER2_RISK_PCT,
                       const double growthTier1RiskPct = GROWTH_TIER1_RISK_PCT)
     {
      m_symbol                    = symbol;
      m_riskMode                  = riskMode;
      m_commissionPerLotRoundTurn = MathMax(0.0, commissionPerLotRoundTurn);
      m_equityGuard               = equityGuard;
      m_logger                    = logger;

      m_propTier2RiskPct          = (propTier2RiskPct   > 0.0 ? propTier2RiskPct   : PROP_TIER2_RISK_PCT);
      m_propTier1RiskPct          = (propTier1RiskPct   > 0.0 ? propTier1RiskPct   : PROP_TIER1_RISK_PCT);
      m_growthTier2RiskPct        = (growthTier2RiskPct > 0.0 ? growthTier2RiskPct : GROWTH_TIER2_RISK_PCT);
      m_growthTier1RiskPct        = (growthTier1RiskPct > 0.0 ? growthTier1RiskPct : GROWTH_TIER1_RISK_PCT);

      return (m_equityGuard != NULL);
     }

   bool           CalculateSniperLots(const ENUM_SIGNAL_DIRECTION direction,
                                      const double entryPrice,
                                      const double stopLossPrice,
                                      const double onnxWinProbability,
                                      SLotCalculationResult &outResult)
     {
      outResult.Reset();

      if(m_equityGuard == NULL)
        {
         outResult.diagnosticNote = "PositionSizer uninitialized: EquityGuard pointer is NULL";
         return false;
        }

      if(onnxWinProbability < ONNX_PROB_TIER2_MIN)
        {
         outResult.diagnosticNote = StringFormat("ONNX probability %.4f below minimum threshold %.2f",
                                                 onnxWinProbability, ONNX_PROB_TIER2_MIN);
         return false;
        }

      bool isTier1Signal = (onnxWinProbability >= ONNX_PROB_TIER1_MIN);

      double slDistancePrice = MathAbs(entryPrice - stopLossPrice);
      outResult.slDistancePrice = slDistancePrice;

      if(slDistancePrice < (HARD_MIN_SL_DISTANCE_USD - 1e-5) ||
         slDistancePrice > (HARD_MAX_SL_DISTANCE_USD + 1e-5))
        {
         outResult.diagnosticNote = StringFormat(
            "SL distance %.3f JPY outside hard sniper bounds [%.3f, %.3f]",
            slDistancePrice, HARD_MIN_SL_DISTANCE_USD, HARD_MAX_SL_DISTANCE_USD);
         return false;
        }

      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(equity <= 0.0 || freeMargin <= 0.0)
        {
         outResult.diagnosticNote = "Invalid account equity or free margin";
         return false;
        }

      bool dampenerActive = m_equityGuard.IsDrawdownDampenerActive();
      outResult.dampenerApplied = dampenerActive;

      double baseRiskPct        = 0.0;
      double effectiveRiskPct   = 0.0;
      double baseRiskUSD        = 0.0;
      double houseMoneyBonusUSD = 0.0;
      double riskCapitalUSD     = 0.0;

      double currentTotalDDPct = m_equityGuard.GetCurrentTotalDrawdownPct();
      if(m_riskMode == MODE_PROP_GUARD)
        {
         baseRiskPct = isTier1Signal ? m_propTier1RiskPct : m_propTier2RiskPct;

         if(currentTotalDDPct >= 3.00)
            effectiveRiskPct = baseRiskPct * 0.55;
         else if(currentTotalDDPct >= 2.00 || dampenerActive)
            effectiveRiskPct = baseRiskPct * 0.70;
         else if(currentTotalDDPct >= 1.15)
            effectiveRiskPct = baseRiskPct * 0.85;
         else
            effectiveRiskPct = baseRiskPct;

         double weeklyProfitUSD      = m_equityGuard.GetWeeklyRealizedProfitUSD();
         double dailyPnLUSD          = m_equityGuard.GetDailyRealizedPnLUSD();
         int    lossesToday          = m_equityGuard.GetConsecutiveLossesToday();
         double dailyScratchFloorUSD = (m_equityGuard.GetDayStartReference() > 0.0 ? m_equityGuard.GetDayStartReference() * 0.0015 : 5.0);

         if(dailyPnLUSD < -dailyScratchFloorUSD || lossesToday > 0)
            effectiveRiskPct = MathMin(effectiveRiskPct, baseRiskPct * 0.38);

         baseRiskUSD    = equity * (effectiveRiskPct / 100.0);
         riskCapitalUSD = baseRiskUSD;

         double hwmBufferUSD = MathMax(weeklyProfitUSD, (currentTotalDDPct < 0.25 ? equity * 0.008 : 0.0));
         if(!dampenerActive && currentTotalDDPct < 0.50 && lossesToday == 0 && dailyPnLUSD >= -dailyScratchFloorUSD &&
            hwmBufferUSD > 0.0)
           {
            houseMoneyBonusUSD = PROP_HOUSE_MONEY_SHARE * hwmBufferUSD;
            double maxAllowedCapitalUSD = equity * (PROP_MAX_EFFECTIVE_RISK_PCT / 100.0);
            if((baseRiskUSD + houseMoneyBonusUSD) > maxAllowedCapitalUSD)
               houseMoneyBonusUSD = MathMax(0.0, maxAllowedCapitalUSD - baseRiskUSD);

            riskCapitalUSD              = baseRiskUSD + houseMoneyBonusUSD;
            effectiveRiskPct            = (riskCapitalUSD / equity) * 100.0;
            outResult.houseMoneyApplied = (houseMoneyBonusUSD > 0.0);
           }
        }
      else
        {
         baseRiskPct = isTier1Signal ? m_growthTier1RiskPct : m_growthTier2RiskPct;

         if(currentTotalDDPct >= 3.60)
            effectiveRiskPct = baseRiskPct * 0.58;
         else if(currentTotalDDPct >= 2.20 || dampenerActive)
            effectiveRiskPct = baseRiskPct * 0.72;
         else if(currentTotalDDPct >= 1.25)
            effectiveRiskPct = baseRiskPct * 0.85;
         else
            effectiveRiskPct = baseRiskPct;

         double weeklyProfitUSD      = m_equityGuard.GetWeeklyRealizedProfitUSD();
         double dailyPnLUSD          = m_equityGuard.GetDailyRealizedPnLUSD();
         int    lossesToday          = m_equityGuard.GetConsecutiveLossesToday();
         double dailyScratchFloorUSD = (m_equityGuard.GetDayStartReference() > 0.0 ? m_equityGuard.GetDayStartReference() * 0.0015 : 5.0);

         if(dailyPnLUSD < -dailyScratchFloorUSD || lossesToday > 0)
            effectiveRiskPct = MathMin(effectiveRiskPct, baseRiskPct * 0.42);

         baseRiskUSD    = equity * (effectiveRiskPct / 100.0);
         riskCapitalUSD = baseRiskUSD;

         double hwmBufferUSD = MathMax(weeklyProfitUSD, (currentTotalDDPct < 0.35 ? equity * 0.010 : 0.0));
         if(!dampenerActive && hwmBufferUSD > 0.0 && currentTotalDDPct < 1.00 && lossesToday == 0 &&
            dailyPnLUSD >= -dailyScratchFloorUSD && (isTier1Signal || onnxWinProbability >= 0.66))
           {
            double share      = isTier1Signal ? GROWTH_HOUSE_MONEY_SHARE : (GROWTH_HOUSE_MONEY_SHARE * 0.50);
            double maxRiskPct = isTier1Signal ? GROWTH_MAX_EFFECTIVE_RISK_PCT : 1.65;
            houseMoneyBonusUSD = share * hwmBufferUSD;
            double maxAllowedCapitalUSD = equity * (maxRiskPct / 100.0);

            if((baseRiskUSD + houseMoneyBonusUSD) > maxAllowedCapitalUSD)
               houseMoneyBonusUSD = MathMax(0.0, maxAllowedCapitalUSD - baseRiskUSD);

            riskCapitalUSD              = baseRiskUSD + houseMoneyBonusUSD;
            effectiveRiskPct            = (riskCapitalUSD / equity) * 100.0;
            outResult.houseMoneyApplied = (houseMoneyBonusUSD > 0.0);
           }

         double remDailyDDPct = m_equityGuard.GetRemainingDailyDrawdownCapacityPct();
         double maxDailyRiskPct = (lossesToday == 0 && dailyPnLUSD >= -dailyScratchFloorUSD)
                                  ? MathMin(GROWTH_MAX_REMAINING_DD_CAP_PCT, remDailyDDPct * 0.90)
                                  : MathMin(GROWTH_MAX_REMAINING_DD_CAP_PCT, MathMax(0.0, remDailyDDPct - 0.15) * 0.60);
         double dayStartRef = m_equityGuard.GetDayStartReference();
         double maxDailyRiskUSD = (dayStartRef > 0.0 ? dayStartRef : equity) * (maxDailyRiskPct / 100.0);

         if(riskCapitalUSD > maxDailyRiskUSD)
           {
            riskCapitalUSD     = MathMax(0.0, maxDailyRiskUSD);
            houseMoneyBonusUSD = MathMax(0.0, riskCapitalUSD - baseRiskUSD);
            effectiveRiskPct   = (riskCapitalUSD / equity) * 100.0;
           }
        }

      double remDailyPct = m_equityGuard.GetRemainingDailyDrawdownCapacityPct();
      double dayRef      = m_equityGuard.GetDayStartReference();
      double dailyScratchFloor = (dayRef > 0.0 ? dayRef * 0.0015 : 5.0);
      double safeDailyPct = (m_equityGuard.GetConsecutiveLossesToday() == 0 && m_equityGuard.GetDailyRealizedPnLUSD() >= -dailyScratchFloor)
                            ? (remDailyPct * 0.90)
                            : MathMax(0.0, (remDailyPct - 0.15) * 0.55);
      double safeDailyCapUSD = (dayRef > 0.0 ? dayRef : equity) * (safeDailyPct / 100.0);
      if(riskCapitalUSD > safeDailyCapUSD)
        {
         riskCapitalUSD   = MathMax(0.0, safeDailyCapUSD);
         effectiveRiskPct = (riskCapitalUSD / equity) * 100.0;
        }

      double remTotalPct = m_equityGuard.GetRemainingTotalDrawdownCapacityPct();
      double hwmRef      = MathMax(m_equityGuard.GetHighWaterMark(), m_equityGuard.GetInitialBalance());
      double safeTotalPct = MathMax(0.0, remTotalPct - 0.08);
      double safeTotalCapUSD = (hwmRef > 0.0 ? hwmRef : equity) * (safeTotalPct / 100.0);
      if(riskCapitalUSD > safeTotalCapUSD)
        {
         riskCapitalUSD   = MathMax(0.0, safeTotalCapUSD);
         effectiveRiskPct = (riskCapitalUSD / equity) * 100.0;
        }

      if(riskCapitalUSD <= 0.0)
        {
         outResult.diagnosticNote = "Insufficient remaining daily or total drawdown capacity for trade";
         return false;
        }

      // 6. Exact Lot Sizing Formula with OrderCalcProfit() + USDJPY Quote-Currency Floor Guard
      ENUM_ORDER_TYPE calcOrderType = (direction == SIGNAL_LONG) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double tickSize      = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
         tickSize = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(tickSize <= 0.0)
         tickSize = 0.001;

      double tickValue     = ResolveLossTickValue(tickSize, stopLossPrice);
      double slTicks       = slDistancePrice / tickSize;
      double lossPerLotTickFormula = slTicks * tickValue;

      double orderCalcOneLotPL   = 0.0;
      double lossPerLotOrderCalc = 0.0;
      if(OrderCalcProfit(calcOrderType, m_symbol, 1.0, entryPrice, stopLossPrice, orderCalcOneLotPL) &&
         MathIsValidNumber(orderCalcOneLotPL) && MathAbs(orderCalcOneLotPL) > QUANT_EPSILON)
        {
         lossPerLotOrderCalc = MathAbs(orderCalcOneLotPL);
        }

      // Physical Contract Size Floor on USDJPY (100,000 USD notional quoted in JPY -> divide by stopLossPrice)
      double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize <= 0.0)
         contractSize = 100000.0;
      double pxDivisor = (stopLossPrice > 10.0) ? stopLossPrice : 150.0;
      double lossPerLotContractFloor = (contractSize * slDistancePrice) / pxDivisor;

      double priceLossPerLot = (lossPerLotOrderCalc > 0.0) ? lossPerLotOrderCalc : lossPerLotTickFormula;
      priceLossPerLot        = MathMax(priceLossPerLot, MathMax(lossPerLotTickFormula, lossPerLotContractFloor));
      if(slTicks > 0.0)
         tickValue = priceLossPerLot / slTicks;

      double lossPerLot    = priceLossPerLot + m_commissionPerLotRoundTurn;

      if(lossPerLot <= 0.0)
        {
         outResult.diagnosticNote = "Invalid lossPerLot calculation (<= 0)";
         return false;
        }

      double rawLots       = riskCapitalUSD / lossPerLot;
      double step          = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = 0.01;

      double finalLots     = MathFloor((rawLots + QUANT_EPSILON) / step) * step;
      finalLots            = NormalizeDouble(finalLots, GetVolumeDigits(step));

      double minVol        = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxVol        = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);

      if(finalLots < minVol)
        {
         double minVolTrueLossUSD    = minVol * lossPerLot;
         double maxMicroTolerancePct = (m_riskMode == MODE_PROP_GUARD ? PROP_MAX_EFFECTIVE_RISK_PCT : (isTier1Signal ? 1.18 : 0.95));
         if(m_riskMode == MODE_ASYMMETRIC_GROWTH)
           {
            if(currentTotalDDPct >= 3.00)
               maxMicroTolerancePct = 0.60;
            else if(currentTotalDDPct >= 1.75)
               maxMicroTolerancePct = 0.78;
           }

         double maxMicroToleranceUSD = equity * (maxMicroTolerancePct / 100.0);
         double minVolDailySafeUSD   = (dayRef > 0.0 ? dayRef : equity) * (MathMax(0.0, remDailyPct - 0.02) / 100.0);
         double minVolTotalSafeUSD   = (hwmRef > 0.0 ? hwmRef : equity) * (MathMax(0.0, remTotalPct - 0.02) / 100.0);
         if(minVolTrueLossUSD <= maxMicroToleranceUSD &&
            minVolTrueLossUSD <= minVolDailySafeUSD &&
            minVolTrueLossUSD <= minVolTotalSafeUSD)
           {
            finalLots          = minVol;
            riskCapitalUSD     = minVolTrueLossUSD;
            effectiveRiskPct   = (riskCapitalUSD / equity) * 100.0;
           }
         else
           {
            outResult.diagnosticNote = StringFormat(
               "Calculated rawLots (%.4f) < SYMBOL_VOLUME_MIN (%.2f) and min lot risk ($%.2f) exceeds micro sniper cap ($%.2f)",
               rawLots, minVol, minVolTrueLossUSD, MathMin(maxMicroToleranceUSD, MathMin(minVolDailySafeUSD, minVolTotalSafeUSD)));
            return false;
           }
        }

      if(finalLots > maxVol)
         finalLots = maxVol;

      double curAsk            = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double curBid            = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double marginCheckPrice  = (direction == SIGNAL_LONG)
                                 ? MathMax(entryPrice, (curAsk > 0.0 ? curAsk : entryPrice))
                                 : MathMax(entryPrice, (curBid > 0.0 ? curBid : entryPrice));
      double marginRequired    = 0.0;
      double maxSafeMargin     = freeMargin * m_freeMarginSafetyRatio;

      double oneLotMarginCalc  = 0.0;
      if(!OrderCalcMargin(calcOrderType, m_symbol, 1.0, marginCheckPrice, oneLotMarginCalc))
         oneLotMarginCalc = 0.0;

      MqlTradeRequest simReq;
      MqlTradeCheckResult simRes;
      ZeroMemory(simReq);
      ZeroMemory(simRes);
      simReq.action       = TRADE_ACTION_DEAL;
      simReq.symbol       = m_symbol;
      simReq.volume       = 1.0;
      simReq.type         = calcOrderType;
      simReq.price        = (direction == SIGNAL_LONG) ? (curAsk > 0.0 ? curAsk : entryPrice) : (curBid > 0.0 ? curBid : entryPrice);
      simReq.deviation    = 30;
      bool oneLotCheckOk  = OrderCheck(simReq, simRes);
      double oneLotMargin = MathMax(oneLotMarginCalc, (oneLotCheckOk || simRes.margin > 0.0) ? simRes.margin : 0.0);

      if(oneLotMargin > 0.0 && (finalLots * oneLotMargin) > maxSafeMargin)
        {
         double maxAffordableLots = MathFloor(((maxSafeMargin / oneLotMargin) + QUANT_EPSILON) / step) * step;
         finalLots = MathMin(finalLots, NormalizeDouble(maxAffordableLots, GetVolumeDigits(step)));
        }

      while(finalLots >= minVol)
        {
         double calcMargin = 0.0;
         if(!OrderCalcMargin(calcOrderType, m_symbol, finalLots, marginCheckPrice, calcMargin))
            calcMargin = 0.0;

         ZeroMemory(simRes);
         simReq.volume = finalLots;
         bool checkOk  = OrderCheck(simReq, simRes);

         marginRequired = MathMax(calcMargin, (checkOk || simRes.margin > 0.0) ? simRes.margin : 0.0);
         if(marginRequired <= 0.0 && oneLotMargin > 0.0)
            marginRequired = finalLots * oneLotMargin;

         double verifiedPosPL = 0.0;
         bool   profitCalcOk  = OrderCalcProfit(calcOrderType, m_symbol, finalLots, entryPrice, stopLossPrice, verifiedPosPL);
         double verifiedRisk  = (profitCalcOk && MathIsValidNumber(verifiedPosPL))
                                ? (MathAbs(verifiedPosPL) + (finalLots * m_commissionPerLotRoundTurn))
                                : (finalLots * lossPerLot);

         if(marginRequired <= maxSafeMargin &&
            (freeMargin - marginRequired) > 0.0 &&
            simRes.retcode != TRADE_RETCODE_NO_MONEY &&
            (finalLots <= minVol + QUANT_EPSILON || verifiedRisk <= (riskCapitalUSD * 1.01 + QUANT_EPSILON)))
            break;

         finalLots = NormalizeDouble(finalLots - step, GetVolumeDigits(step));
        }

      if(finalLots < minVol)
        {
         outResult.diagnosticNote = StringFormat(
            "Insufficient free margin ($%.2f) for minimum volume %.2f (requires $%.2f)",
            freeMargin, minVol, marginRequired);
         return false;
        }

      double actualCapitalAtRisk    = finalLots * lossPerLot;
      outResult.isAllowed           = true;
      outResult.finalLots           = finalLots;
      outResult.rawLots             = rawLots;
      outResult.baseRiskPct         = baseRiskPct;
      outResult.effectiveRiskPct    = (actualCapitalAtRisk / equity) * 100.0;
      outResult.baseRiskUSD         = baseRiskUSD;
      outResult.houseMoneyBonusUSD  = houseMoneyBonusUSD;
      outResult.totalRiskCapitalUSD = actualCapitalAtRisk;
      outResult.slDistancePrice     = slDistancePrice;
      outResult.slTicks             = slTicks;
      outResult.tickSize            = tickSize;
      outResult.tickValue           = tickValue;
      outResult.commissionPerLot    = m_commissionPerLotRoundTurn;
      outResult.lossPerLotUSD       = lossPerLot;
      outResult.requiredMarginUSD   = marginRequired;
      outResult.freeMarginAfterUSD  = freeMargin - marginRequired;
      outResult.diagnosticNote      = StringFormat(
         "OK [Mode=%s | P=%.3f | Lots=%.2f | Risk=$%.2f (%.2f%%) | SL=%.3f JPY | Loss/Lot=$%.2f]",
         RiskModeToString(m_riskMode), onnxWinProbability, finalLots,
         actualCapitalAtRisk, outResult.effectiveRiskPct, slDistancePrice, lossPerLot);

      if(m_logger != NULL)
         m_logger.Debug(outResult.diagnosticNote);

      return true;
     }
  };

#endif // USDJPY_QUANT_POSITION_SIZER_MQH
