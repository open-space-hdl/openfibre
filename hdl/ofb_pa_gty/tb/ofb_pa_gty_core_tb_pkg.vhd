---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- End of the end-to-end testbench ofb_pa_gty_core_tb for a VUnit wrapper: with Finish_g = false the
-- testbench sets these signals instead of stopping the simulation.
--
-- Documentation: hdl/ofb_pa_gty/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_pa_gty_core_tb_pkg is

    signal PaCoreTbEnd  : boolean := false; -- the sequence of the testbench has ended
    signal PaCoreTbPass : boolean := false; -- every check of the testbench passed

end package;
