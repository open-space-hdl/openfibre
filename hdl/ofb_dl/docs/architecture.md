# ofb_dl: Architecture and Design Description

## 1. Block diagram

```text
 UserClk                     Clk (core clock)
 Network layer               |
  TxVc_* (x NumVc) --> ofb_dl_vc_out (DT-1/2) --+                                +--> TxRow_* (Multi-Lane)
  TxBc_*           --> ofb_dl_bc_out (DT-3) ----+--> ofb_dl_tx_admit --> ofb_dl_erb --> ofb_dl_tx_frame
                                                |     (DT-4, admission)  (DT-7)        (DT-5/6/8)
                         FCT requests ----------+                ^  ACK / NACK   ^ ACK / NACK requests, RxSeq
                                                                 |               |
  RxVc_* (x NumVc) <-- ofb_dl_vc_in (DR-6) <-- ofb_dl_rx_buf (DR-5) <-- ofb_dl_rx_check (DR-1/2/4) <-- RxRow_*
  RxBc_*           <-- ofb_dl_bc_in (DR-7) <------------------------------+        |
                                                                 ofb_dl_rx_err (DR-3)
                                       ofb_dl_link_reset (DC-1): link reset, LaneReset, capability
```

The transmit path is store and forward: a new item (data segment, broadcast message, FCT) is first admitted into the
error recovery buffer and then sent from there. New items and items to be resent therefore take the same path, and an
item that is interrupted by a RETRY is complete in the buffer.

All blocks except the user side of the four buffer kinds run on `Clk` with the synchronous high-active `Rst`. Link reset
(`LinkReset`, one cycle) is a synchronous command for every block.

## 2. Common package (`ofb_dl_pkg`)

- `DlKind_t`: kind of a received word (`KindData`, `KindSdf`, `KindEdf`, `KindSbf`, `KindEbf`, `KindSif`, `KindFct`,
  `KindAck`, `KindNack`, `KindFull`, `KindRetry`, `KindRxErr`, `KindUnknown`) and `dlWordKind(data, k)`.
- `ErbKind_t`: item kind of the error recovery buffer (`ErbBc`, `ErbFct`, `ErbData`).
- Sequence number helpers: `seqCount`, `seqPol`, modulo-128 difference `seqDiff`.
- `crc8Chars(crc, word, n)`: CRC-8 over the first n characters of a word (running CRC of broadcast frames).
- `wordHasEnd(data, k)`: the word contains an EOP or EEP; `wordLastIsEnd(data, k)`: character 3 is EOP, EEP or Fill.

## 3. Sub-block descriptions

### 3.1 ofb_dl_vc_out (DT-1, DT-2), one per VC

- Buffer: `olo_ft_fifo_async` (36 bits: data and K flags, `VcOutDepth_g` words), `UserClk` to `Clk`.
- Link reset: the read side resets the FIFO (`Out_Rst`); the reset reaches the user side as `In_RstOut`. The user side
  then enters spill mode when the last word written did not end with EOP, EEP or Fill (character 3): words are accepted
  and discarded up to and including the next word with an EOP or EEP.
- End-of-packet count: the user side counts words with an EOP or EEP in a Gray-coded counter, which crosses with
  `olo_ft_cc_bits`; the read side counts the words it reads. A difference not equal to zero means that the buffer holds
  an EOP or EEP. The crossed value lags, so the read side never sees an EOP that is not yet in the buffer.
- Credit: `Credit` (`CreditWidth_g` bits) + (M x 64) per received FCT (`Fct_Valid`), - 1 per word read; overflow sets
  the counter to its maximum and pulses `Ev_CreditOverflow`; cleared on link reset.
- Segment: `Seg_Ready = Credit > 0 and Level > 0 and (Level >= 64 or Eop or Full)`,
  `Seg_Words = min(Level, 64, Credit)` (`Level` is the read-side level of the FIFO, which never exceeds the true level).

### 3.2 ofb_dl_bc_out (DT-3)

- Buffer: `olo_ft_fifo_async` (82 bits: 8 data bytes, channel, B_TYPE, DELAYED flag, `BcOutDepth_g` messages).
- Broadcast Bandwidth Credit Counter (0 to 256): + 1 every `Cfg_BcInterval` words sent on the link (4 / Normalised
  Expected Broadcast Bandwidth, 40 words for 10 %), - 1 for every broadcast frame sent (`Ev_BcSent`, saturating at 0 for
  resent frames), zero on link reset. `Bc_Credit` = counter greater than zero.
- LATE flag: set while a message waits and no lane is active or error recovery is in progress, cleared when the buffer
  is empty; it is added to every message read while it is set.

### 3.3 ofb_dl_tx_admit (DT-4 and admission)

Writes new items into the error recovery buffer:

| Item | Condition | Action |
| --- | --- | --- |
| Data segment | A VC with `Seg_Ready` (round robin, `olo_base_arb_rr`), a free data item and at least one free data word | Copies `L = min(Seg_Words, free words)` words from the VC into the buffer, then commits the item (VC, L) |
| Broadcast message | Message available, broadcast credit, a free broadcast item and no broadcast item waiting to be sent | Moves the message into the buffer |
| FCT | An input VC buffer requests an FCT (round robin), a free FCT item | Writes the FCT (VC, M - 1), acknowledges the request |

