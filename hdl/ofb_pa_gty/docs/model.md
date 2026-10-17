# ofb_pa_gty: Behavioural Model

## 1. Purpose

The architecture `mdl` of `ofb_pa_gty` is a behavioural model of the Physical adapter for GHDL and QuestaSim. It has
the ports and generics of the transceiver wrapper (architecture `struct`), so a system that uses `ofb_pa_gty` can be
simulated without the AMD transceiver model and without the AMD simulation libraries. The serial pins carry the 8B/10B
bit stream at the line rate: two models connect pin to pin like two transceivers, and the protocol stack above sees the
same symbol streams, ready signals and status as with the transceiver.

## 2. Architectures and source lists

| Architecture | File | Flows |
| --- | --- | --- |
| `struct` | `src/ofb_pa_gty_struct.vhd` | Synthesis (AMD Vivado) and the AMD simulator with the transceiver model (`tools/run_xsim.py`) |
| `mdl` | `sim/ofb_pa_gty_model.vhd` | GHDL and QuestaSim |

The entity is in `src/ofb_pa_gty.vhd` and has no vendor library. A flow analyses exactly one architecture into its
library, so that the default binding cannot pick the wrong one:

- `compile_order.txt` lists the entity and `struct` (with the transceiver wizard instance `ofb_gtw`, created by
  `tcl/ofb_gtw.tcl`);
- `compile_order_sim.txt` lists the 8B/10B package, the control package `sim/ofb_pa_model_pkg.vhd`, the entity and
  `mdl`.

Both lists follow the compile order of the core (`compile_order.txt` of the repository). `python run.py
--compile-order` fails when a list misses its architecture or contains both. The model testbench and the core
harness bind the architecture explicitly (`entity work.ofb_pa_gty(mdl)`). The end-to-end testbench
`ofb_pa_gty_core_tb` uses the default binding: the AMD simulator runs it with `struct`, GHDL and QuestaSim with
`mdl` through the VUnit wrapper `ofb_pa_gty_model_core_tb`.

## 3. Generic and control record

The model uses the generics of the entity (`NumLanes_g`, `RstPulseCycles_g`; `SimDevice_g` has no effect) and one
generic of its own, `ModelIdx_g` (default 0, ignored by `struct`): the index of its control record in the signal
`PaModelCtrl` of `ofb_pa_model_pkg` (indices 0 to 7). A testbench assigns the record; the defaults give a correct
link.

| Field | Default | Meaning |
| --- | --- | --- |
| `PowerUpTime` | 43.745 us | A reset sequence starts at the end of the stretched reset, but not before this time after the start of the simulation (the transceiver model completes its power-up first) |
| `TxDoneStale` | 27.9 us | The transmit reset done shows 1, the state of the previous start, for this time after the end of the stretched reset, until the master reset of the transceiver starts and at the latest until `LaneClk` starts; `Stat_TxReady` ignores it |
| `ClkDelay` | 20.342 us | `LaneClk` starts this long after the start of the sequence (transmit PLL locked) |
| `TxReadyDelay` | 21.13 us | `Stat_TxReady` (register of `FreeRunClk`) after the start of the sequence, later than `ClkDelay`; `LaneRst` is released two `LaneClk` cycles later |
| `RxReadyDelay` | 3.33 us | `Stat_RxReady` after `Stat_TxReady`; the receivers decode from then on |
| `CdrLockTime` | 17.1 us | The receiver decodes words this long after the first transition of a signal at its pins (after electrical idle or a reset of the adapter): the lock time of the clock-data recovery |
| `NoSignalDelay` | 100 ns | `Phy_NoSignal` after the line became idle |
| `Lane(l).TxInvert` | false | Transmitted pair crossed (P and N swapped) |
| `Lane(l).SkewUi` | 0 | Additional delay of the transmitted bits in unit intervals (lane skew; a change shifts the bit stream) |
| `Lane(l).Idle` | false | Electrical idle on the pins (loss of signal) |
| `Lane(l).ErrReq` | 0 | Every increment inverts one bit of the next transmitted word |
| `Lane(l).BurstReq`, `BurstLen` | 0, 8 | Every increment sets `BurstLen` consecutive bits of the next word to '0' (a dropout, always detected by 8B/10B) |
| `Lane(l).ErrEvery` | 0 | One inverted bit every `ErrEvery` transmitted bits (0: off) |

