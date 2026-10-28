# ONIX Quantitative Trading Suite — 3-Asset Sniper + Chrysalis Power Duo (`XAUUSD`, `USDJPY`, `BTCUSD`)

An institutional MetaTrader 5 Expert Advisor suite (`MQL5` + native `ONNX` machine learning) pairing **Controlled-Risk Prop Snipers** (`<3%` Daily / `<6%` Total Drawdown ceiling) with **Asymmetric `$300` Seed Moonshot Compounders** (`Chrysalis`) across **Gold (`XAUUSD`)**, **The Ninja (`USDJPY`)**, and **Bitcoin (`BTCUSD`)**.

---

## 1. Quick Deployment Cheat Sheet (Complete 6-EA Fleet)

Every EA uses an isolated **Magic Number** namespace (`20260401`, `20260501`, `20260777`, `20260888`, `20260901`, `20260990`), so they never collide even if multiple EAs run inside the same MT5 terminal.

| Asset | EA Binary (`MQL5\Experts\`) | Archived Release (`bin/`) | Chart Timeframe | Role & Target Account | Default Magic Number | Changelog |
| :--- | :--- | :--- | :---: | :--- | :---: | :--- |
| **Gold (`XAUUSD`)** | `XAUUSD_Sniper_ONNX.ex5` | `bin/XAUUSD_Sniper_ONNX/XAUUSD_Sniper_ONNX_v4.25.ex5` (`v4.25`) | **`M5`** | Prop / Funded Guard (`<3%` Daily, `<6%` Total DD) | `20260401` | [`xauusd-quant-ea/CHANGELOG.md`](xauusd-quant-ea/CHANGELOG.md) |
| **Gold (`XAUUSD`)** | `chrysalis_ea.ex5` | `bin/xauusd_chrysalis_ea/xauusd_chrysalis_ea_v2.40.ex5` (`v2.40`) | **`H1`** (or `M15`) | `$300` Seed Moonshot Compounder | `20260777` | [`chrysalis-moonshot-ea/CHANGELOG.md`](chrysalis-moonshot-ea/CHANGELOG.md) |
| **Ninja (`USDJPY`)** | `USDJPY_Sniper_ONNX.ex5` | `bin/USDJPY_Sniper_ONNX/USDJPY_Sniper_ONNX_v2.10.ex5` (`v2.10`) | **`M5`** | Prop / Funded Guard (`<3%` Daily, `<6%` Total DD) | `20260501` | [`usdjpy-sniper-ea/CHANGELOG.md`](usdjpy-sniper-ea/CHANGELOG.md) |
| **Ninja (`USDJPY`)** | `usdjpy_chrysalis_ea.ex5` | `bin/usdjpy_chrysalis_ea/usdjpy_chrysalis_ea_v3.10.ex5` (`v3.10`) | **`H1`** | `$300` Seed Marsshot Compounder | `20260888` | [`usdjpy-moonshot-ea/CHANGELOG.md`](usdjpy-moonshot-ea/CHANGELOG.md) |
| **Bitcoin (`BTCUSD`)** | `BTCUSD_Sniper_ONNX.ex5` | `bin/BTCUSD_Sniper_ONNX/BTCUSD_Sniper_ONNX_v1.10.ex5` (`v1.10`) | **`M5`** | Prop / Capital Guard "Bart-Hunter" (`<6%` Total DD) | `20260901` | [`btcusd-sniper-ea/CHANGELOG.md`](btcusd-sniper-ea/CHANGELOG.md) |
| **Bitcoin (`BTCUSD`)** | `btcusd_chrysalis_ea.ex5` | `bin/btcusd_chrysalis_ea/btcusd_chrysalis_ea_v2.00.ex5` (`v2.00`) | **`H1`** | `$300` Seed 24/7 Satoshi Supernova | `20260990` | [`btcusd-moonshot-ea/CHANGELOG.md`](btcusd-moonshot-ea/CHANGELOG.md) |

---

## 2. Repository Structure

```text
onix/
├── README.md
├── AGENTS.md
├── bin/                                        # Versioned binary archive for all EA releases
│   ├── XAUUSD_Sniper_ONNX/
│   ├── USDJPY_Sniper_ONNX/
│   ├── BTCUSD_Sniper_ONNX/
│   ├── xauusd_chrysalis_ea/
│   ├── usdjpy_chrysalis_ea/
│   ├── btcusd_chrysalis_ea/
│   └── aegis_regime_hunter_ea/
├── xauusd-quant-ea/                            # Gold Prop Sniper (XAUUSD_Sniper_ONNX v4.21)
├── chrysalis-moonshot-ea/                      # Gold $300 Moonshot (chrysalis_ea v2.40)
├── usdjpy-sniper-ea/                           # USDJPY Prop Sniper (USDJPY_Sniper_ONNX v2.00)
├── usdjpy-moonshot-ea/                         # USDJPY $300 Marsshot (usdjpy_chrysalis_ea v3.10)
├── btcusd-sniper-ea/                           # BTCUSD Prop Sniper "Bart-Hunter" (BTCUSD_Sniper_ONNX v1.00)
├── btcusd-moonshot-ea/                         # BTCUSD $300 Satoshi Supernova (btcusd_chrysalis_ea v2.00)
└── aegis-regime-hunter-ea/                     # Aegis Regime Hunter EA (aegis_regime_hunter_ea v4.00)
```

### Detailed Sniper Architecture (`xauusd-quant-ea/`, `usdjpy-sniper-ea/`, `btcusd-sniper-ea/`)

```text
<asset>-sniper-ea/
    ├── CHANGELOG.md
    ├── MQL5/
    │   ├── Experts/
    │   │   ├── <ASSET>_Sniper_ONNX.mq5         # Main EA source (#resource embeds <asset>_meta_model.onnx)
    │   │   └── <ASSET>_Sniper_ONNX.ex5         # Ready-to-run compiled MT5 binary (versioned)
    │   ├── Files/
    │   │   └── models/
    │   │       └── <asset>_meta_model.onnx     # Production 12-feature float32 ONNX model (versioned)
    │   └── Include/
    │       └── <ASSET>_Quant/
    │           ├── Core/
    │           │   ├── Definitions.mqh         # Enums, structs, constants, tick-step price normalization
    │           │   └── Logger.mqh              # Trade journal & 12-feature setup telemetry CSV logger
    │           ├── Layer1_Signal/
    │           │   ├── SessionLevels.mqh       # Killzones, Asian Range, PDH/PDL, M15 fractals & EQH/EQL
    │           │   ├── VolumeProfile.mqh       # Intraday M1 Volume Profile (VPOC, VAH, VAL, LVNs)
    │           │   └── SweepSignalEngine.mqh   # 4-State FSM: Sweep -> Reclaim/MSS -> FVG Sniper Entry
    │           ├── Layer2_AI/
    │           │   ├── FeatureExtractor.mqh    # 12 stationary (ATR/SL-normalized) microstructure features
    │           │   └── OnnxMetaLabeler.mqh     # Native MT5 ONNX runtime ([1,12] -> [1], [1,2], zipmap=False)
    │           └── Layer3_Risk/
    │               ├── EquityGuard.mqh         # OnTick DD circuit breakers (2.25%/2.40% daily, 5.20%/5.40% total)
    │               ├── PositionSizer.mqh       # OrderCalcProfit() + Anti-10x Prop Guard + House-Money sizer
    │               └── ExecutionManager.mqh    # Single-position manager, TP1 @ +0.62R (35%), 5-stage runner ratchet
    └── python_pipeline/                        # ONNX training & export scripts
```

> **Note**: Non-code artifacts (Strategy Tester HTML reports, `.ini` files, historical telemetry CSVs, and compilation logs) are stored outside the repository in `C:\Users\faker\Documents\onix_artifacts\`.

---

## 3. Verified Strategy Tester Performance

### A. Prop Snipers (`$50,000` `MODE_PROP_GUARD`, `<3.0%` Daily DD / `<6.0%` Total DD Ceiling — `Model=4` 99%–100% Real Ticks + `ExecutionMode=-1` Random Delay)

| EA (`M5`) | Tick Source & Quality (`Model=4` + Random Delay) | Period | Net Profit | Profit Factor | Win Rate | Max Balance DD | Max Equity DD |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **`XAUUSD_Sniper_ONNX v4.25`** | `XAUUSD_REAL` (`99% real ticks` — `56.1M` Dukascopy ticks) | `2024` | **`+$129,977.02` (`+259.95%`)** | **`12.84`** | **`89.61%`** (`207/231`) | `2.45%` | `2.99%` |
| **`XAUUSD_Sniper_ONNX v4.25`** | `XAUUSD` Live01 (`99% real ticks` — `195.2M` Pepperstone ticks) | `2025–2026` | **`+$1,540,997.35` (`+3,081.99%`)** | **`12.18`** | **`92.79%`** (`463/499`) | `2.32%` | `3.39%` |
| **`USDJPY_Sniper_ONNX v2.10`** | `USDJPY_REAL` (`99% real ticks` — `40.8M` Dukascopy ticks) | `2024` | **`+$48,339.08` (`+96.68%`)** | **`5.95`** | **`84.89%`** (`118/139`) | `2.14%` | `2.92%` |
| **`USDJPY_Sniper_ONNX v2.10`** | `USDJPY` Live01 (`99% real ticks` — `102.5M` Pepperstone ticks) | `2025–2026` | **`+$71,066.50` (`+142.13%`)** | **`4.34`** | **`89.50%`** (`196/219`) | `2.09%` | `3.18%` |
| **`BTCUSD_Sniper_ONNX v1.10`** | `BTCUSD_REAL` (`100% real ticks` — `57.4M` Dukascopy ticks) | `2024` | **`+$38,716.03` (`+77.43%`)** | **`3.43`** | **`85.61%`** (`119/139`) | `2.62%` | `3.91%` |
| **`BTCUSD_Sniper_ONNX v1.10`** | `BTCUSD` Live01 (`100% real ticks` — `192.5M` Pepperstone ticks) | `2025–2026` | **`+$847,389.93` (`+1,694.78%`)** | **`7.73`** | **`89.93%`** (`670/745`) | `2.79%` | `3.98%` |

### B. `$300` Seed Chrysalis Moonshot Compounders (`H1`, `1:500` Leverage)

| EA (`H1`) | Modeling Regime | Period | Starting Deposit | Net Profit | Multiple | Profit Factor | Win Rate | Max Equity DD |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **`chrysalis_ea v2.40` (`XAUUSD`)** | `Model=4` (Real Ticks + Random Delay) | `2024` | `$300` | **`+$123,789.80`** | **`413.6x`** | `1.97` | `85.14%` | `35.09%` |
| **`chrysalis_ea v2.40` (`XAUUSD`)** | `Model=4` (Real Ticks + Random Delay) | `2025–2026` | `$300` | **`+$1,288,187.47`** | **`4,295.0x`** | `2.99` | `87.30%` | `26.83%` |
| **`usdjpy_chrysalis_ea v3.10` (`USDJPY`)** | `Model=4` (Real Ticks + Random Delay) | `2024` | `$300` | **`+$166,184.42`** | **`554.9x`** | `1.99` | `87.65%` | `29.21%` |
| **`usdjpy_chrysalis_ea v3.10` (`USDJPY`)** | `Model=4` (Real Ticks + Random Delay) | `2025–2026` | `$300` | **`+$154,992.20`** | **`517.6x`** | `2.07` | `88.78%` | `24.84%` |
| **`btcusd_chrysalis_ea v2.00` (`BTCUSD`)** | `Model=4` (Real Ticks, Zero Latency) | `2024` | `$300` | **`+$2,391.95`** | **`9.0x`** | `1.31` | `88.68%` | `65.08%` |
| **`btcusd_chrysalis_ea v2.00` (`BTCUSD`)** | `Model=4` (Real Ticks, Zero Latency) | `2025–2026` | `$300` | **`+$162,207.66`** | **`541.7x`** | `2.79` | `94.82%` | `42.11%` |
| **`btcusd_chrysalis_ea v2.00` (`BTCUSD`)** | `Model=4` (Real Ticks + Random Delay) | `2025–2026` | `$300` | **`+$39,652.14`** | **`133.2x`** | `2.45` | `94.28%` | `45.36%` |

---

## 4. Quick Installation (Ready-to-Use Binaries)

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

## 5. Standard Operating Procedure (SOP): How to Retrain the ONNX Models

All 12 features in `FeatureExtractor.mqh` are normalized by `ATR` or `SL` distance (price-invariant). However, you should retrain the ONNX models **once every 1 to 3 months** so the meta-labelers adapt to changes in spread-to-ATR ratios and session liquidity behavior.

### Step 1: Collect Latest Candidate Telemetry in MT5 Strategy Tester
1. Open **MetaTrader 5 Strategy Tester**.
2. Select `<ASSET>_Sniper_ONNX.ex5` (`XAUUSD_Sniper_ONNX.ex5`, `USDJPY_Sniper_ONNX.ex5`, or `BTCUSD_Sniper_ONNX.ex5`), the matching symbol, period `M5`, and modeling `1 minute OHLC`.
3. Set the date range (for example, `2024.01.01` to the current date).
4. Set the following inputs:
   - `InpUseOnnxModel` = `false` *(executes all Layer 1 candidate setups to record ground-truth outcomes)*
   - `InpEnableCsvTelemetry` = `true`
   - `InpCsvUseCommonFolder` = `true`
5. Click **Start** and wait for completion.
   - *Output*: MT5 writes `SIGNAL_TRIGGERED` and `POSITION_CLOSED` rows to `%APPDATA%\MetaQuotes\Terminal\Common\Files\<asset>_setup_telemetry.csv`.

### Step 2: Train and Export the New ONNX Model
Run the corresponding Python retraining pipeline from `c:\Users\faker\Documents\dev\onix`:
```powershell
# Gold (XAUUSD)
C:\Users\faker\mlv\Scripts\python.exe xauusd-quant-ea\python_pipeline\retrain_multiyear_onnx.py

# Ninja (USDJPY)
C:\Users\faker\mlv\Scripts\python.exe usdjpy-sniper-ea\python_pipeline\train_usdjpy_onnx.py

# Bitcoin (BTCUSD)
C:\Users\faker\mlv\Scripts\python.exe btcusd-sniper-ea\python_pipeline\train_btcusd_onnx.py
```
- *Output*: Validates the model with `onnx.checker` and `onnxruntime` and writes the updated `.onnx` binary to `<asset>-sniper-ea/MQL5/Files/models/<asset>_meta_model.onnx`.

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
