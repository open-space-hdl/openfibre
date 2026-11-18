# ofb_mib: Specification

## 1. Overview

`ofb_mib` is the Management Information Base of OpenFibre (ECSS-E-ST-50-11C clause 5.9 and 6.5): the configuration
and status parameters of all layers in a register file with an AXI4-Lite port, sticky error flags, event counters and
an interrupt. It contains the crossings between the management clock and the clock domains of the layers.

| Block | Function | State |
| --- | --- | --- |
| MG-1 | Register file, AXI4-Lite access, configuration and status crossings | Complete for 1 to 4 lanes |
| MG-2 | Sticky error flags, event counters, interrupt | Complete for the events of phase 2 |
| MG-3 | EDAC monitor | Complete |
| MG-4 | Reset per clock domain | In `ofb_core` |
| MG-5 | PRBS test of the Physical adapters (bit error rate) | Complete |

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-IF-01 | The configuration parameters of Table 5-36 for the Data Link, Multi-Lane, Lane and Physical layers shall be readable and writable through an AXI4-Lite slave. | 5.9.3a, b, 6.5 |
| MG-IF-02 | The status parameters of Table 5-37 shall be readable through the AXI4-Lite slave. | 5.9.4a, b |
| MG-CF-01 | The configuration parameters shall take the reset values of Table 5-36 on reset and on Interface Reset: DataScrambled set, Normalised Expected Broadcast Bandwidth 10 % (40 words per broadcast credit), LaneStart de-asserted, AutoStart asserted, LaneReset and parallel loopback de-asserted, Standby Reason 0, TxEn and RxEn asserted, maximum number of data-sending lanes `NumLanes_g`, Multi-Lane bypass de-asserted. | 5.9.3c, 5.7.9.2b, Table 5-36 |
| MG-VN-01 | The virtual network number (0 to 63) of every VC shall be readable and writable; the virtual network number of VC 0 shall be fixed to 0. | 5.8.3h, i, k, bb |
| MG-PL-01 | The near-end and far-end serial loopback enables of every lane (Physical layer parameters of Table 5-36, de-asserted after reset and Interface Reset) shall be readable and writable and passed to the Physical adapter of the lane (lane clock). | 5.4.1h, Table 5-36 |
| MG-PL-02 | The bit synchronisation status of the clock and data recovery of every lane (input from the Physical adapter, lane clock) shall be readable. | 5.4.2e |
| MG-ML-01 | The Multi-Lane parameters TxEn and RxEn (per lane), the maximum number of data-sending lanes and the bypass shall be passed to the Multi-Lane layer (lane clock), the maximum number of data-sending lanes also to the Data Link layer (core clock); the bypass state and the Misaligned events (counted) of the Multi-Lane layer shall be readable. | 5.6.1p, q, 5.6.3a, Tables 5-36, 5-37 |
| MG-CF-02 | Link Reset and Interface Reset shall be commands: a write of one sends one pulse to the Data Link layer. | 5.7.1j, Table 5-36 |
| MG-CF-03 | The reset values of LaneStart and AutoStart of every lane shall be the generics `LaneStart_g` (default false) and `AutoStart_g` (default true), on reset and on Interface Reset; the defaults are the reset values of MG-CF-01. | 5.9.3c, 5.5.2.5, Table 5-36 |
| MG-ST-01 | Error events shall set sticky flags, cleared by writing one; the Link Reset command shall clear the status of the Data Link, Multi-Lane and Lane layers (sticky flags and counters); the EDAC status shall be kept. | 5.9.4d, e |
| MG-ST-02 | The number of error recovery attempts shall be counted, and the CRC-16, CRC-8, frame and sequence errors and the lane timeouts in saturating counters; a write clears a counter. | 5.7.7.1k, l, Table 5-37 |
| MG-ST-07 | The expiries of the alignment watchdog of the Multi-Lane layer (`Ml_EvAlignTimeout`, lane clock, ML-AL-11) shall be counted in a saturating counter (ML_ALIGN_TIMEOUTS); a write and the Link Reset command clear it. | none (extension, ML-AL-11) |
| MG-ST-04 | A receive row lost in the crossing to the core clock (`Ml_EvRxOverflow`, lane clock) shall set a sticky flag with interrupt. | 5.9.4c |
| MG-ST-03 | An interrupt output shall be asserted while a sticky flag enabled in the interrupt mask is set. | none (implementation) |
| MG-ST-05 | The receive framing errors of the Network interface (user clock) shall set a sticky flag per VC and a common sticky flag with interrupt; the received packets of zero length discarded by the Network interface shall be counted in a saturating 16-bit counter without losing events of consecutive cycles or of several VCs in one cycle; a write and the Link Reset command shall clear the counter. | 5.9.4a, c, d, e, 5.3.9h |
| MG-ST-06 | The transmitter ready level of the Physical adapter (`Phy_TxReady`, synchronised to the management clock, CORE-PL-04) shall be readable (DL_STATUS bit 9, TX_READY), and its fall after it was 1 since the reset shall set a sticky flag with interrupt (DL_ERRORS bit 12, TX_LOST), also while the core and lane clocks stand still. | 5.9.4c |
| MG-ED-01 | The SEC and DED events of every fault-tolerant buffer of the core shall be counted per channel (output VC buffers, error recovery buffer, frame buffer, input VC buffers, broadcast output and input buffers, transmit and receive row crossings, control crossings) in saturating 16-bit counters; a DED shall set a sticky flag of its channel, a SEC a common sticky flag. | none (fault tolerance, architecture P5) |
| MG-ED-02 | The counters of a selected channel shall be readable and clearable; the flags and all counters shall be clearable at once; the DED flags and the SEC flag shall be interrupt sources. | none |
| MG-ED-03 | A single or double bit error shall be injectable into the next word written into the buffers of a selected channel. | none (verification of the EDAC paths) |
| MG-PR-01 | The transmitted and the checked PRBS pattern of every lane (4 bits each, 0 off, transceiver encoding) and a hold bit shall be readable and writable (reset and Interface Reset: 0) and passed to the Physical adapter of the lane (lane clock). | none (test function) |
| MG-PR-02 | Count reset and force error shall be commands per lane: a write of one sends one pulse to the Physical adapter (lane clock); the count reset also clears the PRBS counters of the lane. | none (test function) |
| MG-PR-03 | While the checker of a lane is on and not held, the lane clock cycles (checked words) shall be counted in a 48-bit counter and the cycles with a checker error (words with at least one bit error) in a 32-bit counter, both saturating; the error counter and bits 47:16 of the word counter and the lock status of the checker shall be readable. | none (test function) |
| MG-PA-01 | The initialisation timeout of the lanes (LANE_INIT_TIMEOUT, 24 bits, words) shall be readable and writable, with the generic `InitTimeoutWords_g` (default 5000, the value of the standard) as reset value on reset and on Interface Reset, and passed to the lanes (lane clock). | 5.5.2.6b.1 |
| MG-PA-02 | The control of the Physical adapters (PA_CTRL: receiver reset on disconnection, CDR-only receiver reset, CDR hold during electrical idle, PCSRSVDIN; reset values 1, 0, 1, 0x0360 on reset and on Interface Reset) shall be readable and writable and passed to the adapters as static levels from registers of the management clock (the adapter synchronises them; a crossing into the lane clock would clear them during every transmitter reset). A receiver reset command per lane (LANE_CTRL RX_RESET, a write of one, reads as zero) shall send one pulse to the adapter (lane clock). | none (implementation) |
| MG-PA-03 | The receiver reset status of every lane (LANE_STATUS: RX_RESET_DONE, RX_RESET_BUSY, CDR_LOCK, RX_ELEC_IDLE) shall be readable. A receive or transmit buffer error of the adapter (the rising edge of its level), a completed receiver reset and a receiver reset timeout shall set sticky flags (LANE_EVENTS bits 4 to 7, interrupt mask bits 20 to 23). The completed receiver resets shall be counted in a saturating counter (LANE_TIMEOUT_COUNT bits 31:16, RX_RESETS), cleared together with the timeout count by a write and by the Link Reset command. | none (implementation) |
| MG-CC-01 | Configuration levels shall cross to the core and lane clock domains with `olo_base_cc_bits`, commands and events with `ofb_cc_pulse`, multi-bit status values with `olo_base_cc_status`, all with triplicated synchronisers; the control of the Physical adapters is passed without a crossing (MG-PA-02). | none (architecture section 6) |
| MG-CC-02 | The flags of bandwidth use (VC_BW_OVER, VC_BW_UNDER) shall be set only from status values that the status crossing of the core clock domain has transferred since the end of its reset, also when the core clock starts long after the reset (a transmit clock of a transceiver that runs only after its power-up): before that they keep their reset value 0. | 5.9.4a, b |

## 3. Register map

See the architecture, section 3.

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels |
| `NumLanes_g` | 1 | Number of lanes |
| `LaneStart_g` | false | Reset value of LaneStart of every lane (LANE_CTRL bit 0) |
| `AutoStart_g` | true | Reset value of AutoStart of every lane (LANE_CTRL bit 1) |

## 5. Interpretation of the standard

Bandwidth Credit Limit, FCT multiplier and data segment multiplier are fixed by generics (Table 5-36 allows this).

The reset values of LaneStart and AutoStart are generics (MG-CF-03). Their defaults are the reset values of Table
5-36; another value acts as a management write right after the reset. It lets a node whose MIB can only be reached
over its own link start that link.

The Link Reset command clears all status parameters of Table 5-37 held in the MIB (5.9.4e): the Data Link flags and
counters, the flags of bandwidth use, the lane event flags and the additional counters (lane timeouts, Misaligned
conditions, expiries of the alignment watchdog). The RXERR counter of a lane is cleared by the LaneReset that the link
reset asserts. The EDAC status describes the memories, not the link, and is kept. The virtual network number of a VC is
a configuration register only: a node has one end-point per VC (ECSS 5.8.3h, i).
