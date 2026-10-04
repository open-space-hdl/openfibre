# ofb_dl: Specification

## 1. Overview

`ofb_dl` is the Data Link layer of OpenFibre (ECSS-E-ST-50-11C clause 5.7). It transfers the N-Chars of up to 32
virtual channels and broadcast messages over the link in frames, controls the flow of every virtual channel with FCTs,
recovers from errors with ACK, NACK and RETRY, and resets the link with the far end.

The module consists of the blocks of the architecture (sections 7.2 and 7.3):

| Block | Entity | Function |
| --- | --- | --- |
| DT-1, DT-2 | `ofb_dl_vc_out` (x `NumVc_g`) | Output VC buffer, FCT credit counter |
| DT-3 | `ofb_dl_bc_out` | Broadcast output buffer, broadcast bandwidth credit |
| DT-4 to DT-6, DT-8 | `ofb_dl_tx_frame` | Medium access, transmit scheduler (precedence), frame assembly, sequence numbers and CRC-8 |
| DT-7 | `ofb_dl_erb` | Error recovery buffer, ACK and NACK processing |
| DR-1, DR-2, DR-4 | `ofb_dl_rx_check` | Data word identification, CRC-8 and sequence checks, decoding of control words |
| DR-3 | `ofb_dl_rx_err` | Receive error state machine, ACK and NACK requests |
| DR-5 | `ofb_dl_rx_buf` | Frame buffer: commit or drop of received data frames, distribution to the input VC buffers |
| DR-6 | `ofb_dl_vc_in` (x `NumVc_g`) | Input VC buffer, FCT requests |
| DR-7 | `ofb_dl_bc_in` | Broadcast input buffer |
| DC-1 | `ofb_dl_link_reset` | Link reset state machine |
| DC-2 | in `ofb_dl` | Status and event outputs for the MIB |

This issue covers phase 2 of the roadmap: one lane (`NumLanes_g = 1`, rows of one word, FCT multiplier and data
segment multiplier 1), up to 32 virtual channels with round-robin medium access. The quality of service mechanisms of
ECSS 5.7.4.2 to 5.7.4.7 (priority, bandwidth reservation, schedule) and the continuous mode of ECSS 5.7.2.2h, i follow
in phase 3; their requirements are listed in section 2.13 and marked as such.

Clock domains: the user side of the VC and broadcast buffers runs on `UserClk`, everything else on `Clk` (the core
clock). The rows to and from the Multi-Lane layer are on `Clk`; the crossing to the lane clock is in the core top
level.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-IF-01 | For every VC the Data Link layer shall accept words of four N-Chars or Fills (32 bits, one K flag per character) from the Network layer with a valid / ready handshake on `UserClk`, and pass received words to the Network layer with a valid / ready handshake. | 5.7.1b, c, 5.7.2.1 |
| DL-IF-02 | The Data Link layer shall accept broadcast messages (8 data bytes, broadcast channel, B_TYPE, DELAYED flag) with a valid / ready handshake and pass received broadcast messages (with DELAYED and LATE flags) with a valid strobe on `UserClk`. | 5.7.1b, c, 5.3.8.4 |
| DL-IF-03 | The Data Link layer shall pass rows to the Multi-Lane layer with a valid / ready handshake and receive rows with a valid strobe and a CRC-16 error flag, as defined by the interface of `ofb_multilane`. | 5.7.1e, f |
| DL-IF-04 | The Data Link layer shall drive link reset, LaneReset and the near-end capability (INIT3LinkResetFlag, DataScrambled) of the Multi-Lane layer, and use its far-end capability event and its lane active indication. | 5.7.1g to i |
| DL-IF-05 | The Data Link layer shall accept the management parameters DataScrambled, Link Reset, Interface Reset and the per-VC parameters, and provide the status of Table 5-37 for the Data Link layer as levels and one-cycle events. | 5.7.1j, k, 5.9.3, 5.9.4 |

