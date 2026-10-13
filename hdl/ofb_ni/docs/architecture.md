# ofb_ni: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_ni: VC ports with the packet to N-Char conversion in both directions (NI-1), broadcast port
(NI-3) and schedule port (NI-4)](img/ofb_ni_arch.drawio.svg)

`B` = 4 x `NumLanes_g` is the number of bytes of a beat. Character `c` of a beat of the Data Link layer is character
`c mod 4` of word `c / 4`; it holds byte `c` of the beat of the user port (`TDATA(8c+7:8c)`), and `TKEEP(c)` and the
K flag of the character have the same index. The conversion therefore moves no byte inside a beat on the transmit side,
and on the receive side only by the offset of a packet that starts after Fills.

## 2. ofb_ni_vc_tx (NI-1, transmit)

A combinational conversion of the input beat followed by an `olo_base_pl_stage` of the beat (36 x `NumLanes_g` bits):

- Valid beat: character `c` is data byte `c` (K flag clear) where `TKEEP(c)` is set. In the last beat of a packet the
  first character without a byte is the EOP, or the EEP when `TUSER(0)` is set, and the characters after it are Fills,
  so the end marker word and the further words of the beat end the packet (NI-TX-02).
- Full last beat (`TKEEP` all ones with `TLAST`): the beat is passed as data, and the state `EndPend` sends an
  additional beat with the end marker in character 0 and Fills; the input is not ready during that cycle.
- `TKEEP` check (NI-TX-03): bit 0 set, no set bit above a clear bit, and all bits set in a beat without `TLAST`. A beat
  that fails it raises `Ev_FrameErr`. When the packet has passed bytes before (`Started`), the beat is replaced by an
  EEP followed by Fills; otherwise nothing is passed, so no packet of zero length is sent (ECSS 5.3.9h). Without
  `TLAST` the state `Spill` discards the further beats of the packet up to and including the beat with `TLAST`.

`In_Ready` depends only on the state (`EndPend`, `Spill`) and on the ready of the pipeline stage, not on `TKEEP` or
`TDATA`. A beat discarded without output (first beat with a framing error, beats in `Spill`) is accepted in one
cycle.

## 3. ofb_ni_vc_rx (NI-1, receive)

The input VC buffer of the Data Link layer delivers beats of `NumLanes_g` words that end after the word with an EOP
or EEP (DL-RW-06). An `olo_base_pl_stage` registers the beat; the conversion works on this register (timing, and the
ready of the buffer is a register).

### 3.1 Classification

Every character of the beat is classified as data (K flag clear), end marker (EOP or EEP), Fill or other K-code. Three
prefix and suffix terms per character position decide the beat without arithmetic:

| Term | Meaning |
| --- | --- |
| `PreD(c)` | a data character before position `c` |
| `PreE(c)` | an end marker before position `c` |
| `SufF(c)` | only Fills after position `c` |

- Character rule violation (NI-RX-03): another K-code; a data character or end marker after an end marker; a Fill
  that follows a data character, or any Fill in a beat that continues a packet, before the first end marker.
- Clean end: an end marker followed by Fills only (`E(c)` and `SufF(c)`).
- First data character: `FirstD(c)` = data at `c` and not `PreD(c)` (one-hot).

### 3.2 Alignment

A conforming packet is `F* D+ (EOP | EEP)`: leading Fills, a contiguous run of data characters and the end marker
(ECSS 5.3.7.2c). The data of the packet therefore keep one offset `Off` (the position of the first data character in
its first beat) relative to the beats of the input, and one rotation of every input beat by `Off` aligns the packet to
byte 0 of the output:

```text
Rot(i) = In((i + Off) mod B)            rotation, AND-OR over the one-hot offset
Mix(i) = Rot(i) when SelMask(i) = '1' else Hold(i)     SelMask(i) = '1' for i >= B - Off
```

`Hold` keeps the rotated previous beat of the packet, whose first `B - Off` bytes belong to the next output beat; the
current beat completes it with its first `Off` bytes. `OffSel` (one-hot) and `SelMask` are registered at the first beat
of a packet and stay constant up to its end. A packet that starts at character 0 (every packet of an OpenFibre
transmitter) has `Off` = 0: `Hold` holds a whole beat and `Mix` = `Hold`.

| Beat | Action |
| --- | --- |
| Fills only, between packets | Accepted, nothing passed |
| End marker without data, between packets | Packet of zero length: discarded, `Ev_Empty` (NI-RX-02) |
| First beat with data, no end | `Hold` := rotated beat, `OffSel` and `SelMask` registered, packet open |
| First beat with data and end | One output beat: rotated beat, `TKEEP` = rotated data mask, `TLAST`, `TUSER` = EEP |
| Beat of an open packet, no end | Output `Mix` (all bytes valid), `Hold` := rotated beat |
| Beat of an open packet with end | Output `Mix` with `TKEEP` = not `SelMask` or the rotated data mask; when data of the beat remain at positions below `B - Off` (`Tail`), `Mix` is a full beat without `TLAST` and the tail follows from `Hold` in the next cycle with `TLAST`; otherwise `Mix` has `TLAST` |

The output beat of a packet waits for the next input beat of the packet (look-ahead): only then is it known whether
the next characters are data or the end marker, so that a packet that ends with a word holding only its EOP or EEP
still ends with `TLAST` on its last data byte.

### 3.3 Violations and discard

A beat with a violation raises `Ev_FrameErr`. An open packet is ended with the bytes of its earlier beats (`Hold`,
`TKEEP` = not `SelMask`) and `TUSER` = '1'; the bytes of the violating beat are not passed. A packet that starts in
the violating beat is not passed. Without a clean end in the beat, the state `Discard` drops the following beats up to
and including a beat with a clean end. After a link reset the input VC buffer adds an EEP when the last character read
was not an end marker or Fill (DL-VI-04); that EEP is a clean end and ends `Discard` as well.

### 3.4 Output

The output register (`Out_*`) and the pending tail (`TailVld`, data in `Hold`) form the output. The input stage is read
when the output register is free or read in this cycle and no tail is pending, so one beat per cycle passes inside a
packet and a packet with a tail costs one cycle (NI-IF-03). `Ev_FrameErr` and `Ev_Empty` are registered one-cycle
events.

## 4. Broadcast port (NI-3)

Field mapping only: `TUSER` bits 7:0 channel, 15:8 B_TYPE, 16 DELAYED, 17 LATE (receive direction).

## 5. Timing and resources

- Transmit latency one cycle (pipeline stage), receive latency two cycles (input stage, output register) plus the
  look-ahead of one input beat inside a packet.
- Logic depth: the receive path from the input stage to the output register is the classification (K flag and value
  of a character), a prefix term over `B` characters and an AND-OR of `B` inputs for the rotation; the transmit path is
  the `TKEEP` check and a 3-input selection per character.
- Registers per VC: transmit 36 x `NumLanes_g` (stage); receive 36 x `NumLanes_g` (stage) plus about 2 x 36 x
  `NumLanes_g` (`Hold`, output register) and the masks.
