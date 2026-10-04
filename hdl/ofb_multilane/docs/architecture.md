# ofb_multilane: Architecture and Design Description

## 1. Block diagram

```text
          Data Link layer (rows)                              Data Link control          MIB status
     TxRow_*  |                  ^ RxRow_*        Dl_LaneReset, Dl_NearCapability  |  ^ Dl_Far*, Dl_LaneActive
              v                  |                                                  v  |
   +---------------------------------------------------------------------------------------------+
   | ofb_multilane                                                                               |
   |   +-------------------+   +-------------------+        +-------------------------------+    |
   |   | ML-2 distributor  |   | ML-6 concentrator |        | ofb_ml_lane_mgr (ML-1)        |    |
   |   | (bypass: word 0)  |   | (bypass: drop ML  |        | lane control, capabilities,   |--> Stat_*
   |   +-------------------+   |  control words)   |        | scramble enables, status      |    |
   |        | per lane         +-------------------+        +-------------------------------+    |
   |        v                          ^ per lane                  |  ^                          |
   |   +----------------+      +----------------+                  |  |                          |
   |   | ofb_ml_col_enc |      | ofb_ml_col_dec |                  |  |                          |
   |   | (ML-3)         |      | (ML-4)         |                  |  |                          |
   |   +----------------+      +----------------+                  |  |                          |
   +--------|-----------------------^-------------------------------|--|--------------------------+
            v LaneTx_*              | LaneRx_*                      v  | Lane_* control / state
                               Lane layers (one per lane)
```

All blocks run on `Clk` (lane clock) with the synchronous high-active `Rst`. ML-5 (alignment) and the multi-lane
functions of ML-2 and ML-6 are added in phase 4; with `NumLanes_g = 1` ML-2 and ML-6 reduce to the bypass below
(decision D1 of the core architecture).

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
- `Ctrl_Flush` (link reset) clears `OutValid` and the frame state.

### 2.4 ofb_ml_col_dec (ML-4)

One pipeline stage without back-pressure. The input word is unscrambled with the same scrambler as in the encoder
(enabled by `Cfg_Unscramble`); the CRC unit receives the received (scrambled) words exactly as in the encoder. In the
output register an EDF that ended a data frame is compared with `Out_Crc`; `Out_CrcErr` is set with an EDF when the
CRC differs or when the EDF did not end a data frame, and is 0 with all other words. `Ctrl_Flush` clears the frame
state.

### 2.5 ofb_ml_lane_mgr (ML-1), single lane

| Output | Value |
| --- | --- |
| `Lane_Reset` | `Dl_LaneReset` |
| `Lane_TxOnly`, `Lane_RxOnly`, `Lane_FarEndActive` | 0 |
| `Lane_NearCapability` | `Dl_NearCapability` with the MultiLane bit (3) cleared |
| `Dl_FarCapability`, `Dl_FarCapabilityValid` | Far-end capability value and event of lane 0 |
| `Dl_LaneActive` | Lane 0 is Active |
| `Enc_Scramble` | Register: follows the DataScrambled bit of `Dl_NearCapability` while lane 0 is not Active, held while it is Active |
| `Dec_Unscramble` | DataScrambled bit of the far-end capability of lane 0 (the Lane layer keeps it) |
| `Stat_DataSendingLanes`, `Stat_DataReceivingLanes` | Lane 0 is Active |
| `Stat_AlignState` | Both-Ends Ready while lane 0 is Active, else Not Ready |

### 2.6 Bypass (ML-2, ML-6 with one lane)

- Transmit: word 0 of the row goes to the column encoder of lane 0; `TxRow_Mask` and `TxRow_Replicate` are not
  needed with one lane. The encoder output drives the lane.
- Receive: the column decoder output becomes the row (`RxRow_Mask = "1"`); PAD, ACTIVE and ALIGN are discarded
  (`RxRow_Valid` cleared).

## 3. Top-level ports (`ofb_multilane`)

`N` = `NumLanes_g`. Vectors of lanes or row words hold lane / word `i` at bits `(i+1)*w-1 downto i*w`.

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
| `Dl_LinkReset` | in | 1 | Link reset: flush the transmit words and the frame state |
| `Dl_LaneReset` | in | 1 | LaneReset of all lanes |
| `Dl_NearCapability` | in | 8 | Near-end INIT3 capability (LinkReset flag, DataScrambled) |
| `Dl_FarCapability`, `Dl_FarCapabilityValid` | out | 8, 1 | Far-end capability and its event |
| `Dl_LaneActive` | out | 1 | At least one lane is Active |
| `LaneTx_Data`, `LaneTx_K` | out | 32N, 4N | Words to the Lane layers |
| `LaneTx_Valid` / `LaneTx_Ready` | out / in | N | Handshake per lane |
| `LaneRx_Data`, `LaneRx_K`, `LaneRx_Valid` | in | 32N, 4N, N | Words from the Lane layers |
| `Lane_Reset`, `Lane_TxOnly`, `Lane_RxOnly`, `Lane_FarEndActive` | out | N | Lane control |
| `Lane_NearCapability` | out | 8N | Near-end capability per lane |
| `Lane_State` | in | 4N | Lane state (encoding of `ofb_lane_pkg`) |
| `Lane_FarCapability`, `Lane_FarCapabilityValid` | in | 8N, N | Far-end capability and its event per lane |
| `Stat_DataSendingLanes`, `Stat_DataReceivingLanes` | out | N | Lanes that send / receive data |
| `Stat_AlignState` | out | 2 | Alignment state: Not Ready 0, Near-End Ready 1, Both-Ends Ready 2 |

## 4. Configuration parameters

See the specification, section 4.

## 5. Timing and behaviour

- Transmit latency: one cycle from `TxRow_*` to `LaneTx_*` (column encoder).
- Receive latency: one cycle from `LaneRx_*` to `RxRow_*` (column decoder).

## 6. Open points

- Phase 4: ML-2 and ML-6 for 2 to 4 lanes (rows, PAD, replication), ML-5 (alignment FIFOs, ACTIVE and ALIGN, alignment
  state machine), ML-1 for TxEn / RxEn, asymmetric links, unidirectional and hot redundant lanes. SKIP on all lanes at
  once (ECSS 5.6.4.5a) needs a SKIP request input of the Lane layer transmitter.
