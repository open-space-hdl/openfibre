# ofb_ni: Verification Plan

## 1. Overview

The packet ports of the virtual channels (NI-1) are verified with a module testbench of `ofb_ni` that drives and
observes all four streams of two VCs: the packets of the user, the rows to the Data Link layer, the rows from the
Data Link layer and the received packets. The expected rows and bytes come from a model of the N-Char format of ECSS
5.3.7 in the testbench, not from the RTL. The broadcast port (NI-3), the schedule port (NI-4) and the packets between
two complete cores are verified in the core testbench.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_ni_tb` with `ofb_ni_th` | `ofb_ni` with two VCs and `NumLanes_g` = 1 to 4 (VUnit configurations `lanes1` to `lanes4`: 4, 8, 12 and 16 bytes per beat). Per VC: a driver of the packets to send and a driver of the received rows (queues filled by the sequencer, random valid), a monitor of the rows to the Data Link layer and a monitor of the received packets (random ready). The row monitor compares every word with K flags; the packet monitor checks the `TKEEP` format (byte 0 valid, contiguous, all bytes in a beat without `TLAST`) and compares every byte with its position (last byte of the packet, EEP flag). Counters of the three events per VC |

The sequencer builds the received rows from character patterns (data, EOP, EEP, Fill, K28.5) with the rule of the
input VC buffer: a row ends after the word with an end marker and is completed with Fills. Data bytes are running
counters per VC, so that a lost, repeated or misplaced byte is detected.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_tx_packets` (TC-NI-01) | Packets of every length from 1 to 3 x B + 1 bytes (B = 4 x `NumLanes_g`) on both VCs, every third with the EEP flag, random handshakes: data characters in stream order from character 0, the end marker after the last byte, Fills up to the end of the row, an additional row with the end marker after a full last beat; no framing error | NI-IF-01, NI-TX-01, NI-TX-02 |
| `test_tx_framing` (TC-NI-02) | Invalid `TKEEP`: a gap in the first beat of a packet (nothing passed, the beats up to `TLAST` discarded), a partial `TKEEP` without `TLAST` in the second beat (the first beat passed, then an EEP row, the rest discarded; a further invalid beat while discarding is not reported), `TKEEP` all zero with `TLAST` after a full beat (EEP row, no discard), `TKEEP` without byte 0 in a single beat with `TLAST` (nothing passed); one event per error, the following packets pass | NI-TX-03, NI-TX-04 |
| `test_rx_packets` (TC-NI-03) | Received packets after 0 to 2 x B + 3 leading Fills (every offset in the word and in the beat, whole Fill words and rows) with 1 to 2 x B + 2 bytes, EOP or EEP, random handshakes: bytes aligned to byte 0 of the beat, all bytes valid except in the last beat, `TLAST` on the last byte (also when the end marker is alone in the next word), `TUSER` = EEP | NI-IF-01, NI-RX-01 |
| `test_rx_empty` (TC-NI-04) | Packets of zero length between packets: an EOP or EEP alone, after Fills in the same word, after a row of Fills; discarded and counted, the packets between them pass | NI-RX-02 |
| `test_rx_framing` (TC-NI-05) | Character rule violations: a Fill inside an open packet with offset 0 and 1 (the bytes of the earlier beats passed with `TLAST` and EEP, the rest discarded up to the next clean end), data after an EOP in the same word (nothing passed, the next packet discarded up to its clean end), K28.5 inside an open packet with a clean end in the same beat (no discard), a second end marker between packets, a Fill after the first data character without an end (discarded, a further violation while discarding not reported); one event per violation, the following packets pass | NI-RX-03 |
| `test_rx_random` (TC-NI-06) | 300 random packets per VC: 0 to B + 1 leading Fills (sometimes up to 3 x B), 1 to 5 x B bytes, 10 % EEP, 5 % packets of zero length; random handshakes | NI-RX-01, NI-RX-02 |
| `test_throughput` (TC-NI-07) | Handshakes always ready: 20 packets of 4 x B bytes in 100 rows and 100 cycles (one row per cycle including the end marker rows); 20 received packets of 4 x B + 1 bytes (5 rows, 5 beats with a tail beat each) in at most 6 cycles per packet | NI-IF-03 |

The broadcast port, the schedule port and the packets between two cores are verified in the core testbench
(`ofb_core_tb`): NI-IF-02 and NI-RX-04 in TC-CORE-02 (broadcast messages with random channel, B_TYPE and DELAYED
flag), NI-SC-01 in TC-CORE-06 (a SCHEDULE.request at the Network interface sets the current time-slot of the Data Link
layer), the packet ports with 1, 2 and 4 lanes in TC-CORE-02 and TC-CORE-17, framing errors and the EEP flag of the user
through the MIB in TC-CORE-05, and the packets of zero length after an uncorrectable error in the input VC buffer in
TC-CORE-14.
