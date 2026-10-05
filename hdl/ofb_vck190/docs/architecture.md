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
```

## 2. Clocks and resets

| Clock | Source | Use |
| --- | --- | --- |
| `SysClk` | 200 MHz LVDS, IBUFDS and BUFG | MIB (`MgmtClk`), free-running clock of the transceiver reset controller, power-on reset, LED poller |
| `LaneClk` | `ofb_pa_gty` (transmit user clock, 156.25 MHz) | `UserClk`, `CoreClk` and `LaneClk` of the core |

The core reset is the power-on reset or `LaneRst` (transmitters not ready). The echo needs no buffering: the output
port of every VC (`M_Vc`) feeds the input port of the same VC (`S_Vc`), back-pressure included.

## 3. Constraints (`constr/ofb_vck190.xdc`)

- System clock on AE42 / AF43 (LVDS15), transceiver reference clock on AD11 / AD10 (MGTREFCLK1_200).
- Quad location GTY_QUAD_X1Y0 (quad 200) and the serial pins of channels 0 to 3.
- LEDs on H34, J33, K36, L35 (LVCMOS18), false path.
- Crossings between `SysClk` and `LaneClk`: `set_max_delay -datapath_only` with the period of the faster clock, as
  required by Open Logic; the scoped constraints of Open Logic (base, intf) are added for implementation.

## 4. Build (`tcl/build.tcl`)

`vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl [-tclargs project | synth | impl | all]` creates the
project in `vivado_out/ofb_vck190` (Open Logic in the library `olo`, OpenFibre in the default library, VHDL-2008),
creates the transceiver wizard instance with `hdl/ofb_pa_gty/tcl/ofb_gtw.tcl`, adds the constraints and runs the
requested steps up to the device image.
