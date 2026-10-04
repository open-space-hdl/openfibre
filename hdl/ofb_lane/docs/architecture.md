# ofb_lane: Architecture and Design Description

## 1. Block diagram

```text
                 Multi-Lane layer (words, lane control)                 MIB (cfg / status)
          TxWord_*  |  ^ RxWord_*          Ctrl_*  |  ^                    |  ^
                    v  |                           v  |                    v  |
   +----------------------------------------------------------------------------------+
   | ofb_lane                                                                         |
   |   +-------------+   Tx mode, capability,  +------------------+                   |
   |   | ofb_lane_tx |<------------------------| ofb_lane_init    |<-- Cfg_*, Ctrl_*  |
   |   |   (LN-2)    |----- sent events ------>|   (LN-1)         |--> Stat_*, Ctrl_* |
   |   +-------------+                          +------------------+                  |
   |          |                     rx events ^   | active, clear, sync reset         |
   |          |   +--------------------+       |   v                                  |
   |          |   | ofb_lane_rx (LN-3) |-------+   RXERR counter                      |
   |          |   +--------------------+-------------------------------> RxWord_*      |
   |          v              ^                                                        |
   |   +---------------------------------+                                            |
   |   | ofb_lane_loopback (LN-4)        |  near-end: RX := TX, far-end: TX := RX      |
   |   +---------------------------------+                                            |
   +----------------------------------------------------------------------------------+
                    |  ^            ^ Phy_NoSignal    | Phy_TxEnable, RxEnable, CdrEnable, RxInvert
          PhyTx_*   v  | PhyRx_*    |                 v
                 Physical adapter (symbol stream: 4 characters + K + code / disparity error flags)
```

All blocks run on `Clk` (lane clock) with one word per clock cycle and the synchronous high-active `Rst`.

## 2. Sub-block descriptions

### 2.1 ofb_lane_init (LN-1)

Two-process FSM with the ten states of ECSS Figure 5-29 (`LaneStateFsm_t`). The record holds:

| Register | Function |
| --- | --- |
| `State` | Current state |
| `TimerCnt` | ClearLine 2 us timer, cycles = ceil(2 us * `ClkFrequency_g`) |
| `TimeoutCnt`, `TimeoutRun` | Initialisation timeout: started on entry to Started, stopped in Active, expires after `InitTimeoutWords_g` words |
| `WordCnt`, `SeenInit` | Words received since the last RXERR in Started / InvertRxPolarity, and whether an INIT1 or INIT2 was among them (1023 words rule) |
| `InvInit1Cnt`, `InvInit2Cnt` | iINIT1 / iINIT2 received without intervening RXERR |
| `Init2Cnt` | INIT2 received without intervening RXERR |
| `Init3Cnt`, `Init3Cap` | INIT3 with the same capability received without intervening RXERR, and that capability |
| `LostCnt`, `StbyCnt` | Consecutive LOST_SIGNAL / STANDBY words (SKIP words are transparent, any other word restarts the count) |
| `Init3Sent`, `SentCnt` | INIT3 words sent in Connected (0 to 3), STANDBY / LOST_SIGNAL words sent (0 to 32) |
| `RxInvert` | Receive bit inversion: set on entry to InvertRxPolarity, cleared in ClearLine |
| `LosCause` | LOS_Cause of the transition to LossOfSignal |
| `FarCap` | Far-end capability of the last three identical INIT3 |

Counter rules: every reception counter is cleared on an RXERR word. `WordCnt`, `SeenInit`, `InvInit*Cnt` restart on
entry to Started and to InvertRxPolarity, `Init2Cnt` on entry to Connecting, `Init3Cnt` on entry to any state other
than Connected (so that INIT3 counted in Connecting remain valid in Connected), `Init3Sent` and `SentCnt` on every
state change. A counter sees the event of the current word in the same cycle, so the transition happens with the
word that completes a condition (no further word is evaluated in the old state).

Output per state (LN-INIT-10):

| State | Phy_TxEnable | Phy_RxEnable | Phy_CdrEnable | Tx mode |
| --- | --- | --- | --- | --- |
| ClearLine, Disabled | 0 | 0 | 0 | Off |
| Wait | 0 | not TxOnly | 0 | Off |
| Started, InvertRxPolarity | not RxOnly | not TxOnly | not TxOnly | Init1 |
| Connecting | not RxOnly | not TxOnly | not TxOnly | Init2 |
| Connected | not RxOnly | not TxOnly | not TxOnly | Init3 |
| Active | not RxOnly | not TxOnly | not TxOnly | Active |
| PrepareStandby | not RxOnly | not TxOnly | not TxOnly | Standby |
| LossOfSignal | not RxOnly | not TxOnly | not TxOnly | LostSignal |

The RXERR counter of LN-3 is cleared while the state is Connected or LaneReset is asserted. Clearing it on the
transition out of Active would lose the overflow indication and the LOS_Cause.

### 2.2 ofb_lane_tx (LN-2)

Registered word multiplexer controlled by the Tx mode of LN-1:

| Mode | Words sent |
| --- | --- |
| Off | IDLE (the driver is disabled) |
| Init1, Init2 | INIT1 / INIT2 followed by `InitPrbsWords_g` PRBS data words, repeated; a mode change restarts with the INIT word |
| Init3 | INIT3 with the capability of LN-1 |
| Active | SKIP every `SkipIntervalWords_g` words (with `SkipExternal_g`: in the cycle of `Ctrl_SkipReq`), otherwise the word of the Multi-Lane layer, otherwise IDLE |
| Standby | STANDBY with the configured Standby Reason |
| LostSignal | LOST_SIGNAL with the LOS_Cause of LN-1 |

