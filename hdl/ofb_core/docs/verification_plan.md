# ofb_core: Verification Plan

## 1. Overview

The core is verified with two cores connected through the behavioural Physical adapter model, with all four clock
domains at different frequencies (user 192 MHz, core 166.7 MHz, lane 156.25 MHz, management 100 MHz). The cores are
configured and monitored through the MIB with the UVVM AXI-Lite VVC; packets and broadcast messages are random and
checked with scoreboards. The final end-to-end test with the transceiver model follows in phase 5.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_core_tb` | `ofb_core_th` | Two `ofb_core` (4 VCs) A and B with `NumLanes_g` = 1, 2 and 4 (VUnit configurations `lanes1`, `lanes2`, `lanes4`), one `ofb_tb_pa_model` per lane, one `ofb_tb_axilite_master` per core, packet generator and receiver per VC (random length, receiver back-pressure, beats of `NumLanes_g` words, every packet starts in a new beat; words of four Fills are not compared), broadcast generator and receiver (channel, B_TYPE and DELAYED compared; LATE depends on the error recovery), SCHEDULE.request strobe per core, raw word queue for VC 0 of A |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link_up` (TC-CORE-01) | ID register; LaneStart of A through the MIB, AutoStart at B: both ends reach Link Initialised, lane Active, no error | CORE-IF-01, CORE-CK-01, CORE-RS-01, CORE-SY-01 |
| `test_traffic` (TC-CORE-02) | 15 packets per VC and 10 broadcast messages (random channel, B_TYPE and DELAYED flag) in both directions: all delivered unchanged, no error and no retry in the MIB | CORE-SY-01, CORE-CC-01, NI-IF-01, NI-IF-02, NI-RX-01 |
| `test_error_recovery` (TC-CORE-03) | 20 bit errors per direction during traffic: all delivered, retries counted in the MIB, no link reset | CORE-SY-01 |
| `test_link_reset` (TC-CORE-04) | Link Reset command at A through the MIB: both ends reset, Far-End Link Reset at B only, link up again, traffic | CORE-SY-01, CORE-CC-01 |
| `test_qos_config` (TC-CORE-06) | Bandwidth of VC 3 of A set to zero through the MIB: its packets wait; with a bandwidth they are delivered. VC 3 of A excluded from time-slot 5, SCHEDULE.request to slot 5 at the Network interface: current time-slot 5 in the MIB, the packets of VC 3 wait; SCHEDULE.request to slot 0: delivered | CORE-IF-01, CORE-SY-01, NI-SC-01 |
| `test_framing_error` (TC-CORE-05) | Word with K28.7 at the Network interface of A: B receives the packet ended with EEP, the framing error flags are set at A | CORE-IF-01, NI-FR-01, NI-FR-02 |
| `test_lane_failure` (TC-CORE-07) | Several lanes: the highest lane is cut during traffic in both directions and reconnected: every packet delivered, Misaligned condition counted, no link reset, the lane sends data again | CORE-SY-02, CORE-ML-01 |
| `test_max_data_lanes` (TC-CORE-08) | Maximum number of data-sending lanes 1 through the MIB, Link Reset: one data-sending lane, traffic with packets up to 300 bytes delivered | CORE-SY-02, CORE-ML-01 |
| `test_serial_loopback_near` (TC-CORE-11) | B disabled; near-end serial loopback at A through the MIB, LaneStart at A: the Physical adapter model returns the transmitter of A to its receiver; the lanes and the link of A initialise with themselves, the lanes of B stay inactive, a packet sent on VC 0 of A is received on VC 0 of A, no error | CORE-PL-01, MG-PL-01 |
| `test_serial_loopback_far` (TC-CORE-12) | B disabled with far-end serial loopback through the MIB, LaneStart at A: the model returns the signal of A at B; the lanes and the link of A initialise with themselves, a packet of A comes back to A, no error | CORE-PL-01, MG-PL-01 |
| `test_ecc_injection` (TC-CORE-10) | A single error injected through the MIB into each of the 9 EDAC channels of A before traffic in both directions, broadcast messages and a QoS write: every channel counts a corrected error, no DED, all packets delivered | CORE-ED-01 |
| `test_bypass` (TC-CORE-09) | Multi-Lane bypass through the MIB at both cores: bypass and lane 0 reported, traffic delivered | CORE-SY-02, CORE-ML-01 |

All test cases run in the three configurations; with one lane TC-CORE-07 only checks the link start.
