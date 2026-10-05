# ofb_vck190: Architecture and Design Description

## 1. Block diagram

```text
 SysClk_P/N --> IBUFDS --> BUFG --> SysClk (200 MHz) --> olo_base_reset_gen --> PorRst
                                      |
 GtRefClk_P/N --> IBUFDS_GTE5 --> ofb_pa_gty (quad 200) <--> Qsfp_Tx/Rx (lanes 0..3)
                                      | LaneClk, LaneRst
                                      v
                                   ofb_core (8 VCs, 4 lanes)   UserClk = CoreClk = LaneClk = 156.25 MHz,
                                   M_Vc --> S_Vc (echo)        MgmtClk = SysClk
                                   M_Bc --> S_Bc (echo)
                                   AXI4-Lite <-- p_poll (DL_STATUS) --> Led(3)

 ofb_cips_wrapper (block design ofb_cips: versal_cips, no ports; only with IncludeCips_g)
```

## 2. Clocks and resets

| Clock | Source | Use |
| --- | --- | --- |
| `SysClk` | 200 MHz LVDS, IBUFDS and BUFG | MIB (`MgmtClk`), free-running clock of the transceiver reset controller, power-on reset, LED poller |
| `LaneClk` | `ofb_pa_gty` (transmit user clock, 156.25 MHz) | `UserClk`, `CoreClk` and `LaneClk` of the core |

The core reset is the power-on reset or `LaneRst` (transmitters not ready). The echo needs no buffering: the output
port of every VC (`M_Vc`) feeds the input port of the same VC (`S_Vc`), back-pressure included. The serial loopback
enables of the core drive the adapter, and the comma alignment of the adapter (`Stat_Aligned`) is the bit
synchronisation status of the core (`Phy_BitSync`, LANE_STATUS bit 6).

## 3. Constraints (`constr/ofb_vck190.xdc`)

- System clock on AE42 / AF43 (LVDS15), transceiver reference clock on AD11 / AD10 (MGTREFCLK1_200).
- Quad location GTY_QUAD_X1Y0 (quad 200) and the serial pins of channels 0 to 3.
- LEDs on H34, J33, K36, L35 (LVCMOS18), false path.
- Crossings between `SysClk` and `LaneClk`: `set_max_delay -datapath_only` with the period of the faster clock, as
  required by Open Logic; the scoped constraints of Open Logic (base, intf) are added for implementation.

## 4. Build (`tcl/build.tcl`)

Every Versal design needs the CIPS IP: its platform management controller loads the device image. The script
creates the block design `ofb_cips` with one `versal_cips` in its default configuration (no interfaces to the
programmable logic, JTAG boot), generates its wrapper and sets `IncludeCips_g` = true, so that the top instantiates
the wrapper (a component without ports). The simulations keep the default false and need no CIPS model.

`vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl [-tclargs project | synth | impl | all]` creates the
project in `vivado_out/ofb_vck190` (Open Logic in the library `olo`, OpenFibre in the default library, VHDL-2008),
creates the transceiver wizard instance with `hdl/ofb_pa_gty/tcl/ofb_gtw.tcl`, adds the constraints and runs the
requested steps up to the device image.
