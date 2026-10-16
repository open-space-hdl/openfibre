---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the link reset crossing of ofb_core_cc: the link reset and LaneReset levels of the
-- Data Link layer give exactly one pulse per entry in the lane clock domain, whatever the length of
-- the level, none after the release; the hold of the lanes passes as a level. A faster core clock,
-- equal clocks and a lane clock at half the rate (VUnit configurations).
--
-- Documentation: hdl/ofb_core/docs/verification_plan.md

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
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_cc_tb is
    generic (
        runner_cfg   : string;
        CoreHalfPs_g : positive := 3000;
        LaneHalfPs_g : positive := 3200
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_core_cc_tb is

    constant CorePeriod_c : time := 2 * CoreHalfPs_g * 1 ps;
    constant LanePeriod_c : time := 2 * LaneHalfPs_g * 1 ps;

    -- Longer than two transfers of the pulse crossing (ofb_cc_pulse, specification PKG-11)
    constant Settle_c : time := 20 * CorePeriod_c + 20 * LanePeriod_c;

    signal CoreClk   : std_logic := '0';
    signal LaneClk   : std_logic := '0';
    signal CoreRst   : std_logic := '1';
    signal LaneRst   : std_logic := '1';
    signal LinkReset : std_logic := '1';
    signal Hold      : std_logic := '0';
    signal MlLink    : std_logic;
    signal MlLane    : std_logic;

    -- Pulses at the Multi-Lane layer outside the hold: link reset, LaneReset
    type Count_t is array (0 to 1) of natural;

    signal Count : Count_t := (0, 0);

begin

    CoreClk <= not CoreClk after CoreHalfPs_g * 1 ps;
    LaneClk <= not LaneClk after LaneHalfPs_g * 1 ps;

    -----------------------------------------------------------------------------------------------
    -- DUT: the link reset and LaneReset of the Data Link layer are one level (as in ofb_dl_link_reset)
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_core_cc
        generic map (
            NumLanes_g => 1
        )
        port map (
            CoreClk               => CoreClk,
            CoreRst               => CoreRst,
            Dl_TxRow_Data         => (others => '0'),
            Dl_TxRow_K            => (others => '0'),
            Dl_TxRow_Mask         => (others => '0'),
            Dl_TxRow_Replicate    => '0',
            Dl_TxRow_Valid        => '0',
            Dl_TxRow_Ready        => open,
            Dl_RxRow_Data         => open,
            Dl_RxRow_K            => open,
            Dl_RxRow_Mask         => open,
            Dl_RxRow_CrcErr       => open,
            Dl_RxRow_Valid        => open,
            Dl_LinkReset          => LinkReset,
            Dl_LaneReset          => LinkReset,
            Dl_NearCapability     => x"00",
            Dl_FarCapability      => open,
            Dl_FarCapabilityValid => open,
            Dl_FarCapabilityIdle  => open,
            Dl_LaneActive         => open,
            LaneClk               => LaneClk,
            LaneRst               => LaneRst,
            Ml_TxRow_Data         => open,
            Ml_TxRow_K            => open,
            Ml_TxRow_Mask         => open,
            Ml_TxRow_Replicate    => open,
            Ml_TxRow_Poison       => open,
            Ml_TxRow_Valid        => open,
            Ml_TxRow_Ready        => '0',
            Ml_RxRow_Data         => (others => '0'),
            Ml_RxRow_K            => (others => '0'),
            Ml_RxRow_Mask         => (others => '0'),
            Ml_RxRow_CrcErr       => '0',
            Ml_RxRow_Valid        => '0',
            Ml_ResetHold          => Hold,
            Ml_LinkReset          => MlLink,
            Ml_LaneReset          => MlLane,
            Ml_NearCapability     => open,
            Ml_FarCapability      => x"00",
            Ml_FarCapabilityValid => '0',
            Ml_FarCapabilityIdle  => '0',
            Ml_LaneActive         => '0',
            Ev_RxOverflow         => open,
            Ecc_Core              => open,
            Ecc_Lane              => open
        );

    -----------------------------------------------------------------------------------------------
    -- Monitor: pulses outside the hold, each one lane clock cycle long
    -----------------------------------------------------------------------------------------------
    p_monitor : process (LaneClk) is
        variable Prev_v : std_logic_vector(1 downto 0) := "00";
        variable Out_v  : std_logic_vector(1 downto 0);
    begin
        if rising_edge(LaneClk) then
            Out_v := MlLane & MlLink;
            if Hold = '0' and LaneRst = '0' then

                for b in 0 to 1 loop
                    if Out_v(b) = '1' then
                        Count(b) <= Count(b) + 1;
                        check_value(Prev_v(b), '0', error, "Pulse " & to_string(b) & " lasts one cycle");
                    end if;
                end loop;

                Prev_v := Out_v;
            else
                Prev_v := "00";
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Exp_v : natural;

        procedure coreCycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(CoreClk);
            end loop;

        end procedure;

        -- Entry into the link reset with a level of n core clock cycles
        procedure entry (n : positive) is
        begin
            wait until rising_edge(CoreClk);
            LinkReset <= '1';
            coreCycles(n);
            LinkReset <= '0';
        end procedure;

        procedure checkCount (
            exp : natural;
            msg : string) is
        begin
            wait for Settle_c;
            check_value(Count(0), exp, error, msg & ": link reset pulses");
            check_value(Count(1), exp, error, msg & ": LaneReset pulses");
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        log(ID_LOG_HDR, "Core clock " & to_string(CorePeriod_c) & ", lane clock " & to_string(LanePeriod_c));

        while test_suite loop

            -- TC-CORE-27: one link reset and one LaneReset pulse per entry of the Data Link layer into the
            -- link reset, whatever the length of the level, none after the release (CORE-PL-06); the hold of
            -- the lanes passes as a level (CORE-PL-04)
            if run("test_link_reset_entry") then
                -- Release of the resets: the Data Link layer leaves its reset in ConfigReset with the level
                -- set and leaves Near-End Reset 50 cycles later; no entry
                wait for 10 * (CorePeriod_c + LanePeriod_c);
                wait until rising_edge(CoreClk);
                CoreRst   <= '0';
                LaneRst   <= '0';
                wait for 20 * (CorePeriod_c + LanePeriod_c);
                coreCycles(50);
                LinkReset <= '0';
                Exp_v     := 0;
                checkCount(Exp_v, "Release of the resets");

                -- Link reset of the Management Information Base (Near-End Reset for one cycle), Interface
                -- Reset (ConfigReset and Near-End Reset), transmitters not ready for 200 cycles
                entry(1);
                Exp_v     := Exp_v + 1;
                checkCount(Exp_v, "Level of one cycle");
                entry(2);
                Exp_v     := Exp_v + 1;
                checkCount(Exp_v, "Level of two cycles");
                wait until rising_edge(CoreClk);
                LinkReset <= '1';
                coreCycles(150);
                check_value(Count(0), Exp_v + 1, error, "One link reset pulse while the level is held");
                check_value(Count(1), Exp_v + 1, error, "One LaneReset pulse while the level is held");
                coreCycles(50);
                LinkReset <= '0';
                Exp_v     := Exp_v + 1;
                checkCount(Exp_v, "Level of 200 cycles: none after the release");

                -- Two entries within one transfer of the crossing: two pulses
                entry(1);
                coreCycles(2);
                entry(1);
                Exp_v := Exp_v + 2;
                checkCount(Exp_v, "Two entries in quick succession");

                -- Hold of the lanes: link reset and LaneReset follow it as a level
                wait until rising_edge(LaneClk);
                Hold <= '1';
                wait until rising_edge(LaneClk);
                wait until falling_edge(LaneClk);
                check_value(MlLink = '1' and MlLane = '1', error, "Hold passed as a level");
                -- Transmitters not ready: entry while the lanes are held, the hold ends three core cycles
                -- before the Data Link layer leaves Near-End Reset; no pulse after the hold
                entry(1);
                coreCycles(5);
                wait until rising_edge(CoreClk);
                LinkReset <= '1';
                coreCycles(200);
                wait until rising_edge(LaneClk);
                Hold      <= '0';
                coreCycles(3);
                LinkReset <= '0';
                checkCount(Exp_v, "No pulse after the hold");
                check_value(MlLink = '0' and MlLane = '0', error, "Hold released");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

end architecture;
