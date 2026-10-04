# ofb_mib: Architecture and Design Description

## 1. Block diagram

```text
 AXI4-Lite --> olo_axi_lite_slave --> register file (Clk = management clock)
                                        |  ^            |  ^             |  ^
                    configuration, cmd  v  | status,    v  |             |  | events
                    olo_ft_cc_bits /    CoreClk:      LaneClk:          UserClk:
                    olo_ft_cc_pulse     Data Link     Multi-Lane, Lane  Network interface
                    olo_base_cc_status  (cc_status, cc_pulse back)
```

One crossing group per clock domain: configuration levels (`olo_ft_cc_bits`), commands (`olo_ft_cc_pulse`), status
values (`olo_base_cc_status`, a consistent snapshot of the whole status vector), events (`olo_ft_cc_pulse`). An event
that occurs again before the previous one has crossed may be counted once.

## 2. Register file

- Read data is registered; `Rb_RdValid` follows `Rb_Rd` by one cycle.
- Sticky flags are set by events and cleared by writing one (W1C).
- Counters saturate; any write clears them.
- A write of one to `LinkReset` clears the Data Link sticky flags and counters (ECSS 5.9.4e); a write of one to
  `InterfaceReset` sets all configuration registers to their reset values.
- `Irq` = OR of (sticky flags AND interrupt mask).

## 3. Register map

Byte addresses, 32-bit registers. RO read only, RW read / write, W1 write one (command), W1C write one to clear.

| Address | Name | Bits | Access | Reset | Content |
| --- | --- | --- | --- | --- | --- |
| 0x000 | ID | 31:0 | RO | 0x0FB10002 | OpenFibre, register map version 2 |
| 0x004 | GENERICS | 7:0, 11:8 | RO | | NumVc_g, NumLanes_g |
| 0x008 | DL_CTRL | 0, 1, 8 | W1, W1, RW | 0, 0, 1 | LinkReset, InterfaceReset, DataScrambled |
| 0x00C | DL_BC_INTERVAL | 15:0 | RW | 40 | Words per broadcast credit (4 / Normalised Expected Broadcast Bandwidth) |
| 0x010 | DL_STATUS | 1:0, 3:2, 6:4, 8 | RO | | Link reset state, receive error state, data word identification state, error recovery buffer empty |
| 0x014 | DL_ERRORS | 9:0 | W1C | 0 | CRC-16, CRC-8, frame, sequence, Link Reset Caused by Protocol Error, Far-End Link Reset, broadcast discarded, input buffer overflow (any VC), FCT credit overflow (any VC), framing error of the Network interface (any VC) |
| 0x018 | DL_RETRIES | 31:0 | RO, write clears | 0 | Number of error recovery attempts |
| 0x01C | DL_CRC16_COUNT | 15:0 | RO, write clears | 0 | CRC-16 errors |
| 0x020 | DL_CRC8_COUNT | 15:0 | RO, write clears | 0 | CRC-8 errors |
| 0x024 | DL_FRAME_COUNT | 15:0 | RO, write clears | 0 | Frame errors |
| 0x028 | DL_SEQ_COUNT | 15:0 | RO, write clears | 0 | Sequence errors |
| 0x030 | VC_HAS_CREDIT | NumVc-1:0 | RO | | Has Credit per VC |
| 0x034 | VC_INPUT_OVERFLOW | NumVc-1:0 | W1C | 0 | Input buffer overflow per VC |
| 0x038 | VC_CREDIT_OVERFLOW | NumVc-1:0 | W1C | 0 | FCT credit counter overflow per VC |
| 0x03C | VC_FRAMING_ERROR | NumVc-1:0 | W1C | 0 | Framing error of the Network interface per VC |
| 0x040 | ML_STATUS | 3:0, 7:4, 9:8 | RO | | Data-sending lanes, data-receiving lanes, alignment state |
| 0x044 | IRQ_MASK | 9:0, 19:16 | RW | 0 | Interrupt enable for DL_ERRORS bits 9:0 and LANE_EVENTS bits 3:0 of any lane |
| 0x048 | VC_BW_OVER | NumVc-1:0 | W1C | 0 | Bandwidth over use per VC |
| 0x04C | VC_BW_UNDER | NumVc-1:0 | W1C | 0 | Bandwidth under use per VC |
| 0x050 | VC_IDLE_LIMIT | 31:0 | RW | 156250 | Virtual Channel Idle Time Limit in words (1 ms at 6.25 Gbit/s) |
| 0x054 | SCHED_STATUS | 5:0 | RO | | Current time-slot |
| 0x100 + 0x20 i | LANE_CTRL | 0, 1, 2, 3, 4, 15:8 | RW | 0, 1, 0, 0, 0, 0 | LaneStart, AutoStart, LaneReset, near-end parallel loopback, far-end parallel loopback, Standby Reason |
| 0x104 + 0x20 i | LANE_STATUS | 3:0, 4, 5, 15:8, 23:16 | RO | | Lane state, RX polarity, NoSignal, RXERR counter, far-end capabilities |
| 0x108 + 0x20 i | LANE_EVENTS | 3:0 | W1C | 0 | RXERR overflow, timeout, far-end standby, far-end lost signal |
| 0x10C + 0x20 i | LANE_REASONS | 7:0, 15:8 | RO | | Far-end Standby Reason, far-end LOST_SIGNAL reason |
| 0x110 + 0x20 i | LANE_TIMEOUT_COUNT | 15:0 | RO, write clears | 0 | Initialisation timeouts |
| 0x400 + 0x10 v | VC_CFG | 3:0, 8, 21:16 | RW | NumPrio-1, 0, v | Priority level, continuous mode, virtual network number (VC 0: always VN 0) |
| 0x404 + 0x10 v | VC_BANDWIDTH | 15:0 | RW | 0x0A00 (VC 0), 0xFFFF | 1 / Normalised Expected Bandwidth, 8.8 fixed point (0x0100: 100 %, 0x0A00: 10 %, 0: no bandwidth) |
| 0x408 + 0x10 v | VC_SLOTS_LO | 31:0 | RW | all ones | Allocated time-slots 31 to 0 |
| 0x40C + 0x10 v | VC_SLOTS_HI | 31:0 | RW | all ones | Allocated time-slots 63 to 32 |

Unused addresses read as zero. Writes to VC_IDLE_LIMIT and to the VC block are forwarded to the Data Link layer through
an `olo_ft_fifo_async` (address and data); the MIB keeps a copy for reading.
