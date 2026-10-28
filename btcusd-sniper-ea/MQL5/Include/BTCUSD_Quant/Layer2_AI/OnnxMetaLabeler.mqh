//+------------------------------------------------------------------+
//|                                              OnnxMetaLabeler.mqh |
//|                     BTCUSD Hybrid Quantitative Sniper EA (ONNX)  |
//|  Layer 2 AI: Native OnnxCreateFromBuffer & OnnxRun Engine        |
//+------------------------------------------------------------------+
#property copyright "Principal Quantitative Systems Engineering"
#property link      "https://www.mql5.com"
#property strict

#ifndef BTCUSD_QUANT_ONNX_META_LABELER_MQH
#define BTCUSD_QUANT_ONNX_META_LABELER_MQH

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

   int           ClassifyRiskTier(const double prob) const
     {
      if(prob >= m_tier1Threshold)
         return 1;
      if(prob >= m_tier2Threshold)
         return 2;
      return 0;
     }

   double        EvaluateDeterministicScore(const SStationaryFeatures &f) const
     {
      double logit = 0.35;

      if(f.f0_sweep_depth_norm >= 0.12 && f.f0_sweep_depth_norm <= 0.48)
         logit += 0.22;
      else if(f.f0_sweep_depth_norm > 0.72)
         logit -= 0.18;

      logit += (f.f1_wick_body_ratio - 0.38) * 0.85;

      if(f.f2_bars_outside_level <= 0.50)
         logit += 0.22;
      else
         logit -= (f.f2_bars_outside_level - 0.50) * 0.75;

      if(f.f3_rel_tick_volume >= 1.20 && f.f3_rel_tick_volume <= 2.40)
         logit += 0.14;

      if(f.f4_vpoc_distance_norm >= 0.40)
         logit += 0.12;

      if(f.f5_value_area_width_norm >= 0.35 && f.f5_value_area_width_norm <= 1.95)
         logit += 0.24;
      else if(f.f5_value_area_width_norm > 2.05)
         logit -= 0.42;

      if(f.f6_h1_adx >= 0.22 && f.f6_h1_adx <= 0.46)
         logit += 0.18;

      if(f.f7_hurst_exponent >= 0.33)
         logit += 0.20;
      else
         logit -= 0.18;

      if(f.f8_volatility_ratio <= 0.30)
         logit += 0.15;
      else
         logit -= 0.20;

      if(f.f11_spread_to_sl_ratio >= 0.015 && f.f11_spread_to_sl_ratio <= 0.140)
         logit += 0.22;
      else if(f.f11_spread_to_sl_ratio > 0.18)
         logit -= (f.f11_spread_to_sl_ratio - 0.18) * 2.00;

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

      const long inputShape[] = {1, ONNX_FEATURE_COUNT};
      if(!OnnxSetInputShape(m_onnxHandle, 0, inputShape))
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxSetInputShape(0, [1, 12]) failed (err=%d)", GetLastError()));
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
         return false;
        }

      const long outputLabelShape[] = {1};
      if(!OnnxSetOutputShape(m_onnxHandle, 0, outputLabelShape))
        {
         if(m_logger != NULL)
            m_logger.Error(StringFormat("OnnxSetOutputShape(0, [1]) failed (err=%d)", GetLastError()));
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
         return false;
        }

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

   void          Deinit()
     {
      if(m_onnxHandle != INVALID_HANDLE)
        {
         OnnxRelease(m_onnxHandle);
         m_onnxHandle = INVALID_HANDLE;
        }
      m_modelReady = false;
     }

   bool          PredictProbability(SStationaryFeatures &features,
                                    SOnnxPrediction &outPrediction)
     {
      outPrediction.Reset();
      ulong tStartUs = GetMicrosecondCount();

      features.SyncTensor();

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

      double winProb = (double)outputProbs[1];
      if(!MathIsValidNumber(winProb) || winProb < 0.0 || winProb > 1.0)
        {
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
            "ONNX Meta-Labeler [P(Win)=%.4f | Label=%I64d | Tier=%d | Latency=%.1f us]",
            winProb, outputLabel[0], outPrediction.riskTier, outPrediction.inferenceTimeMicroseconds));

      return true;
     }

   bool          IsModelReady() const { return m_modelReady; }
  };

#endif // BTCUSD_QUANT_ONNX_META_LABELER_MQH
