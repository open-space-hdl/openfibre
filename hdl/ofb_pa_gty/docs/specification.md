# ofb_pa_gty: Specification

## 1. Overview

`ofb_pa_gty` is the Physical adapter PA-1 of OpenFibre for one AMD Versal GTY quad (ECSS-E-ST-50-11C clause 5.4 and
the symbol level of clauses 5.3.2 and 5.5.6). It connects up to four lanes of `ofb_core` to the transceiver: the
serialiser and deserialiser, the 8B/10B codec (PA-2), the comma alignment and the receive elastic buffer with clock
correction (PA-3) are functions of the transceiver.

| Block | Implementation | Function |
| --- | --- | --- |
| PA-1 | `ofb_pa_gty` | Mapping of the symbol streams and the lane control to the transceiver channels, user clock, status |
| PA-2 | Transceiver (`ofb_gtw`) | 8B/10B encoding and decoding |
| PA-3 | Transceiver (`ofb_gtw`) | Comma alignment, receive elastic buffer with clock correction |

`ofb_gtw` is an instance of the Versal Transceivers Wizard, created by `tcl/ofb_gtw.tcl`. The module is the only
target-specific part of OpenFibre; it is not part of the GHDL regression (section 4).

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| PA-IF-01 | The adapter shall take one word of four symbols (8 bits and a K flag each, symbol 0 first) per lane and `LaneClk` cycle for transmission and pass one received word of four decoded symbols per cycle with a K flag, a code error flag and a disparity error flag per symbol and a valid flag. | 5.4.1b, c, 5.5.1k, l, 6.4.2 |
| PA-IF-02 | The adapter shall disable the line driver (electrical idle) when line driver enable is low, mark received words invalid when line receiver enable is low, hold the clock data recovery when CDR enable is low and invert the received bits when Invert RX Polarity is high. | 5.4.1d, 5.4.2h, 6.4.3 |
| PA-IF-03 | NoSignal shall be the electrical idle indication of the receiver of the lane, synchronised to `LaneClk`. | 5.4.1e, 5.4.2.4a |
| PA-LB-01 | The near-end serial loopback of a lane shall connect the serialiser output of the channel to its deserialiser input (near-end PMA loopback), the far-end serial loopback the received serial signal to the line driver (far-end PMA loopback); after a change of a far-end loopback the transmitters shall be reset. | 5.4.1h, 5.4.2.2a to c |
| PA-SE-01 | Every lane shall transmit and receive at 6.25 Gbit/s, symbols serialised least significant bit first. | 5.4.2a to c, 5.4.2.3b |
| PA-SE-02 | The symbols shall be encoded and decoded with 8B/10B; a symbol that is not a valid code group shall set the code error flag, a running disparity error the disparity error flag. | 5.3.2, 5.5.7j, k |
| PA-SY-01 | The receiver shall align the symbols on positive and negative commas (7-bit comma sequences) and realign when a comma is detected in another position; the comma shall be placed in symbol 0 of a received word. | 5.5.6a to g, 5.5.7c |
| PA-CC-01 | The received words shall pass a receive elastic buffer into `LaneClk`; the buffer shall insert or remove SKIP words (K28.7, LLCW, SKIP, SKIP) to compensate the difference of the signalling rates. | 5.5.3 (receive side) |
| PA-CK-01 | `LaneClk` shall be the transmit user clock of the quad (156.25 MHz from a 156.25 MHz reference clock), common to all lanes; all transmitters and receivers use it. | 5.6.2 (note), 5.4.2.3a |
| PA-RS-01 | The asynchronous reset shall start the reset sequence of the transceiver; `LaneRst` shall be high until the transmitters are ready, the received words invalid until the receivers are ready. | none (implementation) |
| PA-ST-01 | The adapter shall report transmitter ready, receiver ready, comma alignment per lane, receive buffer errors per lane and a pulse per clock correction of a receive elastic buffer. | 5.4.2e |
| PA-PR-01 | For the bit error rate test of the electrical link, the PRBS generator and the PRBS checker of every transceiver channel shall be selectable per lane (`LaneClk`, 4 bits, transceiver encoding: 0 off, 1 PRBS-7, 2 PRBS-9, 3 PRBS-15, 4 PRBS-23, 5 PRBS-31); they bypass the 8B/10B codec. A single-cycle pulse shall insert one error into the transmitted pattern, another one reset the checker; the checker shall report per `LaneClk` cycle whether the received word contains a bit error, and its lock to the pattern. | none (test function) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumLanes_g` | 4 | Number of lanes (1 to 4); channels 0 to `NumLanes_g` - 1 of the quad, the other channels send electrical idle |

Transceiver settings (`tcl/ofb_gtw.tcl`): line rate 6.25 Gbit/s, reference clock frequency (argument, 156.25 MHz for
the VCK190), LCPLL, 8B/10B, user data width 32 bits, internal width 40 bits, comma alignment on 4-byte boundaries,
receive elastic buffer with clock correction sequence K28.7 D14.6 D31.3 D31.3 (expected rate difference 200 ppm).

## 4. Verification environment

The transceiver is an encrypted model of the AMD simulation libraries. Its test runs separately from the GHDL
regression with the AMD simulator (`tools/run_xsim.py`); the final end-to-end test of two cores over the transceiver
model follows the same flow.

## 5. Interpretation of the standard

- The serial loopbacks (5.4.2.2) are the PMA loopbacks of the transceiver. In near-end loopback the transmitter
  still drives the line. A far-end loopback resets the transmit datapath of the quad (the transceiver requires a
  transmit reset after entering or leaving it), so the transmitters of the other lanes restart as well. The far-end
  loopback retimes the received bits with the transmit clock of the loopback end: with different reference clocks at
  the two ends, bits are lost or repeated at intervals given by the frequency difference (seen in the simulation at
  1000 ppm); the error recovery of the Data Link layer at the far end corrects the affected frames.
- Bit synchronisation status (5.4.2e) is reported as the comma alignment of the receiver (`Stat_Aligned`). The
  VCK190 reference design connects it to `Phy_BitSync` of the core (LANE_STATUS bit 6).
- The deserialiser is ready within 150000 bits after a valid signal appears (5.4.2g) once the transceiver reset
  sequence is complete; the receive clock data recovery of the GTY locks within a few microseconds.
