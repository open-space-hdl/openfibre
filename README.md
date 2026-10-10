# OpenFibre

[![TRL 3](docs/img/trl-3.svg)](https://openspacehdl.org/trl/)

OpenFibre is an open SpaceFibre implementation that is based on the Open Logic VHDL Library.

It implements a SpaceFibre port according to
[ECSS-E-ST-50-11C](https://ecss.nl/standard/ecss-e-st-50-11c-spacefibre-very-high-speed-serial-link/) (15 May 2019):
Physical layer adaptation, Lane layer, Multi-Lane layer (1 to 4 lanes), Data Link layer with up to 32 virtual
channels, quality of service, broadcast, scrambling and error recovery, the Network layer service interface and the
Management Information Base. All RAMs, clock domain crossings and reset synchronisers use the fault-tolerant
entities of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, TMR synchronisers).

## Status

**Technology readiness level: TRL 3** (fully verified by simulation). The core has not been tested on
hardware yet and has no flight heritage; see [what the levels mean](https://openspacehdl.org/trl/) and the next
steps in the [roadmap](docs/roadmap.md#technology-readiness).

The core (1 to 4 lanes, 1 to 32 virtual channels, broadcast messages, quality of service, EDAC) is complete and
verified in simulation; the [compliance matrix](docs/compliance.md) traces every ECSS clause in scope to its tests.
A fault injection campaign (line errors, word slips, lane failures, single and double errors in the buffers)
checks that no packet is lost, duplicated or corrupted unnoticed; with packets of up to 1024 bytes the core
transfers 94 % of the lane capacity in one direction and 90 % per direction in both. The regression covers every
statement, branch and state machine transition of the core except a few defensive or unreachable items, each
justified in the [code coverage report](docs/coverage.md).
The first target is the AMD Versal AI Core XCVC1902 on the VCK190 evaluation board (4 GTY lanes on the QSFP
connector, 6.25 Gbit/s per lane): the Physical adapter for the GTY and a reference design are verified with the
transceiver model; the first build was analysed and its findings fixed, timing closure and the hardware test are
open. See [docs/roadmap.md](docs/roadmap.md) for the state of every module.

## Documentation

The documents are also published as a website: [openspacehdl.org/openfibre](https://openspacehdl.org/openfibre/) (built
from this repository by `tools/docs/`).

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: layers, building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/user_guide.md](docs/user_guide.md) | Integration: sources, generics, clocks, interfaces, programming sequence, performance, synthesis |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| [docs/compliance.md](docs/compliance.md) | ECSS compliance matrix: requirements and test cases of every clause (generated) |
| [hdl/ofb_mib/docs/register_map.md](hdl/ofb_mib/docs/register_map.md) | Register map of the MIB (generated; C header `sw/ofb_regs.h`) |
| [docs/coverage.md](docs/coverage.md) | Code coverage of the regression (QuestaSim) and the justification of every item not covered |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openfibre/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches
|-- lint/             VSG configuration (Open Logic rules), synthesizability check
|-- tools/            Compliance matrix and register map generators, simulations with the transceiver model (xsim)
|   `-- docs/         Documentation website (MkDocs)
|-- sw/               C header of the register map (generated)
|-- open-logic/       Git submodule: Open Logic (fault-tolerant entities branch)
|-- uvvm/             Git submodule: UVVM verification framework
|-- component_list.txt  Modules in dependency order
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt`.

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 8              # full regression with GHDL, 8 parallel simulations
python run.py "*ofb_pkg*"       # one module
python run.py --questa <test>   # QuestaSim
python run.py --questa --coverage  # code coverage of the OpenFibre sources (QuestaSim), report in coverage/
python tools/run_xsim.py        # tests with the GTY transceiver model (AMD Vivado simulator)
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenFibre sources into the library `openfibre`. Environment variables: `OFB_CAMPAIGN_SEEDS="2,3,4"` adds seeds to
the fault injection campaign of the core (TC-CORE-13), `OFB_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation,
for example `--vcd=wave.vcd --read-wave-opt=wave.opt` for a waveform of selected signals.

`--coverage` compiles the OpenFibre sources with statement, branch, condition, expression and state machine
coverage, merges the coverage of all tests into `coverage/coverage.ucdb` and writes the reports
`coverage/coverage_report.txt` (details) and `coverage/coverage_byfile.txt`. The analysis of the last run is in
[docs/coverage.md](docs/coverage.md).

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # GHDL synthesis of ofb_core for 1, 2 and 4 lanes (after python run.py --compile)
python tools/compliance.py --check  # every ECSS clause and requirement traced to a test case
python tools/regmap.py --check      # generated register map files match hdl/ofb_mib/regs/ofb_regs.yml
python -m mkdocs build -f tools/docs/mkdocs.yml  # documentation website, fails on broken links
```

## Licence

OpenFibre is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
