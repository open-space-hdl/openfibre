# ofb_mib: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_mib_tb` | 7 | 7 |

Full regression of the repository: 182 of 182 tests pass. VSG reports no errors and no warnings.

## 2. Summary

All test cases pass and cover every requirement of the specification.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| ECSS table audit (5.9.4e): the Link Reset command cleared only the Data Link status; the lane event flags and the flags of bandwidth use were kept | The command clears the status of all layers, the EDAC status excepted (MG-ST-01, TC-MG-04) |
| The sticky bandwidth flags latched the undefined value of the status crossing before its first transfer (simulation) | The sticky flags accumulate the crossed status only 32 cycles after reset (first fix with `to_01` replaced: not synthesizable, found with `lint/synth_check.py`) |
| Every event was counted twice and every command gave two pulses: `olo_ft_cc_pulse` stretches its output pulses to two cycles of the output clock | `ofb_cc_pulse` (edge detector after `olo_ft_cc_pulse`), also used in the input VC buffer of the Data Link layer, where the same effect doubled the FCT requests |
