# OpenFibre: User Guide

This guide describes how to integrate the OpenFibre core `ofb_core` into an FPGA design: sources, generics, clocks,
interfaces, programming sequence, performance, synthesis settings and the conformance to the standard. The design
itself is described in the [architecture](architecture.md) and in the documentation of every module
(`hdl/<module>/docs/`); the register map is in [register_map.md](../hdl/ofb_mib/docs/register_map.md), with the C
header `sw/ofb_regs.h` for the software.

## 1. Scope

`ofb_core` is the SpaceFibre node interface of one port (ECSS-E-ST-50-11C): Network interface, Data Link layer,
Multi-Lane layer, Lane layer and Management Information Base. It supports 1 to 4 lanes, 1 to 32 virtual channels,
broadcast messages, quality of service (priority, bandwidth reservation, scheduling) and SECDED protection of all
buffers with an EDAC monitor. The [compliance matrix](compliance.md) lists the ECSS clauses with their requirements and
test cases.

Not part of the core:

- The Physical adapter (serialiser, 8B/10B codec, symbol alignment, receive clock correction). The core exchanges
  decoded symbols with it (section 5.5). `hdl/ofb_pa_gty` is the adapter for one AMD Versal GTY quad, and
  `hdl/ofb_vck190` a reference design for the VCK190 board that uses it.
- Routing switch functions (ECSS 5.8.8 to 5.8.11) and the forwarding of broadcast messages between several ports.

## 2. Sources

| Item | Content |
| --- | --- |
| `component_list.txt` | OpenFibre modules in compile order; every `hdl/<module>/src/*.vhd` goes into one library (`openfibre` in the regression) |
| `open-logic/` (submodule) | Open Logic with the fault-tolerant entities (`olo_ft_*`); the areas `base`, `axi`, `intf` and `ft` are compiled into the library `olo` in the order of `open-logic/compile_order.txt` |
| `hdl/ofb_pa_gty/compile_order.txt` | Physical adapter for the AMD Versal GTY for synthesis and the AMD simulator: the entity `ofb_pa_gty` and the architecture `struct` with the transceiver wizard |
| `hdl/ofb_pa_gty/compile_order_sim.txt` | The same adapter for GHDL and QuestaSim without the AMD libraries: the entity with the behavioural architecture `mdl` (serial pins with the 8B/10B bit stream, [model description](../hdl/ofb_pa_gty/docs/model.md)). Compile exactly one of the two lists into a library |

The sources are VHDL-2008 and use no vendor primitives. `run.py` shows the complete compile flow.

### System simulation with the behavioural adapter

A system simulation in GHDL or QuestaSim replaces the GTY wrapper by the architecture `mdl` of `ofb_pa_gty`: the same
entity, ports and generics, the 8B/10B bit stream on the serial pins and the reset sequence and status of the
transceiver ([model description](../hdl/ofb_pa_gty/docs/model.md)). The design above the adapter stays unchanged.
QuestaSim needs a time resolution of 1 fs (`vsim -t fs`) when the reference clocks differ by fractions of a
picosecond, for example a few hundred ppm.

Compile order (VHDL-2008):

1. Open Logic into the library `olo`, as above.
2. Into one library for OpenFibre (`openfibre` in the regression): the files of `compile_order.txt` of the repository
   (the core), then the files of `hdl/ofb_pa_gty/compile_order_sim.txt` in their order: `tb/ofb_tb_8b10b_pkg.vhd`,
   `hdl/ofb_pa_gty/sim/ofb_pa_model_pkg.vhd`, `hdl/ofb_pa_gty/src/ofb_pa_gty.vhd`,
   `hdl/ofb_pa_gty/sim/ofb_pa_gty_model.vhd`. The model uses `ofb_pkg` of the core through `work` and must be in the
   library of the core.
3. Never compile `hdl/ofb_pa_gty/compile_order.txt` (architecture `struct`, AMD libraries) into the same library.
   With only `mdl` analysed, the default binding of `ofb_pa_gty` is the model; `entity openfibre.ofb_pa_gty(mdl)`
   binds it explicitly.

All files of `compile_order_sim.txt` analyse strictly (GHDL without `-frelaxed`).

| Generic | Value for the model |
| --- | --- |
| `NumLanes_g` | 1 to 4, the same as `NumLanes_g` of `ofb_core` |
| `RstPulseCycles_g` | Cycles of `FreeRunClk` of the stretched reset (default 1000); the reset sequence starts at its end, not before `PowerUpTime` |
| `ModelIdx_g` | 0 to 7, a different value for every instance: the index of its control record `PaModelCtrl(ModelIdx_g)` in `ofb_pa_model_pkg` |
| `SimDevice_g` | Ignored by the model |

Clocks and connections of each adapter:

- `RefClk`: 156.25 MHz (6.4 ns) for 6.25 Gbit/s; the unit interval of the serial pins is the `RefClk` period / 40.
- `FreeRunClk`: any free-running clock (the regression uses 100 MHz); `Rst`: asynchronous, any pulse width.
- `LaneClk` (output) is `RefClk` once the transmit clock runs: drive `LaneClk` of `ofb_core` with it, and `CoreClk`
  as well where the design runs the Data Link layer on the transmit clock (as `ofb_vck190`).
- `Phy_TxReady` of `ofb_core` from `Stat_TxReady`, `Phy_BitSync` from `Stat_Aligned`; the symbol streams, lane
  controls, serial loopbacks and PRBS ports one to one as with `struct` (section 5.5).

