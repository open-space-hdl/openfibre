# ofb_multilane: Architecture and Design Description

## 1. Block diagram

```text
        Data Link layer (rows of N words)                  Data Link control            MIB
   TxRow_*  |                     ^ RxRow_*      Dl_LaneReset, Dl_NearCapability |  ^ Dl_Far*  | Cfg_* ^ Stat_*
            v                     |                                              v  |          v       |
  +----------------------------------------------------------------------------------------------------------+
  | ofb_multilane                                                                                            |
  |  +----------------------+  +----------------------+     +---------------------------------------------+  |
  |  | ofb_ml_tx (ML-2)     |  | ofb_ml_rx (ML-6)     |<----| ofb_ml_lane_mgr (ML-1)                      |  |
  |  | gearbox N -> L words |  | frame state, packing |     | TxOnly, RxOnly, FarEndActive, LaneReset,    |  |
  |  | PAD, IDLE, ACTIVE,   |  | into rows of N words |     | data-sending / hot redundant lanes, bypass, |  |
  |  | ALIGN, PRBS, SKIP    |  +----------------------+     | capabilities, scramble enables              |  |
  |  +----------------------+            ^ receiving rows   +---------------------------------------------+  |
  |       | one word per lane            |                         ^ FarAct (valid ACTIVE)      |            |
  |       v                  +----------------------------------+  |                            |            |
  |  +----------------+      | ofb_ml_align (ML-5)              |--+  alignment state           |            |
  |  | ofb_ml_col_enc |      | ACTIVE / ALIGN reception,        |---------------------------->--+            |
  |  | x N (ML-3)     |      | alignment FIFOs, row reading,    |                                            |
  |  +----------------+      | row classification, state machine|                                            |
  |       |                  +----------------------------------+                                            |
  |       |                              ^ one word per lane                                                  |
  |       |                      +----------------+                                                           |
  |       |                      | ofb_ml_col_dec |                                                           |
  |       |                      | x N (ML-4)     |                                                           |
  |       |                      +----------------+                                                           |
  +-------|------------------------------^--------------------------------------------------------------------+
          v LaneTx_*, Lane_SkipReq       | LaneRx_*                    Lane_* control / state
                                Lane layers (one per lane)
```

All blocks run on `Clk` (lane clock) with the synchronous high-active `Rst`. `N` is `NumLanes_g`.

With `N = 1` only the lane manager, one column encoder and one column decoder are instantiated; the row distributor
and the row concentrator reduce to the bypass of section 2.10 (decision D1 of the core architecture). With `N > 1`
all blocks are instantiated; the bypass of section 2.10 is selected at run time by the lane manager (ML-LM-07) and
handled inside `ofb_ml_tx` and `ofb_ml_rx`.

## 2. Sub-block descriptions

### 2.1 Word classification (`ofb_ml_pkg`)

The function `wordKind` classifies a word by its first two characters and K flags:

| Kind | Condition |
| --- | --- |
| `Data_k` | K flag of character 0 clear, or character 0 is EOP, EEP or Fill |
| `Sdf_k`, `Sbf_k`, `Sif_k`, `Retry_k` | K28.7 followed by the SDF, SBF, SIF or RETRY symbol |
| `Pad_k` | K28.7 followed by K27.7 with K flag (PAD) |
| `MlCtrl_k` | K28.7 followed by the ACTIVE or ALIGN symbol |
| `Edf_k`, `Ebf_k` | K28.0, K28.2 |
| `RxErr_k` | K0.0 |
| `Other_k` | Every other control word (FCT, ACK, NACK, FULL, unknown) |

The package also defines the alignment state encoding, the functions `isActive`, `alignCorrect`, `alignHot`
(ALIGN word checks of ML-AL-02), `interleaved` (words that may pass waiting data words: `Data_k`, `Sbf_k`, `Ebf_k`,
`Other_k`) and the counting helper `countOnes`.

### 2.2 Column identification

Encoder and decoder share the same frame state (`FrameFsm_t`):

| State | Entered on | Words of the data frame |
| --- | --- | --- |
| `None_s` | Reset, flush, EDF in `Data_s`, SIF, RETRY, RXERR | none |
| `Data_s` | SDF (in any state), EBF in `Bcst_s` | data words |
| `Bcst_s` | SBF in `Data_s` | none (broadcast frame inside the data frame) |