The VC selection for the next data segment is made when the last word of the previous segment is copied (ECSS
5.7.4.4c).

### 3.4 ofb_dl_erb (DT-7)

Three item queues in send order, each with the pointers `Head` (oldest item), `Send` (next item to send) and `Tail`
(next free entry): items in `[Head, Send)` were sent and carry a valid sequence number, items in `[Send, Tail)` are
waiting to be sent or resent.

| Queue | Entry | Payload |
| --- | --- | --- |
| Broadcast (`ErbBcItems_g`) | Data, channel, B_TYPE, DELAYED, LATE, sent-once flag | In the entry |
| FCT (`ErbFctItems_g`) | VC, multiplier | In the entry |
| Data (`ErbDataItems_g`) | VC, length | Ring of `ErbWords_g` words in `olo_ft_ram_sdp` |

- Send-order log: a circular list of the kinds of the sent items in sequence-number order (at most 127 entries). An
  item sent by `ofb_dl_tx_frame` (`Sent_Valid`, `Sent_Kind`) advances `Send` of its queue and appends its kind.
- ACK with count c: `d = (c - LastAck) mod 128`; `d` greater than the log count is a protocol error
  (`Ev_ProtocolError`), otherwise `d` log entries are removed and with each the head item of its queue (one per
  cycle); `LastAck = c`.
- NACK with count c: as ACK, then `Send = Head` for all queues, log cleared, `Retry_Req` with `Retry_Seq = c` to
  `ofb_dl_tx_frame`. Until the RETRY is sent (`Retry_Done`), further ACKs, NACKs and sent items are ignored: words
  sent in this window carry the old polarity and are rejected by the far end.
- ACKs and NACKs are valid only with the polarity of the Transmit Polarity Flag; they wait in a small event FIFO.
- Data payload: the item at `Send` is read ahead into a 4-word FIFO (`olo_base_fifo_sync`), which `ofb_dl_tx_frame`
  reads (`Pay_*`). After a NACK the read-ahead restarts at the head item once the RETRY is sent.
- Full: `Full = no free data word or no free item of any kind`; `Empty` when all queues are empty.

### 3.5 ofb_dl_tx_frame (DT-5, DT-6, DT-8)

One output register towards the Multi-Lane layer. In every cycle in which the register can be loaded, the first
matching rule selects the word:

| Rule | Condition | Word |
| --- | --- | --- |
| 1 | `Retry_Req` | RETRY; the current frame is abandoned; Transmit Sequence Counter = `Retry_Seq`, polarity inverted; `Retry_Done` |
| 2 | Broadcast frame open | Next word of SBF, data 0, data 1, EBF |
| 3 | Broadcast item waiting in the buffer | SBF (opens the broadcast frame; an open data frame is suspended, an idle frame ends) |
| 4 | ACK or NACK pending (ACK: at least 15 words after the previous ACK) | ACK (Receive Sequence Counter and flag) or NACK (inverse flag) |
| 5 | FCT item waiting | FCT |
| 6 | FULL pending | FULL |
| 7 | Data frame open | Next payload word, after the last one the EDF |
| 8 | Data item waiting | SDF (opens the data frame) |
| 9 | none of the above | SIF when no idle frame is open or 64 PRBS words were sent, otherwise the next PRBS word |

- EDF, EBF and FCT increment the Transmit Sequence Counter and carry the new value; SIF and FULL carry the current
  value. In the cycle in which an EDF, EBF or FCT is loaded into the register, `Sent_Valid` reports the item to the
  buffer, and the RETRY is reported with `Retry_Done` (both combinational, so that the buffer never offers the same
  item twice).
- CRC-8: `crc8Word3` for SIF, FCT, ACK, NACK, FULL; a running CRC-8 over SBF, the two data words and the first three
  characters of the EBF.
- Idle PRBS: `olo_base_prbs` (seed `PrbsSeed_c` after reset and link reset), advanced only by PRBS words.
- FULL: pending when `Full` rises, every 64 words while `Full` stays set, and once after an RXERR or CRC error when all
  output VC buffers are empty, no item waits and the buffer is not empty.
- A resent broadcast frame carries the LATE flag.

### 3.6 ofb_dl_rx_check (DR-1, DR-2, DR-4)

Registered processing of one received word per cycle:

1. Classification (`dlWordKind`), CRC-8 check of SIF, FCT, ACK, NACK, FULL (`crc8Word3`), of the broadcast frame
   (running CRC-8), CRC-16 flag of the EDF from the Multi-Lane layer.
2. Sequence check: EDF, EBF, FCT against counter + 1, SIF and FULL against the counter, polarity against the Receive
   Polarity Flag of DR-3. EDF is checked in RxDataFrame only, EBF in the broadcast states only, FCT, SIF, FULL in all.