### 2.2 Output VC buffer and flow control (DT-1, DT-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-VO-01 | Every VC shall have an output VC buffer of `VcOutDepth_g` words (at least 64 words, 256 N-Chars), which accepts words while it is not full and keeps their order. | 5.7.2.2a to f |
| DL-VO-02 | On link reset the output VC buffer shall be flushed; if the last character written by the Network layer was not an EOP, EEP or Fill, all new words shall be discarded up to and including the next word with an EOP or EEP. | 5.7.2.2g, 5.7.10a.1 to 3 |
| DL-VO-03 | The output VC buffer shall indicate a data segment ready when its FCT credit counter is greater than zero and it contains 64 words, a word with an EOP or EEP, or is full. | 5.7.3.1b |
| DL-VO-04 | A data segment shall have at most `min(64, credit, words in the buffer, free words of the error recovery buffer)` words, so that the input VC buffer at the far end has room for it. | 5.7.3.1d, 5.7.4.1c, 5.3.8.2c |
| DL-CR-01 | Every VC shall have an FCT credit counter of `CreditWidth_g` bits (at least four FCTs) that is increased by M x 64 words for every received FCT of the VC, decreased by the words sent, set to zero on link reset and not changed on LaneReset. | 5.7.3.1a, e to h, j, k |
| DL-CR-02 | An FCT that would overflow the credit counter shall leave it unchanged at its maximum value and raise the credit overflow status of the VC. | 5.7.3.1i |

### 2.3 Broadcast output and broadcast flow control (DT-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-BO-01 | Broadcast messages shall be buffered in a broadcast output buffer of `BcOutDepth_g` messages. | 5.7.1b |
| DL-BO-02 | A Broadcast Bandwidth Credit Counter shall be decreased by one for every broadcast frame sent and increased by one after each interval of 4 / (Normalised Expected Broadcast Bandwidth) words, saturate at 256, never be negative, and be set to zero on link reset; no broadcast frame shall be sent while it is zero. | 5.7.5a to k |
| DL-BO-03 | A broadcast message that cannot be sent immediately because no lane is active or because of error recovery shall be sent with the LATE flag set; the DELAYED flag shall be passed from the Network layer unchanged. | 5.3.8.4i, j, 5.3.5.1.6c |

### 2.4 Medium access (DT-4, phase 2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-MAC-01 | Only VCs with a data segment ready (DL-VO-03) shall compete for sending the next data segment; the competing VCs shall be served in round-robin order. | 5.7.4.1a to d |

### 2.5 Transmit scheduling and frames (DT-5, DT-6)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-TS-01 | The words of the Data Link layer shall be sent in the precedence order RETRY, broadcast frame to be resent, broadcast frame, ACK or NACK, FCT to be resent, FCT, FULL, data frame to be resent, data frame, idle frame. | 5.3.10c6 to c15 |
| DL-TS-02 | A RETRY shall be able to interrupt a broadcast, data or idle frame; a broadcast frame shall be able to be inserted within a data frame; ACK, NACK, FCT and FULL shall be able to be inserted within a data or idle frame. A frame that is interrupted by a RETRY is not completed. | 5.3.10i to n |
| DL-TS-03 | An idle frame shall be sent only when there is no data frame, broadcast frame or control word to send; it shall end on a word boundary as soon as a data or broadcast frame is to be sent and after 64 PRBS words. | 5.3.10o, 5.3.8.3j to l, 5.7.6.6a |
| DL-TS-04 | While broadcast frames of the error recovery buffer are resent no new broadcast frame shall be sent; while broadcast frames or FCTs are resent no new FCT; while broadcast frames, FCTs or data frames are resent no new data frame. | 5.3.10q to s, 5.7.7.1e |
| DL-TS-05 | An ACK shall be sent as soon as possible after it is requested, with at least 15 words between two ACKs; a pending ACK or NACK is replaced by a newer request of the other kind. | 5.7.7.2.1b to f, 5.7.7.2.2c, e |
| DL-TS-06 | A FULL shall be sent when the error recovery buffer becomes full and every 64 words while it stays full; a FULL shall also be sent after an RXERR or a CRC error when all output VC buffers are empty, nothing else is to be sent and the error recovery buffer is not empty. | 5.7.7.1q to s |
| DL-FA-01 | A data segment shall be sent as a data frame: SDF with the VC number, the data words, EDF with the sequence number (the CRC-16 field is filled by the Multi-Lane layer). | 5.7.6.1a, 5.3.5.1.3, 5.3.5.1.4, 5.3.8.2 |
| DL-FA-02 | A broadcast message shall be sent as a broadcast frame: SBF with broadcast channel and B_TYPE, two data words, EBF with STATUS (DELAYED, LATE), sequence number and CRC-8. | 5.7.6.1b, 5.3.5.1.5, 5.3.5.1.6, 5.3.8.4 |
| DL-FA-03 | An idle frame shall consist of an SIF with the current sequence number and CRC-8, followed by PRBS words of the ECSS generator (seed 0xFFFF after link reset, continued from one idle frame to the next, paused while control words are embedded). | 5.7.6.2.3, 5.7.6.6, 5.3.5.1.7, 5.3.8.3 |
| DL-FA-04 | FCT, ACK, NACK, FULL and RETRY shall be built as specified, FCT with the multiplier M - 1 and the VC number. | 5.3.5.2, 5.3.5.3 |
| DL-FA-05 | On link reset, the frame being sent shall be stopped and the idle frame PRBS generator set to its seed. | 5.7.6.1c, 5.7.10b.1, b.3 |

