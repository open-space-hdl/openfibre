# OpenFibre Roadmap

The development follows the migration path of the [architecture](architecture.md) (section 11). This page tracks
the state of every module; a module is done when its verification report is written and its regression is green.

## Phases

| Phase | Content | Exit criterion |
| --- | --- | --- |
| 1 Foundations | Repository, regression runner, common package, shared verification components | Regression runs in CI |
| 2 Single-lane core | Lane layer, Multi-Lane bypass with column codec, Data Link with 8 VCs, MIB, VC and broadcast ports, PA-1 for the VCK190 GTY | Link and traffic between two cores in simulation; with STAR-Dundee equipment on the VCK190 |
| 3 Complete Data Link | QoS, 32 VCs, data scrambling, virtual networks, schedule service | All Data Link clauses verified |
| 4 Multi-Lane | 2 and 4 lanes, alignment, asymmetric links, unidirectional and hot redundant lanes | All Multi-Lane clauses verified |
| 5 Hardening | Fault injection campaigns, resource and timing closure, final top-level end-to-end test with the GTY model | Release |

## Modules

| Module | Blocks (architecture section 7) | Phase | Status |
| --- | --- | --- | --- |
| `ofb_pkg` | Common constants and types (ECSS symbols, control words) | 1 | In work |
| `tb` (shared) | Verification helpers, behavioural PA model, SpaceFibre reference model | 1, 2 | In work |
| `ofb_lane` | LN-1 lane initialisation, LN-2 transmitter, LN-3 receiver, LN-4 parallel loopback | 2 | Planned |
| `ofb_multilane` | ML-1 to ML-6 | 2 (bypass, column codec), 4 | Planned |
| `ofb_dl_tx` | DT-1 to DT-8 | 2, 3 (QoS) | Planned |
| `ofb_dl_rx` | DR-1 to DR-7 | 2 | Planned |
| `ofb_dl` | DC-1 link reset, DC-2 statistics, Data Link layer top | 2 | Planned |
| `ofb_ni` | NI-1 to NI-4 | 2, 3 | Planned |
| `ofb_mib` | MG-1 to MG-4, TA-1 | 2 | Planned |
| `ofb_pa_gty` | PA-1 for the Versal GTY (PA-2, PA-3 in the transceiver) | 2 | Planned |
| `ofb_core` | Core top level | 2 | Planned |
| `ofb_vck190` | VCK190 board top level and constraints | 5 | Planned |

## Dependencies outside this repository

| Item | State |
| --- | --- |
| `olo_ft_cc_simple`, `olo_ft_cc_status`, `olo_ft_cc_handshake` (Open Logic fault-tolerant backlog) | In development |
| Synthesis licence for the XCVC1902 | Open |
| Lab set-up with STAR-Dundee equipment for the phase 2 exit criterion | Open |
