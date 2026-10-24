# Changelog

The notable changes of OpenFibre. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the register map, a minor version for a feature and a patch
version for a fix.

## [Unreleased]

### Changed

- `ofb_dl`: the error recovery buffer registers each admitted data word with its row write, the commit of its item
  and the error injection command and writes the row one cycle later (DL-ER-09). In the laboratory build the path
  from the read register of an output VC buffer through its ECC decoder, the VC multiplexer of the admission and the
  ECC encoder of the buffer RAM missed the lane clock period (worst slack -0.620 ns at 156.25 MHz); the register
  splits it. Every item reaches the transmitter one lane clock cycle later (the transmit path is store and
  forward); the admission sees the same free space, and no port, generic or register changes. New test case
  TC-DL-32 (items read right after their commit, error injection and NACK across the stage).
- Verification: `python tools/compliance.py --check` also fails when `docs/compliance.md` is out of date (the matrix
  is generated in memory and compared with the file), and the CI runs the check, with a step that shows that a stale
  matrix fails it. The generated matrix is reproducible: test case entries of the same group and number (test names
  with their test case in brackets) were ordered by the iteration order of a set, which changes with the hash seed
  of every Python process.

### Fixed

- `ofb_vck190`: the clock pair constraints of `ofb_vck190.xdc` were lost in every build since the reference clock
  became selectable (release 0.1.1): `tcl/build.tcl` read the clock constraint of the reference clock after
  `ofb_vck190.xdc`, so the lane clock, derived from it through the transceiver, did not exist when the constraints
  were read. The crossings between the lane clock and the clocks of the CIPS were timed as synchronous paths (setup
  violations of more than 5 ns), and the two constraints with `clk_pl_0` covered every path of that clock, so its
  hold was not analysed. The script now reads the clock constraint first (processing order EARLY).
- `ofb_vck190`: `tcl/build.tcl` checks the constraint integrity (`tcl/build_checks.tcl`) and stops the build when a
  constraint did not apply in synthesis or implementation or when TIMING-6, TIMING-7 or TIMING-47 report a clock pair
  without its constraint; the known Open Logic constraint of the retimed distributed RAM read register is counted as
  the one exception. The timing summary (TIMING NOT MET or timing met) goes to the console and to `build_info.txt`,
  with `results/constraint_check.txt`. The CI runs the checks on excerpts of logs and reports
  (`tcl/test/build_checks_test.tcl`).
- `ofb_vck190`: `tcl/build.tcl` sets `XILINX_LOCAL_USER_DATA=no` for the runs of `launch_runs` (AMD AR 63253). On a
  fresh installation of Vivado the runs that start at the same time create the user directory of the Tcl Store
  together, and one of them can fail at start-up with Common 17-1257 ("Failed to create directory") and
  "tclapp::load_apps failed".

## [0.1.3] - 2026-10-24

The transceiver handling of `ofb_pa_gty` follows the recommendations of the transceiver documentation (AM002, PG331,
PG442) more closely. In the laboratory, with releases 0.1.1 and 0.1.2, no lane of the VCK190 design reached Active
with the far end used there: the transmitters were ready and the receivers bit-synchronised, but the lanes stayed in
Started (LANE_TIMEOUT_COUNT saturated at 0xFFFF) and never received 1023 words without error after INIT1. All
interface changes are additive (new registers in reserved fields of register map version 9, new ports with defaults);
the generic `InitTimeoutWords_g` moved from the internal units `ofb_lane` and `ofb_lane_init` to `ofb_core`, where it
is the reset value of LANE_INIT_TIMEOUT.

### Added

- `ofb_pa_gty`: entire receiver reset of one lane, the other lanes undisturbed (PA-RS-04): GTRXRESET with
  PCSRSVDIN[10] in sequential mode, all reset masks and PCSRSVDIN[9:8] held until RXRESETDONE (AM002, receiver reset in
  response to a GTRXRESET pulse in full sequential mode), the reset AM002 recommends after the remote end powers up,
  after electrical idle and after connecting the line. It runs when a lane leaves the states that use the line (CDR
  enable falling) and on a command per lane; the words of the lane are not valid while it runs. Optionally a CDR reset
  only. Every wait for the transceiver is bounded, with a timeout event (PA-RS-05). Transmit buffer reset after a
  transmit buffer error (PA-RS-06). CDR hold while the receiver reports electrical idle (PA-IF-04). Status per lane:
  RXRESETDONE, receiver reset in progress, CDR lock, electrical idle, transmit buffer error, receiver reset events
  (PA-ST-03). New generics `RxRstDoneCycles_g`, `CdrWaitCycles_g`, `RxRstGapCycles_g`, configuration inputs
  `Cfg_RxResetOnDisc`, `Cfg_RxResetCdrOnly`, `Cfg_CdrHoldIdle`, `Cfg_PcsRsvdIn`, the command `Cmd_RxReset` and the
  status outputs. The reset sequences of a lane are one entity, `ofb_pa_gty_lane_rst`, used by both architectures.