### 2.6 Sequence numbers and CRC-8 on transmission (DT-8)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-SQ-01 | A 7-bit Transmit Sequence Counter (modulo 128) and a Transmit Polarity Flag shall be kept; immediately before an EDF, EBF or FCT is passed on, the counter shall be incremented and the new value with the flag placed in its SEQ_NUM; SIF and FULL carry the current value. | 5.7.6.3.1a to c, g to i, 5.3.5.1.2 |
| DL-SQ-02 | On link reset the counter and the flag shall be cleared. When a valid NACK is processed the counter shall be set to the sequence count of the NACK before the RETRY is sent, and the flag inverted after the RETRY. | 5.7.6.3.1d to f, 5.7.7.2.4c.2 to 4 |
| DL-SQ-03 | The CRC-8 (x^8 + x^2 + x + 1, seed 0) of SIF, FCT, ACK, NACK and FULL shall cover their first three characters; the CRC-8 of a broadcast frame shall cover the SBF, the two data words and the first three characters of the EBF. | 5.7.6.5 |

### 2.7 Error recovery buffer (DT-7)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-ER-01 | Data segments, FCTs and broadcast messages shall be stored in the error recovery buffer when they are sent, referenced by their sequence number, with room for at least one FCT and one broadcast message regardless of the data stored. | 5.7.7.1a to d |
| DL-ER-02 | A valid ACK (CRC-8 correct, polarity equal to the Transmit Polarity Flag) shall delete all items sent with a sequence count less than or equal to its sequence count (modulo 128). | 5.7.7.2.3a to c |
| DL-ER-03 | A valid NACK shall delete the items up to its sequence count, set the Transmit Sequence Counter to its count, cause a RETRY, invert the polarity and resend the remaining items with new sequence numbers: broadcast frames first, then FCTs, then data frames, each in their original order. A NACK with the other polarity shall be ignored. | 5.7.7.2.4a to d, 5.7.7.1e, g |
| DL-ER-04 | A valid ACK or NACK with a sequence count different from that of the previous valid ACK or NACK and no item with that count in the buffer shall cause a link reset and raise the Link Reset Caused by Protocol Error status. | 5.7.7.2.3d, 5.7.7.2.4e |
| DL-ER-05 | The error recovery buffer shall be full when it cannot store an item of a kind (data word, FCT, broadcast message) or 127 items are waiting for acknowledgement; no new item of that kind shall then be accepted. | 5.7.7.1n, o |
| DL-ER-06 | On link reset the error recovery buffer shall be emptied; on LaneReset it shall not. | 5.7.7.1h, i, 5.7.10b.8 |
| DL-ER-07 | The number of error recovery attempts (RETRYs sent) shall be counted, reported, and cleared by reset, interface reset or the MIB. The empty state of the buffer shall be reported. | 5.7.7.1j to l, Table 5-37 |

