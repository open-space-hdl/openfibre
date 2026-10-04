# ofb_core: Verification Plan

## 1. Overview

The core is verified with two cores connected through the behavioural Physical adapter model, with all four clock
domains at different frequencies (user 192 MHz, core 166.7 MHz, lane 156.25 MHz, management 100 MHz). The cores are
configured and monitored through the MIB with the UVVM AXI-Lite VVC; packets and broadcast messages are random and
checked with scoreboards. The final end-to-end test with the transceiver model follows in phase 5.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ofb_core_tb` | `ofb_core_th` | Two `ofb_core` (4 VCs) A and B, `ofb_tb_pa_model`, one `ofb_tb_axilite_master` per core, packet generator and receiver per VC (random length, receiver back-pressure), broadcast generator and receiver, raw word queue for VC 0 of A |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link_up` (TC-CORE-01) | ID register; LaneStart of A through the MIB, AutoStart at B: both ends reach Link Initialised, lane Active, no error | CORE-IF-01, CORE-CK-01, CORE-RS-01, CORE-SY-01 |
| `test_traffic` (TC-CORE-02) | 15 packets per VC and 10 broadcast messages in both directions: all delivered, no error and no retry in the MIB | CORE-SY-01, CORE-CC-01 |
| `test_error_recovery` (TC-CORE-03) | 20 bit errors per direction during traffic: all delivered, retries counted in the MIB, no link reset | CORE-SY-01 |
| `test_link_reset` (TC-CORE-04) | Link Reset command at A through the MIB: both ends reset, Far-End Link Reset at B only, link up again, traffic | CORE-SY-01, CORE-CC-01 |
| `test_framing_error` (TC-CORE-05) | Word with K28.7 at the Network interface of A: B receives the packet ended with EEP, the framing error flags are set at A | CORE-IF-01 |
