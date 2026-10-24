# ofb_vck190: Specification

## 1. Overview

`ofb_vck190_top` is the reference design of OpenFibre for the AMD VCK190 evaluation board (XCVC1902): one core with
four lanes and eight virtual channels on the QSFP1 cage. Received packets and broadcast messages are sent back
(echo), so that SpaceFibre test equipment at the far end can exercise the link without software on the board.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| VCK-IF-01 | The design shall connect `ofb_core` (8 VCs, 4 lanes) through `ofb_pa_gty` to the four channels of GTY quad 200 (QSFP1) at 6.25 Gbit/s, with the reference clock on MGTREFCLK1 of quad 200 (156.25 MHz). | 5.4.2.3b, 5.6.2 |
| VCK-CK-01 | A 100 MHz clock of the CIPS shall drive the MIB, the reset controller of the transceivers and a power-on reset (with the fabric reset of the CIPS), a 150 MHz clock of the CIPS the user side of the core; core clock and lane clock shall be the lane clock of `ofb_pa_gty`. | none (board integration) |
| VCK-ST-01 | The lanes shall start with AutoStart (reset value of the MIB) when the far end starts its lanes. | 5.5.2.6 |
| VCK-ST-02 | The initialisation timeout of the lanes shall be 468750 words (3 ms; `InitTimeoutWords_g` of the core, reset value of LANE_INIT_TIMEOUT), and the adapter shall reset the receiver of a lane at every restart of the lane without a gap (`RxRstGapCycles_g` = 0): a restarted lane stays in Started and sends INIT1 while its receiver resets. This deviates from the initialisation timeout of the standard (section 5). | 5.5.2.6b.1 (deviation), 5.5.2.7b.1 (deviation) |
| VCK-EC-01 | Every received packet shall be sent back unchanged on the same virtual channel, every received broadcast message unchanged with its channel, B_TYPE and DELAYED flag. | none (test function) |
| VCK-LD-01 | The LEDs 0 to 3 shall show transmitter ready, receiver ready, all lanes aligned and link initialised (Data Link link reset state machine in its final state, read from the MIB). | none |
| VCK-BD-01 | A Vivado script shall create the project with the transceiver wizard instance, the sources and the constraints, and run synthesis, implementation and the device image. | none |
| VCK-BD-02 | The design shall contain the control, interfaces and processing system (CIPS) of the Versal device, whose platform management controller configures the device (JTAG boot) and whose clock generator drives the clocks of the programmable logic; simulations run with clock models instead. | none (device boot) |
| VCK-MG-01 | The registers of the MIB shall be readable and writable from the master port M_AXI_FPD of the CIPS at 0xA400_0000 to 0xA400_0FFF (access over JTAG with XSDB, no software on the board), next to the LED poller. | none (test access, bit error rate test) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels |
| `LedPollBits_g` | 16 | The link state is read from the MIB every 2^`LedPollBits_g` management clock cycles |
| `IncludeCips_g` | false | Instance of the CIPS block design `ofb_cips` (set to true by `tcl/build.tcl`) |

## 4. Board set-up

- QSFP1 (J288) carries the lanes 0 to 3 (GTY quad 200, channels 0 to 3, UG1366).
- Transceiver reference clock, selected when the image is built: the programmable oscillator Si570 (U205) through
  the clock buffer SI53340 (U206) on GTY_REFCLK0 of quad 201 (default; 100 MHz after every power-up, no programming
  needed), or the clock generator 8A34001 (U219) with its output Q1 on MGTREFCLK1 of quad 200, programmed to
  156.25 MHz through the system controller of the board (UG1366).

## 5. Conformance

The design follows the conformance of the core (user guide, section 10) with one deviation:

| Clauses | Deviation | Reason |
| --- | --- | --- |
| 5.5.2.6b.1, 5.5.2.7b.1 | Initialisation timeout of 468750 words (3 ms at 156.25 MHz) instead of the time to send 5000 words (32 us) | At every restart of a lane the adapter resets the receiver of the lane, the reset the transceiver documentation (AM002) recommends after the remote end powers up, after electrical idle and after connecting the line. The reset takes about 6.3 us in the simulation of the transceiver model; on the device the reset time depends on the configuration (PG442 gives up to 150 ms for a full GT reset of a quad) and can exceed 32 us. With the longer timeout the lane stays in Started, sending INIT1, until its receiver is back, and every restart starts with a receiver that acquires the far-end signal afresh. The join hold of the core (8192 words) no longer covers a whole initialisation attempt: a lane that joins late costs one retry without data loss |

LANE_INIT_TIMEOUT can be set to 5000 words at run time (the value of the standard). Without a gap between two receiver
resets the receiver of a lane then resets at nearly every attempt; in that case clear RX_RESET_ON_DISCONNECT in PA_CTRL
or select the CDR-only receiver reset (RX_RESET_CDR_ONLY).