The default reset sequence is that of the transceiver model in the AMD simulator, measured with
`ofb_pa_gty_core_tb`. At power-up (four lanes, the reset of the adapter released at 200 ns, the stretched reset of
1000 cycles of `FreeRunClk` ends at about 10.21 us) the reset done of the wizard shows 1 from 10.225 us to 38.135 us
(`TxDoneStale`), the first `LaneClk` edge comes at 64.097 us, `Stat_TxReady` rises at 64.885 us and `Stat_RxReady` at
68.212 us (`RxReadyDelay` after `Stat_TxReady`), at both ends and with one to four lanes. The transceiver model
completes its power-up first, so these times do not follow the end of the stretched reset: a system testbench whose
stretched reset ends at 6.0 us reaches TX ready at 64.83 us. A later reset is shorter: the full run of 2026-10-16
resets the adapter of A in operation with a request of 100 ns; `Stat_TxReady` of A falls at 197.485 us and rises
again at 228.725 us, 31.15 us after the end of the request, 21.13 us after the end of the stretched reset
(`TxReadyDelay`). `ClkDelay` keeps the distance of the first `LaneClk` edge to TX ready at power-up (0.788 us), and
`PowerUpTime` is chosen so that the power-up sequence reaches TX ready at 64.885 us.

`CdrLockTime` is the value of the transceiver simulation model, measured with `ofb_pa_gty_core_tb` (one lane, run of
2026-10-17, timeline of the receive side at the adapter outputs): the first valid word arrives 17.21 us after the far
end starts to send, at both ends (A sends from 66.151 us, B receives from 83.357 us; B sends from 66.491 us, A
receives from 83.700 us), without any word with a code or disparity error before; the Lane layer then counts 1023
words in Started (6.5 us). The receivers are ready earlier (68.212 us), so the lock and not the reset of the receivers
sets the time of the link initialisation. It is not the lock time of the silicon (typically 50,000 UI, 8 us at
6.25 Gbit/s, in the data sheet; user guide section 5.5): a system testbench that does not compare with the transceiver
model may set `CdrLockTime` lower (the model testbench uses 500 ns for its short reset sequence, the error recovery
tests of the core testbench in pin mode 500 ns as protocol tests). The model applies the lock time after every return
of the signal, also when a lane restarts in operation (run `lanes1_relock` of the model core testbench).

## 4. Behaviour

- Clocks: `LaneClk` is `RefClk` once the clock delay has passed (156.25 MHz at 6.25 Gbit/s, as the transmit output
  clock of the wizard configuration). The unit interval is the `RefClk` period divided by 40, measured on the rising
  edges, so two ends with different reference clocks run at different line rates.
- Transmitter: per `LaneClk` cycle the four symbols of a lane are encoded with 8B/10B and running disparity and sent as
  40 bits, symbol 0 first and bit a of a symbol first. While the adapter is in reset, not ready, the transmitter
  disabled (`Phy_TxEnable`) or idle by control, both pins are '0' (electrical idle).
- Receiver: the bits between two transitions are counted in the own unit interval. Symbols align on the 7-bit comma
  (0011111 or 1100000) and realign on a comma in another position; the decoder flags code and disparity errors; a word
  starts with a comma symbol (K28.1, K28.5, K28.7), so the comma is in symbol 0. `Phy_RxInvert` inverts the received
  bits. Without signal, while the receiver or the clock-data recovery is disabled, or before the receivers are ready,
  no word is received and the alignment is lost.
- Receive buffer: 64 words per lane into `LaneClk`. The output starts at 16 words; above 24 words a SKIP word is
  removed, below 8 words a SKIP word is repeated (`Stat_ClkCor`, one pulse per correction). A full or empty buffer
  sets `Stat_RxBufErr`.