Far end of the link:

- Two adapters back to back: per lane `Gt_TxP` and `Gt_TxN` of one end to `Gt_RxP` and `Gt_RxN` of the other, in
  both directions, each adapter with its own `ModelIdx_g`. The reference clocks of the two ends may differ (the
  regression uses 200 ppm and 1000 ppm); the receive buffers compensate with SKIP words.
- The model against the model of another SpaceFibre device: that model sends and receives the 8B/10B bit stream with
  running disparity at the line rate, bit a of symbol 0 first; '0' on both pins is electrical idle.

The default timing is that of the transceiver simulation model. The reset sequence starts at the end of the stretched
reset, but not before `PowerUpTime` (43.715 us) after the start of the simulation, as the transceiver model completes
its power-up first: the transmitters are ready 64.885 us after the start of the simulation when the stretched reset
ends before `PowerUpTime`, and 21.16 us after the end of a later stretched reset (a reset of the adapter in
operation). A receiver decodes words 16.83 us after the signal of the far end appears (`CdrLockTime`, the lock time of
the clock-data recovery of the simulation model, not of the silicon), so the link is initialised about 28 us after the
transmitters are ready, as with the transceiver model. A system test that does not need this timing shortens it in
`PaModelCtrl` before the end of the stretched reset, when the model reads the record, for example `PowerUpTime` 0 ns,
`TxDoneStale` 0 ns, `ClkDelay` 1 us, `TxReadyDelay` 2 us, `RxReadyDelay` 200 ns and `CdrLockTime` 500 ns (keep
`ClkDelay` < `TxReadyDelay`). The same record injects bit errors, dropouts, a bit error rate, lane skew, crossed pairs
and electrical idle per lane (model description, section 3). `PaModelCtrl` is an unresolved signal: drive it from one
process. Two models with four lanes in both directions cost about 44 s of processor time per simulated millisecond in
GHDL; two cores with traffic cost 1000 to 3000 s.

The model applies `CdrLockTime` after every return of the signal at its pins, also when a lane restarts in operation.
With the default, a restarted lane is Active again at both ends 26 us after the signal of the far end returns, as with
the transceiver model; when the signal is away for about 11 us or longer, the initialisation timeout expires once at
each end and the lane is Active again within about 54 us. The error recovery of a link with four lanes under traffic
is verified with `CdrLockTime` 500 ns; with the default lock time it is not yet verified.

Differences to the transceiver model that a system test must not rely on (model description, section 5):

- `Stat_Aligned` rises with the first comma decoded after the lock; the transceiver model reports the byte alignment
  earlier, before it delivers valid words. A system test must not depend on the time of `Stat_Aligned` (no effect on
  the link initialisation, PA-MD-10).
- `Phy_NoSignal` follows the transceiver model by default (`NoSignalMode`): it falls at a fixed time of the reset
  sequence and does not show a lost signal, so the Lane layer detects a loss through the overflow of its RXERR counter
  (about 1.8 us);
  `NoSignalLine` lets it follow the line. The core works with both; the behaviour of the receive electrical idle on
  silicon is not yet verified.
- After a return of the signal the transceiver model delivers valid words before its clock-data recovery has locked;
  the model does not. A system test must not rely on words before the lock.
- No analogue effects (equalisation, jitter, attenuation), no lock process of the PLL or the clock-data recovery
  (fixed delays), a datapath latency close to but not equal to the transceiver.

## 3. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (1 to 4); the VC ports carry 4 x `NumLanes_g` bytes per beat |
| `LaneClkFreq_g` | 156.25e6 | Frequency of `LaneClk` in Hz (lane timers, alignment timeout); must match the clock |
| `CoreClkFreq_g` | 200.0e6 | Frequency of `CoreClk` in Hz (scrubber of the error recovery buffer); must match the clock |
| `VcOutDepth_g` | 128 | Output VC buffer per VC, in beats: a power of two, at least 64 words (`VcOutDepth_g` x `NumLanes_g` >= 64) |
| `VcInDepth_g` | 256 | Input VC buffer per VC, in words: `NumLanes_g` times a power of two, at least 64 with one lane and 128 x `NumLanes_g` with several lanes. With three or four lanes the default is too small: set it, reference value 256 x `NumLanes_g` |
| `ErbRows_g` | 512 | Error recovery buffer, in data rows of `NumLanes_g` words: a power of two, at least 64 |
| `InitPrbsWords_g` | 64 | PRBS words sent after INIT1 and INIT2 during lane initialisation (0 to 64) |
| `LaneStart_g` | false | Reset value of LaneStart (LANE_CTRL bit 0) of every lane: true starts the link after the reset without a write of the MIB |
| `AutoStart_g` | true | Reset value of AutoStart (LANE_CTRL bit 1) of every lane: the lanes start when the far end sends |
| `AlignTimeoutWords_g` | 10000 | Alignment watchdog of the Multi-Lane layer, in lane clock cycles: 0 (off) or 1024 to 1000000. The lower bound makes the stable time (an eighth of the value, at least 128 words) span at least 16 ALIGN periods of 8 words, so that a stable Both-Ends Ready cannot come from a single ALIGN that happens to arrive aligned (behaviour in section 10) |

A value outside these ranges stops the elaboration with a message that names the rule. Every lane count, 1 and 32
VCs, a lane clock of 78.125 MHz, the smallest buffers and lane initialisation without PRBS words are simulated; the
boundaries are also synthesised (verification report of `ofb_core`, section "Generic ranges").

