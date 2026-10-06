# ofb_multilane: Verification Plan

## 1. Overview

The Multi-Lane layer is verified on two levels: unit testbenches of the column codec (encoder and decoder), which
checks the ECSS examples bit-exactly and random frames against a reference model, and of the receive side of the
multi-lane case (lane alignment and row concentrator), which drives words per lane directly; and layer testbenches in
which two Multi-Lane layers exchange rows through Lane layers and the behavioural Physical adapter model, with one
lane (bypass) and with 2 and 4 lanes. All checks observe ports only.

The reference model (`ofb_ml_tb_pkg`) computes the CRC-16 and the scrambling sequence with the functions of `ofb_pkg`
(`crc16Update`, `prbsWord`, `prbsNextState`), independent of the Open Logic entities used in the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_ml_codec_tb` | `ofb_ml_codec_th` | `ofb_ml_col_enc` and `ofb_ml_col_dec`; AXI-Stream VVCs for the encoder input and the decoder input; random back-pressure at the encoder output; the decoder input is switched between its VVC and the encoder output (loopback); logs of both outputs |
| `ofb_multilane_tb` | `ofb_multilane_th` | Two `ofb_multilane` (A, B, one lane) with two `ofb_lane` and `ofb_tb_pa_model`; AXI-Stream VVCs for the transmit rows; logs of the received rows; Data Link control and status through package signals |
| `ofb_ml_link_tb` | `ofb_ml_link_th` | Two `ofb_multilane` (A, B) with `NumLanes_g` = 2 and 4 (VUnit configurations), one `ofb_lane` per lane (`SkipExternal_g`), one `ofb_tb_pa_model` per lane with skew, cut and bit errors; row drivers fed from a row queue per end; monitors that parse the received rows into frames and control words and compare them with the expected streams; a monitor of the words sent on every lane (ACTIVE, ALIGN, PAD, IDLE, SKIP, PRBS) |
| `ofb_ml_align_tb` | none (test sequencer drives the DUT) | `ofb_ml_align` and `ofb_ml_rx` (`NumLanes_g = 4`); words per lane from the sequencer; log of the rows passed and of the alignment state |

Lane clock 156.25 MHz. Simulator: GHDL.

## 3. Test cases

### 3.1 Column codec (`ofb_ml_codec_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_enc_crc_vectors` (TC-ML-01) | The three frames of ECSS Figure 5-44 without scrambling: CRC fields as in the standard, all other words unchanged | ML-ENC-04, ML-ENC-06 |
| `test_enc_scramble_vector` (TC-ML-02) | The frame of ECSS Figure 5-42 with scrambling: scrambled data and CRC as in the standard; EOP and Fill kept | ML-ENC-02, ML-ENC-03, ML-ENC-04 |
| `test_enc_interleaved` (TC-ML-03) | Data frames with FCT, ACK, NACK, FULL, PAD, unknown control words and a broadcast frame inside; idle frame, broadcast frame and an EDF outside a data frame; two frames in a row: output equal to the reference model | ML-ENC-01, ML-ENC-03, ML-ENC-05, ML-ENC-06 |
| `test_enc_backpressure` (TC-ML-04) | Random frames (2000 words, scrambling on) with random input gaps and random output back-pressure: output equal to the reference model, no word lost or duplicated | ML-ENC-07 |
| `test_enc_abort_flush` (TC-ML-05) | RETRY and SIF end a data frame (following data words unchanged); flush discards the held word and ends the frame | ML-ENC-01, ML-BP-03 |
| `test_dec_vectors` (TC-ML-06) | Decoder input from Figures 5-44 and 5-42 (scrambled): original data restored, no CRC error | ML-DEC-02, ML-DEC-03 |
| `test_dec_crc_errors` (TC-ML-07) | Bit error in the SDF, a data word, the EDF sequence number and the CRC field; EDF without SDF: CRC error with the EDF only | ML-DEC-03 |
| `test_dec_interleaved` (TC-ML-08) | Frames of TC-ML-03 after encoding: control words, PAD and broadcast words excluded, latency one cycle, every word passed | ML-DEC-01, ML-DEC-04, ML-DEC-05 |
| `test_codec_loopback` (TC-ML-09) | Random frames with interleaved words through encoder and decoder with scrambling on and off: decoded words equal the original words, CRC field excepted, no CRC error | ML-ENC-01 to 07, ML-DEC-01 to 05 |

### 3.2 Layer testbench (`ofb_multilane_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_bypass_traffic` (TC-ML-20) | Lanes reach Active; random frames in both directions with scrambling: rows received in order, CRC error flag clear | ML-IF-01 to 03, ML-BP-01, ML-BP-02, ML-LM-05 |
| `test_scramble_capability` (TC-ML-21) | A scrambles, B does not: both directions correct; a change of DataScrambled in Active takes effect only after a LaneReset | ML-LM-05 |
| `test_lane_control` (TC-ML-22) | TxOnly, RxOnly and FarEndActive de-asserted; LaneReset from the Data Link layer restarts the lane; lane active, data-sending / receiving lanes and alignment state follow the lane; far-end capability event and value with the MultiLane bit cleared | ML-IF-04 to 06, ML-LM-01 to 04, ML-LM-06 |
| `test_ml_ctrl_discard` (TC-ML-23) | PAD, ACTIVE and ALIGN sent from A are not passed up at B; the words around them are | ML-BP-02 |
| `test_link_reset_flush` (TC-ML-24) | A row held while the lane is not Active is discarded by link reset and not received at the far end | ML-BP-03 |
| `test_capability_hold` (TC-ML-25) | The near-end capability changed while the lane is in Connected: the far end receives the value held in Connected, the new value in the next initialisation | ML-LM-03 |

### 3.3 Multi-lane link (`ofb_ml_link_tb`, `NumLanes_g` = 2 and 4)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_align_traffic` (TC-ML-30) | All lanes start with different skews (0 to 2 words); both ends reach Both-Ends Ready; random frames (lengths not a multiple of the lanes), interleaved FCT, ACK, broadcast frames and idle frames in both directions: frames, control words and broadcast words received in order, no RXERR, no CRC error, rows incomplete only before the end of a frame | ML-IF-01, ML-IF-02, ML-DS-01 to 04, ML-AL-01, ML-AL-05, ML-AL-06, ML-AL-08, ML-CO-01, ML-CO-02, ML-CO-05, ML-CO-06, ML-LM-13 to 16 |
| `test_lane_words` (TC-ML-31) | Words on every lane: SKIP in the same cycle on all lanes; in Not Ready seven ACTIVE and one ALIGN with the ACT, #Lanes and lane number fields; in Near-End Ready one ALIGN every eight words; none in Both-Ends Ready; IDLE rows without traffic; PAD only before an EDF | ML-IF-08, ML-DS-02, ML-DS-04 to 09, LN-TX-06 |
| `test_skew_slip` (TC-ML-32) | Skew of three words is absorbed; a lane slip in Both-Ends Ready (skew changed while words flow) causes the Misaligned condition, RXERR to the Data Link layer and a new alignment; traffic afterwards correct | ML-AL-07, ML-AL-09, ML-AL-10, ML-CO-03, ML-CO-04 |
| `test_hot_redundant` (TC-ML-33) | Maximum number of data-sending lanes below the number of lanes: data-sending and hot redundant lanes, PRBS and ALIGN with LANES = iLANES = 0 on the hot redundant lanes, the far end does not receive data on them; traffic correct with fewer data-sending lanes than row words (PAD, interleaved words) | ML-LM-13, ML-DS-03, ML-DS-09, ML-DS-10, ML-AL-03, ML-IF-07 |
| `test_lane_failure` (TC-ML-34) | A data-sending lane is cut during traffic: new alignment over the remaining lanes (a hot redundant lane is promoted when present), RXERR to the Data Link layer; after reconnection the lane joins again; traffic correct after each alignment | ML-LM-13, ML-AL-07, ML-AL-09, ML-CO-04 |
| `test_asymmetric` (TC-ML-35) | A: lane 0 bidirectional, lane 1 TxEn only; B: lane 0 bidirectional, lane 1 RxEn only: TxOnly and RxOnly asserted, the TxOnly lane becomes Active through FarEndActive, two lanes A to B and one lane B to A carry traffic; when the RxOnly lane is reset, the TxOnly lane is reset (FarEndActive cleared); disabled lanes (TxEn = RxEn = 0) stay in reset | ML-LM-09 to 12, ML-DS-09 (interpretation), ML-AL-02, ML-IF-07 |
| `test_bypass` (TC-ML-36) | Bypass set at both ends: one lane, no ACTIVE and ALIGN, the other lanes held in LaneReset, Multi-LaneCapable bit clear; bypass at B only: A selects the bypass from the capability of lane 0; traffic correct in both cases | ML-LM-07, ML-LM-08, ML-IF-07 |
| `test_rxerr_rows` (TC-ML-37) | Bit error on one lane in Both-Ends Ready: one RXERR passed, no Misaligned condition; bit error within 4 us of entering Near-End Ready: Misaligned condition | ML-CO-03, ML-AL-09 |
| `test_link_reset` (TC-ML-38) | Link reset at A during traffic: words in the distributor discarded, alignment FIFOs flushed, new alignment, traffic correct afterwards | ML-DS-11, ML-AL-07 |

