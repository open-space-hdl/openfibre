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

This issue covers phase 2: one lane.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| CORE-IF-01 | The core shall offer the AXI4-Stream ports of `ofb_ni`, the AXI4-Lite port and interrupt of `ofb_mib`, and per lane the symbol stream and control of the Physical adapter as defined by `ofb_lane`. | 6.2, 6.3, 6.5, 5.5.1k to n |
| CORE-CK-01 | The core shall run on four clocks: UserClk, CoreClk, LaneClk and MgmtClk; CoreClk shall not be slower than LaneClk. | none (architecture section 6) |
| CORE-RS-01 | One asynchronous reset input shall reset every clock domain through a reset generator per domain. | 5.7.9.2a.1 (power-on reset) |
| CORE-CC-01 | Rows shall cross between CoreClk and LaneClk through FIFOs that are flushed on link reset; link reset and LaneReset shall cross as pulses, the near-end capability as a level, the far-end capability event together with its "no lane active" qualifier. | 5.7.9, 5.7.10b |
| CORE-SY-01 | Two cores connected through their Physical adapters shall initialise the link when started through the MIB, transfer packets and broadcast messages without loss, recover from bit errors and reset both ends on a Link Reset command. | 5.5 to 5.9 (system level) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (phase 2: 1) |
| `LaneClkFreq_g` | 156.25e6 | Lane clock frequency in Hz |
| `VcOutDepth_g`, `VcInDepth_g` | 128, 256 | VC buffers, words |
| `ErbWords_g` | 512 | Error recovery buffer, words |
| `InitPrbsWords_g` | 64 | PRBS words after INIT1 / INIT2 |
