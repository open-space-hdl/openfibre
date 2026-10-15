# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Network interface testbench: one to four lanes (4, 8, 12 and 16 bytes per beat)."""


def configure(lib):
    tb = lib.test_bench("ofb_ni_tb")
    for lanes in (1, 2, 3, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
