---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Layer testbench of ofb_lane: two lane ends connected through the behavioural Physical adapter
-- model.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

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
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_pa_pkg.all;
    use work.ofb_lane_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_tb is

    constant A_c : natural := 0;
    constant B_c : natural := 1;

    constant ClkPeriod_c : time := 6.4 ns;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Seed1_v : positive := 17;
        variable Seed2_v : positive := 4711;

        -- Wait until a lane end reaches a state
        procedure waitState (
            lane    : natural;
            state   : LaneState_t;
            timeout : time;
            msg     : string) is
            variable Start_v : time;
        begin
            Start_v := now;

            while LaneStat(lane).State /= state loop
                wait for ClkPeriod_c;
                if now - Start_v >= timeout then
                    alert(error, "Timeout waiting for lane state " & to_hstring(state) & ": " & msg &
                          " (states A=" & to_hstring(LaneStat(0).State) & " B=" & to_hstring(LaneStat(1).State) &
                          ", timeouts A=" & to_string(LaneStat(0).TimeoutCnt) & " B=" &
                          to_string(LaneStat(1).TimeoutCnt) & ")");
                    return;
                end if;
            end loop;

            log(ID_SEQUENCER, "Lane " & to_string(lane) & " in state " & to_hstring(state) & ": " & msg);
        end procedure;

        procedure waitCycles (n : natural) is
        begin
            wait for n * ClkPeriod_c;
        end procedure;

        -- Random word of the upper layers: data word, word with EOP / EEP, or Data Link control word
        procedure randomWord (
            word : out Word_t;
            k    : out WordK_t) is
            variable R_v    : real;
            variable Kind_v : natural;
            variable W_v    : Word_t;
        begin

            for i in 0 to 3 loop
                uniform(Seed1_v, Seed2_v, R_v);
                W_v(8*i+7 downto 8*i) := std_logic_vector(to_unsigned(natural(floor(R_v * 256.0)) mod 256, 8));
            end loop;

            uniform(Seed1_v, Seed2_v, R_v);
            Kind_v := natural(floor(R_v * 10.0));
            if Kind_v < 7 then
                word := W_v;
                k    := KData_c;
            elsif Kind_v = 7 then
                W_v(31 downto 24) := CharEop_c;
                word              := W_v;
                k                 := "1000";
            elsif Kind_v = 8 then
                word := wordSif(W_v(7 downto 0));
                k    := KCtrl_c;
            else
                word := wordAck(W_v(15 downto 8));
                k    := KCtrl_c;
            end if;
        end procedure;

        -- Send words from a lane end (one VVC command, at most 512 words) and expect them at the other end
        procedure sendChunk (
            src : natural;
            n   : positive) is
            variable Words_v : WordArray_t(0 to n-1);
            variable Ks_v    : WordKArray_t(0 to n-1);
        begin

            for i in 0 to n-1 loop
                randomWord(Words_v(i), Ks_v(i));
                if LaneCfg(src).NearLoopback = '1' or LaneCfg(1-src).FarLoopback = '1' then
                    RxSb_v.add_expected(src + 1, Ks_v(i) & Words_v(i));
                else
                    RxSb_v.add_expected(2 - src, Ks_v(i) & Words_v(i));
                end if;
            end loop;

            axistream_transmit(AXISTREAM_VVCT, VvcTxA_c + src, toSlvArray(Words_v), toUserArray(Ks_v),
                               to_string(n) & " words from lane end " & to_string(src));
        end procedure;

        procedure sendWords (
            src : natural;
            n   : positive) is
            variable Left_v : natural;
        begin
            Left_v := n;

            while Left_v > 0 loop
                sendChunk(src, minimum(Left_v, 512));
                Left_v := Left_v - minimum(Left_v, 512);
            end loop;

        end procedure;

        -- Wait until all words sent are received
        procedure awaitWords (timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;
            await_completion(AXISTREAM_VVCT, VvcTxA_c, timeout, "Transmit A");
            await_completion(AXISTREAM_VVCT, VvcTxB_c, timeout, "Transmit B");

            while RxSb_v.get_pending_count(1) /= 0 or RxSb_v.get_pending_count(2) /= 0 loop
                waitCycles(10);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for the received words");
                    exit;
                end if;
            end loop;

            check_value(RxSb_v.get_pending_count(1), 0, error, "All words received at lane end A");
            check_value(RxSb_v.get_pending_count(2), 0, error, "All words received at lane end B");
        end procedure;

        procedure startBoth is
        begin
            LaneCfg(A_c).LaneStart <= '1';
            LaneCfg(B_c).LaneStart <= '1';
            waitState(A_c, LaneStateActive_c, 100 us, "A active");
            waitState(B_c, LaneStateActive_c, 100 us, "B active");
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        RxSb_v.set_scope("RX_SB");
        RxSb_v.enable(1);
        RxSb_v.enable(2);
        RxSb_v.disable_log_msg(1, ID_DATA);
        RxSb_v.disable_log_msg(2, ID_DATA);
        wait for 200 ns;

        while test_suite loop

            -- TC-LN-01: both ends with LaneStart reach Active and exchange their capabilities
            if run("test_init_lanestart") then
                LaneCfg(A_c).NearCapability <= x"1D";
                LaneCfg(B_c).NearCapability <= x"04";
                startBoth;
                waitCycles(20);
                check_value(LaneStat(A_c).CapEventCnt, 1, error, "A capability event");
                check_value(LaneStat(B_c).CapEventCnt, 1, error, "B capability event");
                -- Bit 1 (INIT3LaneStart) carries LaneStart of the sending lane
                check_value(LaneStat(B_c).CtrlFarCap, x"1F", error, "Capability of A seen at B");
                check_value(LaneStat(A_c).CtrlFarCap, x"06", error, "Capability of B seen at A");
                check_value(LaneStat(B_c).FarCapability, x"1F", error, "Far-end capability status at B");
                check_value(LaneStat(A_c).TimeoutCnt, 0, error, "No timeout at A");
                check_value(LaneStat(B_c).TimeoutCnt, 0, error, "No timeout at B");
                check_value(LaneStat(A_c).RxPolarity, '0', error, "A receive polarity");

            -- TC-LN-02: an AutoStart end starts when the far end sends
            elsif run("test_init_autostart") then
                LaneCfg(B_c).AutoStart <= '1';
                waitState(B_c, LaneStateWait_c, 10 us, "B waits for a signal");
                waitCycles(2000);
                check_value(LaneStat(B_c).State, LaneStateWait_c, error, "B stays in Wait without signal");
                LaneCfg(A_c).LaneStart <= '1';
                waitState(A_c, LaneStateActive_c, 100 us, "A active");
                waitState(B_c, LaneStateActive_c, 100 us, "B active");

            -- TC-LN-03: without a far end the initialisation times out and restarts
            elsif run("test_init_timeout") then
                LaneCfg(A_c).LaneStart <= '1';
                waitState(A_c, LaneStateStarted_c, 10 us, "A started");
                wait for 100 us;
                check_value(LaneStat(A_c).TimeoutCnt >= 2, error, "A timed out at least twice");
                check_value(LaneStat(B_c).State, LaneStateDisabled_c, error, "B disabled");

            -- TC-LN-04: words pass in both directions, lane control words are filtered
            elsif run("test_data_transfer") then
                startBoth;
                shared_axistream_vvc_config(VvcTxA_c).bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcTxA_c).bfm_config.valid_low_duration    := C_RANDOM;
                sendWords(A_c, 3000);
                sendWords(B_c, 3000);
                awaitWords(200 us);
                check_value(LaneStat(A_c).RxErrWordCnt, 0, error, "No RXERR at A");
                check_value(LaneStat(B_c).RxErrWordCnt, 0, error, "No RXERR at B");

            -- TC-LN-05: SKIP every 5000 words in Active, including during data transfer
            elsif run("test_skip_insertion") then
                startBoth;
                sendWords(A_c, 8000);
                awaitWords(500 us);
                wait for 50 us;
                check_value(LaneStat(A_c).SkipCnt >= 3, error, "At least three SKIP words sent by A");
                check_value(LaneStat(A_c).SkipGapMin, 4999, error, "4999 words between two SKIP words (min)");
                check_value(LaneStat(A_c).SkipGapMax, 4999, error, "4999 words between two SKIP words (max)");

            -- TC-LN-06: a crossed pair is corrected by InvertRxPolarity
            elsif run("test_rx_polarity") then
                PaCtrl(0).AtoB.Invert <= true;
                startBoth;
                check_value(LaneStat(B_c).RxPolarity, '1', error, "B inverts the received bits");
                check_value(LaneStat(A_c).RxPolarity, '0', error, "A does not invert");
                sendWords(A_c, 1000);
                sendWords(B_c, 1000);
                awaitWords(100 us);

            -- TC-LN-07: words are aligned whatever the symbol offset on the line
            elsif run("test_word_alignment") then
                PaCtrl(0).AtoB.Offset <= 1;
                PaCtrl(0).BtoA.Offset <= 3;
                startBoth;
                sendWords(A_c, 1000);
                sendWords(B_c, 1000);
                awaitWords(100 us);
                -- Realignment in Active: some RXERR words, then words pass again
                LaneCfg(B_c).SbCheck  <= false;
                PaCtrl(0).AtoB.Offset <= 2;
                waitCycles(500);
                check_value(LaneStat(B_c).RxErrWordCnt >= 1, error, "Realignment produces RXERR at B");
                check_value(LaneStat(B_c).State, LaneStateActive_c, error, "B stays active after realignment");

            -- TC-LN-08: bit errors produce RXERR words and count, the lane stays active
            elsif run("test_bit_errors") then
                startBoth;
                LaneCfg(B_c).SbCheck <= false;

                for i in 1 to 10 loop
                    PaCtrl(0).AtoB.Flips <= i;
                    waitCycles(200);
                end loop;

                waitCycles(100);
                check_value(LaneStat(B_c).RxErrWordCnt >= 10, error, "RXERR words passed up at B");
                check_value(to_integer(unsigned(LaneStat(B_c).RxErrCount)) >= 10, error, "RXERR counter at B");
                check_value(LaneStat(B_c).State, LaneStateActive_c, error, "B still active");
                check_value(LaneStat(B_c).OverflowCnt, 0, error, "No overflow");

            -- TC-LN-09: RXERR counter overflow ends Active with LOS_Cause 0b01 and stays visible
            elsif run("test_rxerr_overflow") then
                startBoth;
                LaneCfg(A_c).SbCheck <= false;
                LaneCfg(B_c).SbCheck <= false;

                for i in 1 to 400 loop
                    PaCtrl(0).AtoB.Flips <= i;
                    waitCycles(2);
                    exit when LaneStat(B_c).OverflowCnt /= 0;
                end loop;

                waitState(B_c, LaneStateLossOfSignal_c, 50 us, "B in LossOfSignal after the overflow");
                check_value(LaneStat(B_c).OverflowCnt, 1, error, "One overflow event at B");
                waitState(B_c, LaneStateClearLine_c, 50 us, "B in ClearLine");
                check_value(LaneStat(B_c).RxErrCount, x"FF", error, "Counter stays at 255 after Active");
                check_value(LaneStat(A_c).FarLostCnt >= 1, error, "A received LOST_SIGNAL");
                check_value(LaneStat(A_c).FarLostReason, x"01", error, "LOS_Cause 0b01: too many errors");
                -- Both ends recover; the counter is cleared in Connected
                waitState(A_c, LaneStateActive_c, 200 us, "A active again");
                waitState(B_c, LaneStateActive_c, 200 us, "B active again");
                check_value(LaneStat(B_c).RxErrCount, x"00", error, "Counter cleared in Connected");

            -- TC-LN-10: LaneStart and AutoStart de-asserted: STANDBY, far end in ClearLine
            elsif run("test_standby") then
                LaneCfg(A_c).StandbyReason <= x"53";
                LaneCfg(A_c).SbCheck       <= false; -- RXERR passed up when Active is left
                LaneCfg(B_c).SbCheck       <= false;
                startBoth;
                LaneCfg(A_c).LaneStart     <= '0';
                waitState(A_c, LaneStatePrepareStandby_c, 1 us, "A prepares standby");
                waitState(A_c, LaneStateDisabled_c, 10 us, "A disabled");
                check_value(LaneStat(B_c).FarStandbyCnt >= 3, error, "B received STANDBY");
                check_value(LaneStat(B_c).FarStandbyReason, x"53", error, "Standby Reason at B");
                check_value(LaneStat(B_c).State /= LaneStateActive_c, error, "B left Active");

            -- TC-LN-11: loss of signal at one end, LOST_SIGNAL to the far end, recovery
            elsif run("test_loss_of_signal") then
                startBoth;
                LaneCfg(A_c).SbCheck <= false;
                LaneCfg(B_c).SbCheck <= false;
                PaCtrl(0).AtoB.Cut   <= true;
                waitState(B_c, LaneStateLossOfSignal_c, 1 us, "B detects the loss of signal");
                waitState(A_c, LaneStateClearLine_c, 10 us, "A in ClearLine after LOST_SIGNAL");
                check_value(LaneStat(A_c).FarLostReason, x"00", error, "LOS_Cause 0b00: no signal");
                check_value(LaneStat(B_c).RxErrWordCnt >= 1, error, "RXERR passed up when Active is left");
                PaCtrl(0).AtoB.Cut   <= false;
                waitState(A_c, LaneStateActive_c, 200 us, "A active again");
                waitState(B_c, LaneStateActive_c, 200 us, "B active again");

            -- TC-LN-12: LaneReset restarts the lane
            elsif run("test_lane_reset") then
                startBoth;
                LaneCfg(A_c).SbCheck   <= false;
                LaneCfg(B_c).SbCheck   <= false;
                LaneCfg(A_c).LaneReset <= '1';
                waitCycles(1);
                LaneCfg(A_c).LaneReset <= '0';
                waitState(A_c, LaneStateClearLine_c, 1 us, "A in ClearLine");
                waitState(A_c, LaneStateActive_c, 200 us, "A active again");
                waitState(B_c, LaneStateActive_c, 200 us, "B active again");
                check_value(LaneStat(A_c).ActiveCnt, 2, error, "A entered Active twice");

            -- TC-LN-13: near-end parallel loopback
            elsif run("test_near_loopback") then
                LaneCfg(A_c).NearLoopback <= '1';
                LaneCfg(A_c).LaneStart    <= '1';
                waitState(A_c, LaneStateActive_c, 100 us, "A active in near-end loopback");
                sendWords(A_c, 1000);
                awaitWords(100 us);

            -- TC-LN-14: far-end parallel loopback
            elsif run("test_far_loopback") then
                LaneCfg(B_c).FarLoopback <= '1';
                LaneCfg(B_c).SbCheck     <= false; -- B also passes the words of A up
                LaneCfg(B_c).LaneStart   <= '1';
                LaneCfg(A_c).LaneStart   <= '1';
                waitState(A_c, LaneStateActive_c, 100 us, "A active with far-end loopback at B");
                sendWords(A_c, 1000);
                awaitWords(100 us);

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 5 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_lane_th;

end architecture;
