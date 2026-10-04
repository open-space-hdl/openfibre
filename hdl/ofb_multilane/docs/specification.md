# ofb_multilane: Specification

## 1. Overview

`ofb_multilane` is the Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6). It sits between the Data Link
layer and the Lane layers, distributes the rows of the Data Link layer over the lanes, collects the received words
into rows, computes the data frame CRC-16 and the data scrambling per lane, and controls the lanes.

The module consists of six blocks of the architecture (section 7.4):

| Block | Entity | Function | State |
| --- | --- | --- | --- |
| ML-1 | `ofb_ml_lane_mgr` | Lane manager: lane control, unidirectional and hot redundant lanes, capability exchange, status | Complete |
| ML-2 | `ofb_ml_tx` | Row distributor: rows over the data-sending lanes, PAD, ACTIVE, ALIGN, IDLE, SKIP | Complete |
| ML-3 | `ofb_ml_col_enc` | Column encoder: data scrambling and CRC-16 of one lane | Complete |
| ML-4 | `ofb_ml_col_dec` | Column decoder: unscrambling and CRC-16 check of one lane | Complete |
| ML-5 | `ofb_ml_align` | Lane alignment: alignment FIFOs, ACTIVE and ALIGN reception, alignment state machine | Complete |
| ML-6 | `ofb_ml_rx` | Row concentrator: valid and invalid rows, one control word per row, rows to the Data Link layer | Complete |

Issue 1 of this specification (phase 2 of the roadmap) covered `NumLanes_g = 1`: the Multi-Lane bypass of ECSS 5.6.3
and the complete column codec. This issue (phase 4) adds the multi-lane functions for 2 to 4 lanes (rows, PAD, ACTIVE
and ALIGN, alignment, asymmetric links, unidirectional and hot redundant lanes). With `NumLanes_g = 1` the Multi-Lane
layer is the bypass of issue 1; with more lanes the bypass is selected at run time (section 2.6).

All blocks run in the lane clock domain (`Clk` = `LaneClk`, one word per lane per clock cycle). The crossing to the
Data Link clock domain is outside this module (core top level).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-IF-01 | The Multi-Lane layer shall accept transmit rows from the Data Link layer with a valid / ready handshake: `NumLanes_g` words of 32 bits with 4 K flags, a word mask and a replicate flag (word 0 to be replicated over all data-sending lanes). The row width is fixed; the number of data-sending lanes may be smaller. | 5.6.1c, 5.6.4.1 |
| ML-IF-02 | The Multi-Lane layer shall pass received rows to the Data Link layer with a valid strobe and no back-pressure: `NumLanes_g` words, a word mask and a CRC error flag that is valid with an EDF. A row holds either data words (word 0 upwards, mask) or one control word (word 0). | 5.6.1d |
| ML-IF-03 | The Multi-Lane layer shall pass words to each Lane layer with a valid / ready handshake and receive words from each Lane layer with a valid strobe. | 5.6.1e, f |
| ML-IF-04 | The Multi-Lane layer shall drive LaneReset, TxOnly, RxOnly, FarEndActive and the near-end capability of each lane and use the lane state and the far-end capability of each lane. | 5.6.1g to o |
| ML-IF-05 | The Multi-Lane layer shall accept LaneReset of all lanes, link reset and the near-end capability from the Data Link layer, and report the far-end capability (event and value) and whether a lane is active to the Data Link layer. | 5.6.1l, m, Figure 5-31 |
| ML-IF-06 | The Multi-Lane layer shall report the data-sending lanes, the data-receiving lanes and the alignment state. | 5.6.1q |
| ML-IF-07 | The Multi-Lane layer shall accept the management parameters TxEn and RxEn per lane, the maximum number of data-sending lanes and the Multi-Lane bypass. | 5.6.1p, 5.6.3a, 5.6.8c, Table 5-36 |
| ML-IF-08 | The Multi-Lane layer shall request a SKIP from all Lane layers in the same clock cycle. | 5.6.4.5a |

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

### 2.6 Lane manager (ML-1), multi-lane

