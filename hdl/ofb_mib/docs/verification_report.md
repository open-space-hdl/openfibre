# ofb_mib: Verification Report

## 1. Test results

Run on 2026-10-04 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_mib_tb` | 4 | 4 |

Full regression of the repository: 89 of 89 tests pass. VSG reports no errors and no warnings.

## 2. Summary

All test cases pass and cover every requirement of the specification.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| Every event was counted twice and every command gave two pulses: `olo_ft_cc_pulse` stretches its output pulses to two cycles of the output clock | `ofb_cc_pulse` (edge detector after `olo_ft_cc_pulse`), also used in the input VC buffer of the Data Link layer, where the same effect doubled the FCT requests |
