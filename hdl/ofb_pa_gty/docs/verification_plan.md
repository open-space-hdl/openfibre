# ofb_pa_gty: Verification Plan

## 1. Overview

The adapter is verified with the encrypted transceiver model of the AMD simulation libraries and the AMD simulator
(xsim): `python tools/run_xsim.py`. The script creates the transceiver wizard instance with Vivado,
exports its simulation sources, compiles them with Open Logic and the OpenFibre sources and runs the testbenches.
The GHDL regression cannot compile the transceiver model; all other tests use the behavioural Physical adapter model
(`tb/ofb_tb_pa_model.vhd`).

The testbenches use plain VHDL checks (`report` with "FAIL", "Simulation done" at the end) because the support of
UVVM in xsim is limited; the runner evaluates the log.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_pa_gty_tb` | `ofb_pa_gty` with four lanes, serial lines looped back (transmitter of each lane to its receiver), 156.25 MHz reference clock, 100 MHz free-running clock; a word generator per lane (data words counting up, IDLE words, SKIP words) and a checker per lane |
| `ofb_pa_gty_cc_tb` | Two `ofb_pa_gty` A and B with four lanes, serial lines crossed; per lane a word generator (counting data words, an IDLE word every 8 words, a SKIP word every 16 words) and a checker; counters of the clock corrections and receive buffer errors. Test run `cc`: reference clock of B 1000 ppm slower than that of A (exaggerated to reach many clock corrections in a short simulation). Test run `far`: same reference clock frequency, then far-end serial loopback at B |
| `ofb_pa_gty_core_tb` | Two ends A and B, each `ofb_core` (4 VCs, 4 lanes, all core clocks = `LaneClk`) with `ofb_pa_gty`, serial lines crossed; reference clocks 156.25 MHz at A and 200 ppm slower at B (the limit of 5.4.2.3a at both ends); AXI4-Lite access to both MIBs, packet generator and checker per VC and end, broadcast generator and checker, counter of the clock corrections per end |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| TC-PA-01 (`ofb_pa_gty_tb`) | Reset sequence: transmitter and receiver ready, `LaneClk` running; every lane aligned; 300 data words per lane received in order with K flags clear, IDLE and SKIP words with the K flag of symbol 0, no code or disparity error, no other lane's words | PA-IF-01, PA-SE-01, PA-SE-02, PA-SY-01, PA-CK-01, PA-RS-01, PA-RS-02, PA-ST-01 |
| TC-PA-04 (`ofb_pa_gty_tb`) | After TC-PA-01: external loopback removed (static lines), near-end serial loopback on every lane: 300 more data words per lane received in order without error | PA-LB-01 |
| TC-PA-06 (`ofb_pa_gty_tb`) | After TC-PA-04, external loopback again: PRBS-31 generator and checker of every channel: all checkers locked after the checker reset, no error during 5 us; the line of one lane inverted for 1 ns (about six bits): errors on that lane only, checker still locked, no error afterwards; a PRBS-7 checker on the PRBS-31 pattern detects errors | PA-PR-01 |
| TC-PA-05 (`ofb_pa_gty_cc_tb`, run `far`) | Both reference clocks at 156.25 MHz: words in order at both ends, then far-end serial loopback on every lane of B: A receives its own words, 3000 data words per lane in order without error | PA-LB-01 |
| TC-PA-03 (`ofb_pa_gty_cc_tb`, run `cc`) | At least 4 clock corrections at each end (SKIP words inserted at A, removed at B), no receive buffer error, 3000 data words per lane and end received in order without loss or repetition | PA-CC-01, PA-ST-01 |
| TC-PA-02 (`ofb_pa_gty_core_tb`) | Both cores reset with the reset pulse of the adapters, `Phy_TxReady` from `Stat_TxReady` (link held in Near-End Reset until the transmitters are ready); LaneStart at A, AutoStart at B: lane initialisation through the transceivers (ClearLine with electrical idle and CDR hold, polarity control), alignment of the four lanes, link initialised at both ends; a first burst of 12 packets per VC (1 to 40 words) and 4 broadcast messages in both directions; clock corrections at both ends (SKIP words inserted at one end, removed at the other); a second burst of 12 packets per VC; all delivered in order, no error flag in DL_ERRORS (bits 12:0, TX_LOST 0 after the start), no retry; throughout the run `Stat_TxReady` of each end is 1 only while its `LaneClk` runs, and every edge of `Stat_TxReady` and the first `LaneClk` edge are reported; then the adapter of A alone is reset with the link up: `LaneClk` of A stops (no edge for 1 us), the MIB of A reads TX_READY 0 and TX_LOST 1 while it stands still, both ends initialise the link again after the transmitters are ready, a third burst is delivered in order and TX_LOST stays set | PA-IF-01 to 03, PA-CC-01, PA-RS-02, PA-SE-01, PA-SE-02, PA-SY-01, CORE-PL-04, CORE-SY-01, CORE-SY-02, PA-ST-02 |
| TC-PA-02 with 1 to 3 lanes (runs `ofb_pa_gty_core_tb.lanes1` to `.lanes3`: `Lanes_g` = 1 to 3, `Short_g`) | Cores and adapters with one, two and three lanes, the other channels of the quad idle: link initialised at both ends with all lanes data-sending and data-receiving, first burst delivered in order, no error flag | PA-IF-01, PA-SY-01, CORE-SY-01 |
| TC-PA-02 lane restart (run `ofb_pa_gty_core_tb.relock`: `Lanes_g` = 1, `Short_g`, `Relock_g`) | After the first burst the transmitter of the lane of B is disabled at its adapter for 5 us (`CutNs_g`; the core of B is not told): the lane of A loses the signal and restarts (fails if lane 0 of A does not leave Active), B follows; reported: loss and return of the signal at each receiver, the first lane word decoded and the first 1023 words without error after the return, the lane states, LANE_TIMEOUT_COUNT of both ends; the lane is Active again at both ends within 300 us and a second burst is delivered in order without error | PA-IF-02, LN-INIT-03, LN-INIT-07 |

### Behavioural model

`ofb_pa_gty_model_tb` (VUnit, GHDL and QuestaSim): two `ofb_pa_gty(mdl)` A and B, pins crossed, 10 cycles of
reset stretching, configurations `lanes1` to `lanes4` with equal reference clocks and, for TC-PA-11 and TC-PA-18,
`lanes4_ppm1000` and `lanes1_ppmm1000` (reference clock of B 1000 ppm slower or faster). Per end and lane a generator
of numbered data words, a SKIP word every 8 words and an IDLE word every 32 words (or the PRBS pattern), and a checker
of the order and source of the data words, the error flags, the clock corrections and the buffer errors.

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link` (TC-PA-10) | Default reset sequence at power-up, the stretched reset of B ending 5 us after that of A, both before `PowerUpTime`: `LaneClk` `ClkDelay` and TX ready of both ends at the same time `TxReadyDelay` after `PowerUpTime`, the reset done of the previous start (`TxDoneStale`) does not show as TX ready, `LaneRst` released after TX ready, `Phy_NoSignal` 1 on every lane of both ends after TX ready and 0 at both ends `NoSignalTime` after `PowerUpTime`, RX ready after `RxReadyDelay`; every lane of B aligned `CdrLockTime` to `CdrLockTime` + 1 us after the transmitters of A are ready, and with signal; 2000 data words per lane and end in order, no error; no output of the lane clock domain changes in the delta cycle of a `LaneClk` edge (monitor at both ends over the whole test, which also counts the edges after which the received data changed); then a reset of A in operation: TX ready of A falls, `LaneClk` runs again `ClkDelay` and TX ready rises `TxReadyDelay` after the end of the stretched reset although `TxDoneStale` lasts beyond `ClkDelay`, every lane of B aligned again, 2000 data words per lane and end in order | PA-MD-01, PA-MD-02, PA-MD-03, PA-MD-05, PA-MD-11 |
| `test_clock_correction` (TC-PA-11) | 300 us of traffic: 30000 data words per lane and end in order without loss or repetition, no buffer error; with different reference clocks clock corrections at both ends | PA-MD-04 |
| `test_align` (TC-PA-12) | Lane skew of 3, 10, 17 and 24 unit intervals: every lane aligned and in order; a shift of the bit stream of lane 0 by 45 unit intervals during traffic: realigned, in order again | PA-MD-03, PA-MD-07 |
| `test_invert` (TC-PA-13) | Crossed pair at A: no correct words at B; with `Phy_RxInvert` at B: words in order | PA-MD-03, PA-MD-07 |
| `test_errors` (TC-PA-14) | Ten single bit errors: 10 to 30 words with code or disparity errors; a dropout of 20 bits: error words; a bit error rate of 1e-5 for 1 ms: 50 to 200 error words; words in order afterwards | PA-MD-03, PA-MD-07 |
| `test_idle` (TC-PA-15) | `NoSignalLine` at both ends: transmitter disabled: no signal at B after `NoSignalDelay` (+ 50 ns), lane not aligned; signal back; idle control: no signal; receiver or CDR disabled at B: no words; words in order afterwards. `NoSignalSequence` at B: transmitter of A disabled: `Phy_NoSignal` stays 0, 13 words with code errors and then more than 200 words without errors within 2 us, lane not aligned; words in order after the signal returns | PA-MD-06, PA-MD-07 |
| `test_loopback` (TC-PA-16) | Near-end serial loopback at A: A receives its own words on every lane; far-end serial loopback at B: A receives its own words through B | PA-MD-08 |
| `test_prbs` (TC-PA-17) | Every pattern (1 to 5) on every lane from A to B: checker locked, no error for 5 us, a forced error counted (1 to 3 erroneous bits: the bit and the two taps of the checker), locked again after the checker reset | PA-MD-09 |
| `test_buffer` (TC-PA-18) | Without SKIP words for 1 ms: receive buffer errors with different reference clocks, none with equal clocks | PA-MD-04 |
| TC-PA-02 (`ofb_pa_gty_core_tb`, GHDL with the model) | The end-to-end test of TC-PA-02 with `ofb_pa_gty(mdl)` in GHDL: times of TX ready, link initialised and first burst compared with the AMD simulator run; the lane restart with the checks of the AMD simulator run, with `Phy_NoSignal` as the transceiver model (run `lanes1_relock`: the Lane layer detects the loss) and following the line (run `lanes1_relock_line`: `Phy_NoSignal` shows the loss) | PA-MD-10, PA-MD-06 |

## 4. Coverage analysis

PA-IF-02 and PA-IF-03 are exercised by the lane initialisation of TC-PA-02 (the Lane layer drives line driver, line
receiver and CDR enable in ClearLine and uses NoSignal in Wait). A lane failure over the transceiver model is not
simulated: the behavioural model covers it in the core testbench (TC-CORE-07).

The transceiver model does not insert the forced error of the PRBS generator (`TXPRBSFORCEERR`): TC-PA-06 tests the
error detection of the checker with bit errors on the line instead. The path of the forced error from the register to
the adapter port is tested in the core testbench (TC-CORE-18) and the forced error itself on the hardware
(TC-VCK-HW-08).
