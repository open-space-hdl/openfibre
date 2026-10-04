# ofb_pkg: Verification Report

## 1. Test results

Run on 2026-10-04 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20, Open Logic 4990f33e:
`python run.py "*ofb_pkg*"`.

| Test ID | Result |
| --- | --- |
| `test_symbols` | Pass |
| `test_control_words` | Pass |
| `test_crc_functions` | Pass |
| `test_crc_open_logic` | Pass |
| `test_prbs_reference` | Pass |
| `test_prbs_open_logic` | Pass |

## 2. Summary

All 6 test cases pass; every requirement PKG-01 to PKG-10 is verified. VSG reports no errors and no warnings on the
package and the testbench files.

Findings during verification:

- `olo_base_prbs` is a Fibonacci LFSR. It reproduces the ECSS sequence only with the reciprocal polynomial and the
  transformed state 0xFFE8 (see the architecture document, section 4); with the ECSS polynomial and seed 0xFFFF it
  produces a different sequence.