### 3.4 Lane alignment and concentration (`ofb_ml_align_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_alignment_fifo` (TC-ML-40) | Sequence of Figure 5-36 (ALIGN held until all data-receiving lanes have one); skew of 0 to 3 words aligned; a skew of 4 words overflows a FIFO: all FIFOs flushed and Misaligned | ML-AL-01, ML-AL-05 to 07, ML-AL-09 |
| `test_row_rules` (TC-ML-41) | Valid data rows (with PAD), control rows (word of the lowest lane, CRC error OR of the lanes), invalid rows, rows with RXERR, rows with some ACTIVE words, rows of PAD only, partial rows after alignment | ML-CO-01 to 04, ML-AL-09 |
| `test_align_states` (TC-ML-42) | Not Ready to Near-End Ready only when the far-end active lanes equal the near-end active lanes; Near-End Ready to Both-Ends Ready on a data word; Both-Ends Ready to Near-End Ready on ACTIVE; RXERR within and after 4 us; invalid ALIGN; ALIGN of a hot redundant lane removes the lane from the data-receiving lanes; an incorrect ALIGN on an active lane that is not data-receiving is ignored; valid ACTIVE needs two equal words | ML-AL-02 to 04, ML-AL-08 to 10 |
| `test_slip_reverse` (TC-ML-44) | Lane slip at B while both ends send: Misaligned condition at B; every word that B sends is received at A in order, without RXERR, mismatch or CRC error at A; traffic afterwards correct | ML-DS-12 |
| `test_enc_poison` (TC-ML-45) | Encoder: frame of Figure 5-44 with poisoned words (CRC inverted), poisoned word between two frames (CRC of the next frame inverted), clean frame (CRC as in the standard) | ML-ENC-08 |
| `test_poison` (TC-ML-46) | Rows of one data frame poisoned at A: exactly one EDF with CRC error at B; traffic afterwards correct | ML-DS-13, ML-ENC-08 |
| `test_packing` (TC-ML-43) | Data words packed into rows of N words, incomplete row before EDF, RETRY, SIF and RXERR; FCT and broadcast words pass waiting data words; one word of replicated broadcast and idle rows | ML-CO-05, ML-CO-06 |
| `test_packing_errors` (TC-ML-47) | Frame structure errors at the receiver: SIF inside a data frame passes the waiting words and starts an idle frame; second SBF without EBF; SDF after a broadcast frame packs again; SIF inside a broadcast frame inside and outside a data frame | ML-CO-05, ML-CO-06 |

## 4. Coverage analysis

Every requirement of the specification is covered by at least one test case. The rules of the row classification
and of the alignment state machine that cannot be provoked reliably over a link (invalid rows, partial ACTIVE rows,
exact 4 us timing) are covered by `ofb_ml_align_tb`; the link testbench covers the same functions end to end.

The column codec is checked against the ECSS examples (Figures 5-42 and 5-44) and, for interleaved words, against the
reference model; the interpretation of section 5 of the specification is checked against STAR-Dundee equipment in the
lab test of phase 2.
