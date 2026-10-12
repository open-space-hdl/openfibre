# ofb_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_core: ofb_ni, ofb_dl, ofb_core_cc, ofb_multilane and ofb_lane in a row with their clock domains,
ofb_mib below with the management connections, and the reset generators](img/ofb_core_arch.drawio.svg)

## 2. ofb_core_cc

| Signal | Direction | Crossing |
| --- | --- | --- |
| Transmit rows | CoreClk to LaneClk | `olo_ft_fifo_async`, 16 rows, write side reset on link reset (flush); a row read with a DED goes to the Multi-Lane layer with all mask bits set, as a non-replicated row and with `Ml_TxRow_Poison` (CORE-ED-02) |
| Receive rows | LaneClk to CoreClk | `olo_ft_fifo_async`, 16 rows, read side reset on link reset; a full FIFO is reported as `Ev_RxOverflow` to the MIB, DL_ERRORS bit 10 (cannot happen while CoreClk is not slower than LaneClk); a row read with a DED is replaced by one RXERR (CORE-ED-02) |
| Link reset, LaneReset | CoreClk to LaneClk | `ofb_cc_pulse` |
| Near-end capability | CoreClk to LaneClk | `olo_base_cc_bits` (the bits are independent) |
| Lane active | LaneClk to CoreClk | `olo_base_cc_bits` |
| Far-end capability and "no lane active" | LaneClk to CoreClk | `olo_ft_fifo_async` (4 entries), event and qualifier in one word |

## 3. Resets

`olo_base_reset_gen` with `SyncTmr_g` = true per domain synchronises the asynchronous `Rst` input with three
synchroniser chains and a majority voter, so that an upset does not reset a domain; inside the domains all resets are
synchronous and high-active.
