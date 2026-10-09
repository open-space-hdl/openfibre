# ofb_vck190: Architecture and Design Description

## 1. Block diagram

```text
 ofb_cips_wrapper (block design ofb_cips: versal_cips, SmartConnect mib_axi)
   pl0_clk (100 MHz) --> MgmtClk --> olo_ft_reset_gen (pl0_resetn) ---> PorRst
   pl1_clk (150 MHz) --> UserClk
   M_AXI_FPD (0xA400_0000) --+
   S_AXI_POLL <-- p_poll ----+--> mib_axi --> M_AXI_MIB --> AXI4-Lite of ofb_core
                                      |
 GtRefClk_P/N --> IBUFDS_GTE5 --> ofb_pa_gty (quad 200) <--> Qsfp_Tx/Rx (lanes 0..3)
                                      | LaneClk, LaneRst
                                      v
                                   ofb_core (8 VCs, 4 lanes)   CoreClk = LaneClk = 156.25 MHz,
                                   M_Vc --> S_Vc (echo)        UserClk = 150 MHz, MgmtClk = 100 MHz
                                   M_Bc --> S_Bc (echo)
                                   p_poll (DL_STATUS) --> Led(3)
```

## 2. Clocks and resets

| Clock | Source | Use |
| --- | --- | --- |
| `MgmtClk` | CIPS `pl0_ref_clk`, 100 MHz (`clk_pl_0`) | MIB, free-running clock of the transceiver reset controller, power-on reset (with the fabric reset `pl0_resetn`), LED poller |
| `UserClk` | CIPS `pl1_ref_clk`, 150 MHz (`clk_pl_1`) | User side of the core (VC and broadcast ports, echo) |
| `LaneClk` | `ofb_pa_gty` (transmit user clock, 156.25 MHz) | `CoreClk` and `LaneClk` of the core |

`CoreClk` is the lane clock, so that it is never slower than `LaneClk` (CORE-CK-01). `UserClk` is independent of
the link and exercises the user clock crossings of the core; at 150 MHz a VC port of 128 bits carries 19.2 Gbit/s,
more than the 18.7 Gbit/s that four lanes deliver (94 % of the payload capacity, user guide section 7). In
simulation (`IncludeCips_g` = false) clock models of the same frequencies replace the CIPS.

The core reset is a register of `MgmtClk`: the power-on reset or `LaneRst` (transmitters not ready, a register of
the lane clock, synchronised with `olo_ft_sync`), so that no logic sits in front of the reset synchronisers of the
core. The echo needs no buffering: the output
port of every VC (`M_Vc`) feeds the input port of the same VC (`S_Vc`), back-pressure included. The serial loopback
enables of the core drive the adapter, and the comma alignment of the adapter (`Stat_Aligned`) is the bit
synchronisation status of the core (`Phy_BitSync`, LANE_STATUS bit 6). The PRBS test signals of the core (`Phy_Prbs*`)
connect to the PRBS generator and checker of the transceiver channels.

## 3. Register access

The MIB has one AXI4-Lite port and two masters. In the block design `ofb_cips` a SmartConnect (`mib_axi`, clock
`pl0`, reset from a `proc_sys_reset` of `pl0_resetn`) takes the master port M_AXI_FPD of the CIPS (32 bits) and the
LED poller of the top level (`S_AXI_POLL`), arbitrates between them and drives the MIB (`M_AXI_MIB`, AXI4-Lite,
32 bits). Address map:

| Master | MIB registers |
| --- | --- |
| CIPS M_AXI_FPD | 0xA400_0000 to 0xA400_0FFF (register offset = address - 0xA400_0000) |
| LED poller | 0x000 to 0xFFF |

`M_AXI_MIB` carries 32 address bits; the top level uses bits 11:0. Over JTAG, XSDB reads and writes the registers
through the debug access port of the device without software on the board (hardware test procedure, section 7). In
simulation (`IncludeCips_g` = false) the poller drives the MIB port directly.

## 4. Constraints (`constr/ofb_vck190.xdc`)

- Transceiver reference clock on AD11 / AD10 (MGTREFCLK1_200); the clocks of the CIPS are created by its IP
  constraints (`clk_pl_0`, `clk_pl_1`).
- Quad location GTY_QUAD_X1Y0 (quad 200) and the serial pins of channels 0 to 3.
- LEDs on H34, J33, K36, L35 (LVCMOS18), false path.
- Crossings between `clk_pl_0`, `clk_pl_1` and the lane clock: `set_max_delay -datapath_only` with the period of
  the faster clock of each pair, as required by Open Logic; the scoped constraints of the Open Logic base entities are
  added for implementation. The scoped constraint of `olo_intf_sync` is not loaded for `olo_ft_sync`: it constrains
  device pins, and the design uses `olo_ft_sync` only for internal asynchronous signals (transceiver status, far-end
  loopback, lane
  reset), whose crossings the clock pair constraints cover.

## 5. Build (`tcl/build.tcl`)

Every Versal design needs the CIPS IP: its platform management controller loads the device image. The script
creates the block design `ofb_cips` with one `versal_cips` (JTAG boot) whose PMC clock generator drives two clocks of
the programmable logic (`pl0_ref_clk` 100 MHz, `pl1_ref_clk` 150 MHz) and the fabric reset `pl0_resetn`, all three
external ports of the block design, and whose master port M_AXI_FPD reaches the MIB (section 3); it generates the
wrapper and sets `IncludeCips_g` = true, so that the top instantiates it. The simulations keep the default false and
use clock models instead.

`vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl [-tclargs project | synth | impl | all]` creates the
project in `vivado_out/ofb_vck190` or in the directory of the environment variable `OFB_VIVADO_OUT` (on Windows at
most about 40 characters, see the hardware test procedure) (Open Logic in the library `olo`, OpenFibre in the default
library, VHDL-2008, all files of one library with one `add_files` call),
creates the transceiver wizard instance with `hdl/ofb_pa_gty/tcl/ofb_gtw.tcl`, adds the constraints and runs the
requested steps up to the device image. The implementation run uses the strategy
`Performance_ExplorePostRoutePhysOpt` (several placement and routing directives, physical optimization also after
routing).
