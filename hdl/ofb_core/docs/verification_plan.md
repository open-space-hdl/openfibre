# ofb_core: Verification Plan

## 1. Overview

The core is verified with two cores connected through the behavioural Physical adapter model, with all four clock
domains at different frequencies (user 192 MHz, core 166.7 MHz, lane 156.25 MHz, management 100 MHz). The cores are
configured and monitored through the MIB with the UVVM AXI-Lite VVC; packets and broadcast messages are random and
checked with scoreboards. The final end-to-end test with the transceiver model follows in phase 5.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_core_tb` | `ofb_core_th` | Two `ofb_core` (4 VCs) A and B with `NumLanes_g` = 1 to 4 (VUnit configurations `lanes1` to `lanes4`), `LaneClkFreq_g` and `CoreClkFreq_g` derived from the generated clock periods, one `ofb_tb_pa_model` per lane, one `ofb_tb_axilite_master` per core, packet generator and receiver per VC (random length and bytes, beats of 4 x `NumLanes_g` bytes with `TKEEP` and `TLAST`, receiver back-pressure; the receiver checks the `TKEEP` format and compares the packets as words of four bytes with a last word of the remaining bytes, the end marker (EOP, or EEP from `TUSER`) and Fills), broadcast generator and receiver (channel, B_TYPE and DELAYED compared; LATE depends on the error recovery), SCHEDULE.request strobe per core, raw beat queue for VC 0 of A (bytes, `TKEEP`, `TLAST`, `TUSER`) |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link_up` (TC-CORE-01) | ID register; LaneStart of A through the MIB, AutoStart at B: both ends reach Link Initialised, lane Active, no error; bit synchronisation of every lane of A (model: signal present and CDR enabled) in LANE_STATUS | CORE-IF-01, CORE-CK-01, CORE-RS-01, CORE-SY-01, CORE-PL-02, MG-PL-02 |
| `test_traffic` (TC-CORE-02) | 15 packets per VC and 10 broadcast messages (random channel, B_TYPE and DELAYED flag) in both directions: all delivered unchanged, no error and no retry in the MIB | CORE-SY-01, CORE-CC-01, NI-IF-01, NI-IF-02, NI-TX-01, NI-TX-02, NI-RX-01, NI-RX-04 |
| `test_traffic_mix` (TC-CORE-17) | 8 packets per VC and direction with lengths that cycle through the classes 1 to 4, 5 to 64, 65 to 256 and 257 to 1024 bytes, 20 broadcast messages per direction, receivers ready 70 % of the time: all delivered unchanged, no error; functional coverage: every length class on every VC in both directions, broadcast messages with and without DELAYED flag | CORE-SY-01, CORE-CC-01, NI-IF-01, NI-IF-02, NI-TX-01, NI-TX-02, NI-RX-01, NI-RX-04 |
| `test_prbs` (TC-CORE-18) | PRBS test from A to B on every lane through the MIB registers (behavioural adapter model with a functional PRBS checker): the checkers of B lock, no error, a forced error at A is counted at B on lane 0 only, a PRBS-7 checker on the PRBS-31 pattern counts errors | CORE-PL-03, MG-PR-01, MG-PR-02, MG-PR-03 |
| `test_error_recovery` (TC-CORE-03) | 20 bit errors per direction during traffic (200 packets per VC and end, so that the bit errors hit data frames also with four lanes): all delivered, retries counted in the MIB, no link reset | CORE-SY-01 |
| `test_far_end_restart` (TC-CORE-19) | Complete restart of one end while the other end is in Link Initialised: power-on reset of B, Interface Reset of B, power-on reset of A; Far-End Link Reset at the other end each time, link up again, traffic | CORE-SY-03 |
| `test_long_packets` (TC-CORE-20) | Packets of 65542 bytes (largest Space Packet): one from A to B on VC 0, then two at the same time from B to A on VCs 1 and 2; every byte compared, no error flag at either end | CORE-SY-04, CORE-SY-01 |
| `test_tx_ready_late` (TC-CORE-21) | `Phy_TxReady` of A 0 from the reset on and 1 after 50 us: until then A in Near-End Reset (DL_STATUS bits 1:0 = 01, TX_READY 0), no lane of A enabled (transmitter, receiver, CDR), link of B not initialised; afterwards link up, TX_READY 1, no error flag at either end (TX_LOST is not raised by the first start), traffic | CORE-PL-04, CORE-CC-01, DL-LR-06, MG-ST-06 |
| `test_tx_ready_never` (TC-CORE-22) | `Phy_TxReady` of A stays 0, all interrupt sources of A enabled: during 300 us A in Near-End Reset, no lane of A enabled, no interrupt, no error flag, retry or lane event; the MIB of A stays accessible | CORE-PL-04, CORE-CC-01, DL-LR-06, MG-ST-06 |
| `test_tx_ready_lost` (TC-CORE-23) | `Phy_TxReady` of A falls during traffic (lossy comparison): A in Near-End Reset with TX_LOST set, no lane of A enabled in the last 5 us of the hold, configuration of A kept; when it rises the link initialises again and the traffic is delivered; TX_LOST stays set until it is cleared | CORE-PL-04, CORE-CC-01, DL-LR-06, MG-ST-06 |
| `test_link_reset` (TC-CORE-04) | Link Reset command at A through the MIB: both ends reset, Far-End Link Reset at B only, link up again, traffic | CORE-SY-01, CORE-CC-01 |
| `test_qos_config` (TC-CORE-06) | Bandwidth of VC 3 of A set to zero through the MIB: its packets wait; with a bandwidth they are delivered. VC 3 of A excluded from time-slot 5, SCHEDULE.request to slot 5 at the Network interface: current time-slot 5 in the MIB, the packets of VC 3 wait; SCHEDULE.request to slot 0: delivered | CORE-IF-01, CORE-SY-01, NI-SC-01 |
| `test_framing_error` (TC-CORE-05) | Raw beats at VC 0 of A: a gap in `TKEEP` in the first beat (nothing reaches B, no packet of zero length at B), a partial `TKEEP` without `TLAST` in the second beat (B receives the first beat ended with EEP, the rest is discarded), a packet of three bytes with the EEP flag of the user (received with EEP); the framing error flags are set at A (VC_FRAMING_ERROR, DL_ERRORS bit 9), no receive framing error and NI_RX_EMPTY_COUNT zero at B | CORE-IF-01, NI-TX-01, NI-TX-03, NI-TX-04, NI-RX-01 |
| `test_lane_failure` (TC-CORE-07) | Several lanes: the highest lane is cut during traffic in both directions and reconnected: every packet delivered, Misaligned condition counted, no link reset, the lane sends data again | CORE-SY-02, CORE-ML-01 |
| `test_max_data_lanes` (TC-CORE-08) | Maximum number of data-sending lanes 1 through the MIB, Link Reset: one data-sending lane, traffic with packets up to 300 bytes delivered | CORE-SY-02, CORE-ML-01 |
| `test_serial_loopback_near` (TC-CORE-11) | B disabled; near-end serial loopback at A through the MIB, LaneStart at A: the Physical adapter model returns the transmitter of A to its receiver; the lanes and the link of A initialise with themselves, the lanes of B stay inactive, a packet sent on VC 0 of A is received on VC 0 of A, no error | CORE-PL-01, MG-PL-01 |
| `test_serial_loopback_far` (TC-CORE-12) | B disabled with far-end serial loopback through the MIB, LaneStart at A: the model returns the signal of A at B; the lanes and the link of A initialise with themselves, a packet of A comes back to A, no error | CORE-PL-01, MG-PL-01 |
| `test_ecc_injection` (TC-CORE-10) | A single error injected through the MIB into each of the 9 EDAC channels of A before traffic in both directions, broadcast messages and a QoS write: every channel counts a corrected error, no DED, all packets delivered | CORE-ED-01 |
| `test_fault_campaign` (TC-CORE-13) | Fault injection campaign (seed `Seed_g`): 40 random faults 2 to 15 us apart during packets of all length classes (up to 1024 bytes, several data frames) on all VCs (about 60 % of the link capacity) and broadcast messages in both directions: single bit error or burst of 2 to 8 symbols with bit errors on a random lane and direction, word slip (skew of a line changed by one word), single error injected through the MIB into a random EDAC channel of a random core, double error into a row crossing, and with several lanes a lane cut for 5 to 30 us followed by the return of all lanes. Then: every packet and message delivered unchanged and in order, link initialised at both ends without link reset, retries at both ends, SEC counted in every channel with a single error, DED flags and counts exactly in the channels with a double error, all lanes sending and receiving data; functional coverage: every fault kind injected, every length class on every VC in both directions | CORE-FT-01, CORE-ED-01, CORE-ED-02, CORE-SY-02 |
| `test_throughput` (TC-CORE-16) | Latency of a packet of one byte on the idle link (reported); payload throughput with packets of 1 to 1024 bytes on all VCs, over 100 us after 20 us of warm-up: from A to B only at least 90 % of the lane capacity, in both directions at least 85 % per direction | CORE-PF-01 |
| `test_row_overflow` (TC-CORE-15) | Configuration `lanes1_slowcore` (CoreClk half period 4 ns, LaneClk 3.2 ns): lanes started, receive rows lost in the crossing, DL_ERRORS bit 10 set at A; regular configurations: traffic in both directions, no row overflow at either end | CORE-CC-02, MG-ST-04, CORE-CK-01 |
| `test_ded_containment` (TC-CORE-14) | Lossy comparison (packets may be lost or end with EEP, every word received must be correct): a DED injected through the MIB into each buffer channel of the Data Link layer of A (output VC, error recovery, frame, input VC, broadcast output, broadcast input) during traffic in both directions: DED counted; link reset (far-end link reset at B) for the output VC, error recovery, frame and broadcast output buffers, none for the input buffers; no protocol error; traffic after the error delivered; a broadcast message discarded at A. For the input VC buffers the DED is injected twice with no traffic in flight: into an early word of one packet of 1024 bytes per VC from B (the packet ends with EEP at A, its rest of several beats is discarded up to its end), then into one of four packets of one word per VC (the beat with the error is the whole packet: the EEP that replaces it is a packet of zero length, discarded and counted in NI_RX_EMPTY_COUNT of A, one per VC); together at least two packets per VC end with EEP at A or are discarded as packets of zero length | DL-ED-01, DL-ED-02, DL-LR-05, CORE-ED-01, NI-RX-02 |
| `test_bypass` (TC-CORE-09) | Multi-Lane bypass through the MIB at both cores: bypass and lane 0 reported, traffic delivered | CORE-SY-02, CORE-ML-01 |

