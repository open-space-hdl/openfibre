# ofb_pa_gty: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (transceiver wizard gtwiz_versal 1.0, xsim): `python tools/run_xsim.py`.

| Testbench | Test | Result | Simulated time | Wall time |
| --- | --- | --- | --- | --- |
| `ofb_pa_gty_tb` | TC-PA-01 | PASS_TC01 |
| `ofb_pa_gty_core_tb` | TC-PA-02 | PASS_TC02 |

TC-PA-01: transmitter ready after TX_READY_TC01, receiver ready after RX_READY_TC01; WORDS_TC01 data words per lane
checked without error, all lanes aligned, NoSignal low.

TC-PA-02: transceivers ready after READY_TC02, link initialised after LINK_TC02 (four lanes data-sending and
data-receiving, Both-Ends Ready at both ends); CLKCOR_TC02; all 24 packets per VC and direction and 4 broadcast
messages per direction delivered in order, DL_ERRORS zero, no retry at either end.

## 2. Summary

All test cases pass. VSG reports no errors and no warnings (the port names of the transceiver wizard and of
`BUFG_GT` are excluded from the naming rules with `vsg_off` comments).

Findings during verification:

| Finding | Fix |
| --- | --- |
| No clock correction: the receive buffers overflowed and underflowed (data words lost or repeated, TC-PA-03). The combined fields `RX_CC_K` and `RX_CC_VAL` of the wizard are not derived from the per-character keys when the settings are set by Tcl, so the sequence expected D28.7 instead of K28.7 | `tcl/ofb_gtw.tcl` sets the combined fields |
| Optional ports of the wizard set through `INTF0_TXRX_OPTIONAL_PORTS` are ignored | `INTF0_OPTIONAL_PORTS` takes the dictionary of all ports (`tcl/ofb_gtw.tcl`) |
| With an inherited stdin, `export_simulation` writes the file list `vlog.prj` to stdout | The runner starts Vivado with stdin closed |
| xsim does not order the files of a module | The runner orders the files by the units they define and use |
