//+------------------------------------------------------------------+
//|                                                  Definitions.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|     Layer 0 Core: Enums, Structs, Constants & Shared Utilities   |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_DEFINITIONS_MQH
#define XAUUSD_QUANT_DEFINITIONS_MQH

//+------------------------------------------------------------------+
//| Global System & Mathematical Constants                           |
//+------------------------------------------------------------------+
#define QUANT_EA_VERSION                 "4.00"
#define QUANT_DEFAULT_MAGIC              20260401
#define QUANT_EPSILON                    1e-9
#define ONNX_FEATURE_COUNT               12
#define VP_DEFAULT_BIN_SIZE_USD          0.25
#define VP_VALUE_AREA_PCT                0.70
#define VP_LVN_THRESHOLD_RATIO           0.30
#define MAX_LVN_COUNT                    64
#define MAX_FRACTAL_POOLS                128

//--- Hard Non-Negotiable Drawdown & Ceiling Constants
#define HARD_DAILY_DD_CEILING_PCT        3.00
#define PROP_DAILY_DD_BREAKER_PCT        2.25
#define GROWTH_DAILY_DD_BREAKER_PCT      2.40

#define HARD_MAX_TOTAL_DD_CEILING_PCT    6.00
#define PROP_TOTAL_DD_BREAKER_PCT        5.20
#define GROWTH_TOTAL_DD_BREAKER_PCT      5.40

//--- Sniper Stop-Loss Guardrails (in USD on XAUUSD, dynamically lot-scaled by PositionSizer)
#define HARD_MIN_SL_DISTANCE_USD         1.20
#define HARD_MAX_SL_DISTANCE_USD         10.50
#define IDEAL_MIN_SL_DISTANCE_USD        1.50
#define IDEAL_MAX_SL_DISTANCE_USD        3.50

//--- ONNX Meta-Labeler Probability Thresholds
#define ONNX_PROB_TIER2_MIN              0.58
#define ONNX_PROB_TIER1_MIN              0.72

//--- Mode A (Prop Guard) Risk Parameters
#define PROP_TIER2_RISK_PCT              1.05
#define PROP_TIER1_RISK_PCT              1.88
#define PROP_HOUSE_MONEY_SHARE           0.25
#define PROP_MAX_EFFECTIVE_RISK_PCT      1.98
#define PROP_DD_DAMPENER_TRIGGER_PCT     2.00
#define PROP_DD_DAMPENER_MULTIPLIER      0.60
#define PROP_MAX_CONSECUTIVE_LOSSES      2
#define PROP_DAILY_PROFIT_LOCK_PCT       5.20

//--- Mode B (Asymmetric Growth) Risk Parameters
#define GROWTH_TIER2_RISK_PCT            1.10
#define GROWTH_TIER1_RISK_PCT            1.92
#define GROWTH_HOUSE_MONEY_SHARE         0.40
#define GROWTH_MAX_EFFECTIVE_RISK_PCT    2.15
#define GROWTH_MAX_REMAINING_DD_CAP_PCT  2.15
#define GROWTH_DD_DAMPENER_TRIGGER_PCT   2.50
#define GROWTH_DD_DAMPENER_CLAMP_PCT     0.65

//+------------------------------------------------------------------+
//| System Enumerations                                              |
//+------------------------------------------------------------------+

//--- Dual-Scale Account Operating Mode
enum ENUM_RISK_MODE
  {
   MODE_PROP_GUARD        = 0,  // Prop Guard Mode ($50k+ Prop Account Protection)
   MODE_ASYMMETRIC_GROWTH = 1   // Asymmetric Growth Mode ($500 Moonshot Compounder)
  };

//--- Maximum Drawdown Calculation Reference Type
enum ENUM_DD_TYPE
  {
   DD_TRAILING_HWM   = 0,       // Trailing from Account High-Water Mark (Equity/Balance Peak)
   DD_STATIC_INITIAL = 1        // Static from Initial Account Starting Balance
  };

//--- Directional Bias / Trade Signal Direction
enum ENUM_SIGNAL_DIRECTION
  {
   SIGNAL_NONE  =  0,           // Neutral / No Active Signal
   SIGNAL_LONG  =  1,           // Bullish Sweep of Low -> Buy Limit
   SIGNAL_SHORT = -1            // Bearish Sweep of High -> Sell Limit
  };