An SDF always (re)starts the column: CRC-16 restarted with the SDF, scrambler re-seeded. A data word in `Data_s` is
scrambled (encoder) or unscrambled (decoder) and enters the CRC-16. An EDF in `Data_s` enters the CRC-16 with
characters 0 and 1 only and ends the frame. All other words pass unchanged and do not touch the CRC or the scrambler.
Since control words, broadcast words and idle words are replicated over all data-sending lanes, every lane sees the
SDF, the EDF and the broadcast frame delimiters, and the frame state of every lane is the same.

### 2.3 ofb_ml_col_enc (ML-3)

One pipeline stage with valid / ready handshake:

| Register | Function |
| --- | --- |
| `State` | Frame state of section 2.2 |
| `OutData`, `OutK`, `OutValid` | Output word (scrambled data word, or the word unchanged) |
| `OutCrc` | The output word is an EDF that ends a data frame: characters 2 and 3 are taken from the CRC unit |

`In_Ready = (not OutValid or Out_Ready) and not Ctrl_Flush`. A word is taken when `In_Valid` and `In_Ready`.

- Scrambler: `olo_base_prbs` (32 bits per word, ECSS settings of `ofb_pkg`). `Out_Data` is the sequence for the
  current word; it advances (`Out_Ready`) with every data word of a data frame and is re-seeded (`State_Set`,
  `State_New = PrbsSeed_c`) with every SDF. A data character (K flag clear) is XORed with its byte of the sequence
  when `Cfg_Scramble` is set; a K-code (EOP, EEP, Fill) is kept.
- CRC unit: `olo_base_crc` (32-bit input, CRC-16 settings of `ofb_pkg`, `Out_Ready` tied high). It receives the SDF
  with `In_First`, the scrambled data words, and the EDF with `In_Last` and `In_Be = "0011"`. Its registered output is
  valid in the cycle after the EDF was taken, which is the cycle in which the EDF is in the output register.
  `Out_Crc(7:0)` is CRC_LS (character 2), `Out_Crc(15:8)` CRC_MS (character 3). While the EDF waits in the output
  register no word is taken, so `Out_Crc` stays valid.
- `Ctrl_Flush` clears `OutValid` and the frame state. In the multi-lane case the encoder of lane `i` is flushed on
  link reset and while lane `i` is not an active transmitting lane, so that no stale word is sent when the lane
  becomes active again.

### 2.4 ofb_ml_col_dec (ML-4)

One pipeline stage without back-pressure. The input word is unscrambled with the same scrambler as in the encoder
(enabled by `Cfg_Unscramble`); the CRC unit receives the received (scrambled) words exactly as in the encoder. In the
output register an EDF that ended a data frame is compared with `Out_Crc`; `Out_CrcErr` is set with an EDF when the
CRC differs or when the EDF did not end a data frame, and is 0 with all other words. `Ctrl_Flush` clears the frame
state. In the multi-lane case one decoder per lane sits before the alignment FIFO, so that each decoder sees the word
stream of its lane in order.

### 2.5 ofb_ml_lane_mgr (ML-1)

All outputs are registered unless noted. `Active(i)` is the decoded lane state of lane `i`.

