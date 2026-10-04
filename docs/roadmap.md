# OpenFibre Roadmap

The development follows the migration path of the [architecture](architecture.md) (section 11). This page tracks
the state of every module; a module is done when its verification report is written and its regression is green.

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
| `ofb_ni` | NI-1 to NI-4 | 2 (NI-1, NI-3), 3 (NI-2, NI-4), 4 (beats) | Done (VC ports of 1 to 4 words per beat with framing check, broadcast port, schedule port; VN number in the MIB) |
| `ofb_mib` | MG-1 to MG-4, TA-1 | 2, 4 (Multi-Lane registers), 5 (MG-3 EDAC monitor), later (TA-1) | Done except TA-1 (MG-1, MG-2 with QoS and Multi-Lane registers, MG-3 EDAC monitor with error injection; MG-4 in the core top level) |
| `ofb_pa_gty` | PA-1 for the Versal GTY (PA-2, PA-3 in the transceiver) | 2 | Planned |
| `ofb_core` | Core top level | 2, 4, 5 | Phase 4 done (1 to 4 lanes, four clock domains, core testbench with 1, 2 and 4 lanes) |
| `ofb_vck190` | VCK190 board top level and constraints | 5 | Planned |

## Dependencies outside this repository

| Item | State |
| --- | --- |
| `olo_ft_cc_simple`, `olo_ft_cc_status`, `olo_ft_cc_handshake` (Open Logic fault-tolerant backlog) | Implemented in the backlog, not yet pushed; `olo_base_cc_status` is used until the submodule is repinned |
| Synthesis licence for the XCVC1902 | Open |
| Lab set-up with STAR-Dundee equipment for the phase 2 exit criterion | Open |