## 4. Clocks and reset

| Clock | Domain | Requirement |
| --- | --- | --- |
| `UserClk` | VC ports, broadcast ports, SCHEDULE.request | For full throughput not slower than `LaneClk` (one beat of `NumLanes_g` words per cycle) |
| `CoreClk` | Data Link layer | Not slower than `LaneClk` |
| `LaneClk` | Multi-Lane and Lane layers, Physical adapter interface | Word clock of the lanes: 156.25 MHz at 6.25 Gbit/s (four 10-bit symbols per cycle) |
| `MgmtClk` | AXI4-Lite port of the MIB, interrupt | Any frequency |

The clocks may be asynchronous to each other. All crossings are Open Logic clock crossings. They need the constraints
of the [Open Logic clock crossing principles](../open-logic/doc/base/clock_crossing_principles.md): for every pair of
the four clocks, in both directions,
`set_max_delay -from [get_clocks <a>] -to [get_clocks <b>] -datapath_only <period of the faster clock>`.

`Rst` is an asynchronous reset, high active. A reset generator per clock domain asserts the reset of the domain
asynchronously and releases it synchronously; all four clocks must run for the reset to complete.

`Phy_TxReady` (asynchronous level) tells the core whether the transmitters of the Physical adapter are ready. While it
is 0, the link stays in Near-End Reset: link reset and LaneReset are held, the lanes stay in ClearLine, the buffers
keep the state of a link reset, and the MIB stays accessible (DL_STATUS bit 9, TX_READY). When the transmitters drop
after they were ready, the link is reset and DL_ERRORS bit 12 (TX_LOST) is set. The core synchronises the level to
CoreClk, LaneClk and MgmtClk separately, so the hold and TX_LOST also work while a transceiver stops `LaneClk` (and a
`CoreClk` that is the same clock) during a reset of its transmitters. Integration rule: drive `Phy_TxReady` from a
register (any clock domain) or a constant, never from combinational logic: the core takes it asynchronously, and a
glitch would reset the link. Connect `Stat_TxReady` of `ofb_pa_gty` (a register of `FreeRunClk`); the default `'1'`
is for an adapter that is always ready. The reset of the core then needs no adapter status: `ofb_vck190_top` resets
the core and the adapter with the power-on reset.

## 5. Interfaces

### 5.1 Virtual channels (`UserClk`)

Per VC an AXI4-Stream slave (`S_Vc_*`, packets to send) and master (`M_Vc_*`, received packets); the vectors hold the
VCs in ascending order. A stream packet is one SpaceFibre packet (ECSS 5.3.9: destination address and cargo) of any
length from one byte. The ports carry bytes only; the Network interface adds and removes the EOP, EEP and Fill
characters of the Data Link layer (ECSS 5.3.7).

| Signal | Width per VC | Content |
| --- | --- | --- |
| `TDATA` | 32 x `NumLanes_g` | 4 x `NumLanes_g` bytes per beat: byte 0 of the beat in bits 7:0, byte 1 in bits 15:8, and so on; the first byte of a packet is byte 0 of its first beat and is sent first |
| `TKEEP` | 4 x `NumLanes_g` | Valid bytes: all set except in the last beat of a packet, where the valid bytes are contiguous from byte 0 (at least one) |
| `TLAST` | 1 | Last beat of the packet |
| `TUSER` | 1 | With `TLAST`: '1' ends the packet with an EEP instead of an EOP (send), the packet ended with an EEP (receive, "Terminated by EEP" of READ_PACKET.indication, ECSS 6.2.2) |

This is the format of the link ports of OpenSPP: `spp_core` with `DataWidth_g` = 32 x `NumLanes_g` connects to a VC
port directly (its `M_Link_User(0)` to `S_Vc_TUser`).

Send: the bytes of a packet become data characters in their order, followed by the EOP (or EEP) and Fills up to the end
of the row; when the last beat is full, the end marker follows in an additional row (one more cycle). A beat with an
invalid `TKEEP` (no byte, a gap, or not all bytes without `TLAST`) is a framing error: the packet is ended with an EEP
when bytes of it were sent before, otherwise nothing of it is sent (no packet of zero length, ECSS 5.3.9h); the rest of
the packet up to `TLAST` is discarded, and the framing error flag of the VC is set in the MIB (VC_FRAMING_ERROR,
DL_ERRORS bit 9).

Receive: the Fills are removed and every packet is delivered from byte 0 of the first beat, also when the far end
started it after Fills at any character of a word (ECSS 5.3.7.2c, for example after a routing switch deleted path
address characters). A packet without data (an EOP or EEP right after the end of the previous packet) is discarded
and counted (NI_RX_EMPTY_COUNT). A received beat that breaks the character rules of ECSS 5.3.7 (a Fill or another
K-code inside a packet, data or a second end marker after an EOP or EEP in the same word) sets the receive framing
error flag (VC_RX_FRAMING_ERROR, DL_ERRORS bit 11): the packet is ended with an EEP after the bytes of its earlier beats
and the characters up to the next end marker are discarded. After a link reset, a packet that was being received is
ended with an EEP (ECSS 5.7.10).