| Signal | Value |
| --- | --- |
| `Bypass` | `N = 1`, or `Cfg_Bypass`, or `BypassFar`: register loaded with the inverted Multi-LaneCapable bit of every capability event of lane 0 |
| `Lane_NearCapability(i)` | Register per lane: `Dl_NearCapability` with the MultiLane bit = `N > 1 and not Cfg_Bypass`, held while lane `i` is in Connected (ML-LM-03) |
| `Enc_Scramble(i)` | Register per lane: DataScrambled bit of `Lane_NearCapability(i)` while lane `i` is not Active, held while it is Active |
| `Dec_Unscramble(i)` | DataScrambled bit of the far-end capability of lane `i` (the Lane layer keeps it) once lane `i` delivered a capability since it left ClearLine (`CapSeen(i)`); otherwise `FarScr`, the DataScrambled bit of the last capability event of any lane. A receive-only lane enters Active from Connected without waiting for INIT3 (ECSS 5.5.2.10e.3) and never delivers its own capability |
| `Lane_TxOnly(i)` | `TxEn(i) and not RxEn(i)` and lane `i` not in ClearLine (ML-LM-09) |
| `Lane_RxOnly(i)` | Set when `not TxEn(i) and RxEn(i)` and a bidirectional lane is Active; cleared when `TxEn(i)` or `not RxEn(i)` (ML-LM-10) |
| `Lane_FarEndActive(i)` | Loaded with bit `i` of the ACT field of every valid ACTIVE word (`Al_FarActValid`); cleared while lane `i` is in ClearLine (ML-LM-11) |
| `Lane_Reset(i)` | `Cond(i) or Hold(i)` (combinational OR): `Cond` = `Dl_LaneReset`, or Active and TxOnly without FarEndActive, or Active and TxOnly without an active bidirectional lane, or TxEn = RxEn = 0, or bypass and `i > 0`; `Hold(i)` keeps the request until lane `i` is in ClearLine (ML-LM-12) |
| `TxLanes` (T) | Active and TxEn (zero in bypass) |
| `DataLanes` (D) | The lowest `P` set bits of T, `P` = `Cfg_MaxDataLanes` (1 to N, other values N) |
| `HotLanes` (H) | T and not D |
| `RxLanes` | Active and RxEn (zero in bypass) |
| `NumTxLanes`, `NumRxLanes` | Number of set bits of T and of `RxLanes` (4 bits) |
| `ActLanes` | Active, for the ACT field and the alignment state machine |
| `Dl_FarCapability*` | Event of the lowest lane with a capability event in this cycle (in bypass lane 0 only), registered; `Dl_FarCapabilityIdle` = no lane was Active in the cycle of the event |
| `Dl_LaneActive` | At least one lane is Active |

### 2.6 ofb_ml_tx (ML-2)

Two-process design (record `r`). Inputs from ML-1 (T, D, H, `NumTxLanes`, `ActLanes`, `Bypass`) and the alignment
state from ML-5. `L` is the number of set bits of D; `Idx(i)` is the number of set bits of D below lane `i` (the
position of lane `i` in the sending row).

**Bypass.** `Enc_Data(0) = TxRow word 0`, `Enc_Valid(0) = TxRow_Valid`, `TxRow_Ready = Enc_Ready(0)`; no other lane is
driven. The Lane layer sends IDLE when there is no word.

**Sending rows.** `Advance` = T is not empty and every lane of T has `Enc_Ready`. `Enc_Valid(i) = T(i) and Advance`,
so all active transmitting lanes take a word in the same cycle or none does (lock-step; the Lane layers send SKIP in
the same cycle, ML-DS-05). The content of the row:

| Condition | Data-sending lanes D | Hot redundant lanes H |
| --- | --- | --- |
| Not Ready, `Slot < 7` | ACTIVE (ACT = `ActLanes`) | ACTIVE |
| Not Ready or Near-End Ready, `Slot = 7` | ALIGN (`NumTxLanes`, lane number) | ALIGN with LANES = iLANES = 0 |
| Near-End Ready (`Slot < 7`), Both-Ends Ready | gearbox row, or IDLE | PRBS word (`olo_base_prbs`, advanced per row) |

`Slot` counts the rows sent (modulo 8) in Not Ready and Near-End Ready and is 0 in Both-Ends Ready.

**Gearbox.** Registers `Q` (2N words with K flags), `Cnt` (0 to 2N), `Rep` (one replicated word), `RepValid`,
`RepIl` (the replicated word may pass waiting data words, `interleaved`). In a data slot with `Advance`:

| Priority | Condition | Row on D | Update |
| --- | --- | --- | --- |
| 1 | `Cnt >= L` | `Q(0)` to `Q(L-1)` | shift `Q` by L |
| 2 | `RepValid` and (`Cnt = 0` or `RepIl`) | `Rep` on every lane | `RepValid := 0` |
| 3 | `RepValid` and `0 < Cnt < L` | `Q(0)` to `Q(Cnt-1)`, PAD on the other lanes | `Cnt := 0` |
| 4 | otherwise | IDLE | none |

Rule 3 implements ML-DS-02: a word that ends a data frame waits until the incomplete sending row was sent with PAD
words. Rule 2 with `RepIl` lets FCT, ACK, NACK, FULL and broadcast words pass waiting data words (ML-DS-03).