`N` is `NumLanes_g`. A lane is _active_ when its Lane layer is in the Active state. _Active transmitting lanes_ are
active lanes with TxEn set; _active receiving lanes_ are active lanes with RxEn set.

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-LM-07 | The Multi-Lane layer shall operate in bypass mode, using lane 0 only as in sections 2.2 and 2.3, when `N = 1`, when the Bypass parameter is set, or when the last INIT3 capability received on lane 0 has the Multi-LaneCapable bit clear. The other lanes shall then be held in LaneReset. | 5.6.3a, 5.3.3.8i |
| ML-LM-08 | The Multi-LaneCapable bit of the near-end capability shall be set on every lane when `N > 1` and the Bypass parameter is clear. | 5.3.3.8i |
| ML-LM-09 | TxOnly(L) shall be asserted when TxEn(L) = 1, RxEn(L) = 0 and lane L is not in ClearLine, and de-asserted otherwise. | 5.6.9.3 |
| ML-LM-10 | RxOnly(L) shall be asserted when TxEn(L) = 0, RxEn(L) = 1 and at least one bidirectional lane (TxEn = RxEn = 1) is active, and de-asserted when TxEn(L) = 1 or RxEn(L) = 0. | 5.6.9.4 |
| ML-LM-11 | FarEndActive(L) shall be set by a valid ACTIVE word with bit L set, cleared by a valid ACTIVE word with bit L clear and cleared while lane L is in ClearLine. | 5.6.9.2 |
| ML-LM-12 | LaneReset(L) shall be asserted on the LaneReset request of the Data Link layer, when lane L is active, TxOnly(L) is asserted and FarEndActive(L) is not, when lane L is active, TxOnly(L) is asserted and no bidirectional lane is active, and while TxEn(L) = RxEn(L) = 0. It shall be de-asserted when lane L is in ClearLine and none of these conditions holds. | 5.6.9.5, 5.6.8c.4 |
| ML-LM-13 | When the number of active transmitting lanes is at most the maximum number of data-sending lanes, all active transmitting lanes shall be data-sending lanes; otherwise the active transmitting lanes with the lowest lane numbers shall be data-sending lanes, up to the maximum, and the others hot redundant lanes. The maximum shall be taken over on link reset and while no lane is active. | 5.6.10d, e, h, Table 5-36 |
| ML-LM-14 | The near-end capability of each lane shall be held while that lane is in Connected (ML-LM-03). The far-end capability events of all lanes shall be passed to the Data Link layer with the information whether any lane was active. | 5.6.1m, n, o |
| ML-LM-15 | The scramble enable of the column encoder of each lane shall follow ML-LM-05 for that lane; the unscramble enable of each lane shall be the INIT3DataScrambled bit received on that lane, or, for a lane that entered Active without receiving INIT3 (receive-only lane), the bit of the last capability received on any lane. | 5.7.6.2.1a, 5.7.6.2.2a, 5.5.2.10e.3 |
| ML-LM-16 | The data-sending lanes, the data-receiving lanes and the alignment state shall be reported. | 5.6.1q |

### 2.7 Row distributor (ML-2)

`L` is the number of data-sending lanes.

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-DS-01 | The data words of a data frame shall be spread over the data-sending lanes, the first word over the lowest numbered data-sending lane, L words per sending row, in the order received from the Data Link layer. | 5.6.4.1b, c, 5.6.4.2a |
| ML-DS-02 | When a data frame ends with fewer than L words in the last sending row, the unused words of that row shall be PAD words, sent before the EDF row. Any other word that ends a data frame (SDF, SIF, RETRY, RXERR) shall also be preceded by the padded row. | 5.6.4.2b |
| ML-DS-03 | A replicated word (Data Link control word, word of a broadcast frame, word of an idle frame) shall be sent over all data-sending lanes in one sending row. FCT, ACK, NACK, FULL and the words of a broadcast frame may be sent while data words of an incomplete sending row wait, so that PAD words occur only before the end of a data frame. | 5.6.4.1d, 5.6.4.3a, 5.6.4.4a |
| ML-DS-04 | In Near-End Ready and Both-Ends Ready, a sending row of IDLE words shall be sent on the data-sending lanes when no row is available. | 5.6.4.5b to d |
| ML-DS-05 | A SKIP shall be requested from all lanes in the same clock cycle, once per SKIP interval. | 5.6.4.5a |
| ML-DS-06 | In Not Ready, seven ACTIVE words followed by one ALIGN word shall be sent repeatedly on every active transmitting lane, and no word of the Data Link layer shall be taken. | 5.6.6.3d, 5.6.7.2b.1 |
| ML-DS-07 | In Near-End Ready, one ALIGN word shall be sent after every seven words on every active transmitting lane. | 5.6.7.3b.3 |
| ML-DS-08 | In Both-Ends Ready, no ACTIVE and no ALIGN word shall be sent. | 5.6.7.4b |
| ML-DS-09 | The ACT field of the ACTIVE word shall have bit L set for every active lane L. The ALIGN word of a data-sending lane shall carry the number of active transmitting lanes (0 for 16) and its lane number; the ALIGN word of a hot redundant lane shall carry LANES = iLANES = 0. | 5.3.4.1, 5.3.4.2, 5.6.9.1, 5.6.10i |
| ML-DS-10 | A hot redundant lane shall send the PRBS sequence of the idle frames when it has no Multi-Lane control word to send, and no word of the Data Link layer. | 5.6.10c, f, g |
| ML-DS-11 | Words held in the distributor shall be discarded on link reset and when the Not Ready state is entered. | 5.7.10b.1 |

