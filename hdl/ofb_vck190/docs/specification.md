# ofb_vck190: Specification

## 1. Overview

`ofb_vck190_top` is the reference design of OpenFibre for the AMD VCK190 evaluation board (XCVC1902): one core with
four lanes and eight virtual channels on the QSFP1 cage. Received packets and broadcast messages are sent back
(echo), so that SpaceFibre test equipment at the far end can exercise the link without software on the board.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| VCK-IF-01 | The design shall connect `ofb_core` (8 VCs, 4 lanes) through `ofb_pa_gty` to the four channels of GTY quad 200 (QSFP1) at 6.25 Gbit/s, with the reference clock on MGTREFCLK1 of quad 200 (156.25 MHz). | 5.4.2.3b, 5.6.2 |
| VCK-CK-01 | A 200 MHz LVDS system clock shall drive the MIB, the reset controller of the transceivers and a power-on reset; all other core clocks shall be the lane clock of `ofb_pa_gty`. | none (board integration) |
| VCK-ST-01 | The lanes shall start with AutoStart (reset value of the MIB) when the far end starts its lanes. | 5.5.2.6 |
| VCK-EC-01 | Every received packet shall be sent back unchanged on the same virtual channel, every received broadcast message unchanged with its channel, B_TYPE and DELAYED flag. | none (test function) |
| VCK-LD-01 | The LEDs 0 to 3 shall show transmitter ready, receiver ready, all lanes aligned and link initialised (Data Link link reset state machine in its final state, read from the MIB). | none |
| VCK-BD-01 | A Vivado script shall create the project with the transceiver wizard instance, the sources and the constraints, and run synthesis, implementation and the device image. | none |
| VCK-BD-02 | The design shall contain the control, interfaces and processing system (CIPS) of the Versal device, whose platform management controller configures the device (default configuration, JTAG boot); simulations run without it. | none (device boot) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels |
| `LedPollBits_g` | 16 | The link state is read from the MIB every 2^`LedPollBits_g` system clock cycles |
| `IncludeCips_g` | false | Instance of the CIPS block design `ofb_cips` (set to true by `tcl/build.tcl`) |

## 4. Board set-up

- QSFP1 (J288) carries the lanes 0 to 3 (GTY quad 200, channels 0 to 3, UG1366).
- The clock generator 8A34001 (U219) drives MGTREFCLK1 of quad 200 with its output Q1; it is programmed to
  156.25 MHz through the system controller of the board (UG1366).
- The system clock is the 200 MHz DDR4 DIMM clock (bank 700, pins AE42 / AF43).