`TxRow_Ready = AlignState /= NotReady and Cnt <= N and (not RepValid or Rep sent in this cycle)`. A replicated row
loads `Rep`; a data row appends its masked words (compacted, word 0 first) at `Cnt` after the shift of this cycle.
With `Cnt <= N` before the cycle there is always room for N more words (`Q` holds 2N words), and with L = N one row is
taken and one sent per cycle. Taking a row in the cycle in which `Rep` is sent avoids an IDLE row after every
replicated word (ECSS 5.6.4.5b); it makes `TxRow_Ready` depend on `Enc_Ready`. A data row taken behind `Rep` is
never sent before it: it enters `Q` only in the cycle in which `Rep` is sent.

`Q`, `Cnt` and `RepValid` are cleared on `Ctrl_Flush` (link reset), in bypass and in Not Ready (ML-DS-11).

**SKIP.** A free-running counter requests a SKIP (`Lane_SkipReq`, one cycle) every `SkipIntervalWords_g` cycles. All
Lane layers of a multi-lane link use this request (generic `SkipExternal_g` of `ofb_lane`).

### 2.7 ofb_ml_align (ML-5)

**Input stage (per lane, combinational on the decoder output).** For a word with `In_Valid(i)`:

| Flag | Condition |
| --- | --- |
| `IsAct` | ACTIVE word (`isActive`) |
| `AlCorrect` | ALIGN word with iLANES = not LANES (`alignCorrect`) |
| `AlHot` | ALIGN word with LANES = iLANES = 0 (`alignHot`) |
| `AlValid` | `AlCorrect`, #Lanes = `NumRxLanes`, lane number = `i` |

Per-lane registers: `PrevAct(i)`, `PrevActV(i)` (last ACTIVE value; cleared while lane `i` is not Active): an ACTIVE
word equal to `PrevAct(i)` with `PrevActV(i)` is a valid ACTIVE word. The lowest lane with a valid ACTIVE word loads
`FarAct` (16 bits) and pulses `FarActValid`; a value different from `FarAct` is a far-end change. `Recv(i)` (data-
receiving lane): set with `AlCorrect`, cleared with `AlHot`, cleared while lane `i` is not in `RxLanes`; lane 0 in
bypass. `Seen(i)`: an ALIGN word (correct or of a hot redundant lane) was received since lane `i` entered
`RxLanes`; the lanes count as aligned only when every lane of `RxLanes` has `Seen` set, so that a lane with a large
skew is not added to the data-receiving lanes after the alignment.

**Alignment FIFOs.** Per lane four registers (word, K flags, CRC error flag of the decoder, `AlValid`) with a count.
The FIFO is a register file inside the entity and not `olo_base_fifo_sync`: the alignment reads the head of every
FIFO in the cycle after the write and needs the exact fill level for the overflow rule of ECSS 5.6.6.4h; the two-cycle
latency and the delayed write level of the Open Logic FIFO would reduce the tolerated skew from three words to one.
A word is written when `In_Valid(i)` and the lane is a data-receiving lane after this word (`Recv(i)` updated with
this word). Writing to a full FIFO that is not read in the same cycle is an overflow: all FIFOs are flushed. A FIFO
is also flushed on link reset, when its lane enters the Active state and when `Recv(i)` falls.

**Row reading.** With R = `Recv`:

- `RowAvail` = R not empty and every FIFO of R holds a word.
- `AllAlign` = every head of R is a valid ALIGN word.
- `Pop(i)` = `RowAvail and R(i) and (AllAlign or not HeadAlValid(i))`.
- `Held` = `RowAvail and not AllAlign` and some head of R is a valid ALIGN word.

**Row classification** (on `RowAvail`, registered output to ML-6):

| Row | Not Ready | Near-End Ready, Both-Ends Ready |
| --- | --- | --- |
| `AllAlign` | Aligned := 1 when every lane of `RxLanes` has received an ALIGN word (`Seen`), not passed | not passed (alignment confirmed) |
| `Held` | not passed (alignment in progress) when not aligned; else Misaligned and RXERR | Misaligned and RXERR |
| Only ACTIVE and ALIGN words, all ACTIVE | ACTIVE received, not passed | ACTIVE received, not passed |
| Only ACTIVE and ALIGN words, not all ACTIVE | not passed | RXERR (ML-CO-03) |
| Contains an ACTIVE word, other words too | RXERR | RXERR, ACTIVE received |
| Contains an RXERR word | RXERR | RXERR |
| Data or PAD words with another control word | Misaligned, RXERR | Misaligned, RXERR |
| Data words (and PAD) | RXERR | data row: data words compacted in lane order, PAD removed |
| Only PAD words | not passed | not passed |
| Only control words | RXERR | control row: word of the lowest lane of R, CRC error = OR of the CRC error flags of R |

