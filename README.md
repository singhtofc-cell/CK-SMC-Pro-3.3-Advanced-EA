# CK SMC Pro 3.3 Advanced EA

Smart Money Concepts multi-symbol portfolio Expert Advisor for MetaTrader 5 with adaptive risk, pyramiding, trailing structure management, volatility & news-aware filters, VaR throttling, setup CSV logging, slippage tracking, and remote JSON profile loading.

## Contents
- CK_SMC_Pro_3_3_Advanced.mq5 – Main EA.
- CK_SMC_ProfileLoader.mqh – JSON remote profile loader (global & per-symbol overrides).
- CK_SMC_KellyRisk.mqh – Fractional Kelly adaptive risk overlay (conservative).
- CK_SMC_TradeCSVLogger.mqh – CSV logging of trade setups.
- CK_SMC_VaRAlerts.mqh – VaR alert module with cooldown.
- CK_SMC_VolatilityGates.mqh – Multi-timeframe ATR volatility gates for scaling decisions.

## Key Features
| Feature | Description |
|---------|-------------|
| Multi-symbol autoscan | Scan configured symbols from one chart, open & manage trades. |
| Per-symbol ATR timeframes | Independent HTF/MTF/LTF selection based on ATR regimes. |
| SMC confluence | HTF bias, MTF structure, liquidity sweep, micro BOS, OB + FVG overlap filter. |
| Adaptive SL distance | Symbol-specific ATR-based minimum SL viability checks. |
| Partial TP + Breakeven | Optional half close at configured R, shift SL to BE. |
| Structure trailing | Pivot + ATR buffer trailing with fallback ATR trailing. |
| Pyramiding (scaling) | Laddered RR targets, spacing, volatility & news inhibition, risk cap. |
| Weighted avg entry | Maintains blended entry for proper scaling RR gating. |
| Slippage aggregation | Open/close slippage collected per position. |
| VaR throttle + alerts | R-normalized portfolio VaR + open risk ratio gating & alert. |
| Fractional Kelly overlay | Conservative dynamic risk fraction if trade history stable. |
| Remote profile JSON | Overrides global & per-symbol config via Files/yourProfile.json. |
| CSV logging | Setup metadata: OB, FVG gap, ATR set, volatility regime, expected USD profit. |
| Dynamic symbol risk share | Prevents one symbol monopolizing portfolio risk. |
| Volatility gates for scaling | Multi-timeframe ATR ratio thresholds gate scale-in attempts. |
| Trade comment enrichment | Includes symbol & expected USD profit for each new position. |

## Folder Placement
```
MQL5/Experts/CK_SMC_Pro_3_3_Advanced.mq5
MQL5/Include/*.mqh
MQL5/Files/Baseline_Stable.json (example profile)
MQL5/Files/TradeSetups.csv (auto-generated)
```

## Example JSON Profile (Baseline_Stable.json)
```json
{
  "profileName": "Baseline_Stable",
  "version": "1.3.2",
  "global": {
    "riskPercent": 0.50,
    "targetRR": 3.0,
    "partialTP_RR": 1.5,
    "enablePartialTP": true,
    "enableStructureTrailing": true,
    "newsRiskReductionPercent": 30.0,
    "maxBasePositions": 6,
    "maxTotalPositions": 10,
    "portfolioThrottleOn": true
  },
  "filters": {
    "volHighThreshold": 1.35,
    "volLowRevertThreshold": 1.25,
    "obFvgOverlapMin": 0.30
  },
  "symbols": {
    "EURUSD": {
      "riskPercent": 0.50,
      "targetRR": 2.8,
      "partialTP_RR": 1.3,
      "trailAtrMult": 0.85,
      "slBufferPoints": 12,
      "fvgMinGapPoints": 6,
      "liquidityLookback": 35
    },
    "XAUUSD": {
      "riskPercent": 0.30,
      "targetRR": 3.2,
      "partialTP_RR": 1.4,
      "trailAtrMult": 1.25,
      "slBufferPoints": 18,
      "fvgMinGapPoints": 12,
      "liquidityLookback": 28
    }
  }
}
```
