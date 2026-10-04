# ofb_ni: Specification

## 1. Overview

`ofb_ni` is the Network interface of an OpenFibre node (ECSS-E-ST-50-11C clauses 5.8 and 6.2, 6.3): AXI4-Stream ports
for the N-Chars of every virtual channel and for broadcast messages, with a check of the packet framing on the transmit
side.

| Block | Entity | Function | State |
| --- | --- | --- | --- |
| NI-1 | `ofb_ni_vc` (x `NumVc_g`) | VC port: framing check of the transmitted words | Complete |
| NI-2 | none | Virtual network mapper | Phase 3 |
| NI-3 | in `ofb_ni` | Broadcast port | Complete |
| NI-4 | none | Schedule port | Phase 3 |

All ports run on `UserClk`. A word carries four N-Chars or Fills; `TUSER` bit i is the K flag of character i (EOP,
EEP or Fill). Without NI-2 the virtual network number is the VC number (ECSS 5.8.3bb for VN0).

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-IF-01 | For every VC the Network interface shall offer an AXI4-Stream slave for words to send and an AXI4-Stream master for received words (`TDATA` 32 bits, `TUSER` 4 K flags). | 6.2.2, 6.3.2, 5.8.6, 5.8.7 |
| NI-IF-02 | The Network interface shall offer an AXI4-Stream slave for broadcast messages to send (`TDATA` 64 bits, `TUSER` channel, B_TYPE, DELAYED) and a master for received messages (`TUSER` channel, B_TYPE, DELAYED, LATE). | 6.2.3, 6.3.3, 5.8.12 |
| NI-FR-01 | A word with more than one EOP or EEP, with a K-code other than EOP, EEP and Fill, or with a data character after an EOP or EEP shall be reported as a framing error (one-cycle event per VC). | 5.3.7.1d, f, 5.3.7.2 |
| NI-FR-02 | In a word with a framing error, the first offending character shall be replaced by an EEP and the following characters by Fills; the following words shall be discarded up to and including the next word with an EOP or EEP of the Network layer, unless the replaced character already ended the packet. | 5.3.9e |
| NI-FR-03 | Words of four Fills shall not be passed to the Data Link layer. | 5.3.7.2e |
| NI-RX-01 | Received words and broadcast messages shall be passed to the user unchanged. | 5.8.7, 6.2.2.3 |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `NumVc_g` | 8 | Number of virtual channels |