//--- Layer 1 Deterministic 4-State Finite State Machine
enum ENUM_SWEEP_STATE
  {
   STATE_IDLE              = 0, // Monitoring active Killzone for liquidity sweep
   STATE_SWEEP_DETECTED    = 1, // Liquidity pool or external LVN pierced within ATR bounds
   STATE_RECLAIM_CONFIRMED = 2, // M5 close inside level + volume absorption + MSS/FVG confirmed
   STATE_PENDING_LIMIT     = 3  // Sniper Limit Order active in market awaiting fill or expiry
  };

//--- Institutional Reference Liquidity Pool Classification
enum ENUM_LIQUIDITY_TYPE
  {
   LIQ_NONE              = 0,   // Unclassified
   LIQ_ASIAN_HIGH        = 1,   // Asian Session High (00:00 - 07:00 UTC)
   LIQ_ASIAN_LOW         = 2,   // Asian Session Low (00:00 - 07:00 UTC)
   LIQ_PDH               = 3,   // Previous Day High
   LIQ_PDL               = 4,   // Previous Day Low
   LIQ_M15_SWING_HIGH    = 5,   // M15 5-Bar Fractal Swing High
   LIQ_M15_SWING_LOW     = 6,   // M15 5-Bar Fractal Swing Low
   LIQ_EQUAL_HIGHS       = 7,   // Clustered Equal Highs (within 0.15 * ATR_M15)
   LIQ_EQUAL_LOWS        = 8,   // Clustered Equal Lows (within 0.15 * ATR_M15)
   LIQ_EXTERNAL_LVN_HIGH = 9,   // External Low Volume Node Above VAH
   LIQ_EXTERNAL_LVN_LOW  = 10   // External Low Volume Node Below VAL
  };

//--- Intraday Session & Killzone Windows (UTC)
enum ENUM_KILLZONE_SESSION
  {
   SESSION_OUTSIDE_KILLZONE   = 0, // Outside active execution windows
   SESSION_ASIAN_ACCUMULATION = 1, // Asian Range Building (00:00 - 07:00 UTC)
   SESSION_LONDON_KILLZONE    = 2, // London Killzone (07:00 - 10:30 UTC)
   SESSION_NY_KILLZONE        = 3, // New York Killzone (12:30 - 16:00 UTC)
   SESSION_ROLLOVER_BLACKOUT  = 4  // Rollover Blackout Window (20:55 - 22:10 UTC)
  };

//--- Telemetry Logger Severity Levels
enum ENUM_LOG_LEVEL
  {
   LOG_DEBUG    = 0,            // Granular state & tick diagnostics
   LOG_INFO     = 1,            // Normal operational lifecycle events
   LOG_WARN     = 2,            // Non-fatal warnings, spread spikes, rejected signals
   LOG_ERROR    = 3,            // Execution or ONNX runtime failures
   LOG_CRITICAL = 4             // Hard circuit breaker trips & emergency liquidations
  };

//--- Layer 3 Equity Guard Breach / Stand-Down Reasons
enum ENUM_BREACH_REASON
  {
   BREACH_NONE                 = 0, // All risk systems nominal
   BREACH_DAILY_DRAWDOWN       = 1, // Hard Daily Drawdown Breaker tripped
   BREACH_MAX_TOTAL_DRAWDOWN   = 2, // Hard Max Total Drawdown Breaker tripped
   BREACH_CONSECUTIVE_LOSSES   = 3, // Max consecutive daily losses reached (Prop Mode)
   BREACH_DAILY_PROFIT_TARGET  = 4, // Daily realized profit lock reached (+2.0% Prop Mode)
   BREACH_ROLLOVER_WINDOW      = 5, // Rollover blackout active (20:55 - 22:10 UTC)
   BREACH_HIGH_IMPACT_NEWS     = 6, // High-impact USD economic event window (+/- 15m)
   BREACH_SPREAD_WIDENING      = 7  // Current spread > 1.8x 5-minute rolling average spread
  };

//+------------------------------------------------------------------+
//| Structured Data Payloads                                         |
//+------------------------------------------------------------------+