Back-pressure: `S_Vc_TReady` is low when the output VC buffer is full; the Data Link layer sends data only when the far
end has announced buffer space (flow control credit). With the continuous mode of a VC (VC_CFG bit 8) the output
buffer accepts data also without credit: when the buffer is full or no lane is active, the buffer is flushed and the
rest of the packet being written is discarded; a packet of which bytes were already sent is ended with an EEP (no
packet of zero length is sent). `M_Vc_TReady` may be low at any time; the far end is stopped through flow control. Both
directions carry one beat per cycle inside a packet; a packet costs at most one additional cycle (end marker row after
a full last beat, last beat of a received packet whose bytes need one more beat).

### 5.2 Broadcast messages (`UserClk`)

| Port | `TDATA` | `TUSER` |
| --- | --- | --- |
| `S_Bc_*` (send) | 64-bit message: bits 31:0 first data word, 63:32 second data word | 7:0 broadcast channel, 15:8 B_TYPE, 16 DELAYED |
| `M_Bc_*` (receive) | as sent | 7:0 broadcast channel, 15:8 B_TYPE, 16 DELAYED, 17 LATE |

The Data Link layer sets LATE when a message could not be sent immediately (no lane active or error recovery). A node
that is not the source of a broadcast channel does not send on it (ECSS 5.8.12). Received messages that the user does
not read are buffered (4 messages); further messages are discarded and flagged in DL_ERRORS.

### 5.3 SCHEDULE.request (`UserClk`)

`S_Sched_Valid` (one cycle) with `S_Sched_Slot` (0 to 63) starts a time-slot. A VC competes for the link only in the
time-slots allocated to it (VC_SLOTS_LO / VC_SLOTS_HI, all allocated after reset). Unused ports may stay open: the
defaults keep time-slot 0.

### 5.4 Management Information Base (`MgmtClk`)

AXI4-Lite slave with 12-bit byte addresses and 32-bit data, register map in
[register_map.md](../hdl/ofb_mib/docs/register_map.md) (C header `sw/ofb_regs.h`, VHDL package `ofb_regs_pkg`). `Irq`
is high while a sticky flag enabled in IRQ_MASK is set.

### 5.5 Physical adapter (`LaneClk`, per lane)

| Port | Direction | Content |
| --- | --- | --- |
| `PhyTx_Data`, `PhyTx_K` | out | Four symbols per cycle to encode (8B/10B), symbol 0 in bits 7:0 is sent first, K flag per symbol |
| `PhyRx_Data`, `PhyRx_K` | in | Four decoded symbols, K flag per symbol; any symbol offset (the Lane layer aligns the words on the comma) |
| `PhyRx_CodeErr`, `PhyRx_DispErr` | in | 8B/10B code and disparity error per symbol |
| `PhyRx_Valid` | in | Received word valid (gaps allowed) |
| `Phy_TxEnable`, `Phy_RxEnable` | out | Line driver and line receiver enable |
| `Phy_CdrEnable` | out | Clock and data recovery enable |
| `Phy_RxInvert` | out | Invert the receive polarity (crossed pair detected) |
| `Phy_NoSignal` | in | No signal on the line, synchronous to `LaneClk` (the adapter synchronises it) |
| `Phy_TxReady` | in | Transmitters ready (one bit for all lanes, asynchronous level from a register or a constant, default `'1'`); while 0 the link is held in Near-End Reset (section 4) |
| `Phy_SerialNearLoopback`, `Phy_SerialFarLoopback` | out | Near-end and far-end serial loopback (LANE_CTRL bits 16 and 17) |
| `Phy_BitSync` | in | Bit synchronisation of the clock and data recovery (LANE_STATUS bit 6, ECSS 5.4.2e); optional, `ofb_pa_gty` provides it as `Stat_Aligned` |
| `Phy_PrbsTxSel`, `Phy_PrbsRxSel` | out | PRBS test: transmitted and checked pattern per lane (4 bits, LANE_PRBS_CTRL) |
| `Phy_PrbsForceErr`, `Phy_PrbsCntReset` | out | PRBS test: single-cycle pulses, one error in the transmitted pattern, checker reset |
| `Phy_PrbsErr`, `Phy_PrbsLocked` | in | PRBS test: received word with a bit error, checker locked (optional) |

The adapter aligns the receive symbols to 10-bit symbol boundaries, decodes them, and passes them in `LaneClk`
(receive clock correction with the SKIP words that the Lane layer sends, ECSS 5.5.3). The transmit side takes one word
per `LaneClk` cycle without gaps. For the AMD Versal GTY, `ofb_pa_gty` connects these ports one to one; its
`LaneClk` output is the lane clock of the core (see `hdl/ofb_vck190/src/ofb_vck190_top.vhd`). The generic
`NumLanes_g` of `ofb_pa_gty` defaults to 4 (one GTY quad) and that of `ofb_core` to 1: set both to the same value.
The adapter is verified with the transceiver model for 1 to 4 lanes; the unused channels of the quad send electrical
idle.

Receiver equalisation of `ofb_pa_gty`: `tcl/ofb_gtw.tcl` selects `RX_EQ_MODE` AUTO with the default channel insertion
loss of the wizard (`INS_LOSS_NYQ` 20 dB at the Nyquist frequency), which the wizard resolves to the decision feedback
equaliser (DFE, `RXLPMEN` tied to 0). The clock-data recovery lock time `TDLOCK` of the Versal AI Core data sheet
(DS957) ranges from 50,000 UI to 37 x 10^6 UI with DFE and from 50,000 UI to 2.3 x 10^6 UI in low-power mode (LPM); the
lane initialisation timeout of ECSS-E-ST-50-11C (the time to send 5000 words) is 200,000 UI. A lane locks within the
timeout only when the clock-data recovery locks in less than about 22 us at 6.25 Gbit/s (lock time, 1023 words without
error and the INIT2/INIT3 handshake within 32 us). The GTY architecture manual (AM002, LPM use mode) recommends LPM for
short, low-reflection channels with up to 15 dB loss at the Nyquist frequency; a system on such a channel (for example
a short QSFP cable) may select LPM (`RX_EQ_MODE` LPM in `tcl/ofb_gtw.tcl`).

