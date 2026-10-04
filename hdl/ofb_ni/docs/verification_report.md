# ofb_ni: Verification Report

## 1. Test results

Run on 2026-10-04 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_ni*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_ni_vc_tb` | 3 | 3 |

## 2. Summary

All test cases pass. VSG reports no errors and no warnings. NI-IF-02 and NI-RX-01 are verified with the core
testbench.

Defects found during verification: none in the RTL. Testbench: a clock period of 5 ns produces time stamps with two
decimals, which UVVM reports as a warning; the period is 6 ns.
