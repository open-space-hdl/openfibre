# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Multi-Lane layer testbenches: the link testbench runs with 2, 3 and 4 lanes; the
alignment watchdog test also runs with the watchdog off."""


def configure(lib):
    tb = lib.test_bench("ofb_ml_link_tb")
    for lanes in (2, 3, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
    align = lib.test_bench("ofb_ml_align_tb")
    align.test("test_align_watchdog").add_config(name="wdoff", generics={"AlignTimeout_g": 0})
    align.test("test_align_watchdog").add_config(name="wd1024", generics={"AlignTimeout_g": 1024})
