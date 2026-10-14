# ofb_pa_gty: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (transceiver wizard gtwiz_versal 1.0, xsim): `python tools/run_xsim.py`.

| Testbench | Test | Result | Simulated time |
| --- | --- | --- | --- |
| `ofb_pa_gty_tb` | TC-PA-01, TC-PA-04, TC-PA-06 | Pass | 132 us |
| `ofb_pa_gty_cc_tb`, run `cc` | TC-PA-03 | Pass | 94 us |
| `ofb_pa_gty_cc_tb`, run `far` | TC-PA-05 | Pass | 144 us |
| `ofb_pa_gty_core_tb` | TC-PA-02 | Pass | 199 us |

TC-PA-01: transmitters ready after 64.9 us, receivers ready after 68.2 us; 342 data words per lane checked without
error, all lanes aligned, NoSignal low.

TC-PA-04: with the external loopback removed and the near-end serial loopback enabled, 409 data words per lane
received in order without error.

TC-PA-06: PRBS-31 sent and checked on every channel with the external loopback; the checkers locked 14.3 us after the
patterns were selected, no error in 5 us; the line of each lane inverted for 1 ns gave 2 or 3 words with errors on that
lane only, the checker stayed locked, no error afterwards; the PRBS-7 checker of lane 0 on the PRBS-31 pattern counted
769 words with errors in 5 us (nearly every word).

TC-PA-05: same reference clock frequency at both ends; about 3210 data words per lane and end before, then with the
far-end serial loopback at B 3006 data words per lane of A received in order without error.

TC-PA-03 (1000 ppm): 8 clock corrections at A (SKIP words inserted), 4 at B (SKIP words removed), no receive buffer
error; about 3480 data words per lane and end received in order, no word lost or repeated.

TC-PA-02 (200 ppm): transceivers ready after 64.9 us, link initialised after 94.2 us (four lanes data-sending and
data-receiving, Both-Ends Ready at both ends, ML_STATUS 0x2FF); first burst delivered after 98.3 us; 4 clock
corrections at A and 1 at B by 194.3 us; all 24 packets per VC and direction and 4 broadcast messages per direction
delivered in order, DL_ERRORS zero and no retry at either end.

A simulation of the transceiver model takes about 10 minutes of elaboration and 2 to 25 minutes of simulation.
A line `model error <run> (attempt 1 of 3: transceiver model power-up error DIV_VAL_CHK, ...), elaborating again` in
the output of `tools/run_xsim.py` is expected now and then: it is the power-up error of the simulation model
(section 2), and the runner repeats the run with a new elaboration. A run fails only when the last of three attempts
fails.

Rerun on the merged tree (serial loopbacks, bit synchronisation, fault injection campaign, DED containment) with
the CPU otherwise idle: all runs pass, `ofb_pa_gty_core_tb` with the changed Multi-Lane and Data Link layers as
well.

Rerun with the fault-tolerant status crossings, reset synchronisers and transceiver status synchronisers (Open
Logic backlog on the 4.7.0 development state): all runs pass; `ofb_pa_gty_core_tb` needed a second run (power-up
error of the model in the first one, section 2).

Rerun with the PRBS test ports (TC-PA-06 added): all runs pass with the results above, `ofb_pa_gty_core_tb` at the
first attempt.

Rerun after the timing changes of the second build (end flags in the input VC buffers, input stage of the column
encoder): `ofb_pa_gty_cc_tb` (both runs), `ofb_pa_gty_core_tb` (link initialised after 94.2 us, first burst after
98.3 us, all packets delivered, no error, no retry) and `ofb_vck190_tb` pass. `ofb_pa_gty_tb`, the first run after the
runner had generated the wizard instance again, reached TX ready 14 ns early and two lanes never aligned (the
non-deterministic behaviour of the transceiver model, section 2); its rerun passes with the results above.
Rerun of `ofb_pa_gty_core_tb` with the output register of the receive frame buffer: link initialised after 94.2 us,
all packets and broadcast messages delivered, no error, no retry (pass).

Rerun after the findings of the first VCK190 build (lane reset and far-end loopback enables from registers,
register stages of the input VC buffers, latch-free pulse crossing): `ofb_pa_gty_tb` and both runs of
`ofb_pa_gty_cc_tb` pass with the results above. `ofb_pa_gty_core_tb` first failed: the transceiver model of end B
reported the power-up error of the model (section 2; the link never came up)
and the input VC buffers of end A delivered one beat of undefined words before their reset (see the Data Link
report); the rerun with the fix passes with the results above (link initialised after 94.2 us, all packets and
broadcast messages delivered, no error, no retry).

