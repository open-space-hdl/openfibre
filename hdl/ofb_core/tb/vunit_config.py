# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: one to four lanes with all tests, the boundaries of the other
generic ranges with the tests of link start, traffic and link reset, and four lanes through two ofb_pa_gty with the
architecture mdl (lanes4_pin). The link reset crossing of ofb_core_cc runs with a core clock faster than, equal to and
twice the lane clock.

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
    # LaneClkFreq_g; with the transmitter ready tests the Data Link layer leaves its hold well before the lanes
    ("halfrate", {"NumLanes_g": 2, "LaneHalfPs_g": 6400},
     ("test_link_up", "test_link_reset", "test_tx_ready_late", "test_tx_ready_lost")),
    # Smallest buffers: output VC buffer 64 words, input VC buffer 128 words per lane (two flow control units),
    # error recovery buffer 64 rows
    ("minbuf", {"NumLanes_g": 2, "VcOutDepth_g": 32, "VcInDepth_g": 256, "ErbRows_g": 64},
     BASIC_TESTS + ("test_error_recovery",)),
    # Lane initialisation without PRBS words after INIT1 and INIT2
    ("noprbs", {"NumLanes_g": 1, "InitPrbsWords_g": 0}, ("test_link_up", "test_traffic")),
    # One lane with CoreClk at the frequency of LaneClk, as when both are the transmit clock of the transceiver: in the
    # transmitter ready tests the first rows of the Data Link layer reach the Multi-Lane layer a few cycles after the
    # link reset that the release of the hold started
    ("eqclk", {"NumLanes_g": 1, "CoreHalfPs_g": 3200},
     ("test_tx_ready_late", "test_tx_ready_never", "test_tx_ready_lost", "test_tx_ready_clock_stop",
      "test_tx_ready_pulse", "test_tx_ready_start")),
    # Reset values of LaneStart and AutoStart (TC-CORE-28): LaneStart_g at A with one and four lanes, no AutoStart
    ("lanestart1", {"NumLanes_g": 1, "LaneStartA_g": True}, ("test_start_generics",)),
    ("lanestart4", {"NumLanes_g": 4, "LaneStartA_g": True}, ("test_start_generics",)),
    ("noauto", {"NumLanes_g": 1, "AutoStart_g": False}, ("test_start_generics",)),
    # Two ofb_pa_gty with the architecture mdl pin to pin instead of the word-level channel model: the bit-level
    # model under the full protocol stack (link start, traffic, bit errors, throughput)
    ("lanes4_pin", {"NumLanes_g": 4, "PinModel_g": True},
     ("test_link_up", "test_traffic", "test_error_recovery", "test_throughput")),
    # Error recovery through the models with the lock time of the transceiver model (16.83 us) and near the ends of the
    # interval that bounds it: the word losses at comma realignments are recovered by the alignment watchdog
    ("lanes4_pin_lock16650", {"NumLanes_g": 4, "PinModel_g": True, "PinLockNs_g": 16650}, ("test_error_recovery",)),
    ("lanes4_pin_lock16830", {"NumLanes_g": 4, "PinModel_g": True, "PinLockNs_g": 16830}, ("test_error_recovery",)),
    ("lanes4_pin_lock17000", {"NumLanes_g": 4, "PinModel_g": True, "PinLockNs_g": 17000}, ("test_error_recovery",)),
)


# Alignment watchdog (TC-CORE-30 to 33): several lanes, the watchdog of A and B as the test needs it; these tests do
# not run in the configurations lanes1 to lanes4
WATCHDOG_CONFIGS = (
    ("lanes4_wd", {"NumLanes_g": 4}, ("test_align_watchdog", "test_align_watchdog_bound")),
    ("lanes2_wd", {"NumLanes_g": 2}, ("test_align_watchdog",)),
    ("lanes4_wdoff", {"NumLanes_g": 4, "AlignTimeoutA_g": 0, "AlignTimeoutB_g": 0}, ("test_align_watchdog_off",)),
    ("lanes4_wdfar", {"NumLanes_g": 4, "AlignTimeoutB_g": 0}, ("test_align_watchdog_far",)),
)


def configure(lib):
    tb = lib.test_bench("ofb_core_tb")
    watchdog_tests = {test for _, _, tests in WATCHDOG_CONFIGS for test in tests}
    for test in tb.get_tests():
        if test.name not in watchdog_tests:
            for lanes in (1, 2, 3, 4):
                test.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
    for name, generics, tests in WATCHDOG_CONFIGS:
        for test in tests:
            tb.test(test).add_config(name=name, generics=generics)
    # Receive row overflow with CoreClk slower than LaneClk (TC-CORE-15)
    tb.test("test_row_overflow").add_config(name="lanes1_slowcore", generics={"NumLanes_g": 1, "CoreHalfPs_g": 4000})
    for name, generics, tests in RANGE_CONFIGS:
        for test in tests:
            tb.test(test).add_config(name=name, generics=generics)
    cc = lib.test_bench("ofb_core_cc_tb")
    for name, core_half_ps, lane_half_ps in (("core_fast", 3000, 3200), ("equal", 3200, 3200),
                                             ("lane_half", 3000, 6400)):
        cc.add_config(name=name, generics={"CoreHalfPs_g": core_half_ps, "LaneHalfPs_g": lane_half_ps})
    seeds = [int(s) for s in os.environ.get("OFB_CAMPAIGN_SEEDS", "").split(",") if s.strip()]
    if seeds:
        test = tb.test("test_fault_campaign")
        for lanes in (1, 2, 3, 4):
            for seed in seeds:
                test.add_config(name=f"lanes{lanes}_seed{seed}", generics={"NumLanes_g": lanes, "Seed_g": seed})
