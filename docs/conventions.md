# OpenFibre Conventions

OpenFibre follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenFibre-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `ofb_<function>` (for example `ofb_lane_tx`). All OpenFibre sources are compiled into the VHDL
  library `openfibre`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008. `run.py` analyses the synthesis sources (`hdl/*/src`) as strict VHDL-2008, without the
  `-frelaxed` option of GHDL that Open Logic, UVVM and the testbenches need.
- An attribute specification of an entity or an architecture uses a literal value (for example
  `attribute syn_radhardlevel of rtl : architecture is "none";`): VHDL requires a locally static expression there, so
  a constant of the Open Logic attribute packages is not allowed. Attributes of signals use those constants.
- `compile_order.txt` lists the synthesis sources of the library `openfibre` (the modules of `component_list.txt`,
  without testbenches and without the vendor-specific modules `ofb_pa_gty` and `ofb_vck190`) in compile order.
  `python run.py --compile-order` writes it; the CI fails when it is not up to date.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset. `olo_base_reset_gen` brings a reset into
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
  [compliance matrix](compliance.md); `python tools/compliance.py --check` fails on a gap and when the matrix is out
  of date.

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

## Diagrams

- Every architecture document has a block diagram; state machines, data formats and crossings have one where text
  alone is hard to follow.
- Diagrams are draw.io drawings stored as editable SVG with the drawing embedded (`<name>.drawio.svg`) in the `img/`
  folder next to the document. The SVG is the source: open it in draw.io to change it. It is exported with the light
  theme on an opaque white background, so that it reads in both colour schemes of the documentation site.
- Blocks: light blue for OpenFibre logic, white with a blue outline for an OpenFibre entity instantiated as a whole,
  light grey for an Open Logic entity, drawn inside the block that instantiates it, light yellow for vendor IP and
  device primitives. A dashed outline groups the blocks of one entity instance (a layer); a stacked block is
  replicated per VC or per lane. The title carries the building block ID of the architecture (`DT-7 Error recovery`),
  the entity follows in grey.
- Connections: thick lines for streams and signal groups, thin lines for single signals. Every line is horizontal or
  vertical; a dot marks a branch, an arc marks a crossing without a connection. Ports cross the frame of the entity,
  inputs on the left, outputs on the right where the layout allows.
- A diagram is at most about 1050 px wide, so that its text stays readable in the content column, and its alt text
  names the blocks it shows.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`ofb_tb_pkg.ofbTestEnd`).
- Tests observe ports and management interfaces only, never internal signals.
- `run.py` gives every GHDL simulation its own copy of the option `ghdl.sim_flags` and stops when a GHDL command does
  not carry exactly the generics of its configuration: VUnit 5.0.0.dev7 appends the generics of a test to that list in
  place, and configurations that share the list pass their generics on to later simulations.
- QuestaSim runs at a time resolution of 1 fs, as GHDL (`run.py`), so that clock periods and offsets of fractions
  of a picosecond are kept.
- GHDL is the default simulator. Only the tests that instantiate the vendor transceiver model (PA-1 wrapper test and
  the end-to-end test of two cores over the transceivers) run in the AMD Vivado simulator
  (`tools/run_xsim.py`); their testbenches use plain VHDL checks evaluated from the log. The transceiver model (secure
  IP with a firmware simulation) gives the same result in every run of one elaborated snapshot, but the elaborator
  builds a different snapshot from the same sources every time, and in some snapshots the model of one quad fails
  its power-up (error `DIV_VAL_CHK`, the quad never becomes ready). The runner detects this error and elaborates the
  test run again (at most three attempts, every repetition is reported). It concerns only the simulation model, not
  the design or the device image.
- Negative tests inject the fault from the bench (corrupted word, wrong sequence number, ...) and expect the alert
  with `increment_expected_alerts`.

## Git

- `main` holds the integrated state. Every module or change is developed on a branch `feature/<module>` or
  `bugfix/<topic>` and merged with `--no-ff` once its regression is green.
- Commit messages: imperative subject line, body explains what and why.
