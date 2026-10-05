# ofb_pa_gty: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (transceiver wizard gtwiz_versal 1.0, xsim): `python tools/run_xsim.py`.

| Testbench | Test | Result | Simulated time |
| --- | --- | --- | --- |
| `ofb_pa_gty_tb` | TC-PA-01 | Pass | 71 us |
| `ofb_pa_gty_cc_tb` | TC-PA-03 | Pass | 94 us |
| `ofb_pa_gty_core_tb` | TC-PA-02 | Pass | 199 us |

TC-PA-01: transmitters ready after 64.9 us, receivers ready after 68.2 us; 342 data words per lane checked without
error, all lanes aligned, NoSignal low.

TC-PA-03 (1000 ppm): 8 clock corrections at A (SKIP words inserted), 4 at B (SKIP words removed), no receive buffer
error; about 3480 data words per lane and end received in order, no word lost or repeated.

TC-PA-02 (200 ppm): transceivers ready after 64.9 us, link initialised after 94.2 us (four lanes data-sending and
data-receiving, Both-Ends Ready at both ends, ML_STATUS 0x2FF); first burst delivered after 98.3 us; 4 clock
corrections at A and 1 at B by 194.3 us; all 24 packets per VC and direction and 4 broadcast messages per direction
delivered in order, DL_ERRORS zero and no retry at either end.

A simulation of the transceiver model takes about 10 minutes of elaboration and 2 to 25 minutes of simulation.

## 2. Summary

All test cases pass. VSG reports no errors and no warnings (the port names of the transceiver wizard and of
`BUFG_GT` are excluded from the naming rules with `vsg_off` comments).

Findings during verification:

| Finding | Fix |
| --- | --- |
| No clock correction: the receive buffers overflowed and underflowed (data words lost or repeated, TC-PA-03). The combined fields `RX_CC_K` and `RX_CC_VAL` of the wizard are not derived from the per-character keys when the settings are set by Tcl | `tcl/ofb_gtw.tcl` sets the combined fields in the format of the Gigabit Ethernet preset of the wizard (K flags in `RX_CC_K`, values in `RX_CC_VAL`) and `RX_PPM_OFFSET` 200 |
| The receive buffers output zero words for a few hundred cycles after the receivers are ready (TC-PA-03) | `PhyRx_Valid` from the first K character of the lane after the receivers are ready |
| Optional ports of the wizard set through `INTF0_TXRX_OPTIONAL_PORTS` are ignored | `INTF0_OPTIONAL_PORTS` takes the dictionary of all ports (`tcl/ofb_gtw.tcl`) |
| With an inherited stdin, `export_simulation` writes the file list `vlog.prj` to stdout | The runner starts Vivado with stdin closed |
| xsim does not order the files of a module | The runner orders the files by the units they define and use |
