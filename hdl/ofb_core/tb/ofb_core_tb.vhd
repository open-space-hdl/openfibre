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
    use ieee.math_real.all;

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
    use work.ofb_regs_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_pa_pkg.all;
    use work.ofb_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_tb is
    generic (
        runner_cfg      : string;
        NumLanes_g      : positive range 1 to 4  := 1;
        NumVc_g         : positive range 1 to 32 := 4;
        Seed_g          : positive               := 1;    -- Seed of the fault injection campaign
        CoreHalfPs_g    : positive               := 3000; -- Half period of CoreClk in ps
        LaneHalfPs_g    : positive               := 3200; -- Half period of LaneClk in ps
        VcOutDepth_g    : positive               := 128;
        VcInDepth_g     : natural                := 0;    -- 0: 256 x NumLanes_g words
        ErbRows_g       : positive               := 512;
        InitPrbsWords_g : natural range 0 to 64  := 64
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_core_tb is

    signal MgmtClk : std_logic;
    signal Rst     : std_logic;

    -- Payload capacity of one lane in Gbit/s: 32 bits per LaneClk cycle
    constant LaneGbps_c : real := 32.0 / (2.0e-3 * real(LaneHalfPs_g));

    -- Largest Space Packet (CCSDS 133.0-B-2: 6 header bytes and 65536 data bytes), TC-CORE-20
    constant LongPacket_c : positive := 65542;

    -- Register addresses
    constant RegId_c        : natural := 16#000#;
    constant RegGenerics_c  : natural := 16#004#;
    constant RegDlCtrl_c    : natural := 16#008#;
    constant RegDlStatus_c  : natural := 16#010#;
    constant RegDlErrors_c  : natural := 16#014#;
    constant RegRetries_c   : natural := 16#018#;
    constant RegFrameErr_c  : natural := 16#03C#;
    constant RegLaneCtrl_c  : natural := 16#100#;
    constant RegLaneStat_c  : natural := 16#104#;
    constant RegMlStatus_c  : natural := 16#040#;
    constant RegTimeSlot_c  : natural := 16#054#;
    constant RegMlCtrl_c    : natural := 16#058#;
    constant RegMlMisal_c   : natural := 16#05C#;
    constant RegEccStatus_c : natural := 16#060#;
    constant RegEccSelect_c : natural := 16#064#;
    constant RegEccCount_c  : natural := 16#068#;
    constant RegEccInject_c : natural := 16#06C#;

    -- Fault injection campaign (TC-CORE-13): number of faults, fault kinds
    constant CampaignFaults_c : positive := 40;
    constant FaultFlip_c      : natural  := 0; -- Single bit error on a line
    constant FaultBurst_c     : natural  := 1; -- Bit errors in 2 to 8 consecutive symbols
    constant FaultSlip_c      : natural  := 2; -- Word slip: the skew of a line changes by one word
    constant FaultSec_c       : natural  := 3; -- Single error in a random EDAC channel
    constant FaultDed_c       : natural  := 4; -- Double error in a row crossing
    constant FaultCut_c       : natural  := 5; -- Lane cut and reconnected (several lanes), else bit error

    -- TKEEP of a full beat
    constant AllKeep_c : std_logic_vector(4*NumLanes_g-1 downto 0) := (others => '1');

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Data_v : std_logic_vector(31 downto 0);

        -- Fault injection campaign
        type CoreEcc_t is array (0 to 1) of std_logic_vector(EccChannels_c-1 downto 0);
        type FaultCount_t is array (FaultFlip_c to FaultCut_c) of natural;

        variable Seed1_v  : positive;
        variable Seed2_v  : positive;
        variable Sec_v    : CoreEcc_t;
        variable Ded_v    : CoreEcc_t;
        variable Faults_v : FaultCount_t;
        variable Kind_v   : natural;
        variable Lane_v   : natural;
        variable Dir_v    : natural;
        variable Core_v   : natural;
        variable Ch_v     : natural;
        variable N_v      : natural;
        variable W0_v     : natural;
        variable T0_v     : time;
        variable Rate_v   : real;
        variable RateB_v  : real;

        -- Functional coverage of the campaign: fault kinds, line faults per lane, single errors per
        -- EDAC channel
        variable CovFault_v : t_coverpoint;
        variable CovLine_v  : t_coverpoint;
        variable CovSec_v   : t_coverpoint;

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

                for inst in 1 to 2 * CoreMaxVc_c + 2 loop
                    Pending_v := Pending_v + CoreSb_v.get_pending_count(inst);
                end loop;

                exit when Pending_v = 0;
                cycles(50);
                if now - Start_v > timeout then

                    for inst in 1 to 2 * CoreMaxVc_c + 2 loop
                        if CoreSb_v.get_pending_count(inst) > 0 then
                            log(ID_LOG_HDR, "Instance " & to_string(inst) & ": " &
                                to_string(CoreSb_v.get_pending_count(inst)) & " elements pending");
                        end if;
                    end loop;

                    alert(error, "Timeout waiting for delivery, " & to_string(Pending_v) & " elements pending");
                    exit;
                end if;
            end loop;

        end procedure;

        procedure sendAll (n : natural) is
        begin

            for c in 0 to 1 loop

                for vc in 0 to NumVc_g-1 loop
                    CoreCfg(c).Vc(vc).Packets <= CoreCfg(c).Vc(vc).Packets + n;
                end loop;

            end loop;

            cycles(1);
        end procedure;

        -- Uniformly distributed integer from lo to hi
        procedure randInt (
            lo :     integer;
            hi :     integer;
            r  : out integer) is
            variable U_v : real;
        begin
            uniform(Seed1_v, Seed2_v, U_v);
            r := minimum(hi, lo + integer(floor(U_v * real(hi - lo + 1))));
        end procedure;

        -- Wait until all lanes send and receive data at both ends (Both-Ends Ready)
        procedure allLanes (timeout : time) is
            constant All_c   : std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
            variable Start_v : time;
            variable A_v     : std_logic_vector(31 downto 0);
            variable B_v     : std_logic_vector(31 downto 0);
        begin
            Start_v := now;

            loop
                rd(0, RegMlStatus_c, A_v);
                rd(1, RegMlStatus_c, B_v);
                exit when A_v(NumLanes_g-1 downto 0) = All_c and A_v(NumLanes_g+3 downto 4) = All_c and
                          B_v(NumLanes_g-1 downto 0) = All_c and B_v(NumLanes_g+3 downto 4) = All_c and
                          A_v(9 downto 8) = "10" and B_v(9 downto 8) = "10";
                cycles(200);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for all lanes at both ends");
                    exit;
                end if;
            end loop;

        end procedure;

        -- DED into the input VC buffers of A (TC-CORE-14): injected with no traffic in flight, it goes into the
        -- next word written into bank 0 of every input VC buffer, a word of the packets that B sends afterwards
        -- (packets of minLen to maxLen bytes per VC; the caller restores the lengths after the delivery)
        procedure dedVcIn (
            minLen  : positive;
            maxLen  : positive;
            packets : positive) is
            variable Status_v : std_logic_vector(31 downto 0);
        begin
            waitDelivered(2 ms);
            wr(0, RegEccInject_c, std_logic_vector(to_unsigned(16#100# + EccChVcIn_c, 32)));

            for vc in 0 to NumVc_g-1 loop
                CoreCfg(1).Vc(vc).MinLen  <= minLen;
                CoreCfg(1).Vc(vc).MaxLen  <= maxLen;
                CoreCfg(1).Vc(vc).Packets <= CoreCfg(1).Vc(vc).Packets + packets;
            end loop;

            cycles(1);

            for k in 0 to 1000 loop
                rd(0, RegEccStatus_c, Status_v);
                exit when Status_v(EccChVcIn_c) = '1';
                cycles(100);
            end loop;

            check_value(Status_v(EccChVcIn_c), '1', error, "DED read in the input VC buffers");
        end procedure;

        -- Raw beat for VC 0 of A with the bytes first, first + 1, ... and the given TKEEP, TLAST and TUSER
        procedure rawBeat (
            first : natural;
            keep  : std_logic_vector;
            last  : std_logic;
            user  : std_logic := '0') is
            variable Beat_v : RawBeat_t := (others => '0');
        begin

            for c in 0 to 4*NumLanes_g-1 loop
                Beat_v(8*c+7 downto 8*c) := std_logic_vector(to_unsigned((first + c) mod 256, 8));
            end loop;

            Beat_v(128+4*NumLanes_g-1 downto 128) := keep;
            Beat_v(144)                           := last;
            Beat_v(145)                           := user;
            RawQueue_v.push(0, Beat_v);
        end procedure;

        -- Expected data words of a full raw beat at the receiver of VC 0 (default: B)
        procedure expBeatWords (
            first : natural;
            inst  : positive := 1 + CoreMaxVc_c) is
            variable Word_v : Word_t;
        begin

            for w in 0 to NumLanes_g-1 loop

                for c in 0 to 3 loop
                    Word_v(8*c+7 downto 8*c) := std_logic_vector(to_unsigned((first + 4 * w + c) mod 256, 8));
                end loop;

                CoreSb_v.add_expected(inst, "0000" & Word_v);
            end loop;

        end procedure;

        -- TKEEP with a gap: bytes 0 and 2
        impure function gapKeep return std_logic_vector is
            variable Keep_v : std_logic_vector(4*NumLanes_g-1 downto 0) := (others => '0');
        begin
            Keep_v(0) := '1';
            Keep_v(2) := '1';
            return Keep_v;
        end function;

        procedure defaultLengths is
        begin

            for vc in 0 to NumVc_g-1 loop
                CoreCfg(1).Vc(vc).MinLen <= CoreVcCfgDefault_c.MinLen;
                CoreCfg(1).Vc(vc).MaxLen <= CoreVcCfgDefault_c.MaxLen;
            end loop;

            cycles(1);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        -- TC-CORE-21, TC-CORE-22: the transmitters of A are not ready from the reset on
        if enabled("test_tx_ready_late") or enabled("test_tx_ready_never") then
            CoreTxReady(0) <= '0';
        end if;
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        CoreSb_v.set_scope("CORE_SB");

        for inst in 1 to 2 * CoreMaxVc_c + 2 loop
            CoreSb_v.enable(inst);
            CoreSb_v.disable_log_msg(inst, ID_DATA);
        end loop;

        coreCovInit(NumVc_g);
        wait until Rst = '0';
        cycles(50);

        while test_suite loop

            -- TC-CORE-01: identification, link start through the MIB
            if run("test_link_up") then
                rd(0, RegGenerics_c, Data_v);
                check_value(to_integer(unsigned(Data_v(7 downto 0))), NumVc_g, error, "NUM_VC of A");
                check_value(to_integer(unsigned(Data_v(11 downto 8))), NumLanes_g, error, "NUM_LANES of A");
                rd(0, RegId_c, Data_v);
                check_value(Data_v, x"0FB10008", error, "ID of A");
                linkUp(500 us);
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error at B");

                for l in 0 to NumLanes_g-1 loop
                    rd(0, RegLaneStat_c + 16#20# * l, Data_v);
                    check_value(Data_v(6), '1', error, "Bit synchronisation of lane " & to_string(l) & " at A");
                end loop;

            -- TC-CORE-02: packets on all VCs and broadcast messages in both directions
            elsif run("test_traffic") then
                linkUp(500 us);

                for c in 0 to 1 loop

                    for vc in 0 to NumVc_g-1 loop
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

            -- TC-CORE-03: error recovery after bit errors, counted in the MIB. The traffic lasts at least as
            -- long as most of the bit errors, so that they hit data frames (with several lanes, a bit error in
            -- an idle word is a lane slip and causes a realignment, no retry)
            elsif run("test_error_recovery") then
                linkUp(500 us);
                sendAll(200);

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

            -- TC-CORE-04: Link Reset through the MIB resets both ends. The lanes of A pass ClearLine,
            -- which lasts 2 us counted in LaneClk cycles of LaneClkFreq_g (ECSS 5.5.2.4)
            elsif run("test_link_reset") then
                linkUp(500 us);
                wr(0, RegDlCtrl_c, x"00000101");
                if CoreLaneOn(0) = '1' then
                    wait until CoreLaneOn(0) = '0' for 10 us;
                end if;
                T0_v := now - CoreLaneOn(0)'last_event;
                wait until CoreLaneOn(0) = '1' for 20 us;
                log(ID_LOG_HDR, "ClearLine of A: " & to_string(now - T0_v));
                check_value(now - T0_v >= 2 us and now - T0_v < 2 us + 40 * LaneHalfPs_g * 1 ps, error,
                            "ClearLine of A lasts 2 us");
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
                check_value(CoreSb_v.get_pending_count(1 + CoreMaxVc_c + 3) > 0, error, "VC 3 of A blocked");
                wr(0, 16#434#, x"00000100");
                waitDelivered(1 ms);
                -- SCHEDULE.request through the Network interface: VC 3 of A excluded from time-slot 5
                wr(0, 16#438#, x"FFFFFFDF");
                CoreCfg(0).Slot          <= 5;
                CoreCfg(0).SchedReq      <= CoreCfg(0).SchedReq + 1;
                cycles(50);
                rd(0, RegTimeSlot_c, Data_v);
                check_value(Data_v(5 downto 0), "000101", error, "Current time-slot 5 at A");
                CoreCfg(0).Vc(3).Packets <= 6;
                cycles(2000);
                check_value(CoreSb_v.get_pending_count(1 + CoreMaxVc_c + 3) > 0, error, "VC 3 of A waits in time-slot 5");
                CoreCfg(0).Slot          <= 0;
                CoreCfg(0).SchedReq      <= CoreCfg(0).SchedReq + 1;
                waitDelivered(1 ms);
                rd(0, RegTimeSlot_c, Data_v);
                check_value(Data_v(5 downto 0), "000000", error, "Current time-slot 0 at A");

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

                    for vc in 0 to NumVc_g-1 loop
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

            -- TC-CORE-05: framing errors at the Network interface of A and the EEP flag of the user
            elsif run("test_framing_error") then
                linkUp(500 us);
                -- Gap in TKEEP in the first beat: the packet is discarded up to TLAST, nothing reaches B (no
                -- packet of zero length)
                rawBeat(16#10#, gapKeep, '0');
                rawBeat(16#20#, AllKeep_c, '1');
                -- Partial TKEEP in the second beat without TLAST: the first beat reaches B, ended with an EEP;
                -- the rest of the packet is discarded
                rawBeat(16#30#, AllKeep_c, '0');
                expBeatWords(16#30#);
                CoreSb_v.add_expected(1 + CoreMaxVc_c, "1111" & CharFill_c & CharFill_c & CharFill_c & CharEep_c);
                rawBeat(16#40#, '0' & AllKeep_c(NumLanes_g*4-2 downto 0), '0');
                rawBeat(16#50#, AllKeep_c, '1');
                -- Packet of three bytes ended with an EEP by the user
                rawBeat(16#60#, (NumLanes_g*4-1 downto 3 => '0') & "111", '1', '1');
                CoreSb_v.add_expected(1 + CoreMaxVc_c, "1000" & CharEep_c & x"626160");
                waitDelivered(1 ms);
                rd(0, RegFrameErr_c, Data_v);
                check_value(Data_v(0), '1', error, "Framing error of VC 0 at A");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(9), '1', error, "Framing error flag at A");
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v(11), '0', error, "No receive framing error at B");
                rd(1, RegNiRxEmptyCount_c, Data_v);
                check_value(Data_v, x"00000000", error, "No packet of zero length at B");

            -- TC-CORE-11, TC-CORE-12: serial loopbacks of the Physical layer (B disabled): near-end at A
            -- (own transmitter to own receiver), far-end at B (B returns the signal of A); the lanes and
            -- the link of A initialise with themselves and a packet of A comes back to A
            elsif run("test_serial_loopback_near") or run("test_serial_loopback_far") then

                for l in 0 to NumLanes_g-1 loop
                    if running_test_case = "test_serial_loopback_far" then
                        wr(1, RegLaneCtrl_c + 16#20# * l, x"00020060");
                        wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
                    else
                        wr(1, RegLaneCtrl_c + 16#20# * l, x"00000060");
                        wr(0, RegLaneCtrl_c + 16#20# * l, x"00010063");
                    end if;
                end loop;

                for i in 0 to 500 loop
                    rd(0, RegDlStatus_c, Data_v);
                    exit when Data_v(1 downto 0) = "11" and Data_v(8) = '1';
                    cycles(200);
                end loop;

                check_value(Data_v(1 downto 0), "11", error, "Link of A initialised with itself");

                for l in 0 to NumLanes_g-1 loop
                    rd(0, RegLaneStat_c + 16#20# * l, Data_v);
                    check_value(Data_v(3 downto 0), x"7", error, "Lane " & to_string(l) & " of A active");
                    rd(1, RegLaneStat_c + 16#20# * l, Data_v);
                    check_value(Data_v(3 downto 0) /= x"7", error, "Lane " & to_string(l) & " of B not active");
                end loop;

                -- A packet of one beat and three bytes on VC 0 of A comes back to VC 0 of A
                rawBeat(16#A1#, AllKeep_c, '0');
                rawBeat(16#B1#, (NumLanes_g*4-1 downto 3 => '0') & "111", '1');
                expBeatWords(16#A1#, 1);
                CoreSb_v.add_expected(1, "1000" & CharEop_c & x"B3B2B1");
                waitDelivered(1 ms);
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error at A");

            -- TC-CORE-13: fault injection campaign: random faults on the lines and in the EDAC-protected
            -- buffers during traffic and broadcast messages in both directions; every packet and message
            -- delivered unchanged and in order, no link reset, the EDAC monitor reports the injected errors
            elsif run("test_fault_campaign") then
                enable_log_msg(ID_SEQUENCER);
                linkUp(500 us);
                Seed1_v  := Seed_g;
                Seed2_v  := 1000 + NumLanes_g;
                Sec_v    := (others => (others => '0'));
                Ded_v    := (others => (others => '0'));
                Faults_v := (others => 0);
                CovFault_v.set_name("CovFault");
                CovFault_v.add_bins(bin_range(FaultFlip_c, FaultDed_c, 0));
                if NumLanes_g > 1 then
                    CovFault_v.add_bins(bin(FaultCut_c));
                end if;
                CovLine_v.set_name("CovLine");
                CovLine_v.add_cross(bin_range(FaultFlip_c, FaultSlip_c, 0) & bin(FaultCut_c), bin_range(0, NumLanes_g-1, 0));
                CovSec_v.set_name("CovSec");
                CovSec_v.add_cross(bin_range(0, 1, 0), bin_range(0, EccChannels_c-1, 0));

                -- Packets of all length classes, so that faults hit packets of several data frames
                for c in 0 to 1 loop

                    for vc in 0 to NumVc_g-1 loop
                        CoreCfg(c).Vc(vc).LenClasses <= true;
                    end loop;

                end loop;

                for f in 1 to CampaignFaults_c loop
                    sendAll(3 * NumLanes_g); -- about 60 % load of the link (209.5 bytes per packet on average)
                    CoreCfg(0).BcSend <= CoreCfg(0).BcSend + 1;
                    CoreCfg(1).BcSend <= CoreCfg(1).BcSend + 1;
                    randInt(200, 1500, N_v);
                    cycles(N_v);
                    randInt(FaultFlip_c, FaultCut_c, Kind_v);
                    randInt(0, NumLanes_g-1, Lane_v);
                    randInt(0, 1, Dir_v);
                    randInt(0, 1, Core_v);
                    if Kind_v = FaultCut_c and NumLanes_g = 1 then
                        Kind_v := FaultFlip_c;
                    end if;
                    Faults_v(Kind_v) := Faults_v(Kind_v) + 1;
                    CovFault_v.sample_coverage(Kind_v);
                    if Kind_v /= FaultSec_c and Kind_v /= FaultDed_c then
                        CovLine_v.sample_coverage((Kind_v, Lane_v));
                    end if;

                    case Kind_v is

                        when FaultFlip_c | FaultBurst_c =>
                            N_v := 1;
                            if Kind_v = FaultBurst_c then
                                randInt(2, 8, N_v);
                            end if;
                            if Dir_v = 0 then
                                PaCtrl(Lane_v).AtoB.Flips <= PaCtrl(Lane_v).AtoB.Flips + N_v;
                            else
                                PaCtrl(Lane_v).BtoA.Flips <= PaCtrl(Lane_v).BtoA.Flips + N_v;
                            end if;

                        when FaultSlip_c =>
                            if Dir_v = 0 then
                                PaCtrl(Lane_v).AtoB.Skew <= 1 - PaCtrl(Lane_v).AtoB.Skew;
                            else
                                PaCtrl(Lane_v).BtoA.Skew <= 1 - PaCtrl(Lane_v).BtoA.Skew;
                            end if;

                        when FaultSec_c =>
                            randInt(0, EccChannels_c-1, Ch_v);
                            wr(Core_v, RegEccInject_c, std_logic_vector(to_unsigned(Ch_v, 32)));
                            Sec_v(Core_v)(Ch_v) := '1';
                            CovSec_v.sample_coverage((Core_v, Ch_v));

                        when FaultDed_c =>
                            -- A double error in a row crossing corrupts one word on the link: the receiver
                            -- detects it with the CRC and the frame is sent again
                            Ch_v                := EccChCcTx_c + Dir_v;
                            wr(Core_v, RegEccInject_c, std_logic_vector(to_unsigned(16#100# + Ch_v, 32)));
                            Ded_v(Core_v)(Ch_v) := '1';

                        when others =>
                            PaCtrl(Lane_v).AtoB.Cut <= true;
                            PaCtrl(Lane_v).BtoA.Cut <= true;
                            randInt(500, 3000, N_v);
                            cycles(N_v);
                            PaCtrl(Lane_v).AtoB.Cut <= false;
                            PaCtrl(Lane_v).BtoA.Cut <= false;
                            allLanes(2 ms);

                    end case;

                    log(ID_SEQUENCER, "Fault " & to_string(f) & ": kind " & to_string(Kind_v) & ", lane " & to_string(Lane_v) &
                        ", direction " & to_string(Dir_v) & ", core " & to_string(Core_v) & ", channel " & to_string(Ch_v) &
                        ", symbols / cycles " & to_string(N_v));
                end loop;

                -- Traffic in every EDAC channel after the last fault: packets, broadcast messages, a QoS write
                for c in 0 to 1 loop
                    CoreCfg(c).BcSend <= CoreCfg(c).BcSend + 1;
                    wr(c, 16#434#, x"0000FFFF");
                end loop;

                sendAll(2);
                waitDelivered(10 ms);
                log(ID_LOG_HDR, "Faults (bit error, burst, slip, SEC, DED, lane cut): " & to_string(Faults_v(0)) & ", " &
                    to_string(Faults_v(1)) & ", " & to_string(Faults_v(2)) & ", " & to_string(Faults_v(3)) & ", " &
                    to_string(Faults_v(4)) & ", " & to_string(Faults_v(5)));

                for c in 0 to 1 loop
                    rd(c, RegDlStatus_c, Data_v);
                    check_value(Data_v(1 downto 0), "11", error, "Link initialised at core " & to_string(c));
                    rd(c, RegDlErrors_c, Data_v);
                    check_value(Data_v(5 downto 4), "00", error, "No link reset at core " & to_string(c));
                    rd(c, RegRetries_c, Data_v);
                    check_value(unsigned(Data_v) > 0, error, "Retries at core " & to_string(c));
                    log(ID_LOG_HDR, "Core " & to_string(c) & ": " & to_string(to_integer(unsigned(Data_v))) & " retries");
                    rd(c, RegEccStatus_c, Data_v);
                    check_value(Data_v(EccChannels_c-1 downto 0), Ded_v(c), error, "DED flags at core " & to_string(c));

                    for ch in 0 to EccChannels_c-1 loop
                        wr(c, RegEccSelect_c, std_logic_vector(to_unsigned(ch, 32)));
                        rd(c, RegEccCount_c, Data_v);
                        if Sec_v(c)(ch) = '1' then
                            check_value(unsigned(Data_v(15 downto 0)) > 0, error,
                                        "SEC counted at core " & to_string(c) & ", channel " & to_string(ch));
                        end if;
                        check_value(unsigned(Data_v(31 downto 16)) > 0, Ded_v(c)(ch) = '1', error,
                                    "DED counted at core " & to_string(c) & ", channel " & to_string(ch));
                    end loop;

                end loop;

                if NumLanes_g > 1 then
                    allLanes(2 ms);
                end if;

                CovFault_v.report_coverage(VOID);
                CovLine_v.report_coverage(VOID);
                CovSec_v.report_coverage(VOID);
                check_value(CovFault_v.coverage_completed(BINS), error, "Every fault kind injected");
                check_value(CovPkt_v.coverage_completed(BINS), error, "Every length class on every VC in both directions");

            -- TC-CORE-17: traffic mix for the functional coverage: packets of every length class (1 to 4,
            -- 5 to 64, 65 to 256, 257 to 1024 bytes) on every VC and broadcast messages with and without
            -- DELAYED flag in both directions, receivers ready 70 % of the time
            elsif run("test_traffic_mix") then
                linkUp(500 us);

                for c in 0 to 1 loop

                    for vc in 0 to NumVc_g-1 loop
                        CoreCfg(c).Vc(vc).LenClasses <= true;
                        CoreCfg(c).Vc(vc).ReadyPct   <= 70;
                    end loop;

                end loop;

                CoreCfg(0).BcSend <= 20;
                CoreCfg(1).BcSend <= 20;
                sendAll(8);
                waitDelivered(10 ms);
                check_value(CovPkt_v.coverage_completed(BINS), error, "Every length class on every VC in both directions");
                check_value(CovBc_v.coverage_completed(BINS), error, "Broadcast messages with and without DELAYED flag");

                for c in 0 to 1 loop
                    rd(c, RegDlErrors_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No error at core " & to_string(c));
                end loop;

            -- TC-CORE-16: throughput and latency. Latency of a packet of one word on the idle link; payload
            -- throughput with packets of up to 1024 bytes on all VCs, from A to B only and in both directions,
            -- over 100 us after 20 us of warm-up, compared with the payload capacity of the lanes (32 bits per
            -- LaneClk cycle and lane)
            elsif run("test_throughput") then
                enable_log_msg(ID_SEQUENCER);
                linkUp(500 us);
                cycles(1000);
                -- Latency: one packet of 4 bytes on VC 0 from A to B
                CoreCfg(0).Vc(0).MaxLen  <= 1;
                cycles(1);
                T0_v                     := now;
                CoreCfg(0).Vc(0).Packets <= CoreCfg(0).Vc(0).Packets + 1;

                wait until CoreRxWords(1, 0) /= 0 for 100 us;
                log(ID_SEQUENCER, "Latency of a packet of one byte from A to B: " & to_string(now - T0_v));
                waitDelivered(100 us);

                for dir in 0 to 1 loop

                    for c in 0 to 1 loop

                        for vc in 0 to NumVc_g-1 loop
                            CoreCfg(c).Vc(vc).MaxLen <= 1024;
                            if c = 0 or dir = 1 then
                                CoreCfg(c).Vc(vc).Packets <= CoreCfg(c).Vc(vc).Packets + 40 * NumLanes_g;
                            end if;
                        end loop;

                    end loop;

                    cycles(2000);
                    N_v  := 0;
                    W0_v := 0;

                    for vc in 0 to NumVc_g-1 loop
                        N_v  := N_v + CoreRxWords(1, vc);
                        W0_v := W0_v + CoreRxWords(0, vc);
                    end loop;

                    T0_v    := now;
                    cycles(10000);
                    Rate_v  := 0.0;
                    RateB_v := 0.0;

                    for vc in 0 to NumVc_g-1 loop
                        Rate_v  := Rate_v + real(CoreRxWords(1, vc));
                        RateB_v := RateB_v + real(CoreRxWords(0, vc));
                    end loop;

                    -- Payload bits per ns = Gbit/s; capacity 32 bits per LaneClk cycle and lane
                    Rate_v  := (Rate_v - real(N_v)) * 32.0 / real((now - T0_v) / 1 ns);
                    RateB_v := (RateB_v - real(W0_v)) * 32.0 / real((now - T0_v) / 1 ns);
                    if dir = 0 then
                        log(ID_SEQUENCER, "A to B only: " & to_string(Rate_v, 3) & " Gbit/s, " &
                            to_string(100.0 * Rate_v / (LaneGbps_c * real(NumLanes_g)), 1) & " % of the lane capacity");
                        check_value(Rate_v > 0.9 * LaneGbps_c * real(NumLanes_g), error, "Throughput from A to B");
                    else
                        log(ID_SEQUENCER, "Both directions: A to B " & to_string(Rate_v, 3) & " Gbit/s, B to A " &
                            to_string(RateB_v, 3) & " Gbit/s (" & to_string(100.0 * Rate_v / (LaneGbps_c * real(NumLanes_g)), 1) &
                            " %, " & to_string(100.0 * RateB_v / (LaneGbps_c * real(NumLanes_g)), 1) & " %)");
                        check_value(Rate_v > 0.85 * LaneGbps_c * real(NumLanes_g), error, "Throughput from A to B");
                        check_value(RateB_v > 0.85 * LaneGbps_c * real(NumLanes_g), error, "Throughput from B to A");
                    end if;
                    waitDelivered(5 ms);
                end loop;

            -- TC-CORE-15: receive row overflow. With CoreClk slower than LaneClk (configuration
            -- lanes1_slowcore, outside CORE-CK-01) rows are lost in the crossing and DL_ERRORS bit 10 is set;
            -- with the regular clocks no row is lost during traffic
            elsif run("test_row_overflow") then
                if CoreHalfPs_g > 3200 then

                    for l in 0 to NumLanes_g-1 loop
                        wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
                    end loop;

                    for k in 0 to 1000 loop
                        rd(0, RegDlErrors_c, Data_v);
                        exit when Data_v(10) = '1';
                        cycles(100);
                    end loop;

                    check_value(Data_v(10), '1', error, "Receive row overflow at A");
                else
                    linkUp(500 us);
                    sendAll(20);
                    waitDelivered(5 ms);

                    for c in 0 to 1 loop
                        rd(c, RegDlErrors_c, Data_v);
                        check_value(Data_v(10), '0', error, "No receive row overflow at core " & to_string(c));
                    end loop;

                end if;

            -- TC-CORE-14: an uncorrectable error (DED) in each buffer of the Data Link layer of A during
            -- traffic: no wrong word reaches a user. Output VC buffers, error recovery buffer, frame buffer
            -- and broadcast output buffer: link reset (packets end with EEP or are lost); input VC buffer:
            -- the packet ends with EEP; broadcast input buffer: the message is discarded
            -- TC-CORE-18: PRBS test from A to B on every lane (behavioural adapter model): the MIB patterns reach
            -- the adapters, B locks, a forced error at A is counted at B on its lane only, a different pattern at
            -- the checker counts errors
            elsif run("test_prbs") then
                linkUp(500 us);

                for l in 0 to NumLanes_g-1 loop
                    wr(0, RegLanePrbsCtrl_c + l * RegLaneStride_c, x"00000005");
                    wr(1, RegLanePrbsCtrl_c + l * RegLaneStride_c, x"00000050");
                end loop;

                cycles(100);

                for l in 0 to NumLanes_g-1 loop
                    wr(1, RegLanePrbsCtrl_c + l * RegLaneStride_c, x"00010050");
                end loop;

                cycles(200);

                for l in 0 to NumLanes_g-1 loop
                    rd(1, RegLaneStatus_c + l * RegLaneStride_c, Data_v);
                    check_value(Data_v(LaneStatusPrbsLocked_c), '1', error, "PRBS checker of B locked, lane " &
                                to_string(l));
                    rd(1, RegLanePrbsErrors_c + l * RegLaneStride_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No PRBS error at B, lane " & to_string(l));
                end loop;

                wr(0, RegLanePrbsCtrl_c, x"00020005");
                cycles(200);

                for l in 0 to NumLanes_g-1 loop
                    rd(1, RegLanePrbsErrors_c + l * RegLaneStride_c, Data_v);
                    if l = 0 then
                        check_value(Data_v, x"00000001", error, "Forced error of A counted at B, lane 0");
                    else
                        check_value(Data_v, x"00000000", error, "No PRBS error at B, lane " & to_string(l));
                    end if;
                end loop;

                wr(1, RegLanePrbsCtrl_c, x"00010010");
                cycles(200);
                rd(1, RegLanePrbsErrors_c, Data_v);
                check_value(unsigned(Data_v) > 0, error, "PRBS-7 checker on PRBS-31 counts errors");

            elsif run("test_ded_containment") then
                enable_log_msg(ID_SEQUENCER);
                CoreCfg(0).Lossy <= true;
                CoreCfg(1).Lossy <= true;
                linkUp(500 us);

                for ch in EccChVcOut_c to EccChBcIn_c loop
                    log(ID_SEQUENCER, "DED in channel " & to_string(ch));
                    sendAll(10);
                    CoreCfg(0).BcSend <= CoreCfg(0).BcSend + 3;
                    CoreCfg(1).BcSend <= CoreCfg(1).BcSend + 3;
                    cycles(300);
                    if ch = EccChVcIn_c then
                        -- One packet of 1024 bytes per VC: the rest of the packet after the error spans several
                        -- beats (discarded up to its end)
                        dedVcIn(1024, 1024, 1);
                    else
                        wr(0, RegEccInject_c, std_logic_vector(to_unsigned(16#100# + ch, 32)));
                        -- The error goes into the next word written into the channel: more traffic
                        sendAll(5);
                        CoreCfg(0).BcSend <= CoreCfg(0).BcSend + 2;
                        CoreCfg(1).BcSend <= CoreCfg(1).BcSend + 2;
                    end if;

                    -- The word with the error is read (DED flag of the channel at A)
                    for k in 0 to 1000 loop
                        rd(0, RegEccStatus_c, Data_v);
                        exit when Data_v(ch) = '1';
                        cycles(100);
                    end loop;

                    check_value(Data_v(ch), '1', error, "DED read in channel " & to_string(ch));
                    -- Link reset: reported by the far end, then the link starts again
                    if ch /= EccChVcIn_c and ch /= EccChBcIn_c then

                        for k in 0 to 1000 loop
                            rd(1, RegDlErrors_c, Data_v);
                            exit when Data_v(5) = '1';
                            cycles(100);
                        end loop;

                        check_value(Data_v(5), '1', error, "Link reset (far end B) for channel " & to_string(ch));
                    end if;
                    linkUp(500 us);
                    -- Traffic after the error: packets and messages lost before it are recognised
                    sendAll(2);
                    CoreCfg(0).BcSend <= CoreCfg(0).BcSend + 1;
                    CoreCfg(1).BcSend <= CoreCfg(1).BcSend + 1;
                    waitDelivered(2 ms);
                    wr(0, RegEccSelect_c, std_logic_vector(to_unsigned(ch, 32)));
                    rd(0, RegEccCount_c, Data_v);
                    check_value(unsigned(Data_v(31 downto 16)) > 0, error, "DED counted in channel " & to_string(ch));
                    if ch = EccChVcIn_c or ch = EccChBcIn_c then
                        rd(1, RegDlErrors_c, Data_v);
                        check_value(Data_v(5), '0', error, "No link reset for channel " & to_string(ch));
                    end if;
                    rd(0, RegDlErrors_c, Data_v);
                    check_value(Data_v(4), '0', error, "No protocol error at A for channel " & to_string(ch));
                    wr(0, RegDlErrors_c, x"FFFFFFFF");
                    wr(1, RegDlErrors_c, x"FFFFFFFF");
                    wr(0, RegEccStatus_c, x"00000000");
                    if ch = EccChVcIn_c then
                        defaultLengths;
                        -- Second error: four packets of one word (1 to 3 bytes and the EOP) per VC, so that the
                        -- beat with the error ends its packet (nothing to discard): the EEP that replaces it is a
                        -- packet of zero length, discarded and counted by the Network interface
                        rd(0, RegNiRxEmptyCount_c, Data_v);
                        N_v := to_integer(unsigned(Data_v(15 downto 0)));
                        dedVcIn(1, 3, 4);
                        sendAll(2);
                        waitDelivered(2 ms);
                        rd(0, RegNiRxEmptyCount_c, Data_v);
                        check_value(to_integer(unsigned(Data_v(15 downto 0))) - N_v, NumVc_g, error,
                                    "Packets of zero length after the second error in the input VC buffers of A");
                        defaultLengths;
                        rd(1, RegDlErrors_c, Data_v);
                        check_value(Data_v(5), '0', error, "No link reset for the second error in the input VC buffers");
                        wr(0, RegEccStatus_c, x"00000000");
                    end if;
                end loop;

                -- Every packet with a DED in the input VC buffer of A ends with an EEP, or is discarded as a
                -- packet of zero length when the error is in its first beat (two errors per VC)
                rd(0, RegNiRxEmptyCount_c, Data_v);
                N_v := to_integer(unsigned(Data_v(15 downto 0)));

                for vc in 0 to NumVc_g-1 loop
                    N_v := N_v + CoreRxEep(0, vc);
                end loop;

                check_value(N_v >= 2 * NumVc_g, error, "Packets with a DED in the input VC buffers of A ended " &
                            "with EEP or discarded");

                check_value(CoreBcLost(0) > 0, error, "Message with a DED in the broadcast input buffer discarded");

            -- TC-CORE-19: complete restart of one end while the other end is in Link Initialised (ECSS 5.7.9,
            -- Near-End Reset a.3): power-on reset of B, Interface Reset of B, power-on reset of A. The lanes of
            -- both ends initialise from ClearLine, the end in Link Initialised detects the far-end reset
            -- (Far-End Link Reset) and resets too, the link comes up and the traffic continues
            elsif run("test_far_end_restart") then
                linkUp(500 us);
                sendAll(3);
                waitDelivered(2 ms);
                log(ID_LOG_HDR, "Power-on reset of B");
                CoreRstReq(1) <= '1';
                cycles(100);
                CoreRstReq(1) <= '0';
                cycles(100);
                linkUp(500 us);
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(5), '1', error, "Far-End Link Reset at A after the power-on reset of B");
                wr(0, RegDlErrors_c, x"00000020");
                sendAll(3);
                waitDelivered(2 ms);
                log(ID_LOG_HDR, "Interface Reset of B");
                wr(1, RegDlCtrl_c, x"00000102");
                cycles(100);
                linkUp(500 us);
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(5), '1', error, "Far-End Link Reset at A after the Interface Reset of B");
                sendAll(3);
                waitDelivered(2 ms);
                log(ID_LOG_HDR, "Power-on reset of A");
                CoreRstReq(0) <= '1';
                cycles(100);
                CoreRstReq(0) <= '0';
                cycles(100);
                linkUp(500 us);
                rd(1, RegDlErrors_c, Data_v);
                check_value(Data_v(5), '1', error, "Far-End Link Reset at B after the power-on reset of A");
                sendAll(3);
                waitDelivered(2 ms);

            -- TC-CORE-20: packets of 65542 bytes (the largest Space Packet of CCSDS 133.0-B-2), much longer
            -- than a data frame and than the VC buffers: one from A to B on VC 0, then two at the same time from
            -- B to A on VCs 1 and 2; every byte is compared, no error flag
            elsif run("test_long_packets") then
                linkUp(500 us);
                CoreCfg(0).Vc(0).MinLen  <= LongPacket_c;
                CoreCfg(0).Vc(0).MaxLen  <= LongPacket_c;
                CoreCfg(0).Vc(0).Packets <= CoreCfg(0).Vc(0).Packets + 1;
                cycles(1);
                waitDelivered(2 ms);

                for vc in 1 to 2 loop
                    CoreCfg(1).Vc(vc).MinLen  <= LongPacket_c;
                    CoreCfg(1).Vc(vc).MaxLen  <= LongPacket_c;
                    CoreCfg(1).Vc(vc).Packets <= CoreCfg(1).Vc(vc).Packets + 1;
                end loop;

                cycles(1);
                waitDelivered(4 ms);

                for c in 0 to 1 loop
                    rd(c, RegDlErrors_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No error flag at core " & to_string(c));
                end loop;

            -- TC-CORE-21: the transmitters of A become ready only 50 us after the reset: until then A stays
            -- in Near-End Reset with its lanes in reset (no error, link not initialised), afterwards the link
            -- comes up as after a reset; TX_LOST is not set by the first start
            elsif run("test_tx_ready_late") then

                for l in 0 to NumLanes_g-1 loop
                    wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
                end loop;

                cycles(5000);
                check_value(CoreLaneOn(0) = '0' and CoreLaneOn(0)'last_event >= 50 us, error,
                            "Lanes of A held in reset for 50 us");
                rd(0, RegDlStatus_c, Data_v);
                check_value(Data_v(1 downto 0), "01", error, "A held in Near-End Reset");
                check_value(Data_v(9), '0', error, "TX_READY 0 at A");
                rd(1, RegDlStatus_c, Data_v);
                check_value(Data_v(1 downto 0) /= "11", error, "Link of B not initialised");
                rd(0, RegLaneStat_c, Data_v);
                check_value(Data_v(3 downto 0) /= x"7", error, "Lane 0 of A not active");
                CoreTxReady(0) <= '1';
                linkUp(500 us);
                rd(0, RegDlStatus_c, Data_v);
                check_value(Data_v(9), '1', error, "TX_READY 1 at A");

                for c in 0 to 1 loop
                    rd(c, RegDlErrors_c, Data_v);
                    check_value(Data_v, x"00000000", error, "No error flag at core " & to_string(c));
                end loop;

                sendAll(5);
                waitDelivered(2 ms);

            -- TC-CORE-22: the transmitters of A never become ready: A stays in Near-End Reset without error
            -- flags, counters or interrupts (all interrupt sources enabled); the MIB stays accessible with
            -- TX_READY 0
            elsif run("test_tx_ready_never") then
                wr(0, RegIrqMask_c, x"030F1FFF");

                for l in 0 to NumLanes_g-1 loop
                    wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
                end loop;

                N_v := 0;

                for i in 1 to 30000 loop
                    wait until falling_edge(MgmtClk);
                    if CoreIrq(0) = '1' then
                        N_v := N_v + 1;
                    end if;
                end loop;

                check_value(N_v, 0, error, "No interrupt at A in 300 us");
                check_value(CoreLaneOn(0) = '0' and CoreLaneOn(0)'last_event >= 300 us, error,
                            "Lanes of A held in reset for 300 us");
                rd(0, RegDlStatus_c, Data_v);
                check_value(Data_v(1 downto 0), "01", error, "A held in Near-End Reset");
                check_value(Data_v(9), '0', error, "TX_READY 0 at A");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v, x"00000000", error, "No error flag at A");
                rd(0, RegRetries_c, Data_v);
                check_value(Data_v, x"00000000", error, "No retry at A");

                for l in 0 to NumLanes_g-1 loop
                    rd(0, RegLaneEvents_c + 16#20# * l, Data_v);
                    check_value(Data_v, x"00000000", error, "No event of lane " & to_string(l) & " at A");
                end loop;

                wr(0, RegDlBcInterval_c, x"00000123");
                rd(0, RegDlBcInterval_c, Data_v);
                check_value(Data_v, x"00000123", error, "MIB of A accessible");

            -- TC-CORE-23: the transmitters of A drop during traffic: link reset of both ends (packets in
            -- progress end with EEP or are lost, lossy comparison), the configuration of A is kept, TX_LOST is
            -- set; when they are ready again the link comes up and the traffic continues
            elsif run("test_tx_ready_lost") then
                CoreCfg(0).Lossy <= true;
                CoreCfg(1).Lossy <= true;
                linkUp(500 us);
                wr(0, RegDlBcInterval_c, x"00000033");
                sendAll(20);
                cycles(300);
                CoreTxReady(0)   <= '0';
                cycles(1000);
                check_value(CoreLaneOn(0) = '0' and CoreLaneOn(0)'last_event >= 5 us, error,
                            "Lanes of A held in reset in the last 5 us of the hold");
                rd(0, RegDlStatus_c, Data_v);
                check_value(Data_v(1 downto 0), "01", error, "A held in Near-End Reset");
                check_value(Data_v(9), '0', error, "TX_READY 0 at A");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(12), '1', error, "TX_LOST at A");
                rd(0, RegDlBcInterval_c, Data_v);
                check_value(Data_v, x"00000033", error, "Configuration of A kept");
                CoreTxReady(0)   <= '1';
                linkUp(500 us);
                sendAll(5);
                waitDelivered(5 ms);
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(12), '1', error, "TX_LOST at A still set (sticky)");
                wr(0, RegDlErrors_c, x"00001000");
                rd(0, RegDlErrors_c, Data_v);
                check_value(Data_v(12), '0', error, "TX_LOST at A cleared");

            -- TC-CORE-24: the transmitters of A are reset during traffic and their clock stops (LaneClk and
            -- CoreClk of A stand still, the lines from A carry no signal): the MIB of A reports TX_READY 0
            -- and TX_LOST while the clocks stand still, the lanes of A are held as soon as LaneClk runs
            -- again. The link comes up again with the lanes released 1 us before the Data Link layer (round
            -- 0: LaneClk runs again 1 us before CoreClk) and with the Data Link layer released 1 us before
            -- the lanes (round 1); no error flag but TX_LOST at A in either order
            elsif run("test_tx_ready_clock_stop") then
                CoreCfg(0).Lossy <= true;
                CoreCfg(1).Lossy <= true;
                linkUp(500 us);

                for round in 0 to 1 loop
                    sendAll(10);
                    cycles(300);
                    CoreLaneClkRun(0) <= '0';
                    CoreCoreClkRun(0) <= '0';
                    cycles(10);
                    CoreTxReady(0)    <= '0';

                    for l in 0 to NumLanes_g-1 loop
                        PaCtrl(l).AtoB.Cut <= true;
                    end loop;

                    cycles(1000);
                    rd(0, RegDlStatus_c, Data_v);
                    check_value(Data_v(9), '0', error, "TX_READY 0 at A while its clocks stand still");
                    rd(0, RegDlErrors_c, Data_v);
                    check_value(Data_v(12), '1', error, "TX_LOST at A while its clocks stand still");
                    if round = 0 then
                        CoreLaneClkRun(0) <= '1';
                        cycles(20);
                        check_value(CoreLaneOn(0), '0', error, "Lanes of A held as soon as LaneClk runs again");
                    else
                        CoreCoreClkRun(0) <= '1';
                        cycles(20);
                    end if;
                    CoreTxReady(0) <= '1';

                    for l in 0 to NumLanes_g-1 loop
                        PaCtrl(l).AtoB.Cut <= false;
                    end loop;

                    cycles(100);
                    if round = 0 then
                        CoreCoreClkRun(0) <= '1';
                    else
                        CoreLaneClkRun(0) <= '1';
                    end if;
                    linkUp(500 us);
                    sendAll(5);
                    waitDelivered(5 ms);
                    rd(0, RegDlErrors_c, Data_v);
                    check_value(Data_v, x"00001000", error, "Only TX_LOST at A, round " & to_string(round));
                    wr(0, RegDlErrors_c, x"00001000");
                end loop;

            end if;

        end loop;

        coreCovReport;
        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 20 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_core_th
        generic map (
            NumLanes_g      => NumLanes_g,
            NumVc_g         => NumVc_g,
            CoreHalfPs_g    => CoreHalfPs_g,
            LaneHalfPs_g    => LaneHalfPs_g,
            VcOutDepth_g    => VcOutDepth_g,
            VcInDepth_g     => VcInDepth_g,
            ErbRows_g       => ErbRows_g,
            InitPrbsWords_g => InitPrbsWords_g
        )
        port map (
            MgmtClk => MgmtClk,
            Rst     => Rst
        );

end architecture;
