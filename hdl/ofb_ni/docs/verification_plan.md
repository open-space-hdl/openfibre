# ofb_ni: Verification Plan

## 1. Overview

The framing check of the VC port (NI-1) is verified with a unit testbench, for words (one lane) and for beats of four
words (four lanes). The field mapping of the broadcast port (NI-3) and the pass-through of the received words are
verified in the core testbench, where packets and broadcast messages travel between two cores.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_ni_vc_tb` | `ofb_ni_vc` with one lane: AXI-Stream VVC for the user words (random gaps), random back-pressure at the output, log of the output words, count of framing errors; `ofb_ni_vc` with four lanes: beats driven by the sequencer, random back-pressure, log of the output words, count of framing errors |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_valid_words` (TC-NI-01) | Data words, words with EOP or EEP and Fills, Fills before data: passed unchanged and in order under back-pressure, no framing error | NI-IF-01, NI-RX-01 (transmit side) |
| `test_framing_errors` (TC-NI-02) | Data after EOP: Fills and spill of the rest; second EOP: Fill, no spill; K28.7 inside a packet: EEP, spill up to the user's EOP; K28.5 in a word ending with EOP: EEP, no spill; one event per error | NI-FR-01, NI-FR-02 |
| `test_fill_words` (TC-NI-03) | Words of four Fills are dropped | NI-FR-03 |
| `test_beats` (TC-NI-04) | Beats of four words: Fill words inside a beat passed; a beat of Fill words only dropped; K28.7 in word 1: EEP, the words 2 and 3 of the beat discarded, the next beat (only words of the packet) dropped, the words of the following beat discarded up to and including the user's EOP, the next packet in the same beat passed; one event | NI-IF-01, NI-FR-01 to 03 |

Beats of several words travel between two cores in the core testbench with 2 and 4 lanes (`ofb_core_tb`, TC-CORE-02
and TC-CORE-05). NI-IF-02 and NI-RX-01 are verified there (TC-CORE-02): broadcast messages with random channel, B_TYPE
and DELAYED flag, and the received words of every VC are compared with the words sent. NI-SC-01 is verified in
TC-CORE-06: a SCHEDULE.request at the Network interface sets the current time-slot of the Data Link layer.
