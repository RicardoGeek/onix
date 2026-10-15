# XAUUSD Hybrid Quantitative Sniper EA (`XAUUSD_Sniper_ONNX`)

A 3-layer institutional MetaTrader 5 Expert Advisor (`MQL5` + native `ONNX` machine learning) engineered for **XAUUSD (Gold)** on the **M5** timeframe. The system combines Liquidity Sweep + Volume Profile microstructure detection with an embedded 12-feature ONNX Meta-Labeler and a strict prop-firm equity/lot-sizing engine.

---

## 1. Repository Structure

```text
onix/
├── README.md
├── AGENTS.md
└── xauusd-quant-ea/
    ├── MQL5/
    │   ├── Experts/
    │   │   ├── XAUUSD_Sniper_ONNX.mq5          # Main EA source (#resource embeds xauusd_meta_model.onnx)
    │   │   └── XAUUSD_Sniper_ONNX.ex5          # Ready-to-run compiled MT5 binary (versioned)
    │   ├── Files/
    │   │   └── models/
    │   │       └── xauusd_meta_model.onnx      # Production 12-feature float32 ONNX model (versioned)
    │   └── Include/
    │       └── XAUUSD_Quant/
    │           ├── Core/
    │           │   ├── Definitions.mqh         # Enums, structs, constants, tick-step price normalization
    │           │   └── Logger.mqh              # Trade journal & 12-feature setup telemetry CSV logger
    │           ├── Layer1_Signal/
    │           │   ├── SessionLevels.mqh       # Asian Range (00-07 UTC), PDH/PDL, M15 fractals & EQH/EQL
    │           │   ├── VolumeProfile.mqh       # Intraday M1 Volume Profile ($0.25 bins, VPOC, VAH, VAL, LVNs)
    │           │   └── SweepSignalEngine.mqh   # 4-State FSM: Sweep -> Reclaim/MSS -> FVG Sniper Entry
    │           ├── Layer2_AI/
    │           │   ├── FeatureExtractor.mqh    # 12 stationary (ATR/SL-normalized) microstructure features
    │           │   └── OnnxMetaLabeler.mqh     # Native MT5 ONNX runtime ([1,12] -> [1], [1,2], zipmap=False)
    │           └── Layer3_Risk/
    │               ├── EquityGuard.mqh         # OnTick DD circuit breakers (2.25%/2.40% daily, 5.20%/5.40% total)
    │               ├── PositionSizer.mqh       # OrderCalcProfit() + Anti-10x Prop Guard + House-Money sizer
    │               └── ExecutionManager.mqh    # Single-position manager, TP1 @ +0.62R (35%), 5-stage runner ratchet
    └── python_pipeline/
        ├── config.py                           # Feature names, ONNX contract, and walk-forward configuration
        ├── data_loader.py                      # MT5 bar & setup telemetry CSV loader
        ├── feature_engineering.py              # Python parity implementation of the 12 stationary features
        ├── triple_barrier_labeling.py          # Triple-barrier and MT5 telemetry outcome labeling
        ├── train_walk_forward.py               # Purged Walk-Forward splitter & NativeResidualMetaClassifier
        ├── export_onnx.py                      # Pure ONNX graph builder (Gemm/Tanh/Add/Sigmoid, zipmap=False)
        ├── retrain_multiyear_onnx.py           # One-command multi-year (2024-2026+) ONNX retraining pipeline
        └── bootstrap_dummy_onnx.py             # ONNX contract verification utility
```

