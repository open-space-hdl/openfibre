# ofb_ni: Specification

## 1. Overview

`ofb_ni` is the Network interface of an OpenFibre node (ECSS-E-ST-50-11C clauses 5.8 and 6.2, 6.3): AXI4-Stream packet
ports for every virtual channel and ports for broadcast messages and the schedule. The packet ports carry the packets
of the Packet Transfer service (6.2.2): the bytes of a packet with the end of the packet in `TLAST` and the EEP flag in
`TUSER`. The Network interface converts them to and from the N-Chars and Fills of the Virtual Channel service of the
Data Link layer (6.3.2): it ends every transmitted packet with an EOP or EEP and fills the rest of the word, and it
removes the Fills and end markers of the received packets.

| Block | Entity | Function | State |
| --- | --- | --- | --- |
| NI-1 | `ofb_ni_vc_tx`, `ofb_ni_vc_rx` (x `NumVc_g` each) | VC port: packets to N-Chars (end marker, Fills, framing check), N-Chars to packets (Fill removal, alignment, end marker, character rule check) | Complete |
| NI-2 | MIB register | Virtual network number per VC (one end-point per VC) | Complete |
| NI-3 | in `ofb_ni` | Broadcast port | Complete |
| NI-4 | in `ofb_ni` | Schedule port (SCHEDULE.request) | Complete |

All ports run on `UserClk`. Without NI-2 the virtual network number is the VC number (ECSS 5.8.3bb for VN0).

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-IF-01 | For every VC the Network interface shall offer an AXI4-Stream slave for packets to send and an AXI4-Stream master for received packets: `TDATA` 32 x `NumLanes_g` bits with byte 0 of a beat in bits 7:0, `TKEEP` one bit per byte, `TLAST` on the last beat of a packet, and `TUSER` one bit, valid with `TLAST`, that marks a packet terminated by an EEP. | 6.2.2, 6.3.2, 5.8.6, 5.8.7 |
| NI-IF-02 | The Network interface shall offer an AXI4-Stream slave for broadcast messages to send (`TDATA` 64 bits, `TUSER` channel, B_TYPE, DELAYED) and a master for received messages (`TUSER` channel, B_TYPE, DELAYED, LATE). | 6.2.3, 6.3.3, 5.8.12 |
| NI-IF-03 | Each VC port shall transfer one beat per clock cycle inside a packet, in both directions, with at most one additional cycle per packet. | none (performance) |
| NI-TX-01 | The Network interface shall pass the bytes of a packet to the output VC buffer as data characters in stream order, starting at character 0 of word 0 of a beat, and shall end the packet with an EOP, or with an EEP when `TUSER` is '1' on its last beat. | 5.3.7.1a to c, e, g, 5.3.9a, d |
| NI-TX-02 | The characters after the EOP or EEP in its word and the further words of the beat shall be Fills; when the last beat of a packet carries 4 x `NumLanes_g` bytes, the EOP or EEP shall follow in an additional beat with the end marker in character 0 of word 0 and Fills in all other characters. | 5.3.7.1d, f, 5.3.7.2b, c, e |
| NI-TX-03 | A beat with an invalid `TKEEP` (no byte valid, valid bytes not contiguous from byte 0, or not all bytes valid in a beat without `TLAST`) shall be reported as a framing error (one-cycle event per VC). | 5.3.9e |
| NI-TX-04 | After a framing error the beat and the further beats of the packet up to and including the beat with `TLAST` shall be discarded. When bytes of the packet were passed before, the packet shall be ended with an EEP as in NI-TX-02; otherwise nothing of the packet shall be passed. | 5.3.9e, h |
| NI-RX-01 | The Network interface shall pass every received packet with at least one data character to the user: its data characters in order with byte 0 of the packet in byte 0 of the first beat, all bytes of a beat valid except in the last beat, whose valid bytes are contiguous from byte 0, `TLAST` on the last beat and `TUSER` '1' when the packet ended with an EEP. Fills shall be removed; a packet may start after Fills at any character of a word. | 6.2.2, 5.3.7.2c, d, 5.3.9d, f |
| NI-RX-02 | A received packet without data characters (an EOP or EEP that follows the end of the previous packet, with Fills only between them) shall be discarded and counted (one-cycle event per VC). | 5.3.9h |
| NI-RX-03 | A received beat that breaks the character rules (a Fill or a K-code other than EOP, EEP and Fill between the first data character and the end of a packet, a data character or a further EOP or EEP after an EOP or EEP in the same beat) shall be reported as a receive framing error (one-cycle event per VC). The packet shall be ended with an EEP after the bytes of its earlier beats, a packet that starts in the beat shall be discarded, and the following characters shall be discarded up to and including an EOP or EEP that only Fills follow in its beat. | 5.3.7.1d, f, g, 5.3.7.2c, 5.3.9e |
| NI-RX-04 | Received broadcast messages shall be passed to the user unchanged. | 5.8.12, 6.2.3 |
| NI-SC-01 | The Network interface shall pass SCHEDULE.request (time-slot number, valid strobe) to the Data Link layer. | 6.3.4, 5.7.4.3b |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (1 to 4): words per beat of the Data Link layer, 4 x `NumLanes_g` bytes per beat of the VC ports |

## 4. Interpretation of the standard

- Packet Transfer service (6.2.2): SEND_PACKET.request is a packet on the slave port of the VC, READ_PACKET.indication
  a packet on the master port with "Terminated by EEP" in `TUSER`. The virtual network is the VC of the port (NI-2).
  The Virtual Channel service (6.3.2, N-Chars and Fills) is the interface between `ofb_ni` and the Data Link layer.
- Fills (5.3.7.2): the transmitter places Fills only after an end marker (5.3.7.2b, c), so its packets start at
  character 0 of a word. Fills that a far end places at the start of a packet (note of 5.3.7.2c, for example after a
  routing switch deleted path address characters) are removed by the receiver; the cargo is delivered from byte 0 of
  the port.
- Packets of zero length (5.3.9h): the transmitter never generates one, also not after a framing error (NI-TX-04).
  A received one is discarded like a routing switch does (note of 5.3.9h) and counted in the MIB.
- Virtual networks (5.8.3): an OpenFibre node has one end-point per VC (5.8.3h). The virtual network number of a VC
  (VN0 to VN63, 5.8.3i, k) is a configuration register of the MIB; VN0 is always mapped to VC0 (5.8.3bb). A node with
  one port maps no virtual networks between ports, so NI-2 has no data path.
- Broadcast messages (5.8.12): the broadcast channel number and the broadcast type are parameters of every message
  (6.2.3, 6.3.3). The user decides which channels it sends on; a node that is not associated with a broadcast channel
  does not send (5.8.12f) and receives all messages. The acceptance rules for messages that arrive on several ports
  (port of arrival, broadcast time-out) belong to the broadcast mechanism of a routing switch or of a node with several
  ports and are out of scope (no routing switch, architecture section 1).
- The STATUS parameter of BROADCAST_MESSAGE.indication and RX_BROADCAST.indication consists of the DELAYED and LATE
  flags (5.3.8.4); TX_BROADCAST.request takes DELAYED from the user, LATE is set by the Data Link layer (DL-BO-03).
