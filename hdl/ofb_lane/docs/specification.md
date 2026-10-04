# ofb_lane: Specification

## 1. Overview

`ofb_lane` is the Lane layer of OpenFibre for one lane (ECSS-E-ST-50-11C clause 5.5). It initialises the lane with
the far end, inserts and removes the lane control words, synchronises the received words, counts receive errors and
offers parallel loopback. Towards the Multi-Lane layer it passes words of 32 bits plus 4 K flags; towards the
Physical adapter it passes the decoded symbol stream (8B/10B encoding, symbol alignment and the receive elastic
buffer belong to the Physical adapter).

The module consists of four blocks of the architecture (section 7.5):

| Block | Entity | Function |
| --- | --- | --- |
| LN-1 | `ofb_lane_init` | Lane initialisation and standby state machine |
| LN-2 | `ofb_lane_tx` | Lane transmitter: INIT, STANDBY, LOST_SIGNAL, IDLE and SKIP words, PRBS during initialisation |
| LN-3 | `ofb_lane_rx` | Lane receiver: word synchronisation, receive synchronisation state machine, error words, lane control word detection, RXERR word counter |
| LN-4 | `ofb_lane_loopback` | Near-end and far-end parallel loopback |

`ofb_lane` connects them; all blocks run in one clock domain (`Clk` = lane clock, one word per clock cycle).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| LN-IF-01 | The Lane layer shall accept transmit words (32 bit, 4 K flags) from the Multi-Lane layer with a valid / ready handshake and pass received words with a valid strobe. | 5.5.1b to e |
| LN-IF-02 | The Lane layer shall accept LaneReset, TxOnly, RxOnly, FarEndActive and the near-end capability from the Multi-Lane layer and report the lane state and the far-end capability (as a one-cycle event) to it. | 5.5.1f to j |
| LN-IF-03 | The Lane layer shall pass one transmit word per clock cycle to the Physical adapter and receive one word of four decoded symbols per clock cycle with a valid flag, a K flag, a code error flag and a disparity error flag per symbol. | 5.5.1k, l |
| LN-IF-04 | The Lane layer shall control the Physical adapter with line driver enable, line receiver enable, CDR enable and invert RX polarity, and shall use its NoSignal indication. | 5.5.1m, n, 5.4.1d, e |
| LN-IF-05 | The Lane layer shall accept the management parameters LaneStart, AutoStart, LaneReset, parallel loopback and Standby Reason. | 5.5.1o, Table 5-36 |
| LN-IF-06 | The Lane layer shall provide the status Lane State, RXERR counter, RXERR overflow, far-end standby (with reason), timeout, far-end lost signal (with reason), far-end capabilities and RX polarity; events are one-cycle pulses, the MIB makes them sticky. | 5.5.1p, Table 5-37 |

### 2.2 Lane initialisation (LN-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LN-INIT-01 | The lane initialisation state machine shall implement the states ClearLine, Disabled, Wait, Started, InvertRxPolarity, Connecting, Connected, Active, PrepareStandby and LossOfSignal with the entry conditions, actions and exit conditions of the standard, exit conditions evaluated in the order given there. | 5.5.2.1, 5.5.2.4 to 5.5.2.13 |
| LN-INIT-02 | ClearLine shall last 2 us, disable the transmitter, receiver and CDR and switch off the receive bit inversion; it is entered on LaneReset from any state. | 5.5.2.4 |
| LN-INIT-03 | The initialisation timeout timer shall start on entry to Started, expire after the time to transmit 5000 words and be stopped in Active; its expiry in Started, InvertRxPolarity, Connecting or Connected moves to ClearLine and is reported as a timeout event. | 5.5.2.4a.2 to 5, 5.5.2.7b.1, 5.5.2.11b.1 |
| LN-INIT-04 | Started shall move to Connecting when FarEndActive is asserted or when 1023 words including at least one INIT1 or INIT2 are received without intervening RXERR, and to InvertRxPolarity on three iINIT1 or three iINIT2 without intervening RXERR. InvertRxPolarity shall invert the received bits. | 5.5.2.7f, 5.5.2.8 |
| LN-INIT-05 | Connecting shall move to Connected on RxOnly, FarEndActive, three INIT2 or three INIT3 with the same parameters, each without intervening RXERR. | 5.5.2.9f |
| LN-INIT-06 | Connected shall send INIT3 with the capability field, report the far-end capability once three INIT3 with the same capability are received without intervening RXERR, clear the RXERR word counter, and move to Active on RxOnly, on FarEndActive after at least one INIT3 was sent, or after three such INIT3 are received and at least three INIT3 are sent; a received comma K28.7 moves it to ClearLine. | 5.5.2.10b, e |
| LN-INIT-07 | In Active the lane shall pass words to and from the Multi-Lane layer, and leave Active on LaneReset, NoSignal (not TxOnly), RXERR counter reaching 255 (not TxOnly), INIT1 received (not RxOnly), LaneStart and AutoStart de-asserted, or three LOST_SIGNAL / STANDBY, in this order. | 5.5.2.11 |
| LN-INIT-08 | PrepareStandby shall send 32 STANDBY words, LossOfSignal 32 LOST_SIGNAL words with the LOS_Cause of the transition (0b00 NoSignal, 0b01 RXERR overflow, 0b10 INIT1), then move to ClearLine. | 5.5.2.12, 5.5.2.13, 5.3.3.10f |
| LN-INIT-09 | Three consecutive LOST_SIGNAL or three consecutive STANDBY words received in a state with the CDR enabled shall move to ClearLine. | 5.5.2.4a.7, 8 |
| LN-INIT-10 | Transmitter driver, receiver and CDR shall be enabled per state as specified, with the transmitter disabled when RxOnly and the receiver and CDR disabled when TxOnly. | 5.5.2.5b to 5.5.2.13d, Figure 5-29 |
| LN-INIT-11 | The INIT3 capability sent shall be the near-end capability with bit 1 (INIT3LaneStart) set to the LaneStart management parameter. | 5.3.3.8e, g |

