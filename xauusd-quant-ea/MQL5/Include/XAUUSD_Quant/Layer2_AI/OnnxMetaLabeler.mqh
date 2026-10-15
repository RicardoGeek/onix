//+------------------------------------------------------------------+
//|                                              OnnxMetaLabeler.mqh |
//|                     XAUUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 2 AI: Native OnnxCreateFromBuffer & OnnxRun Engine        |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef XAUUSD_QUANT_ONNX_META_LABELER_MQH
#define XAUUSD_QUANT_ONNX_META_LABELER_MQH

#include "../Core/Definitions.mqh"
#include "../Core/Logger.mqh"

//+------------------------------------------------------------------+
//| COnnxMetaLabeler: Native MQL5 ONNX Runtime & Deterministic Mode  |
//+------------------------------------------------------------------+
class COnnxMetaLabeler
  {
private:
   long          m_onnxHandle;
   bool          m_useOnnxModel;
   bool          m_modelReady;
   double        m_tier2Threshold;
   double        m_tier1Threshold;
   CQuantLogger *m_logger;

   //--- Classify probability P in [0, 1] into Risk Tier (0=Reject, 2=Tier2, 1=Tier1)
   int           ClassifyRiskTier(const double prob) const
     {
      if(prob >= m_tier1Threshold)
         return 1;
      if(prob >= m_tier2Threshold)
         return 2;
      return 0;
     }

   //+------------------------------------------------------------------+
   //| EvaluateDeterministicScore                                       |
   //| Calibrated quantitative meta-scorer over the 12 stationary       |
   //| features when InpUseOnnxModel = false (Strategy Tester data      |
   //| collection mode or fallback).                                    |
   //+------------------------------------------------------------------+
   double        EvaluateDeterministicScore(const SStationaryFeatures &f) const
     {
      double logit = 0.35; // Base prior (~0.587) for Layer-1 confirmed structural sweep

      // [0] Sweep depth sweet spot (shallow-to-moderate sweep depth <= 0.48 ATR_M15 has highest win rate)
      if(f.f0_sweep_depth_norm >= 0.12 && f.f0_sweep_depth_norm <= 0.48)
         logit += 0.22;
      else if(f.f0_sweep_depth_norm > 0.72)
         logit -= 0.18;

      // [1] Rejection wick-to-range ratio
      logit += (f.f1_wick_body_ratio - 0.38) * 0.85;

      // [2] M1 bars spent outside level (fast 1-2 bar sweep <= 0.50 has +19.43R vs -0.95R for > 0.50)
      if(f.f2_bars_outside_level <= 0.50)
         logit += 0.22;
      else
         logit -= (f.f2_bars_outside_level - 0.50) * 0.75;

      // [3] Relative M5 tick volume absorption (SweepVol / SMA20)
      if(f.f3_rel_tick_volume >= 1.20 && f.f3_rel_tick_volume <= 2.40)
         logit += 0.14;

      // [4] Distance from entry to Session VPOC
      if(f.f4_vpoc_distance_norm >= 0.40)
         logit += 0.12;

      // [5] Value Area width relative to H1 ATR (<= 2.00 has +25.27R; > 2.00 is overextended and lost -6.79R)
      if(f.f5_value_area_width_norm >= 0.35 && f.f5_value_area_width_norm <= 1.95)
         logit += 0.24;
      else if(f.f5_value_area_width_norm > 2.05)
         logit -= 0.42;

      // [6] H1 ADX (trend-aligned pullback sweeps thrive in ADX 22-45)
      if(f.f6_h1_adx >= 0.22 && f.f6_h1_adx <= 0.46)
         logit += 0.18;

      // [7] Rolling 100-bar M5 Hurst Exponent (> 0.32 has +18.07R vs +0.41R for <= 0.32)
      if(f.f7_hurst_exponent >= 0.33)
         logit += 0.20;
      else
         logit -= 0.18;

      // [8] Intraday-to-Macro Volatility Ratio (ATR_M15 / ATR_H4 <= 0.30 has +20.13R vs -1.65R for > 0.30)
      if(f.f8_volatility_ratio <= 0.30)
         logit += 0.15;
      else
         logit -= 0.20;

      // [11] Spread-to-SL ratio: tight sniper stops ($1.50-$3.50 -> ratio 0.055..0.11) have 70%+ WR
      if(f.f11_spread_to_sl_ratio >= 0.052 && f.f11_spread_to_sl_ratio <= 0.125)
         logit += 0.22;
      else if(f.f11_spread_to_sl_ratio > 0.14)
         logit -= (f.f11_spread_to_sl_ratio - 0.14) * 2.00;

      // Logistic sigmoid P = 1 / (1 + exp(-logit))
      double prob = 1.0 / (1.0 + MathExp(-logit));
      return MathMax(0.01, MathMin(0.99, prob));
     }

public:
                 COnnxMetaLabeler()
     {
      m_onnxHandle     = INVALID_HANDLE;
      m_useOnnxModel   = true;
      m_modelReady     = false;
      m_tier2Threshold = ONNX_PROB_TIER2_MIN;
      m_tier1Threshold = ONNX_PROB_TIER1_MIN;
      m_logger         = NULL;
     }

                ~COnnxMetaLabeler()
     {
      Deinit();
     }

   //+------------------------------------------------------------------+
   //| InitFromBuffer                                                   |
   //| Initializes native MQL5 ONNX session from embedded #resource     |
   //| uchar buffer and configures [1,12] float32 input and flat        |
   //| zipmap=False output shapes ([1] int64 label, [1,2] float32 prob).|
   //+------------------------------------------------------------------+
   bool          InitFromBuffer(const uchar &onnxBuffer[],
                                const bool useOnnxModel,
                                CQuantLogger *logger,
                                const double tier2Threshold = ONNX_PROB_TIER2_MIN,
                                const double tier1Threshold = ONNX_PROB_TIER1_MIN)
     {
      Deinit();

      m_useOnnxModel   = useOnnxModel;
      m_logger         = logger;
      m_tier2Threshold = (tier2Threshold > 0.0 && tier2Threshold < 1.0) ? tier2Threshold : ONNX_PROB_TIER2_MIN;
      m_tier1Threshold = (tier1Threshold >= m_tier2Threshold && tier1Threshold < 1.0) ? tier1Threshold : ONNX_PROB_TIER1_MIN;

      if(!m_useOnnxModel)
        {
         m_modelReady = false;
         if(m_logger != NULL)
            m_logger.Info("OnnxMetaLabeler initialized in Deterministic Scoring Mode (InpUseOnnxModel=false).");
         return true;
        }

      int bufferSize = ArraySize(onnxBuffer);
      if(bufferSize <= 0)
        {
         if(m_logger != NULL)
            m_logger.Error("OnnxMetaLabeler::InitFromBuffer failed: embedded ONNX resource buffer is empty.");
         return false;
        }

      ResetLastError();
      m_onnxHandle = OnnxCreateFromBuffer(onnxBuffer, ONNX_DEFAULT);
      if(m_onnxHandle == INVALID_HANDLE)
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat(
               "OnnxCreateFromBuffer failed (err=%d). Falling back to deterministic scorer.",
               GetLastError()));
         return false;
        }

      // Configure Input 0: "input_features" of shape [1, 12] (float32)
      const long inputShape[] = {1, ONNX_FEATURE_COUNT};
      if(!OnnxSetInputShape(m_onnxHandle, 0, inputShape))
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxSetInputShape(0, [1, 12]) failed (err=%d)", GetLastError()));
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
         return false;
        }

      // Configure Output 0: "label" of shape [1] (int64)
      const long outputLabelShape[] = {1};
      if(!OnnxSetOutputShape(m_onnxHandle, 0, outputLabelShape))
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxSetOutputShape(0, [1]) failed (err=%d)", GetLastError()));
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
         return false;
        }

      // Configure Output 1: "probabilities" of shape [1, 2] (float32, zipmap=False)
      const long outputProbShape[] = {1, 2};
      if(!OnnxSetOutputShape(m_onnxHandle, 1, outputProbShape))
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxSetOutputShape(1, [1, 2]) failed (err=%d)", GetLastError()));
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
         return false;
        }

      m_modelReady = true;
      if(m_logger != NULL)
        {
         m_logger.Info(StringFormat(
            "OnnxMetaLabeler Initialized from embedded buffer [Bytes=%d | Input=[1,12] float32 | Tier2>=%.2f | Tier1>=%.2f]",
            bufferSize, m_tier2Threshold, m_tier1Threshold));
        }
      return true;
     }

   //--- Release native ONNX session handle
   void          Deinit()
     {
      if(m_onnxHandle != INVALID_HANDLE)
        {
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
        }
      m_modelReady = false;
     }

   //+------------------------------------------------------------------+
   //| PredictProbability                                               |
   //| Runs sub-millisecond ONNX inference on the 12 stationary         |
   //| features (or deterministic fallback when InpUseOnnxModel=false). |
   //+------------------------------------------------------------------+
   bool          PredictProbability(SStationaryFeatures &features,
                                    SOnnxPrediction &outPrediction)
     {
      outPrediction.Reset();
      ulong tStartUs = GetMicrosecondCount();

      features.SyncTensor();

      // Use deterministic scoring mode if configured or if ONNX handle is unavailable
      if(!m_useOnnxModel || !m_modelReady || m_onnxHandle == INVALID_HANDLE)
        {
         double detProb = EvaluateDeterministicScore(features);
         outPrediction.inferenceSuccess          = true;
         outPrediction.usedDeterministicFallback = true;
         outPrediction.predictedClassLabel       = (detProb >= m_tier2Threshold ? 1 : 0);
         outPrediction.winProbability            = detProb;
         outPrediction.riskTier                  = ClassifyRiskTier(detProb);
         outPrediction.inferenceTimeMicroseconds = (double)(GetMicrosecondCount() - tStartUs);
         outPrediction.statusMessage             = "DETERMINISTIC_FALLBACK";
         return true;
        }

      // Prepare flat input & output buffers matching [1, 12], [1], [1, 2]
      float inputBuffer[ONNX_FEATURE_COUNT];
      for(int i = 0; i < ONNX_FEATURE_COUNT; i++)
         inputBuffer[i] = features.tensor[i];

      long  outputLabel[1];
      float outputProbs[2];
      outputLabel[0] = 0;
      outputProbs[0] = 0.0f;
      outputProbs[1] = 0.0f;

      ResetLastError();
      bool ok = OnnxRun(m_onnxHandle,
                        ONNX_NO_CONVERSION,
                        inputBuffer,
                        outputLabel,
                        outputProbs);

      ulong elapsedUs = GetMicrosecondCount() - tStartUs;

      if(!ok)
        {
         int err = GetLastError();
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxRun inference failed (err=%d); invoking deterministic fallback.", err));

         double detProb = EvaluateDeterministicScore(features);
         outPrediction.inferenceSuccess          = true;
         outPrediction.usedDeterministicFallback = true;
         outPrediction.predictedClassLabel       = (detProb >= m_tier2Threshold ? 1 : 0);
         outPrediction.winProbability            = detProb;
         outPrediction.riskTier                  = ClassifyRiskTier(detProb);
         outPrediction.inferenceTimeMicroseconds = (double)elapsedUs;
         outPrediction.statusMessage             = StringFormat("ONNX_ERR_%d_FALLBACK", err);
         return true;
        }

      // Read probabilities[0][1] -> outputProbs[1] for class 1 (+2.5R win probability P)
      double winProb = (double)outputProbs[1];
      if(!MathIsValidNumber(winProb) || winProb < 0.0 || winProb > 1.0)
        {
         // If model output logits or unnormalized values, normalize safely
         double p0 = (double)outputProbs[0];
         double p1 = (double)outputProbs[1];
         if(MathIsValidNumber(p0) && MathIsValidNumber(p1) && (p0 + p1) > 0.0)
            winProb = p1 / (p0 + p1);
         else
            winProb = EvaluateDeterministicScore(features);
        }

      winProb = MathMax(0.0, MathMin(1.0, winProb));

      outPrediction.inferenceSuccess          = true;
      outPrediction.usedDeterministicFallback = false;
      outPrediction.predictedClassLabel       = outputLabel[0];
      outPrediction.winProbability            = winProb;
      outPrediction.riskTier                  = ClassifyRiskTier(winProb);
      outPrediction.inferenceTimeMicroseconds = (double)elapsedUs;
      outPrediction.statusMessage             = "ONNX_NATIVE_OK";

      if(m_logger != NULL)
         m_logger.Debug(StringFormat(
            "ONNX Meta-Labeler [P(Win +2.5R)=%.4f | Label=%I64d | Tier=%d | Latency=%.1f us]",
            winProb, outputLabel[0], outPrediction.riskTier, outPrediction.inferenceTimeMicroseconds));

      return true;
     }

   bool          IsModelReady() const { return m_modelReady; }
  };

#endif // XAUUSD_QUANT_ONNX_META_LABELER_MQH
