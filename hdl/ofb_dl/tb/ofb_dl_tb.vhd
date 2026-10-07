---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Layer testbench of the Data Link layer: two ends with Multi-Lane and Lane layers through the
-- behavioural Physical adapter model; link initialisation, packet and broadcast traffic, flow
-- control, error recovery, loss of the lane and link reset.
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

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_pa_pkg.all;
    use work.ofb_dl_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_dl_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

    constant AllVc_c : std_logic_vector(TbNumVc_c-1 downto 0) := (others => '1');

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Start_v : time;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Wait until both ends are in Link Initialised with an active lane and credit on all VCs
        procedure waitLinkUp (timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;

            while not (DlStat(0).LinkState = "11" and DlStat(1).LinkState = "11" and DlStat(0).LaneActive = '1' and
                       DlStat(1).LaneActive = '1' and DlStat(0).HasCredit = AllVc_c and
                       DlStat(1).HasCredit = AllVc_c) loop
                cycles(10);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for the link to come up");
                    exit;
                end if;
            end loop;

        end procedure;

        -- Request packets on one VC of one end
        procedure sendPackets (
            src : natural;
            vc  : natural;
            n   : natural) is
        begin
            DlCfg(src).Vc(vc).Packets <= DlCfg(src).Vc(vc).Packets + n;
            cycles(1);
        end procedure;

        -- Wait until every expected word and broadcast message has been received
        procedure waitDelivered (timeout : time) is
            variable Start_v   : time;
            variable Pending_v : natural;
        begin
            -- Let the generators start on the requests made just before
            cycles(20);
            Start_v := now;

            loop
                Pending_v := 0;

                for inst in 1 to 2 * TbNumVc_c + 2 loop
                    Pending_v := Pending_v + Sb_v.get_pending_count(inst);
                end loop;

                exit when Pending_v = 0;
                cycles(50);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for delivery, " & to_string(Pending_v) & " elements pending");
                    exit;
                end if;
            end loop;

        end procedure;

        -- Wait until one scoreboard instance has received everything expected
        procedure waitPending (
            inst    : positive;
            timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;

            while Sb_v.get_pending_count(inst) /= 0 loop
                cycles(50);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for scoreboard instance " & to_string(inst));
                    exit;
                end if;
            end loop;

        end procedure;

        -- Wait until both error recovery buffers are empty
        procedure waitErbEmpty (timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;

            while DlStat(0).ErbEmpty /= '1' or DlStat(1).ErbEmpty /= '1' loop
                cycles(10);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for empty error recovery buffers");
                    exit;
                end if;
            end loop;

        end procedure;

        -- Report the error and recovery counters
        procedure logStat (msg : string) is
        begin

            for e in 0 to 1 loop
                log(ID_LOG_HDR, msg & ", end " & to_string(e) & ": retries " & to_string(DlStat(e).Retries) &
                    ", CRC-16 " & to_string(DlStat(e).Crc16Errs) & ", CRC-8 " & to_string(DlStat(e).Crc8Errs) &
                    ", frame " & to_string(DlStat(e).FrameErrs) & ", sequence " & to_string(DlStat(e).SeqErrs) &
                    ", broadcasts " & to_string(DlStat(e).BcRx) & " (late " & to_string(DlStat(e).BcRxLate) & ")");
            end loop;

        end procedure;

        procedure checkNoErrors (msg : string) is
        begin

            for e in 0 to 1 loop
                check_value(DlStat(e).Crc16Errs, 0, error, msg & ": CRC-16 errors at end " & to_string(e));
                check_value(DlStat(e).Crc8Errs, 0, error, msg & ": CRC-8 errors at end " & to_string(e));
                check_value(DlStat(e).FrameErrs, 0, error, msg & ": frame errors at end " & to_string(e));
                check_value(DlStat(e).SeqErrs, 0, error, msg & ": sequence errors at end " & to_string(e));
                check_value(DlStat(e).Retries, 0, error, msg & ": retries at end " & to_string(e));
                check_value(DlStat(e).ProtErrs, 0, error, msg & ": protocol errors at end " & to_string(e));
                check_value(DlStat(e).Overflows, 0, error, msg & ": input overflows at end " & to_string(e));
            end loop;

        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        Sb_v.set_scope("DL_SB");

        for inst in 1 to 2 * TbNumVc_c + 2 loop
            Sb_v.enable(inst);
            Sb_v.disable_log_msg(inst, ID_DATA);
        end loop;

        wait until Rst = '0';
        cycles(2);

        while test_suite loop

            -- TC-DL-01: link initialisation, FCT exchange, empty error recovery buffers
            if run("test_link_init") then
                waitLinkUp(200 us);
                waitErbEmpty(50 us);
                checkNoErrors("Link initialisation");
                check_value(DlStat(0).FarEndResets + DlStat(1).FarEndResets, 0, error, "No far-end link reset");

            -- TC-DL-02: packets on all VCs in both directions
            elsif run("test_vc_traffic") then
                waitLinkUp(200 us);

                for e in 0 to 1 loop

                    for vc in 0 to TbNumVc_c-1 loop
                        DlCfg(e).Vc(vc).MaxLen   <= 300;
                        DlCfg(e).Vc(vc).EepPct   <= 10;
                        DlCfg(e).Vc(vc).GapPct   <= 20;
                        DlCfg(e).Vc(vc).ReadyPct <= 80;
                    end loop;

                end loop;

                cycles(1);

                for e in 0 to 1 loop

                    for vc in 0 to TbNumVc_c-1 loop
                        sendPackets(e, vc, 30);
                    end loop;

                end loop;

                waitDelivered(5 ms);
                waitErbEmpty(100 us);
                checkNoErrors("VC traffic");
                check_value(Sb_v.get_entered_count(sbVc(1, 0)) > 0, error, "Words were sent");

            -- TC-DL-03: broadcast messages, broadcast bandwidth credit
            elsif run("test_broadcast") then
                waitLinkUp(200 us);
                DlCfg(0).BcSend <= 20;
                DlCfg(1).BcSend <= 20;
                sendPackets(0, 1, 10);
                sendPackets(1, 2, 10);
                waitDelivered(2 ms);
                check_value(DlStat(0).BcRx, 20, error, "Broadcasts received at A");
                check_value(DlStat(1).BcRx, 20, error, "Broadcasts received at B");
                check_value(DlStat(0).BcRxLate + DlStat(1).BcRxLate, 0, error, "No LATE flag");
                waitErbEmpty(100 us);
                checkNoErrors("Broadcast");
                -- Slow broadcast credit: one broadcast per 2000 words (12.8 us)
                DlCfg(0).BcInterval <= x"07D0";
                cycles(1);
                DlCfg(0).LinkReset  <= '1';
                cycles(1);
                DlCfg(0).LinkReset  <= '0';
                cycles(100);
                waitLinkUp(200 us);
                Start_v             := now;
                DlCfg(0).BcSend     <= 23;
                waitDelivered(2 ms);
                check_value(DlStat(1).BcRx, 23, error, "Broadcasts received at B");
                check_value(now - Start_v > 2 * 12.8 us, error, "Broadcasts limited by the broadcast credit");

            -- TC-DL-04: flow control: a receiver that does not read stops its VC only
            elsif run("test_flow_control") then
                waitLinkUp(200 us);
                DlCfg(1).Vc(0).ReadyPct <= 0;
                DlCfg(0).Vc(0).MaxLen   <= 300;
                cycles(1);
                sendPackets(0, 0, 20);
                cycles(20000);
                check_value(Sb_v.get_pending_count(sbVc(1, 0)) > 0, error, "VC 0 blocked by the receiver");
                check_value(DlStat(0).HasCredit(0), '0', error, "No credit left on VC 0");
                sendPackets(0, 1, 10);
                waitPending(sbVc(1, 1), 1 ms);
                DlCfg(1).Vc(0).ReadyPct <= 100;
                waitDelivered(2 ms);
                waitErbEmpty(100 us);
                checkNoErrors("Flow control");

            -- TC-DL-05: error recovery after bit errors in both directions
            elsif run("test_error_recovery") then
                waitLinkUp(200 us);

                for e in 0 to 1 loop

                    for vc in 0 to TbNumVc_c-1 loop
                        DlCfg(e).Vc(vc).MaxLen <= 200;
                        DlCfg(e).Vc(vc).EepPct <= 5;
                    end loop;

                end loop;

                cycles(1);

                for e in 0 to 1 loop

                    for vc in 0 to TbNumVc_c-1 loop
                        sendPackets(e, vc, 25);
                    end loop;

                end loop;

                DlCfg(0).BcSend <= 10;
                DlCfg(1).BcSend <= 10;

                for i in 1 to 30 loop
                    cycles(300);
                    PaCtrl(0).AtoB.Flips <= PaCtrl(0).AtoB.Flips + 1;
                    cycles(137);
                    PaCtrl(0).BtoA.Flips <= PaCtrl(0).BtoA.Flips + 1;
                end loop;

                waitDelivered(5 ms);
                waitErbEmpty(200 us);
                logStat("Error recovery");
                check_value(DlStat(0).Retries > 0, error, "Error recovery at A");
                check_value(DlStat(1).Retries > 0, error, "Error recovery at B");
                check_value(DlStat(0).ProtErrs + DlStat(1).ProtErrs, 0, error, "No protocol error");
                check_value(DlStat(0).Overflows + DlStat(1).Overflows, 0, error, "No input buffer overflow");
                check_value(DlStat(0).LinkState & DlStat(1).LinkState, "1111", error, "No link reset");

            -- TC-DL-06: loss of the lane during traffic, recovery without link reset
            elsif run("test_lane_loss") then
                waitLinkUp(200 us);

                for e in 0 to 1 loop

                    for vc in 0 to TbNumVc_c-1 loop
                        DlCfg(e).Vc(vc).MaxLen <= 300;
                    end loop;

                end loop;

                cycles(1);

                for vc in 0 to TbNumVc_c-1 loop
                    sendPackets(0, vc, 30);
                    sendPackets(1, vc, 30);
                end loop;

                cycles(1000);
                PaCtrl(0).AtoB.Cut <= true;
                Start_v            := now;

                -- Broadcast messages submitted while the lane of the sending end is not active wait and are sent
                -- with the LATE flag (DL-BO-03)
                for k in 0 to 4000 loop
                    exit when DlStat(0).LaneActive = '0' and DlStat(1).LaneActive = '0';
                    cycles(1);
                end loop;

                check_value(DlStat(0).LaneActive = '0' and DlStat(1).LaneActive = '0', error, "Lanes not active during the cut");
                DlCfg(0).BcSend    <= 2;
                DlCfg(1).BcSend    <= 2;
                wait for 5 us - (now - Start_v);
                PaCtrl(0).AtoB.Cut <= false;
                waitDelivered(5 ms);
                waitErbEmpty(200 us);
                logStat("Lane loss");
                check_value(DlStat(0).BcRx, 2, error, "Broadcasts received at A");
                check_value(DlStat(1).BcRx, 2, error, "Broadcasts received at B");
                check_value(DlStat(0).BcRxLate, 2, error, "Broadcasts received at A with LATE");
                check_value(DlStat(1).BcRxLate, 2, error, "Broadcasts received at B with LATE");
                check_value(DlStat(0).Retries + DlStat(1).Retries > 0, error, "Error recovery after the loss");
                check_value(DlStat(0).ProtErrs + DlStat(1).ProtErrs, 0, error, "No protocol error");
                check_value(DlStat(0).FarEndResets + DlStat(1).FarEndResets, 0, error, "No link reset");

            -- TC-DL-07: link reset command at one end resets both ends
            elsif run("test_link_reset") then
                waitLinkUp(200 us);
                sendPackets(0, 0, 5);
                waitDelivered(1 ms);
                DlCfg(0).LinkReset <= '1';
                cycles(1);
                DlCfg(0).LinkReset <= '0';
                cycles(100);
                check_value(DlStat(0).LinkState /= "11", error, "Near end left Link Initialised");
                waitLinkUp(500 us);
                check_value(DlStat(1).FarEndResets, 1, error, "Far-end link reset at B");
                check_value(DlStat(0).FarEndResets, 0, error, "No far-end link reset at A");
                sendPackets(0, 0, 5);
                sendPackets(1, 3, 5);
                waitDelivered(1 ms);
                waitErbEmpty(100 us);
                checkNoErrors("After link reset");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 20 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_dl_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
