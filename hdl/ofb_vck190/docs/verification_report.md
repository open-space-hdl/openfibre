# ofb_vck190: Verification Report

## 1. Test results

Run on 2026-10-05 with Vivado 2025.2 (xsim): `python tools/run_xsim.py ofb_vck190_tb`.

| Test | Result |
| --- | --- |
| TC-VCK-01 (`ofb_vck190_tb`) | Pass (99 us simulated) |
| TC-VCK-02 (RTL elaboration) | Pass |

TC-VCK-01: transceivers ready after 64.9 us, link initialised after 94.8 us (the far end started its lanes, the design
started with AutoStart); 6 packets on each of the 8 VCs and 4 broadcast messages came back unchanged and in order;
DL_ERRORS zero and no retry at the far end; LEDs 0 to 3 on. Rerun on the merged tree (serial loopback outputs of
the core to the adapter, bit synchronisation from the adapter, fault injection fixes, DED containment): pass. One
earlier run hung with a PLL divider error of the far-end transceiver model at time 0; it did not occur again
(model not deterministic, see the report of `ofb_pa_gty`).

TC-VCK-02: `vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl -tclargs project`, then `synth_design -rtl`:
the design elaborates without errors. The remaining warnings are unconnected ports of generic entities (unused bits
of the EDAC injection vectors, address bits of the AXI4-Lite slave, upper lanes of the 16-bit far-end activity
vector), null ranges of unused generics and registers removed as unused. The critical warning about the constraints
of the transceiver quad is expected at RTL level (the wizard instance is synthesised out of context). Rerun on main
546b81a (serial loopbacks, bit synchronisation, fault injection fixes, DED containment, status changes): the design
elaborates without errors; the clock constraint of the lane clock finds no clock at RTL level (the transmit clock of
the transceiver exists only after synthesis), as before.

## 2. Summary

All test cases pass. Synthesis, implementation, the timing and resource reports and the hardware test with
SpaceFibre test equipment are open: the host has no synthesis licence for the XCVC1902. The 8A34001 clock generator
of the board must provide 156.25 MHz on MGTREFCLK1 of quad 200 for the hardware test.
