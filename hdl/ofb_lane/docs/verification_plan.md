# ofb_lane: Verification Plan

## 1. Overview

The Lane layer is verified on two levels: unit testbenches for the initialisation state machine, the receiver and
the transmitter, which reach every state and exit condition directly, and a layer testbench in which two lane ends
initialise and exchange words through a behavioural Physical adapter model with 8B/10B coding. All checks observe
ports only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_lane_tb` | `ofb_lane_th` | Two `ofb_lane` (A, B), `ofb_tb_pa_model` (8B/10B, cut, crossed pair, symbol offset, bit errors), AXI-Stream VVCs for the transmit words, monitors with scoreboard of the received words |
| `ofb_lane_init_tb` | `ofb_lane_init_th` | `ofb_lane_init`, events of LN-2 / LN-3 driven by the sequencer, timeout 5000 words |
| `ofb_lane_rx_tb` | `ofb_lane_rx_th` | `ofb_lane_rx`, symbol stream driven by the sequencer, log of the words passed up, RXERR leak every 64 words |
| `ofb_lane_tx_tb` | `ofb_lane_tx_th` | Two `ofb_lane_tx` (64 PRBS words and SKIP every 20 words; no PRBS words), AXI-Stream VVC, log of the transmitted words |
| `ofb_tb_8b10b_tb` | none | Self test of the 8B/10B package of the Physical adapter model |

Lane clock 156.25 MHz (6.25 Gbit/s with 32-bit words). Simulator: GHDL.

## 3. Test cases

### 3.1 Layer testbench (`ofb_lane_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_init_lanestart` (TC-LN-01) | Both ends with LaneStart reach Active; capabilities exchanged with the INIT3LaneStart flag | LN-INIT-01, LN-INIT-06, LN-INIT-11, LN-IF-02, LN-IF-06 |
| `test_init_autostart` (TC-LN-02) | An AutoStart end waits in Wait without signal and starts when the far end sends | LN-INIT-01, LN-IF-05 |
| `test_init_timeout` (TC-LN-03) | Without far end the initialisation times out repeatedly | LN-INIT-03, LN-IF-06 |
| `test_data_transfer` (TC-LN-04) | 3000 random words in each direction with random gaps: all received in order, no RXERR | LN-IF-01, LN-TX-02, LN-RX-04, LN-RX-06 |
| `test_skip_insertion` (TC-LN-05) | SKIP every 5000 words (4999 words between) during traffic | LN-TX-03 |
| `test_rx_polarity` (TC-LN-06) | Crossed pair: InvertRxPolarity, then Active and traffic | LN-INIT-04, LN-IF-04, LN-IF-06 |
| `test_word_alignment` (TC-LN-07) | Symbol offsets 1 and 3, realignment in Active | LN-RX-01 |
| `test_bit_errors` (TC-LN-08) | 10 bit errors: RXERR words passed up and counted, lane stays Active | LN-RX-02, LN-RX-05 |
| `test_rxerr_overflow` (TC-LN-09) | RXERR counter overflow: LossOfSignal, LOS_Cause 0b01 at the far end, counter stays 255 until Connected, recovery | LN-RX-05, LN-INIT-07, LN-INIT-08, LN-TX-04 |
| `test_standby` (TC-LN-10) | LaneStart and AutoStart de-asserted: PrepareStandby, STANDBY with reason, far end leaves Active | LN-INIT-08, LN-INIT-09, LN-TX-04, LN-IF-05 |
| `test_loss_of_signal` (TC-LN-11) | Cut cable: LossOfSignal, LOST_SIGNAL with LOS_Cause 0b00, RXERR passed up, recovery | LN-INIT-07 to 09, LN-RX-06 |
| `test_lane_reset` (TC-LN-12) | LaneReset restarts the lane, both ends Active again | LN-INIT-02, LN-IF-05 |
| `test_near_loopback` (TC-LN-13) | Near-end parallel loopback: the lane initialises with itself and returns the words | LN-LB-01 |
| `test_far_loopback` (TC-LN-14) | Far-end parallel loopback at B: A initialises with itself and receives its words | LN-LB-02 |

### 3.2 Unit testbench of LN-1 (`ofb_lane_init_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_clearline` (TC-LN-20) | ClearLine lasts 2 us with transmitter, receiver and CDR disabled | LN-INIT-02, LN-INIT-10 |
| `test_wait` (TC-LN-21) | Disabled, Wait (NoSignal detection only), Started on a signal | LN-INIT-01, LN-INIT-10 |
| `test_started_1023` (TC-LN-22) | 1023 words with INIT1 or INIT2, RXERR restarts the count | LN-INIT-04 |
| `test_invert_polarity` (TC-LN-23) | Three iINIT1, RXERR in between, NoSignal and inversion reset in ClearLine | LN-INIT-02, LN-INIT-04 |
| `test_far_end_active` (TC-LN-24) | FarEndActive through Connecting and Connected, Active after one INIT3 sent | LN-INIT-04 to 06 |
| `test_rxonly` (TC-LN-25) | RxOnly: transmitter disabled, Connected and Active on RxOnly, INIT1 ignored | LN-INIT-05 to 07, LN-INIT-10 |
| `test_txonly` (TC-LN-26) | TxOnly: receiver and CDR disabled, NoSignal and overflow ignored | LN-INIT-07, LN-INIT-10 |
| `test_connected_comma` (TC-LN-27) | K28.7 in Connected: ClearLine | LN-INIT-06 |
| `test_init3` (TC-LN-28) | Three identical INIT3 without RXERR, capability event and value | LN-INIT-06, LN-INIT-11 |
| `test_active_exits` (TC-LN-29) | Order NoSignal before overflow, LOS_Cause 0b00 / 0b01 / 0b10, 32 LOST_SIGNAL, no counter clear in LossOfSignal | LN-INIT-07, LN-INIT-08 |
| `test_standby_and_stop` (TC-LN-30) | 32 STANDBY in PrepareStandby; three consecutive LOST_SIGNAL with SKIP transparent | LN-INIT-08, LN-INIT-09 |
| `test_timeout` (TC-LN-31) | Timeout in Started and in Connected, one event | LN-INIT-03 |
| `test_errclear` (TC-LN-32) | RXERR counter clear only in Connected and on LaneReset | LN-RX-05, LN-INIT-06 |

### 3.3 Unit testbench of LN-3 (`ofb_lane_rx_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_alignment` (TC-LN-40) | Words aligned for symbol offsets 0 to 3 | LN-RX-01 |
| `test_realignment` (TC-LN-41) | Realigned word RXERR, words after the next comma correct | LN-RX-01 |
| `test_error_rule` (TC-LN-42) | Symbol error: its word and the previous word RXERR, exact output sequence | LN-RX-02 |
| `test_lost_sync` (TC-LN-43) | Five error words: LostSync, all words RXERR until a comma | LN-RX-03 |
| `test_lane_words` (TC-LN-44) | Detection of all lane control words, filtering, INIT1 / STANDBY / LOST_SIGNAL as RXERR, nothing outside Active | LN-RX-04, LN-RX-06 |
| `test_rxerr_counter` (TC-LN-45) | Increment, leak, saturation and overflow, kept outside Active, clear | LN-RX-05 |
| `test_active_exit` (TC-LN-46) | One RXERR when Active is left | LN-RX-06 |
| `test_sync_reset` (TC-LN-47) | LaneReset / CDR disabled: LostSync, earlier words discarded | LN-RX-03, LN-RX-07 |

### 3.4 Unit testbench of LN-2 (`ofb_lane_tx_tb`)

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_init_prbs` (TC-LN-50) | INIT1 followed by 64 PRBS words of the ECSS sequence, repeated; mode change starts with INIT2 | LN-TX-01 |
| `test_init_words` (TC-LN-51) | Without PRBS words only INIT1; INIT3 with capability and events | LN-TX-01 |
| `test_active` (TC-LN-52) | 200 words with random gaps in order, IDLE in the gaps, SKIP exactly every 20 words | LN-TX-02, LN-TX-03, LN-IF-01 |
| `test_standby_lost_signal` (TC-LN-53) | STANDBY with reason, LOST_SIGNAL with LOS_Cause, events, IDLE when off | LN-TX-04 |

## 4. Coverage analysis

Every requirement of the specification is covered by at least one test case. LN-TX-05 (no iINIT generated) is
verified by inspection: the transmitter has no path that selects an inverse INIT word. LN-TX-06 (SKIP on request of
the Multi-Lane layer) is verified with the multi-lane link testbench (`ofb_ml_link_tb`, TC-ML-31: SKIP on all lanes
in the same cycle).

## 5. Functional coverage plan

The random traffic of TC-LN-04 covers data words, words with EOP and Data Link control words in both directions.
Functional coverage bins are added with the Multi-Lane and Data Link layer benches, where the traffic mix matters.
