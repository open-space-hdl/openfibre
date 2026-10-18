# ofb_mib: Verification Report

## 1. Test results

Run on 2026-10-13 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_mib_tb` | 11 | 11 |

Full regression of the repository: 227 of 227 tests pass (with the packet ports of the VCs and register map version
7). VSG reports no errors and no warnings. Run on 2026-10-15 with register map version 8 (transmitter ready): 11 of
11, full regression 322 of 322. Run on 2026-10-17 with register map version 9 (ML_ALIGN_TIMEOUTS, MG-ST-07): 11 of 11;
TC-MG-06 counts two expiries of the alignment watchdog and clears the counter with a write, TC-MG-01 reads its reset
value. A MIB that does not count the expiries fails TC-MG-06 (mutation check). Run on 2026-10-18: 11 of 11; TC-MG-04
also counts one Misaligned condition and one expiry of the alignment watchdog and checks that the Link Reset command
clears ML_MISALIGNED and ML_ALIGN_TIMEOUTS (MG-ST-07). QuestaSim on 2026-10-18: 11 of 11 with coverage (commit
b6242a2) and without coverage (commit 9dff622, the tree of main 77f4eea).

## 2. Summary

All test cases pass and cover every requirement of the specification.

Code coverage (QuestaSim, [docs/coverage.md](../../../docs/coverage.md)): the first measurement showed registers whose
write, clear or read path no test used (counter clears, W1C of several flags, CRC-8, frame and sequence counters, idle
limit, time-slots 63 to 32, lane events, SEC interrupt) and no test of the counter saturation (MG-ST-02). TC-MG-08 and
TC-MG-09 cover them and passed without a design change; every statement and branch is covered.

Code coverage after the PRBS test registers (MG-5): two branches were not covered. The saturation of the 48-bit word
counter needs 2^48 words (about 20 days at the line rate), and the read of an undefined lane register no longer
exists, because every word of the 32-byte lane stride is now a register (TC-MG-08 read two of them as undefined).
All counters now use one saturating increment (`satInc`), which TC-MG-09 covers; the last branch of the lane read
decode is the word counter, as in the VC decode; TC-MG-08 reads and writes the registers of a lane beyond
`NumLanes_g` instead. Rerun: the MIB covers 268 of 268 statements and 134 of 134 branches.

Register map: TC-MG-01 reads every fixed reset value of the register description (`regs/ofb_regs.yml`) back through
the generated package `ofb_regs_pkg`; a reset value changed in the description fails TC-MG-01 (mutation check).

PRBS test registers (TC-MG-10): an error counter that ignores the hold bit fails the test (mutation check: 15 instead
of 10 counted words).

Events of the Network interface (TC-MG-11, register map version 7): the packets of zero length are counted in the
user clock domain, because a pulse crossing merges events of consecutive cycles; the test drives three events of one
VC in consecutive cycles and two VCs in the same cycle and reads 4. QuestaSim (coverage run of 2026-10-14, 228 of
228 tests pass): the MIB covers 288 of 288 statements and 145 of 145 branches.

Transmitter ready (register map version 8, MG-ST-06): TC-MG-03 reads DL_STATUS bit 9 (TX_READY) as 1 and as 0;
TC-MG-04 sets DL_ERRORS bit 12 (TX_LOST) with its interrupt and clears it with W1C. The core testbench checks both
bits with the link held in Near-End Reset (TC-CORE-21 to TC-CORE-25), TC-CORE-24 and TC-CORE-25 also while the
core and lane clocks of the core stand still; TC-CORE-26 checks that a start of both cores with stopped clocks sets
no TX_LOST, and TC-CORE-29 that TX_LOST cleared while the transmitters stay not ready is not set again. TC-CORE-28
reads the reset values of LaneStart and AutoStart from the generics (MG-CF-03).

Defects found during verification:

| Finding | Fix |
| --- | --- |
| ECSS table audit (5.9.4e): the Link Reset command cleared only the Data Link status; the lane event flags and the flags of bandwidth use were kept | The command clears the status of all layers, the EDAC status excepted (MG-ST-01, TC-MG-04) |
| The sticky bandwidth flags latched the undefined value of the status crossing before its first transfer (simulation) | The sticky flags accumulate the crossed status only 32 cycles after reset (first fix with `to_01` replaced: not synthesizable, found with `lint/synth_check.py`) |
| Every event was counted twice and every command gave two pulses: `olo_ft_cc_pulse` stretches its output pulses to two cycles of the output clock | `ofb_cc_pulse` (edge detector after `olo_ft_cc_pulse`), also used in the input VC buffer of the Data Link layer, where the same effect doubled the FCT requests |
| First build of the VCK190 design: the latches of `olo_ft_cc_pulse` can lose commands and events (gate and data follow the input pulse) | `ofb_cc_pulse` without latch: handshake with single-cycle output pulses (`ofb_pkg` report) |
