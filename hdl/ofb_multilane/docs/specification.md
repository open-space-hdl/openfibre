# ofb_multilane: Specification

## 1. Overview

`ofb_multilane` is the Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6). It sits between the Data Link
layer and the Lane layers, distributes the rows of the Data Link layer over the lanes, collects the received words
into rows, computes the data frame CRC-16 and the data scrambling per lane, and controls the lanes.

The module consists of six blocks of the architecture (section 7.4):

| Block | Entity | Function | State |
| --- | --- | --- | --- |
| ML-1 | `ofb_ml_lane_mgr` | Lane manager: lane control, capability exchange, status | Single lane (bypass) |
| ML-2 | in `ofb_multilane` | Row distributor | Bypass only (one lane) |
| ML-3 | `ofb_ml_col_enc` | Column encoder: data scrambling and CRC-16 of one lane | Complete |
| ML-4 | `ofb_ml_col_dec` | Column decoder: unscrambling and CRC-16 check of one lane | Complete |
| ML-5 | none | Lane alignment | Phase 4 |
| ML-6 | in `ofb_multilane` | Row concentrator | Bypass only (one lane) |

This issue of the specification covers phase 2 of the roadmap: `NumLanes_g = 1`, the Multi-Lane bypass of ECSS 5.6.3
and the complete column codec. The requirements of the multi-lane functions (rows over 2 to 4 lanes, PAD, ACTIVE and
ALIGN, alignment, asymmetric links, unidirectional and hot redundant lanes) are added in phase 4. The column codec is
already written for the multi-lane case: it excludes PAD words and handles every lane independently.

All blocks run in the lane clock domain (`Clk` = `LaneClk`, one word per lane per clock cycle). The crossing to the
Data Link clock domain is outside this module (core top level).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-IF-01 | The Multi-Lane layer shall accept transmit rows from the Data Link layer with a valid / ready handshake: `NumLanes_g` words of 32 bits with 4 K flags, a word mask and a replicate flag (word 0 to be replicated over all data-sending lanes). | 5.6.1c, 5.6.4.1 |
| ML-IF-02 | The Multi-Lane layer shall pass received rows to the Data Link layer with a valid strobe and no back-pressure: `NumLanes_g` words, a word mask and a CRC error flag that is valid with an EDF. | 5.6.1d |
| ML-IF-03 | The Multi-Lane layer shall pass words to each Lane layer with a valid / ready handshake and receive words from each Lane layer with a valid strobe. | 5.6.1e, f |
| ML-IF-04 | The Multi-Lane layer shall drive LaneReset, TxOnly, RxOnly, FarEndActive and the near-end capability of each lane and use the lane state and the far-end capability of each lane. | 5.6.1g to o |
| ML-IF-05 | The Multi-Lane layer shall accept LaneReset of all lanes, link reset and the near-end capability from the Data Link layer, and report the far-end capability (event and value) and whether a lane is active to the Data Link layer. | 5.6.1l, m, Figure 5-31 |
| ML-IF-06 | The Multi-Lane layer shall report the data-sending lanes, the data-receiving lanes and the alignment state. | 5.6.1q |

### 2.2 Lane manager (ML-1), single lane

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-LM-01 | With one lane, FarEndActive, TxOnly and RxOnly shall be de-asserted. | 5.6.1i (note), 5.6.3 |
| ML-LM-02 | LaneReset of the lane shall follow the LaneReset request of the Data Link layer. | 5.6.1j, 5.7.9.3b.2 |
| ML-LM-03 | The near-end capability of the Data Link layer shall be passed to the lane and held constant while the lane is in Connected, so that all INIT3 words of one initialisation carry the same value; the MultiLane bit shall be 0 with one lane. | 5.6.1n, 5.3.3.8e, 5.7.9 |
| ML-LM-04 | The far-end capability event and value of the lane shall be passed to the Data Link layer. | 5.6.1m, o |
| ML-LM-05 | The scramble enable of the transmitter shall be the DataScrambled bit of the near-end capability, held constant while the lane is Active, so that it is the value the far end received in INIT3. The unscramble enable of the receiver shall be the INIT3DataScrambled bit of the far-end capability. | 5.7.6.2.1a, 5.7.6.2.2a |
| ML-LM-06 | With one lane, the lane shall be data-sending and data-receiving and the alignment state Both-Ends Ready while it is Active; otherwise no lane shall be data-sending or data-receiving and the alignment state shall be Not Ready. | 5.6.1q, 5.6.3 |

