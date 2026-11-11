//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|     Layer 0 Core: Structured Journal & CSV Telemetry Engine      |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_LOGGER_MQH
#define XAUUSD_QUANT_LOGGER_MQH

#include "Definitions.mqh"

//+------------------------------------------------------------------+
//| CQuantLogger: Institutional Telemetry & Audit Trail Manager      |
//+------------------------------------------------------------------+
class CQuantLogger
  {
private:
   string            m_symbol;
   ulong             m_magic;
   ENUM_LOG_LEVEL    m_minLogLevel;
   bool              m_enableCsvTelemetry;
   bool              m_useCommonFolder;
   int               m_brokerGMTOffset;

   string            m_setupCsvFileName;
   string            m_tradeCsvFileName;
   string            m_riskCsvFileName;

   bool              m_setupHeaderWritten;
   bool              m_tradeHeaderWritten;
   bool              m_riskHeaderWritten;

   //--- Ensure CSV file exists with proper header columns
   bool              EnsureCsvHeader(const string fileName, const string headerLine, bool &headerFlag)
     {
      if(headerFlag)
         return true;

      int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
      if(m_useCommonFolder)
         flags |= FILE_COMMON;

      int handle = FileOpen(fileName, flags);
      if(handle == INVALID_HANDLE)
        {
         PrintFormat("[QUANT-LOGGER][ERROR] Unable to open CSV telemetry file '%s' (err=%d)",
                     fileName, GetLastError());
         return false;
        }

      ulong fileSize = FileSize(handle);
      if(fileSize == 0)
        {
         FileWriteString(handle, headerLine + "\r\n");
         FileFlush(handle);
        }

      FileClose(handle);
      headerFlag = true;
      return true;
     }

   //--- Append a pre-formatted CSV row atomically
   bool              AppendCsvRow(const string fileName, const string rowText)
     {
      if(!m_enableCsvTelemetry)
         return false;

      int flags = FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE;
      if(m_useCommonFolder)
         flags |= FILE_COMMON;

      int handle = FileOpen(fileName, flags);
      if(handle == INVALID_HANDLE)
         return false;

      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, rowText + "\r\n");
      FileFlush(handle);
      FileClose(handle);
      return true;
     }

