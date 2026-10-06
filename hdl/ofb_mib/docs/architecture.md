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
- A write of one to `LinkReset` clears the sticky flags and counters of the Data Link, Multi-Lane and Lane layers
  (ECSS 5.9.4e; the EDAC status is kept); a write of one to
  `InterfaceReset` sets all configuration registers to their reset values.
- `Irq` = OR of (sticky flags AND interrupt mask).

## 3. Register map

The register map is described once in [`regs/ofb_regs.yml`](../regs/ofb_regs.yml). `tools/regmap.py` generates from it
the documentation [register_map.md](register_map.md), the VHDL package `ofb_regs_pkg` (addresses, field positions and
reset values, used by the register file and by `ofb_dl_qos_regs`) and the C header `sw/ofb_regs.h`;
`python tools/regmap.py --check` (CI) fails when a generated file does not match the description. TC-MG-01 reads every
fixed reset value of the description back from the register file.

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
