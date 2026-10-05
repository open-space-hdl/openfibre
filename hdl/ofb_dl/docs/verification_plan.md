# ofb_dl: Verification Plan

## 1. Overview

The Data Link layer is verified on two levels:

- A layer testbench with two complete ends (Data Link, Multi-Lane and Lane layers) connected through the behavioural
  Physical adapter model. It checks the end-to-end services: every packet and broadcast message arrives once, in order
  and unchanged, also after bit errors, loss of the lane and link reset.
- A row-level testbench with one `ofb_dl`, in which the testbench is the far end at the row interface. It injects
  arbitrary words (including wrong CRCs, wrong sequence numbers, RXERR and malformed frames) and checks every
  transmitted word, which the layer testbench cannot observe.

All checks observe ports only. Packets are random (length, EOP or EEP, gaps, receiver back-pressure) and checked with
UVVM scoreboards per VC.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_dl_tb` | `ofb_dl_th` | Two ends A and B, each `ofb_dl` (4 VCs) + `ofb_multilane` + `ofb_lane`, `ofb_tb_pa_model`; packet generator and receiver per VC (user clock 192 MHz, core clock 156.25 MHz), broadcast generator and receiver, scoreboard per destination |
| `ofb_dl_mac_tb` | none | `ofb_dl_mac` (4 VCs, Bandwidth Credit Limit 1024 words), inputs driven by the sequencer |
| `ofb_dl_row_tb` | `ofb_dl_row_th` | `ofb_dl` (2 VCs, input buffers of 128 words, error recovery buffer of 256 words, 8 data, 4 FCT, 2 broadcast items); far-end model: receive word queue, log of the transmitted words, optional automatic ACK of every frame and FCT in sequence, capability event in Check Far-End Reset |

Simulator: GHDL.

## 3. Test cases

### 3.1 Layer testbench (`ofb_dl_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link_init` (TC-DL-01) | Both ends reach Link Initialised, exchange FCTs for all VCs, error recovery buffers become empty, no error | DL-LR-01 to 03, DL-VI-02, DL-CR-01, DL-ER-02, DL-IF-04 |
| `test_vc_traffic` (TC-DL-02) | 30 random packets (up to 300 bytes, 10 % EEP) per VC in both directions with gaps and back-pressure: all delivered in order, no error | DL-IF-01, DL-VO-01, 03, 04, DL-MAC-01, DL-FA-01, DL-WI-02, DL-SR-01, DL-VI-01, DL-RE-02, DL-TS-01, DL-IF-03 |
| `test_broadcast` (TC-DL-03) | Broadcast messages with VC traffic in both directions, no LATE flag; a slow broadcast credit (2000 words) delays the messages | DL-IF-02, DL-BO-01, 02, DL-FA-02, DL-WI-03, DL-BI-01, DL-TS-02 |
| `test_flow_control` (TC-DL-04) | A receiver that does not read blocks its VC only: no credit left, other VCs continue, no overflow; all delivered after the receiver reads again | DL-CR-01, DL-VO-03, DL-VI-02, DL-VI-03, DL-MAC-01 |
| `test_error_recovery` (TC-DL-05) | 30 bit errors per direction during packet and broadcast traffic: NACK, RETRY and resend at both ends, every packet and message delivered once and in order, no protocol error, no link reset | DL-ER-01 to 03, DL-RE-01, 03, DL-TS-01, 02, 04, DL-SQ-01, 02 |
| `test_lane_loss` (TC-DL-06) | Cut of one direction for 5 us during traffic: the lanes initialise again, error recovery completes the transfer without link reset | DL-ER-03, DL-ER-06, DL-LR-03 |
| `test_link_reset` (TC-DL-07) | Link Reset at A: both ends reset (Far-End Link Reset at B only), initialise and transfer packets again | DL-LR-01 to 04, DL-ER-06, DL-IF-05, DL-ST-01 |

### 3.2 Row-level testbench (`ofb_dl_row_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_tx_idle_fct` (TC-DL-10) | FCTs after link reset (two per VC, sequence 1 to 4, multiplier 0, CRC-8), FULL with the current sequence number when the FCT items are full, idle frames: SIF with the current sequence number, 64 PRBS words of the ECSS sequence (seed 0xFFFF, Figure 5-43), continued over idle frames and paused by control words | DL-FA-03, 04, DL-SQ-01, 03, DL-TS-03, 06, DL-VI-02 |
| `test_ack_spacing` (TC-DL-11) | Six frames received back to back: data delivered, ACKs combined with at least 15 words between them, the last ACK with the Receive Sequence Number | DL-TS-05, DL-RE-02, DL-WI-02 |
| `test_rx_errors` (TC-DL-12) | RXERR in a data frame: NACK with positive polarity, Error Negative; a frame of negative polarity: ACK with negative polarity, Valid Negative; RXERR in an idle frame: no NACK; sequence error: NACK with negative polarity, Error Positive; CRC-16 error: NACK, frame discarded; CRC-8 error outside a frame: no NACK | DL-RE-01 to 03, DL-SR-01, 02, DL-WI-02, DL-IF-03, DL-ST-01 |
| `test_word_id` (TC-DL-13) | SDF inside a data frame: frame error, frame discarded; EDF and EBF in RxNothing ignored; broadcast frame and FCT inside a data frame, unknown control word ignored; data frame of 65 words and broadcast frame of one word: frame errors | DL-WI-01 to 04, DL-ST-01 |
| `test_crc8_vectors` (TC-DL-14) | ECSS Figure 5-46: FCT with CRC 0x4F accepted; broadcast frame with CRC 0x29 has a valid CRC (sequence error only), with a changed CRC a CRC-8 error | DL-SR-02, DL-SQ-03, DL-ST-01 |
| `test_retry` (TC-DL-15) | NACK with count 2 while FCTs, data frames and a broadcast frame are outstanding: RETRY, resend with new sequence numbers from 3 and negative polarity, broadcast frame first (with LATE), then FCTs, then data frames; the ACK of the last item empties the buffer | DL-ER-03, DL-SQ-02, DL-TS-01, 04, DL-BO-03, DL-ER-07, DL-SR-03 |
| `test_protocol_error` (TC-DL-16) | ACK equal to the previous count accepted; ACK outside the outstanding items: protocol error and link reset; ACK of the other polarity ignored | DL-ER-04, DL-ER-02, DL-LR-01, DL-SR-03, DL-ST-01 |
| `test_erb_full` (TC-DL-17) | Without ACKs: data stops when the buffer is full, FULL every 64 words; after the ACK of all items the rest is sent | DL-ER-05, DL-TS-06, DL-VO-04 |
| `test_vc_link_reset` (TC-DL-18) | Input side: the user read a partial packet, after link reset an EEP word is read first; output side: words written before link reset are flushed, the rest of the partial packet is discarded up to the EOP, the next packet is sent | DL-VO-02, DL-VI-04 |
| `test_credit` (TC-DL-19) | No data without credit; one FCT allows 64 words, a second one the rest; FCTs beyond the counter width raise the credit overflow | DL-CR-01, 02, DL-VO-03, 04, DL-ST-01 |
| `test_fct_return` (TC-DL-20) | Two FCTs per VC after link reset; after the user read 128 words exactly two more FCTs, no input buffer overflow | DL-VI-02 |

### 3.3 Medium access controller (`ofb_dl_mac_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_priority` (TC-QS-01) | Equal priority and credit: lowest VC; priority 0 wins; no grant without a ready VC | DL-QS-01, DL-QS-04, DL-MAC-01 |
| `test_bandwidth_credit` (TC-QS-02) | Within one priority level the VC that used less bandwidth wins | DL-QS-03, DL-QS-04 |
| `test_threshold` (TC-QS-03) | A high-priority VC that overuses its bandwidth falls below -0.9 B: over use reported, a lower-priority VC wins | DL-QS-04, DL-QS-05 |
| `test_schedule` (TC-QS-04) | Only VCs allocated to the current time-slot compete | DL-QS-02 |
| `test_bandwidth_zero` (TC-QS-05) | A VC with bandwidth zero does not compete | DL-QS-01, DL-QS-02 |
| `test_under_use` (TC-QS-06) | Credit at +B for the idle time limit: under use; ends with a segment | DL-QS-05 |
| `test_config_reset` (TC-QS-07) | Interface Reset clears the credits | DL-QS-03, DL-QS-07 |

### 3.4 Row-level testbench, quality of service and continuous mode

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_qos_priority_schedule` (TC-DL-21) | Both VCs excluded from time-slot 1: no data; SCHEDULE.request to slot 0: both ready at once, all frames of the priority-0 VC first | DL-QS-01, 02, 04, 06, DL-MAC-01, DL-IF-05 |
| `test_continuous_mode` (TC-DL-22) | Continuous mode: 140 words for a buffer of 128 without credit are accepted without back-pressure; flush, EEP, rest of the packet discarded; without an active lane the next packet is flushed as well | DL-CM-01 |
| `test_seq_error_pair` (TC-DL-26) | Frame 2 lost: the EDF of frame 3 and a SIF with its sequence number in consecutive cycles, both with positive polarity: two sequence errors, Error Negative (one error recovery), every NACK with positive polarity | DL-RE-01, DL-RE-03 |
| `test_full_after_rxerr` (TC-DL-23) | RXERR with an empty error recovery buffer: no FULL; RXERR while a data frame waits for acknowledgement and nothing else is to be sent: FULL with the current sequence number | DL-TS-06 |
| `test_bc_input_discard` (TC-DL-24) | Six broadcast frames while the user does not read: four messages buffered, two discarded and counted; the four are delivered afterwards | DL-BI-01 |
| `test_link_reset_frame` (TC-DL-25) | Link Reset while a data frame of 60 words is sent: the frame is stopped (no EDF), the packet is flushed, the first idle frame after the link reset carries 64 PRBS words from the seed | DL-FA-05 |

