# ofb_ni: Verification Report

## 1. Test results

Run on 2026-10-13 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_ni*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_ni_tb` (configurations `lanes1`, `lanes2`, `lanes4`) | 7 x 3 | 21 |

Throughput (TC-NI-07, all configurations): transmit 100 rows of 20 packets in 100 cycles; receive 100 beats of 20
packets with a tail beat each in 119 cycles (the limit is 6 cycles per packet).

## 2. Summary

All test cases pass. VSG reports no errors and no warnings. NI-IF-02, NI-RX-04 and NI-SC-01 are verified with the
core testbench (TC-CORE-02, TC-CORE-06).

Mutation checks with two lanes (each detected, then reverted): the rotation of an open packet by the offset of the
first data character of its current beat instead of the registered offset fails TC-NI-03 to TC-NI-06; the output bytes
of an open packet taken from the rotated beat only (without the held bytes) fails TC-NI-03 to TC-NI-07; no discard
after a violation fails TC-NI-05; no additional end marker row after a full last beat fails TC-NI-01, TC-NI-02 and
TC-NI-07.

Design iterations found during verification:

| Finding | Change |
| --- | --- |
| Technology-independent synthesis (GHDL and Yosys, 6-input LUTs) of the first receive design with four lanes: 2201 LUT per VC and 8 to 10 logic levels; the rotation was an AND-OR over the one-hot offset (16 inputs per bit), and the selects of the data registers depended on the character rule decision | Rotation by a binary offset in two stages (words, then 0 to 3 bytes), data registers with selects and enables from registers only, character classes and the offset of the first data character decoded before the input stage: 1044 LUT per VC and 6 levels |
| GHDL synthesis rejects a slice with a variable offset in a function | The rotation selects among slices with constant offsets |
| Testbench: a further protected type with a two-dimensional array in the shared package `ofb_tb_pkg` made GHDL 6.0.0 abort the elaboration of every testbench with an internal error ("bad elaboration order of objects"); QuestaSim rejects a shared variable of a protected type before the protected body in the same package | The queues of the drivers are a protected type in their own package `tb/ofb_tb_queue_pkg.vhd`; the shared variables are declared in the testbench packages |