3. Data word identification state machine (ECSS Figure 5-49), exit conditions in the order of the standard: RETRY,
   RXERR, CRC error, sequence error, valid end of frame, frame error.
4. Outputs: data words with their VC to DR-5, commit on a valid EDF, drop when a data frame ends otherwise; accepted
   broadcast messages to DR-7; accepted FCTs to DT-2; CRC-valid ACK and NACK to DT-7; ACK and NACK requests and the
   sequence error with matching polarity to DR-3; status events.

The Receive Sequence Counter increments on an accepted EDF, EBF or FCT.

### 3.7 ofb_dl_rx_err (DR-3)

Four-state machine of ECSS Figure 5-48: a NACK request moves Valid Positive to Error Negative and Valid Negative to
Error Positive; an ACK request moves Error Positive to Valid Positive and Error Negative to Valid Negative; a sequence
error with the polarity of the Receive Polarity Flag moves Error Positive to Error Negative and back. The flag is 0 in
Valid Positive and Error Positive. ACK and NACK requests are passed to `ofb_dl_tx_frame`, which keeps one pending
request (the newer replaces the older).

### 3.8 ofb_dl_rx_buf (DR-5)

The last data word of the current frame is held in a register, so that it can be written with `Last` once the frame
ends: on the next data word it is written as a normal word, on commit with `Last`, on drop with `Last` and `In_Drop`.
The frame buffer is an `olo_ft_fifo_packet` (41 bits: data, K, VC; 128 words): only committed frames reach its output.
The output is distributed to the input VC buffer of the VC stored with every word; a word for a full input VC buffer is
an overflow (`Ev_Overflow` per VC).

### 3.9 ofb_dl_vc_in (DR-6), one per VC

- Buffer: `olo_ft_fifo_async` (36 bits, `VcInDepth_g` words), `Clk` to `UserClk`; link reset resets it from the write
  side.
- FCT requests: a counter of FCTs to send, set to `VcInDepth_g / 64` on link reset, + 1 for every 64 words read by the
  Network layer (pulse through `olo_ft_cc_pulse`), - 1 for every FCT admitted.
- User side after link reset: when the last word read did not end with EOP, EEP or Fill, a word EEP, Fill, Fill, Fill is
  read first.

### 3.10 ofb_dl_bc_in (DR-7)

`olo_ft_fifo_async` (82 bits, `BcInDepth_g` messages), `Clk` to `UserClk`; a message for a full buffer is discarded
(`Ev_BcDiscard`).

### 3.11 ofb_dl_link_reset (DC-1)

| State | Outputs | Exit (in this order) |
| --- | --- | --- |
| ConfigReset | Link reset, LaneReset, configuration reset | NearEndReset |
| NearEndReset | Link reset, LaneReset | Interface Reset: ConfigReset; otherwise CheckFarEnd |
| CheckFarEnd | INIT3LinkResetFlag = 1 | Interface Reset: ConfigReset; Link Reset or link error: NearEndReset; capability event with flag 1: LinkInit |
| LinkInit | INIT3LinkResetFlag = 0 | Interface Reset: ConfigReset; Link Reset or link error: NearEndReset; no lane active and capability event with flag 1: NearEndReset, `Ev_FarEndLinkReset` |

Reset enters ConfigReset. Link errors are the protocol error of DT-7 and the overflows of DR-5 and DR-6.

## 4. Top-level ports (`ofb_dl`)

| Group | Ports |
| --- | --- |
| Clocks | `Clk`, `Rst`, `UserClk`, `UserRst` |
| VC ports (`UserClk`) | `TxVc_Data` (32 x NumVc), `TxVc_K` (4 x NumVc), `TxVc_Valid`, `TxVc_Ready`; `RxVc_Data`, `RxVc_K`, `RxVc_Valid`, `RxVc_Ready` |
| Broadcast (`UserClk`) | `TxBc_Data` (64), `TxBc_Channel`, `TxBc_Type`, `TxBc_Delayed`, `TxBc_Valid`, `TxBc_Ready`; `RxBc_Data`, `RxBc_Channel`, `RxBc_Type`, `RxBc_Delayed`, `RxBc_Late`, `RxBc_Valid`, `RxBc_Ready` |
| Multi-Lane layer | `TxRow_*`, `RxRow_*` (section 2.1 of the `ofb_multilane` architecture), `Ml_LinkReset`, `Ml_LaneReset`, `Ml_NearCapability`, `Ml_FarCapability`, `Ml_FarCapabilityValid`, `Ml_LaneActive` |
| Configuration | `Cfg_DataScrambled`, `Cfg_LinkReset`, `Cfg_InterfaceReset`, `Cfg_BcInterval` |
| Status | `Stat_*` levels and `Ev_*` events of DL-ST-01 |

## 5. Open points

- Phase 3: QoS (DT-4), continuous mode; phase 4: rows of more than one word.
- The data payload RAM is `olo_ft_ram_sdp`; the scrubbing variant is introduced with the hardening phase.
- The item entries of the error recovery buffer are registers (small), not `olo_ft_ram_sdp` as foreseen in the core
  architecture.
