# ofb_core: Architecture and Design Description

## 1. Block diagram

```text
 UserClk            CoreClk                    LaneClk                              MgmtClk
 S_Vc_*, S_Bc_* --> ofb_ni --> ofb_dl ==> ofb_core_cc ==> ofb_multilane --> ofb_lane --> PhyTx_*
 M_Vc_*, M_Bc_* <-- ofb_ni <-- ofb_dl <== ofb_core_cc <== ofb_multilane <-- ofb_lane <-- PhyRx_*
                                  ^            ^                ^              ^
                                  +------------+---- ofb_mib ---+--------------+      <-- AXI4-Lite, Irq
 Rst --> olo_ft_reset_gen (one per clock domain)
```

## 2. ofb_core_cc

| Signal | Direction | Crossing |
| --- | --- | --- |
| Transmit rows | CoreClk to LaneClk | `olo_ft_fifo_async`, 16 rows, write side reset on link reset (flush); a row read with a DED goes to the Multi-Lane layer with all mask bits set, as a non-replicated row and with `Ml_TxRow_Poison` (CORE-ED-02) |
| Receive rows | LaneClk to CoreClk | `olo_ft_fifo_async`, 16 rows, read side reset on link reset; a full FIFO is reported as `Ev_RxOverflow` to the MIB, DL_ERRORS bit 10 (cannot happen while CoreClk is not slower than LaneClk); a row read with a DED is replaced by one RXERR (CORE-ED-02) |
| Link reset, LaneReset | CoreClk to LaneClk | `ofb_cc_pulse` |
| Near-end capability | CoreClk to LaneClk | `olo_ft_cc_bits` (the bits are independent) |
| Lane active | LaneClk to CoreClk | `olo_ft_cc_bits` |
| Far-end capability and "no lane active" | LaneClk to CoreClk | `olo_ft_fifo_async` (4 entries), event and qualifier in one word |

## 3. Resets

`olo_ft_reset_gen` per domain synchronises the asynchronous `Rst` input with three synchroniser chains and a
majority voter, so that an upset does not reset a domain; inside the domains all resets are synchronous and
high-active.

## 4. Open points

- Timing of the four clock domains is checked with the first implementation on the XCVC1902 (no synthesis licence
  on the development host).
