# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Multi-Lane layer testbenches: the link testbench runs with 2 and 4 lanes."""


def configure(lib):
    tb = lib.test_bench("ofb_ml_link_tb")
    for lanes in (2, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