> **Note**: Non-code artifacts (Strategy Tester HTML reports, `.ini` files, historical telemetry CSVs, and compilation logs) are stored outside the repository in `C:\Users\faker\Documents\onix_artifacts\`.

---

## 2. Verified Strategy Tester Performance (`M5`, `Model=1` 1-Minute OHLC)

| Period | Account / Mode | Net Profit | Profit Factor | Deal Win Rate | Position Win Rate | Sharpe Ratio | Max Balance DD | Max Equity DD |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`2024.01.01 – 2025.01.01`** | `$10,000` (`MODE_PROP_GUARD`) | **`+$5,762.12` (`+57.62%`)** | **`4.32`** | `85.34%` | `85.5%` (`53/62`) | `46.07` | `2.74%` | `4.90%` |
| **`2024.01.01 – 2025.01.01`** | `$50,000` (`MODE_PROP_GUARD`) | **`+$29,040.43` (`+58.08%`)** | **`4.33`** | `85.34%` | `87.1%` (`54/62`) | `46.23` | `2.75%` | `4.92%` |
| **`2025.01.01 – 2026.10.01`** | `$50,000` (`MODE_PROP_GUARD`) | **`+$138,107.31` (`+276.21%`)** | **`4.52`** | `80.52%` | `89.4%` (`126/141`) | `56.10` | `1.98%` | `4.15%` |

---

## 3. Quick Installation (Ready-to-Use Binary)

1. Copy `xauusd-quant-ea/MQL5/Experts/XAUUSD_Sniper_ONNX.ex5` into your MetaTrader 5 Data Folder under `MQL5\Experts\`.
2. Attach `XAUUSD_Sniper_ONNX` to an **XAUUSD M5** chart or select it in the MT5 Strategy Tester.
3. Recommended Inputs (`MODE_PROP_GUARD`):
   - `InpRiskMode` = `0` (`MODE_PROP_GUARD`) or `1` (`MODE_ASYMMETRIC_GROWTH` for `$500` micro accounts)
   - `InpPropTier2RiskPct` = `1.05`
   - `InpPropTier1RiskPct` = `1.88`
   - `InpUseOnnxModel` = `true`
   - `InpOnnxTier2Threshold` = `0.58`
   - `InpOnnxTier1Threshold` = `0.72`
   - `InpBrokerGMTOffsetHours` = `2` *(used only as a fallback inside MT5 Strategy Tester; on Live/Demo/VPS, the EA **automatically detects** the broker's UTC offset on every tick via `TimeTradeServer()`/`TimeCurrent()` vs `TimeGMT()`, whether on Pepperstone `GMT+2`/`GMT+3` or Upcomers `UTC+1`)*

---

## 4. Standard Operating Procedure (SOP): How to Retrain the ONNX Model

All 12 features in `FeatureExtractor.mqh` are normalized by `ATR` or `SL` distance (price-invariant). However, you should retrain the ONNX model **once every 1 to 3 months** so the meta-labeler adapts to changes in spread-to-ATR ratios and session liquidity behavior.

### Step 1: Collect Latest Candidate Telemetry in MT5 Strategy Tester
1. Open **MetaTrader 5 Strategy Tester**.
2. Select `XAUUSD_Sniper_ONNX.ex5`, symbol `XAUUSD`, period `M5`, and modeling `1 minute OHLC`.
3. Set the date range (for example, `2024.01.01` to the current date).
4. Set the following inputs:
   - `InpUseOnnxModel` = `false` *(executes all Layer 1 candidate setups to record ground-truth outcomes)*
   - `InpEnableCsvTelemetry` = `true`
   - `InpCsvUseCommonFolder` = `true`
5. Click **Start** and wait for completion.
   - *Output*: MT5 writes `SIGNAL_TRIGGERED` and `POSITION_CLOSED` rows to `%APPDATA%\MetaQuotes\Terminal\Common\Files\xauusd_setup_telemetry.csv`.

### Step 2: Train and Export the New ONNX Model
1. Open **PowerShell** in `c:\Users\faker\Documents\dev\onix\xauusd-quant-ea`.
2. Run the multi-year ONNX retraining script:
   ```powershell
   C:\Users\faker\mlv\Scripts\python.exe python_pipeline\retrain_multiyear_onnx.py
   ```
   - *Output*: Validates the model with `onnx.checker` and `onnxruntime` and writes the updated binary to `xauusd-quant-ea/MQL5/Files/models/xauusd_meta_model.onnx`.

### Step 3: Recompile `XAUUSD_Sniper_ONNX.mq5` to Embed the Updated ONNX Model
Because `XAUUSD_Sniper_ONNX.mq5` embeds `xauusd_meta_model.onnx` into `.ex5` via `#resource`, recompile the EA after every ONNX export:
```powershell
$mt5Mql5 = "C:\Users\faker\AppData\Roaming\MetaQuotes\Terminal\73B7A2420D6397DFF9014A20F1201F97\MQL5"
Copy-Item "xauusd-quant-ea\MQL5\Files\models\xauusd_meta_model.onnx" "$mt5Mql5\Files\models\xauusd_meta_model.onnx" -Force
Copy-Item "xauusd-quant-ea\MQL5\Experts\XAUUSD_Sniper_ONNX.mq5" "$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.mq5" -Force
Copy-Item "xauusd-quant-ea\MQL5\Include\XAUUSD_Quant" "$mt5Mql5\Include\" -Recurse -Force

Start-Process -FilePath "C:\Program Files\Pepperstone MetaTrader 5\MetaEditor64.exe" `
  -ArgumentList "/compile:`"$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.mq5`" /log:`"C:\Users\faker\Documents\onix_artifacts\logs\compile.log`"" -Wait

Copy-Item "$mt5Mql5\Experts\XAUUSD_Sniper_ONNX.ex5" "xauusd-quant-ea\MQL5\Experts\XAUUSD_Sniper_ONNX.ex5" -Force
```
4. Re-enable `InpUseOnnxModel` = `true` for live trading or Strategy Tester verification.
