---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the Management Information Base: register map, reset values, configuration
-- crossings, commands, status, sticky flags, counters and interrupt (four clock domains).
--
-- Documentation: hdl/ofb_mib/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_mib_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_mib_tb is

    constant NumVc_c : positive := 4;
    constant Axi_c   : natural  := 1;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic := '1';
    signal CoreClk : std_logic := '0';
    signal LaneClk : std_logic := '0';
    signal UserClk : std_logic := '0';

    -- AXI4-Lite
    signal ArAddr  : std_logic_vector(11 downto 0);
    signal ArValid : std_logic;
    signal ArReady : std_logic;
    signal AwAddr  : std_logic_vector(11 downto 0);
    signal AwValid : std_logic;
    signal AwReady : std_logic;
    signal WData   : std_logic_vector(31 downto 0);
    signal WStrb   : std_logic_vector(3 downto 0);
    signal WValid  : std_logic;
    signal WReady  : std_logic;
    signal BResp   : std_logic_vector(1 downto 0);
    signal BValid  : std_logic;
    signal BReady  : std_logic;
    signal RData   : std_logic_vector(31 downto 0);
    signal RResp   : std_logic_vector(1 downto 0);
    signal RValid  : std_logic;
    signal RReady  : std_logic;
    signal Irq     : std_logic;

    -- Core domain
    signal DataScrambled : std_logic;
    signal BcInterval    : std_logic_vector(15 downto 0);
    signal LinkResetCmd  : std_logic;
    signal IfResetCmd    : std_logic;
    signal LinkResetCnt  : natural                              := 0;
    signal IfResetCnt    : natural                              := 0;
    signal DlStates      : std_logic_vector(7 downto 0)         := x"00";
    signal HasCredit     : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');
    signal DlEv          : std_logic_vector(7 downto 0)         := x"00";
    signal InOvf         : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');
    signal CrOvf         : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');
    signal BwOver        : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');
    signal BwUnder       : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');
    signal TimeSlot      : std_logic_vector(5 downto 0)         := (others => '0');
    signal RegWr         : std_logic;
    signal RegAddr       : std_logic_vector(11 downto 0);
    signal RegData       : std_logic_vector(31 downto 0);
    signal RegWrCnt      : natural                              := 0;
    signal RegWrLast     : std_logic_vector(43 downto 0)        := (others => '0');

    -- Lane domain
    signal LaneStart : std_logic_vector(0 downto 0);
    signal AutoStart : std_logic_vector(0 downto 0);
    signal LaneReset : std_logic_vector(0 downto 0);
    signal NearLb    : std_logic_vector(0 downto 0);
    signal FarLb     : std_logic_vector(0 downto 0);
    signal SerNearLb : std_logic_vector(0 downto 0);
    signal SerFarLb  : std_logic_vector(0 downto 0);
    signal BitSync   : std_logic_vector(0 downto 0)  := "0";
    signal Reason    : std_logic_vector(7 downto 0);
    signal LaneStat  : std_logic_vector(37 downto 0) := (others => '0');
    signal LaneEv    : std_logic_vector(3 downto 0)  := "0000";
    signal MlStat    : std_logic_vector(3 downto 0)  := "0000";
    signal MlBypStat : std_logic                     := '0';
    signal MlMisEv   : std_logic                     := '0';
    signal RxOvfEv   : std_logic                     := '0';
    signal MlTxEn    : std_logic_vector(0 downto 0);
    signal MlRxEn    : std_logic_vector(0 downto 0);
    signal MlMax     : std_logic_vector(2 downto 0);
    signal MlBypass  : std_logic;
    signal DlMax     : std_logic_vector(2 downto 0);

    -- User domain
    signal NiEv : std_logic_vector(NumVc_c-1 downto 0) := (others => '0');

    -- EDAC monitor: events per domain, injection commands and their counts
    subtype EccVec_t is std_logic_vector(2*EccChannels_c-1 downto 0);

    type InjCnt_t is array (0 to 2*EccChannels_c-1) of natural;

    signal EccCore    : EccVec_t := (others => '0');
    signal EccUser    : EccVec_t := (others => '0');
    signal EccLane    : EccVec_t := (others => '0');
    signal EccInjCore : EccVec_t;
    signal EccInjUser : EccVec_t;
    signal EccInjLane : EccVec_t;
    signal InjCntCore : InjCnt_t := (others => 0);
    signal InjCntUser : InjCnt_t := (others => 0);
    signal InjCntLane : InjCnt_t := (others => 0);

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk     <= not Clk after 5 ns;
    CoreClk <= not CoreClk after 3.2 ns;
    LaneClk <= not LaneClk after 3.4 ns;
    UserClk <= not UserClk after 2.6 ns;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Start_v : time;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        procedure wr (
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(addr, 12), data, "Write " & to_hstring(to_unsigned(addr, 12)));
            await_completion(AXILITE_VVCT, Axi_c, 10 us);
        end procedure;

        procedure chk (
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(addr, 12), data, msg);
            await_completion(AXILITE_VVCT, Axi_c, 10 us);
        end procedure;

        -- One-cycle event in the core, lane or user domain
        procedure coreEvent (bit : natural) is
        begin
            wait until rising_edge(CoreClk);
            DlEv(bit) <= '1';
            wait until rising_edge(CoreClk);
            DlEv(bit) <= '0';

            for i in 1 to 10 loop
                wait until rising_edge(CoreClk);
            end loop;

        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        cycles(10);
        Rst <= '0';
        cycles(20);

        while test_suite loop

            -- TC-MG-01: identification and reset values
            if run("test_reset_values") then
                chk(16#000#, x"0FB10005", "ID");
                chk(16#004#, x"00000104", "Generics");
                chk(16#008#, x"00000100", "DataScrambled set");
                chk(16#00C#, x"00000028", "Broadcast interval 40");
                chk(16#100#, x"00000062", "AutoStart, TxEn and RxEn set");
                chk(16#058#, x"00000001", "Maximum number of data-sending lanes");
                chk(16#044#, x"00000000", "Interrupt mask");
                cycles(10);
                check_value(DataScrambled, '1', error, "DataScrambled in the core domain");
                check_value(BcInterval, x"0028", error, "Broadcast interval in the core domain");
                check_value(std_logic_vector'(AutoStart(0) & LaneStart(0)), "10", error, "Lane configuration");

            -- TC-MG-02: configuration, commands, Interface Reset
            elsif run("test_config") then
                wr(16#008#, x"00000000");
                wr(16#00C#, x"00001234");
                wr(16#100#, x"0000A51D");
                chk(16#100#, x"0000A51D", "Lane control read back");
                cycles(10);
                check_value(DataScrambled, '0', error, "DataScrambled cleared");
                check_value(BcInterval, x"1234", error, "Broadcast interval");
                check_value(std_logic_vector'(LaneStart(0) & AutoStart(0) & LaneReset(0) & NearLb(0) & FarLb(0)), "10111", error,
                            "Lane flags");
                check_value(Reason, x"A5", error, "Standby Reason");
                -- Link Reset command: one pulse
                wr(16#008#, x"00000001");
                cycles(10);
                check_value(LinkResetCnt, 1, error, "One Link Reset pulse");
                -- Interface Reset: one pulse, configuration back to the reset values
                wr(16#008#, x"00000002");
                cycles(10);
                check_value(IfResetCnt, 1, error, "One Interface Reset pulse");
                chk(16#008#, x"00000100", "DataScrambled reset value");
                chk(16#00C#, x"00000028", "Broadcast interval reset value");
                chk(16#100#, x"00000062", "Lane control reset value");

            -- TC-MG-03: status registers
            elsif run("test_status") then
                DlStates  <= x"BF";
                HasCredit <= "1010";
                LaneStat  <= x"D1" & x"56" & x"78" & x"9A" & '1' & '0' & x"7";
                MlStat    <= "1011";
                BitSync   <= "1";
                cycles(20);
                chk(16#010#, x"0000013F", "Data Link status");
                chk(16#030#, x"0000000A", "Has Credit");
                chk(16#104#, x"00789A67", "Lane status with bit synchronisation (bit 6)");
                chk(16#10C#, x"0000D156", "Lane reasons");
                chk(16#040#, x"00000211", "Multi-Lane status");

            -- TC-MG-05: quality of service registers: reset values, read back, forwarding to the core
            -- clock domain, bandwidth status, time-slot, Interface Reset
            elsif run("test_qos_registers") then
                chk(16#400#, x"00000003", "VC 0: lowest priority, VN 0");
                chk(16#410#, x"00010003", "VC 1: VN 1");
                chk(16#404#, x"00000A00", "VC 0: 10 %");
                chk(16#414#, x"0000FFFF", "VC 1: minimum bandwidth");
                chk(16#418#, x"FFFFFFFF", "VC 1: all time-slots");
                chk(16#050#, x"0002625A", "Idle time limit 156250 words");
                wr(16#410#, x"00050100");
                wr(16#400#, x"00070000");
                chk(16#410#, x"00050100", "VC 1 written");
                chk(16#400#, x"00000000", "VN of VC 0 stays 0");
                cycles(10);
                check_value(RegWrCnt, 2, error, "Two writes forwarded");
                check_value(RegWrLast, x"400" & x"00070000", error, "Last forwarded write");
                BwOver(2)  <= '1';
                BwUnder(3) <= '1';
                TimeSlot   <= "101010";
                cycles(20);
                BwOver(2)  <= '0';
                cycles(20);
                chk(16#048#, x"00000004", "Bandwidth over use VC 2 (sticky)");
                chk(16#04C#, x"00000008", "Bandwidth under use VC 3");
                chk(16#054#, x"0000002A", "Current time-slot");
                wr(16#008#, x"00000002");
                chk(16#410#, x"00010003", "Interface Reset restores VC 1");

            -- TC-MG-06: Multi-Lane registers: TxEn, RxEn, maximum number of data-sending lanes, bypass,
            -- status, Misaligned counter
            elsif run("test_multilane_registers") then
                cycles(10);
                check_value(std_logic_vector'(MlTxEn & MlRxEn & MlBypass), "110", error, "TxEn, RxEn, bypass reset");
                check_value(MlMax, "001", error, "Maximum number of data-sending lanes in the lane domain");
                check_value(DlMax, "001", error, "Maximum number of data-sending lanes in the core domain");
                wr(16#100#, x"00000023");
                wr(16#058#, x"00000100");
                cycles(10);
                check_value(std_logic_vector'(MlTxEn & MlRxEn & MlBypass), "101", error, "RxEn cleared, bypass set");
                check_value(MlMax & DlMax, "000000", error, "Maximum written");
                chk(16#058#, x"00000100", "ML_CTRL read back");
                -- Serial loopbacks of the Physical layer (Table 5-36)
                check_value(std_logic_vector'(SerNearLb(0) & SerFarLb(0)), "00", error, "Serial loopbacks de-asserted after reset");
                wr(16#100#, x"00010023");
                cycles(10);
                check_value(std_logic_vector'(SerNearLb(0) & SerFarLb(0)), "10", error, "Near-end serial loopback");
                chk(16#100#, x"00010023", "LANE_CTRL with near-end serial loopback");
                wr(16#100#, x"00020023");
                cycles(10);
                check_value(std_logic_vector'(SerNearLb(0) & SerFarLb(0)), "01", error, "Far-end serial loopback");
                MlStat    <= "1011";
                MlBypStat <= '1';
                cycles(20);
                chk(16#040#, x"00000611", "Multi-Lane status with bypass");

                for i in 1 to 3 loop
                    wait until rising_edge(LaneClk);
                    MlMisEv <= '1';
                    wait until rising_edge(LaneClk);
                    MlMisEv <= '0';
                    cycles(5);
                end loop;

                chk(16#05C#, x"00000003", "Misaligned conditions counted");
                wr(16#05C#, x"00000000");
                chk(16#05C#, x"00000000", "Misaligned counter cleared");
                wr(16#008#, x"00000002");
                chk(16#058#, x"00000001", "Interface Reset restores ML_CTRL");
                chk(16#100#, x"00000062", "Interface Reset restores TxEn and RxEn");
                cycles(10);
                check_value(std_logic_vector'(SerNearLb(0) & SerFarLb(0)), "00", error, "Interface Reset clears the serial loopbacks");

            -- TC-MG-07: EDAC monitor: events of the three domains counted per channel, DED flags,
            -- corrected-error flag, interrupt, clears; injection commands to the write domain of the
            -- channel; injection into the QoS write FIFO of the MIB (channel Ctrl)
            elsif run("test_edac") then

                for i in 1 to 3 loop
                    wait until rising_edge(CoreClk);
                    EccCore(EccChErb_c) <= '1';
                    wait until rising_edge(CoreClk);
                    EccCore(EccChErb_c) <= '0';
                    cycles(4);
                end loop;

                for i in 1 to 2 loop
                    wait until rising_edge(UserClk);
                    EccUser(EccChVcIn_c) <= '1';
                    wait until rising_edge(UserClk);
                    EccUser(EccChVcIn_c) <= '0';
                    cycles(4);
                end loop;

                wait until rising_edge(LaneClk);
                EccLane(EccChannels_c + EccChCcTx_c) <= '1';
                wait until rising_edge(LaneClk);
                EccLane(EccChannels_c + EccChCcTx_c) <= '0';
                cycles(10);
                wr(16#064#, x"00000001");
                chk(16#068#, x"00000003", "Three corrected errors in the error recovery buffer");
                wr(16#064#, x"00000003");
                chk(16#068#, x"00000002", "Two corrected errors in the input VC buffers");
                wr(16#064#, x"00000006");
                chk(16#068#, x"00010000", "One uncorrectable error in the transmit row crossing");
                chk(16#060#, x"00010040", "DED flag of channel 6, corrected error seen");
                -- Interrupt on an uncorrectable error
                wr(16#044#, x"01000000");
                cycles(5);
                check_value(Irq, '1', error, "Interrupt on DED");
                -- Clear of the selected channel, then of all flags and counters
                wr(16#068#, x"00000000");
                chk(16#068#, x"00000000", "Channel 6 cleared");
                chk(16#060#, x"00010000", "DED flag of channel 6 cleared with its counters");
                wr(16#064#, x"00000001");
                chk(16#068#, x"00000003", "Channel 1 kept");
                wr(16#060#, x"00000000");
                chk(16#060#, x"00000000", "All flags cleared");
                chk(16#068#, x"00000000", "All counters cleared");
                cycles(5);
                check_value(Irq, '0', error, "No interrupt after the clear");
                -- Injection commands to the write domain of the channel
                wr(16#06C#, std_logic_vector(to_unsigned(EccChVcOut_c, 32)));
                wr(16#06C#, x"00000100" or std_logic_vector(to_unsigned(EccChCcRx_c, 32)));
                wr(16#06C#, std_logic_vector(to_unsigned(EccChErb_c, 32)));
                cycles(20);
                check_value(InjCntUser(EccChVcOut_c), 1, error, "Single error into the output VC buffers (user)");
                check_value(InjCntLane(EccChannels_c + EccChCcRx_c), 1, error,
                            "Double error into the receive row crossing (lane)");
                check_value(InjCntCore(EccChErb_c), 1, error, "Single error into the error recovery buffer (core)");
                check_value(InjCntCore(EccChVcOut_c) + InjCntLane(EccChVcOut_c), 0, error, "Only to the write domain");
                -- Injection into the QoS write FIFO: the next forwarded write is corrected and counted
                wr(16#06C#, std_logic_vector(to_unsigned(EccChCtrl_c, 32)));
                wr(16#410#, x"00050100");
                cycles(20);
                check_value(RegWrLast, x"410" & x"00050100", error, "Corrected QoS write forwarded");
                wr(16#064#, std_logic_vector(to_unsigned(EccChCtrl_c, 32)));
                chk(16#068#, x"00000001", "Corrected error in the control crossings");

            -- TC-MG-04: sticky flags, counters, interrupt, Link Reset clears the status of all layers
            elsif run("test_events") then
                coreEvent(0);
                coreEvent(0);
                coreEvent(4);
                coreEvent(4);
                coreEvent(4);
                coreEvent(5);
                wait until rising_edge(CoreClk);
                InOvf(1)  <= '1';
                wait until rising_edge(CoreClk);
                InOvf(1)  <= '0';
                wait until rising_edge(UserClk);
                NiEv(2)   <= '1';
                wait until rising_edge(UserClk);
                NiEv(2)   <= '0';
                wait until rising_edge(LaneClk);
                LaneEv(1) <= '1';
                RxOvfEv   <= '1';
                wait until rising_edge(LaneClk);
                LaneEv(1) <= '0';
                RxOvfEv   <= '0';
                cycles(20);
                chk(16#014#, x"00000691", "Sticky Data Link errors, receive row overflow");
                chk(16#01C#, x"00000002", "CRC-16 counter");
                chk(16#018#, x"00000003", "Retries");
                chk(16#034#, x"00000002", "Input overflow VC 1");
                chk(16#03C#, x"00000004", "Framing error VC 2");
                chk(16#108#, x"00000002", "Lane timeout flag");
                chk(16#110#, x"00000001", "Lane timeout counter");
                check_value(Irq, '0', error, "No interrupt without mask");
                wr(16#044#, x"00000010");
                cycles(3);
                check_value(Irq, '1', error, "Interrupt for the protocol error");
                wr(16#014#, x"00000010");
                cycles(3);
                check_value(Irq, '0', error, "Interrupt cleared with the flag");
                chk(16#014#, x"00000681", "Protocol error flag cleared");
                wr(16#044#, x"00000400");
                cycles(3);
                check_value(Irq, '1', error, "Interrupt for the receive row overflow");
                wr(16#044#, x"00020000");
                cycles(3);
                check_value(Irq, '1', error, "Interrupt for the lane timeout");
                -- Link Reset command clears the status of the Data Link, Multi-Lane and Lane layers
                wr(16#008#, x"00000101");
                chk(16#014#, x"00000000", "Data Link flags cleared by Link Reset");
                chk(16#018#, x"00000000", "Retries cleared by Link Reset");
                chk(16#01C#, x"00000000", "CRC-16 counter cleared by Link Reset");
                chk(16#034#, x"00000000", "Input overflow flags cleared by Link Reset");
                chk(16#03C#, x"00000000", "Framing error flags cleared by Link Reset");
                chk(16#108#, x"00000000", "Lane flags cleared by Link Reset");
                chk(16#110#, x"00000000", "Lane timeout counter cleared by Link Reset");
                cycles(3);
                check_value(Irq, '0', error, "No interrupt after the Link Reset command");

            -- TC-MG-08: the remaining counters and flags: CRC-8, frame and sequence counters, credit
            -- overflow, bandwidth and lane event flags; a write clears a counter, W1C clears only the
            -- written bits; idle limit and time-slots 32 to 63 written, read back and forwarded;
            -- undefined lane registers read as zero; interrupt of the SEC flag
            elsif run("test_register_access") then
                coreEvent(1);
                coreEvent(2);
                coreEvent(2);

                for i in 1 to 3 loop
                    coreEvent(3);
                end loop;

                coreEvent(0);
                coreEvent(4);
                wait until rising_edge(CoreClk);
                CrOvf     <= "1001";
                wait until rising_edge(CoreClk);
                CrOvf     <= "0000";
                BwOver(1) <= '1';
                BwUnder   <= "0110";
                cycles(20);
                BwOver(1) <= '0';
                BwUnder   <= "0000";
                wait until rising_edge(LaneClk);
                LaneEv    <= "1101";
                wait until rising_edge(LaneClk);
                LaneEv    <= "0000";
                cycles(20);
                chk(16#020#, x"00000001", "CRC-8 counter");
                chk(16#024#, x"00000002", "Frame error counter");
                chk(16#028#, x"00000003", "Sequence error counter");
                chk(16#038#, x"00000009", "Credit overflow VC 0 and 3");
                chk(16#048#, x"00000002", "Bandwidth over use VC 1");
                chk(16#04C#, x"00000006", "Bandwidth under use VC 1 and 2");
                chk(16#108#, x"0000000D", "Lane events");
                wr(16#104#, x"FFFFFFFF");
                chk(16#104#, x"00000000", "LANE_STATUS is read only");
                chk(16#114#, x"00000000", "Undefined lane register");
                chk(16#11C#, x"00000000", "Undefined lane register");
                -- A write clears a counter
                wr(16#018#, x"00000000");
                wr(16#01C#, x"00000000");
                wr(16#020#, x"00000000");
                wr(16#024#, x"00000000");
                wr(16#028#, x"00000000");
                wr(16#110#, x"00000000");
                chk(16#018#, x"00000000", "Retries cleared");
                chk(16#01C#, x"00000000", "CRC-16 counter cleared");
                chk(16#020#, x"00000000", "CRC-8 counter cleared");
                chk(16#024#, x"00000000", "Frame error counter cleared");
                chk(16#028#, x"00000000", "Sequence error counter cleared");
                chk(16#110#, x"00000000", "Lane timeout counter cleared");
                -- W1C clears only the written bits
                wr(16#038#, x"00000008");
                chk(16#038#, x"00000001", "Credit overflow VC 3 cleared, VC 0 kept");
                wr(16#048#, x"00000002");
                chk(16#048#, x"00000000", "Bandwidth over use cleared");
                wr(16#04C#, x"00000004");
                chk(16#04C#, x"00000002", "Bandwidth under use VC 2 cleared, VC 1 kept");
                wr(16#108#, x"00000005");
                chk(16#108#, x"00000008", "Lane events 0 and 2 cleared, 3 kept");
                wait until rising_edge(CoreClk);
                InOvf(2) <= '1';
                wait until rising_edge(CoreClk);
                InOvf(2) <= '0';
                wait until rising_edge(UserClk);
                NiEv(3)  <= '1';
                wait until rising_edge(UserClk);
                NiEv(3)  <= '0';
                cycles(20);
                wr(16#034#, x"00000004");
                wr(16#03C#, x"00000001");
                chk(16#034#, x"00000000", "Input overflow VC 2 cleared");
                chk(16#03C#, x"00000008", "Framing error VC 3 kept");
                -- Idle limit and time-slots 32 to 63
                wr(16#050#, x"00001234");
                wr(16#43C#, x"5555AAAA");
                chk(16#050#, x"00001234", "Idle limit read back");
                chk(16#43C#, x"5555AAAA", "Time-slots 63 to 32 of VC 3 read back");
                cycles(10);
                check_value(RegWrLast, x"43C" & x"5555AAAA", error, "Time-slots forwarded to the Data Link layer");
                -- Interrupt of the SEC flag
                wait until rising_edge(CoreClk);
                EccCore(EccChFrameBuf_c) <= '1';
                wait until rising_edge(CoreClk);
                EccCore(EccChFrameBuf_c) <= '0';
                cycles(10);
                check_value(Irq, '0', error, "No interrupt without mask");
                wr(16#044#, x"02000000");
                cycles(3);
                check_value(Irq, '1', error, "Interrupt of the SEC flag");
                wr(16#060#, x"00000000");
                cycles(3);
                check_value(Irq, '0', error, "SEC flag cleared");

            -- TC-MG-09: the event counters saturate at 0xFFFF (CRC-8 counter, the counters share the
            -- saturating increment)
            elsif run("test_counter_saturation") then

                for i in 1 to 65537 loop
                    wait until rising_edge(CoreClk);
                    DlEv(1) <= '1';
                    wait until rising_edge(CoreClk);
                    DlEv(1) <= '0';

                    for k in 1 to 6 loop
                        wait until rising_edge(CoreClk);
                    end loop;

                end loop;

                cycles(10);
                chk(16#020#, x"0000FFFF", "CRC-8 counter saturated");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 10 ms);

    -----------------------------------------------------------------------------------------------
    -- Harness
    -----------------------------------------------------------------------------------------------
    i_axi : entity work.ofb_tb_axilite_master
        generic map (
            InstanceIdx_g => Axi_c,
            AddrWidth_g   => 12
        )
        port map (
            Clk     => Clk,
            ArAddr  => ArAddr,
            ArValid => ArValid,
            ArReady => ArReady,
            AwAddr  => AwAddr,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            RData   => RData,
            RResp   => RResp,
            RValid  => RValid,
            RReady  => RReady
        );

    i_dut : entity work.ofb_mib
        generic map (
            NumVc_g    => NumVc_c,
            NumLanes_g => 1
        )
        port map (
            Clk                    => Clk,
            Rst                    => Rst,
            S_AxiLite_ArAddr       => ArAddr,
            S_AxiLite_ArValid      => ArValid,
            S_AxiLite_ArReady      => ArReady,
            S_AxiLite_AwAddr       => AwAddr,
            S_AxiLite_AwValid      => AwValid,
            S_AxiLite_AwReady      => AwReady,
            S_AxiLite_WData        => WData,
            S_AxiLite_WStrb        => WStrb,
            S_AxiLite_WValid       => WValid,
            S_AxiLite_WReady       => WReady,
            S_AxiLite_BResp        => BResp,
            S_AxiLite_BValid       => BValid,
            S_AxiLite_BReady       => BReady,
            S_AxiLite_RData        => RData,
            S_AxiLite_RResp        => RResp,
            S_AxiLite_RValid       => RValid,
            S_AxiLite_RReady       => RReady,
            Irq                    => Irq,
            CoreClk                => CoreClk,
            CoreRst                => Rst,
            Dl_DataScrambled       => DataScrambled,
            Dl_BcInterval          => BcInterval,
            Dl_LinkReset           => LinkResetCmd,
            Dl_InterfaceReset      => IfResetCmd,
            Dl_LinkResetState      => DlStates(1 downto 0),
            Dl_RxErrState          => DlStates(3 downto 2),
            Dl_WordIdState         => DlStates(6 downto 4),
            Dl_ErbEmpty            => DlStates(7),
            Dl_HasCredit           => HasCredit,
            Dl_EvCrc16Err          => DlEv(0),
            Dl_EvCrc8Err           => DlEv(1),
            Dl_EvFrameErr          => DlEv(2),
            Dl_EvSeqErr            => DlEv(3),
            Dl_EvRetry             => DlEv(4),
            Dl_EvProtocolError     => DlEv(5),
            Dl_EvFarEndLinkReset   => DlEv(6),
            Dl_EvBcDiscard         => DlEv(7),
            Dl_EvInputOverflow     => InOvf,
            Dl_EvCreditOverflow    => CrOvf,
            Dl_BwOver              => BwOver,
            Dl_BwUnder             => BwUnder,
            Dl_TimeSlot            => TimeSlot,
            Dl_RegWr               => RegWr,
            Dl_RegAddr             => RegAddr,
            Dl_RegData             => RegData,
            Dl_MaxDataLanes        => DlMax,
            LaneClk                => LaneClk,
            LaneRst                => Rst,
            Lane_Start             => LaneStart,
            Lane_AutoStart         => AutoStart,
            Lane_Reset             => LaneReset,
            Lane_NearLoopback      => NearLb,
            Lane_FarLoopback       => FarLb,
            Lane_StandbyReason     => Reason,
            Phy_SerialNearLoopback => SerNearLb,
            Phy_SerialFarLoopback  => SerFarLb,
            Phy_BitSync            => BitSync,
            Lane_State             => LaneStat(3 downto 0),
            Lane_RxPolarity        => LaneStat(4 downto 4),
            Lane_NoSignal          => LaneStat(5 downto 5),
            Lane_RxErrCount        => LaneStat(13 downto 6),
            Lane_FarCapability     => LaneStat(21 downto 14),
            Lane_FarStandbyReason  => LaneStat(29 downto 22),
            Lane_FarLostReason     => LaneStat(37 downto 30),
            Lane_EvRxErrOverflow   => LaneEv(0 downto 0),
            Lane_EvTimeout         => LaneEv(1 downto 1),
            Lane_EvFarStandby      => LaneEv(2 downto 2),
            Lane_EvFarLostSignal   => LaneEv(3 downto 3),
            Ml_DataSending         => MlStat(0 downto 0),
            Ml_DataReceiving       => MlStat(1 downto 1),
            Ml_AlignState          => MlStat(3 downto 2),
            Ml_StatBypass          => MlBypStat,
            Ml_EvMisaligned        => MlMisEv,
            Ml_EvRxOverflow        => RxOvfEv,
            Ml_TxEn                => MlTxEn,
            Ml_RxEn                => MlRxEn,
            Ml_MaxDataLanes        => MlMax,
            Ml_Bypass              => MlBypass,
            UserClk                => UserClk,
            UserRst                => Rst,
            Ni_EvFrameErr          => NiEv,
            Ecc_Core               => EccCore,
            Ecc_User               => EccUser,
            Ecc_Lane               => EccLane,
            EccInj_Core            => EccInjCore,
            EccInj_User            => EccInjUser,
            EccInj_Lane            => EccInjLane
        );

    -- Count the command pulses and the register writes
    p_cmd : process (CoreClk) is
    begin
        if rising_edge(CoreClk) then
            if RegWr = '1' then
                RegWrCnt  <= RegWrCnt + 1;
                RegWrLast <= RegAddr & RegData;
            end if;
            if LinkResetCmd = '1' then
                LinkResetCnt <= LinkResetCnt + 1;
            end if;
            if IfResetCmd = '1' then
                IfResetCnt <= IfResetCnt + 1;
            end if;
        end if;
    end process;

    -- Injection commands counted per bit in their domain
    p_inj_core : process (CoreClk) is
    begin
        if rising_edge(CoreClk) then

            for i in 0 to 2*EccChannels_c-1 loop
                if EccInjCore(i) = '1' then
                    InjCntCore(i) <= InjCntCore(i) + 1;
                end if;
            end loop;

        end if;
    end process;

    p_inj_user : process (UserClk) is
    begin
        if rising_edge(UserClk) then

            for i in 0 to 2*EccChannels_c-1 loop
                if EccInjUser(i) = '1' then
                    InjCntUser(i) <= InjCntUser(i) + 1;
                end if;
            end loop;

        end if;
    end process;

    p_inj_lane : process (LaneClk) is
    begin
        if rising_edge(LaneClk) then

            for i in 0 to 2*EccChannels_c-1 loop
                if EccInjLane(i) = '1' then
                    InjCntLane(i) <= InjCntLane(i) + 1;
                end if;
            end loop;

        end if;
    end process;

end architecture;
