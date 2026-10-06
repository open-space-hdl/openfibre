# OpenFibre: User Guide

This guide describes how to integrate the OpenFibre core `ofb_core` into an FPGA design: sources, generics, clocks,
interfaces, programming sequence and synthesis settings. The design itself is described in the
[architecture](architecture.md) and in the documentation of every module (`hdl/<module>/docs/`); the register map is in
[register_map.md](../hdl/ofb_mib/docs/register_map.md), with the C header `sw/ofb_regs.h` for the software.

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

The sources are VHDL-2008 and use no vendor primitives. `run.py` shows the complete compile flow.

## 3. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (1 to 4); also the number of words per beat of the VC ports |
| `LaneClkFreq_g` | 156.25e6 | Frequency of `LaneClk` in Hz (lane timers, alignment timeout) |
| `CoreClkFreq_g` | 200.0e6 | Frequency of `CoreClk` in Hz (scrubber of the error recovery buffer) |
| `VcOutDepth_g` | 128 | Output VC buffer per VC, in beats |
| `VcInDepth_g` | 256 | Input VC buffer per VC, in words (multiple of 64 x `NumLanes_g`) |
| `ErbRows_g` | 512 | Error recovery buffer, in data rows of `NumLanes_g` words |
| `InitPrbsWords_g` | 64 | PRBS words sent after INIT1 and INIT2 during lane initialisation |

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

## 5. Interfaces

### 5.1 Virtual channels (`UserClk`)

Per VC an AXI4-Stream slave (`S_Vc_*`, data to send) and master (`M_Vc_*`, received data); the vectors hold the VCs in
ascending order. A beat carries `NumLanes_g` words, word 0 in the lowest bits. A word carries four characters,
character 0 in bits 7:0; `TUSER` bit 4w+i is the K flag of character i of word w.

| Character | K flag | Value |
| --- | --- | --- |
| Data | 0 | 0x00 to 0xFF |
| EOP (end of packet) | 1 | 0xFD (K29.7) |
| EEP (error end of packet) | 1 | 0xFE (K30.7) |
| Fill | 1 | 0xFB (K27.7) |

Transmit rules (checked by the Network interface, ECSS 5.3.7):

- A packet is a sequence of data characters ended by an EOP or EEP. A word may contain at most one end marker; the
  characters after it in the word are Fills.
- Fills may also precede the first data character of a word. Words of four Fills inside a beat are sent (they keep
  the alignment of the words of a beat); beats of Fill words only are dropped.
- A framing error (second end marker in a word, data after an end marker, a K-code other than EOP, EEP or Fill)
  ends the packet with an EEP, discards the rest of the packet up to the user's next end marker and sets the framing
  error flag of the VC in the MIB.

Receive format: the received characters in the same format. A beat ends at the end of a packet: the words after the
word with the EOP or EEP are Fill words. The user ignores Fill characters. After a link reset, a packet that was being
received is ended with an EEP (ECSS 5.7.10).

Back-pressure: `S_Vc_TReady` is low when the output VC buffer is full; the Data Link layer sends data only when the far
end has announced buffer space (flow control credit). With the continuous mode of a VC (VC_CFG bit 8) the output
buffer accepts data also without credit: when the buffer is full, the current packet is ended with an EEP and the rest
of the packet is discarded. `M_Vc_TReady` may be low at any time; the far end is stopped through flow control.

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
| `Phy_SerialNearLoopback`, `Phy_SerialFarLoopback` | out | Near-end and far-end serial loopback (LANE_CTRL bits 16 and 17) |
| `Phy_BitSync` | in | Bit synchronisation of the clock and data recovery (LANE_STATUS bit 6, ECSS 5.4.2e); optional, `ofb_pa_gty` provides it as `Stat_Aligned` |

The adapter aligns the receive symbols to 10-bit symbol boundaries, decodes them, and passes them in `LaneClk`
(receive clock correction with the SKIP words that the Lane layer sends, ECSS 5.5.3). The transmit side takes one word
per `LaneClk` cycle without gaps. For the AMD Versal GTY, `ofb_pa_gty` connects these ports one to one; its
`LaneClk` output is the lane clock of the core (see `hdl/ofb_vck190/src/ofb_vck190_top.vhd`).

## 6. Programming sequence

