# ofb_mib: Specification

## 1. Overview

`ofb_mib` is the Management Information Base of OpenFibre (ECSS-E-ST-50-11C clause 5.9 and 6.5): the configuration
and status parameters of all layers in a register file with an AXI4-Lite port, sticky error flags, event counters and
an interrupt. It contains the crossings between the management clock and the clock domains of the layers.

| Block | Function | State |
| --- | --- | --- |
| MG-1 | Register file, AXI4-Lite access, configuration and status crossings | Complete for one lane |
| MG-2 | Sticky error flags, event counters, interrupt | Complete for the events of phase 2 |
| MG-3 | EDAC monitor | Hardening phase |
| MG-4 | Reset per clock domain | In `ofb_core` |
| TA-1 | Lane test access | Later |

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-IF-01 | The configuration parameters of Table 5-36 for the Data Link, Multi-Lane, Lane and Physical layers shall be readable and writable through an AXI4-Lite slave. | 5.9.3a, b, 6.5 |
| MG-IF-02 | The status parameters of Table 5-37 shall be readable through the AXI4-Lite slave. | 5.9.4a, b |
| MG-CF-01 | The configuration parameters shall take the reset values of Table 5-36 on reset and on Interface Reset: DataScrambled set, Normalised Expected Broadcast Bandwidth 10 % (40 words per broadcast credit), LaneStart de-asserted, AutoStart asserted, LaneReset and parallel loopback de-asserted, Standby Reason 0. | 5.9.3c, 5.7.9.2b |
| MG-CF-02 | Link Reset and Interface Reset shall be commands: a write of one sends one pulse to the Data Link layer. | 5.7.1j, Table 5-36 |
| MG-ST-01 | Error events shall set sticky flags, cleared by writing one; the Link Reset command shall clear the status of the Data Link layer (sticky flags and counters). | 5.9.4d, e |
| MG-ST-02 | The number of error recovery attempts shall be counted, and the CRC-16, CRC-8, frame and sequence errors and the lane timeouts in saturating counters; a write clears a counter. | 5.7.7.1k, l, Table 5-37 |
| MG-ST-03 | An interrupt output shall be asserted while a sticky flag enabled in the interrupt mask is set. | none (implementation) |
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
virtual channel and QoS parameters (priority, expected bandwidth, time slots, continuous mode) and the Maximum Number of
Data-Sending Lanes, RxEn and TxEn follow with phases 3 and 4.
