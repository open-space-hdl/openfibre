# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: one to four lanes with all tests, and the boundaries of the other
generic ranges with the tests of link start, traffic and link reset.

The fault injection campaign (test_fault_campaign, TC-CORE-13) runs with seed 1 in the regression. More seeds for an
extended campaign: OFB_CAMPAIGN_SEEDS="2,3,4" python run.py "*test_fault_campaign*".
"""

import os

# Tests of the configurations for the generic ranges (TC-CORE-01, 02, 04)
BASIC_TESTS = ("test_link_up", "test_traffic", "test_link_reset")

# Generic ranges: name, generics, tests (None: all tests)
RANGE_CONFIGS = (
    # One VC (point-to-point or configuration link, ECSS 5.8.4d) and the maximum of 32 VCs
    ("vc1", {"NumLanes_g": 2, "NumVc_g": 1}, BASIC_TESTS),
    ("vc32", {"NumLanes_g": 2, "NumVc_g": 32}, BASIC_TESTS),
    # Lane clock at half the rate (LaneClk 78.125 MHz): the timers of the Lane and Multi-Lane layers follow
    # LaneClkFreq_g
    ("halfrate", {"NumLanes_g": 2, "LaneHalfPs_g": 6400}, ("test_link_up", "test_link_reset")),
    # Smallest buffers: output VC buffer 64 words, input VC buffer 128 words per lane (two flow control units),
    # error recovery buffer 64 rows
    ("minbuf", {"NumLanes_g": 2, "VcOutDepth_g": 32, "VcInDepth_g": 256, "ErbRows_g": 64},
     BASIC_TESTS + ("test_error_recovery",)),
    # Lane initialisation without PRBS words after INIT1 and INIT2
    ("noprbs", {"NumLanes_g": 1, "InitPrbsWords_g": 0}, ("test_link_up", "test_traffic")),
)


def configure(lib):
    tb = lib.test_bench("ofb_core_tb")
    for lanes in (1, 2, 3, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
    # Receive row overflow with CoreClk slower than LaneClk (TC-CORE-15)
    tb.test("test_row_overflow").add_config(name="lanes1_slowcore", generics={"NumLanes_g": 1, "CoreHalfPs_g": 4000})
    for name, generics, tests in RANGE_CONFIGS:
        for test in tests:
            tb.test(test).add_config(name=name, generics=generics)
    seeds = [int(s) for s in os.environ.get("OFB_CAMPAIGN_SEEDS", "").split(",") if s.strip()]
    if seeds:
        test = tb.test("test_fault_campaign")
        for lanes in (1, 2, 3, 4):
            for seed in seeds:
                test.add_config(name=f"lanes{lanes}_seed{seed}", generics={"NumLanes_g": lanes, "Seed_g": seed})
