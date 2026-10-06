# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the pulse crossing testbench: faster input clock, faster output clock, nearly equal clocks
(user clock and lane clock of the VCK190 design)."""


def configure(lib):
    tb = lib.test_bench("ofb_cc_pulse_tb")
    for name, in_ps, out_ps in (("in_fast", 4000, 10000), ("out_fast", 10000, 4000), ("near", 6667, 6400)):
        tb.add_config(name=name, generics={"InPeriodPs_g": in_ps, "OutPeriodPs_g": out_ps})