### 2.8 Data word identification and frame checks (DR-1, DR-2, DR-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-WI-01 | The data word identification state machine shall implement RxNothing, RxDataFrame, RxBroadcastFrame, RxBroadcast&DataFrame and RxIdleFrame with the transitions, word counters, maximum lengths (data and idle frame 64 words, broadcast frame 2 words) and frame error conditions of the standard, evaluated in the order given; FCT, ACK, NACK, FULL and RETRY shall be accepted in any state, unknown control words ignored. | 5.7.8 |
| DL-WI-02 | A data frame shall be accepted when its EDF arrives in RxDataFrame with a correct CRC-16 (from the Multi-Lane layer) and a correct sequence number; its data segment shall then be written into the input VC buffer of its VC. Otherwise it shall be discarded. | 5.7.6.7a, b |
| DL-WI-03 | A broadcast frame shall be accepted when its EBF has a correct CRC-8 and sequence number and the frame has two data words; the message shall then be passed to the broadcast input buffer. | 5.7.6.7c, d |
| DL-WI-04 | An FCT with correct CRC-8 and sequence number shall be passed to the credit counter of its VC. | 5.7.6.7e, f |
| DL-SR-01 | A 7-bit Receive Sequence Counter shall be kept, cleared on link reset and not changed on LaneReset; EDF, EBF and FCT shall be in sequence when their count is the counter plus one and their polarity equals the Receive Polarity Flag, SIF and FULL when their count equals the counter and the polarity matches. An accepted data frame, broadcast frame or FCT shall increment the counter; a frame or FCT out of sequence shall be discarded. | 5.7.6.3.2, 5.3.5.1.2 |
| DL-SR-02 | The CRC-8 of received SIF, FCT, ACK, NACK, FULL and broadcast frames shall be checked; a word with a CRC error shall not be acted upon. | 5.7.6.5g to j |
| DL-SR-03 | Valid ACKs and NACKs (CRC-8 correct) shall be passed to the error recovery buffer with their sequence number. | 5.7.7.2.3a, 5.7.7.2.4a |

### 2.9 Receive errors, ACK and NACK requests (DR-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-RE-01 | The receive error state machine shall implement Valid Positive, Valid Negative, Error Positive and Error Negative with the transitions of the standard and determine the Receive Polarity Flag; it shall enter Valid Positive on link reset. | 5.7.7.3 |
| DL-RE-02 | An ACK shall be requested when a data frame, broadcast frame, FCT or FULL is received without sequence or CRC error. ACKs carry the Receive Sequence Counter and the Receive Polarity Flag. | 5.7.7.2.1a, e |
| DL-RE-03 | A NACK shall be requested when an RXERR or a CRC error occurs while the data word identification state machine is in RxDataFrame, RxBroadcastFrame or RxBroadcast&DataFrame, or when a sequence error is detected in a control word with a valid CRC; not for unknown control words. NACKs carry the Receive Sequence Counter and the inverse of the Receive Polarity Flag. | 5.7.7.2.2a, b, d, 5.7.7.3 |

### 2.10 Frame buffer and input VC buffers (DR-5, DR-6, DR-7)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-VI-01 | Every VC shall have an input VC buffer of `VcInDepth_g` words (at least 64 words) on `UserClk`, which keeps the order of the received N-Chars and Fills. | 5.7.2.3a, b, 5.3.7.2d |
| DL-VI-02 | After link reset an input VC buffer shall request one FCT for every 64 words of space, and one further FCT every time the Network layer has read 64 words; FCT requests of several VCs shall be served in round-robin order. | 5.7.3.2b to d |
| DL-VI-03 | A word received for a full input VC buffer is an overflow: the link shall be reset and the input buffer overflow status of the VC raised. | 5.7.3.2e |
| DL-VI-04 | On link reset the input VC buffers shall be flushed; if the last character read by the Network layer was not an EOP, EEP or Fill, an EEP shall be the next character read. | 5.7.2.3d, 5.7.10a.4 to 7 |
| DL-BI-01 | Accepted broadcast messages shall be passed to the Network layer through a broadcast input buffer of `BcInDepth_g` messages; a message that finds the buffer full shall be discarded and counted. | 5.7.6.7c |

