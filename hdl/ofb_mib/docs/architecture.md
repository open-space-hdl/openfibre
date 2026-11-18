# ofb_mib: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_mib: AXI4-Lite slave, register file (MG-1), EDAC monitor (MG-3) and the crossings to the core,
lane and user clock domains](img/ofb_mib_arch.drawio.svg)

One crossing group per clock domain: configuration levels (`olo_base_cc_bits`), commands (`ofb_cc_pulse`), status
values (`olo_base_cc_status`, a consistent snapshot of the whole status vector), events (`ofb_cc_pulse`). All of
them use triplicated synchronisers (`SyncTmr_g` = true). An event
that occurs more than once while the previous one is crossing may be counted once (see `ofb_cc_pulse` in the
`ofb_pkg` architecture).

The control of the Physical adapters (PA_CTRL, MG-PA-02) leaves the MIB without a crossing, as static levels from
registers of the management clock: the adapter runs its reset sequencers on its own free-running clock, which the core
does not have, and synchronises the values itself. Coherence of the 16-bit PCSRSVDIN and the flags is ensured in the
adapter (`ofb_pa_gty` architecture, section 4): it takes a value only after it has been unchanged for 8 cycles of its
clock, longer than the synchroniser depth, and applies it only at the start of a reset sequence of a lane. Software
changes PA_CTRL while the lanes are stopped or before a receiver reset command (LANE_CTRL RX_RESET); a write during
traffic takes effect at the next reset sequence of each lane. A crossing into the lane clock domain would also clear
the values during every transmitter reset (`olo_base_cc_bits` resets its output with the lane reset).

## 2. Register file

- Read data is registered; `Rb_RdValid` follows `Rb_Rd` by one cycle.
- Sticky flags are set by events and cleared by writing one (W1C).
- Counters saturate; any write clears them.
- A write of one to `LinkReset` clears the sticky flags and counters of the Data Link, Multi-Lane and Lane layers
  (ECSS 5.9.4e; the EDAC status is kept); a write of one to
  `InterfaceReset` sets all configuration registers to their reset values.
- `Irq` = OR of (sticky flags AND interrupt mask).
- The flags of bandwidth use (VC_BW_OVER, VC_BW_UNDER) are set from the levels of the Data Link layer in the status of
  the core clock domain. The output of an `olo_base_cc_status` holds no value before its first transfer after a reset,
  and the crossing stays in reset (`Out_RstOut`) until the core clock domain has left its own reset, which needs the
  core clock. The flags take the status only from 31 cycles after the end of the reset of the crossing on, when its
  first value has arrived (MG-CC-02). A core clock that starts long after the reset, as the transmit clock of a
  transceiver after its power-up, therefore sets no flag. A Link Reset command restarts the 31 cycles: it clears the
  flags, and the status of the cycles before the clear can still be in the crossing. The status registers that are
  not sticky read the output of the crossing directly; until the first transfer after the power-up they read the
  power-up value of its registers.

## 3. Register map

The register map is described once in [`regs/ofb_regs.yml`](../regs/ofb_regs.yml). `tools/regmap.py` generates from it
the documentation [register_map.md](register_map.md), the VHDL package `ofb_regs_pkg` (addresses, field positions and
reset values, used by the register file and by `ofb_dl_qos_regs`) and the C header `sw/ofb_regs.h`;
`python tools/regmap.py --check` (CI) fails when a generated file does not match the description. TC-MG-01 reads every
fixed reset value of the description back from the register file.

Unused addresses read as zero. Writes to VC_IDLE_LIMIT and to the VC block are forwarded to the Data Link layer through
an `olo_ft_fifo_async` (address and data); the MIB keeps a copy for reading.

## 4. PRBS test (MG-5)

LANE_PRBS_CTRL holds the patterns and the hold bit of a lane (configuration, crossing with the lane configuration in
`olo_base_cc_bits`); its count reset and force error bits are commands (`ofb_cc_pulse` to the lane clock, one pulse to
the Physical adapter each). In the lane clock domain a 48-bit counter counts the cycles while the checker is on and
not held, a 32-bit counter the cycles with a checker error; both saturate and are cleared by the count reset. The
error counter, bits 47:16 of the word counter and the lock status cross with the lane status (`olo_base_cc_status`, a
consistent snapshot); with the hold bit set the two counters can be read without a change in between. The Link Reset
command does not clear the PRBS counters (they belong to a test, not to the link status).

## 5. Events of the Network interface

The framing errors of the VC ports (transmit: invalid `TKEEP`; receive: character rule violations) cross with one
`ofb_cc_pulse` of 2 x `NumVc_g` pulses and set VC_FRAMING_ERROR, VC_RX_FRAMING_ERROR and DL_ERRORS bits 9 and 11.
The packets of zero length can arrive in consecutive cycles and on several VCs in the same cycle, which a pulse
crossing would merge: they are counted in the user clock domain (a 16-bit saturating counter that adds the events of
all VCs of a cycle), and the counter value crosses to the management clock with `olo_base_cc_status`. A write to
NI_RX_EMPTY_COUNT and the Link Reset command clear it through an `ofb_cc_pulse` to the user clock, so the clear takes
effect a few cycles after the write.

## 6. EDAC monitor (MG-3)

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