## 6. Programming sequence

1. Release `Rst`. Read ID (0x0FB10009) and GENERICS.
2. Optional configuration before the link start:
   - DL_CTRL bit 8 DataScrambled (set after reset), DL_BC_INTERVAL.
   - Per VC: VC_CFG (priority, continuous mode, virtual network number), VC_BANDWIDTH, VC_SLOTS_LO / HI.
   - Multi-Lane: ML_CTRL (maximum number of data-sending lanes, bypass); per lane LANE_CTRL TxEn and RxEn (bits 5, 6,
     set after reset) for asymmetric links and unidirectional lanes.
   - IRQ_MASK.
   - Test modes per lane in LANE_CTRL: near-end and far-end parallel loopback (bits 3, 4, Lane layer), near-end and
     far-end serial loopback (bits 16, 17, Physical adapter).
3. Start the link: LANE_CTRL of every lane with LaneStart (bit 0) at one end, for example 0x63 (LaneStart, AutoStart,
   TxEn, RxEn). An end with AutoStart only (the reset value 0x62) starts when the far end sends. With `LaneStart_g` =
   true the reset value is 0x63 and the end starts by itself. Two ends that both only wait never start: a core whose
   MIB is reachable only over its own link must start the link itself (`LaneStart_g`) or have a far end that starts.
4. Wait for the link: LANE_STATUS bits 3:0 = 7 (Active) for the lanes, ML_STATUS bits 9:8 = 2 (Both-Ends Ready) with
   several lanes, DL_STATUS bits 1:0 = 3 (link initialised). VC_HAS_CREDIT shows the VCs that may send.
5. Operation: DL_ERRORS, LANE_EVENTS and ECC_STATUS hold sticky flags (interrupt sources); the counters count retries,
   CRC, frame and sequence errors, lane timeouts and Misaligned conditions. DL_ERRORS bit 10 reports receive rows
   lost because CoreClk is slower than LaneClk (a clocking error). DL_ERRORS bits 9 and 11 report framing errors of
   the VC ports (section 5.1) with the VC in VC_FRAMING_ERROR and VC_RX_FRAMING_ERROR; NI_RX_EMPTY_COUNT counts the
   received packets of zero length.
6. Link Reset: DL_CTRL bit 0 resets both ends of the link (the far end sees a Far-End Link Reset); the link
   initialises again without software action. The maximum number of data-sending lanes is taken over at a link reset.
   The command clears the status flags and counters of the Data Link, Multi-Lane and Lane layers (ECSS 5.9.4e), not
   the EDAC status.
   Interface Reset (DL_CTRL bit 1) sets all configuration registers to their reset values.
7. Stop: LANE_CTRL with LaneStart and AutoStart cleared sends STANDBY (with the Standby Reason of bits 15:8) and
   disables the lane.

Bit error rate test of the electrical link (PRBS test, MG-5): the PRBS generator and checker of the transceiver
replace the SpaceFibre traffic of a lane (8B/10B bypassed), so the link goes down while a pattern is sent.

1. Far end or loopback: the far end sends the same pattern (or a QSFP loopback module, or the near-end serial
   loopback of LANE_CTRL bit 16 for a self-test of the transceiver).
2. LANE_PRBS_CTRL = 0x55 (PRBS-31 sent and checked; 0x11 for PRBS-7, closer to the run lengths of 8B/10B).
3. LANE_PRBS_CTRL = 0x10055 (count reset: clears the counters and restarts the lock detection of the checker), then
   wait for LANE_STATUS bit 7 (checker locked).
4. Measurement time, then LANE_PRBS_CTRL = 0x155 (hold), read LANE_PRBS_ERRORS (E, words with at least one bit
   error) and LANE_PRBS_WORDS (W, checked words / 65536), LANE_PRBS_CTRL = 0x55 to continue.
5. Bit error rate: BER = E / (W x 65536 x 40) (40 line bits per word). Without errors the upper bound of the BER at
   95 % confidence is 3 / (W x 65536 x 40): BER below 1e-12 needs 3e12 bits, about 8 minutes at 6.25 Gbit/s.
6. LANE_PRBS_CTRL bit 17 inserts one error into the transmitted pattern (test of the measurement chain).
7. LANE_PRBS_CTRL = 0 ends the test; LaneStart starts the link again.

An errored word counts once, also when it holds several bit errors; at the bit error rates of interest (below 1e-9)
the difference is negligible.

EDAC: ECC_STATUS shows the uncorrectable errors per channel and corrected errors of any channel; ECC_SELECT and
ECC_COUNT read the counters of one channel. ECC_INJECT injects a single or double bit error into the next word written
into the buffers of a channel (test of the EDAC paths). Single errors are corrected in every channel. An uncorrectable
error (DED) in a row crossing (channels 6 and 7) becomes a link error that the error recovery repairs: the frame is
sent again. A DED in the output VC buffers, the error recovery buffer, the frame buffer or the broadcast output
buffer resets the link (packets in progress end with EEP at the far end), a DED in an input VC buffer ends the
packet with EEP (a packet whose first beat holds the error has no bytes left and is discarded as a packet of zero
length), a DED in the broadcast input buffer discards the message. No corrupted word reaches a user; only a
DED in the control crossings (channel 8) is reported without further action.

