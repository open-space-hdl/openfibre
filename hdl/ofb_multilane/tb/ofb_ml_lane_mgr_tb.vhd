---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the lane manager of the Multi-Lane layer (ofb_ml_lane_mgr) with two lanes, the
-- lane states and capability events driven from the test sequencer: far-end capability passed to the
-- Data Link layer with the condition "no lane was Active" of the far-end reset (ECSS 5.7.9).
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_lane_mgr_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_lane_mgr_tb is

    constant N_c         : positive := 2;
    constant ClkPeriod_c : time     := 6.4 ns;

    -- Far-end capability with INIT3LinkResetFlag set (far end reset) and Multi-Lane capable
    constant CapReset_c : Char_t := (CapLinkReset_c => '1', CapMultiLane_c => '1', others => '0');

    signal Clk       : std_logic                          := '0';
    signal Rst       : std_logic                          := '1';
    signal LaneState : std_logic_vector(4*N_c-1 downto 0) := (others => '0');
    signal LaneCap   : std_logic_vector(8*N_c-1 downto 0) := (others => '0');
    signal LaneCapV  : std_logic_vector(N_c-1 downto 0)   := (others => '0');
    signal DlCap     : Char_t;
    signal DlCapV    : std_logic;
    signal DlCapIdle : std_logic;

begin

    Clk <= not Clk after ClkPeriod_c / 2;

    p_seq : process is
        variable Events_v : natural := 0; -- Capability events checked

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Lane l changes to state s; with cap, its capability event comes in the same cycle
        procedure setLane (
            l   : natural;
            s   : LaneState_t;
            cap : boolean) is
        begin
            wait until falling_edge(Clk);
            LaneState(4*l+3 downto 4*l) <= s;
            if cap then
                LaneCap(8*l+7 downto 8*l) <= CapReset_c;
                LaneCapV(l)               <= '1';
            end if;
            wait until falling_edge(Clk);
            LaneCapV <= (others => '0');
        end procedure;

        -- The capability event at the Data Link layer and its "no lane was Active" flag
        procedure checkEvent (
            idle : std_logic;
            msg  : string) is
        begin
            if DlCapV /= '1' then
                wait until DlCapV = '1' for 10 * ClkPeriod_c;
            end if;
            wait for 0 ns;
            Events_v := Events_v + 1;
            check_value(DlCapV, '1', error, msg & ": capability event " & to_string(Events_v));
            check_value(DlCap(CapLinkReset_c), '1', error, msg & ": INIT3LinkResetFlag");
            check_value(DlCapIdle, idle, error, msg & ": no lane was Active");
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        cycles(5);
        Rst <= '0';
        cycles(5);

        while test_suite loop

            -- TC-ML-48: the capability of the far end belongs to the Connected state (ECSS 5.7.9 Near-End
            -- Reset a.3): a lane whose capability event comes in the cycle in which it enters Active counts as
            -- not Active; a lane that was Active before does count
            if run("test_far_reset_idle") then
                -- Event in Connected, no lane Active
                setLane(0, LaneStateConnected_c, false);
                setLane(0, LaneStateConnected_c, true);
                checkEvent('1', "Event in Connected");
                setLane(0, LaneStateClearLine_c, false);
                cycles(3);
                -- Event in the cycle in which the lane enters Active, no other lane Active
                setLane(0, LaneStateConnected_c, false);
                cycles(3);
                setLane(0, LaneStateActive_c, true);
                checkEvent('1', "Event with the transition to Active");
                -- Lane 0 Active: an event of lane 1 entering Active is not a far-end reset of an idle link
                cycles(3);
                setLane(1, LaneStateConnected_c, false);
                cycles(3);
                setLane(1, LaneStateActive_c, true);
                checkEvent('0', "Event while another lane is Active");
            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 100 us);

    -----------------------------------------------------------------------------------------------
    -- Device under test
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_ml_lane_mgr
        generic map (
            NumLanes_g => N_c
        )
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Cfg_TxEn                => (others => '1'),
            Cfg_RxEn                => (others => '1'),
            Cfg_MaxDataLanes        => "000",
            Cfg_Bypass              => '0',
            Dl_LaneReset            => '0',
            Dl_NearCapability       => x"00",
            Dl_FarCapability        => DlCap,
            Dl_FarCapabilityValid   => DlCapV,
            Dl_FarCapabilityIdle    => DlCapIdle,
            Dl_LaneActive           => open,
            Lane_Reset              => open,
            Lane_TxOnly             => open,
            Lane_RxOnly             => open,
            Lane_FarEndActive       => open,
            Lane_NearCapability     => open,
            Lane_State              => LaneState,
            Lane_FarCapability      => LaneCap,
            Lane_FarCapabilityValid => LaneCapV,
            Bypass                  => open,
            ActLanes                => open,
            TxLanes                 => open,
            DataLanes               => open,
            HotLanes                => open,
            RxLanes                 => open,
            NumTxLanes              => open,
            NumRxLanes              => open,
            Enc_Scramble            => open,
            Dec_Unscramble          => open
        );

end architecture;
