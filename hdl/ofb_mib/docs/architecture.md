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
| 0x000 | ID | 31:0 | RO | 0x0FB10004 | OpenFibre, register map version 4 |
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
| 0x040 | ML_STATUS | 3:0, 7:4, 9:8, 10 | RO | | Data-sending lanes, data-receiving lanes, alignment state, bypass |
| 0x044 | IRQ_MASK | 9:0, 19:16, 24, 25 | RW | 0 | Interrupt enable for DL_ERRORS bits 9:0, LANE_EVENTS bits 3:0 of any lane, an ECC DED flag, the ECC SEC flag |
| 0x048 | VC_BW_OVER | NumVc-1:0 | W1C | 0 | Bandwidth over use per VC |
| 0x04C | VC_BW_UNDER | NumVc-1:0 | W1C | 0 | Bandwidth under use per VC |
| 0x050 | VC_IDLE_LIMIT | 31:0 | RW | 156250 | Virtual Channel Idle Time Limit in words (1 ms at 6.25 Gbit/s) |
| 0x054 | SCHED_STATUS | 5:0 | RO | | Current time-slot |
| 0x058 | ML_CTRL | 2:0, 8 | RW | NumLanes_g, 0 | Maximum number of data-sending lanes (taken over at link reset), Multi-Lane bypass |
| 0x05C | ML_MISALIGNED | 15:0 | RO, write clears | 0 | Misaligned conditions in Near-End Ready or Both-Ends Ready (saturating) |
| 0x060 | ECC_STATUS | 8:0, 16 | RO, write clears all | 0 | DED flag per EDAC channel, SEC seen in any channel; a write clears the flags and all counters |
| 0x064 | ECC_SELECT | 3:0 | RW | 0 | EDAC channel of ECC_COUNT |
| 0x068 | ECC_COUNT | 15:0, 31:16 | RO, write clears the channel | 0 | SEC count, DED count of the selected channel (saturating) |
| 0x06C | ECC_INJECT | 3:0, 8 | W | | Error injection into the next word written in the buffers of the channel: channel, double error |
| 0x100 + 0x20 i | LANE_CTRL | 0, 1, 2, 3, 4, 5, 6, 15:8, 16, 17 | RW | 0, 1, 0, 0, 0, 1, 1, 0, 0, 0 | LaneStart, AutoStart, LaneReset, near-end parallel loopback, far-end parallel loopback, TxEn, RxEn, Standby Reason, near-end serial loopback, far-end serial loopback (Physical layer) |
| 0x104 + 0x20 i | LANE_STATUS | 3:0, 4, 5, 6, 15:8, 23:16 | RO | | Lane state, RX polarity, NoSignal, bit synchronisation (Physical adapter), RXERR counter, far-end capabilities |
| 0x108 + 0x20 i | LANE_EVENTS | 3:0 | W1C | 0 | RXERR overflow, timeout, far-end standby, far-end lost signal |
| 0x10C + 0x20 i | LANE_REASONS | 7:0, 15:8 | RO | | Far-end Standby Reason, far-end LOST_SIGNAL reason |
| 0x110 + 0x20 i | LANE_TIMEOUT_COUNT | 15:0 | RO, write clears | 0 | Initialisation timeouts |
| 0x400 + 0x10 v | VC_CFG | 3:0, 8, 21:16 | RW | NumPrio-1, 0, v | Priority level, continuous mode, virtual network number (VC 0: always VN 0) |
| 0x404 + 0x10 v | VC_BANDWIDTH | 15:0 | RW | 0x0A00 (VC 0), 0xFFFF | 1 / Normalised Expected Bandwidth, 8.8 fixed point (0x0100: 100 %, 0x0A00: 10 %, 0: no bandwidth) |
| 0x408 + 0x10 v | VC_SLOTS_LO | 31:0 | RW | all ones | Allocated time-slots 31 to 0 |
| 0x40C + 0x10 v | VC_SLOTS_HI | 31:0 | RW | all ones | Allocated time-slots 63 to 32 |

Unused addresses read as zero. Writes to VC_IDLE_LIMIT and to the VC block are forwarded to the Data Link layer through
an `olo_ft_fifo_async` (address and data); the MIB keeps a copy for reading.

## 4. EDAC monitor (MG-3)

The EDAC channels are defined in `ofb_pkg` (`EccCh*_c`, 9 channels). Every module with fault-tolerant buffers reports
for each channel a SEC and a DED pulse per word read with an error, in the clock domain of the read side, and takes
injection commands (single or double error in the next word written) in the clock domain of the write side:

| Channel | Buffers | Events (read side) | Injection (write side) |
| --- | --- | --- | --- |
| 0 VC_OUT | Output VC buffers (all VCs) | CoreClk | UserClk (all VCs) |
| 1 ERB | Error recovery buffer: RAM (with scrubber, also the scrubber events), ACK / NACK FIFO, read-ahead FIFO | CoreClk | CoreClk (RAM) |
| 2 FRAME_BUF | Frame buffer | CoreClk | CoreClk |
| 3 VC_IN | Input VC buffers (all banks) | UserClk | CoreClk (bank 0 of every VC) |
| 4 BC_OUT | Broadcast output buffer | CoreClk | UserClk |
| 5 BC_IN | Broadcast input buffer | UserClk | CoreClk |
| 6 CC_TX | Transmit row crossing | LaneClk | CoreClk |
| 7 CC_RX | Receive row crossing | CoreClk | LaneClk |
| 8 CTRL | SCHEDULE.request crossing, far-end capability crossing, QoS write FIFO of the MIB | CoreClk | MgmtClk (QoS write FIFO) |

The MIB crosses the events of the core, user and lane domains with one `ofb_cc_pulse` each (18 pulses: SEC, DED per
channel) and counts them in `olo_ft_ecc_monitor` (16-bit counters, DED sticky flags). Events of one channel closer
together than the crossing can transfer them are counted once. The read port of the monitor reads the selected
channel in every cycle (`ECC_COUNT`); a write to `ECC_COUNT` is the read-and-clear of that channel, a write to
`ECC_STATUS` the global clear. The SEC sticky flag is set by the SEC event output of the monitor. Injection commands
cross from MgmtClk with one `ofb_cc_pulse` per domain to the write side of the channel.