## 7. Performance

C is the payload capacity of the lanes per direction: 32 bits per `LaneClk` cycle and lane, with `LaneClk` = R / 40
for the data signalling rate R (8B/10B), so C = 0.8 x R x `NumLanes_g`, 5 Gbit/s per lane at 6.25 Gbit/s. The
measurements are simulations of two cores with the behavioural Physical adapter, `LaneClk` 156.25 MHz, `CoreClk`
166.7 MHz and `UserClk` 192.3 MHz, packets of 1 to 1024 bytes at random on four VCs; the throughput counts the words of
the received packets including the word with the end marker.

| Property | Value | Measured in |
| --- | --- | --- |
| Throughput, one direction | 94.6 %, 94.2 %, 94.1 % and 93.7 % of C with 1, 2, 3 and 4 lanes (4.73, 9.42, 14.11 and 18.73 Gbit/s at 6.25 Gbit/s) | TC-CORE-16 |
| Throughput, both directions | At least 90.5 %, 90.5 %, 90.5 % and 89.7 % of C per direction with 1, 2, 3 and 4 lanes (4.53, 9.05, 13.58 and 17.94 Gbit/s at 6.25 Gbit/s) | TC-CORE-16 |
| Link overhead | SDF and EDF per data frame (at most 64 words per lane), end marker and Fill characters, a SKIP word every 5000 words per lane, and with traffic in both directions the ACK and FCT words of the reverse traffic | |
| Packet on the link | A packet of n bytes takes ceil((n + 1) / (4 x `NumLanes_g`)) rows of 4 x `NumLanes_g` characters: the bytes, the EOP or EEP, Fills to the end of the row | TC-NI-07 |
| VC ports | 4 x `NumLanes_g` bytes per beat, one beat per `UserClk` cycle inside a packet. One more cycle per packet: at `S_Vc` when the last beat is full (row with the end marker), at `M_Vc` when the bytes of the last received row need one more beat | TC-NI-07 |
| Clocks | `UserClk` not slower than `LaneClk` for the full throughput at the VC ports. `CoreClk` not slower than `LaneClk` (CORE-CK-01): with a slower `CoreClk` received rows are lost (DL_ERRORS bit 10) | TC-CORE-15 |
| Packet length | No limit: packets longer than a data frame and than the VC buffers are streamed through them; packets of 65542 bytes (the largest Space Packet) with 1 to 4 lanes | TC-CORE-20 |
| Latency | Packet of one byte on the idle link: 365, 388, 390 and 392 ns with 1, 2, 3 and 4 lanes, without the serialisation and transceiver delay. The receiver forwards a data frame after its EDF (store and forward), so the latency grows with the frame length | TC-CORE-16 |
| Share of a VC | Set by the quality of service configuration: priority, bandwidth (VC_BANDWIDTH), time-slots (ECSS 5.7.4) | |

Capacity for packets of n bytes: a packet takes rows(n) = ceil((n + 1) / (4 x `NumLanes_g`)) rows on the link, so the
payload capacity per direction is

capacity(n) = rowEff x f(`LaneClk`) x n / rows(n) bytes per second,

with the row efficiency rowEff derived from the measured throughput: rowEff = eta x `NumLanes_g` x sum(rows(n)) /
sum(ceil((n + 1) / 4)), sums over n = 1 to 1024 (the throughput eta counts words of 4 bytes, the row padding after
the word with the end marker is not counted). rowEff is 0.946, 0.946, 0.948 and 0.948 with 1, 2, 3 and 4 lanes in one
direction, 0.905, 0.909, 0.912 and 0.908 per direction in both directions. It is an average over packets of 1 to 1024
bytes; for longer packets the overhead per row is the same by construction (SDF and EDF per data frame of 64 words per
lane, a SKIP word every 5000 words), so the values are conservative there, below the bound 64/66 x 4999/5000 = 0.9695.
Example: four lanes at 156.25 MHz and packets of 1024 bytes give 0.948 x 156.25e6 x 1024 / 65 = 2.33e9 bytes per
second (18.7 Gbit/s).

## 8. Protection scope

The core is designed for radiation environments together with the triple modular redundancy (TMR) of the synthesis
tool, like the Open Logic ft entities it is built on. It protects the parts in the first rows itself and relies on
TMR for all other logic:

| Part | Protection | Indication and test |
| --- | --- | --- |
| Buffers of the nine EDAC channels: output and input VC buffers, error recovery buffer (RAM with scrubber, ACK / NACK FIFO, read-ahead FIFO), receive frame buffer, broadcast output and input buffers, transmit and receive row crossings, control crossings (SCHEDULE.request, far-end capability, QoS write FIFO of the MIB) | SECDED ECC of the Open Logic ft entities: a single error is corrected, a double error is detected and contained (section 6): a frame is sent again (row crossings), the link is reset (output VC buffers, error recovery buffer, frame buffer, broadcast output buffer), the packet ends with an EEP (input VC buffers), the message is discarded (broadcast input buffer); a double error in the control crossings is reported only | ECC_STATUS (DED flag per channel, SEC flag, interrupt), ECC_SELECT and ECC_COUNT (SEC and DED counters per channel); error injection through the ECC_INJECT register |
| Clock domain crossings and reset synchronisers | Triplicated synchronisers (`SyncTmr_g` = true): three synchroniser chains and a majority voter. Their registers carry the Synplify attribute `syn_radhardlevel` = `none`, so the TMR of the synthesis tool adds no voters between the stages. The pulse crossing `ofb_cc_pulse` also triplicates its request, pending and last registers itself (section 9) | none |
| State machines | Recovery state through the `when others` branch and the reset | none |
| All other logic: registers of the control and data paths, counters, pointers, pipeline registers | TMR of the synthesis tool (for example `syn_radhardlevel` = `tmr` with Synplify, or the equivalent setting of the tool chain). The core adds no protection of its own for this logic; without TMR, an upset in it is not covered | synthesis report |