//--- Individual Intraday or Daily Liquidity Level Descriptor
struct SLiquidityPool
  {
   double              price;
   datetime            formedTime;
   ENUM_LIQUIDITY_TYPE poolType;
   int                 touchCount;
   bool                isSwept;
   datetime            sweptTime;
   bool                isEqualCluster;

   void Reset()
     {
      price          = 0.0;
      formedTime     = 0;
      poolType       = LIQ_NONE;
      touchCount     = 0;
      isSwept        = false;
      sweptTime      = 0;
      isEqualCluster = false;
     }
  };

//--- Session Reference Levels & Volatility Regime Filter State
struct SSessionReference
  {
   datetime              sessionDateUTC;
   double                asianHigh;
   double                asianLow;
   double                asianRange;
   bool                  asianComplete;
   double                pdh;
   double                pdl;
   double                adr20;
   double                atrM15Current;
   double                atrM15Percentile5th;
   double                atrM5Current;
   double                atrH1Current;
   double                atrH4Current;
   bool                  isAsianExhausted;
   bool                  isVolatilityCompressed;
   bool                  isTradableRegime;
   ENUM_KILLZONE_SESSION currentSession;

   void Reset()
     {
      sessionDateUTC         = 0;
      asianHigh              = 0.0;
      asianLow               = 0.0;
      asianRange             = 0.0;
      asianComplete          = false;
      pdh                    = 0.0;
      pdl                    = 0.0;
      adr20                  = 0.0;
      atrM15Current          = 0.0;
      atrM15Percentile5th    = 0.0;
      atrM5Current           = 0.0;
      atrH1Current           = 0.0;
      atrH4Current           = 0.0;
      isAsianExhausted       = false;
      isVolatilityCompressed = false;
      isTradableRegime       = false;
      currentSession         = SESSION_OUTSIDE_KILLZONE;
     }
  };

//--- Rolling Intraday M1 Volume Profile Snapshot
struct SVolumeProfileSnapshot
  {
   datetime profileDayStartUTC;
   datetime lastUpdatedBarTime;
   double   sessionHigh;
   double   sessionLow;
   double   binSizeUSD;
   int      totalBins;
   double   totalSessionVolume;
   double   vpoc;
   double   vah;
   double   val;
   int      lvnCount;
   double   lvnPrices[MAX_LVN_COUNT];
   bool     isValid;

   void Reset()
     {
      profileDayStartUTC = 0;
      lastUpdatedBarTime = 0;
      sessionHigh        = 0.0;
      sessionLow         = 0.0;
      binSizeUSD         = VP_DEFAULT_BIN_SIZE_USD;
      totalBins          = 0;
      totalSessionVolume = 0.0;
      vpoc               = 0.0;
      vah                = 0.0;
      val                = 0.0;
      lvnCount           = 0;
      ArrayInitialize(lvnPrices, 0.0);
      isValid            = false;
     }

   //--- Locate nearest external LVN outside Value Area [VAL, VAH]
   bool FindNearestExternalLVN(const double referencePrice,
                               const bool searchAboveVAH,
                               double &outLvnPrice) const
     {
      outLvnPrice = 0.0;
      if(!isValid || lvnCount <= 0)
         return false;

      double minDistance = DBL_MAX;
      bool   found       = false;

      for(int i = 0; i < lvnCount && i < MAX_LVN_COUNT; i++)
        {
         double nodePrice = lvnPrices[i];
         if(nodePrice <= 0.0)
            continue;

         if(searchAboveVAH && nodePrice <= vah)
            continue;
         if(!searchAboveVAH && nodePrice >= val)
            continue;

         double dist = MathAbs(referencePrice - nodePrice);
         if(dist < minDistance)
           {
            minDistance = dist;
            outLvnPrice = nodePrice;
            found       = true;
           }
        }
      return found;
     }
  };