### 2.11 Link reset (DC-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-LR-01 | The link reset state machine shall implement Configuration Reset, Near-End Reset, Check Far-End Reset and Link Initialised with the transitions of the standard; reset and Interface Reset lead to Configuration Reset, the Link Reset parameter, a protocol error and an input buffer overflow to Near-End Reset. | 5.7.9.1 to 5.7.9.5 |
| DL-LR-02 | In Near-End Reset link reset and LaneReset of all lanes shall be asserted for one cycle; in Check Far-End Reset the INIT3LinkResetFlag of the near-end capability shall be 1, in Link Initialised 0. | 5.7.9.3b, 5.7.9.4b, 5.7.9.5b |
| DL-LR-03 | The far-end capability shall be used as an event (not as a stored level): Check Far-End Reset moves to Link Initialised, and Link Initialised to Near-End Reset when no lane is active, on a capability event with INIT3LinkResetFlag set; the latter raises the Far-End Link Reset status. | 5.7.9.4c, 5.7.9.5c, Table 5-37 |
| DL-LR-04 | Link reset shall perform the actions of 5.7.10b in all Data Link blocks: frame stopped, broadcast credit zero, PRBS seed, sequence counters and polarity flags cleared, error recovery buffer emptied, data word identification in RxNothing. | 5.7.10b |

### 2.12 Status (DC-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-ST-01 | The Data Link layer shall report, per VC, Has Credit, input buffer overflow and FCT credit counter overflow, and for the link 16-bit CRC error, frame error, CRC-8 error, sequence error, error recovery buffer empty, number of error recovery attempts, Link Reset Caused by Protocol Error and Far-End Link Reset; errors are one-cycle events, the MIB keeps them until read. | Table 5-37 |

### 2.13 Phase 3 (not in this issue)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-P3-01 | Priority, bandwidth reservation and scheduled QoS with precedence = priority precedence + bandwidth credit, bandwidth over / under use status. | 5.7.4.2 to 5.7.4.7 |
| DL-P3-02 | Continuous mode per VC. | 5.7.2.2h, i |

## 3. Error conditions

| Condition | Reaction |
| --- | --- |
| CRC error, RXERR inside a frame | Frame discarded, NACK (DL-RE-03), status |
| Sequence error | Frame or FCT discarded, NACK, status |
| Frame error (data word identification) | Frame discarded, status |
| ACK or NACK with an inconsistent sequence count | Link reset, status (DL-ER-04) |
| Input VC buffer overflow | Link reset, status (DL-VI-03) |
| FCT credit counter overflow | Counter saturated, status (DL-CR-02) |
| Broadcast input buffer full | Message discarded, counted (DL-BI-01) |

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (phase 2: 1) |
| `VcOutDepth_g` | 128 | Output VC buffer, words |
| `VcInDepth_g` | 256 | Input VC buffer, words (multiple of 64) |
| `BcOutDepth_g`, `BcInDepth_g` | 4 | Broadcast buffers, messages |
| `ErbWords_g` | 512 | Error recovery buffer, data words |
| `ErbDataItems_g`, `ErbFctItems_g`, `ErbBcItems_g` | 32, 16, 4 | Error recovery buffer, items per kind (sum below 128) |
| `CreditWidth_g` | 12 | FCT credit counter width (words) |

## 5. Interpretation of the standard

| Topic | Interpretation |
| --- | --- |
| FCT credit and segment size (5.7.3.1b, 5.7.4.1c) | A VC competes when its credit is greater than zero; the segment is limited to the credit, so the far-end buffer always has room |
| FULL (5.7.7.1n to q) | The error recovery buffer is managed per kind of item; a kind that has no room blocks only new items of that kind, and FULL is sent (note 2 of 5.7.7.1q). Resending stored items is always allowed |
| Frame interrupted by RETRY | A data frame read in part is kept in the error recovery buffer with the words read so far and resent as a shorter segment; the rest stays in the output VC buffer |
| Frame error | Not a NACK condition by itself (5.7.7.2.2a); the missing frame is detected by the sequence number of the next frame, SIF or FULL |
| NACK polarity | NACKs carry the inverse of the Receive Polarity Flag (notes of 5.7.7.3.2c to 5.7.7.3.5b) |
