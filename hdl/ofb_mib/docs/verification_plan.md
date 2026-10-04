# ofb_mib: Verification Plan

## 1. Overview

The register file and the crossings are verified with a unit testbench in four clock domains (management 100 MHz,
core 156.25 MHz, lane 147 MHz, user 192 MHz), with the UVVM AXI-Lite VVC as register master. The connection of the
registers to the layers is verified with the core testbench.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_mib_tb` | `ofb_mib` (4 VCs, one lane), `ofb_tb_axilite_master`, status and events driven by the sequencer in their clock domains, counters of the command pulses |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_reset_values` (TC-MG-01) | ID, generics, reset values of the configuration registers and of the configuration outputs in the core and lane domains | MG-IF-01, MG-CF-01, MG-CC-01 |
| `test_config` (TC-MG-02) | Configuration written and read back, outputs in the domains; Link Reset and Interface Reset give one pulse each; Interface Reset restores the reset values | MG-IF-01, MG-CF-01, MG-CF-02, MG-CC-01 |
| `test_status` (TC-MG-03) | Data Link, Has Credit, lane and Multi-Lane status read through the status crossings | MG-IF-02, MG-CC-01 |
| `test_qos_registers` (TC-MG-05) | Reset values of the QoS registers, write and read back, VN 0 fixed for VC 0, forwarding of the writes to the core clock, bandwidth status and time-slot, Interface Reset | MG-IF-01, MG-IF-02, MG-CF-01, MG-VN-01, DL-QS-07 |
| `test_events` (TC-MG-04) | Events of the three domains set sticky flags and counters; W1C; interrupt with mask; Link Reset clears the Data Link status and keeps the lane flags | MG-ST-01 to 03 |
| `test_edac` (TC-MG-07) | SEC and DED events in the core, user and lane domains counted per channel; DED and SEC flags, DED interrupt; clear of a channel and of all; injection commands reach the write domain of the channel only; an error injected into the QoS write FIFO is corrected and counted in channel CTRL | MG-ED-01 to 03, PKG-11 |
| `test_multilane_registers` (TC-MG-06) | Reset values of TxEn, RxEn, maximum number of data-sending lanes and bypass in the lane and core domains; written values reach both domains; ML_STATUS with the bypass bit; Misaligned events counted and cleared; Interface Reset restores ML_CTRL and LANE_CTRL | MG-ML-01, MG-CF-01 |
