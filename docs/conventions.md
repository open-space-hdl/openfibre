# OpenFibre Conventions

OpenFibre follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenFibre-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `ofb_<function>` (for example `ofb_lane_tx`). All OpenFibre sources are compiled into the VHDL
  library `openfibre`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset. `olo_ft_cc_reset` brings a reset into
  each clock domain.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics).
- Standard functions (FIFOs, RAMs, crossings, CRC, PRBS, arbiters, width converters, pipeline stages) are
  instantiated from Open Logic, never rewritten. RAMs and crossings use the fault-tolerant `olo_ft_*` entities.
- Every line that implements an ECSS requirement is traceable through the module specification; comments name the
  clause where it helps the reader (for example `-- ECSS 5.5.2.11e.3`).
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `vsg -c lint/config/vsg_config.yml -f <file>`. Safe automatic fixes:
  `vsg -c lint/config/vsg_config.yml --fix --fix_only lint/config/fix_only_config.yml -f <file>`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` elaborates
  `ofb_core` for 1, 2 and 4 lanes with the synthesis of GHDL (after `python run.py --compile`) and fails on errors and
  inferred latches. Signals with a variable index select a slice with a loop over the constant slices rather than a
  slice with variable bounds; `to_01` and other simulation-only functions are not used in RTL.
- Traceability: every requirement of a specification is verified by at least one test case of the verification plan,
  every ECSS clause of the traceability matrix (architecture section 10) by the test cases of its requirements, and
  every test case of a plan is run by a testbench. `python tools/compliance.py` writes the
  [compliance matrix](compliance.md); `python tools/compliance.py --check` fails on a gap.

## Module development process

Every module goes through the seven phases of the architecture document (section 9):

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to ECSS clauses |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

A module is one layer or one group of blocks of the architecture (section 7). Every block keeps its own entity and
its own unit testbench. `hdl/<module>/README.md` links the four documents and explains how to run the tests.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`ofb_tb_pkg.ofbTestEnd`).
- Tests observe ports and management interfaces only, never internal signals.
- GHDL is the default simulator. Only the tests that instantiate the vendor transceiver model (PA-1 wrapper test and
  the end-to-end test of two cores over the transceivers) run in the AMD Vivado simulator
  (`tools/run_xsim.py`); their testbenches use plain VHDL checks evaluated from the log.
- Negative tests inject the fault from the bench (corrupted word, wrong sequence number, ...) and expect the alert
  with `increment_expected_alerts`.

## Git

- `main` holds the integrated state. Every module or change is developed on a branch `feature/<module>` or
  `bugfix/<topic>` and merged with `--no-ff` once its regression is green.
- Commit messages: imperative subject line, body explains what and why.