//--- Exact 12-Feature Stationary Input Vector for Native ONNX Inference
struct SStationaryFeatures
  {
   double f0_sweep_depth_norm;      // [0] (Sweep_Extreme_Distance_Beyond_Level) / ATR_M15(14)
   double f1_wick_body_ratio;       // [1] Rejection_Wick_Size / MathMax(Candle_Range, 0.01)
   double f2_bars_outside_level;    // [2] M1 bars spent beyond swept level before reclaim / 15.0
   double f3_rel_tick_volume;       // [3] Sweep_M5_TickVol / SMA(M5_TickVol, 20)
   double f4_vpoc_distance_norm;    // [4] MathAbs(Entry_Price - Session_VPOC) / ATR_M15(14)
   double f5_value_area_width_norm; // [5] (Session_VAH - Session_VAL) / ATR_H1(14)
   double f6_h1_adx;                // [6] ADX(H1, 14) / 100.0
   double f7_hurst_exponent;        // [7] Rolling 100-bar M5 Hurst Exponent H in [0, 1]
   double f8_volatility_ratio;      // [8] ATR_M15(14) / ATR_H4(14)
   double f9_hour_sin;              // [9] MathSin(2.0 * M_PI * Current_UTC_Hour / 24.0)
   double f10_hour_cos;             // [10] MathCos(2.0 * M_PI * Current_UTC_Hour / 24.0)
   double f11_spread_to_sl_ratio;   // [11] (Current_Spread_In_Dollars) / Stop_Loss_Distance_In_Dollars

   float  tensor[ONNX_FEATURE_COUNT];

   void Reset()
     {
      f0_sweep_depth_norm      = 0.0;
      f1_wick_body_ratio       = 0.0;
      f2_bars_outside_level    = 0.0;
      f3_rel_tick_volume       = 0.0;
      f4_vpoc_distance_norm    = 0.0;
      f5_value_area_width_norm = 0.0;
      f6_h1_adx                = 0.0;
      f7_hurst_exponent        = 0.5;
      f8_volatility_ratio      = 1.0;
      f9_hour_sin              = 0.0;
      f10_hour_cos             = 1.0;
      f11_spread_to_sl_ratio   = 0.0;
      for(int i = 0; i < ONNX_FEATURE_COUNT; i++)
         tensor[i] = 0.0f;
     }

   void SyncTensor()
     {
      tensor[0]  = (float)f0_sweep_depth_norm;
      tensor[1]  = (float)f1_wick_body_ratio;
      tensor[2]  = (float)f2_bars_outside_level;
      tensor[3]  = (float)f3_rel_tick_volume;
      tensor[4]  = (float)f4_vpoc_distance_norm;
      tensor[5]  = (float)f5_value_area_width_norm;
      tensor[6]  = (float)f6_h1_adx;
      tensor[7]  = (float)f7_hurst_exponent;
      tensor[8]  = (float)f8_volatility_ratio;
      tensor[9]  = (float)f9_hour_sin;
      tensor[10] = (float)f10_hour_cos;
      tensor[11] = (float)f11_spread_to_sl_ratio;
     }

   void CopyToFloatArray(float &outFeatures[]) const
     {
      ArrayResize(outFeatures, ONNX_FEATURE_COUNT);
      for(int i = 0; i < ONNX_FEATURE_COUNT; i++)
         outFeatures[i] = tensor[i];
     }
  };