1. Release `Rst`. Read ID (0x0FB10005) and GENERICS.
2. Optional configuration before the link start:
   - DL_CTRL bit 8 DataScrambled (set after reset), DL_BC_INTERVAL.
   - Per VC: VC_CFG (priority, continuous mode, virtual network number), VC_BANDWIDTH, VC_SLOTS_LO / HI.
   - Multi-Lane: ML_CTRL (maximum number of data-sending lanes, bypass); per lane LANE_CTRL TxEn and RxEn (bits 5, 6,
     set after reset) for asymmetric links and unidirectional lanes.
   - IRQ_MASK.
   - Test modes per lane in LANE_CTRL: near-end and far-end parallel loopback (bits 3, 4, Lane layer), near-end and
     far-end serial loopback (bits 16, 17, Physical adapter).
3. Start the link: LANE_CTRL of every lane with LaneStart (bit 0) at one end, for example 0x63 (LaneStart, AutoStart,
   TxEn, RxEn). An end with AutoStart only (the reset value 0x62) starts when the far end sends.
4. Wait for the link: LANE_STATUS bits 3:0 = 7 (Active) for the lanes, ML_STATUS bits 9:8 = 2 (Both-Ends Ready) with
   several lanes, DL_STATUS bits 1:0 = 3 (link initialised). VC_HAS_CREDIT shows the VCs that may send.
5. Operation: DL_ERRORS, LANE_EVENTS and ECC_STATUS hold sticky flags (interrupt sources); the counters count retries,
   CRC, frame and sequence errors, lane timeouts and Misaligned conditions. DL_ERRORS bit 10 reports receive rows
   lost because CoreClk is slower than LaneClk (a clocking error).
6. Link Reset: DL_CTRL bit 0 resets both ends of the link (the far end sees a Far-End Link Reset); the link
   initialises again without software action. The maximum number of data-sending lanes is taken over at a link reset.
   The command clears the status flags and counters of the Data Link, Multi-Lane and Lane layers (ECSS 5.9.4e), not
   the EDAC status.
   Interface Reset (DL_CTRL bit 1) sets all configuration registers to their reset values.
7. Stop: LANE_CTRL with LaneStart and AutoStart cleared sends STANDBY (with the Standby Reason of bits 15:8) and
   disables the lane.

EDAC: ECC_STATUS shows the uncorrectable errors per channel and corrected errors of any channel; ECC_SELECT and
ECC_COUNT read the counters of one channel. ECC_INJECT injects a single or double bit error into the next word written
into the buffers of a channel (test of the EDAC paths). Single errors are corrected in every channel. An uncorrectable
error (DED) in a row crossing (channels 6 and 7) becomes a link error that the error recovery repairs: the frame is
sent again. A DED in the output VC buffers, the error recovery buffer, the frame buffer or the broadcast output
buffer resets the link (packets in progress end with EEP at the far end), a DED in an input VC buffer ends the
packet with EEP, a DED in the broadcast input buffer discards the message. No corrupted word reaches a user; only a
DED in the control crossings (channel 8) is reported without further action.

## 7. Performance

Measured in simulation (TC-CORE-16, 6.25 Gbit/s lanes, payload capacity 5 Gbit/s per lane, packets of 1 to 1024
bytes on all VCs): from one end only 94 % of the lane capacity (4.7, 9.4 and 18.7 Gbit/s with 1, 2 and 4 lanes),
with traffic in both directions 90 % per direction. The latency of a short packet on an idle link is about 0.35 us
without the serialisation delay of the transceivers; the receiver forwards a data frame after its EDF (store and
forward), so the latency grows with the frame length (up to 64 words per lane).

## 8. Synthesis

- The core is technology independent: `python lint/synth_check.py` synthesises `ofb_core` for 1, 2 and 4 lanes with
  GHDL and fails on errors and inferred latches. RAMs are inferred by the Open Logic RAM entities.
- Every state machine has a recovery branch (`when others`) to its reset state. Synthesis tools that re-encode state
  machines remove this branch unless a safe implementation is requested. With AMD Vivado set the property
  `FSM_SAFE_STATE` to `default_state` on the state registers (in the XDC, see UG901); with Synplify set the attribute
  `syn_encoding` to `safe`. The core does not set vendor attributes itself.
- Clock crossings: constraints of section 4.

The VCK190 reference design is built with `vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl` (with the CIPS
block design that every Versal design needs); resource figures and timing results for the XCVC1902 follow with its
first implementation. The hardware test procedure is `hdl/ofb_vck190/docs/hardware_test.md`.
