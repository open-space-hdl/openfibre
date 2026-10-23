# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the testbench of the behavioural model of ofb_pa_gty: one to four lanes with equal
reference clocks, and the clock correction and receive buffer tests with reference clocks 1000 ppm apart. The
end-to-end testbench with the model runs the full run with four lanes and the short runs with one to three lanes, as
the runs of the transceiver model (tools/run_xsim.py)."""


def configure(lib):
    tb = lib.test_bench("ofb_pa_gty_model_tb")
    for lanes in (1, 2, 3, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"Lanes_g": lanes})
    for test in ("test_clock_correction", "test_buffer"):
        tb.test(test).add_config(name="lanes4_ppm1000", generics={"Lanes_g": 4, "PpmB_g": 1000})
        tb.test(test).add_config(name="lanes1_ppmm1000", generics={"Lanes_g": 1, "PpmB_g": -1000})
    core = lib.test_bench("ofb_pa_gty_model_core_tb")
    for lanes in (1, 2, 3):
        core.add_config(name=f"lanes{lanes}", generics={"Lanes_g": lanes, "Short_g": True})
    core.add_config(name="lanes4", generics={"Lanes_g": 4})
    core.add_config(name="lanes1_relock", generics={"Lanes_g": 1, "Short_g": True, "Relock_g": True})
    # Lane restart with Phy_NoSignal following the line (loss detected by NoSignal instead of the Lane layer)
    core.add_config(name="lanes1_relock_line", generics={"Lanes_g": 1, "Short_g": True, "Relock_g": True,
                                                         "LineSig_g": True})
    # Lane restart without a gap between two receiver resets (as the VCK190 design): every restart resets the receiver
    core.add_config(name="lanes1_relock_gap0", generics={"Lanes_g": 1, "Short_g": True, "Relock_g": True,
                                                         "RxRstGap_g": 0})
