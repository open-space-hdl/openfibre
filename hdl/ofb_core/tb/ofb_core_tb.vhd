---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Core testbench: two OpenFibre cores with all clock domains, configured and monitored through the
-- MIB, exchange packets and broadcast messages through the behavioural Physical adapter model.
--
-- Documentation: hdl/ofb_core/docs/verification_plan.md

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

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_pa_pkg.all;
    use work.ofb_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_tb is
    generic (
        runner_cfg : string;
        NumLanes_g : positive range 1 to 4 := 1
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_core_tb is

    signal MgmtClk : std_logic;
    signal Rst     : std_logic;

    -- Register addresses
    constant RegId_c        : natural := 16#000#;
    constant RegDlCtrl_c    : natural := 16#008#;
    constant RegDlStatus_c  : natural := 16#010#;
    constant RegDlErrors_c  : natural := 16#014#;
    constant RegRetries_c   : natural := 16#018#;
    constant RegFrameErr_c  : natural := 16#03C#;
    constant RegLaneCtrl_c  : natural := 16#100#;
    constant RegLaneStat_c  : natural := 16#104#;
    constant RegMlStatus_c  : natural := 16#040#;
    constant RegMlCtrl_c    : natural := 16#058#;
    constant RegMlMisal_c   : natural := 16#05C#;
    constant RegEccStatus_c : natural := 16#060#;
    constant RegEccSelect_c : natural := 16#064#;
    constant RegEccCount_c  : natural := 16#068#;
    constant RegEccInject_c : natural := 16#06C#;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Data_v : std_logic_vector(31 downto 0);

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(MgmtClk);
            end loop;

        end procedure;

        procedure wr (
            core : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, AxiA_c + core, to_unsigned(addr, 12), data, "Write");
            await_completion(AXILITE_VVCT, AxiA_c + core, 10 us);
        end procedure;

        procedure rd (
            core :     natural;
            addr :     natural;
            data : out std_logic_vector(31 downto 0)) is
            variable Cmd_v    : natural;
            variable Result_v : bitvis_vip_axilite.vvc_cmd_pkg.t_vvc_result;
        begin
            axilite_read(AXILITE_VVCT, AxiA_c + core, to_unsigned(addr, 12), "Read");
            Cmd_v := get_last_received_cmd_idx(AXILITE_VVCT, AxiA_c + core);
            await_completion(AXILITE_VVCT, AxiA_c + core, 10 us);
            fetch_result(AXILITE_VVCT, AxiA_c + core, Cmd_v, Result_v, "Fetch");
            data  := Result_v(31 downto 0);
        end procedure;

        -- Start the link: LaneStart at A, AutoStart at both, wait for Link Initialised at both
        procedure linkUp (timeout : time) is
            variable Start_v : time;
            variable A_v     : std_logic_vector(31 downto 0);
            variable B_v     : std_logic_vector(31 downto 0);
        begin

            for l in 0 to NumLanes_g-1 loop
                wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
            end loop;

            Start_v := now;

            loop
                rd(0, RegDlStatus_c, A_v);
                rd(1, RegDlStatus_c, B_v);
                exit when A_v(1 downto 0) = "11" and B_v(1 downto 0) = "11" and A_v(8) = '1' and B_v(8) = '1';
                cycles(200);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for the link");
                    exit;
                end if;
            end loop;

            rd(0, RegLaneStat_c, A_v);
            check_value(A_v(3 downto 0), x"7", error, "Lane of A active");
        end procedure;

        procedure waitDelivered (timeout : time) is
            variable Start_v   : time;
            variable Pending_v : natural;
        begin
            cycles(20);
            Start_v := now;

            loop
                Pending_v := 0;

                for inst in 1 to 2 * CoreNumVc_c + 2 loop
                    Pending_v := Pending_v + CoreSb_v.get_pending_count(inst);
                end loop;

                exit when Pending_v = 0;
                cycles(50);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for delivery, " & to_string(Pending_v) & " elements pending");
                    exit;
                end if;
            end loop;

        end procedure;

        procedure sendAll (n : natural) is
        begin

            for c in 0 to 1 loop

                for vc in 0 to CoreNumVc_c-1 loop
                    CoreCfg(c).Vc(vc).Packets <= CoreCfg(c).Vc(vc).Packets + n;
                end loop;

            end loop;

            cycles(1);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        CoreSb_v.set_scope("CORE_SB");

        for inst in 1 to 2 * CoreNumVc_c + 2 loop
            CoreSb_v.enable(inst);
            CoreSb_v.disable_log_msg(inst, ID_DATA);
        end loop;

        wait until Rst = '0';
        cycles(50);

        while test_suite loop

            -- TC-CORE-01: identification, link start through the MIB
            if run("test_link_up") then
                rd(0, RegId_c, Data_v);
                check_value(Data_v, x"0FB10004", error, "ID of A");
                linkUp(500 us);
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error at B");

            -- TC-CORE-02: packets on all VCs and broadcast messages in both directions
            elsif run("test_traffic") then
                linkUp(500 us);

                for c in 0 to 1 loop

                    for vc in 0 to CoreNumVc_c-1 loop
                        CoreCfg(c).Vc(vc).MaxLen   <= 200;
                        CoreCfg(c).Vc(vc).ReadyPct <= 70;
                    end loop;

                end loop;

                CoreCfg(0).BcSend <= 10;
                CoreCfg(1).BcSend <= 10;
                sendAll(15);
                waitDelivered(5 ms);

                for c in 0 to 1 loop
                    rd(c, RegDlErrors_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No error at core " & to_string(c));
                    rd(c, RegRetries_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No retry at core " & to_string(c));
                end loop;

            -- TC-CORE-03: error recovery after bit errors, counted in the MIB
            elsif run("test_error_recovery") then
                linkUp(500 us);
                sendAll(20);

                for i in 1 to 20 loop
                    cycles(100);
                    PaCtrl(0).AtoB.Flips <= PaCtrl(0).AtoB.Flips + 1;
                    cycles(37);
                    PaCtrl(0).BtoA.Flips <= PaCtrl(0).BtoA.Flips + 1;
                end loop;

                waitDelivered(5 ms);
                rd(0, RegRetries_c, Data_v);
                check_value(unsigned(Data_v) > 0, error, "Retries counted at A");
                rd(1, RegRetries_c, Data_v);
                check_value(unsigned(Data_v) > 0, error, "Retries counted at B");
                rd(0, RegDlStatus_c, Data_v);
                check_value(Data_v(1 downto 0), "11", error, "No link reset at A");

            -- TC-CORE-04: Link Reset through the MIB resets both ends
            elsif run("test_link_reset") then
                linkUp(500 us);
                wr(0, RegDlCtrl_c, x"00000101");
                cycles(100);
                linkUp(500 us);
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v(5), '1', error, "Far-End Link Reset at B");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(5), '0', error, "No Far-End Link Reset at A");
                sendAll(5);
                waitDelivered(2 ms);

            -- TC-CORE-06: quality of service configuration through the MIB reaches the Data Link layer:
            -- a VC with bandwidth zero does not send until its bandwidth is set
            elsif run("test_qos_config") then
                linkUp(500 us);
                wr(0, 16#434#, x"00000000");
                rd(0, 16#434#, Data_v);
                check_value(Data_v, x"00000000", error, "Bandwidth of VC 3 at A read back");
                CoreCfg(0).Vc(3).Packets <= 3;
                cycles(2000);
                check_value(CoreSb_v.get_pending_count(1 + CoreNumVc_c + 3) > 0, error, "VC 3 of A blocked");
                wr(0, 16#434#, x"00000100");
                waitDelivered(1 ms);

            -- TC-CORE-07: a lane fails during traffic and is reconnected: every packet is delivered
            -- (realignment of the Multi-Lane layer, error recovery of the Data Link layer)
            elsif run("test_lane_failure") then
                linkUp(500 us);
                if NumLanes_g > 1 then
                    sendAll(40);
                    cycles(300);
                    PaCtrl(NumLanes_g-1).AtoB.Cut <= true;
                    PaCtrl(NumLanes_g-1).BtoA.Cut <= true;
                    cycles(3000);
                    rd(1, RegMlStatus_c, Data_v);
                    check_value(Data_v(NumLanes_g-1), '0', error, "Failed lane not data-sending at B");
                    PaCtrl(NumLanes_g-1).AtoB.Cut <= false;
                    PaCtrl(NumLanes_g-1).BtoA.Cut <= false;
                    waitDelivered(10 ms);
                    rd(0, RegMlMisal_c, Data_v);
                    check_value(unsigned(Data_v) > 0, error, "Misaligned condition counted at A");
                    rd(0, RegDlStatus_c, Data_v);
                    check_value(Data_v(1 downto 0), "11", error, "No link reset at A");
                    -- The lane joins again
                    cycles(5000);
                    rd(0, RegMlStatus_c, Data_v);
                    check_value(Data_v(NumLanes_g-1 downto 0), std_logic_vector(to_unsigned(2 ** NumLanes_g - 1, NumLanes_g)),
                                error, "All lanes data-sending again at A");
                    check_value(Data_v(9 downto 8), "10", error, "Both-Ends Ready at A");
                    sendAll(5);
                    waitDelivered(5 ms);
                end if;

            -- TC-CORE-08: maximum number of data-sending lanes through the MIB, taken over at link reset
            elsif run("test_max_data_lanes") then

                for c in 0 to 1 loop
                    wr(c, RegMlCtrl_c, x"00000001");
                    wr(c, RegDlCtrl_c, x"00000101");
                end loop;

                linkUp(500 us);
                cycles(2000);
                rd(0, RegMlStatus_c, Data_v);
                check_value(Data_v(3 downto 0), "0001", error, "One data-sending lane at A");
                rd(1, RegMlStatus_c, Data_v);
                check_value(Data_v(7 downto 4), "0001", error, "One data-receiving lane at B");

                for c in 0 to 1 loop

                    for vc in 0 to CoreNumVc_c-1 loop
                        CoreCfg(c).Vc(vc).MaxLen <= 300;
                    end loop;

                end loop;

                sendAll(10);
                waitDelivered(5 ms);
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error at A");

            -- TC-CORE-09: Multi-Lane bypass through the MIB
            elsif run("test_bypass") then

                for c in 0 to 1 loop
                    wr(c, RegMlCtrl_c, x"00000100");
                end loop;

                linkUp(500 us);
                cycles(2000);
                rd(0, RegMlStatus_c, Data_v);
                check_value(Data_v(10), '1', error, "Bypass at A");
                check_value(Data_v(9 downto 8), "10", error, "Both-Ends Ready reported in bypass");
                check_value(Data_v(3 downto 0), "0001", error, "Lane 0 data-sending in bypass");
                sendAll(10);
                waitDelivered(5 ms);
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error at B");

            -- TC-CORE-10: single errors injected through the MIB into every EDAC channel of A are
            -- corrected and counted per channel; the traffic is not affected
            elsif run("test_ecc_injection") then
                linkUp(500 us);

                for ch in 0 to EccChannels_c-1 loop
                    wr(0, RegEccInject_c, std_logic_vector(to_unsigned(ch, 32)));
                end loop;

                -- Traffic in both directions, broadcast messages, a QoS write at A
                CoreCfg(0).BcSend <= 3;
                CoreCfg(1).BcSend <= 3;
                sendAll(5);
                wr(0, 16#434#, x"0000FFFF");
                waitDelivered(5 ms);
                rd(0, RegEccStatus_c, Data_v);
                check_value(Data_v(EccChannels_c-1 downto 0), std_logic_vector(to_unsigned(0, EccChannels_c)), error,
                            "No uncorrectable error at A");
                check_value(Data_v(16), '1', error, "Corrected errors seen at A");

                for ch in 0 to EccChannels_c-1 loop
                    wr(0, RegEccSelect_c, std_logic_vector(to_unsigned(ch, 32)));
                    rd(0, RegEccCount_c, Data_v);
                    check_value(unsigned(Data_v(15 downto 0)) > 0, error, "Corrected error of channel " & to_string(ch));
                    check_value(Data_v(31 downto 16), x"0000", error, "No DED in channel " & to_string(ch));
                end loop;

            -- TC-CORE-05: framing error at the Network interface of A
            elsif run("test_framing_error") then
                linkUp(500 us);
                -- Word with K28.7 in a packet: EEP, the rest of the packet up to the EOP is discarded
                RawQueue_v.push('0' & "0010" & x"5A5A" & K28_7_c & x"11");
                RawQueue_v.push('0' & "0000" & x"22334455");
                RawQueue_v.push('0' & "1000" & CharEop_c & x"667788");
                CoreSb_v.add_expected(1 + CoreNumVc_c, "1110" & CharFill_c & CharFill_c & CharEep_c & x"11");
                waitDelivered(1 ms);
                rd(0, RegFrameErr_c, Data_v);
                check_value(Data_v(0), '1', error, "Framing error of VC 0 at A");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(9), '1', error, "Framing error flag at A");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 20 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_core_th
        generic map (
            NumLanes_g => NumLanes_g
        )
        port map (
            MgmtClk => MgmtClk,
            Rst     => Rst
        );

end architecture;