//--- Layer 1 Candidate Setup Payload
struct SSweepCandidateSetup
  {
   ulong                 setupId;
   datetime              sweepBarTime;
   datetime              reclaimBarTime;
   datetime              signalTimeUTC;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_LIQUIDITY_TYPE   sweptPoolType;
   double                sweptLevelPrice;
   double                sweepExtremePrice;
   double                sweepDepthUSD;
   double                rejectionWickUSD;
   double                reclaimCandleRangeUSD;
   int                   m1BarsOutsideLevel;
   double                sweepM5TickVolume;
   double                sma20M5TickVolume;
   bool                  hasFVG;
   double                fvgProximalPrice;
   double                fvgDistalPrice;
   bool                  hasMSS;
   double                mssBreakLevel;
   double                entryLimitPrice;
   double                stopLossPrice;
   double                slDistanceUSD;
   double                tp1Price;
   double                tp2Price;
   double                vpocAtSignal;
   double                vahAtSignal;
   double                valAtSignal;
   double                opposingLiquidityPrice;
   int                   expiryM5Bars;
   bool                  isValid;

   void Reset()
     {
      setupId                = 0;
      sweepBarTime           = 0;
      reclaimBarTime         = 0;
      signalTimeUTC          = 0;
      direction              = SIGNAL_NONE;
      sweptPoolType          = LIQ_NONE;
      sweptLevelPrice        = 0.0;
      sweepExtremePrice      = 0.0;
      sweepDepthUSD          = 0.0;
      rejectionWickUSD       = 0.0;
      reclaimCandleRangeUSD  = 0.0;
      m1BarsOutsideLevel     = 0;
      sweepM5TickVolume      = 0.0;
      sma20M5TickVolume      = 0.0;
      hasFVG                 = false;
      fvgProximalPrice       = 0.0;
      fvgDistalPrice         = 0.0;
      hasMSS                 = false;
      mssBreakLevel          = 0.0;
      entryLimitPrice        = 0.0;
      stopLossPrice          = 0.0;
      slDistanceUSD          = 0.0;
      tp1Price               = 0.0;
      tp2Price               = 0.0;
      vpocAtSignal           = 0.0;
      vahAtSignal            = 0.0;
      valAtSignal            = 0.0;
      opposingLiquidityPrice = 0.0;
      expiryM5Bars           = 3;
      isValid                = false;
     }
  };

//--- Layer 2 ONNX Meta-Labeler Prediction Output
struct SOnnxPrediction
  {
   bool   inferenceSuccess;
   bool   usedDeterministicFallback;
   long   predictedClassLabel;
   double winProbability;
   int    riskTier;                  // 0 = Reject (<0.58), 2 = Tier-2 [0.58,0.72), 1 = Tier-1 (>=0.72)
   double inferenceTimeMicroseconds;
   string statusMessage;

   void Reset()
     {
      inferenceSuccess          = false;
      usedDeterministicFallback = false;
      predictedClassLabel       = 0;
      winProbability            = 0.0;
      riskTier                  = 0;
      inferenceTimeMicroseconds = 0.0;
      statusMessage             = "";
     }
  };

//--- Layer 3 Real-Time Risk & Equity Protection State Snapshot
struct SRiskStateSnapshot
  {
   ENUM_RISK_MODE     riskMode;
   ENUM_DD_TYPE       ddType;
   double             initialBalance;
   double             highWaterMark;
   double             dayStartReference;
   double             weekStartBalance;
   double             currentBalance;
   double             currentEquity;
   double             dailyDrawdownUSD;
   double             dailyDrawdownPct;
   double             dailyBreakerLimitPct;
   double             totalDrawdownUSD;
   double             totalDrawdownPct;
   double             totalBreakerLimitPct;
   double             dailyRealizedPnLUSD;
   double             dailyRealizedPnLPct;
   double             weeklyRealizedProfitUSD;
   double             recoveryAnchorDrawdownPct;
   int                consecutiveLossesToday;
   bool               tradingHaltedToday;
   bool               permanentLockout;
   ENUM_BREACH_REASON activeBreachReason;
   double             currentSpreadUSD;
   double             rollingAvgSpreadUSD;
   bool               spreadGuardTripped;
   bool               newsWindowBlocked;
   bool               rolloverWindowBlocked;
   string             activeNewsEventTitle;

   void Reset()
     {
      riskMode                  = MODE_PROP_GUARD;
      ddType                    = DD_TRAILING_HWM;
      initialBalance            = 0.0;
      highWaterMark             = 0.0;
      dayStartReference         = 0.0;
      weekStartBalance          = 0.0;
      currentBalance            = 0.0;
      currentEquity             = 0.0;
      dailyDrawdownUSD          = 0.0;
      dailyDrawdownPct          = 0.0;
      dailyBreakerLimitPct      = PROP_DAILY_DD_BREAKER_PCT;
      totalDrawdownUSD          = 0.0;
      totalDrawdownPct          = 0.0;
      totalBreakerLimitPct      = PROP_TOTAL_DD_BREAKER_PCT;
      dailyRealizedPnLUSD       = 0.0;
      dailyRealizedPnLPct       = 0.0;
      weeklyRealizedProfitUSD   = 0.0;
      recoveryAnchorDrawdownPct = 0.0;
      consecutiveLossesToday    = 0;
      tradingHaltedToday        = false;
      permanentLockout          = false;
      activeBreachReason        = BREACH_NONE;
      currentSpreadUSD          = 0.0;
      rollingAvgSpreadUSD       = 0.0;
      spreadGuardTripped        = false;
      newsWindowBlocked         = false;
      rolloverWindowBlocked     = false;
      activeNewsEventTitle      = "";
     }
  };

