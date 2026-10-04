# ofb_ni: Specification

## 1. Overview

`ofb_ni` is the Network interface of an OpenFibre node (ECSS-E-ST-50-11C clauses 5.8 and 6.2, 6.3): AXI4-Stream ports
for the N-Chars of every virtual channel and for broadcast messages, with a check of the packet framing on the transmit
side.

| Block | Entity | Function | State |
| --- | --- | --- | --- |
| NI-1 | `ofb_ni_vc` (x `NumVc_g`) | VC port: framing check of the transmitted words | Complete |
| NI-2 | MIB register | Virtual network number per VC (one end-point per VC) | Complete |
| NI-3 | in `ofb_ni` | Broadcast port | Complete |
| NI-4 | in `ofb_ni` | Schedule port (SCHEDULE.request) | Complete |

All ports run on `UserClk`. A beat carries `NumLanes_g` words of four N-Chars or Fills; `TUSER` bit 4w+i is the K
flag of character i of word w (EOP, EEP or Fill). Without NI-2 the virtual network number is the VC number (ECSS
5.8.3bb for VN0).

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-IF-01 | For every VC the Network interface shall offer an AXI4-Stream slave for beats to send and an AXI4-Stream master for received beats; a beat has `NumLanes_g` words (`TDATA` 32 bits and `TUSER` 4 K flags per word, word 0 first). | 6.2.2, 6.3.2, 5.8.6, 5.8.7 |
| NI-IF-02 | The Network interface shall offer an AXI4-Stream slave for broadcast messages to send (`TDATA` 64 bits, `TUSER` channel, B_TYPE, DELAYED) and a master for received messages (`TUSER` channel, B_TYPE, DELAYED, LATE). | 6.2.3, 6.3.3, 5.8.12 |
| NI-FR-01 | A word with more than one EOP or EEP, with a K-code other than EOP, EEP and Fill, or with a data character after an EOP or EEP shall be reported as a framing error (one-cycle event per VC). | 5.3.7.1d, f, 5.3.7.2 |
| NI-FR-02 | In a word with a framing error, the first offending character shall be replaced by an EEP and the following characters by Fills; the following words, also in the same beat, shall be discarded (replaced by words of four Fills) up to and including the next word with an EOP or EEP of the Network layer, unless the replaced character already ended the packet. | 5.3.9e |
| NI-FR-03 | Beats of words of four Fills only shall not be passed to the Data Link layer; words of four Fills inside a beat are passed (they keep the packet cargo word alignment, note of 5.7.2.2d). | 5.3.7.2e |
| NI-RX-01 | Received words and broadcast messages shall be passed to the user unchanged. | 5.8.7, 6.2.2.3 |
| NI-SC-01 | The Network interface shall pass SCHEDULE.request (time-slot number, valid strobe) to the Data Link layer. | 6.3.4, 5.7.4.3b |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels (1 to 32) |
| `NumLanes_g` | 1 | Number of lanes (1 to 4): words per beat of the VC ports |

## 4. Interpretation of the standard

- Virtual networks (5.8.3): an OpenFibre node has one end-point per VC (5.8.3h). The virtual network number of a VC
  (VN0 to VN63, 5.8.3i, k) is a configuration register of the MIB; VN0 is always mapped to VC0 (5.8.3bb). A node with
  one port maps no virtual networks between ports, so NI-2 has no data path.
- Broadcast messages (5.8.12): the broadcast channel number and the broadcast type are parameters of every message
  (6.2.3, 6.3.3). The user decides which channels it sends on; a node that is not associated with a broadcast channel
  does not send (5.8.12f) and receives all messages. The acceptance rules for messages that arrive on several ports
  (port of arrival, broadcast time-out) belong to the broadcast mechanism of a routing switch or of a node with several
  ports and are out of scope (O7).
- The STATUS parameter of BROADCAST_MESSAGE.indication and RX_BROADCAST.indication consists of the DELAYED and LATE
  flags (5.3.8.4); TX_BROADCAST.request takes DELAYED from the user, LATE is set by the Data Link layer (DL-BO-03).
