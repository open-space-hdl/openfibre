# ofb_ni: Verification Plan

## 1. Overview

The framing check of the VC port (NI-1) is verified with a unit testbench. The field mapping of the broadcast port
(NI-3) and the pass-through of the received words are verified in the core testbench, where packets and broadcast
messages travel between two cores.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_ni_vc_tb` | `ofb_ni_vc`, AXI-Stream VVC for the user words (random gaps), random back-pressure at the output, log of the output words, count of framing errors |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_valid_words` (TC-NI-01) | Data words, words with EOP or EEP and Fills, Fills before data: passed unchanged and in order under back-pressure, no framing error | NI-IF-01, NI-RX-01 (transmit side) |
| `test_framing_errors` (TC-NI-02) | Data after EOP: Fills and spill of the rest; second EOP: Fill, no spill; K28.7 inside a packet: EEP, spill up to the user's EOP; K28.5 in a word ending with EOP: EEP, no spill; one event per error | NI-FR-01, NI-FR-02 |
| `test_fill_words` (TC-NI-03) | Words of four Fills are dropped | NI-FR-03 |

Beats of several words (NI-IF-01, NI-FR-02 across the words of a beat, NI-FR-03 for beats) are verified in the core
testbench with 2 and 4 lanes (`ofb_core_tb`, TC-CORE-02 and TC-CORE-05).

NI-IF-02 and NI-RX-01 are covered by the core testbench.