//--- Layer 3 Position Sizer Computation Result
struct SLotCalculationResult
  {
   bool   isAllowed;
   double finalLots;
   double rawLots;
   double baseRiskPct;
   double effectiveRiskPct;
   double baseRiskUSD;
   double houseMoneyBonusUSD;
   double totalRiskCapitalUSD;
   double slDistancePrice;
   double slTicks;
   double tickSize;
   double tickValue;
   double commissionPerLot;
   double lossPerLotUSD;
   double requiredMarginUSD;
   double freeMarginAfterUSD;
   bool   dampenerApplied;
   bool   houseMoneyApplied;
   string diagnosticNote;

   void Reset()
     {
      isAllowed           = false;
      finalLots           = 0.0;
      rawLots             = 0.0;
      baseRiskPct         = 0.0;
      effectiveRiskPct    = 0.0;
      baseRiskUSD         = 0.0;
      houseMoneyBonusUSD  = 0.0;
      totalRiskCapitalUSD = 0.0;
      slDistancePrice     = 0.0;
      slTicks             = 0.0;
      tickSize            = 0.0;
      tickValue           = 0.0;
      commissionPerLot    = 0.0;
      lossPerLotUSD       = 0.0;
      requiredMarginUSD   = 0.0;
      freeMarginAfterUSD  = 0.0;
      dampenerApplied     = false;
      houseMoneyApplied   = false;
      diagnosticNote      = "";
     }
  };

//--- Layer 3 Active Order / Position Lifecycle Context
struct SActiveTradeContext
  {
   bool                  hasPendingOrder;
   bool                  hasOpenPosition;
   ulong                 pendingOrderTicket;
   ulong                 positionTicket;
   ulong                 setupId;
   ENUM_SIGNAL_DIRECTION direction;
   ENUM_LIQUIDITY_TYPE   sweptPoolType;
   datetime              orderPlacedTime;
   datetime              orderPlacedM5BarTime;
   datetime              positionOpenTime;
   int                   expiryM5Bars;
   double                plannedEntryPrice;
   double                actualEntryPrice;
   double                initialStopLoss;
   double                currentStopLoss;
   double                initialRiskDistanceUSD;
   double                tp1Price;
   double                tp2Price;
   double                initialLots;
   double                remainingLots;
   double                riskCapitalUSD;
   bool                  tp1Executed;
   bool                  movedToBreakeven;
   double                onnxProbability;
   int                   riskTier;
   SStationaryFeatures   setupFeatures;
   double                maxFavorableExcursionR;
   double                maxAdverseExcursionR;

   void Reset()
     {
      hasPendingOrder        = false;
      hasOpenPosition        = false;
      pendingOrderTicket     = 0;
      positionTicket         = 0;
      setupId                = 0;
      direction              = SIGNAL_NONE;
      sweptPoolType          = LIQ_NONE;
      orderPlacedTime        = 0;
      orderPlacedM5BarTime   = 0;
      positionOpenTime       = 0;
      expiryM5Bars           = 3;
      plannedEntryPrice      = 0.0;
      actualEntryPrice       = 0.0;
      initialStopLoss        = 0.0;
      currentStopLoss        = 0.0;
      initialRiskDistanceUSD = 0.0;
      tp1Price               = 0.0;
      tp2Price               = 0.0;
      initialLots            = 0.0;
      remainingLots          = 0.0;
      riskCapitalUSD         = 0.0;
      tp1Executed            = false;
      movedToBreakeven       = false;
      onnxProbability        = 0.0;
      riskTier               = 0;
      setupFeatures.Reset();
      maxFavorableExcursionR = 0.0;
      maxAdverseExcursionR   = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| Shared Pure Utility & Conversion Functions                       |
//+------------------------------------------------------------------+

//--- Normalize price to symbol tick size (prevents 10015/10016 invalid price/stops) and digits (prevents IEEE 754 .999999)
inline double NormalizeSymbolPrice(const string symbol, const double rawPrice)
  {
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0)
      tickSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(tickSize > 0.0)
      return NormalizeDouble(MathRound(rawPrice / tickSize) * tickSize, digits);
   return NormalizeDouble(rawPrice, digits);
  }

//--- Normalize volume downward to symbol volume step and clamp to [min, max]
inline double NormalizeSymbolLots(const string symbol, const double rawLots)
  {
   double step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)
      step = 0.01;

   double stepped = MathFloor((rawLots + QUANT_EPSILON) / step) * step;
   int lotDigits  = 2;
   if(step >= 1.0)
      lotDigits = 0;
   else if(step >= 0.1)
      lotDigits = 1;
   else if(step >= 0.01)
      lotDigits = 2;
   else
      lotDigits = 3;

   stepped = NormalizeDouble(stepped, lotDigits);
   if(stepped < minVol)
      return 0.0;
   if(stepped > maxVol)
      stepped = maxVol;
   return stepped;
  }

