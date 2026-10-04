# ofb_core: Architecture and Design Description

## 1. Block diagram

```text
 UserClk            CoreClk                    LaneClk                              MgmtClk
 S_Vc_*, S_Bc_* --> ofb_ni --> ofb_dl ==> ofb_core_cc ==> ofb_multilane --> ofb_lane --> PhyTx_*
 M_Vc_*, M_Bc_* <-- ofb_ni <-- ofb_dl <== ofb_core_cc <== ofb_multilane <-- ofb_lane <-- PhyRx_*
                                  ^            ^                ^              ^
                                  +------------+---- ofb_mib ---+--------------+      <-- AXI4-Lite, Irq
 Rst --> olo_base_reset_gen (one per clock domain)
```

## 2. ofb_core_cc

| Signal | Direction | Crossing |
| --- | --- | --- |
| Transmit rows | CoreClk to LaneClk | `olo_ft_fifo_async`, 16 rows, write side reset on link reset (flush) |
| Receive rows | LaneClk to CoreClk | `olo_ft_fifo_async`, 16 rows, read side reset on link reset; a full FIFO is reported as `Ev_RxOverflow` (cannot happen while CoreClk is not slower than LaneClk) |
| Link reset, LaneReset | CoreClk to LaneClk | `ofb_cc_pulse` |
| Near-end capability | CoreClk to LaneClk | `olo_ft_cc_bits` (the bits are independent) |
| Lane active | LaneClk to CoreClk | `olo_ft_cc_bits` |
| Far-end capability and "no lane active" | LaneClk to CoreClk | `olo_ft_fifo_async` (4 entries), event and qualifier in one word |

## 3. Resets

`olo_base_reset_gen` per domain synchronises the asynchronous `Rst` input; inside the domains all resets are
synchronous and high-active.

## 4. Open points

- Phase 4: 2 to 4 lanes.
- The receive row overflow event is not yet connected to the MIB.