### 2.3 Bypass (ML-2, ML-6), single lane

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-BP-01 | With one lane, every row (one word) shall be passed to the lane through the column encoder. | 5.6.3, 5.6.4.1c |
| ML-BP-02 | With one lane, every word received from the lane shall be passed to the Data Link layer through the column decoder, except the Multi-Lane control words PAD, ACTIVE and ALIGN, which shall be discarded. | 5.6.3, 5.6.1d |
| ML-BP-03 | On link reset, a transmit word held in the Multi-Lane layer shall be discarded. | 5.7.10b.1 |

### 2.4 Column encoder (ML-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-ENC-01 | The column encoder shall identify the words of a data frame: from an SDF to the following EDF, without the words of a broadcast frame (SBF to EBF) inside the data frame, Data Link control words and PAD words. An SIF, a RETRY or an RXERR ends the data frame. | 5.7.8, 5.6.4.2f |
| ML-ENC-02 | When scrambling is enabled, the data characters of the data words of a data frame shall be XORed with the ECSS random number sequence (G(x) = x^16 + x^5 + x^4 + x^3 + 1, seed 0xFFFF, least significant bit of character 0 first). EOP, EEP and Fill characters (K flag set) shall not be scrambled, but the sequence shall advance over them. The sequence shall only advance over data words of a data frame. | 5.7.6.2.1a to g |
| ML-ENC-03 | The scrambler shall be re-seeded at every SDF. | 5.7.6.2.1d |
| ML-ENC-04 | The CRC-16 (x^16 + x^12 + x^5 + 1, seed 0xFFFF, least significant bit of character 0 first, data value of K-codes) shall be computed over the SDF, the data words of the data frame after scrambling and characters 0 and 1 of the EDF (EDF code and sequence number), and placed into characters 2 (CRC_LS) and 3 (CRC_MS) of the EDF. | 5.7.6.4b to h, 5.6.4.2d, e, g |
| ML-ENC-05 | PAD words shall neither be scrambled nor included in the CRC-16. | 5.6.4.2f |
| ML-ENC-06 | All words that are not data words of a data frame shall pass unchanged; an EDF that does not end a data frame shall pass unchanged. | 5.7.6.2.1e (note) |
| ML-ENC-07 | The column encoder shall pass words in order with a valid / ready handshake on both sides and lose or duplicate no word under back-pressure. | 5.6.1e |

### 2.5 Column decoder (ML-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-DEC-01 | The column decoder shall identify the words of a data frame as in ML-ENC-01. | 5.7.8 |
| ML-DEC-02 | When unscrambling is enabled, the data characters of the data words of a data frame shall be XORed with the scrambling sequence of ML-ENC-02, re-seeded at every SDF; EOP, EEP and Fill characters shall not be unscrambled. | 5.7.6.2.2a, b |
| ML-DEC-03 | The CRC-16 of ML-ENC-04 shall be computed over the received (scrambled) words and compared with the CRC field of the EDF; the result shall be passed with the EDF as a CRC error flag. An EDF that does not end a data frame shall be flagged as a CRC error. | 5.7.6.4, 5.6.4.2d, h |
| ML-DEC-04 | PAD words shall be excluded from the CRC-16 and from unscrambling. | 5.6.4.2f |
| ML-DEC-05 | The column decoder shall pass every received word, in order and with a fixed latency. | 5.6.1d |

## 3. Error conditions

| Condition | Reaction |
| --- | --- |
| CRC-16 mismatch of a data frame column | CRC error flag with the EDF (ML-DEC-03); the Data Link layer discards the frame |
| EDF without SDF | Passed with the CRC error flag set (ML-DEC-03) |
| RXERR, RETRY or SIF inside a data frame | Data frame ended in the column codec (ML-ENC-01, ML-DEC-01); the Data Link layer handles the error |

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumLanes_g` | 1 | Number of lanes (phase 2: 1 only) |

## 5. Interpretation of the standard

Clause 5.7.6.4b defines the CRC-16 over "an entire data frame, from and including the comma in the SDF up to and
including the Sequence Number in the EDF". Data Link control words (FCT, ACK, NACK, FULL) and broadcast frames sent
inside a data frame are not part of the data frame: they carry their own CRC-8, and the note of 5.7.6.2.1e states for
scrambling that the random number generator only runs for the data of the data frame when an FCT is interleaved. The
column codec therefore excludes them from the CRC-16 and from scrambling. This interpretation is checked against
STAR-Dundee equipment in the lab test of phase 2.