- Register map version 10 (ID 0x0FB1000A): LANE_INIT_TIMEOUT (0x07C, initialisation timeout of the lanes), PA_CTRL
  (0x080, receiver reset on disconnection, CDR-only reset, CDR hold, PCSRSVDIN), LANE_CTRL bit 18 RX_RESET, LANE_STATUS
  bits 27:24, LANE_EVENTS bits 7:4 with IRQ_MASK bits 23:20, LANE_TIMEOUT_COUNT bits 31:16 RX_RESETS (completed
  receiver resets, saturating). Every new field was reserved in version 9.
- `ofb_core`: generic `InitTimeoutWords_g` (reset value of LANE_INIT_TIMEOUT, default 5000, the value of the
  standard) and the control and status ports of the receiver reset (`Phy_RxResetOnDisc`, `Phy_RxResetCdrOnly`,
  `Phy_CdrHoldIdle`, `Phy_PcsRsvdIn`, `Phy_RxResetCmd`; inputs `Phy_RxBufErr`, `Phy_TxBufErr`, `Phy_RxResetDone`,
  `Phy_RxResetBusy`, `Phy_CdrLock`, `Phy_RxElecIdle`, `Phy_EvRxReset`, `Phy_EvRxResetTimeout` with default 0).

### Changed

- `ofb_pa_gty`, transceiver wizard (`tcl/ofb_gtw.tcl`): user clock from TXPROGDIVCLK (156.25 MHz from the LCPLL);
  comma mask 0011111111; clock correction periodicity setting 2000 (the Lane layer still sends SKIP every 5000 words,
  ECSS 5.5.3d); elastic buffer reset on comma alignment; out-of-band detection enabled (receive electrical idle for the
  CDR hold); the channel reset, CDR and debug ports for the reset sequences. PCSRSVDIN is 0x0360 outside the reset
  sequences (bits 9:8 set and bit 10 clear, as the reset sequences require), a transceiver setting for laboratory use
  that PA_CTRL can change at run time; the wizard ties it to 0x0240. The line driver settings of the wizard
  (TXDIFFCTRL 11001, TXMAINCURSOR 77, no pre-cursor or post-cursor) are used unchanged.
- `ofb_lane`: the initialisation timeout is the input `Cfg_InitTimeout` (24 bits, words, default 5000) instead of the
  generic `InitTimeoutWords_g`.
- `ofb_vck190`: initialisation timeout of 468750 words (3 ms) and a receiver reset at every restart of a lane (no gap),
  so a restarted lane stays in Started while its receiver resets; a documented deviation from ECSS 5.5.2.6b.1
  (specification of `ofb_vck190`, section 5). The adapter and the core are connected with all new ports.
- Behavioural model `ofb_pa_gty(mdl)`: the reset sequencer of `struct`, the receiver reset with the control fields
  `RxResetTime` and `RxResetHang`, and the transmit buffer error `TxBufErrReq`.
- `lint/synth_check.py`: the configuration of the watchdog bound 1024 sets the join hold to 1024 (the default of 8192
  exceeds the watchdog, which the Multi-Lane layer rejects); the bounds of `InitTimeoutWords_g` are synthesised.
- Verification: the test end (`ofb_tb_pkg.ofbTestEnd`) compares the alert counters of every level itself and ends
  the simulation with a failure, whatever the stop limits of the test.

### Verification

- GHDL: the full regression in the CI of the release pull request, on the released tree; 423 of 423 in the CI of the
  feature pull request (runs 39987693049 and 40060386480). New tests: the reset sequencer (TC-PA-19 to TC-PA-24), the
  receiver reset with the behavioural model (TC-PA-25), the MIB registers of the receiver reset (TC-MG-12, RX_RESETS
  saturation in TC-MG-09), the core through the adapter models (TC-CORE-37), the initialisation timeout from the
  input (TC-LN-54). A mutation check of the new logic killed 21 of 21 mutants.
- AMD Vivado simulator with the transceiver model, with the wizard instance created again by the changed
  `tcl/ofb_gtw.tcl`, 11 of 11 runs on a tree that differs from the released one in Markdown files and two comment
  lines: the tests of `ofb_pa_gty`, `ofb_pa_gty` with two cores (one to four lanes; the lane restart with the entire
  receiver reset, also with the settings of `ofb_vck190`) and `ofb_vck190` (records in the verification reports of
  `ofb_pa_gty` and `ofb_vck190`). The entire receiver reset of one lane takes about 6.3 us in the model.
- The QuestaSim regression and the code coverage were not repeated; the changed lines are listed in
  [coverage.md](docs/coverage.md), section 6.

## [0.1.2] - 2026-10-23

### Fixed

