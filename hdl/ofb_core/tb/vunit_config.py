# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: one, two and four lanes.

The fault injection campaign (test_fault_campaign, TC-CORE-13) runs with seed 1 in the regression. More seeds for an
extended campaign: OFB_CAMPAIGN_SEEDS="2,3,4" python run.py "*test_fault_campaign*".
"""

import os


def configure(lib):
    tb = lib.test_bench("ofb_core_tb")
    for lanes in (1, 2, 4):
        tb.add_config(name=f"lanes{lanes}", generics={"NumLanes_g": lanes})
    # Receive row overflow with CoreClk slower than LaneClk (TC-CORE-15)
    tb.test("test_row_overflow").add_config(name="lanes1_slowcore", generics={"NumLanes_g": 1, "CoreHalfPs_g": 4000})
    seeds = [int(s) for s in os.environ.get("OFB_CAMPAIGN_SEEDS", "").split(",") if s.strip()]
    if seeds:
        test = tb.test("test_fault_campaign")
        for lanes in (1, 2, 4):
            for seed in seeds:
                test.add_config(name=f"lanes{lanes}_seed{seed}", generics={"NumLanes_g": lanes, "Seed_g": seed})
