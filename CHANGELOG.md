# Changelog

The notable changes of OpenFibre. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the register map, a minor version for a feature and a patch
version for a fix.

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
