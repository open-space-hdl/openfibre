# ofb_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of ofb_core: ofb_ni, ofb_dl, ofb_core_cc, ofb_multilane and ofb_lane in a row with their clock domains,
ofb_mib below with the management connections, and the reset generators](img/ofb_core_arch.drawio.svg)

## 2. ofb_core_cc

| Signal | Direction | Crossing |
| --- | --- | --- |
| Transmit rows | CoreClk to LaneClk | `olo_ft_fifo_async`, 16 rows, write side reset on link reset (flush); a row read with a DED goes to the Multi-Lane layer with all mask bits set, as a non-replicated row and with `Ml_TxRow_Poison` (CORE-ED-02) |
| Receive rows | LaneClk to CoreClk | `olo_ft_fifo_async`, 16 rows, read side reset on link reset; a full FIFO is reported as `Ev_RxOverflow` to the MIB, DL_ERRORS bit 10 (cannot happen while CoreClk is not slower than LaneClk); a row read with a DED is replaced by one RXERR (CORE-ED-02) |
| Link reset, LaneReset | CoreClk to LaneClk | `ofb_cc_pulse` with the rising edge of the levels of the Data Link layer: one pulse per entry into the link reset (CORE-PL-06); ORed in the lane clock domain with the hold of the lanes while the transmitters are not ready (section 4) |
| Transmitters ready (`Phy_TxReady`) | Asynchronous to CoreClk, LaneClk and MgmtClk (in `ofb_core`) | One `olo_base_reset_gen` per domain (section 4) |
| Near-end capability | CoreClk to LaneClk | `olo_base_cc_bits` (the bits are independent) |
| Lane active | LaneClk to CoreClk | `olo_base_cc_bits` |
| Far-end capability and "no lane active" | LaneClk to CoreClk | `olo_ft_fifo_async` (4 entries), event and qualifier in one word |

## 3. Resets

`olo_base_reset_gen` with `SyncTmr_g` = true per domain synchronises the asynchronous `Rst` input with three
synchroniser chains and a majority voter, so that an upset does not reset a domain; inside the domains all resets are
synchronous and high-active.

## 4. Transmitters ready

`Phy_TxReady` is asynchronous to the core. A transceiver stops its transmit clock while its transmitters are reset:
in `ofb_pa_gty` the reset controller of the transceiver wizard clears the `BUFG_GT` of `LaneClk` while the transmit PMA
of a channel is in reset, and `CoreClk` may be the same clock. A level sampled in `LaneClk` would stay 1 while the clock
stands still. The input therefore drives three `olo_base_reset_gen` (`RstInPolarity_g` = '0', `SyncTmr_g` = true)
(CORE-PL-04):

| Domain | Hold | Use |
| --- | --- | --- |
| CoreClk | `TxHoldCore` | Data Link layer: Near-End Reset with link reset and LaneReset held (DL-LR-06) |
| LaneClk | `TxHoldLane` | Lane and Multi-Lane layers: link reset and LaneReset of all lanes, ORed with the entry pulses of the crossing in `ofb_core_cc` |
| MgmtClk | `TxHoldMgmt` | MIB: TX_READY and the TX_LOST flag (MG-ST-06), also while CoreClk and LaneClk stand still |

`Phy_TxReady` = 0 sets the input registers of the three synchroniser chains of each generator without a clock edge.
The outputs are asserted synchronously (`AsyncResetOutput_g` = false), because their users are synchronous: an output
that changed at any time would reach the synchronous reset inputs close to a running clock edge. After a clock stood
still, the hold of its domain is active from the second edge after the clock runs again, and it is released once the
chains have shifted out the set state after `Phy_TxReady` became 1. The lanes and the Multi-Lane layer therefore leave
every stop of `LaneClk` through a reset, also when a short pulse at the stop of the clock (the clear of a `BUFG_GT`,
AMD AM003) has corrupted their state. The input must be free of glitches: a register or a constant (user guide
section 4).

Two-cycle window after a restart of `LaneClk`: until the hold is active, the lanes and the Multi-Lane layer run for at
most two cycles in the state they had when the clock stopped and pass at most two words per lane to the Physical
layer. The transmitters are still in reset at that time: the reset controller of `ofb_pa_gty` releases the `BUFG_GT`
when the transmit PMA reset is done and asserts the user ready of the transmit PCS 32 cycles of `FreeRunClk` later, so
these words are not sent. The far end has lost the signal and is in its own link reset. When `CoreClk` is `LaneClk`, the
Data Link layer runs for the same two cycles in its old state before it enters Near-End Reset; an error it counts in
these cycles is reported together with TX_LOST, and the link is reset in any case.

Release order (CORE-PL-05). The holds of CoreClk and LaneClk are released independently, at most seven cycles of their
clocks after `Phy_TxReady` rises (three registers of the input chain, two synchroniser stages, the output register and
one cycle for a metastable first stage). With both clocks running the two releases differ by less than 50 ns at
156.25 MHz. Either order keeps the sequence of ECSS 5.7.9:

- Lanes first: a lane released from its hold starts in ClearLine, which lasts 2 us (LN-INIT-02, ECSS 5.5.2.4), and has
  to pass the INIT handshake before it reports a far-end capability. The Data Link layer leaves Near-End Reset before
  that time for any offset below 2 us, which holds for both clocks above 3.5 MHz.
- Data Link layer first: it waits in Check Far-End Reset until a lane reports the far-end capability; it checks
  received words and counts errors only in Link Initialised (DL-LR-05).

TC-CORE-24 forces an offset of 1 us in both orders; TC-CORE-21 and TC-CORE-23 also run with LaneClk at 78.125 MHz
(`halfrate`), where the Data Link layer is released clearly first.

Entry pulses (CORE-PL-06). The Data Link layer holds its link reset and LaneReset as a level for the whole Near-End
Reset, which lasts as long as the transmitters are not ready; the level resets its own blocks and the row FIFOs of
`ofb_core_cc`. The pulse crossing receives only the rising edge of the level (a register in CoreClk, set by the reset
of the domain, so that the release of the reset is no entry). A held level at the crossing would repeat the pulse
after every transfer, and the last repetition would reach the Multi-Lane layer up to two transfers after the Data Link
layer left Near-End Reset. While the transmitters are not ready the lanes get the level from `TxHoldLane`. Two entries
within one transfer (about four cycles of each clock) give two pulses, the second one after the first transfer.

First rows of a link. After a link reset of one cycle the entry pulse reaches the Multi-Lane layer a few cycles after
the Data Link layer left Near-End Reset, when it may already have written its first rows (FCT) into the transmit FIFO.
The Multi-Lane layer takes rows only while it can send them: in Both-Ends Ready, and in the bypass while lane 0 is
Active (ML-DS-06, ML-BP-04). Every link reset resets the lanes as well, and a lane becomes Active only after its
initialisation, so a pulse never discards a row of the new link. A LaneReset that reaches a lane in ClearLine does not
restart its 2 us (ECSS 5.5.2.4): pulses shortly after the release of a hold do not delay the lane initialisation.
TC-CORE-27 checks the pulses at the ports of `ofb_core_cc`; TC-CORE-21 to TC-CORE-26 run with one lane and CoreClk at
the frequency of LaneClk (`eqclk`), where the first rows reach the Multi-Lane layer within a few cycles of the entry
pulse.