The PRBS words come from `olo_base_prbs` with the ECSS polynomial settings of `ofb_pkg` (32 bits per word).
`In_Ready` is asserted in Active when no SKIP is due. One-cycle events report each INIT3, STANDBY and LOST_SIGNAL
word sent.

### 2.3 ofb_lane_rx (LN-3)

Pipeline of four stages:

1. Input register (`In_*`, symbols with a code or disparity error become K0.0).
2. Word alignment: the aligned word is taken from the previous and the current input word starting at `Offset`.
   A comma (K28.5 or K28.7 with K flag) in the current input word at a position different from `Offset` is a word
   realignment: `Offset` takes the comma position and the aligned word of this cycle becomes RXERR.
3. Receive synchronisation state machine (LostSync, CheckSync, Ready, ECSS Figure 5-30) and error rule: a word
   with a K0.0 symbol becomes RXERR together with the previous word, which is held in this stage for one cycle.
   In LostSync every word is RXERR.
4. Decoding and output: lane control words are recognised by exact comparison with `ofb_pkg` (INIT3, STANDBY and
   LOST_SIGNAL by their first three characters), reported as one-cycle events and filtered. In Active the other
   words are passed up; INIT1, STANDBY and LOST_SIGNAL are passed up as RXERR, and one RXERR is passed up in the
   cycle after Active is left.

RXERR word counter: 8-bit saturating counter, incremented for every RXERR word in Active, decremented (when not
zero) every `RxErrLeakWords_g` words received in Active; an increment and a decrement in the same word cancel. When it
reaches 255 the overflow flag is set and an overflow event is pulsed. Counter and flag are cleared only by the clear
input of LN-1.

### 2.4 ofb_lane_loopback (LN-4)

Combinational multiplexers between LN-2, LN-3 and the Physical adapter. Near-end loopback: LN-3 receives the words
of LN-2 (no error flags, always valid). Far-end loopback: the Physical adapter transmits the received words (IDLE
when no valid word is received). While the near-end loopback is enabled `ofb_lane` forces NoSignal to 0 for LN-1,
because the line is not used.

## 3. Top-level ports (`ofb_lane`)

| Port | Dir | Width | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | in | 1 | Lane clock, synchronous high-active reset |
| `TxWord_Data`, `TxWord_K` | in | 32, 4 | Transmit word from the Multi-Lane layer |
| `TxWord_Valid` / `TxWord_Ready` | in / out | 1 | Handshake (ready only in Active) |
| `RxWord_Data`, `RxWord_K`, `RxWord_Valid` | out | 32, 4, 1 | Received word to the Multi-Lane layer (no back-pressure) |
| `Ctrl_LaneReset`, `Ctrl_TxOnly`, `Ctrl_RxOnly`, `Ctrl_FarEndActive` | in | 1 | Lane control from the Multi-Lane layer |
| `Ctrl_NearCapability` | in | 8 | INIT3 capability (bit 1 is replaced by LaneStart) |
| `Ctrl_State` | out | 4 | Lane state (encoding below) |
| `Ctrl_FarCapability`, `Ctrl_FarCapabilityValid` | out | 8, 1 | Far-end capability and its event (three identical INIT3) |
| `PhyTx_Data`, `PhyTx_K` | out | 32, 4 | Symbols to the Physical adapter, character 0 first |
| `PhyRx_Data`, `PhyRx_K`, `PhyRx_CodeErr`, `PhyRx_DispErr`, `PhyRx_Valid` | in | 32, 4, 4, 4, 1 | Decoded symbols from the Physical adapter |
| `Phy_TxEnable`, `Phy_RxEnable`, `Phy_CdrEnable`, `Phy_RxInvert` | out | 1 | Physical layer control |
| `Phy_NoSignal` | in | 1 | NoSignal, synchronous to `Clk` |
| `Cfg_LaneStart`, `Cfg_AutoStart`, `Cfg_LaneReset` | in | 1 | Management parameters |
| `Cfg_NearLoopback`, `Cfg_FarLoopback` | in | 1 | Parallel loopback |
| `Cfg_StandbyReason` | in | 8 | Standby Reason field sent in STANDBY |
| `Stat_State` | out | 4 | Lane state |
| `Stat_RxErrCount`, `Stat_RxErrOverflow` | out | 8, 1 | RXERR counter, overflow event |
| `Stat_Timeout` | out | 1 | Initialisation timeout event |
| `Stat_FarStandby`, `Stat_FarStandbyReason` | out | 1, 8 | STANDBY received event and its reason |
| `Stat_FarLostSignal`, `Stat_FarLostSignalReason` | out | 1, 8 | LOST_SIGNAL received event and its reason |
| `Stat_FarCapability` | out | 8 | Capability of the last INIT3 accepted |
| `Stat_RxPolarity` | out | 1 | Receive polarity inverted |

## 4. Configuration parameters

See the specification, section 4.

## 5. State machine encoding

`Stat_State` / `Ctrl_State` (constants `LaneState*_c` of `ofb_lane_pkg`): ClearLine 0, Disabled 1, Wait 2,
Started 3, InvertRxPolarity 4, Connecting 5, Connected 6, Active 7, PrepareStandby 8, LossOfSignal 9.

## 6. Data formats

Words and control words as in `ofb_pkg`: character 0 in bits 7:0 is sent first; K flag i belongs to character i.

## 7. Timing and behaviour

- Transmit latency LN-2: one cycle from `TxWord_*` to `PhyTx_*`.
- Receive latency LN-3: four cycles from `PhyRx_*` to `RxWord_*` (input, alignment, error hold, decode).
- The state machine reacts to a received word one cycle after it leaves LN-3 stage 4.

## 8. Open points

- `WordsPerCycle_g` = 2 (two words per clock, for SerDes with 64-bit interfaces) is not implemented.
- Safe FSM encoding attributes are added in the hardening phase.