### 2.8 Lane alignment (ML-5)

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-AL-01 | Each lane shall have an alignment FIFO of four words. Only the words of data-receiving lanes shall be stored. | 5.6.6.4a to c, 5.6.10k |
| ML-AL-02 | A received ALIGN word shall be correct when iLANES is the inverse of LANES. A correct ALIGN word shall be valid when #Lanes equals the number of active receiving lanes and the lane number equals the lane on which it is received, and invalid otherwise. An ALIGN word that is not correct shall be treated as any other control word. | 5.6.6.3e to h |
| ML-AL-03 | An active receiving lane shall become a data-receiving lane with a correct ALIGN word and stop being one with an ALIGN word with LANES = iLANES = 0, when it leaves the Active state or when RxEn is cleared. | 5.6.10j, k, 3.2.29 |
| ML-AL-04 | An ACTIVE word shall be valid when the previous ACTIVE word received on the same lane had the same value. The ACT field of the last valid ACTIVE word shall be the far-end active lanes. | 5.6.6.3b, 5.6.9.1a |
| ML-AL-05 | A valid ALIGN word at the output of an alignment FIFO shall not be read unless every data-receiving lane has a valid ALIGN word at the output; then all of them shall be read together and the lanes are aligned. Any other word shall be read. | 5.6.6.4d to f |
| ML-AL-06 | A receiving row shall be read when every data-receiving lane has a word at the output of its alignment FIFO. | 5.6.5d, 5.6.6.4g |
| ML-AL-07 | All alignment FIFOs shall be flushed when a word is written to a full FIFO and on link reset; the FIFO of a lane shall be flushed when the lane enters the Active state and when it stops being a data-receiving lane. | 5.6.6.4h, i |
| ML-AL-08 | The alignment state machine shall implement Figure 5-37: Not Ready on link reset and on the Misaligned condition; Not Ready to Near-End Ready when the lanes are aligned and the far-end active lanes equal the near-end active lanes; Near-End Ready to Both-Ends Ready when a data word is received and the Misaligned condition does not occur; Both-Ends Ready to Near-End Ready when an ACTIVE word is received. | 5.6.7 |
| ML-AL-09 | The Misaligned condition shall arise when the near-end active lanes change, the far-end active lanes change, an alignment FIFO overflows, a correct but invalid ALIGN word is received, an invalid receiving row is received, an RXERR is passed to the Data Link layer within 4 us of entering Near-End Ready, the data-receiving lanes change, or a row is read with a valid ALIGN word held in some lanes after the lanes were aligned. | 5.6.7.1c |
| ML-AL-10 | The Misaligned condition shall clear the aligned state of the lanes. | 5.6.6.4g |

### 2.9 Row concentrator (ML-6)

| ID | Requirement | ECSS |
| --- | --- | --- |
| ML-CO-01 | A receiving row of data words, or of data and PAD words, shall be valid; a row of control words without PAD shall be valid; a row with data or PAD words and a control word other than PAD shall be invalid. RXERR words and the Multi-Lane control words are handled by ML-CO-03 and ML-AL-05. | 5.6.6.2 |
| ML-CO-02 | The data words of a valid data row shall be passed to the Data Link layer in the order of the lanes, without the PAD words. Of a valid control row only the word of the lowest data-receiving lane shall be passed; for an EDF row the CRC error flag shall be set when the CRC-16 check of any lane failed. | 5.6.5c, e, 5.6.4.1e, 5.6.4.2d |
| ML-CO-03 | An invalid row, a row with an RXERR word and a row that contains an ACTIVE word without being full of ACTIVE words shall be discarded and one RXERR passed to the Data Link layer. A row full of ACTIVE words and the aligned row of ALIGN words shall not be passed. | 5.6.5f, 5.6.6.3i |
| ML-CO-04 | In Not Ready, every receiving row with a word other than ACTIVE and ALIGN shall be replaced by one RXERR. When the Misaligned condition occurs in Near-End Ready or Both-Ends Ready, one RXERR shall be passed. | 5.6.7.2b.2, 5.5.2.11e.7 |
| ML-CO-05 | Within a broadcast frame and an idle frame, only one word of each replicated data row shall be passed. | 5.6.4.3a, 5.6.4.4a |
| ML-CO-06 | The data words of a data frame shall be packed into rows of `N` words; a row may be incomplete only before the word that ends the data frame. FCT, ACK, NACK, FULL and the words of a broadcast frame may be passed before data words that wait for a complete row. | 5.6.1d |