public:
                     CQuantLogger()
     {
      m_symbol              = _Symbol;
      m_magic               = QUANT_DEFAULT_MAGIC;
      m_minLogLevel         = LOG_INFO;
      m_enableCsvTelemetry  = true;
      m_useCommonFolder     = false;
      m_brokerGMTOffset     = 2;
      m_setupCsvFileName    = "xauusd_setup_telemetry.csv";
      m_tradeCsvFileName    = "xauusd_trade_journal.csv";
      m_riskCsvFileName     = "xauusd_risk_events.csv";
      m_setupHeaderWritten  = false;
      m_tradeHeaderWritten  = false;
      m_riskHeaderWritten   = false;
     }

                    ~CQuantLogger() {}

   //--- Initialize logger and prepare CSV headers
   bool              Init(const string symbol,
                          const ulong magic,
                          const ENUM_LOG_LEVEL minLevel,
                          const bool enableCsv,
                          const int brokerGMTOffsetHours,
                          const bool useCommonFolder = false,
                          const string filePrefix = "xauusd")
     {
      m_symbol             = symbol;
      m_magic              = magic;
      m_minLogLevel        = minLevel;
      m_enableCsvTelemetry = enableCsv;
      m_brokerGMTOffset    = brokerGMTOffsetHours;
      m_useCommonFolder    = useCommonFolder;

      m_setupCsvFileName   = filePrefix + "_setup_telemetry.csv";
      m_tradeCsvFileName   = filePrefix + "_trade_journal.csv";
      m_riskCsvFileName    = filePrefix + "_risk_events.csv";

      m_setupHeaderWritten = false;
      m_tradeHeaderWritten = false;
      m_riskHeaderWritten  = false;

      if(m_enableCsvTelemetry)
        {
         string setupHeader =
            "setup_id,timestamp_utc,server_time,symbol,direction,swept_pool_type,"
            "swept_level_price,sweep_extreme_price,entry_limit_price,stop_loss_price,"
            "sl_distance_usd,tp1_price,tp2_price,vpoc,vah,val,"
            "f0_sweep_depth_norm,f1_wick_body_ratio,f2_bars_outside_level,f3_rel_tick_volume,"
            "f4_vpoc_distance_norm,f5_value_area_width_norm,f6_h1_adx,f7_hurst_exponent,"
            "f8_volatility_ratio,f9_hour_sin,f10_hour_cos,f11_spread_to_sl_ratio,"
            "onnx_prob,risk_tier,event_stage,realized_pnl_usd,realized_r_multiple,"
            "mfe_r,mae_r,label_2_5r";

         string tradeHeader =
            "timestamp_utc,server_time,setup_id,ticket,symbol,event_type,direction,"
            "lots,price,sl,tp1,tp2,onnx_prob,risk_pct,risk_usd,house_money_usd,"
            "realized_pnl_usd,balance_after,equity_after,notes";

         string riskHeader =
            "timestamp_utc,server_time,risk_mode,breach_reason,day_start_ref,high_water_mark,"
            "balance,equity,daily_dd_pct,total_dd_pct,daily_realized_pnl_usd,"
            "weekly_realized_profit_usd,consecutive_losses,spread_usd,rolling_spread_usd,details";

         EnsureCsvHeader(m_setupCsvFileName, setupHeader, m_setupHeaderWritten);
         EnsureCsvHeader(m_tradeCsvFileName, tradeHeader, m_tradeHeaderWritten);
         EnsureCsvHeader(m_riskCsvFileName,  riskHeader,  m_riskHeaderWritten);
        }

      Info(StringFormat("Logger initialized [Symbol=%s | Magic=%I64u | CSV=%s]",
                        m_symbol, m_magic, (m_enableCsvTelemetry ? "ENABLED" : "DISABLED")));
      return true;
     }

   //--- Core terminal journal logging with level filtering
   void              Log(const ENUM_LOG_LEVEL level, const string message)
     {
      if(level < m_minLogLevel)
         return;

      // Suppress non-critical messages during genetic optimization for speed
      if((bool)MQLInfoInteger(MQL_OPTIMIZATION) && level < LOG_CRITICAL)
         return;

      datetime utcNow = ResolveCurrentUTCTime(m_brokerGMTOffset);
      PrintFormat("[%s][%s][%s] %s",
                  TimeToString(utcNow, TIME_DATE | TIME_SECONDS),
                  m_symbol,
                  LogLevelToString(level),
                  message);
     }

   void              Debug(const string msg)    { Log(LOG_DEBUG,    msg); }
   void              Info(const string msg)     { Log(LOG_INFO,     msg); }
   void              Warn(const string msg)     { Log(LOG_WARN,     msg); }
   void              Error(const string msg)    { Log(LOG_ERROR,    msg); }
   void              Critical(const string msg) { Log(LOG_CRITICAL, msg); }

   //+------------------------------------------------------------------+
   //| WriteSetupTelemetryCSV                                           |
   //| Records the exact 12 stationary features, structural levels,     |
   //| ONNX meta-label probability, and realized trade outcome for      |
   //| zero-skew offline Python training & walk-forward auditing.       |
   //+------------------------------------------------------------------+
   bool              WriteSetupTelemetryCSV(const SSweepCandidateSetup &setup,
                                            const SStationaryFeatures &features,
                                            const SOnnxPrediction &prediction,
                                            const string eventStage = "SIGNAL_TRIGGERED",
                                            const double realizedPnLUSD = 0.0,
                                            const double realizedRMultiple = 0.0,
                                            const double mfeR = 0.0,
                                            const double maeR = 0.0,
                                            const int label2_5R = -1)
     {
      if(!m_enableCsvTelemetry)
         return false;

      datetime serverNow = TimeCurrent();
      datetime utcNow    = (setup.signalTimeUTC > 0)
                           ? setup.signalTimeUTC
                           : ResolveCurrentUTCTime(m_brokerGMTOffset);

      string row = StringFormat(
         "%I64u,%s,%s,%s,%d,%s,"
         "%.2f,%.2f,%.2f,%.2f,"
         "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,"
         "%.6f,%.6f,%.6f,%.6f,"
         "%.6f,%.6f,%.6f,%.6f,"
         "%.6f,%.6f,%.6f,%.6f,"
         "%.6f,%d,%s,%.2f,%.4f,"
         "%.4f,%.4f,%d",
         setup.setupId,
         TimeToString(utcNow, TIME_DATE | TIME_SECONDS),
         TimeToString(serverNow, TIME_DATE | TIME_SECONDS),
         m_symbol,
         (int)setup.direction,
         LiquidityTypeToString(setup.sweptPoolType),
         setup.sweptLevelPrice,
         setup.sweepExtremePrice,
         setup.entryLimitPrice,
         setup.stopLossPrice,
         setup.slDistanceUSD,
         setup.tp1Price,
         setup.tp2Price,
         setup.vpocAtSignal,
         setup.vahAtSignal,
         setup.valAtSignal,
         features.f0_sweep_depth_norm,
         features.f1_wick_body_ratio,
         features.f2_bars_outside_level,
         features.f3_rel_tick_volume,
         features.f4_vpoc_distance_norm,
         features.f5_value_area_width_norm,
         features.f6_h1_adx,
         features.f7_hurst_exponent,
         features.f8_volatility_ratio,
         features.f9_hour_sin,
         features.f10_hour_cos,
         features.f11_spread_to_sl_ratio,
         prediction.winProbability,
         prediction.riskTier,
         eventStage,
         realizedPnLUSD,
         realizedRMultiple,
         mfeR,
         maeR,
         label2_5R
      );

      return AppendCsvRow(m_setupCsvFileName, row);
     }

   //+------------------------------------------------------------------+
   //| WriteTradeLifecycleCSV                                           |
   //| Logs limit placement, fill, partial TP1, SL to BE, and exit      |
   //+------------------------------------------------------------------+
   bool              WriteTradeLifecycleCSV(const ulong setupId,
                                            const ulong ticket,
                                            const string eventType,
                                            const ENUM_SIGNAL_DIRECTION direction,
                                            const double lots,
                                            const double price,
                                            const double sl,
                                            const double tp1,
                                            const double tp2,
                                            const double onnxProb,
                                            const double effectiveRiskPct,
                                            const double riskCapitalUSD,
                                            const double houseMoneyUSD,
                                            const double realizedPnLUSD,
                                            const string notes = "")
     {
      if(!m_enableCsvTelemetry)
         return false;

      datetime serverNow = TimeCurrent();
      datetime utcNow    = ResolveCurrentUTCTime(m_brokerGMTOffset);
      double   balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double   equity    = AccountInfoDouble(ACCOUNT_EQUITY);

      string cleanNotes = notes;
      StringReplace(cleanNotes, ",", ";");

      string row = StringFormat(
         "%s,%s,%I64u,%I64u,%s,%s,%s,"
         "%.2f,%.2f,%.2f,%.2f,%.2f,%.4f,%.3f,%.2f,%.2f,"
         "%.2f,%.2f,%.2f,%s",
         TimeToString(utcNow, TIME_DATE | TIME_SECONDS),
         TimeToString(serverNow, TIME_DATE | TIME_SECONDS),
         setupId,
         ticket,
         m_symbol,
         eventType,
         DirectionToString(direction),
         lots,
         price,
         sl,
         tp1,
         tp2,
         onnxProb,
         effectiveRiskPct,
         riskCapitalUSD,
         houseMoneyUSD,
         realizedPnLUSD,
         balance,
         equity,
         cleanNotes
      );

      return AppendCsvRow(m_tradeCsvFileName, row);
     }

   //+------------------------------------------------------------------+
   //| WriteRiskStateCSV                                                |
   //| Logs circuit breaker trips, daily resets, and emergency halts     |
   //+------------------------------------------------------------------+
   bool              WriteRiskStateCSV(const SRiskStateSnapshot &state,
                                       const string details = "")
     {
      if(!m_enableCsvTelemetry)
         return false;

      datetime serverNow = TimeCurrent();
      datetime utcNow    = ResolveCurrentUTCTime(m_brokerGMTOffset);

      string cleanDetails = details;
      StringReplace(cleanDetails, ",", ";");

      string row = StringFormat(
         "%s,%s,%s,%s,%.2f,%.2f,"
         "%.2f,%.2f,%.4f,%.4f,%.2f,"
         "%.2f,%d,%.3f,%.3f,%s",
         TimeToString(utcNow, TIME_DATE | TIME_SECONDS),
         TimeToString(serverNow, TIME_DATE | TIME_SECONDS),
         RiskModeToString(state.riskMode),
         BreachReasonToString(state.activeBreachReason),
         state.dayStartReference,
         state.highWaterMark,
         state.currentBalance,
         state.currentEquity,
         state.dailyDrawdownPct,
         state.totalDrawdownPct,
         state.dailyRealizedPnLUSD,
         state.weeklyRealizedProfitUSD,
         state.consecutiveLossesToday,
         state.currentSpreadUSD,
         state.rollingAvgSpreadUSD,
         cleanDetails
      );

      return AppendCsvRow(m_riskCsvFileName, row);
     }
  };

#endif // XAUUSD_QUANT_LOGGER_MQH
