---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the medium access controller (DT-4): priority, bandwidth credit, minimum
-- bandwidth credit threshold, schedule, bandwidth zero, over / under use, configuration reset.
--
-- Documentation: hdl/ofb_dl/docs/verification_plan.md

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
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_mac_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_dl_mac_tb is

    constant NumVc_c : positive := 4;
    constant Limit_c : positive := 1024; -- Small Bandwidth Credit Limit for short tests

    signal Clk       : std_logic                               := '0';
    signal Rst       : std_logic                               := '1';
    signal CfgRst    : std_logic                               := '0';
    signal Priority  : std_logic_vector(4*NumVc_c-1 downto 0)  := x"3333";
    signal BwFactor  : std_logic_vector(16*NumVc_c-1 downto 0) := x"0400" & x"0400" & x"0400" & x"0400";
    signal Slots     : std_logic_vector(64*NumVc_c-1 downto 0) := (others => '1');
    signal IdleLimit : std_logic_vector(31 downto 0)           := x"00000100";
    signal TimeSlot  : std_logic_vector(5 downto 0)            := "000000";
    signal SegReady  : std_logic_vector(NumVc_c-1 downto 0)    := (others => '0');
    signal Grant     : std_logic_vector(NumVc_c-1 downto 0);
    signal GrantVld  : std_logic;
    signal WordSent  : std_logic                               := '0';
    signal SegSent   : std_logic                               := '0';
    signal SegVc     : std_logic_vector(4 downto 0)            := (others => '0');
    signal SegWords  : std_logic_vector(6 downto 0)            := (others => '0');
    signal BwOver    : std_logic_vector(NumVc_c-1 downto 0);
    signal BwUnder   : std_logic_vector(NumVc_c-1 downto 0);

begin

    Clk <= not Clk after 3 ns;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Count_v : natural;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        procedure setPrio (vc : natural; prio : natural) is
        begin
            Priority(4*vc+3 downto 4*vc) <= std_logic_vector(to_unsigned(prio, 4));
        end procedure;

        procedure setFactor (vc : natural; factor : std_logic_vector(15 downto 0)) is
        begin
            BwFactor(16*vc+15 downto 16*vc) <= factor;
        end procedure;

        -- One segment of 62 data words (64 words with SDF and EDF) of a VC, 64 words on the link
        procedure sendSegment (vc : natural) is
        begin
            SegVc    <= std_logic_vector(to_unsigned(vc, 5));
            SegWords <= std_logic_vector(to_unsigned(62, 7));
            SegSent  <= '1';
            WordSent <= '1';
            cycles(1);
            SegSent  <= '0';
            cycles(63);
            WordSent <= '0';
        end procedure;

        procedure checkGrant (vc : natural; msg : string) is
            variable Exp_v : std_logic_vector(NumVc_c-1 downto 0);
        begin
            cycles(4);
            Exp_v     := (others => '0');
            Exp_v(vc) := '1';
            check_value(GrantVld, '1', error, msg & ": grant valid");
            check_value(Grant, Exp_v, error, msg);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        cycles(5);
        Rst <= '0';
        cycles(5);

        while test_suite loop

            -- TC-QS-01: priority decides between ready VCs with equal credit
            if run("test_priority") then
                SegReady <= "0011";
                checkGrant(0, "Equal priority and credit: lowest VC");
                setPrio(1, 0);
                checkGrant(1, "Higher priority of VC 1");
                SegReady <= "0001";
                checkGrant(0, "Only VC 0 ready");
                SegReady <= "0000";
                cycles(4);
                check_value(GrantVld, '0', error, "No VC ready");

            -- TC-QS-02: within one priority level the bandwidth credit decides
            elsif run("test_bandwidth_credit") then
                SegReady <= "0011";
                -- VC 0 sends: its credit falls below the one of VC 1
                sendSegment(0);
                checkGrant(1, "VC 1 after VC 0 used bandwidth");
                sendSegment(1);
                sendSegment(1);
                checkGrant(0, "VC 0 after VC 1 used more bandwidth");

            -- TC-QS-03: below the minimum bandwidth credit threshold the priority precedence is zero
            elsif run("test_threshold") then
                setPrio(0, 0);
                setFactor(0, x"2000");
                SegReady <= "0011";
                checkGrant(0, "High priority VC 0");

                -- VC 0 overuses its bandwidth (factor 32): credit down to -B
                for i in 1 to 4 loop
                    sendSegment(0);
                end loop;

                check_value(BwOver(0), '1', error, "Bandwidth over use of VC 0");
                checkGrant(1, "VC 1 of lower priority wins against the overusing VC 0");

            -- TC-QS-04: scheduled QoS: only VCs allocated to the current time-slot compete
            elsif run("test_schedule") then
                Slots(64*0+5) <= '0';
                Slots(64*1+6) <= '0';
                SegReady      <= "0011";
                TimeSlot      <= std_logic_vector(to_unsigned(5, 6));
                checkGrant(1, "VC 0 not allocated to slot 5");
                TimeSlot      <= std_logic_vector(to_unsigned(6, 6));
                checkGrant(0, "VC 1 not allocated to slot 6");
                Slots(64*0+6) <= '0';
                cycles(4);
                check_value(GrantVld, '0', error, "No VC allocated to slot 6");

            -- TC-QS-05: a VC with bandwidth zero does not send
            elsif run("test_bandwidth_zero") then
                setFactor(1, x"0000");
                SegReady <= "0010";
                cycles(4);
                check_value(GrantVld, '0', error, "VC 1 with bandwidth zero");
                SegReady <= "0011";
                checkGrant(0, "VC 0 sends");

            -- TC-QS-06: bandwidth under use after the idle time limit at the positive limit
            elsif run("test_under_use") then
                -- No segment sent: credits rise to +B (1024 words) and stay there
                WordSent <= '1';
                Count_v  := 0;

                while BwUnder(2) = '0' and Count_v < 3000 loop
                    cycles(1);
                    Count_v := Count_v + 1;
                end loop;

                check_value(BwUnder(2), '1', error, "Bandwidth under use");
                check_value(Count_v >= 1024 + 256 - 66, error, "Under use after the limit and the idle time");
                sendSegment(2);
                cycles(2);
                check_value(BwUnder(2), '0', error, "Under use ends with a segment");

            -- TC-QS-07: Interface Reset clears the credits
            elsif run("test_config_reset") then
                SegReady <= "0011";
                sendSegment(0);
                checkGrant(1, "VC 1 after VC 0 sent");
                CfgRst   <= '1';
                cycles(1);
                CfgRst   <= '0';
                checkGrant(0, "Equal credits after Interface Reset");

            end if;

        end loop;

        test_runner_cleanup(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

    i_dut : entity work.ofb_dl_mac
        generic map (
            NumVc_g       => NumVc_c,
            NumPrio_g     => 4,
            CreditLimit_g => Limit_c
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Ctrl_ConfigReset => CfgRst,
            Cfg_Priority     => Priority,
            Cfg_BwFactor     => BwFactor,
            Cfg_Slots        => Slots,
            Cfg_IdleLimit    => IdleLimit,
            TimeSlot         => TimeSlot,
            Seg_Ready        => SegReady,
            Grant            => Grant,
            Grant_Valid      => GrantVld,
            Ev_WordSent      => WordSent,
            Ev_SegSent       => SegSent,
            SegSent_Vc       => SegVc,
            SegSent_Words    => SegWords,
            Stat_BwOver      => BwOver,
            Stat_BwUnder     => BwUnder
        );

end architecture;