All test cases run in the four lane configurations; with one lane TC-CORE-07 only checks the link start.

### Generic ranges

Every value of a generic that changes the structure of the core is simulated, and the boundaries of the numeric
ranges are simulated and synthesised. The configurations below run the named test cases in addition to the lane
configurations; `python lint/synth_check.py` synthesises the same boundaries with GHDL and checks that every value
outside the ranges is rejected at elaboration with the message of its check (`VcOutDepth_g` 32 with one lane, 16
with two lanes, 96; `VcInDepth_g` 96 and 192 with one lane, 128 with two lanes, 256 with four lanes; `ErbRows_g` 32
and 96).

| Test cases | Configuration | Requirements |
| --- | --- | --- |
| TC-CORE-01, TC-CORE-02, TC-CORE-04 (`vc1`, `vc32`) | One VC with two lanes (a point-to-point or configuration link, ECSS 5.8.4d) and the maximum of 32 VCs with two lanes (four lanes with 32 VCs are elaborated and synthesised by `lint/synth_check.py`); TC-CORE-01 reads the generics from the MIB (GENERICS) | CORE-IF-01, MG-IF-02 |
| TC-CORE-01, TC-CORE-04 (`halfrate`) | Two lanes with `LaneClk` at 78.125 MHz (half the data signalling rate) and `LaneClkFreq_g` to match: TC-CORE-04 measures ClearLine (2 us) at the lanes of A after the Link Reset command | CORE-CK-02, LN-INIT-02 |
| TC-CORE-01, TC-CORE-02, TC-CORE-03, TC-CORE-04 (`minbuf`) | Two lanes with the smallest buffers: output VC buffer 64 words, input VC buffer 128 words per lane (two flow control units), error recovery buffer 64 rows | DL-VO-05, DL-VI-05, DL-ER-08 |
| TC-CORE-01, TC-CORE-02 (`noprbs`) | One lane, lane initialisation without PRBS words after INIT1 and INIT2 (`InitPrbsWords_g` = 0) | LN-TX-01 |

