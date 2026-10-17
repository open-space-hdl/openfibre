---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VUnit wrapper of the end-to-end testbench ofb_pa_gty_core_tb with the architecture mdl of
-- ofb_pa_gty (GHDL, QuestaSim): runs TC-PA-02 with the same stimulus and checks as the AMD simulator
-- run with the transceiver model (PA-MD-10).
--
-- Documentation: hdl/ofb_pa_gty/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_tb_pkg.all;
    use work.ofb_pa_gty_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_model_core_tb is
    generic (
        runner_cfg : string;
        Lanes_g    : positive range 1 to 4 := 4;
        Short_g    : boolean               := false;
        Relock_g   : boolean               := false;
        CutNs_g    : positive              := 5000
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_model_core_tb is

begin

    i_tb : entity work.ofb_pa_gty_core_tb
        generic map (
            Lanes_g  => Lanes_g,
            Short_g  => Short_g,
            Relock_g => Relock_g,
            CutNs_g  => CutNs_g,
            Finish_g => false
        );

    p_main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);

        while test_suite loop

            -- TC-PA-02: link initialisation, bursts in both directions and clock correction through two
            -- adapter models
            if run("test_end_to_end") then
                wait until PaCoreTbEnd for 2 ms;
                check_value(PaCoreTbEnd, error, "End of the sequence of ofb_pa_gty_core_tb");
                check_value(PaCoreTbPass, error, "Checks of ofb_pa_gty_core_tb");
            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

end architecture;
