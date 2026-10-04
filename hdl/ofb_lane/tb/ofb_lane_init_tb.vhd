---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the lane initialisation state machine (LN-1): every state, exit condition
-- and its precedence, driven with the events of the lane receiver and transmitter.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

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
    use work.ofb_lane_init_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_init_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_init_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

    -- ClearLine lasts ceil(2 us * 156.25 MHz) cycles
    constant ClearLineCycles_c : natural := 313;

    type RxKind_t is (
        KindData, KindRxErr, KindInit1, KindInit2, KindInvInit1, KindInvInit2, KindInit3, KindStandby,
        KindLostSignal, KindComma, KindSkip
    );

    -- Received words that start with the comma K28.7
    function commaOf (kind : RxKind_t) return std_logic is
    begin
        if kind = KindComma or kind = KindStandby or kind = KindLostSignal or kind = KindSkip then
            return '1';
        end if;
        return '0';
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Cnt_v : natural;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- One received word (event of the lane receiver) in one clock cycle; called at a falling edge,
        -- consecutive calls give one word per cycle
        procedure rxWord (
            kind  : RxKind_t;
            param : Char_t := x"00") is
        begin
            InitIn.Word       <= '1';
            InitIn.RxErr      <= '1' when kind = KindRxErr else '0';
            InitIn.Init1      <= '1' when kind = KindInit1 else '0';
            InitIn.Init2      <= '1' when kind = KindInit2 else '0';
            InitIn.InvInit1   <= '1' when kind = KindInvInit1 else '0';
            InitIn.InvInit2   <= '1' when kind = KindInvInit2 else '0';
            InitIn.Init3      <= '1' when kind = KindInit3 else '0';
            InitIn.Standby    <= '1' when kind = KindStandby else '0';
            InitIn.LostSignal <= '1' when kind = KindLostSignal else '0';
            InitIn.Skip       <= '1' when kind = KindSkip else '0';
            InitIn.Comma      <= commaOf(kind);
            InitIn.Param      <= param;
            wait until falling_edge(Clk);
            InitIn.Word       <= '0';
            InitIn.RxErr      <= '0';
            InitIn.Init1      <= '0';
            InitIn.Init2      <= '0';
            InitIn.InvInit1   <= '0';
            InitIn.InvInit2   <= '0';
            InitIn.Init3      <= '0';
            InitIn.Standby    <= '0';
            InitIn.LostSignal <= '0';
            InitIn.Skip       <= '0';
            InitIn.Comma      <= '0';
        end procedure;

        procedure rxWords (
            kind  : RxKind_t;
            n     : natural;
            param : Char_t := x"00") is
        begin

            for i in 1 to n loop
                rxWord(kind, param);
            end loop;

        end procedure;

        -- Words sent by the lane transmitter
        procedure txSent (
            kind : RxKind_t;
            n    : natural) is
        begin

            for i in 1 to n loop
                InitIn.Init3Sent   <= '1' when kind = KindInit3 else '0';
                InitIn.StandbySent <= '1' when kind = KindStandby else '0';
                InitIn.LostSent    <= '1' when kind = KindLostSignal else '0';
                wait until falling_edge(Clk);
                InitIn.Init3Sent   <= '0';
                InitIn.StandbySent <= '0';
                InitIn.LostSent    <= '0';
            end loop;

        end procedure;

        procedure checkState (
            state : LaneState_t;
            msg   : string) is
        begin
            check_value(InitOut.State, state, error, msg);
        end procedure;

        procedure waitState (
            state  : LaneState_t;
            maxCyc : natural;
            msg    : string) is
        begin

            for i in 0 to maxCyc loop
                exit when InitOut.State = state;
                cycles(1);
            end loop;

            checkState(state, msg);
        end procedure;

        -- Disabled -> Wait -> Started with LaneStart and a signal
        procedure goStarted is
        begin
            InitIn.LaneStart <= '1';
            InitIn.NoSignal  <= '0';
            waitState(LaneStateStarted_c, ClearLineCycles_c + 10, "Started");
        end procedure;

        -- Started -> Connecting -> Connected -> Active with the normal handshake
        procedure goActive is
        begin
            goStarted;
            rxWord(KindInit1);
            rxWords(KindData, 1022);
            waitState(LaneStateConnecting_c, 2, "Connecting after 1023 words with INIT1");
            rxWords(KindInit2, 3);
            waitState(LaneStateConnected_c, 2, "Connected after three INIT2");
            txSent(KindInit3, 3);
            rxWords(KindInit3, 3, x"0A");
            waitState(LaneStateActive_c, 2, "Active after three INIT3 received and sent");
        end procedure;

        procedure checkEnables (
            tx  : std_logic;
            rx  : std_logic;
            cdr : std_logic;
            msg : string) is
        begin
            check_value(InitOut.TxEnable, tx, error, "Transmitter enable: " & msg);
            check_value(InitOut.RxEnable, rx, error, "Receiver enable: " & msg);
            check_value(InitOut.CdrEnable, cdr, error, "CDR enable: " & msg);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        wait until Rst = '0';
        wait until falling_edge(Clk);

        while test_suite loop

            -- TC-LN-20: ClearLine lasts 2 us with everything disabled, then Disabled
            if run("test_clearline") then
                checkState(LaneStateClearLine_c, "ClearLine after reset");
                checkEnables('0', '0', '0', "ClearLine");
                check_value(InitOut.SyncReset, '1', error, "Receiver in LostSync");
                cycles(ClearLineCycles_c - 5);
                checkState(LaneStateClearLine_c, "Still ClearLine before 2 us");
                cycles(10);
                checkState(LaneStateDisabled_c, "Disabled after 2 us");
                checkEnables('0', '0', '0', "Disabled");

            -- TC-LN-21: Disabled / Wait / Started with LaneStart, AutoStart and NoSignal
            elsif run("test_wait") then
                waitState(LaneStateDisabled_c, ClearLineCycles_c + 5, "Disabled");
                InitIn.AutoStart <= '1';
                cycles(2);
                checkState(LaneStateWait_c, "Wait with AutoStart");
                checkEnables('0', '1', '0', "Wait (NoSignal detection only)");
                cycles(100);
                checkState(LaneStateWait_c, "Wait while NoSignal");
                InitIn.AutoStart <= '0';
                cycles(2);
                checkState(LaneStateDisabled_c, "Back to Disabled without LaneStart and AutoStart");
                InitIn.AutoStart <= '1';
                cycles(2);
                InitIn.NoSignal  <= '0';
                cycles(2);
                checkState(LaneStateStarted_c, "Started when a signal is present");
                checkEnables('1', '1', '1', "Started");
                check_value(InitOut.TxMode, TxModeInit1_c, error, "INIT1 sent in Started");

            -- TC-LN-22: Started -> Connecting after 1023 words with an INIT1, RXERR restarts the count
            elsif run("test_started_1023") then
                goStarted;
                rxWords(KindData, 1100);
                checkState(LaneStateStarted_c, "No Connecting without INIT1 or INIT2");
                rxWord(KindRxErr);
                rxWord(KindInit2);
                rxWords(KindData, 500);
                rxWord(KindRxErr);
                checkState(LaneStateStarted_c, "RXERR restarts the count");
                rxWord(KindInit1);
                rxWords(KindData, 1021);
                checkState(LaneStateStarted_c, "Not yet 1023 words since the RXERR");
                rxWord(KindData);
                cycles(1);
                checkState(LaneStateConnecting_c, "Connecting with the 1023rd word");
                check_value(InitOut.TxMode, TxModeInit2_c, error, "INIT2 sent in Connecting");

            -- TC-LN-23: three iINIT1 select InvertRxPolarity; ClearLine switches the inversion off
            elsif run("test_invert_polarity") then
                goStarted;
                rxWords(KindInvInit1, 2);
                rxWord(KindRxErr);
                rxWords(KindInvInit1, 2);
                checkState(LaneStateStarted_c, "RXERR between the iINIT1");
                rxWord(KindInvInit1);
                cycles(1);
                checkState(LaneStateInvertRxPol_c, "InvertRxPolarity after three iINIT1");
                check_value(InitOut.RxInvert, '1', error, "Received bits inverted");
                check_value(InitOut.RxPolarity, '1', error, "RX polarity status");
                check_value(InitOut.TxMode, TxModeInit1_c, error, "INIT1 sent in InvertRxPolarity");
                InitIn.NoSignal <= '1';
                cycles(2);
                checkState(LaneStateClearLine_c, "NoSignal in InvertRxPolarity: ClearLine");
                cycles(2);
                check_value(InitOut.RxInvert, '0', error, "Inversion off in ClearLine");

            -- TC-LN-24: FarEndActive moves Started to Connecting to Connected, Active after one INIT3 sent
            elsif run("test_far_end_active") then
                goStarted;
                InitIn.FarEndActive <= '1';
                cycles(1);
                checkState(LaneStateConnecting_c, "Connecting on FarEndActive");
                cycles(1);
                checkState(LaneStateConnected_c, "Connected on FarEndActive");
                cycles(5);
                checkState(LaneStateConnected_c, "No Active before an INIT3 was sent");
                txSent(KindInit3, 1);
                cycles(1);
                checkState(LaneStateActive_c, "Active after one INIT3 sent");

            -- TC-LN-25: RxOnly: transmitter disabled, Connecting -> Connected -> Active on RxOnly
            elsif run("test_rxonly") then
                InitIn.RxOnly <= '1';
                goStarted;
                checkEnables('0', '1', '1', "Started with RxOnly");
                rxWord(KindInit1);
                rxWords(KindData, 1022);
                cycles(3);
                checkState(LaneStateActive_c, "RxOnly passes Connecting and Connected");
                checkEnables('0', '1', '1', "Active with RxOnly");
                rxWord(KindInit1);
                cycles(2);
                checkState(LaneStateActive_c, "INIT1 ignored with RxOnly");

            -- TC-LN-26: TxOnly: receiver and CDR disabled, NoSignal ignored
            elsif run("test_txonly") then
                goActive;
                InitIn.TxOnly      <= '1';
                cycles(2);
                checkEnables('1', '0', '0', "Active with TxOnly");
                check_value(InitOut.SyncReset, '1', error, "Receiver in LostSync with TxOnly");
                InitIn.NoSignal    <= '1';
                InitIn.ErrOverflow <= '1';
                cycles(5);
                checkState(LaneStateActive_c, "NoSignal and RXERR overflow ignored with TxOnly");

            -- TC-LN-27: a comma received in Connected moves to ClearLine
            elsif run("test_connected_comma") then
                goStarted;
                rxWord(KindInit1);
                rxWords(KindData, 1022);
                rxWords(KindInit2, 3);
                waitState(LaneStateConnected_c, 2, "Connected");
                rxWord(KindComma);
                cycles(1);
                checkState(LaneStateClearLine_c, "ClearLine on K28.7 in Connected");

            -- TC-LN-28: INIT3 with the same parameters; the capability is reported once
            elsif run("test_init3") then
                InitIn.NearCap <= x"05";
                goStarted;
                check_value(InitOut.TxCap, x"07", error, "INIT3LaneStart flag set from LaneStart");
                rxWord(KindInit1);
                rxWords(KindData, 1022);
                rxWords(KindInit2, 3);
                waitState(LaneStateConnected_c, 2, "Connected");
                txSent(KindInit3, 3);
                rxWords(KindInit3, 2, x"11");
                rxWord(KindInit3, x"12");
                rxWords(KindInit3, 1, x"12");
                rxWord(KindRxErr);
                rxWords(KindInit3, 2, x"12");
                checkState(LaneStateConnected_c, "No three identical INIT3 without RXERR yet");
                Cnt_v          := 0;
                rxWord(KindInit3, x"12");
                check_value(InitOut.FarCapValid, '1', error, "Capability event");
                check_value(InitOut.FarCap, x"12", error, "Capability of the three INIT3");
                cycles(1);
                checkState(LaneStateActive_c, "Active after three identical INIT3");

            -- TC-LN-29: Active exit conditions and their order, LOS_Cause
            elsif run("test_active_exits") then
                goActive;
                check_value(InitOut.Active, '1', error, "Receiver in Active");
                -- NoSignal has precedence over the RXERR overflow
                InitIn.NoSignal    <= '1';
                InitIn.ErrOverflow <= '1';
                cycles(2);
                checkState(LaneStateLossOfSignal_c, "LossOfSignal on NoSignal");
                check_value(InitOut.LosCause, LosCauseNoSignal_c, error, "LOS_Cause 0b00");
                check_value(InitOut.TxMode, TxModeLostSignal_c, error, "LOST_SIGNAL sent");
                check_value(InitOut.ErrClear, '0', error, "RXERR counter not cleared in LossOfSignal");
                txSent(KindLostSignal, 31);
                checkState(LaneStateLossOfSignal_c, "Still LossOfSignal after 31 LOST_SIGNAL");
                txSent(KindLostSignal, 1);
                cycles(1);
                checkState(LaneStateClearLine_c, "ClearLine after 32 LOST_SIGNAL");
                InitIn.NoSignal    <= '0';
                InitIn.ErrOverflow <= '0';
                goActive;
                InitIn.ErrOverflow <= '1';
                cycles(2);
                checkState(LaneStateLossOfSignal_c, "LossOfSignal on RXERR overflow");
                check_value(InitOut.LosCause, LosCauseRxErr_c, error, "LOS_Cause 0b01");
                InitIn.ErrOverflow <= '0';
                txSent(KindLostSignal, 32);
                cycles(1);
                goActive;
                rxWord(KindInit1);
                cycles(1);
                checkState(LaneStateLossOfSignal_c, "LossOfSignal on INIT1");
                check_value(InitOut.LosCause, LosCauseInit1_c, error, "LOS_Cause 0b10");

            -- TC-LN-30: PrepareStandby sends 32 STANDBY words; three LOST_SIGNAL / STANDBY in Active
            elsif run("test_standby_and_stop") then
                goActive;
                InitIn.LaneStart <= '0';
                cycles(2);
                checkState(LaneStatePrepareStandby_c, "PrepareStandby");
                check_value(InitOut.TxMode, TxModeStandby_c, error, "STANDBY sent");
                txSent(KindStandby, 32);
                cycles(1);
                checkState(LaneStateClearLine_c, "ClearLine after 32 STANDBY");
                -- Three consecutive LOST_SIGNAL, SKIP is transparent, other words restart the count
                goActive;
                rxWords(KindLostSignal, 2);
                rxWord(KindData);
                rxWords(KindLostSignal, 2);
                checkState(LaneStateActive_c, "Two consecutive LOST_SIGNAL are not enough");
                rxWord(KindSkip);
                rxWord(KindLostSignal);
                cycles(1);
                checkState(LaneStateClearLine_c, "Three consecutive LOST_SIGNAL (SKIP between)");

            -- TC-LN-31: initialisation timeout in Started and Connected
            elsif run("test_timeout") then
                goStarted;
                cycles(TbInitTimeoutWords_c - 10);
                checkState(LaneStateStarted_c, "Before the timeout");
                Cnt_v := 0;

                for i in 1 to 20 loop
                    if InitOut.Timeout = '1' then
                        Cnt_v := Cnt_v + 1;
                    end if;
                    cycles(1);
                end loop;

                check_value(Cnt_v, 1, error, "One timeout event");
                checkState(LaneStateClearLine_c, "ClearLine after the timeout");
                -- The timer runs from Started on, also in Connected
                waitState(LaneStateStarted_c, ClearLineCycles_c + 10, "Started again");
                rxWord(KindInit1);
                rxWords(KindData, 1022);
                rxWords(KindInit2, 3);
                checkState(LaneStateConnected_c, "Connected");
                waitState(LaneStateClearLine_c, TbInitTimeoutWords_c, "Timeout in Connected");

            -- TC-LN-32: RXERR counter clear on LaneReset and in Connected only
            elsif run("test_errclear") then
                check_value(InitOut.ErrClear, '0', error, "No clear in ClearLine without LaneReset");
                goStarted;
                check_value(InitOut.ErrClear, '0', error, "No clear in Started");
                rxWord(KindInit1);
                rxWords(KindData, 1022);
                rxWords(KindInit2, 3);
                checkState(LaneStateConnected_c, "Connected");
                check_value(InitOut.ErrClear, '1', error, "Clear in Connected");
                txSent(KindInit3, 3);
                rxWords(KindInit3, 3, x"00");
                cycles(1);
                checkState(LaneStateActive_c, "Active");
                check_value(InitOut.ErrClear, '0', error, "No clear in Active");
                InitIn.CtrlLaneReset <= '1';
                cycles(1);
                check_value(InitOut.ErrClear, '1', error, "Clear on LaneReset");
                cycles(1);
                InitIn.CtrlLaneReset <= '0';
                checkState(LaneStateClearLine_c, "LaneReset of the Multi-Lane layer: ClearLine");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_lane_init_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
