# OpenFibre Roadmap

The development follows the migration path of the [architecture](architecture.md) (section 11). This page tracks
the state of every module; a module is done when its verification report is written and its regression is green.

## Technology readiness

The core is at **TRL 3**: fully verified by simulation, not yet tested on hardware, no flight heritage. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 4 | Timing closure on a representative FPGA; hardware test in the laboratory against the functional and performance requirements, ideally against independent SpaceFibre equipment; hardware test plan and test report | Timing closure on the XCVC1902 met (third build; fourth build with margin; see the hardening items); a build with the packet ports of the VCs and the hardware test on the VCK190 with STAR-Dundee equipment open |
| TRL 5 | Radiation-tolerant target FPGA with transceivers for SpaceFibre; single-event effects test (beam test) with the core in operation that confirms the single-event mitigation and quantifies the error rates; operation over the temperature range | Open |

## Phases

| Phase | Content | Exit criterion |
| --- | --- | --- |
| 1 Foundations | Repository, regression runner, common package, shared verification components | Regression runs in CI |
| 2 Single-lane core | Lane layer, Multi-Lane bypass with column codec, Data Link with 8 VCs, MIB, VC and broadcast ports, PA-1 for the VCK190 GTY | Link and traffic between two cores in simulation; with STAR-Dundee equipment on the VCK190 |
| 3 Complete Data Link | QoS, 32 VCs, virtual networks, schedule service (data scrambling is done in phase 2) | All Data Link clauses verified |
| 4 Multi-Lane | 2 and 4 lanes, alignment, asymmetric links, unidirectional and hot redundant lanes | All Multi-Lane clauses verified |
| 5 Hardening | Fault injection campaigns, resource and timing closure, final top-level end-to-end test with the GTY model | Release |

## Modules

| Module | Blocks (architecture section 7) | Phase | Status |
| --- | --- | --- | --- |
| `ofb_pkg` | Common constants and types (ECSS symbols, control words, CRC, PRBS) | 1 | Done |
| `tb` (shared) | Verification helpers, behavioural PA model, SpaceFibre reference model | 1, 2 | In work |
| `ofb_lane` | LN-1 lane initialisation, LN-2 transmitter, LN-3 receiver, LN-4 parallel loopback | 2, 4 (SKIP request) | Done (1 word per clock; SKIP on request of the Multi-Lane layer) |
| `ofb_multilane` | ML-1 to ML-6 | 2 (bypass, column codec), 4 | Done (1 to 4 lanes: alignment, asymmetric links, unidirectional and hot redundant lanes, bypass) |
| `ofb_dl` | DT-1 to DT-8, DR-1 to DR-7, DC-1, DC-2 (Data Link layer) | 2, 3 (QoS, continuous mode), 4 (rows of several words) | Done (priority, bandwidth reservation, schedule, continuous mode; rows of 1 to 4 words, banked input VC buffer) |
| `ofb_ni` | NI-1 to NI-4 | 2 (NI-1, NI-3), 3 (NI-2, NI-4), 4 (beats) | Done (packet ports of 4 to 16 bytes per beat with `TKEEP`, `TLAST` and EEP flag: end markers and Fills on transmission, Fill removal and alignment on reception, framing checks in both directions; broadcast port, schedule port; VN number in the MIB) |
| `ofb_mib` | MG-1 to MG-5 | 2, 4 (Multi-Lane registers), 5 (MG-3 EDAC monitor, MG-5 PRBS test) | Done (MG-1 with the register map generated from one description, MG-2 with QoS and Multi-Lane registers, MG-3 EDAC monitor with error injection, MG-5 PRBS test counters; MG-4 in the core top level) |
| `ofb_pa_gty` | PA-1 for the Versal GTY (PA-2, PA-3 in the transceiver) | 2, 5 | Done in simulation (transceiver wizard, loopback test, PRBS generator and checker, reset sequences of a lane (entire receiver reset, transmit buffer reset, receive elastic buffer reset), end-to-end test of two cores over the transceiver model in xsim); synthesis and hardware test open |
| `ofb_core` | Core top level | 2, 4, 5 | Phase 4 done (1 to 4 lanes, four clock domains, core testbench with 1, 2 and 4 lanes); phase 5: EDAC with DED containment, synthesizability check, [compliance matrix](compliance.md), fault injection campaign, throughput and latency measurement |
| `ofb_vck190` | VCK190 board top level and constraints | 5 | Reference design (echo, LEDs, clocks of the CIPS, MIB access over JTAG through the CIPS), constraints and build script; top-level test with the transceiver model; first build (device image, timing not met) analysed and its findings fixed; rebuild and hardware test open |

## Open hardening items (phase 5)

| Item | State |
| --- | --- |
| Fault injection campaign at core level (TC-CORE-13): line errors, word slips, lane failures, SEC in every EDAC channel, DED in the row crossings | Done in simulation (5 seeds x 3 lane configurations, 600 faults); found the loss of held words in Not Ready (ML-DS-12), the silent DED corruption in the row crossings (CORE-ED-02) and the latency of the receive error state machine (DL-RE-01) |
| DED containment in the Data Link buffers (VC, broadcast, error recovery and frame buffers) | Done: link reset for the transmit buffers and the frame buffer, EEP for the input VC buffers, discarded broadcast message (DL-ED-01, DL-ED-02, TC-CORE-14) |
| Code coverage of the regression (QuestaSim) | Done: statements, branches and state machines closed or justified ([coverage.md](coverage.md)); the first measurement found untested behaviour (input buffer overflow, Interface Reset of the link reset state machine, exits of the lane initialisation, control word errors), closed by 12 new or extended tests. Releases 0.1.1 and 0.1.2 are verified with GHDL and the AMD Vivado simulator; their changed lines are not measured yet ([coverage.md](coverage.md), section 6) |
| Resource and timing closure on the XCVC1902 | First build: 43852 LUT, 32239 registers, 42 block RAM tiles, 8 DSP; timing not met in the input VC buffers (fixed: register stage per bank); latches of `olo_ft_cc_pulse` replaced by the latch-free `ofb_cc_pulse`. Second build: 46507 LUT, 44618 registers, 54.5 block RAM tiles; WNS -0.055 ns in the beat formation of the input VC buffers (fixed: end flags before the bank stages), lane clock +0.280 ns (column encoder input stage, output register of the receive frame buffer, implementation strategy with post-route optimization). Third build: timing met (WNS +0.030 ns, WHS +0.012 ns), 47992 LUT, 47212 registers, 37 block RAM tiles; beat logic of the input VC buffers without arithmetic and the triplicated synchronisers of Open Logic 4.7.0-ft.2. Fourth build (dac538f): timing met with margin. The packet ports of the VCs (NI-1, register map version 7) need a new build; hardware test open |
| Repeated receiver resets of a lane without a gap (`RxRstGapCycles_g` = 0) when a reset on the device lasts about as long as the initialisation timeout | Documented with its signature and the remedy at run time (LANE_INIT_TIMEOUT, user guide); an automatic remedy (a gap that grows after receiver resets without Active) follows if the hardware test shows the cycle |

## Dependencies outside this repository

| Item | State |
| --- | --- |
| Triplicated synchronisers (`SyncTmr_g`) in the Open Logic crossings, the reset generator and the input synchroniser (Open Logic fault-tolerant fork) | Done: in the pinned tag of the submodule; used for every crossing, the reset synchronisation per domain and the asynchronous transceiver status |
| Lab set-up with STAR-Dundee equipment for the phase 2 exit criterion | Open |