## 3. Error conditions

| Condition | Reaction |
| --- | --- |
| CRC-16 mismatch of a data frame column | CRC error flag with the EDF (ML-DEC-03); the Data Link layer discards the frame |
| EDF without SDF | Passed with the CRC error flag set (ML-DEC-03) |
| RXERR, RETRY or SIF inside a data frame | Data frame ended in the column codec (ML-ENC-01, ML-DEC-01); the Data Link layer handles the error |
| Invalid receiving row, alignment FIFO overflow, invalid ALIGN, change of the active lanes | Misaligned condition: Not Ready and realignment (ML-AL-09); RXERR to the Data Link layer (ML-CO-03, ML-CO-04) |
| RXERR word in a receiving row | Row replaced by one RXERR (ML-CO-03); within 4 us of entering Near-End Ready also Misaligned |

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumLanes_g` | 1 | Number of lanes, 1 to 4; also the row width of the Data Link layer |
| `ClkFrequency_g` | 156.25e6 | Lane clock frequency in Hz (4 us window of ML-AL-09) |
| `SkipIntervalWords_g` | 5000 | SKIP interval in words (ML-DS-05) |

| Management input | Reset value | Description |
| --- | --- | --- |
| `Cfg_TxEn`, `Cfg_RxEn` | all ones | TxEn and RxEn per lane |
| `Cfg_MaxDataLanes` | `N` | Maximum number of data-sending lanes, 1 to `N` (0 and values above `N` are taken as `N`) |
| `Cfg_Bypass` | 0 | Multi-Lane bypass (lane 0 only) |

## 5. Interpretation of the standard

Clause 5.7.6.4b defines the CRC-16 over "an entire data frame, from and including the comma in the SDF up to and
including the Sequence Number in the EDF". Data Link control words (FCT, ACK, NACK, FULL) and broadcast frames sent
inside a data frame are not part of the data frame: they carry their own CRC-8, and the note of 5.7.6.2.1e states for
scrambling that the random number generator only runs for the data of the data frame when an FCT is interleaved. The
column codec therefore excludes them from the CRC-16 and from scrambling. This interpretation is checked against
STAR-Dundee equipment in the lab test of phase 2.

The multi-lane clauses leave the following points open; OpenFibre resolves them as follows:

| Point | Interpretation | Reason |
| --- | --- | --- |
| #Lanes of the ALIGN word (5.3.4.2d: "lanes in the Active state at the end sending") and its check (5.6.6.3g: "active lanes with RxEn at the receiving end") | #Lanes is the number of active transmitting lanes, hot redundant lanes included | In an asymmetric link the active lanes of the sender include RxOnly lanes that do not send; only the transmitting lanes match the receiving lanes of the far end |
| RXERR in a row (5.6.5f) | A row with an RXERR word is replaced by one RXERR; it is not an invalid row and does not cause the Misaligned condition (except within 4 us of entering Near-End Ready) | 5.6.5f names "invalid" and "contains an RXERR" separately; a bit error in one lane is recovered by the Data Link layer without realignment |
| Partial reads before alignment (Figure 5-36) | Rows read while a valid ALIGN word is held in some lanes are not receiving rows and are discarded silently before the lanes are aligned; after alignment they cause the Misaligned condition | Figure 5-36 reads them as part of the alignment; after alignment such a row is evidence of a lane slip |
| RXERR in Not Ready (5.6.7.2b.2) | Only rows with words other than ACTIVE and ALIGN are replaced by RXERR; one RXERR when Not Ready is entered from an aligned state | Rows of Multi-Lane control words carry no Data Link information; the extra RXERR tells the Data Link layer that words may have been lost, as the Lane layer does when Active is left (5.5.2.11e.7) |
| Data-receiving lanes changed | Misaligned condition | The row composition changes; 5.6.10l note 2 states that a new alignment occurs |
| Multi-LaneCapable bit (5.3.3.8i) | A far end that is not Multi-Lane capable on lane 0 selects the bypass | Interoperation with single-lane devices; the standard defines the flag but no reaction |
| Data words around FCT, ACK, NACK, FULL and broadcast frames | Data words that wait for a complete sending row (or a complete row to the Data Link layer) may follow such a word | 5.6.4.2b allows PAD only at the end of a data frame; these words are processed independently of the data frame content, so the order of data words relative to them carries no information |