**Alignment state machine** (Figure 5-37):

| State | Exit | Next |
| --- | --- | --- |
| any | link reset | Not Ready |
| Not Ready | Aligned, `FarAct = ActLanes`, not Misaligned | Near-End Ready (4 us timer loaded) |
| Near-End Ready | Misaligned | Not Ready |
| Near-End Ready | data row with at least one data word passed | Both-Ends Ready |
| Both-Ends Ready | Misaligned | Not Ready |
| Both-Ends Ready | ACTIVE received | Near-End Ready (4 us timer loaded) |

Misaligned = `ActLanes` changed, or far-end change, or FIFO overflow, or a correct invalid ALIGN word on a lane of
`RxLanes`, or an invalid row, or `Held` after alignment, or R changed, or an RXERR passed in Near-End Ready while the
4 us timer runs. Misaligned clears Aligned (it wins over the aligned row of the same cycle). When Misaligned occurs
in Near-End Ready or Both-Ends Ready, one RXERR is passed (ML-CO-04).

The timer counts `ceil(4 us x ClkFrequency_g)` cycles.

### 2.8 ofb_ml_rx (ML-6)

**Bypass.** The decoder output of lane 0 is the row (word 0, mask `0..01`); PAD, ACTIVE and ALIGN are not passed
(`RxRow_Valid` cleared). Combinational, as with one lane.

**Multi-lane.** Two-process design with:

| Register | Function |
| --- | --- |
| `Fs` | Frame state: `None`, `Data` (data frame), `BcstIn` (broadcast frame in a data frame), `BcstOut` (broadcast frame outside a data frame), `Idle` (idle frame) |
| `Acc`, `AccCnt` | Data words of the data frame waiting for a complete row (up to 2N-1) |
| `Oq` | Output queue of 4 rows (data, K, mask, CRC error); its head drives `RxRow_*` |

Per row from ML-5:

| Row | Action | Frame state |
| --- | --- | --- |
| RXERR | flush `Acc` (partial row), push RXERR | `None` |
| SDF, SIF, RETRY, EDF | flush `Acc`, push the word (EDF with the CRC error flag) | `Data`, `Idle`, `None`, `None` |
| SBF | push | `BcstIn` from `Data`, else `BcstOut` |
| EBF | push | `Data` from `BcstIn`, else `None` |
| Other control word | push | unchanged |
| Data row in `BcstIn`, `BcstOut`, `Idle` | push word 0 only (ML-CO-05) | unchanged |
| Data row in `Data`, `None` | append the data words to `Acc`; push N words when `AccCnt >= N` | unchanged |

"Flush `Acc`" pushes the waiting words as one row with a partial mask. A row from ML-5 pushes at most two rows into
`Oq`; `Oq` drains one row per cycle. Between two flushes the number of rows pushed does not exceed the number of rows
received (a flush is only needed after a data row that pushed nothing), so two entries suffice; `Oq` has four, and
an overflow is reported by a simulation assertion.

### 2.9 Top level (`ofb_multilane`)

| Connection | `N = 1` | `N > 1` |
| --- | --- | --- |
| Transmit | `TxRow` word 0 to encoder 0 | `ofb_ml_tx`, encoder `i` flushed on link reset and while lane `i` is not in T (not in bypass) |
| Receive | decoder 0 to the bypass of `ofb_ml_rx` (inline) | decoders to `ofb_ml_align` and to the bypass input of `ofb_ml_rx` |
| `Lane_SkipReq` | from `ofb_ml_tx` | from `ofb_ml_tx` |
| `Stat_DataSendingLanes` | lane 0 Active | D (bypass: lane 0 Active) |
| `Stat_DataReceivingLanes` | lane 0 Active | R (bypass: lane 0 Active) |
| `Stat_AlignState` | Both-Ends Ready while lane 0 is Active, else Not Ready | state of `ofb_ml_align` (bypass: as with `N = 1`) |

### 2.10 Bypass (ML-2, ML-6 with one lane)

- Transmit: word 0 of the row goes to the column encoder of lane 0; `TxRow_Mask` and `TxRow_Replicate` are not
  needed with one lane. The encoder output drives the lane.
- Receive: the column decoder output becomes the row (`RxRow_Mask = "0..01"`); PAD, ACTIVE and ALIGN are discarded
  (`RxRow_Valid` cleared).

