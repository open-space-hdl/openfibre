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
| TA-1 | Lane test access | Later |

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-IF-01 | The configuration parameters of Table 5-36 for the Data Link, Multi-Lane, Lane and Physical layers shall be readable and writable through an AXI4-Lite slave. | 5.9.3a, b, 6.5 |
| MG-IF-02 | The status parameters of Table 5-37 shall be readable through the AXI4-Lite slave. | 5.9.4a, b |
| MG-CF-01 | The configuration parameters shall take the reset values of Table 5-36 on reset and on Interface Reset: DataScrambled set, Normalised Expected Broadcast Bandwidth 10 % (40 words per broadcast credit), LaneStart de-asserted, AutoStart asserted, LaneReset and parallel loopback de-asserted, Standby Reason 0, TxEn and RxEn asserted, maximum number of data-sending lanes `NumLanes_g`, Multi-Lane bypass de-asserted. | 5.9.3c, 5.7.9.2b, Table 5-36 |
| MG-VN-01 | The virtual network number (0 to 63) of every VC shall be readable and writable; the virtual network number of VC 0 shall be fixed to 0. | 5.8.3h, i, k, bb |
| MG-PL-01 | The near-end and far-end serial loopback enables of every lane (Physical layer parameters of Table 5-36, de-asserted after reset and Interface Reset) shall be readable and writable and passed to the Physical adapter of the lane (lane clock). | 5.4.1h, Table 5-36 |
| MG-ML-01 | The Multi-Lane parameters TxEn and RxEn (per lane), the maximum number of data-sending lanes and the bypass shall be passed to the Multi-Lane layer (lane clock), the maximum number of data-sending lanes also to the Data Link layer (core clock); the bypass state and the Misaligned events (counted) of the Multi-Lane layer shall be readable. | 5.6.1p, q, 5.6.3a, Tables 5-36, 5-37 |
| MG-CF-02 | Link Reset and Interface Reset shall be commands: a write of one sends one pulse to the Data Link layer. | 5.7.1j, Table 5-36 |
| MG-ST-01 | Error events shall set sticky flags, cleared by writing one; the Link Reset command shall clear the status of the Data Link layer (sticky flags and counters). | 5.9.4d, e |
| MG-ST-02 | The number of error recovery attempts shall be counted, and the CRC-16, CRC-8, frame and sequence errors and the lane timeouts in saturating counters; a write clears a counter. | 5.7.7.1k, l, Table 5-37 |
| MG-ST-03 | An interrupt output shall be asserted while a sticky flag enabled in the interrupt mask is set. | none (implementation) |
| MG-ED-01 | The SEC and DED events of every fault-tolerant buffer of the core shall be counted per channel (output VC buffers, error recovery buffer, frame buffer, input VC buffers, broadcast output and input buffers, transmit and receive row crossings, control crossings) in saturating 16-bit counters; a DED shall set a sticky flag of its channel, a SEC a common sticky flag. | none (fault tolerance, architecture P5) |
| MG-ED-02 | The counters of a selected channel shall be readable and clearable; the flags and all counters shall be clearable at once; the DED flags and the SEC flag shall be interrupt sources. | none |
| MG-ED-03 | A single or double bit error shall be injectable into the next word written into the buffers of a selected channel. | none (verification of the EDAC paths) |
| MG-CC-01 | Configuration levels shall cross to the core and lane clock domains with `olo_ft_cc_bits`, commands and events with `olo_ft_cc_pulse`, multi-bit status values with `olo_base_cc_status`. | none (architecture section 6) |

## 3. Register map

See the architecture, section 3.

## 4. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels |
| `NumLanes_g` | 1 | Number of lanes |

## 5. Interpretation of the standard

Bandwidth Credit Limit, FCT multiplier and data segment multiplier are fixed by generics (Table 5-36 allows this). The
Maximum Number of Data-Sending Lanes, RxEn and TxEn follow with phase 4. The virtual network number of a VC is a
configuration register only: a node has one end-point per VC (ECSS 5.8.3h, i).
