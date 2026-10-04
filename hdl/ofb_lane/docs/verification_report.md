# ofb_lane: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_lane*"`
`"*8b10b*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_lane_tb` (layer) | 14 | 14 |
| `ofb_lane_init_tb` (LN-1) | 13 | 13 |
| `ofb_lane_rx_tb` (LN-3) | 8 | 8 |
| `ofb_lane_tx_tb` (LN-2) | 4 | 4 |
| `ofb_tb_8b10b_tb` (verification component) | 4 | 4 |

## 2. Summary

All 43 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports
no errors and no warnings.

Defects found and fixed during verification:

| Finding | Fix |
| --- | --- |
| `Stat_FarCapability` was not driven by `ofb_lane` | Connected to the capability register of LN-1 |
| The consecutive LOST_SIGNAL / STANDBY counters kept their value through ClearLine, so a lane restarted into ClearLine at once when Started was reached (endless restart after a far-end LOST_SIGNAL) | Counters cleared on entry to ClearLine |
| After a sync reset the receiver could still use the last word received before | Sync reset discards the stored input word |

Observations:

- The 1023-word rule counts all words since the last RXERR; an INIT1 or INIT2 after more than 1022 error-free words
  moves to Connecting at once. This follows the wording of ECSS 5.5.2.7f.3.
- Behaviour on the line (8B/10B, SerDes) is covered by the behavioural model; the GTY wrapper test checks the real
  transceiver.