Rerun on 2026-10-12 with Open Logic 4.7.0-ft.2 (status crossings, reset generators and transceiver status
synchronisers as base entities with `SyncTmr_g` = true): `ofb_pa_gty_tb`, `ofb_pa_gty_cc_tb.cc` and `ofb_vck190_tb`
pass at the first attempt. `ofb_pa_gty_cc_tb.far` and `ofb_pa_gty_core_tb` first failed with the power-up error
of the transceiver model of end B (section 2; the receivers never became ready); after a new elaboration both pass
with the results above (far end: receivers ready after 68.2 us, every lane checked without error;
`ofb_pa_gty_core_tb`: all packets and broadcast messages delivered, no error, no retry, simulation done at
198.6 us).

Rerun on 2026-10-13 with the packet ports of the VCs (the generator sends packets of whole words in beats with
`TKEEP` and `TLAST`, the checker compares the words of every beat with `TKEEP` and the end of each packet with
`TLAST` and no EEP): `ofb_pa_gty_core_tb` passes at the first attempt (first burst delivered after 98.3 us, broadcast
messages without error, simulation done at 198.6 us), and again on 2026-10-14 after the change of the continuous mode
of the output VC buffers (same results). `ofb_pa_gty_tb` and `ofb_pa_gty_cc_tb` do not contain the core and were not
run again.

Rerun on 2026-10-14 with the detection of the model power-up error in `tools/run_xsim.py` (section 2), next to other
simulations on the host: all five runs pass at the first attempt with the results above (`ofb_pa_gty_cc_tb.far`:
receivers ready after 68.2 us, every lane checked without error; `ofb_pa_gty_core_tb`: simulation done at 198.6 us).

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
| TC-PA-06: the forced error of the PRBS generator (`TXPRBSFORCEERR`, held for 1 to 64 cycles, near-end and external loopback) gave no error at the checker, although the port reaches the channel of the quad; the checker detects other errors | The transceiver model does not insert the forced error: TC-PA-06 inverts the line for 1 ns instead; the forced error is tested in the core testbench (TC-CORE-18, register to adapter port) and on the hardware (TC-VCK-HW-08) |
| The transceiver model gives different results for the same sources: one `ofb_pa_gty_tb` run reached TX ready 14 ns early and two lanes never aligned; runs of `ofb_pa_gty_cc_tb.far`, `ofb_pa_gty_core_tb` and `ofb_vck190_tb` failed with a power-up error of the model of one quad (`DIV_VAL_CHK`: `div_val has to be >= 9 and <= 163 : 0`, about 38 us after the start, when the model programs the LCPLL; that quad never becomes ready). Analysis with `ofb_pa_gty_cc_tb.far` on 2026-10-14: the elaborator builds a different snapshot from the same sources every time (the snapshot files differ, with and without multithreaded elaboration); 7 fresh elaborations gave 6 passing and 1 failing snapshot. The failing snapshot fails in every further run with the same error at the same picosecond, with other simulations on the host or without, and also when the reset release of end B or of both ends is delayed by 3.2 us (20 x 160 ns, the least common multiple of the 6.4 ns reference clock and the 10 ns free-running clock periods), when the reference clock of B is shifted by 1.1 ns or its free-running clock by 3.7 ns: the error does not depend on the testbench timing. All 1947 parameters and ports of the quad level of the wizard are equal in failing and passing snapshots and at both ends; the outputs of the model of the failing quad differ from 1 to 2 us on (power-up of the encrypted model). The firmware files of the model have the same names in every run | Cause in the simulation model, not in the design or the testbench; the device image is not affected. `tools/run_xsim.py` detects the error in the log and elaborates the test run again (at most three attempts, every repetition reported) |
| The runner reused an exported wizard instance generated before the PRBS ports were added to `tcl/ofb_gtw.tcl` (elaboration error: formal port `INTF0_TX1_ch_txprbssel` does not exist) | The runner keeps a hash of `tcl/ofb_gtw.tcl` and generates, exports and compiles the wizard instance again when it changes |
