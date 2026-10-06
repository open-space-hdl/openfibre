# ofb_pa_gty: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (transceiver wizard gtwiz_versal 1.0, xsim): `python tools/run_xsim.py`.

| Testbench | Test | Result | Simulated time |
| --- | --- | --- | --- |
| `ofb_pa_gty_tb` | TC-PA-01, TC-PA-04 | Pass | 94 us |
| `ofb_pa_gty_cc_tb`, run `cc` | TC-PA-03 | Pass | 94 us |
| `ofb_pa_gty_cc_tb`, run `far` | TC-PA-05 | Pass | 144 us |
| `ofb_pa_gty_core_tb` | TC-PA-02 | Pass | 199 us |

TC-PA-01: transmitters ready after 64.9 us, receivers ready after 68.2 us; 342 data words per lane checked without
error, all lanes aligned, NoSignal low.

TC-PA-04: with the external loopback removed and the near-end serial loopback enabled, 409 data words per lane
received in order without error.

TC-PA-05: same reference clock frequency at both ends; about 3210 data words per lane and end before, then with the
far-end serial loopback at B 3006 data words per lane of A received in order without error.

TC-PA-03 (1000 ppm): 8 clock corrections at A (SKIP words inserted), 4 at B (SKIP words removed), no receive buffer
error; about 3480 data words per lane and end received in order, no word lost or repeated.

TC-PA-02 (200 ppm): transceivers ready after 64.9 us, link initialised after 94.2 us (four lanes data-sending and
data-receiving, Both-Ends Ready at both ends, ML_STATUS 0x2FF); first burst delivered after 98.3 us; 4 clock
corrections at A and 1 at B by 194.3 us; all 24 packets per VC and direction and 4 broadcast messages per direction
delivered in order, DL_ERRORS zero and no retry at either end.

A simulation of the transceiver model takes about 10 minutes of elaboration and 2 to 25 minutes of simulation.

Rerun on the merged tree (serial loopbacks, bit synchronisation, fault injection campaign, DED containment) with
the CPU otherwise idle: all runs pass, `ofb_pa_gty_core_tb` with the changed Multi-Lane and Data Link layers as
well.

Rerun after the findings of the first VCK190 build (lane reset and far-end loopback enables from registers,
register stages of the input VC buffers, latch-free pulse crossing): `ofb_pa_gty_tb` and both runs of
`ofb_pa_gty_cc_tb` pass with the results above. `ofb_pa_gty_core_tb` first failed: the transceiver model of end B
reported a PLL divider error at time 0 under CPU load (the link never came up)
and the input VC buffers of end A delivered one beat of undefined words before their reset (see the Data Link
report); the rerun with the fix passes with the results above (link initialised after 94.2 us, all packets and
broadcast messages delivered, no error, no retry).

## 2. Summary

All test cases pass. VSG reports no errors and no warnings (the port names of the transceiver wizard and of
`BUFG_GT` are excluded from the naming rules with `vsg_off` comments).

Findings during verification:

| Finding | Fix |
| --- | --- |
| No clock correction: the receive buffers overflowed and underflowed (data words lost or repeated, TC-PA-03). The combined fields `RX_CC_K` and `RX_CC_VAL` of the wizard are not derived from the per-character keys when the settings are set by Tcl | `tcl/ofb_gtw.tcl` sets the combined fields in the format of the Gigabit Ethernet preset of the wizard (K flags in `RX_CC_K`, values in `RX_CC_VAL`) and `RX_PPM_OFFSET` 200 |
| The receive buffers output zero words for a few hundred cycles after the receivers are ready (TC-PA-03) | `PhyRx_Valid` from the first K character of the lane after the receivers are ready |
| Far-end serial loopback at B with the reference clock of B 1000 ppm slower: 1 or 2 errors per lane in 3000 words at A (the loopback retimes the bits with the transmit clock of B) | Property of the transceiver loopback, documented in the specification (section 5); TC-PA-05 runs with equal reference clock frequencies |
| `export_simulation` occasionally prints the file list to stdout instead of writing `vlog.prj`, also with stdin closed | The runner recovers `vlog.prj` from the log |
| Optional ports of the wizard set through `INTF0_TXRX_OPTIONAL_PORTS` are ignored | `INTF0_OPTIONAL_PORTS` takes the dictionary of all ports (`tcl/ofb_gtw.tcl`) |
| With an inherited stdin, `export_simulation` writes the file list `vlog.prj` to stdout | The runner starts Vivado with stdin closed |
| xsim does not order the files of a module | The runner orders the files by the units they define and use |
| TC-PA-03 after the generic `RefPpmB_g` was introduced: no clock correction (the offset of B was computed wrongly) | Offset in whole picoseconds: `RefPpmB_g * 3200 ps / 1000000` |
| The transceiver model is not deterministic under heavy CPU load: next to six GHDL simulations `ofb_pa_gty_tb` reached TX ready 14 ns early, two lanes never aligned and two slipped; idle CPU: nominal times and pass. One `ofb_vck190_tb` run and one `ofb_pa_gty_core_tb` run hung with a PLL divider error of the model of one end at time 0 (`div_val has to be >= 9`); reruns pass | Simulations with the transceiver model run without other simulations (`docs/conventions.md`); a run with the PLL divider error is repeated |