### 2.3 Lane transmitter (LN-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LN-TX-01 | In Started and InvertRxPolarity the transmitter shall send INIT1 words, in Connecting INIT2 words, each optionally followed by up to 64 PRBS data words (generic), and in Connected INIT3 words. | 5.5.2.7b.4, e, 5.5.2.8b.4, e, 5.5.2.9b.3, e, 5.5.2.10b.3 |
| LN-TX-02 | In Active the transmitter shall send the words of the Multi-Lane layer and an IDLE word whenever no word is available. | 5.5.2.11b.4, 5.5.4a |
| LN-TX-03 | In Active a SKIP word shall be inserted every 5000 words; SKIP has the highest precedence and may be inserted within any frame. | 5.5.3d, 5.3.10c, d |
| LN-TX-04 | STANDBY words shall carry the configured Standby Reason, LOST_SIGNAL words the LOS_Cause in bits 1:0. | 5.3.3.9, 5.3.3.10 |
| LN-TX-05 | iINIT1 and iINIT2 shall never be generated. | 5.3.3.5e, 5.3.3.7e |

### 2.4 Lane receiver (LN-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LN-RX-01 | Words shall be formed of four symbols with the comma in the least significant position; when a comma occurs in another position the words shall be realigned and the current word set to RXERR. | 5.5.7a to i |
| LN-RX-02 | A symbol with a code or disparity error shall be set to K0.0, and a word containing such a symbol shall be set to RXERR together with the previous word. | 5.5.7j to l |
| LN-RX-03 | The receive synchronisation state machine shall implement LostSync, CheckSync and Ready; in LostSync all received words shall be replaced by RXERR. | 5.5.8 |
| LN-RX-04 | Lane control words (SKIP, IDLE, INIT1, INIT2, iINIT1, iINIT2, INIT3, STANDBY, LOST_SIGNAL) shall be detected, reported to LN-1 and not passed to the Multi-Lane layer. | 5.3.3, 5.5.2.11b.9, 5.5.4b |
| LN-RX-05 | The RXERR word counter shall count RXERR words received in Active, be decremented every 16384 words received, overflow (reported as event and to LN-1) when it reaches 255, and be cleared only on LaneReset and in the Connected state, so that an overflow stays visible in the status. | 5.5.2.2, 5.5.2.10b.7, 5.5.2.11b.6, 7, e.3 |
| LN-RX-06 | In Active, received data words, Multi-Lane and Data Link control words and RXERR words shall be passed up; a received LOST_SIGNAL, STANDBY or INIT1 shall be passed up as one RXERR word, and at least one RXERR word shall be passed up when Active is left. Outside Active no word shall be passed up. | 5.5.2.11b.5, b.8, e.7, 5.3.6e, f |
| LN-RX-07 | When the CDR or the receiver is disabled, the receive synchronisation state machine shall be in LostSync. | 5.5.8, 5.5.2.4c |

### 2.5 Parallel loopback (LN-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LN-LB-01 | When the near-end parallel loopback is enabled, the received words shall be replaced by the transmitted words. | 5.5.5c |
| LN-LB-02 | When the far-end parallel loopback is enabled, the transmitted words shall be replaced by the received words. | 5.5.5d |

## 3. Error conditions

| Condition | Reaction |
| --- | --- |
| Code or disparity error, word realignment | Affected words replaced by RXERR (LN-RX-01, LN-RX-02) |
| More than four error words in CheckSync | LostSync (LN-RX-03) |
| RXERR counter reaches 255 in Active | LossOfSignal with LOS_Cause 0b01, overflow event (LN-RX-05, LN-INIT-07) |
| Initialisation timeout | ClearLine, timeout event (LN-INIT-03) |

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `ClkFrequency_g` | 156.25e6 | Lane clock frequency in Hz (2 us ClearLine timer) |
| `InitTimeoutWords_g` | 5000 | Initialisation timeout in words |
| `InitPrbsWords_g` | 64 | PRBS data words after each INIT1 / INIT2 (0 to 64) |
| `SkipIntervalWords_g` | 5000 | Words between two SKIP words in Active |
| `RxErrLeakWords_g` | 16384 | Received words per decrement of the RXERR counter (15000 to 16384) |

One word per clock cycle (`WordsPerCycle_g` = 2 of the architecture is not implemented yet).