## 3. Top-level ports (`ofb_multilane`)

Vectors of lanes or row words hold lane / word `i` at bits `(i+1)*w-1 downto i*w`.

| Port | Dir | Width | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | in | 1 | Lane clock, synchronous high-active reset |
| `TxRow_Data`, `TxRow_K` | in | 32N, 4N | Transmit row; word 0 is sent first (lowest lane) |
| `TxRow_Mask` | in | N | Valid words of a data frame row (word 0 upwards) |
| `TxRow_Replicate` | in | 1 | Word 0 is replicated over all data-sending lanes (control words, broadcast and idle frame words) |
| `TxRow_Valid` / `TxRow_Ready` | in / out | 1 | Handshake |
| `RxRow_Data`, `RxRow_K`, `RxRow_Mask` | out | 32N, 4N, N | Received row |
| `RxRow_CrcErr` | out | 1 | With an EDF: the CRC-16 of at least one lane failed |
| `RxRow_Valid` | out | 1 | Row valid (no back-pressure) |
| `Dl_LinkReset` | in | 1 | Link reset: flush the transmit words, the alignment FIFOs and the frame state |
| `Dl_LaneReset` | in | 1 | LaneReset of all lanes |
| `Dl_NearCapability` | in | 8 | Near-end INIT3 capability (LinkReset flag, DataScrambled) |
| `Dl_FarCapability`, `Dl_FarCapabilityValid` | out | 8, 1 | Far-end capability and its event |
| `Dl_LaneActive` | out | 1 | At least one lane is Active |
| `Dl_FarCapabilityIdle` | out | 1 | With the capability event: no lane was Active |
| `Cfg_TxEn`, `Cfg_RxEn` | in | N | TxEn and RxEn per lane |
| `Cfg_MaxDataLanes` | in | 3 | Maximum number of data-sending lanes |
| `Cfg_Bypass` | in | 1 | Multi-Lane bypass |
| `LaneTx_Data`, `LaneTx_K` | out | 32N, 4N | Words to the Lane layers |
| `LaneTx_Valid` / `LaneTx_Ready` | out / in | N | Handshake per lane |
| `Lane_SkipReq` | out | 1 | SKIP request to all Lane layers |
| `LaneRx_Data`, `LaneRx_K`, `LaneRx_Valid` | in | 32N, 4N, N | Words from the Lane layers |
| `Lane_Reset`, `Lane_TxOnly`, `Lane_RxOnly`, `Lane_FarEndActive` | out | N | Lane control |
| `Lane_NearCapability` | out | 8N | Near-end capability per lane |
| `Lane_State` | in | 4N | Lane state (encoding of `ofb_lane_pkg`) |
| `Lane_FarCapability`, `Lane_FarCapabilityValid` | in | 8N, N | Far-end capability and its event per lane |
| `Stat_DataSendingLanes`, `Stat_DataReceivingLanes` | out | N | Lanes that send / receive data |
| `Stat_AlignState` | out | 2 | Alignment state: Not Ready 0, Near-End Ready 1, Both-Ends Ready 2 |
| `Stat_Bypass` | out | 1 | The bypass is selected |
| `Ev_Misaligned` | out | 1 | One-cycle event: the Misaligned condition occurred in Near-End Ready or Both-Ends Ready |

## 4. Configuration parameters

See the specification, section 4.

## 5. Timing and behaviour

- Transmit latency: one cycle from `TxRow_*` to `LaneTx_*` (column encoder) with one lane; one more cycle in the
  gearbox with several lanes.
- Receive latency: one cycle from `LaneRx_*` to `RxRow_*` (column decoder) with one lane; with several lanes the
  alignment FIFO (at least one cycle, plus the skew between the lanes), the row classification (one cycle) and the
  output queue of ML-6 (one cycle).
- Skew: the alignment FIFOs of four words absorb a skew of up to three words between the lanes (ECSS: typically one
  or two).

## 6. Open points

- The MIB registers for TxEn, RxEn, the maximum number of data-sending lanes and the bypass, and the data path of the
  Data Link layer for rows of N words, follow in the next steps of phase 4.
- With `N > 1` the bypass (lane 0 only) uses the gearbox and the concentrator with one lane, so that the Data Link
  layer always exchanges rows of N words; with `N = 1` the inline bypass of section 2.10 is used.
