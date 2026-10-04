# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: one, two and four lanes."""


def configure(lib):
    tb = lib.test_bench("ofb_core_tb")
    for lanes in (1, 2, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
