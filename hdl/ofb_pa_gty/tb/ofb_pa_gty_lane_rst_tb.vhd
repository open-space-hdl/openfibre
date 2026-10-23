---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of ofb_pa_gty_lane_rst, the reset sequencer of one lane of the GTY Physical adapter: the
-- port sequences of the entire receiver reset, the CDR-only receiver reset, the transmit buffer reset
-- and the receive elastic buffer reset, the bounded waits for RXRESETDONE, the priority of the
-- requests, the gap after a receiver reset, the PCSRSVDIN base value and the reset. A model of the
-- channel drives RXRESETDONE (normal, never rising again, never falling) and the transmit buffer
-- error; a monitor checks the port rules on every cycle (setup and hold of the masks around every
-- reset pulse, pulse width, PCSRSVDIN bits 10 and 9:8, one reset at a time, single-cycle events).
--
-- Documentation: hdl/ofb_pa_gty/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_lane_rst_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_lane_rst_tb is

    constant Period_c : time := 10 ns;

    -- Generics of the DUT, shortened for the test
    constant Setup_c    : positive                      := 4;
    constant Pulse_c    : positive                      := 6;
    constant Hold_c     : positive                      := 10;
    constant Holdoff_c  : positive                      := 12;
    constant CdrWait_c  : positive                      := 50;
    constant Gap_c      : natural                       := 300;
    constant DoneLow_c  : positive                      := 100;
    constant DoneHigh_c : positive                      := 400;
    constant PcsDflt_c  : std_logic_vector(15 downto 0) := x"0360";

    -- Channel model: RXRESETDONE falls DoneFall_c cycles after the start of a GTRXRESET pulse in sequential mode
    -- and rises DoneRise_c cycles after its end
    constant DoneFall_c : positive := 2;
    constant DoneRise_c : positive := 150;

    -- Port values outside the sequences
    constant RxModeSeq_c : std_logic_vector(1 downto 0) := "00";
    constant RxModeSgl_c : std_logic_vector(1 downto 0) := "11";

    -- RXRESETDONE of the model: normal, never rising after it fell (Hang_s), never falling (Stuck_s)
    type DoneMode_t is (Normal_s, Hang_s, Stuck_s);

    signal DoneMode    : DoneMode_t := Normal_s;
    signal TxErrSet    : std_logic  := '0';
    signal TxErrSticky : boolean    := false;

    signal Clk        : std_logic                     := '0';
    signal Rst        : std_logic                     := '1';
    signal ReqFull    : std_logic                     := '0';
    signal ReqBuf     : std_logic                     := '0';
    signal TxErr      : std_logic                     := '0';
    signal CfgCdrOnly : std_logic                     := '0';
    signal CfgPcs     : std_logic_vector(15 downto 0) := PcsDflt_c;
    signal MasterDone : std_logic                     := '1';
    signal RxRstDone  : std_logic                     := '1';
    signal GtRxRst    : std_logic;
    signal GtRxMode   : std_logic_vector(1 downto 0);
    signal GtRxPma    : std_logic_vector(6 downto 0);
    signal GtRxPcs    : std_logic_vector(4 downto 0);
    signal GtCdrRst   : std_logic;
    signal GtTxRst    : std_logic;
    signal GtTxMode   : std_logic_vector(1 downto 0);
    signal GtTxPma    : std_logic_vector(2 downto 0);
    signal GtTxPcs    : std_logic;
    signal GtPcs      : std_logic_vector(15 downto 0);
    signal RxBusy     : std_logic;
    signal BufBusy    : std_logic;
    signal EvDone     : std_logic;
    signal EvTimeo    : std_logic;

    -- Monitor: reset pulses and events
    signal NumFull  : natural := 0;
    signal NumBuf   : natural := 0;
    signal NumTx    : natural := 0;
    signal NumCdr   : natural := 0;
    signal NumDone  : natural := 0;
    signal NumTimeo : natural := 0;