- `ofb_pa_gty`: the receive elastic buffer of a lane was never reset; the lane initialisation depended on the buffer
  recovering by itself after the recovered clock had become stable. The adapter now resets the buffer of a lane
  alone (RX component reset in single mode, as AM002 recommends) after an overflow or underflow and once per lane
  start at the first comma alignment within a window after the start. The words of the reset window (a fixed
  length of 1.52 us) are not passed to the Lane layer; after the window the words pass as without the reset, so a
  frame across the window is recovered by a retry and an idle line still reaches the Lane layer as RXERR words
  (PA-RS-03).

### Changed

- `ofb_pa_gty`: new generic `RxBufReset_g` (default true; false keeps the behaviour of 0.1.1). The transceiver
  wizard instance enables the optional ports `ch_gtrxreset`, `ch_rxresetmode`, `ch_rxpcsresetmask`,
  `ch_rxpmaresetmask` and `ch_rxbyterealign`. `ofb_vck190` keeps the default.
- Behavioural model `ofb_pa_gty(mdl)`: with `RxBufReset_g` a receive buffer restarts at its start level after an
  overflow, every buffer error withholds the words of the reset window, and a running buffer reports a buffer error
  when the line becomes idle, as the transceiver model; the new field `BufErrReq` of the control record forces a
  buffer error. A reset during the reset sequence starts the sequence again; a reset of the transmitters restarts
  the PRBS generator, as the transmit PCS of the transceiver.
- Open Logic 4.7.0-ft.9 (none of the Open Logic units that OpenFibre uses changed from 4.7.0-ft.6).

### Verification

- GHDL: the full regression in the CI of the release pull request, on the released tree, with the new test of a
  forced reset of the receive buffer during traffic (TC-CORE-36). AMD Vivado simulator with the transceiver model,
  every run on the released tree: the tests of `ofb_pa_gty` (with the forced buffer errors of TC-PA-07),
  `ofb_pa_gty` with two cores (one to four lanes, lane restart through an idle line) and `ofb_vck190` (records in
  the verification report of `ofb_pa_gty`). The QuestaSim regression and the code coverage were not repeated; the
  changed lines are listed in [coverage.md](docs/coverage.md), section 6.

## [0.1.1] - 2026-10-22

### Fixed

- `ofb_multilane`: with three or four lanes, a lane that entered Active after the other lanes when the link started
  caused a realignment after the Data Link layer had started to send. The words in flight were replaced by RXERR and
  recovered by a retry, which showed as a sequence error (DL_ERRORS bit 3) and in DL_RETRIES at both ends; no data was
  lost. Present since 0.1.0. The Multi-Lane layer now holds the rows of the Data Link layer while an enabled lane is
  still initialising (join hold, ML-LM-17).
- `ofb_pa_gty`: NoSignal is always de-asserted (ECSS-E-ST-50-11C 5.4.2.4b.1). It came from the receive electrical
  idle of the transceiver, which in this configuration is a static 0 and cannot detect data above 2.5 Gbit/s; a lost
  signal reaches the Lane layer as RXERR words. An end with AutoStart only now leaves Wait at once.
- `ofb_pa_gty`: the receiver CDR runs in every lane state. It was held while the Lane layer disabled it, which the
  standard only recommends; a running CDR keeps the receiver locked between initialisation attempts.

### Changed

- `ofb_core`: new generic `LaneJoinHoldWords_g` (lane clock cycles, default 8192, at most `AlignTimeoutWords_g`
  while the alignment watchdog is on): the bound of the join hold; 0 keeps the behaviour of 0.1.0.
- `ofb_vck190`: the transceiver reference clock is selected when the image is built: the Si570 at 100 MHz (default,
  the frequency it runs at after power-up, so nothing has to be programmed on the board) or the 8A34001 at 156.25 MHz.
  `tcl/build.tcl` has a step `rtl` and collects the device image, the reports, the invalid constraints and
  `build_info.txt` in `results/` of the project directory.
- Behavioural model `ofb_pa_gty(mdl)`: `NoSignalNever` (default) replaces `NoSignalSequence`, the field
  `NoSignalTime` is removed, and `Phy_CdrEnable` has no effect.
- Documentation build: selectolax 1.0.0, so that the MkDocs site shows its images.

### Verification

- GHDL: the full regression in the CI of the release pull request, on the released tree. AMD Vivado simulator with
  the transceiver model: the tests of `ofb_pa_gty`, `ofb_pa_gty` with two cores (one to four lanes, lane restart) and
  `ofb_vck190` on the release tree.
  The QuestaSim regression and the code coverage were not repeated for this release; the changed lines are listed in
  [coverage.md](docs/coverage.md), section 6.

## [0.1.0] - 2026-10-18

First release: SpaceFibre core `ofb_core` per ECSS-E-ST-50-11C (Network interface, Data Link, Multi-Lane and Lane
layers, management information base), the Physical adapter `ofb_pa_gty` for the AMD Versal GTY with its behavioural
model, and the reference design `ofb_vck190`. TRL 3: verified by simulation (GHDL and QuestaSim, code coverage).
