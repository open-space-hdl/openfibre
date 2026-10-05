# ofb_pa_gty: Verification Plan

## 1. Overview

The adapter is verified with the encrypted transceiver model of the AMD simulation libraries and the AMD simulator
(xsim): `python tools/run_xsim.py`. The script creates the transceiver wizard instance with Vivado,
exports its simulation sources, compiles them with Open Logic and the OpenFibre sources and runs the testbenches.
The GHDL regression cannot compile the transceiver model; all other tests use the behavioural Physical adapter model
(`tb/ofb_tb_pa_model.vhd`).

The testbenches use plain VHDL checks (`report` with "FAIL", "Simulation done" at the end) because the support of
UVVM in xsim is limited; the runner evaluates the log.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `ofb_pa_gty_tb` | `ofb_pa_gty` with four lanes, serial lines looped back (transmitter of each lane to its receiver), 156.25 MHz reference clock, 100 MHz free-running clock; a word generator per lane (data words counting up, IDLE words, SKIP words) and a checker per lane |
| `ofb_pa_gty_cc_tb` | Two `ofb_pa_gty` A and B with four lanes, serial lines crossed, reference clock of B 1000 ppm slower than that of A (exaggerated to reach many clock corrections in a short simulation); per lane a word generator (counting data words, an IDLE word every 8 words, a SKIP word every 16 words) and a checker; counters of the clock corrections and receive buffer errors |
| `ofb_pa_gty_core_tb` | Two ends A and B, each `ofb_core` (4 VCs, 4 lanes, all core clocks = `LaneClk`) with `ofb_pa_gty`, serial lines crossed; reference clocks 156.25 MHz at A and 200 ppm slower at B (the limit of 5.4.2.3a at both ends); AXI4-Lite access to both MIBs, packet generator and checker per VC and end, broadcast generator and checker, counter of the clock corrections per end |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| TC-PA-01 (`ofb_pa_gty_tb`) | Reset sequence: transmitter and receiver ready, `LaneClk` running; every lane aligned; 300 data words per lane received in order with K flags clear, IDLE and SKIP words with the K flag of symbol 0, no code or disparity error, no other lane's words | PA-IF-01, PA-SE-01, PA-SE-02, PA-SY-01, PA-CK-01, PA-RS-01, PA-ST-01 |
| TC-PA-03 (`ofb_pa_gty_cc_tb`) | At least 4 clock corrections at each end (SKIP words inserted at A, removed at B), no receive buffer error, 3000 data words per lane and end received in order without loss or repetition | PA-CC-01, PA-ST-01 |
| TC-PA-02 (`ofb_pa_gty_core_tb`) | LaneStart at A, AutoStart at B: lane initialisation through the transceivers (ClearLine with electrical idle and CDR hold, polarity control), alignment of the four lanes, link initialised at both ends; a first burst of 12 packets per VC (1 to 40 words) and 4 broadcast messages in both directions; clock corrections at both ends (SKIP words inserted at one end, removed at the other); a second burst of 12 packets per VC; all delivered in order, no error flag in DL_ERRORS, no retry | PA-IF-01 to 03, PA-CC-01, PA-SE-01, PA-SE-02, PA-SY-01, CORE-SY-01, CORE-SY-02 |

## 4. Coverage analysis

PA-IF-02 and PA-IF-03 are exercised by the lane initialisation of TC-PA-02 (the Lane layer drives line driver, line
receiver and CDR enable in ClearLine and uses NoSignal in Wait). A lane failure over the transceiver model is not
simulated: the behavioural model covers it in the core testbench (TC-CORE-07).
