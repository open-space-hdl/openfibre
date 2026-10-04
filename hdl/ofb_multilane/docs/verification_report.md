# ofb_multilane: Verification Report

## 1. Test results

Run on 2026-10-04 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_ml*"`
`"*ofb_multilane*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_ml_codec_tb` (ML-3, ML-4) | 9 | 9 |
| `ofb_multilane_tb` (layer, one lane) | 5 | 5 |

Full regression of the repository: 63 of 63 tests pass.

## 2. Summary

All 14 test cases pass; every requirement of the specification (phase 2 scope) is covered (see the verification
plan). The column encoder reproduces ECSS Figures 5-42 and 5-44 bit-exactly, and the decoder restores them. VSG
reports no errors and no warnings.

Mutation checks confirmed that the testbenches detect faults: a wrong byte enable of the EDF in the CRC unit fails
TC-ML-01 and TC-ML-09; a scramble enable that is not held in Active fails TC-ML-21.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| TC-ML-24: the one-cycle link reset pulse of the sequencer did not cover a rising clock edge (testbench timing) | Sequencer aligned to the falling edge before the pulse |

Observations:

- The treatment of control words and broadcast frames inside a data frame (excluded from the CRC-16 and from
  scrambling, specification section 5) follows from the standard but is not shown in its examples; it is checked with
  STAR-Dundee equipment in the lab test of phase 2.
- Multi-lane operation (2 to 4 lanes, alignment) is verified in phase 4.