### 3.5 Rows of several words (core testbench)

The Data Link layer with rows of 2 and 4 words is verified end to end in the core testbench (`ofb_core_tb`,
configurations `lanes2` and `lanes4`), where both ends are complete cores with the Multi-Lane layer; the testbenches
of this module keep one lane.

| Test ID | Description | Requirements |
| --- | --- | --- |
| TC-CORE-02 (`lanes2`, `lanes4`) | Traffic on 4 VCs and broadcast messages: data rows from the beats, replicated rows, FCT multiplier and segment of 64 x N words, received rows packed by the Multi-Lane layer, banked input VC buffer and beats that end at the end of a packet | DL-RW-01, DL-RW-03 to 06, DL-VO-03, DL-VO-04, DL-VI-01, DL-VI-02, DL-IF-03 |
| TC-CORE-03, TC-CORE-07 (`lanes2`, `lanes4`) | Error recovery with rows: bit errors, lane failure and realignment, resend of data rows | DL-ER-03, DL-RW-01 |
| TC-CORE-08 (`lanes2`, `lanes4`) | Maximum number of data-sending lanes 1, taken over at link reset: segments and FCTs of 64 words, received rows of one word | DL-RW-02, DL-RW-03, DL-RW-05 |
| TC-CORE-04 (`lanes2`, `lanes4`) | Link reset with the banked input VC buffer (EEP after link reset, FCTs for the whole buffer) | DL-VI-02, DL-VI-04 |

## 4. Coverage analysis

Every requirement of the specification is covered by at least one test case (checked by `tools/compliance.py`); the
rows of several words (section 2.14) are covered by the core testbench (section 3.5). The Interface Reset values of
the QoS parameters (DL-QS-07) are checked in the MIB (TC-MG-05) and in the medium access controller (TC-QS-07). The
configuration reset output of DC-1 is checked with the MIB (Interface Reset, TC-MG-05 and TC-MG-06).
