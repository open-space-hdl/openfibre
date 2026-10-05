# ofb_multilane: Verification Report

## 1. Test results

Run on 2026-10-05 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*ofb_ml*"`
`"*ofb_multilane*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `ofb_ml_codec_tb` (ML-3, ML-4) | 10 | 10 |
| `ofb_multilane_tb` (layer, one lane) | 6 | 6 |
| `ofb_ml_align_tb` (ML-5, ML-6, four lanes) | 4 | 4 |
| `ofb_ml_link_tb` (multi-lane link, configurations `lanes2` and `lanes4`) | 11 x 2 | 22 |

Full regression of the repository: 179 of 179 tests pass (phase 5, after the fault injection campaign of the core).

## 2. Summary

All 42 test cases pass; every requirement of the specification is covered (see the verification plan). The column
encoder reproduces ECSS Figures 5-42 and 5-44 bit-exactly, and the decoder restores them. VSG reports no errors and no
warnings.

Mutation checks confirmed that the testbenches detect faults: a wrong byte enable of the EDF in the CRC unit fails
TC-ML-01 and TC-ML-09; a scramble enable that is not held in Active fails TC-ML-21. Phase 4: each of the following
faults fails the named test: the PAD row replaced by the replicated word (TC-ML-30, 4 lanes), a held ALIGN after
alignment ignored (TC-ML-41), the 4 us rule removed (TC-ML-42), interleaved control words that flush the waiting data
words (TC-ML-43), the maximum number of data-sending lanes ignored (TC-ML-33), no SKIP request (TC-ML-31),
FarEndActive not cleared by an ACTIVE word (TC-ML-35). Phase 5: held words discarded in Not Ready (the defect found
by TC-CORE-13) fail TC-ML-44; a poison mark that the distributor does not pass on fails TC-ML-46.

Defects found during verification:

| Finding | Fix |
| --- | --- |
| TC-ML-24: the one-cycle link reset pulse of the sequencer did not cover a rising clock edge (testbench timing) | Sequencer aligned to the falling edge before the pulse |
| Found during the design of the link reset state machine: a capability change in the middle of Connected can make the far end miss the INIT3LinkResetFlag | Capability held while the lane is in Connected (TC-ML-25, mutation checked) |
| TC-ML-35: a receive-only lane enters Active from Connected without INIT3 (ECSS 5.5.2.10e.3), so its unscramble enable stayed at the reset value and the data of that lane were not unscrambled | Unscramble enable of a lane without its own capability taken from the last capability of any lane (ML-LM-15 extended) |
| TC-ML-32: with a skew of three words, a lane was aligned before the ALIGN word of the late lane had arrived; the late lane then joined the data-receiving lanes, which caused a Misaligned condition and an RXERR in Near-End Ready | The lanes count as aligned only when every active receiving lane has received an ALIGN word (`Seen`) |
| TC-ML-37: the distributor sent an IDLE row after every replicated word (the next row was only taken one cycle later); a bit error that turns an IDLE word of one lane into RXERR is a lane slip and causes a realignment | The next row is taken in the cycle in which the replicated word is sent (ECSS 5.6.4.5b: no IDLE words while rows are available) |
| TC-ML-40: the end of the word stream let a skew of four words align, since the early lane stopped writing; on a link words never stop | Test sequence continues with ACTIVE rows after the last ALIGN (testbench) |
| TC-ML-40: a gap in an early lane does not slip the lanes (the FIFO absorbs it) | Slip modelled as an additional word on one lane (testbench) |
| TC-CORE-13 (fault injection campaign of the core): after a lane slip at one end, words of the frames sent by that end were missing at the far end without any error: the distributor discarded its held words when Not Ready was entered, the far end only received ACTIVE words (Both-Ends Ready to Near-End Ready, no RXERR) and kept the frame, and the CRC-16 computed after the distributor did not reveal the missing words | Held words are kept in Not Ready and sent after the realignment (ML-DS-12, TC-ML-44); only a link reset discards them |
| TC-CORE-13: a double error in the transmit row crossing of the core corrupted a word before the CRC-16 was computed, the far end accepted the frame | Poison mark of the row through the distributor to the column encoders, which invert the CRC-16 of the frame (ML-DS-13, ML-ENC-08, TC-ML-45, TC-ML-46) |

Observations:

- The treatment of control words and broadcast frames inside a data frame (excluded from the CRC-16 and from
  scrambling, specification section 5) follows from the standard but is not shown in its examples; it is checked with
  STAR-Dundee equipment in the lab test of phase 2.
- A bit error that hits a word which the Lane layer removes (SKIP, IDLE) or the word before it (ECSS 5.5.7l turns
  the previous word into RXERR as well) adds a word to one lane: a lane slip, followed by a realignment. This is a
  property of the standard; the distributor avoids IDLE rows while rows are available.
- The SKIP interval of the link testbench is 300 words to exercise SKIP often; the default is 5000.
