//+------------------------------------------------------------------+
//|                                                PositionSizer.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|   Layer 3 Risk: Dual-Mode Lot Sizing, Commission & Margin Engine |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_POSITION_SIZER_MQH
#define XAUUSD_QUANT_POSITION_SIZER_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"
#include "EquityGuard.mqh"

//+------------------------------------------------------------------+
//| CPositionSizer: Precision XAUUSD Lot & House-Money Calculator    |
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

   //--- Resolve accurate loss tick value for XAUUSD across broker specs
   double         ResolveLossTickValue(const double tickSize) const
     {
      double tickValLoss = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValLoss > 0.0)
         return tickValLoss;

      double tickVal = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickVal > 0.0)
         return tickVal;

      // Fallback using contract size (typically 100 oz for XAUUSD)
      double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize <= 0.0)
         contractSize = 100.0;
      return contractSize * tickSize;
     }

   //--- Determine volume decimal precision from step size
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

   //--- Initialize Position Sizer
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

   //+------------------------------------------------------------------+
   //| CalculateSniperLots                                              |
   //| Computes exact lot size accounting for ONNX probability tier,    |
   //| Prop vs Growth mode rules, drawdown dampeners, house-money       |
   //| profit buffers, tick value, round-turn commission & free margin. |
   //+------------------------------------------------------------------+
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

      // 1. Validate ONNX Meta-Labeler Probability Threshold (P >= 0.58 required in both modes)
      if(onnxWinProbability < ONNX_PROB_TIER2_MIN)
        {
         outResult.diagnosticNote = StringFormat("ONNX probability %.4f below minimum threshold %.2f",
                                                 onnxWinProbability, ONNX_PROB_TIER2_MIN);
         return false;
        }

      bool isTier1Signal = (onnxWinProbability >= ONNX_PROB_TIER1_MIN);

      // 2. Validate Structural Stop-Loss Distance ($1.20 to $4.00 hard bounds)
      double slDistancePrice = MathAbs(entryPrice - stopLossPrice);
      outResult.slDistancePrice = slDistancePrice;

      if(slDistancePrice < (HARD_MIN_SL_DISTANCE_USD - 1e-5) ||
         slDistancePrice > (HARD_MAX_SL_DISTANCE_USD + 1e-5))
        {
         outResult.diagnosticNote = StringFormat(
            "SL distance $%.2f outside hard sniper bounds [$%.2f, $%.2f]",
            slDistancePrice, HARD_MIN_SL_DISTANCE_USD, HARD_MAX_SL_DISTANCE_USD);
         return false;
        }

      // 3. Query current account metrics
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

      // 4. Compute Mode-Specific Risk Capital (Mode A vs Mode B)
      if(m_riskMode == MODE_PROP_GUARD)
        {
         // --- MODE A: MODE_PROP_GUARD ($50k Prop Firm Protection) ---
         baseRiskPct = isTier1Signal ? m_propTier1RiskPct : m_propTier2RiskPct;

         // Drawdown Dampener: If DD from HWM > 2.50%, multiply risk % by 0.50 until HWM recovered
         if(dampenerActive)
            effectiveRiskPct = baseRiskPct * PROP_DD_DAMPENER_MULTIPLIER;
         else
            effectiveRiskPct = baseRiskPct;

         baseRiskUSD    = equity * (effectiveRiskPct / 100.0);
         riskCapitalUSD = baseRiskUSD;
        }
      else
        {
         // --- MODE B: MODE_ASYMMETRIC_GROWTH ($500 Moonshot Compounder) ---
         baseRiskPct = isTier1Signal ? m_growthTier1RiskPct : m_growthTier2RiskPct;

         // Drawdown Dampener: If trailing DD > 3.00%, clamp trade risk to 0.50% until half recovered
         if(dampenerActive)
           {
            effectiveRiskPct = GROWTH_DD_DAMPENER_CLAMP_PCT;
            baseRiskUSD      = equity * (effectiveRiskPct / 100.0);
            riskCapitalUSD   = baseRiskUSD;
           }
         else
           {
            effectiveRiskPct = baseRiskPct;
            baseRiskUSD      = equity * (effectiveRiskPct / 100.0);
            riskCapitalUSD   = baseRiskUSD;

            // House-Money Profit Buffer Accelerator:
            // Whenever WeeklyRealizedProfitUSD > 0 AND Tier-1 ONNX signal (P >= 0.72),
            // add 30% of WeeklyRealizedProfitUSD to riskCapitalUSD, capped at 2.00% of current equity
            double weeklyProfitUSD = m_equityGuard.GetWeeklyRealizedProfitUSD();
            if(isTier1Signal && weeklyProfitUSD > 0.0)
              {
               houseMoneyBonusUSD = GROWTH_HOUSE_MONEY_SHARE * weeklyProfitUSD;
               double maxAllowedCapitalUSD = equity * (GROWTH_MAX_EFFECTIVE_RISK_PCT / 100.0);

               if((baseRiskUSD + houseMoneyBonusUSD) > maxAllowedCapitalUSD)
                  houseMoneyBonusUSD = MathMax(0.0, maxAllowedCapitalUSD - baseRiskUSD);

               riskCapitalUSD            = baseRiskUSD + houseMoneyBonusUSD;
               effectiveRiskPct          = (riskCapitalUSD / equity) * 100.0;
               outResult.houseMoneyApplied = (houseMoneyBonusUSD > 0.0);
              }
           }

         // Hard Cap: Never allow a single stop-out to breach 1.80% remaining daily drawdown capacity
         double remDailyDDPct = m_equityGuard.GetRemainingDailyDrawdownCapacityPct();
         double maxDailyRiskPct = MathMin(GROWTH_MAX_REMAINING_DD_CAP_PCT, remDailyDDPct * 0.85);
         double dayStartRef = m_equityGuard.GetDayStartReference();
         double maxDailyRiskUSD = (dayStartRef > 0.0 ? dayStartRef : equity) * (maxDailyRiskPct / 100.0);

         if(riskCapitalUSD > maxDailyRiskUSD)
           {
            riskCapitalUSD     = MathMax(0.0, maxDailyRiskUSD);
            houseMoneyBonusUSD = MathMax(0.0, riskCapitalUSD - baseRiskUSD);
            effectiveRiskPct   = (riskCapitalUSD / equity) * 100.0;
           }
        }

      // 5. Universal Remaining Drawdown Safety Clamp (applies to both Prop and Growth modes)
      double remDailyPct = m_equityGuard.GetRemainingDailyDrawdownCapacityPct();
      double dayRef      = m_equityGuard.GetDayStartReference();
      double safeDailyCapUSD = (dayRef > 0.0 ? dayRef : equity) * (MathMax(0.0, remDailyPct - 0.15) / 100.0);
      if(riskCapitalUSD > safeDailyCapUSD)
        {
         riskCapitalUSD   = MathMax(0.0, safeDailyCapUSD);
         effectiveRiskPct = (riskCapitalUSD / equity) * 100.0;
        }

      if(riskCapitalUSD <= 0.0)
        {
         outResult.diagnosticNote = "Insufficient remaining daily drawdown capacity for trade";
         return false;
        }

      // 6. Exact Lot Sizing Formula (Section 6.1 Specification)
      double tickSize      = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0.0)
         tickSize = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(tickSize <= 0.0)
         tickSize = 0.01;

      double tickValue     = ResolveLossTickValue(tickSize);
      double slTicks       = slDistancePrice / tickSize;
      double lossPerLot    = (slTicks * tickValue) + m_commissionPerLotRoundTurn;

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

      // Handle small accounts (e.g. $500 Moonshot Mode) when rawLots is slightly below minVol (0.01)
      // Only allow clamping up to minVol if the true dollar loss of minVol does not exceed 1.80% equity
      if(finalLots < minVol)
        {
         double minVolTrueLossUSD = minVol * lossPerLot;
         double maxMicroToleranceUSD = equity * (GROWTH_MAX_REMAINING_DD_CAP_PCT / 100.0);
         if(m_riskMode == MODE_ASYMMETRIC_GROWTH &&
            minVolTrueLossUSD <= maxMicroToleranceUSD &&
            minVolTrueLossUSD <= safeDailyCapUSD)
           {
            finalLots          = minVol;
            riskCapitalUSD     = minVolTrueLossUSD;
            effectiveRiskPct   = (riskCapitalUSD / equity) * 100.0;
           }
         else
           {
            outResult.diagnosticNote = StringFormat(
               "Calculated rawLots (%.4f) < SYMBOL_VOLUME_MIN (%.2f) and min lot risk ($%.2f) exceeds cap ($%.2f)",
               rawLots, minVol, minVolTrueLossUSD, MathMin(maxMicroToleranceUSD, safeDailyCapUSD));
            return false;
           }
        }

      if(finalLots > maxVol)
         finalLots = maxVol;

      // 7. Verify Free Margin via OrderCalcMargin() and scale down if necessary
      ENUM_ORDER_TYPE orderType = (direction == SIGNAL_LONG) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      double marginRequired     = 0.0;
      double maxSafeMargin      = freeMargin * m_freeMarginSafetyRatio;

      while(finalLots >= minVol)
        {
         marginRequired = 0.0;
         if(!OrderCalcMargin(orderType, m_symbol, finalLots, entryPrice, marginRequired))
           {
            outResult.diagnosticNote = StringFormat("OrderCalcMargin failed (err=%d)", GetLastError());
            return false;
           }

         if(marginRequired <= maxSafeMargin && (freeMargin - marginRequired) > 0.0)
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

      // 8. Populate complete result struct
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
         "OK [Mode=%s | P=%.3f | Lots=%.2f | Risk=$%.2f (%.2f%%) | SL=$%.2f | Loss/Lot=$%.2f]",
         RiskModeToString(m_riskMode), onnxWinProbability, finalLots,
         actualCapitalAtRisk, outResult.effectiveRiskPct, slDistancePrice, lossPerLot);

      if(m_logger != NULL)
         m_logger.Debug(outResult.diagnosticNote);

      return true;
     }
  };

#endif // XAUUSD_QUANT_POSITION_SIZER_MQH
