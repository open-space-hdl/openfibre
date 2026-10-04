# ofb_pkg: Verification Plan

## 1. Overview

The package is verified against the values and the worked examples of ECSS-E-ST-50-11C. Expected values are
derived independently in the testbench (character values from the Dx.y / Kx.y notation, examples copied from the
figures of the standard), never from the package itself.

## 2. Test configuration

- Testbench `ofb_pkg_tb` (VUnit runner, UVVM checks), harness `ofb_pkg_th`.
- The harness instantiates `olo_base_crc` (CRC-16 and CRC-8) and `olo_base_prbs` with the package settings and
  connects them to UVVM AXI-Stream VVCs (`ofb_tb_axis_master`, `ofb_tb_axis_slave`).
- Simulator: GHDL (default), any VHDL-2008 simulator.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_symbols` (TC-PKG-01) | Every K-code and control word symbol equals y * 32 + x of its ECSS notation. | PKG-01 |
| `test_control_words` (TC-PKG-02) | Every fixed control word and every word function places the ECSS symbols in characters 0 to 3; SIF, FCT, ACK, NACK and FULL carry the CRC-8 of their first three characters. | PKG-02, PKG-03, PKG-04, PKG-05 |
| `test_crc_functions` (TC-PKG-03) | `crc16Update` reproduces the three frames of Figure 5-44 (0x978A, 0x353D, 0xB7A1) and the zero syndrome; `crc8Update` reproduces Figure 5-46 (broadcast frame 0x29, FCT 0x4F) and the zero syndrome; `wordFct` gives 0x4F for the FCT of Figure 5-46. | PKG-06, PKG-07, PKG-04 |
| `test_crc_open_logic` (TC-PKG-04) | `olo_base_crc` with the package settings computes the same five CRCs from the frames sent as AXI-Stream (partial last word through `In_Be`). | PKG-08 |
| `test_prbs_reference` (TC-PKG-05) | `prbsWord` / `prbsNextState` reproduce the first three PRBS words of Figure 5-43 and the scrambled data words of Figure 5-42. | PKG-09 |
| `test_prbs_open_logic` (TC-PKG-06) | `olo_base_prbs` with the package settings produces the first 1000 words of the reference sequence, including Figure 5-43. | PKG-10 |

## 4. Coverage analysis

Every requirement is covered by at least one test case. The package contains no state, so no negative tests apply;
a wrong constant or function makes the corresponding check fail.

## 5. Functional coverage plan

Not applicable (no randomised stimulus).
