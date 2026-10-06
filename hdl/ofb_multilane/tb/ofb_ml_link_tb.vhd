---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Layer testbench of a multi-lane link (2 or 4 lanes): alignment and traffic, words on the lanes,
-- skew and slip, hot redundant lanes, lane failure, asymmetric links, bypass, RXERR and link reset.
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
    use work.ofb_ml_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_pa_pkg.all;
    use work.ofb_ml_link_tb_pkg.all;
    use work.ofb_ml_row_queue_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_link_tb is
    generic (
        runner_cfg : string;
        NumLanes_g : positive range 2 to 4 := 2
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_link_tb is

    constant N_c : positive := NumLanes_g;

    signal Clk : std_logic;
    signal Rst : std_logic;

    -- All lanes of the configuration
    constant AllLanes_c : std_logic_vector(MaxLanes_c-1 downto 0) :=
        std_logic_vector(to_unsigned(2 ** N_c - 1, MaxLanes_c));

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Num_v : natural;
        variable Seq_v : natural := 0;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Wait until both ends are in the given alignment state (Near-End Ready: at least)
        procedure waitAlign (
            state : AlignState_t;
            msg   : string;
            limit : time := 400 us) is
            variable Start_v : time;
        begin
            Start_v := now;

            -- Near-End Ready: both ends at least in Near-End Ready
            while (LinkStat(0).AlignState /= state or LinkStat(1).AlignState /= state) and
                  (state /= AlignNearEndReady_c or LinkStat(0).AlignState = AlignNotReady_c or
                   LinkStat(1).AlignState = AlignNotReady_c) loop
                cycles(1);
                if now - Start_v > limit then
                    alert(error, "Timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Wait until all rows are sent and all expected words received
        procedure waitTraffic (
            msg   : string;
            limit : time := 1 ms) is
            variable Start_v : time;
        begin
            Start_v := now;

            while not trafficDone loop
                cycles(1);
                if now - Start_v > limit then
                    alert(error, "Timeout: " & msg);
                    exit;
                end if;
            end loop;

            cycles(50);
        end procedure;

        -- One frame in each direction: the data words bring both ends to Both-Ends Ready
        procedure toBothEnds (msg : string) is
        begin
            Seq_v := Seq_v + 1;
            txFrame(0, N_c, 1, 5, Seq_v, false);
            txFrame(1, N_c, 2, 5, Seq_v, false);
            waitAlign(AlignBothEndsReady_c, msg);
            waitTraffic(msg);
        end procedure;

        -- Start the lanes of both ends, align and reach Both-Ends Ready
        procedure startLink (
            lanesA : std_logic_vector(MaxLanes_c-1 downto 0) := AllLanes_c;
            lanesB : std_logic_vector(MaxLanes_c-1 downto 0) := AllLanes_c) is
        begin
            LinkCfg(0).LaneStart <= lanesA;
            LinkCfg(1).LaneStart <= lanesB;
            waitAlign(AlignNearEndReady_c, "both ends Near-End Ready");
            toBothEnds("both ends Both-Ends Ready");
        end procedure;

        -- Random traffic in both directions, received correctly
        procedure traffic (
            frames : positive;
            msg    : string;
            maxLen : positive := 200) is
        begin
            txTraffic(0, N_c, frames, maxLen);
            txTraffic(1, N_c, frames, maxLen);
            waitTraffic(msg);
        end procedure;

        procedure checkClean (msg : string) is
        begin

            for e in 0 to 1 loop
                check_value(LinkStat(e).CheckErrs, 0, error, msg & ": mismatches at " & to_string(e));
                check_value(LinkStat(e).CrcErrs, 0, error, msg & ": CRC errors at " & to_string(e));
                check_value(LinkStat(e).MidPartial, 0, error, msg & ": incomplete rows inside a frame at " &
                            to_string(e));
                check_value(LinkStat(e).SkipAsync, 0, error, msg & ": SKIP not on all lanes at " & to_string(e));
                check_value(LinkStat(e).PatternErr, 0, error, msg & ": ALIGN pattern at " & to_string(e));
                check_value(LinkStat(e).PadMisuse, 0, error, msg & ": PAD not before an EDF at " & to_string(e));
                check_value(LinkStat(e).HotDlWords, 0, error, msg & ": Data Link words on hot lanes at " &
                            to_string(e));
                check_value(LinkStat(e).BerMlWords, 0, error, msg & ": ACTIVE or ALIGN in Both-Ends Ready at " &
                            to_string(e));
            end loop;

        end procedure;

        -- Switch the comparison off at both ends (words are lost on purpose)
        procedure checkOff is
        begin
            LinkCfg(0).Check <= false;
            LinkCfg(1).Check <= false;
            cycles(2);
        end procedure;

        -- Stop sending, discard the remaining expected words and switch the comparison on again
        procedure checkOn is
        begin
            TxQueueA_v.clear;
            TxQueueB_v.clear;
            cycles(500);
            clearTraffic;
            LinkCfg(0).Check <= true;
            LinkCfg(1).Check <= true;
            cycles(2);
        end procedure;

        -- Wait until all rows are sent (comparison switched off)
        procedure waitSent (msg : string) is
            variable Start_v : time;
        begin
            Start_v := now;

            while not rowsSent loop
                cycles(1);
                if now - Start_v > 1 ms then
                    alert(error, "Timeout: " & msg);
                    exit;
                end if;
            end loop;

            cycles(300);
        end procedure;

        procedure cutLane (
            lane : natural;
            cut  : boolean) is
        begin
            PaCtrl(lane).AtoB.Cut <= cut;
            PaCtrl(lane).BtoA.Cut <= cut;
        end procedure;

        function lanes (n : natural) return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(2 ** n - 1, MaxLanes_c));
        end function;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        wait until Rst = '0';
        cycles(2);

        while test_suite loop

            -- TC-ML-30: alignment with skew and random traffic in both directions
            if run("test_align_traffic") then

                for l in 0 to N_c-1 loop
                    PaCtrl(l).AtoB.Skew <= l mod 3;
                    PaCtrl(l).BtoA.Skew <= (N_c - 1 - l) mod 3;
                end loop;

                startLink;

                for e in 0 to 1 loop
                    check_value(LinkStat(e).DataSending(N_c-1 downto 0), AllLanes_c(N_c-1 downto 0), error,
                                "All lanes data-sending at " & to_string(e));
                    check_value(LinkStat(e).DataReceiving(N_c-1 downto 0), AllLanes_c(N_c-1 downto 0), error,
                                "All lanes data-receiving at " & to_string(e));
                    check_value(LinkStat(e).NearCap0(CapMultiLane_c), '1', error, "Multi-LaneCapable set");
                end loop;

                traffic(40, "Random traffic");
                checkClean("Random traffic");
                check_value(LinkStat(1).Frames >= 40, error, "Frames received at B");
                check_value(LinkStat(0).Frames >= 40, error, "Frames received at A");
                check_value(LinkStat(0).RxErrs + LinkStat(1).RxErrs, 0, error, "No RXERR");

            -- TC-ML-31: words on the lanes in each alignment state
            elsif run("test_lane_words") then
                LinkCfg(0).LaneStart <= AllLanes_c;
                LinkCfg(1).LaneStart <= AllLanes_c;
                -- Without Data Link words both ends stay in Near-End Ready
                waitAlign(AlignNearEndReady_c, "both ends Near-End Ready");
                cycles(1000);
                checkClean("Near-End Ready");

                for e in 0 to 1 loop
                    check_value(LinkStat(e).NrActive > 0, error, "ACTIVE words in Not Ready at " & to_string(e));
                    check_value(LinkStat(e).NrAlign > 0, error, "ALIGN words in Not Ready at " & to_string(e));
                    check_value(LinkStat(e).NerAlign > 0, error, "ALIGN words in Near-End Ready at " &
                                to_string(e));
                    check_value(LinkStat(e).LastActive, wordActive(x"000" & AllLanes_c), error,
                                "ACT field: all lanes active at " & to_string(e));

                    for l in 0 to N_c-1 loop
                        check_value(LinkStat(e).LastAlign(l),
                                    wordAlign(std_logic_vector(to_unsigned(N_c, 4)), std_logic_vector(to_unsigned(l, 4))),
                                    error, "ALIGN fields of lane " & to_string(l) & " at " & to_string(e));
                    end loop;

                    check_value(LinkStat(e).Frames, 0, error, "Nothing received in Near-End Ready");
                end loop;

                -- Traffic with frames that end in incomplete sending rows (PAD), then no traffic
                toBothEnds("Both-Ends Ready");
                traffic(20, "Traffic", 30);
                Num_v := LinkStat(0).IdleWords;
                cycles(1000);
                checkClean("Both-Ends Ready");
                check_value(LinkStat(0).IdleWords > Num_v, error, "IDLE rows without traffic");
                check_value(LinkStat(0).Skips > 0, error, "SKIP sent");

            -- TC-ML-32: skew of three words, slip of a lane
            elsif run("test_skew_slip") then
                PaCtrl(N_c-1).AtoB.Skew <= 3;
                PaCtrl(0).BtoA.Skew     <= 3;
                startLink;
                traffic(20, "Traffic with a skew of 3 words");
                checkClean("Skew of 3 words");
                -- Slip: one word of lane 0 repeated at B while traffic flows
                checkOff;
                txTraffic(0, N_c, 20);
                cycles(500);
                PaCtrl(0).AtoB.Skew <= 1;
                cycles(3000);
                check_value(LinkStat(1).Misaligned > 0, error, "Misaligned condition at B after the slip");
                check_value(LinkStat(1).RxErrs > 0, error, "RXERR passed at B after the slip");
                waitAlign(AlignNearEndReady_c, "alignment after the slip");
                checkOn;
                toBothEnds("Both-Ends Ready after the slip");
                traffic(20, "Traffic after the slip");
                checkClean("After the slip");

            -- TC-ML-46: rows of a frame marked as corrupted at A (uncorrectable error before the column
            -- encoders): the CRC-16 of the frame is inverted, B reports a CRC error; the following
            -- traffic is received correctly
            elsif run("test_poison") then
                startLink;
                checkOff;
                Num_v             := LinkStat(1).AnyErrs - LinkStat(1).RxErrs;
                LinkCfg(0).Poison <= '1';
                Seq_v             := Seq_v + 1;
                txFrame(0, N_c, 1, 20, Seq_v, false);
                waitSent("poisoned frame");
                LinkCfg(0).Poison <= '0';
                check_value(LinkStat(1).AnyErrs - LinkStat(1).RxErrs, Num_v + 1, error,
                            "One EDF with CRC error at B");
                checkOn;
                traffic(10, "Traffic after the poisoned frame");
                checkClean("After the poisoned frame");

            -- TC-ML-44: lane slip at B while both ends send: B realigns (Not Ready), A only receives
            -- ACTIVE words (Near-End Ready); every word that B sends reaches A in order, without RXERR
            elsif run("test_slip_reverse") then
                startLink;
                LinkCfg(1).Check    <= false;
                cycles(2);
                Num_v               := LinkStat(0).RxErrs;
                txTraffic(0, N_c, 20);
                txTraffic(1, N_c, 20);
                cycles(500);
                PaCtrl(0).AtoB.Skew <= 1;

                for i in 0 to 100000 loop
                    exit when TxQueueB_v.count = 0 and ExpFrameB_v.count = 0 and ExpCtrlB_v.count = 0;
                    cycles(1);
                end loop;

                check_value(TxQueueB_v.count = 0 and ExpFrameB_v.count = 0 and ExpCtrlB_v.count = 0, error,
                            "All words of B received at A");
                check_value(LinkStat(1).Misaligned > 0, error, "Misaligned condition at B after the slip");
                check_value(LinkStat(0).RxErrs, Num_v, error, "No RXERR at A");
                check_value(LinkStat(0).CheckErrs, 0, error, "No mismatch at A");
                check_value(LinkStat(0).CrcErrs, 0, error, "No CRC error at A");
                checkOn;
                waitAlign(AlignNearEndReady_c, "alignment after the slip");
                toBothEnds("Both-Ends Ready after the slip");
                traffic(20, "Traffic after the slip");
                checkClean("After the slip");

            -- TC-ML-33: hot redundant lanes
            elsif run("test_hot_redundant") then
                LinkCfg(0).MaxDataLanes <= std_logic_vector(to_unsigned(N_c - 1, 3));
                LinkCfg(1).MaxDataLanes <= std_logic_vector(to_unsigned(N_c - 1, 3));
                startLink;

                for e in 0 to 1 loop
                    check_value(LinkStat(e).DataSending, lanes(N_c - 1), error,
                                "Data-sending lanes at " & to_string(e));
                    check_value(LinkStat(e).DataReceiving, lanes(N_c - 1), error,
                                "Data-receiving lanes at " & to_string(e));
                    check_value(LinkStat(e).LastAlign(N_c-1), x"0000" & SymAlign_c & K28_7_c, error,
                                "ALIGN of the hot redundant lane at " & to_string(e));
                end loop;

                traffic(30, "Traffic with a hot redundant lane");
                checkClean("Hot redundant lane");

            -- TC-ML-34: lane failure and reconnection
            elsif run("test_lane_failure") then
                if N_c = 4 then
                    -- Three data-sending lanes and one hot redundant lane
                    LinkCfg(0).MaxDataLanes <= "011";
                    LinkCfg(1).MaxDataLanes <= "011";
                end if;
                startLink;
                traffic(10, "Traffic before the failure");
                checkOff;
                txTraffic(0, N_c, 20);
                txTraffic(1, N_c, 20);
                cycles(300);
                cutLane(1, true);
                cycles(2000);
                waitAlign(AlignNearEndReady_c, "alignment without lane 1");
                checkOn;
                toBothEnds("Both-Ends Ready without lane 1");
                if N_c = 4 then
                    check_value(LinkStat(0).DataSending, "1101", error, "Hot redundant lane 3 promoted");
                else
                    check_value(LinkStat(0).DataSending, "0001", error, "Lane 0 sends alone");
                end if;
                check_value(LinkStat(1).RxErrs > 0, error, "RXERR passed after the failure");
                traffic(20, "Traffic without lane 1");
                checkClean("Without lane 1");
                -- Reconnection: lane 1 joins again
                checkOff;
                cutLane(1, false);
                cycles(100);

                while LinkStat(0).LaneActive(1) = '0' or LinkStat(1).LaneActive(1) = '0' loop
                    cycles(10);
                end loop;

                waitAlign(AlignNearEndReady_c, "alignment with lane 1");
                checkOn;
                toBothEnds("Both-Ends Ready with lane 1");
                if N_c = 4 then
                    check_value(LinkStat(0).DataSending, "0111", error, "Lane 3 hot redundant again");
                else
                    check_value(LinkStat(0).DataSending, "0011", error, "Both lanes send");
                end if;
                traffic(20, "Traffic after the reconnection");
                checkClean("After the reconnection");

            -- TC-ML-35: asymmetric link with a unidirectional lane
            elsif run("test_asymmetric") then
                -- A: lane 1 transmit only; B: lane 1 receive only; lanes 2 and 3 disabled
                LinkCfg(0).RxEn <= "0001";
                LinkCfg(0).TxEn <= "0011";
                LinkCfg(1).RxEn <= "0011";
                LinkCfg(1).TxEn <= "0001";
                startLink;
                check_value(LinkStat(0).TxOnly(1), '1', error, "TxOnly of lane 1 at A");
                check_value(LinkStat(1).RxOnly(1), '1', error, "RxOnly of lane 1 at B");
                check_value(LinkStat(0).FarEndActive(1), '1', error, "FarEndActive of lane 1 at A");
                check_value(LinkStat(0).LaneActive(1) and LinkStat(1).LaneActive(1), '1', error, "Lane 1 active");
                check_value(LinkStat(0).DataSending(1 downto 0), "11", error, "A sends on two lanes");
                check_value(LinkStat(1).DataReceiving(1 downto 0), "11", error, "B receives on two lanes");
                check_value(LinkStat(1).DataSending(1 downto 0), "01", error, "B sends on lane 0");
                check_value(LinkStat(0).DataReceiving(1 downto 0), "01", error, "A receives on lane 0");
                if N_c = 4 then
                    check_value(LinkStat(0).LaneReset(3 downto 2), "11", error, "Disabled lanes held in reset");
                    check_value(LinkStat(0).LaneActive(3 downto 2), "00", error, "Disabled lanes not active");
                end if;
                traffic(20, "Traffic over the asymmetric link");
                checkClean("Asymmetric link");
                -- The receive-only lane fails: the transmit-only lane is reset (FarEndActive cleared)
                checkOff;
                PaCtrl(1).AtoB.Cut <= true;
                cycles(3000);
                check_value(LinkStat(0).ResetSeen(1), '1', error, "LaneReset of the TxOnly lane at A");
                PaCtrl(1).AtoB.Cut <= false;

                while LinkStat(0).LaneActive(1) = '0' or LinkStat(1).LaneActive(1) = '0' loop
                    cycles(10);
                end loop;

                waitAlign(AlignNearEndReady_c, "alignment after the RxOnly lane restarted");
                checkOn;
                toBothEnds("Both-Ends Ready after the restart");
                traffic(10, "Traffic after the restart");
                checkClean("After the restart");

            -- TC-ML-36: bypass, selected locally and by the far end
            elsif run("test_bypass") then
                LinkCfg(0).Bypass    <= '1';
                LinkCfg(1).Bypass    <= '1';
                LinkCfg(0).LaneStart <= AllLanes_c;
                LinkCfg(1).LaneStart <= AllLanes_c;
                waitAlign(AlignBothEndsReady_c, "Bypass active");
                cycles(100);

                for e in 0 to 1 loop
                    check_value(LinkStat(e).Bypass, '1', error, "Bypass at " & to_string(e));
                    check_value(LinkStat(e).NearCap0(CapMultiLane_c), '0', error, "Multi-LaneCapable clear");
                    check_value(LinkStat(e).LaneActive(N_c-1 downto 1) = std_logic_vector(to_unsigned(0, N_c-1)),
                                error, "Lanes other than 0 not active at " & to_string(e));
                    check_value(LinkStat(e).DataSending, "0001", error, "Lane 0 data-sending at " & to_string(e));
                end loop;

                traffic(20, "Traffic in bypass");
                checkClean("Bypass");
                check_value(LinkStat(0).NrActive + LinkStat(0).NrAlign + LinkStat(0).NerAlign, 0, error,
                            "No ACTIVE or ALIGN in bypass");
                -- Bypass at B only: A selects the bypass from the capability of lane 0
                LinkCfg(0).Bypass    <= '0';
                LinkCfg(0).LaneReset <= '1';
                LinkCfg(1).LaneReset <= '1';
                cycles(2);
                LinkCfg(0).LaneReset <= '0';
                LinkCfg(1).LaneReset <= '0';
                cycles(100);
                waitAlign(AlignBothEndsReady_c, "Bypass selected by the far end");
                cycles(100);
                check_value(LinkStat(0).Bypass, '1', error, "A in bypass from the far-end capability");
                check_value(LinkStat(0).NearCap0(CapMultiLane_c), '1', error, "A is Multi-Lane capable");
                traffic(20, "Traffic with the bypass of the far end");
                checkClean("Bypass of the far end");

            -- TC-ML-37: RXERR rows
            elsif run("test_rxerr_rows") then
                startLink;
                -- Bit error in Both-Ends Ready during traffic: RXERR or CRC error, no Misaligned
                checkOff;
                Num_v                := LinkStat(1).Misaligned;
                txTraffic(0, N_c, 10, 400);
                cycles(300);
                PaCtrl(0).AtoB.Flips <= 1;
                waitSent("Traffic with a bit error");
                check_value(LinkStat(1).AnyErrs > 0, error, "Bit error detected at B");
                check_value(LinkStat(1).Misaligned, Num_v, error, "No Misaligned condition at B");
                check_value(LinkStat(1).AlignState, AlignBothEndsReady_c, error, "B stays in Both-Ends Ready");
                checkOn;
                traffic(10, "Traffic after the bit error");
                -- Bit error within 4 us of entering Near-End Ready at B: Misaligned
                checkOff;
                LinkCfg(0).LinkReset <= '1';
                cycles(1);
                LinkCfg(0).LinkReset <= '0';
                Num_v                := LinkStat(1).Misaligned;

                while LinkStat(1).AlignState /= AlignNearEndReady_c loop
                    cycles(1);
                end loop;

                PaCtrl(0).AtoB.Flips <= 2;
                cycles(500);
                check_value(LinkStat(1).Misaligned > Num_v, error, "Misaligned at B: RXERR within 4 us");
                waitAlign(AlignNearEndReady_c, "alignment after the early RXERR");
                checkOn;
                toBothEnds("Both-Ends Ready after the early RXERR");
                traffic(10, "Traffic after the early RXERR");
                check_value(LinkStat(0).CheckErrs + LinkStat(1).CheckErrs, 0, error, "No mismatch afterwards");

            -- TC-ML-38: link reset during traffic
            elsif run("test_link_reset") then
                startLink;
                checkOff;
                txTraffic(0, N_c, 20);
                txTraffic(1, N_c, 20);
                cycles(500);
                LinkCfg(0).LinkReset <= '1';
                cycles(1);
                LinkCfg(0).LinkReset <= '0';
                cycles(10);
                check_value(LinkStat(0).AlignState, AlignNotReady_c, error, "Not Ready after the link reset");
                cycles(2000);
                waitAlign(AlignNearEndReady_c, "alignment after the link reset");
                checkOn;
                toBothEnds("Both-Ends Ready after the link reset");
                traffic(20, "Traffic after the link reset");
                checkClean("After the link reset");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 20 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_ml_link_th
        generic map (
            NumLanes_g => N_c
        )
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