//--- Dynamically resolve Broker Server -> GMT/UTC offset in seconds
//    - Live / Demo / VPS: Auto-detects offset via TimeTradeServer()/TimeCurrent() vs TimeGMT(),
//      quantized to nearest 15-minute (900s) timezone boundary (immune to tick lag & PC clock drift).
//    - Strategy Tester: Uses fallbackGMTOffsetHours because MT5 Tester sets TimeGMT() == TimeCurrent().
inline int ResolveEffectiveGMTOffsetSeconds(const int fallbackGMTOffsetHours)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return (fallbackGMTOffsetHours * 3600);

   datetime gmtNow    = TimeGMT();
   datetime serverNow = TimeTradeServer();
   datetime tickNow   = TimeCurrent();

   // Prefer TimeCurrent() when market is actively ticking (within 5 minutes of TimeTradeServer)
   if(tickNow > 0 && (serverNow <= 0 || MathAbs((long)tickNow - (long)serverNow) < 300))
      serverNow = tickNow;

   if(gmtNow > 0 && serverNow > 0)
     {
      double diffSeconds = (double)((long)serverNow - (long)gmtNow);
      double diffHours   = diffSeconds / 3600.0;
      if(diffHours >= -12.5 && diffHours <= 14.5)
        {
         long quantizedSeconds = (long)MathRound(diffSeconds / 900.0) * 900;
         return (int)quantizedSeconds;
        }
     }

   return (fallbackGMTOffsetHours * 3600);
  }

//--- Return effective Broker GMT offset in hours (for logging & HUD display)
inline double ResolveEffectiveGMTOffsetHours(const int fallbackGMTOffsetHours)
  {
   return ((double)ResolveEffectiveGMTOffsetSeconds(fallbackGMTOffsetHours) / 3600.0);
  }

//--- Resolve current UTC timestamp reliably across live & Strategy Tester
inline datetime ResolveCurrentUTCTime(const int brokerGMTOffsetHours, const bool useAutoTimeGMT = true)
  {
   if(MQLInfoInteger(MQL_TESTER) || !useAutoTimeGMT)
      return (TimeCurrent() - (datetime)(brokerGMTOffsetHours * 3600));

   return (TimeCurrent() - (datetime)ResolveEffectiveGMTOffsetSeconds(brokerGMTOffsetHours));
  }

//--- Convert Broker Server Time to UTC using auto-detected offset (or fallback in Tester)
inline datetime ServerTimeToUTC(const datetime serverTime, const int brokerGMTOffsetHours)
  {
   return (serverTime - (datetime)ResolveEffectiveGMTOffsetSeconds(brokerGMTOffsetHours));
  }

//--- Convert UTC Time to Broker Server Time using auto-detected offset (or fallback in Tester)
inline datetime UTCTimeToServer(const datetime utcTime, const int brokerGMTOffsetHours)
  {
   return (utcTime + (datetime)ResolveEffectiveGMTOffsetSeconds(brokerGMTOffsetHours));
  }