begin

    Clk <= not Clk after Period_c / 2;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_pa_gty_lane_rst
        generic map (
            SetupCycles_g      => Setup_c,
            PulseCycles_g      => Pulse_c,
            HoldCycles_g       => Hold_c,
            HoldoffCycles_g    => Holdoff_c,
            CdrWaitCycles_g    => CdrWait_c,
            GapCycles_g        => Gap_c,
            DoneLowCycles_g    => DoneLow_c,
            DoneHighCycles_g   => DoneHigh_c,
            PcsRsvdInDefault_g => PcsDflt_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Req_Full       => ReqFull,
            Req_Buf        => ReqBuf,
            Req_Tx         => TxErr,
            Cfg_CdrOnly    => CfgCdrOnly,
            Cfg_PcsRsvdIn  => CfgPcs,
            Gt_MasterDone  => MasterDone,
            Gt_RxResetDone => RxRstDone,
            Gt_RxReset     => GtRxRst,
            Gt_RxResetMode => GtRxMode,
            Gt_RxPmaMask   => GtRxPma,
            Gt_RxPcsMask   => GtRxPcs,
            Gt_RxCdrReset  => GtCdrRst,
            Gt_TxReset     => GtTxRst,
            Gt_TxResetMode => GtTxMode,
            Gt_TxPmaMask   => GtTxPma,
            Gt_TxPcsMask   => GtTxPcs,
            Gt_PcsRsvdIn   => GtPcs,
            Stat_RxBusy    => RxBusy,
            Stat_BufBusy   => BufBusy,
            Ev_RxResetDone => EvDone,
            Ev_Timeout     => EvTimeo
        );

    -----------------------------------------------------------------------------------------------
    -- Channel model: RXRESETDONE after a GTRXRESET pulse in sequential mode (unchanged by single-mode resets),
    -- transmit buffer error until GTTXRESET (or sticky)
    -----------------------------------------------------------------------------------------------
    p_gt : process (Clk) is
        variable Last_v    : std_logic := '0';
        variable Run_v     : boolean   := false;
        variable FallCnt_v : natural   := 0;
        variable RiseCnt_v : natural   := 0;
    begin
        if rising_edge(Clk) then
            if GtRxRst = '1' and GtRxMode = RxModeSeq_c then
                if Last_v = '0' then
                    FallCnt_v := 0;
                end if;
                FallCnt_v := FallCnt_v + 1;
                if FallCnt_v >= DoneFall_c and DoneMode /= Stuck_s then
                    RxRstDone <= '0';
                end if;
                Run_v     := true;
                RiseCnt_v := 0;
            elsif Run_v then
                RiseCnt_v := RiseCnt_v + 1;
                if RiseCnt_v >= DoneRise_c and DoneMode = Normal_s then
                    RxRstDone <= '1';
                    Run_v     := false;
                end if;
            elsif DoneMode = Normal_s then
                RxRstDone <= '1';
            end if;
            Last_v := GtRxRst;

            if TxErrSet = '1' then
                TxErr <= '1';
            elsif GtTxRst = '1' and not TxErrSticky then
                TxErr <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitor: port rules on every cycle, counts of the reset pulses and events
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable RxSetLast_v : std_logic_vector(29 downto 0) := (others => '0');
        variable TxSetLast_v : std_logic_vector(21 downto 0) := (others => '0');
        variable RxSet_v     : std_logic_vector(29 downto 0);
        variable TxSet_v     : std_logic_vector(21 downto 0);
        variable RxAge_v     : natural                       := 0;
        variable TxAge_v     : natural                       := 0;
        variable RxHigh_v    : natural                       := 0;
        variable TxHigh_v    : natural                       := 0;
        variable CdrHigh_v   : natural                       := 0;
        variable RxFell_v    : natural                       := 0;
        variable TxFell_v    : natural                       := 0;
        variable RxAfter_v   : boolean                       := false;
        variable TxAfter_v   : boolean                       := false;
        variable FullLast_v  : boolean                       := false;
        variable EvLast_v    : std_logic_vector(1 downto 0)  := "00";
    begin
        if rising_edge(Clk) then
            -- Masks of the receiver and PCSRSVDIN without bit 10 (pulsed with GTRXRESET); masks of the transmitter
            -- and PCSRSVDIN
            RxSet_v := GtRxMode & GtRxPma & GtRxPcs & GtPcs(15 downto 11) & GtPcs(9 downto 0) & "0";
            TxSet_v := GtTxMode & GtTxPma & GtTxPcs & GtPcs;

            if Rst = '0' then
                -- One reset at a time
                check_value(not (GtRxRst = '1' and GtTxRst = '1'), error, "GTRXRESET and GTTXRESET not together");
                check_value(not (GtRxRst = '1' and GtCdrRst = '1'), error, "GTRXRESET and RXCDRRESET not together");
                check_value(not (GtTxRst = '1' and GtCdrRst = '1'), error, "GTTXRESET and RXCDRRESET not together");

                -- PCSRSVDIN bit 10 exactly with GTRXRESET in sequential mode, bits 9:8 high with it
                check_value(GtPcs(10), GtRxRst and not GtRxMode(0) and not GtRxMode(1), error,
                            "PCSRSVDIN[10] with GTRXRESET in sequential mode only");

                -- Receiver reset pulse
                if GtRxRst = '1' then
                    if RxHigh_v = 0 then
                        check_value(RxAge_v >= Setup_c, error, "Receiver masks set before GTRXRESET");
                        FullLast_v := GtRxMode = RxModeSeq_c;
                        if FullLast_v then
                            NumFull <= NumFull + 1;
                        else
                            NumBuf <= NumBuf + 1;
                        end if;
                    else
                        check_value(RxSet_v = RxSetLast_v, error, "Receiver masks stable during GTRXRESET");
                    end if;
                    if GtRxMode = RxModeSeq_c then
                        check_value(GtRxPma, "1111111", error, "Entire receiver reset: PMA mask");
                        check_value(GtRxPcs, "11111", error, "Entire receiver reset: PCS mask");
                        check_value(GtPcs(9 downto 8), "11", error, "Entire receiver reset: PCSRSVDIN[9:8]");
                    else
                        check_value(GtRxMode, RxModeSgl_c, error, "Buffer reset: single mode");
                        check_value(GtRxPma, "0000000", error, "Buffer reset: PMA mask");
                        check_value(GtRxPcs, "00100", error, "Buffer reset: PCS mask (elastic buffer)");
                        check_value(GtPcs, x"0000", error, "Buffer reset: PCSRSVDIN");
                    end if;
                    RxHigh_v := RxHigh_v + 1;
                elsif RxHigh_v /= 0 then
                    check_value(RxHigh_v, Pulse_c, error, "GTRXRESET pulse width");
                    RxHigh_v  := 0;
                    RxFell_v  := 0;
                    RxAfter_v := true;
                end if;

                -- Receiver masks after the pulse: held until the reset done or the timeout (sequential mode, the
                -- end of the receiver reset comes with one of the events) or for the hold time (single mode)
                if RxAfter_v and GtRxRst = '0' then
                    if FullLast_v then
                        if RxBusy = '1' then
                            check_value(RxSet_v = RxSetLast_v, error, "Receiver masks held during the receiver reset");
                        else
                            check_value(EvDone = '1' or EvTimeo = '1', error,
                                        "Receiver reset ends with the reset done or the timeout event");
                            RxAfter_v := false;
                        end if;
                    elsif RxSet_v /= RxSetLast_v then
                        check_value(RxFell_v >= Hold_c, error, "Receiver masks held after a single-mode reset");
                        RxAfter_v := false;
                    end if;
                    RxFell_v := RxFell_v + 1;
                end if;

                -- Transmitter reset pulse
                if GtTxRst = '1' then
                    if TxHigh_v = 0 then
                        check_value(TxAge_v >= Setup_c, error, "Transmitter masks set before GTTXRESET");
                        NumTx <= NumTx + 1;
                    else
                        check_value(TxSet_v = TxSetLast_v, error, "Transmitter masks stable during GTTXRESET");
                    end if;
                    check_value(GtTxMode, RxModeSgl_c, error, "Transmit buffer reset: single mode");
                    check_value(GtTxPma, "000", error, "Transmit buffer reset: PMA mask");
                    check_value(GtTxPcs, '1', error, "Transmit buffer reset: PCS mask");
                    check_value(GtPcs, x"0000", error, "Transmit buffer reset: PCSRSVDIN");
                    check_value(std_logic_vector'(GtRxMode & GtRxPma & GtRxPcs), "00" & "1111111" & "11111", error,
                                "Transmit buffer reset: receiver masks unchanged");
                    TxHigh_v := TxHigh_v + 1;
                elsif TxHigh_v /= 0 then
                    check_value(TxHigh_v, Pulse_c, error, "GTTXRESET pulse width");
                    TxHigh_v  := 0;
                    TxFell_v  := 0;
                    TxAfter_v := true;
                end if;
                if TxAfter_v and GtTxRst = '0' then
                    if TxSet_v /= TxSetLast_v then
                        check_value(TxFell_v >= Hold_c, error, "Transmitter masks held after GTTXRESET");
                        TxAfter_v := false;
                    end if;
                    TxFell_v := TxFell_v + 1;
                end if;

                -- CDR reset pulse
                if GtCdrRst = '1' then
                    if CdrHigh_v = 0 then
                        NumCdr <= NumCdr + 1;
                    end if;
                    CdrHigh_v := CdrHigh_v + 1;
                elsif CdrHigh_v /= 0 then
                    check_value(CdrHigh_v, Pulse_c, error, "RXCDRRESET pulse width");
                    CdrHigh_v := 0;
                end if;

                -- Single-cycle events
                if EvDone = '1' then
                    NumDone <= NumDone + 1;
                    check_value(EvLast_v(0), '0', error, "Reset done event lasts one cycle");
                end if;
                if EvTimeo = '1' then
                    NumTimeo <= NumTimeo + 1;
                    check_value(EvLast_v(1), '0', error, "Timeout event lasts one cycle");
                end if;
                check_value(not (EvDone = '1' and EvTimeo = '1'), error, "Reset done and timeout not together");
            else
                RxHigh_v  := 0;
                TxHigh_v  := 0;
                CdrHigh_v := 0;
                RxAfter_v := false;
                TxAfter_v := false;
            end if;

            if RxSet_v = RxSetLast_v then
                RxAge_v := RxAge_v + 1;
            else
                RxAge_v := 1;
            end if;
            if TxSet_v = TxSetLast_v then
                TxAge_v := TxAge_v + 1;
            else
                TxAge_v := 1;
            end if;
            RxSetLast_v := RxSet_v;
            TxSetLast_v := TxSet_v;
            EvLast_v    := EvTimeo & EvDone;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable T_v       : time;
        variable Full_v    : natural;
        variable Buf_v     : natural;
        variable Tx_v      : natural;
        variable Done_v    : natural;
        variable Timeo_v   : natural;
        variable Elapsed_v : natural;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- The monitor counts an event at the clock edge after it: wait for two edges and the updates
        procedure settle is
        begin
            cycles(2);
            wait for 1 ns;
        end procedure;

        -- Counts of the monitor; a negative expectation is not checked
        procedure checkCounts (full, buf, tx, cdr, done, timeo : integer; msg : string) is
        begin
            if full >= 0 then
                check_value(NumFull, full, error, msg & ": entire receiver resets");
            end if;
            if buf >= 0 then
                check_value(NumBuf, buf, error, msg & ": buffer resets");
            end if;
            if tx >= 0 then
                check_value(NumTx, tx, error, msg & ": transmit buffer resets");
            end if;
            if cdr >= 0 then
                check_value(NumCdr, cdr, error, msg & ": CDR resets");
            end if;
            if done >= 0 then
                check_value(NumDone, done, error, msg & ": reset done events");
            end if;
            if timeo >= 0 then
                check_value(NumTimeo, timeo, error, msg & ": timeout events");
            end if;
        end procedure;

        -- Request pulses of two cycles (rising edges)
        procedure pulseFull is
        begin
            wait until rising_edge(Clk);
            ReqFull <= '1';
            cycles(2);
            ReqFull <= '0';
        end procedure;

        procedure pulseBuf is
        begin
            wait until rising_edge(Clk);
            ReqBuf <= '1';
            cycles(2);
            ReqBuf <= '0';
        end procedure;

        procedure setTxErr is
        begin
            wait until rising_edge(Clk);
            TxErrSet <= '1';
            wait until rising_edge(Clk);
            TxErrSet <= '0';
        end procedure;

        -- Port values outside the sequences
        procedure checkIdle (pcs : std_logic_vector(15 downto 0); msg : string) is
        begin
            check_value(std_logic_vector'(GtRxRst & GtCdrRst & GtTxRst), "000", error, msg & ": no reset pulse");
            check_value(std_logic_vector'(GtRxMode & GtRxPma & GtRxPcs), "00" & "1111111" & "11111", error,
                        msg & ": receiver in sequential mode, all masks set");
            check_value(std_logic_vector'(GtTxMode & GtTxPma & GtTxPcs), "00" & "111" & "1", error,
                        msg & ": transmitter in sequential mode, all masks set");
            check_value(GtPcs, pcs, error, msg & ": PCSRSVDIN base value");
            check_value(std_logic_vector'(RxBusy & BufBusy), "00", error, msg & ": not busy");
        end procedure;

        -- Wait until the sequencer is idle (outputs idle for longer than the holdoff)
        procedure waitIdle (maxCycles : natural; msg : string) is
            variable Quiet_v : natural := 0;
        begin

            for i in 1 to maxCycles loop
                wait until rising_edge(Clk);
                if GtRxRst = '0' and GtTxRst = '0' and GtCdrRst = '0' and RxBusy = '0' and BufBusy = '0' and
                   GtRxMode = RxModeSeq_c and GtTxMode = RxModeSeq_c then
                    Quiet_v := Quiet_v + 1;
                else
                    Quiet_v := 0;
                end if;
                exit when Quiet_v > Holdoff_c + Setup_c + 4;
            end loop;

            check_value(Quiet_v > Holdoff_c + Setup_c + 4, error, msg & ": sequencer idle");
        end procedure;

        procedure resetDut is
        begin
            wait until rising_edge(Clk);
            Rst <= '1';
            cycles(5);
            Rst <= '0';
            cycles(2);
        end procedure;

        -- Wait for a rising edge of a signal within maxCycles, returns the cycles waited
        -- Wait for a level of a signal within maxCycles clock edges, returns the edges waited; the signals are read
        -- 1 ns after the edge
        procedure awaitLevel (
            signal s  : std_logic;
            lvl       : std_logic;
            maxCycles : natural;
            n         : out natural;
            msg       : string) is
            variable Cnt_v : natural := 0;
        begin

            while s /= lvl and Cnt_v < maxCycles loop
                wait until rising_edge(Clk);
                wait for 1 ns;
                Cnt_v := Cnt_v + 1;
            end loop;

            n := Cnt_v;
            check_value(s = lvl, error, msg);
        end procedure;

        procedure awaitHigh (signal s : std_logic; maxCycles : natural; n : out natural; msg : string) is
        begin
            awaitLevel(s, '1', maxCycles, n, msg);
        end procedure;

        procedure awaitLow (signal s : std_logic; maxCycles : natural; n : out natural; msg : string) is
        begin
            awaitLevel(s, '0', maxCycles, n, msg);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        resetDut;

        while test_suite loop

            -- TC-PA-19: entire receiver reset: requests wait for the receivers of the wizard; the sequence with the
            -- configured PCSRSVDIN base taken at its start; setup, pulse with PCSRSVDIN[10], masks and PCSRSVDIN[9:8]
            -- held until RXRESETDONE rises; reset done event; base value afterwards
            if run("test_full") then
                checkIdle(PcsDflt_c, "After the reset");
                CfgPcs     <= x"0040";
                MasterDone <= '0';
                pulseFull;
                cycles(50);
                check_value(NumFull, 0, error, "No sequence while the receivers of the wizard are not ready");
                checkIdle(PcsDflt_c, "Request pending");

                MasterDone <= '1';
                awaitHigh(RxBusy, 4, Elapsed_v, "Receiver reset starts when the receivers are ready");
                T_v        := now - RxBusy'last_event;
                check_value(GtPcs, x"0340", error, "Setup: PCSRSVDIN base with bits 9:8");
                check_value(GtRxRst, '0', error, "Setup: no pulse yet");
                awaitHigh(GtRxRst, Setup_c + 2, Elapsed_v, "GTRXRESET pulse");
                check_value(now - GtRxRst'last_event - T_v, Setup_c * Period_c, error,
                            "Setup time before GTRXRESET");
                check_value(GtPcs, x"0740", error, "Pulse: PCSRSVDIN with bits 10:8");
                T_v        := now - GtRxRst'last_event;
                awaitLow(GtRxRst, Pulse_c + 2, Elapsed_v, "End of the GTRXRESET pulse");
                check_value(now - GtRxRst'last_event - T_v, Pulse_c * Period_c, error, "GTRXRESET pulse width");
                check_value(GtPcs, x"0340", error, "Wait: PCSRSVDIN bits 9:8 held");
                check_value(RxBusy, '1', error, "Wait: receiver reset in progress");
                awaitLow(RxBusy, DoneRise_c + 5, Elapsed_v, "End of the receiver reset");
                check_value(Elapsed_v >= DoneRise_c and Elapsed_v <= DoneRise_c + 3, error,
                            "Receiver reset ends with RXRESETDONE");
                check_value(RxRstDone, '1', error, "RXRESETDONE high at the end");
                checkIdle(x"0040", "After the receiver reset");
                settle;
                checkCounts(1, 0, 0, 0, 1, 0, "One entire receiver reset");

                -- A request level held high starts one reset only (rising edges), also beyond the gap
                cycles(Gap_c);
                wait until rising_edge(Clk);
                ReqFull <= '1';
                waitIdle(DoneRise_c + 100, "Request level held");
                cycles(Gap_c + 50);
                ReqFull <= '0';
                settle;
                checkCounts(2, 0, 0, 0, 2, 0, "One reset per rising edge of the request");

            -- TC-PA-20: bounded waits: RXRESETDONE withheld after it fell (timeout after DoneHighCycles_g) and never
            -- falling (timeout after DoneLowCycles_g): timeout event, no reset done event, the masks released, the
            -- sequencer idle and serving a later request
            elsif run("test_timeout") then
                DoneMode <= Hang_s;
                pulseFull;
                awaitHigh(GtRxRst, Setup_c + 6, Elapsed_v, "GTRXRESET pulse");
                awaitLow(GtRxRst, Pulse_c + 2, Elapsed_v, "End of the GTRXRESET pulse");
                awaitHigh(EvTimeo, DoneHigh_c + 5, Elapsed_v, "Timeout of the wait for RXRESETDONE high");
                check_value(Elapsed_v >= DoneHigh_c and Elapsed_v <= DoneHigh_c + 3, error,
                            "Timeout after DoneHighCycles_g");
                checkIdle(PcsDflt_c, "After the timeout");
                settle;
                checkCounts(1, 0, 0, 0, 0, 1, "Timeout of the wait for RXRESETDONE high");

                -- A request in the gap after the timeout is dropped; the transceiver recovers
                cycles(Gap_c / 2);
                pulseFull;
                DoneMode <= Normal_s;
                waitIdle(Gap_c, "Request in the gap");
                checkCounts(1, 0, 0, 0, 0, 1, "Request in the gap after a timeout dropped");
                cycles(Gap_c);
                pulseFull;
                waitIdle(Setup_c + Pulse_c + DoneRise_c + 100, "Request after the gap");
                checkCounts(2, 0, 0, 0, 1, 1, "Request after the gap served, reset done");

                -- RXRESETDONE never falls
                cycles(Gap_c);
                DoneMode <= Stuck_s;
                pulseFull;
                awaitHigh(GtRxRst, Setup_c + 6, Elapsed_v, "GTRXRESET pulse");
                awaitLow(GtRxRst, Pulse_c + 2, Elapsed_v, "End of the GTRXRESET pulse");
                awaitHigh(EvTimeo, DoneLow_c + 5, Elapsed_v, "Timeout of the wait for RXRESETDONE low");
                check_value(Elapsed_v >= DoneLow_c and Elapsed_v <= DoneLow_c + 3, error,
                            "Timeout after DoneLowCycles_g");
                checkIdle(PcsDflt_c, "After the second timeout");
                settle;
                checkCounts(3, 0, 0, 0, 1, 2, "Timeout of the wait for RXRESETDONE low");
                DoneMode <= Normal_s;

            -- TC-PA-21: CDR-only receiver reset: RXCDRRESET pulse, no GTRXRESET, masks and PCSRSVDIN unchanged,
            -- receiver reset in progress for the pulse and the fixed wait, reset done event
            elsif run("test_cdr_only") then
                CfgCdrOnly <= '1';
                pulseFull;
                awaitHigh(RxBusy, 6, Elapsed_v, "CDR-only receiver reset starts");
                T_v        := now - RxBusy'last_event;
                check_value(GtCdrRst, '1', error, "RXCDRRESET with the start");
                awaitLow(RxBusy, Pulse_c + CdrWait_c + 5, Elapsed_v, "End of the CDR-only receiver reset");
                check_value(now - RxBusy'last_event - T_v, (Pulse_c + CdrWait_c) * Period_c, error,
                            "Pulse and wait of the CDR reset");
                checkIdle(PcsDflt_c, "After the CDR-only reset");
                check_value(RxRstDone, '1', error, "RXRESETDONE not affected");
                settle;
                checkCounts(0, 0, 0, 1, 1, 0, "One RXCDRRESET pulse, no GTRXRESET, reset done event");

                -- The gap applies to the CDR-only reset as well
                pulseFull;
                waitIdle(Gap_c / 2, "Request in the gap");
                checkCounts(0, 0, 0, 1, 1, 0, "Request in the gap after a CDR-only reset dropped");
                cycles(Gap_c);
                pulseFull;
                waitIdle(CdrWait_c + 100, "Request after the gap");
                checkCounts(0, 0, 0, 2, 2, 0, "Request after the gap served");
                CfgCdrOnly <= '0';

            -- TC-PA-22: transmit buffer reset: GTTXRESET in single mode on the transmit PCS while the transmit buffer
            -- error is set, PCSRSVDIN 0 for the sequence, receiver not affected; repeated after the holdoff while the
            -- error stays
            elsif run("test_tx_buffer") then
                setTxErr;
                awaitHigh(GtTxRst, Setup_c + 6, Elapsed_v, "GTTXRESET pulse");
                awaitLow(GtTxRst, Pulse_c + 2, Elapsed_v, "End of the GTTXRESET pulse");
                waitIdle(Hold_c + Holdoff_c + 50, "After the transmit buffer reset");
                checkCounts(0, 0, 1, 0, 0, 0, "One transmit buffer reset, no receiver reset event");
                check_value(TxErr, '0', error, "Transmit buffer error cleared");
                checkIdle(PcsDflt_c, "After the transmit buffer reset");

                -- Error stays: one reset per holdoff
                TxErrSticky <= true;
                setTxErr;
                cycles(5 * (Setup_c + Pulse_c + Hold_c + Holdoff_c) + 20);
                Tx_v        := NumTx - 1;
                check_value(Tx_v >= 5 and Tx_v <= 7, error,
                            "Transmit buffer reset repeated once per sequence and holdoff while the error stays");
                TxErrSticky <= false;
                waitIdle(Setup_c + Pulse_c + Hold_c + Holdoff_c + 50, "Error cleared");
                check_value(TxErr, '0', error, "Transmit buffer error cleared");

            -- TC-PA-23: receive elastic buffer reset: GTRXRESET in single mode on the elastic buffer, PCSRSVDIN 0,
            -- buffer reset window, no reset done needed; one sequence per rising edge, an edge during a sequence
            -- served afterwards
            elsif run("test_rx_buffer") then
                pulseBuf;
                awaitHigh(BufBusy, 6, Elapsed_v, "Buffer reset window starts");
                T_v := now - BufBusy'last_event;
                check_value(GtPcs, x"0000", error, "Buffer reset: PCSRSVDIN 0 from the setup");
                awaitLow(BufBusy, Setup_c + Pulse_c + Hold_c + 5, Elapsed_v, "End of the buffer reset window");
                check_value(now - BufBusy'last_event - T_v, (Setup_c + Pulse_c + Hold_c) * Period_c, error,
                            "Buffer reset window: setup, pulse and hold");
                waitIdle(Holdoff_c + 50, "After the buffer reset");
                checkCounts(0, 1, 0, 0, 0, 0, "One buffer reset, no receiver reset event");
                checkIdle(PcsDflt_c, "After the buffer reset");

                -- Level held high: one sequence; edges during a sequence: one more afterwards
                wait until rising_edge(Clk);
                ReqBuf <= '1';
                waitIdle(Setup_c + Pulse_c + Hold_c + Holdoff_c + 50, "Buffer request level held");
                cycles(50);
                ReqBuf <= '0';
                checkCounts(0, 2, 0, 0, 0, 0, "One buffer reset per rising edge");
                pulseBuf;
                awaitHigh(GtRxRst, Setup_c + 6, Elapsed_v, "Buffer reset pulse");
                pulseBuf;
                pulseBuf;
                waitIdle(2 * (Setup_c + Pulse_c + Hold_c + Holdoff_c) + 50, "Edges during a buffer reset");
                checkCounts(0, 4, 0, 0, 0, 0, "Edges during a buffer reset give one further buffer reset");

            -- TC-PA-24: priority of the requests (receiver reset before transmit buffer reset before buffer reset, the
            -- receiver reset includes the buffer), receiver reset requests during the reset and its gap dropped, the
            -- holdoff between two sequences, PCSRSVDIN taken at the start of the next sequence, a reset in a sequence
            elsif run("test_priority") then
                -- All three requests while the receivers of the wizard are not ready, PCSRSVDIN base 0
                CfgPcs     <= x"0000";
                MasterDone <= '0';
                wait until rising_edge(Clk);
                ReqFull    <= '1';
                ReqBuf     <= '1';
                TxErrSet   <= '1';
                wait until rising_edge(Clk);
                TxErrSet   <= '0';
                cycles(2);
                ReqFull    <= '0';
                ReqBuf     <= '0';
                cycles(10);
                MasterDone <= '1';
                awaitHigh(RxBusy, 4, Elapsed_v, "Receiver reset first");
                check_value(NumTx, 0, error, "Transmit buffer reset waits for the receiver reset");

                -- Receiver reset request during the receiver reset: dropped; buffer request: served afterwards
                awaitHigh(GtRxRst, Setup_c + 2, Elapsed_v, "GTRXRESET pulse");
                cycles(Pulse_c + 10);
                pulseFull;
                pulseBuf;
                awaitLow(RxBusy, DoneRise_c + 5, Elapsed_v, "End of the receiver reset");
                awaitHigh(GtTxRst, Holdoff_c + Setup_c + 4, Elapsed_v, "Transmit buffer reset second");
                check_value(Elapsed_v >= Holdoff_c + Setup_c, error, "Holdoff before the next sequence");
                awaitHigh(BufBusy, Pulse_c + Hold_c + Holdoff_c + 6, Elapsed_v, "Buffer reset third");
                check_value(Elapsed_v >= Hold_c + Holdoff_c, error, "Holdoff before the next sequence");
                waitIdle(Setup_c + Pulse_c + Hold_c + Holdoff_c + 50, "After the three sequences");
                checkCounts(1, 1, 1, 0, 1, 0,
                            "Receiver reset, transmit and buffer reset once each (the first buffer request absorbed)");
                checkIdle(x"0000", "After the three sequences");

                -- Receiver reset requests in the gap are dropped, after the gap served (gap from the reset done)
                Full_v := NumFull;
                pulseFull;
                waitIdle(50, "Request in the gap");
                checkCounts(Full_v, -1, -1, -1, -1, -1, "Request in the gap dropped");
                -- The gap ended Gap_c cycles after the reset done event; wait for its end
                cycles(Gap_c);
                CfgPcs <= x"0360";
                pulseFull;
                awaitHigh(RxBusy, 6, Elapsed_v, "Request after the gap served");
                check_value(GtPcs, x"0360", error, "New PCSRSVDIN base taken at the start of the sequence");
                awaitHigh(GtRxRst, Setup_c + 2, Elapsed_v, "GTRXRESET pulse");
                -- A change of the base during the sequence takes effect at the next sequence only
                CfgPcs <= x"0040";
                awaitLow(RxBusy, Pulse_c + DoneRise_c + 6, Elapsed_v, "End of the receiver reset");
                check_value(GtPcs, x"0360", error, "Base value unchanged until the next sequence");
                cycles(Holdoff_c + 4);
                pulseBuf;
                waitIdle(Setup_c + Pulse_c + Hold_c + Holdoff_c + 50, "Buffer reset");
                check_value(GtPcs, x"0040", error, "Base value of the next sequence");

                -- Reset of the sequencer in a receiver reset: ports at once to the values outside the sequences
                -- with the default base, no event; a request afterwards is served (gap cleared)
                Done_v  := NumDone;
                Timeo_v := NumTimeo;
                Buf_v   := NumBuf;
                cycles(Gap_c);
                pulseFull;
                awaitHigh(GtRxRst, Setup_c + 6, Elapsed_v, "GTRXRESET pulse");
                cycles(Pulse_c + 10);
                check_value(RxBusy, '1', error, "Receiver reset in progress");
                wait until rising_edge(Clk);
                Rst     <= '1';
                wait until rising_edge(Clk);
                wait for 1 ns;
                checkIdle(PcsDflt_c, "Reset in a receiver reset");
                cycles(3);
                Rst     <= '0';
                cycles(2);
                checkCounts(-1, -1, -1, -1, Done_v, Timeo_v, "No event from the reset");
                pulseFull;
                awaitHigh(RxBusy, 6, Elapsed_v, "Request after the reset served");
                waitIdle(Setup_c + Pulse_c + DoneRise_c + Holdoff_c + 50, "After the receiver reset");
                checkCounts(-1, Buf_v, -1, -1, Done_v + 1, Timeo_v, "Receiver reset after the reset");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

end architecture;