The integrator:

- enables the TMR of the synthesis tool for the core and the logic around it,
- checks in the synthesis report that TMR was applied, that the synchroniser chains of the crossings were not
  triplicated a second time, and that no register-based storage meant to be protected by TMR was inferred as a RAM
  primitive,
- requests safe state machines, so that synthesis keeps the `when others` branches (AMD Vivado: property
  `FSM_SAFE_STATE` = `default_state` on the state registers; Synplify: attribute `syn_encoding` = `safe`),
- protects the configuration memory of SRAM-based FPGAs by scrubbing; this is part of the FPGA design, not of the
  core.

The ECC paths are verified in simulation by error injection. Whether the protection as a whole meets the
requirements of a mission is shown by a radiation test with the core in operation (TRL 5). The Physical adapter
`ofb_pa_gty` with the transceivers and the VCK190 reference design are vendor-specific and not covered by this
section.

## 9. Synthesis

- TMR of the synthesis tool enabled for the core: the core protects its buffers and synchronisers itself and relies
  on TMR for all other logic (section 8).
- The core is technology independent: `python lint/synth_check.py` synthesises `ofb_core` for 1, 2 and 4 lanes with
  GHDL and fails on errors and inferred latches. RAMs are inferred by the Open Logic RAM entities.
- Every state machine has a recovery branch (`when others`) to its reset state. Synthesis tools that re-encode state
  machines remove this branch unless a safe implementation is requested. With AMD Vivado set the property
  `FSM_SAFE_STATE` to `default_state` on the state registers (in the XDC, see UG901); with Synplify set the attribute
  `syn_encoding` to `safe`. The core does not set these attributes itself. Its only synthesis attributes are in the
  pulse crossing `ofb_cc_pulse` (the triplicated registers are preserved and not merged, no vendor TMR) and in the
  input VC buffer `ofb_dl_vc_in` (`keep` and `syn_keep` on the nets of the beat decision).
- Clock crossings: constraints of section 4.

The VCK190 reference design is built with `vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl` (with the CIPS
block design that every Versal design needs; on Windows the project path must be short, see the hardware test
procedure `hdl/ofb_vck190/docs/hardware_test.md`). Its MIB is reachable over JTAG through the master port M_AXI_FPD
of the CIPS at 0xA400_0000; `hdl/ofb_vck190/tcl/xsdb_mib.tcl` reads and writes the registers in XSDB and runs the
bit error rate test of section 6. Resources of the whole reference design on the XCVC1902 (eight
VCs, four lanes, third build): 47992 LUT (3325 as memory), 47212 registers, 36 RAMB36 and 2 RAMB18, 8 DSP; all timing
constraints met (WNS +0.030 ns at 150 MHz in the user side of the input VC buffers, +0.157 ns at the lane clock).

## 10. Conformance

OpenFibre implements a SpaceFibre port of a node with one end-point per virtual channel according to
ECSS-E-ST-50-11C. The [compliance matrix](compliance.md) lists the requirements and the test cases of every clause.
Where the standard leaves a choice, the section "Interpretation of the standard" of the module specifications
([ofb_dl](../hdl/ofb_dl/docs/specification.md), [ofb_multilane](../hdl/ofb_multilane/docs/specification.md),
[ofb_ni](../hdl/ofb_ni/docs/specification.md), [ofb_mib](../hdl/ofb_mib/docs/specification.md),
[ofb_pa_gty](../hdl/ofb_pa_gty/docs/specification.md)) states the behaviour of the core.