## 4. Functional coverage

The harness samples UVVM coverpoints (`func_cov_pkg`) in its receivers, the sequencer those of the fault injection
campaign; every test prints the coverage summary at its end.

| Coverpoint | Bins | Goal checked by |
| --- | --- | --- |
| `CovPkt` | Sending core x VC x length class of the packets ended with EOP (1 to 4, 5 to 64, 65 to 256, 257 to 1024 bytes) | TC-CORE-13, TC-CORE-17 |
| `CovEnd` | Sending core x end of the packet (EOP, EEP) | Measured; TC-CORE-14 checks the packets ended with EEP |
| `CovBc` | Sending core x DELAYED flag of the broadcast messages | TC-CORE-17 |
| `CovLate` | Sending core x LATE flag (messages resent by the error recovery) | Measured (TC-CORE-13) |
| `CovFault` | Fault kind of the campaign (bit error, burst, word slip, SEC, DED, lane cut with 2 and 4 lanes) | TC-CORE-13 |
| `CovLine` | Line fault kind (bit error, burst, word slip, lane cut) x lane | Measured (TC-CORE-13) |
| `CovSec` | Core x EDAC channel of the single errors of the campaign | Measured; TC-CORE-10 injects into every channel |

The unit and layer testbenches are directed: every test case drives one scenario of its plan, and the code coverage
([docs/coverage.md](../../../docs/coverage.md)) shows that the test cases reach every statement, branch and state
machine transition.
