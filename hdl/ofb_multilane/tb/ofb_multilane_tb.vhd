---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Layer testbench of the Multi-Lane layer with one lane (bypass): traffic between two ends through
-- Lane layers and the behavioural Physical adapter model, scrambling negotiated by the INIT3
-- capability, lane control and status, Multi-Lane control words and link reset.
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

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_ml_tb_pkg.all;
    use work.ofb_multilane_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_multilane_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_multilane_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

    -- Capability bits
    constant CapScrambled_c : Char_t := x"04";

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable SA_v : Stream_t;
        variable SB_v : Stream_t;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Wait until both ends are active
        procedure waitActive is
            variable Start_v : time;
        begin
            Start_v := now;

            while MlStat(0).LaneActive /= '1' or MlStat(1).LaneActive /= '1' loop
                cycles(1);
                if now - Start_v > 200 us then
                    alert(error, "Timeout waiting for both lanes to become active");
                    exit;
                end if;
            end loop;

            cycles(10);
        end procedure;

        -- Start both lanes and wait until both ends are active
        procedure startLink is
        begin
            MlCfg(0).LaneStart <= '1';
            MlCfg(1).LaneStart <= '1';
            waitActive;
        end procedure;

        -- Queue the words of a stream at one end (chunks of at most 512 words)
        procedure sendStream (
            src : natural;
            s   : Stream_t) is
            variable Pos_v : natural;
            variable Len_v : natural;
        begin
            Pos_v := 0;

            while Pos_v < s.Count loop
                Len_v := minimum(s.Count - Pos_v, 512);
                axistream_transmit(AXISTREAM_VVCT, VvcA_c + src, toSlvArray(s.Data(Pos_v to Pos_v + Len_v - 1)),
                                   toUserArray(s.K(Pos_v to Pos_v + Len_v - 1)), to_string(Len_v) & " words");
                Pos_v := Pos_v + Len_v;
            end loop;

        end procedure;

        procedure awaitSent is
        begin
            await_completion(AXISTREAM_VVCT, VvcA_c, 10 ms, "Rows of A sent");
            await_completion(AXISTREAM_VVCT, VvcB_c, 10 ms, "Rows of B sent");
            cycles(100);
        end procedure;

        -- Compare the rows received at an end with a stream (Multi-Lane control words excluded)
        procedure checkRx (
            dst : natural;
            s   : Stream_t;
            msg : string) is
            variable Exp_v  : natural;
            variable Cnt_v  : natural;
            variable Got_v  : KWord_t;
            variable Flag_v : std_logic;
        begin
            if dst = 0 then
                Cnt_v := RxLogA_v.count;
            else
                Cnt_v := RxLogB_v.count;
            end if;
            Exp_v := 0;

            for i in 0 to s.Count-1 loop
                if s.Drop(i) = '0' then
                    if Exp_v < Cnt_v then
                        if dst = 0 then
                            Got_v  := RxLogA_v.get(Exp_v);
                            Flag_v := RxLogA_v.getFlag(Exp_v);
                        else
                            Got_v  := RxLogB_v.get(Exp_v);
                            Flag_v := RxLogB_v.getFlag(Exp_v);
                        end if;
                        check_value(Got_v, s.K(i) & s.Dec(i), error, msg & ": row " & to_string(Exp_v));
                        check_value(Flag_v, s.CrcErr(i), error, msg & ": CRC error flag of row " & to_string(Exp_v));
                    end if;
                    Exp_v := Exp_v + 1;
                end if;
            end loop;

            check_value(Cnt_v, Exp_v, error, msg & ": number of rows");
        end procedure;

        procedure clearLogs is
        begin
            RxLogA_v.clear;
            RxLogB_v.clear;
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        wait until Rst = '0';
        cycles(2);

        while test_suite loop

            -- TC-ML-20: traffic in both directions with scrambling
            if run("test_bypass_traffic") then
                MlCfg(0).NearCapability <= CapScrambled_c;
                MlCfg(1).NearCapability <= CapScrambled_c;
                startLink;
                streamClear(SA_v, true);
                streamClear(SB_v, true);
                addRandomStream(SA_v, 3000, true, false);
                addRandomStream(SB_v, 3000, true, false);
                sendStream(0, SA_v);
                sendStream(1, SB_v);
                awaitSent;
                checkRx(1, SA_v, "A to B");
                checkRx(0, SB_v, "B to A");

            -- TC-ML-21: scrambling follows the INIT3 capability; a change takes effect after LaneReset
            elsif run("test_scramble_capability") then
                MlCfg(0).NearCapability <= CapScrambled_c;
                MlCfg(1).NearCapability <= x"00";
                startLink;
                streamClear(SA_v, true);
                streamClear(SB_v, false);
                addRandomStream(SA_v, 1000, true, false);
                addRandomStream(SB_v, 1000, true, false);
                sendStream(0, SA_v);
                sendStream(1, SB_v);
                awaitSent;
                checkRx(1, SA_v, "A scrambled to B");
                checkRx(0, SB_v, "B not scrambled to A");
                -- DataScrambled cleared while Active: A keeps scrambling
                clearLogs;
                MlCfg(0).NearCapability <= x"00";
                streamClear(SA_v, true);
                addRandomStream(SA_v, 500, true, false);
                sendStream(0, SA_v);
                awaitSent;
                checkRx(1, SA_v, "A still scrambled after the change in Active");
                -- LaneReset: the new value is sent in INIT3 and used
                MlCfg(0).LaneReset <= '1';
                cycles(10);
                MlCfg(0).LaneReset <= '0';
                cycles(10);
                waitActive;
                clearLogs;
                streamClear(SA_v, false);
                addRandomStream(SA_v, 500, true, false);
                sendStream(0, SA_v);
                awaitSent;
                checkRx(1, SA_v, "A not scrambled after LaneReset");
                check_value(MlStat(1).FarCapability(CapDataScrambled_c), '0', error, "B sees DataScrambled cleared");

            -- TC-ML-22: lane control, capability exchange and status
            elsif run("test_lane_control") then
                check_value(MlStat(0).AlignState, AlignNotReady_c, error, "Alignment state before start");
                check_value(MlStat(0).DataSending, '0', error, "No data-sending lane before start");
                -- LinkReset, DataScrambled and MultiLane bits set by the Data Link layer
                MlCfg(0).NearCapability <= x"0D";
                MlCfg(1).NearCapability <= x"00";
                cycles(2);
                check_value(MlStat(0).LaneNearCap, x"05", error, "MultiLane bit cleared towards the lane");
                startLink;
                check_value(MlStat(1).FarCapability, x"07", error, "Far-end capability at B (LaneStart set by the lane)");
                check_value(MlStat(1).FarCapCnt >= 1, error, "Far-end capability event at B");
                check_value(MlStat(0).FarCapability, x"02", error, "Far-end capability at A");

                for i in 0 to 1 loop
                    check_value(MlStat(i).DataSending, '1', error, "Data-sending lane " & to_string(i));
                    check_value(MlStat(i).DataReceiving, '1', error, "Data-receiving lane " & to_string(i));
                    check_value(MlStat(i).AlignState, AlignBothEndsReady_c, error, "Alignment state " & to_string(i));
                end loop;

                -- LaneReset from the Data Link layer restarts the lane
                MlCfg(0).LaneReset <= '1';
                cycles(5);
                check_value(MlStat(0).LaneCtrl, "1000", error, "LaneReset passed to the lane");
                check_value(MlStat(0).LaneActive, '0', error, "Lane not active during LaneReset");
                check_value(MlStat(0).DataSending, '0', error, "No data-sending lane during LaneReset");
                check_value(MlStat(0).AlignState, AlignNotReady_c, error, "Alignment state during LaneReset");
                MlCfg(0).LaneReset <= '0';
                cycles(10);
                waitActive;
                check_value(MlStat(0).ActiveCnt, 2, error, "Lane A active again");
                check_value(MlStat(0).FarCapCnt >= 2, error, "Capability received again");

                for i in 0 to 1 loop
                    check_value(MlStat(i).LaneCtrlSeen(2 downto 0), "000", error,
                                "TxOnly, RxOnly, FarEndActive never asserted at " & to_string(i));
                end loop;

            -- TC-ML-25: the near-end capability is held while the lane is in Connected
            elsif run("test_capability_hold") then
                MlCfg(0).NearCapability <= x"01";
                MlCfg(0).LaneStart      <= '1';
                MlCfg(1).LaneStart      <= '1';

                while MlStat(0).LaneState /= LaneStateConnected_c loop
                    cycles(1);
                end loop;

                -- INIT3LinkResetFlag cleared in the middle of Connected
                MlCfg(0).NearCapability <= x"00";
                waitActive;
                check_value(MlStat(1).FarCapability, x"03", error, "B received the value held in Connected");
                check_value(MlStat(0).LaneNearCap, x"00", error, "New value passed to the lane after Connected");
                MlCfg(0).LaneReset      <= '1';
                cycles(10);
                MlCfg(0).LaneReset      <= '0';
                cycles(10);
                waitActive;
                check_value(MlStat(1).FarCapability, x"02", error, "New value sent in the next initialisation");

            -- TC-ML-23: PAD, ACTIVE and ALIGN are not passed to the Data Link layer
            elsif run("test_ml_ctrl_discard") then
                startLink;
                streamClear(SA_v, false);
                addCtrl(SA_v, wordActive(x"0001"), KCtrl_c, EffNone, true);
                addSdf(SA_v, 7);
                addData(SA_v, x"01234567");
                addCtrl(SA_v, WordPad_c, KPad_c, EffNone, true);
                addData(SA_v, x"89ABCDEF");
                addCtrl(SA_v, wordAlign("0001", "0000"), KCtrl_c, EffNone, true);
                addEdf(SA_v, 1);
                addCtrl(SA_v, WordPad_c, KPad_c, EffNone, true);
                addRandomStream(SA_v, 200, true, false);
                sendStream(0, SA_v);
                streamClear(SB_v, false);
                sendStream(1, SB_v);
                awaitSent;
                checkRx(1, SA_v, "Multi-Lane control words discarded");

            -- TC-ML-24: link reset discards a row held while the lane is not active
            elsif run("test_link_reset_flush") then
                streamClear(SA_v, false);
                addSdf(SA_v, 9);
                sendStream(0, SA_v);
                await_completion(AXISTREAM_VVCT, VvcA_c, 1 us, "SDF taken by the Multi-Lane layer");
                cycles(2);
                MlCfg(0).LinkReset <= '1';
                cycles(1);
                MlCfg(0).LinkReset <= '0';
                startLink;
                streamClear(SA_v, false);
                addRandomStream(SA_v, 300, false, false);
                sendStream(0, SA_v);
                awaitSent;
                checkRx(1, SA_v, "Only the rows sent after the link reset");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 10 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_multilane_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
