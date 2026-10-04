# OpenFibre

OpenFibre is an open SpaceFibre implementation that is based on the Open Logic VHDL Library.

It implements a SpaceFibre port according to
[ECSS-E-ST-50-11C](https://ecss.nl/standard/ecss-e-st-50-11c-spacefibre-very-high-speed-serial-link/) (15 May 2019):
Physical layer adaptation, Lane layer, Multi-Lane layer (1 to 4 lanes), Data Link layer with up to 32 virtual
channels, quality of service, broadcast, scrambling and error recovery, the Network layer service interface and the
Management Information Base. All RAMs and clock domain crossings use the fault-tolerant entities of
[Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, TMR synchronisers).

## Status

Early development. The first target is the AMD Versal AI Core XCVC1902 on the VCK190 evaluation board (4 GTY lanes
on the QSFP connector, 6.25 Gbit/s per lane). See [docs/roadmap.md](docs/roadmap.md) for the state of every module.

## Documentation

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: layers, building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openfibre/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches
|-- lint/             VSG configuration (Open Logic rules)
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
python run.py --questa <test>   # QuestaSim (only needed for the tests with the GTY transceiver model)
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenFibre sources into the library `openfibre`.

## Licence

OpenFibre is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