| Status | Clauses | Scope |
| --- | --- | --- |
| Implemented | 5.3.2 to 5.3.10, 5.4.1, 5.4.2, 5.5.2 to 5.5.8, 5.6.1 to 5.6.10, 5.7.2 to 5.7.10, 5.8.3, 5.8.5 to 5.8.7, 5.8.12.1, 5.8.13, 5.9.1 to 5.9.4, 6.2 to 6.5 | Lane, Multi-Lane, Data Link and Network layer of a node, MIB and service interfaces. The Physical layer clauses (5.3.2, 5.4.1, 5.4.2, 6.4) need a Physical adapter: `ofb_pa_gty` for the AMD Versal GTY |
| Implemented with a restriction | 5.6.2 | 1 to 4 lanes per port (`NumLanes_g`); the standard allows up to 16 lanes (5.6.2c) |
| Implemented with a restriction | 5.4.2.3 | `ofb_pa_gty` runs at 6.25 Gbit/s (5.4.2.3b) from a 156.25 MHz reference clock. The core itself takes any data signalling rate (`LaneClk` = R / 40) |
| Implemented with an option | 5.9.3c, Table 5-36 | `LaneStart_g` and `AutoStart_g` set the reset values of LaneStart and AutoStart; the defaults are the reset values of the standard, other values act as a management write right after the reset (MG-CF-03) |
| Extension outside the standard | 5.6.6.4b, 5.6.7 | Alignment watchdog of the Multi-Lane layer (ML-AL-11, `AlignTimeoutWords_g`): LaneReset of the active lanes when the alignment has been in Not Ready for `AlignTimeoutWords_g` lane clock cycles, or outside Both-Ends Ready for twice as many, since the last stable Both-Ends Ready. It covers two cases the standard leaves without a way out: a lane skew beyond the alignment FIFOs at the own end (5.6.6.4b gives a FIFO of 3 or 4 words and no mechanism for a larger skew, which word losses at comma realignments after bit errors cause), and a far end that stays in Not Ready, for example without such a watchdog. No shall requirement is changed; `AlignTimeoutWords_g` = 0 gives the behaviour of the standard alone (see below) |
| Implemented with an interpretation | 5.7.9.3c | The link reset state machine leaves Near-End Reset only while the transmitters of the Physical adapter are ready (`Phy_TxReady`, section 4); the standard leaves it unconditionally. A transmitter that is not ready cannot send the INIT words of the lane initialisation. With `Phy_TxReady` = 1, the default of the port, the behaviour is that of the standard (DL-LR-06) |
| Outside the scope of a node with one port | 5.8.8 to 5.8.11 | Routing switch, packet addressing, group adaptive routing, packet multicast |
| Outside the scope of a node with one port | 5.8.12.2 | Acceptance and forwarding of broadcast messages in a routing switch (port of arrival, broadcast time-out) |
| Outside the scope of the core | 5.4.3 to 5.4.6 | Electrical and fibre optic physical layer and media, connectors and cables: properties of the transceiver, the board and the harness |
| Outside the scope of the core | 5.8.2, 5.8.4, 5.8.14 | Composition of networks, links and units. For a link the user selects at least two VCs (`NumVc_g`, 5.8.4c; one VC for a point-to-point or configuration link, 5.8.4d) and the same VC numbers at both ends (5.8.4e) |
| Not implemented | none | Every clause that a node with one port needs is implemented |

Alignment watchdog. A bit error that forms a false comma shifts the symbol alignment of a receiver until the next comma,
and the word being assembled can be lost. Several such losses on one lane give a skew beyond the alignment FIFOs, and
the alignment then stays in Not Ready: the Data Link layer can send no RETRY, ACK or NACK, and the traffic stops in both
directions without a link reset. The watchdog sums the cycles in Not Ready, and separately the cycles outside Both-Ends
Ready, since the last stable Both-Ends Ready (Both-Ends Ready for `AlignTimeoutWords_g / 8` cycles in a row). When the
first sum reaches `AlignTimeoutWords_g`, or the second twice that value, it resets the active lanes: the lanes of both
ends start again, the skew is gone, the link aligns and the Data Link layer continues with a RETRY. The error recovery
buffer is kept (5.7.7i), so no data is lost and no packet ends with an EEP. With two OpenFibre ends the stuck end acts
first; the bound of twice the value in Near-End Ready also recovers a far end that has no watchdog, because the
LaneReset restarts its lanes as well. The default of 10000 cycles (64 us at 156.25 MHz) is two SKIP intervals, so that
the clock correction of a transceiver can restore a skew first, and lies far above the alignment time after a link start
and after a single comma slip (verification report of `ofb_core`). Each expiry increments ML_ALIGN_TIMEOUTS. Under a
lasting high bit error rate, when comma slips follow each other faster than the stable time, the times add up and the
watchdog restarts the lanes repeatedly. This is intended: the error recovery buffer is kept, ML_ALIGN_TIMEOUTS shows the
restarts, and LANE_TIMEOUT_COUNT and the error counters (DL_ERRORS, RXERR_COUNT of LANE_STATUS) show the cause. With
`AlignTimeoutWords_g` = 0 such a stall lasts until a LaneReset or a Link Reset through the MIB.

## 11. Corrected defects

Defects of earlier versions that a user of the core can meet, with their correction. The verification reports of the
modules describe each finding.

| Defect | Affected versions | Correction |
| --- | --- | --- |
| With more than one lane and an input VC buffer of one flow control unit (`VcInDepth_g` = 64 x `NumLanes_g`, for example the default 256 with four lanes), the traffic of a VC could stop for good: a beat holds back up to `NumLanes_g` - 1 words until the next words arrive, so the buffer never became free for the next FCT | All versions before the check of the generic ranges | The elaboration rejects input VC buffers below 128 x `NumLanes_g` words with several lanes (DL-VI-05); reference value 256 x `NumLanes_g` |
| With more than one lane, bit errors that formed false commas could stop the traffic in both directions for good while the link stayed initialised: the word losses at the comma realignments gave a lane skew beyond the alignment FIFOs, and the alignment stayed in Not Ready (ML_STATUS bits 9:8 = 0 at one end, 1 at the other, ERB_EMPTY 0); only a Link Reset recovered the link | All versions before the alignment watchdog | Alignment watchdog of the Multi-Lane layer (ML-AL-11, default 10000 cycles): LaneReset of the active lanes, recovery without data loss; ML_ALIGN_TIMEOUTS counts the expiries |
| After a complete restart of one end while the other end was in Link Initialised, the link could stay down for good: the capability event of a lane that entered Active in the same cycle was evaluated with the lane already Active | All versions before the correction of the Multi-Lane layer (CORE-SY-03) | The lane manager uses the lane states of the cycle before the event (ML-LM-14) |
