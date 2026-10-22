---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the lane manager of the Multi-Lane layer (ofb_ml_lane_mgr) with two lanes, the
-- lane states and capability events driven from the test sequencer: far-end capability passed to the
-- Data Link layer with the condition "no lane was Active" of the far-end reset (ECSS 5.7.9), join hold
-- of the rows of the Data Link layer (a second instance with the hold off).
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
    constant HoldWords_c : positive := 40;

    type StateArray_t is array (natural range <>) of LaneState_t;

    -- Initialisation states that hold, states that do not
    constant InitStates_c : StateArray_t(0 to 3) := (
        LaneStateStarted_c, LaneStateInvertRxPol_c, LaneStateConnecting_c, LaneStateConnected_c
    );
    constant IdleStates_c : StateArray_t(0 to 2) := (
        LaneStateClearLine_c, LaneStateDisabled_c, LaneStateWait_c
    );

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
    signal TxEn      : std_logic_vector(N_c-1 downto 0)   := (others => '1');
    signal RxEn      : std_logic_vector(N_c-1 downto 0)   := (others => '1');
    signal Bypass    : std_logic                          := '0';
    signal Hold      : std_logic;
    signal Hold0     : std_logic;
    signal Hold0Seen : boolean                            := false;

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

            -- TC-ML-51: join hold (ML-LM-17). After the first lane entered Active, Tx_Hold is set while another
            -- enabled lane is in Started, InvertRxPol, Connecting or Connected, and released for good when no lane
            -- initialises any more or after LaneJoinHoldWords_g cycles; it is armed again when no lane is Active.
            -- Lanes in Wait, Disabled or ClearLine, disabled lanes and the bypass do not hold; with
            -- LaneJoinHoldWords_g = 0 there is no hold
            elsif run("test_join_hold") then

                -- Every initialising state of lane 1 holds while lane 0 is Active; lane 1 Active releases
                for s in 0 to 3 loop
                    setLane(0, LaneStateClearLine_c, false);
                    setLane(1, InitStates_c(s), false);
                    cycles(3);
                    setLane(0, LaneStateActive_c, false);
                    cycles(2);
                    check_value(Hold, '1', error, "Hold with lane 1 in state " & to_hstring(InitStates_c(s)));
                    cycles(5);
                    check_value(Hold, '1', error, "Hold kept with lane 1 in state " & to_hstring(InitStates_c(s)));
                    setLane(1, LaneStateActive_c, false);
                    cycles(2);
                    check_value(Hold, '0', error, "Hold released when lane 1 entered Active");
                end loop;

                -- Released for good: lane 1 restarts while lane 0 stays Active, no hold
                setLane(1, LaneStateClearLine_c, false);
                setLane(1, LaneStateStarted_c, false);
                cycles(5);
                check_value(Hold, '0', error, "No hold for a lane that restarts while another lane is Active");
                setLane(1, LaneStateConnected_c, false);
                cycles(5);
                check_value(Hold, '0', error, "No hold for a restarting lane in Connected");

                -- Armed again when no lane is Active; bound of LaneJoinHoldWords_g cycles
                setLane(0, LaneStateClearLine_c, false);
                cycles(3);
                setLane(0, LaneStateActive_c, false);
                if Hold /= '1' then
                    wait until Hold = '1' for 4 * ClkPeriod_c;
                end if;
                check_value(Hold, '1', error, "Hold armed again after no lane was Active");
                cycles(HoldWords_c - 2);
                check_value(Hold, '1', error, "Hold kept until the bound");
                cycles(4);
                check_value(Hold, '0', error, "Hold ends at the bound");
                cycles(20);
                check_value(Hold, '0', error, "No hold after the bound with lane 1 still in Connected");

                -- Lane 1 not initialising when lane 0 enters Active: no hold, and none when it starts later
                for s in 0 to 2 loop
                    setLane(0, LaneStateClearLine_c, false);
                    setLane(1, IdleStates_c(s), false);
                    cycles(3);
                    setLane(0, LaneStateActive_c, false);
                    cycles(3);
                    check_value(Hold, '0', error, "No hold with lane 1 in state " & to_hstring(IdleStates_c(s)));
                    setLane(1, LaneStateStarted_c, false);
                    cycles(3);
                    check_value(Hold, '0', error, "No hold when lane 1 starts after the hold ended");
                end loop;

                -- A disabled lane does not hold
                setLane(0, LaneStateClearLine_c, false);
                setLane(1, LaneStateConnecting_c, false);
                TxEn(1) <= '0';
                RxEn(1) <= '0';
                cycles(3);
                setLane(0, LaneStateActive_c, false);
                cycles(3);
                check_value(Hold, '0', error, "No hold by a disabled lane");
                TxEn(1) <= '1';
                RxEn(1) <= '1';

                -- Bypass: no hold
                setLane(0, LaneStateClearLine_c, false);
                Bypass <= '1';
                cycles(3);
                setLane(0, LaneStateActive_c, false);
                cycles(3);
                check_value(Hold, '0', error, "No hold in bypass");
                Bypass <= '0';
                check_value(Hold0Seen, false, error, "No hold with LaneJoinHoldWords_g = 0");
            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 100 us);

    -- Hold of the instance with LaneJoinHoldWords_g = 0
    p_hold0 : process (Clk) is
    begin
        if rising_edge(Clk) and Hold0 = '1' then
            Hold0Seen <= true;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Device under test
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_ml_lane_mgr
        generic map (
            NumLanes_g          => N_c,
            LaneJoinHoldWords_g => HoldWords_c
        )
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Cfg_TxEn                => TxEn,
            Cfg_RxEn                => RxEn,
            Cfg_MaxDataLanes        => "000",
            Cfg_Bypass              => Bypass,
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
            Tx_Hold                 => Hold,
            Enc_Scramble            => open,
            Dec_Unscramble          => open
        );

    -- The same stimuli with the join hold off
    i_dut_off : entity work.ofb_ml_lane_mgr
        generic map (
            NumLanes_g          => N_c,
            LaneJoinHoldWords_g => 0
        )
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Cfg_TxEn                => TxEn,
            Cfg_RxEn                => RxEn,
            Cfg_MaxDataLanes        => "000",
            Cfg_Bypass              => Bypass,
            Dl_LaneReset            => '0',
            Dl_NearCapability       => x"00",
            Dl_FarCapability        => open,
            Dl_FarCapabilityValid   => open,
            Dl_FarCapabilityIdle    => open,
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
            Tx_Hold                 => Hold0,
            Enc_Scramble            => open,
            Dec_Unscramble          => open
        );

end architecture;
