# ofb_pkg: Verification Report

## 1. Test results

Run on 2026-10-04 (`ofb_pkg_tb`) and 2026-10-06 (`ofb_cc_pulse_tb`) with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7,
UVVM 2026.03.20, Open Logic 4990f33e: `python run.py "*ofb_pkg*" "*ofb_cc_pulse*"`.

| Test ID | Result |
| --- | --- |
| `test_symbols` | Pass |
| `test_control_words` | Pass |
| `test_crc_functions` | Pass |
| `test_crc_open_logic` | Pass |
| `test_prbs_reference` | Pass |
| `test_prbs_open_logic` | Pass |
| `test_single_pulses` (in_fast, out_fast, near) | Pass |
| `test_min_spacing` (in_fast, out_fast, near) | Pass |
| `test_pending` (in_fast, out_fast, near) | Pass |
| `test_reset` (in_fast, out_fast, near) | Pass |

Full regression of the repository: 205 of 205 tests pass; `lint/synth_check.py` finds no latch in `ofb_core` (1, 2
and 4 lanes).

## 2. Summary

All 10 test cases pass (the four pulse crossing tests in three clock configurations); every requirement PKG-01 to
PKG-11 is verified. VSG reports no errors and no warnings on the package and the testbench files.

Findings during verification:

- `olo_base_prbs` is a Fibonacci LFSR. It reproduces the ECSS sequence only with the reciprocal polynomial and the
  transformed state 0xFFE8 (see the architecture document, section 4); with the ECSS polynomial and seed 0xFFFF it
  produces a different sequence.
- The first build of the VCK190 design showed 30 latches (TIMING-20, gated clocks PDRC-153) in `olo_ft_cc_pulse`,
  which `ofb_cc_pulse` used: the set/reset latch of each copy is mapped to a transparent latch whose gate and data
  both follow the input pulse, so the end of the pulse races the closing of the latch and a pulse can be lost; the
  path through the latch is not timed. `ofb_cc_pulse` is now a handshake without latch (architecture section 6).
  Mutation check: without the pending flag `test_pending` fails in all three configurations, the other tests pass
  (the minimum spacing holds without pending pulses).