- Status: `Stat_Aligned` per lane, `Phy_NoSignal` after the no-signal delay, `Stat_TxReady` (register of
  `FreeRunClk` that takes the transmit reset done only after it was 0 once since the release of the reset, as in
  `struct`), `Stat_RxReady`, `LaneRst` (set without a `LaneClk` edge while the transmitters
  are not ready, released two `LaneClk` cycles after `Stat_TxReady`). A reset through `Rst` stops `LaneClk` until
  `ClkDelay` after the start of the new sequence, as the reset controller of the transceiver stops the user clock.
- Serial loopbacks: near-end, the receiver gets the own transmitted bits (the pins are still driven); far-end, the
  received bits are sent back on the pins.
- PRBS test: PRBS-7, -9, -15, -23 and -31 generator and checker per lane on the bit stream (encoding of the
  transceiver, 1 to 5), bypassing 8B/10B; force error inverts one bit; the self-synchronising checker locks after 64
  correct bits and counts an error per wrong bit while locked (a forced error is seen at the bit and at the two taps
  that use it); `Phy_PrbsErr` per `LaneClk` cycle with an error.

## 5. Limits

- No analogue behaviour: no equalisation, jitter, eye or attenuation; a bit is either correct or changed by the control
  record.
- No lock process of the PLL and of the clock-data recovery: the ready delays and the lock time are fixed; the
  receiver follows any frequency difference.
- `Stat_Aligned` rises with the first comma decoded after the lock; the transceiver model reports the byte alignment
  already about 1.6 us after its transmitters are ready, before it delivers valid words (no effect on PA-MD-10). A
  system test must not depend on the time of `Stat_Aligned`.
- `Phy_NoSignal` falls with the first transition at the pins; the signal detection of the transceiver model takes about
  0.32 us (no effect on PA-MD-10).
- No power-up, DRP or reset sequence of the transceiver in detail, and no reset of the transmit datapath of the quad on
  a change of the far-end loopback.
- The datapath latency is close to, not equal to, the transceiver: one `LaneClk` cycle in the transmitter, the
  serialisation, 16 words in the receive buffer.
- A change of `TxInvert` takes effect with the next transmitted bit.

## 6. Simulation speed

GHDL 6.0 (mcode), 6.25 Gbit/s: the serial path of four lanes in both directions costs about 44 s of processor time per
simulated millisecond (two models). Two cores `ofb_core` with traffic cost about 1000 to 3000 s per simulated
millisecond, so the model adds a few percent to a system simulation.

## 7. Use in a system testbench

```vhdl
library openfibre;
    use openfibre.ofb_pa_model_pkg.all;

-- One adapter per end; the pins of the two ends crossed
i_pa_a : entity openfibre.ofb_pa_gty(mdl)
    generic map (NumLanes_g => 4, ModelIdx_g => 0)
    port map (..., Gt_TxP => LineAtoB_P, Gt_TxN => LineAtoB_N, Gt_RxP => LineBtoA_P, Gt_RxN => LineBtoA_N, ...);

-- In the test sequencer: a shorter reset sequence and a bit error on lane 2 of end A
PaModelCtrl(0).PowerUpTime       <= 0 ns;
PaModelCtrl(0).TxReadyDelay      <= 5 us;
PaModelCtrl(0).ClkDelay          <= 2 us;
PaModelCtrl(0).Lane(2).ErrReq    <= PaModelCtrl(0).Lane(2).ErrReq + 1;
```

`PaModelCtrl` is an unresolved signal: drive it from one process, or from several processes with static element
names (a loop index in an element name makes the process drive the whole array).

The model drives `LaneClk` and clocks its own lane clock processes with the port, so a design on `LaneClk` sees each
edge in the same delta cycle as the model and samples the outputs of the previous edge.

The far end of a system can also be a model of another SpaceFibre device that drives the pins with the 8B/10B bit
stream.

In OpenFibre the model runs under the full protocol stack in two places:

- the core testbench, configuration `lanes4_pin` (TC-CORE-01, 02, 03 and 16 with four lanes): two models pin to pin
  instead of the word-level channel model, each core on the lane clock of its adapter, `Phy_TxReady` from
  `Stat_TxReady` and `Phy_BitSync` from `Stat_Aligned`;
- `ofb_pa_gty_model_core_tb`: the end-to-end testbench of the adapter (TC-PA-02) with the model, compared with the
  run of the transceiver model in the AMD simulator (PA-MD-10).
