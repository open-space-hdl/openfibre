# ofb_multilane: Verification Plan

## 1. Overview

The Multi-Lane layer is verified on two levels: a unit testbench of the column codec (encoder and decoder), which
checks the ECSS examples bit-exactly and random frames against a reference model, and a layer testbench in which two
Multi-Lane layers (one lane each) exchange rows through two Lane layers and the behavioural Physical adapter model.
All checks observe ports only.

The reference model (`ofb_ml_tb_pkg`) computes the CRC-16 and the scrambling sequence with the functions of `ofb_pkg`
(`crc16Update`, `prbsWord`, `prbsNextState`), independent of the Open Logic entities used in the RTL.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_ml_codec_tb` | `ofb_ml_codec_th` | `ofb_ml_col_enc` and `ofb_ml_col_dec`; AXI-Stream VVCs for the encoder input and the decoder input; random back-pressure at the encoder output; the decoder input is switched between its VVC and the encoder output (loopback); logs of both outputs |
| `ofb_multilane_tb` | `ofb_multilane_th` | Two `ofb_multilane` (A, B, one lane) with two `ofb_lane` and `ofb_tb_pa_model`; AXI-Stream VVCs for the transmit rows; logs of the received rows; Data Link control and status through package signals |

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

## 4. Coverage analysis

Every requirement of the specification is covered by at least one test case. The column codec is checked against the
ECSS examples (Figures 5-42 and 5-44) and, for interleaved words, against the reference model; the interpretation of
section 5 of the specification is checked against STAR-Dundee equipment in the lab test of phase 2.