//--- Human-readable string formatters for telemetry & logging
inline string RiskModeToString(const ENUM_RISK_MODE mode)
  {
   switch(mode)
     {
      case MODE_PROP_GUARD:        return "MODE_PROP_GUARD";
      case MODE_ASYMMETRIC_GROWTH: return "MODE_ASYMMETRIC_GROWTH";
      default:                     return "UNKNOWN_RISK_MODE";
     }
  }

inline string SweepStateToString(const ENUM_SWEEP_STATE state)
  {
   switch(state)
     {
      case STATE_IDLE:              return "STATE_IDLE";
      case STATE_SWEEP_DETECTED:    return "STATE_SWEEP_DETECTED";
      case STATE_RECLAIM_CONFIRMED: return "STATE_RECLAIM_CONFIRMED";
      case STATE_PENDING_LIMIT:     return "STATE_PENDING_LIMIT";
      default:                      return "STATE_UNKNOWN";
     }
  }

inline string DirectionToString(const ENUM_SIGNAL_DIRECTION dir)
  {
   if(dir == SIGNAL_LONG)  return "LONG";
   if(dir == SIGNAL_SHORT) return "SHORT";
   return "NONE";
  }

inline string LiquidityTypeToString(const ENUM_LIQUIDITY_TYPE type)
  {
   switch(type)
     {
      case LIQ_ASIAN_HIGH:        return "ASIAN_HIGH";
      case LIQ_ASIAN_LOW:         return "ASIAN_LOW";
      case LIQ_PDH:               return "PDH";
      case LIQ_PDL:               return "PDL";
      case LIQ_M15_SWING_HIGH:    return "M15_SWING_HIGH";
      case LIQ_M15_SWING_LOW:     return "M15_SWING_LOW";
      case LIQ_EQUAL_HIGHS:       return "EQUAL_HIGHS";
      case LIQ_EQUAL_LOWS:        return "EQUAL_LOWS";
      case LIQ_EXTERNAL_LVN_HIGH: return "EXTERNAL_LVN_HIGH";
      case LIQ_EXTERNAL_LVN_LOW:  return "EXTERNAL_LVN_LOW";
      default:                    return "LIQ_NONE";
     }
  }

inline string KillzoneSessionToString(const ENUM_KILLZONE_SESSION session)
  {
   switch(session)
     {
      case SESSION_ASIAN_ACCUMULATION: return "ASIAN_ACCUMULATION";
      case SESSION_LONDON_KILLZONE:    return "LONDON_KILLZONE";
      case SESSION_NY_KILLZONE:        return "NY_KILLZONE";
      case SESSION_ROLLOVER_BLACKOUT:  return "ROLLOVER_BLACKOUT";
      default:                         return "OUTSIDE_KILLZONE";
     }
  }

inline string BreachReasonToString(const ENUM_BREACH_REASON reason)
  {
   switch(reason)
     {
      case BREACH_NONE:                return "NONE";
      case BREACH_DAILY_DRAWDOWN:      return "DAILY_DRAWDOWN_BREAKER";
      case BREACH_MAX_TOTAL_DRAWDOWN:  return "MAX_TOTAL_DRAWDOWN_BREAKER";
      case BREACH_CONSECUTIVE_LOSSES:  return "CONSECUTIVE_LOSS_LIMIT";
      case BREACH_DAILY_PROFIT_TARGET: return "DAILY_PROFIT_LOCK";
      case BREACH_ROLLOVER_WINDOW:     return "ROLLOVER_BLACKOUT";
      case BREACH_HIGH_IMPACT_NEWS:    return "HIGH_IMPACT_USD_NEWS";
      case BREACH_SPREAD_WIDENING:     return "ABNORMAL_SPREAD_GUARD";
      default:                         return "UNKNOWN_BREACH";
     }
  }

inline string LogLevelToString(const ENUM_LOG_LEVEL level)
  {
   switch(level)
     {
      case LOG_DEBUG:    return "DEBUG";
      case LOG_INFO:     return "INFO";
      case LOG_WARN:     return "WARN";
      case LOG_ERROR:    return "ERROR";
      case LOG_CRITICAL: return "CRITICAL";
      default:           return "INFO";
     }
  }

#endif // XAUUSD_QUANT_DEFINITIONS_MQH
