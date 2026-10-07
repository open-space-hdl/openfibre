# ofb_vck190: Verification Plan

## 1. Overview

The reference design is verified at top level with the transceiver model in the AMD simulator (`python
tools/run_xsim.py ofb_vck190_tb`), connected to a far end made of an OpenFibre core with its own Physical adapter.
The build script is checked with the RTL elaboration of Vivado (`synth_design -rtl`), which needs no synthesis
licence; synthesis, implementation and the hardware test follow on a host with a licence for the XCVC1902.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_vck190_tb` | `ofb_vck190_top` (`LedPollBits_g` = 10) with clock models of the CIPS (100 MHz, 150 MHz) and 156.25 MHz reference clock; far end: `ofb_core` (8 VCs, 4 lanes) with `ofb_pa_gty`, reference clock 100 ppm slower, AXI4-Lite access, packet generator and checker per VC, broadcast generator and checker |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| TC-VCK-01 (`ofb_vck190_tb`) | The far end starts its lanes, the design starts with AutoStart; link initialised; 6 packets per VC on 8 VCs (1 to 30 words) and 4 broadcast messages sent by the far end come back unchanged and in order; no error and no retry at the far end; LEDs 0 to 3 on | VCK-IF-01, VCK-CK-01, VCK-ST-01, VCK-EC-01, VCK-LD-01 |
| TC-VCK-02 (RTL elaboration) | `build.tcl project`, then `synth_design -rtl`: the block design `ofb_cips` validates without errors with the address map M_AXI_FPD 0xA400_0000 (4 KB) and poller 0x000 (4 KB) to the MIB port; the design elaborates with the transceiver wizard instance and the CIPS block design (CIPS, SmartConnect `mib_axi`, all ports of `M_AXI_MIB` and `S_AXI_POLL` connected) without errors | VCK-BD-01, VCK-BD-02, VCK-MG-01 |

The hardware tests TC-VCK-HW-01 to 09 on the board with SpaceFibre test equipment are described in
[hardware_test.md](hardware_test.md); they run on a host with a licence for the XCVC1902. The register access over
JTAG (VCK-MG-01) is tested on the board by TC-VCK-HW-09 and used by TC-VCK-HW-08; the XSDB script
`tcl/xsdb_mib.tcl` is checked offline (sourced in XSDB, address and pattern helpers).
