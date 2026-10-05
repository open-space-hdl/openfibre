# ofb_core: Specification

## 1. Overview

`ofb_core` is the OpenFibre core: a SpaceFibre node interface (ECSS-E-ST-50-11C) from the AXI4-Stream ports of the
virtual channels and broadcast messages down to the symbol stream of the Physical adapters, with the Management
Information Base on AXI4-Lite. The Physical adapter (SerDes, 8B/10B codec, receive elastic buffer) is outside the core
(PA-1 to PA-3), so the core is independent of the FPGA family.

| Module | Function |
| --- | --- |
| `ofb_ni` | Network interface (UserClk) |
| `ofb_dl` | Data Link layer (CoreClk, user side of the buffers on UserClk) |
| `ofb_core_cc` | Crossing between CoreClk and LaneClk |
| `ofb_multilane` | Multi-Lane layer (LaneClk) |
| `ofb_lane` | Lane layer, one per lane (LaneClk) |
| `ofb_mib` | Management Information Base (MgmtClk) |

This issue covers phases 2 to 4: 1 to 4 lanes (`NumLanes_g`). The VC ports carry beats of `NumLanes_g` words.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| CORE-IF-01 | The core shall offer the AXI4-Stream ports of `ofb_ni`, the AXI4-Lite port and interrupt of `ofb_mib`, and per lane the symbol stream and control of the Physical adapter as defined by `ofb_lane`. | 6.2, 6.3, 6.5, 5.5.1k to n |
| CORE-CK-01 | The core shall run on four clocks: UserClk, CoreClk, LaneClk and MgmtClk; CoreClk shall not be slower than LaneClk. | none (architecture section 6) |
| CORE-RS-01 | One asynchronous reset input shall reset every clock domain through a reset generator per domain. | 5.7.9.2a.1 (power-on reset) |
| CORE-CC-01 | Rows shall cross between CoreClk and LaneClk through FIFOs that are flushed on link reset; link reset and LaneReset shall cross as pulses, the near-end capability as a level, the far-end capability event together with its "no lane active" qualifier. | 5.7.9, 5.7.10b |
| CORE-SY-01 | Two cores connected through their Physical adapters shall initialise the link when started through the MIB, transfer packets and broadcast messages without loss, recover from bit errors and reset both ends on a Link Reset command. | 5.5 to 5.9 (system level) |
| CORE-ML-01 | With several lanes, all Lane layers shall send SKIP on the SKIP request of the Multi-Lane layer; the Multi-Lane management parameters (TxEn, RxEn, maximum number of data-sending lanes, bypass) shall reach the Multi-Lane layer and the Data Link layer from the MIB, and the Multi-Lane status (data-sending and data-receiving lanes, alignment state, bypass, Misaligned events) the MIB. | 5.6.1p, q, 5.6.4.5a, Tables 5-36, 5-37 |
| CORE-ED-01 | The SEC and DED events of all fault-tolerant buffers shall reach the EDAC monitor of the MIB, and errors shall be injectable into every channel through the MIB. | none (fault tolerance, MG-3) |
| CORE-PL-01 | The serial loopback enables of the MIB shall be outputs per lane for the Physical adapter (`Phy_SerialNearLoopback`, `Phy_SerialFarLoopback`, LaneClk). | 5.4.1h, 5.4.2.2 |
| CORE-SY-02 | Two cores with 2 or 4 lanes shall transfer packets without loss also when a lane fails and is reconnected during traffic, with fewer data-sending lanes than lanes, and in the Multi-Lane bypass. | 5.6, 5.7.7 (system level) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (1 to 4); words per beat of the VC ports |
| `LaneClkFreq_g` | 156.25e6 | Lane clock frequency in Hz |
| `CoreClkFreq_g` | 200.0e6 | Core clock frequency in Hz (scrubber of the error recovery buffer) |
| `VcOutDepth_g`, `VcInDepth_g` | 128, 256 | VC buffers: output in beats, input in words (multiple of 64 x `NumLanes_g`) |
| `ErbRows_g` | 512 | Error recovery buffer, data rows of `NumLanes_g` words |
| `InitPrbsWords_g` | 64 | PRBS words after INIT1 / INIT2 |
