---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Row-level testbench of the Data Link layer: the testbench is the far end at the row interface
-- and checks the transmitted words exactly (idle frames, FCT, FULL, ACK spacing, RETRY and resend
-- order) and the reaction to received words (data word identification, CRC and sequence errors,
-- receive error state machine, ECSS examples, credit, link reset rules of the VC buffers).
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
    use work.ofb_dl_pkg.all;
    use work.ofb_dl_row_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_row_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_dl_row_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Got_v   : KWord_t;
        variable Kind_v  : DlKind_t;
        variable State_v : std_logic_vector(15 downto 0);
        variable Cnt_v   : natural;
        variable Pos_v   : integer;
        variable Last_v  : integer;
        variable Seq_v   : natural;
        variable Idx_v   : natural;
        variable N_v     : natural;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        procedure waitLinkInit (timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;

            while RowStat.LinkState /= "11" loop
                cycles(1);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for Link Initialised");
                    exit;
                end if;
            end loop;

        end procedure;

        procedure waitErbEmpty (timeout : time) is
            variable Start_v : time;
        begin
            Start_v := now;

            while RowStat.ErbEmpty /= '1' loop
                cycles(1);
                if now - Start_v > timeout then
                    alert(error, "Timeout waiting for an empty error recovery buffer");
                    exit;
                end if;
            end loop;

        end procedure;

        -- Words into the receive rows
        procedure rxWord (
            word   : Word_t;
            k      : WordK_t   := KCtrl_c;
            crcErr : std_logic := '0') is
        begin
            RxQueue_v.push(crcErr & k & word);
        end procedure;

        procedure rxData (word : Word_t) is
        begin
            RxQueue_v.push('0' & KData_c & word);
        end procedure;

        -- Data frame of n words for a VC with a sequence number (data words count up from base)
        procedure rxFrame (
            vc     : natural;
            n      : natural;
            seq    : natural;
            pol    : std_logic := '0';
            base   : natural   := 0;
            crcErr : std_logic := '0') is
        begin
            rxWord(wordSdf(std_logic_vector(to_unsigned(vc, 5))));

            for i in 0 to n-1 loop
                rxData(std_logic_vector(to_unsigned(base + i, 32)));
            end loop;

            rxWord(wordEdf(pol & std_logic_vector(to_unsigned(seq, 7)), x"0000"), KCtrl_c, crcErr);
        end procedure;

        procedure rxFct (
            vc   : natural;
            seq  : natural;
            pol  : std_logic := '0';
            mult : natural   := 0) is
        begin
            rxWord(wordFct(std_logic_vector(to_unsigned(mult, 3)), std_logic_vector(to_unsigned(vc, 5)),
                           pol & std_logic_vector(to_unsigned(seq, 7))));
        end procedure;

        procedure waitRxIdle is
        begin

            while RxQueue_v.count > 0 loop
                cycles(1);
            end loop;

            cycles(10);
        end procedure;

        -- Words for a transmit VC: n data words, the last one with EOP and Fills
        procedure userPacket (
            vc   : natural;
            n    : positive;
            base : natural := 0) is
            variable Word_v : std_logic_vector(36 downto 0);
        begin

            for i in 0 to n-1 loop
                if i = n-1 then
                    Word_v := '0' & "1111" & CharFill_c & CharFill_c & CharFill_c & CharEop_c;
                else
                    Word_v := '0' & KData_c & std_logic_vector(to_unsigned(base + i, 32));
                end if;
                if vc = 0 then
                    VcTxQueue0_v.push(Word_v);
                else
                    VcTxQueue1_v.push(Word_v);
                end if;
            end loop;

        end procedure;

        -- Kind of a logged transmitted word
        impure function txKind (idx : natural) return DlKind_t is
            variable Word_v : KWord_t;
        begin
            Word_v := TxLog_v.get(idx);
            return dlWordKind(Word_v(31 downto 0), Word_v(35 downto 32));
        end function;

        impure function txWord (idx : natural) return Word_t is
            variable Word_v : KWord_t;
        begin
            Word_v := TxLog_v.get(idx);
            return Word_v(31 downto 0);
        end function;

        -- Index of the next transmitted word of a kind from idx on (-1: none)
        impure function txFind (
            kind : DlKind_t;
            idx  : natural) return integer is
        begin

            for i in idx to TxLog_v.count - 1 loop
                if txKind(i) = kind then
                    return i;
                end if;
            end loop;

            return -1;
        end function;

        -- Number of transmitted words of a kind
        impure function txCount (kind : DlKind_t) return natural is
            variable Cnt_v : natural;
        begin
            Cnt_v := 0;

            for i in 0 to TxLog_v.count - 1 loop
                if txKind(i) = kind then
                    Cnt_v := Cnt_v + 1;
                end if;
            end loop;

            return Cnt_v;
        end function;

        -- Number of data frame payload words in the log
        impure function txPayload return natural is
            variable Cnt_v : natural;
            variable In_v  : boolean;
        begin
            Cnt_v := 0;
            In_v  := false;

            for i in 0 to TxLog_v.count - 1 loop
                if txKind(i) = KindSdf then
                    In_v := true;
                elsif txKind(i) = KindEdf or txKind(i) = KindRetry then
                    In_v := false;
                elsif txKind(i) = KindData and In_v then
                    Cnt_v := Cnt_v + 1;
                end if;
            end loop;

            return Cnt_v;
        end function;

        procedure regWrite (
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            RegWrAddr <= addr;
            RegWrData <= data;
            RegWrCnt  <= RegWrCnt + 1;
            cycles(4);
        end procedure;

        procedure schedule (slot : natural) is
        begin
            SchedSlot <= std_logic_vector(to_unsigned(slot, 6));
            SchedCnt  <= SchedCnt + 1;
            cycles(20);
        end procedure;

        impure function seqOf (word : Word_t) return natural is
        begin
            return to_integer(unsigned(word(22 downto 16)));
        end function;

        -- Broadcast frame with a correct CRC-8: SBF, two data words, EBF with the sequence number
        procedure rxBroadcast (
            seq  : natural;
            data : std_logic_vector(63 downto 0)) is
            variable Crc_v : Char_t;
            variable Ebf_v : Word_t;
        begin
            Crc_v := crc8Chars(Crc8Seed_c, wordSbf(x"07", x"21"), 4);
            Crc_v := crc8Chars(Crc_v, data(31 downto 0), 4);
            Crc_v := crc8Chars(Crc_v, data(63 downto 32), 4);
            Ebf_v := wordEbf("00", std_logic_vector(to_unsigned(seq, 8)), x"00");
            Ebf_v := wordEbf("00", std_logic_vector(to_unsigned(seq, 8)), crc8Chars(Crc_v, Ebf_v, 3));
            rxWord(wordSbf(x"07", x"21"));
            rxData(data(31 downto 0));
            rxData(data(63 downto 32));
            rxWord(Ebf_v);
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

            -- TC-DL-10: FCTs after link reset, idle frames with the ECSS PRBS, FULL
            if run("test_tx_idle_fct") then
                waitLinkInit(10 us);
                cycles(400);
                -- Two FCTs per VC (128 words of input buffer), sequence 1 to 4, positive polarity
                Pos_v := txFind(KindFct, 0);

                for i in 1 to 4 loop
                    check_value(Pos_v >= 0, error, "FCT " & to_string(i));
                    Got_v := TxLog_v.get(Pos_v);
                    check_value(Got_v(31 downto 0), wordFct("000", Got_v(12 downto 8), std_logic_vector(to_unsigned(i, 8))),
                                error, "FCT " & to_string(i) & ": multiplier, sequence number, CRC-8");
                    Pos_v := txFind(KindFct, Pos_v + 1);
                end loop;

                check_value(Pos_v, -1, error, "No further FCT");
                -- The FCT queue of the error recovery buffer (4 items) was full: FULL with sequence 4
                Pos_v := txFind(KindFull, 0);
                check_value(Pos_v >= 0, error, "FULL sent");
                check_value(txWord(Pos_v), wordFull(x"04"), error, "FULL with the current sequence number");
                -- Idle frames: SIF with the current sequence number (0 before the FCTs, 4 after them),
                -- 64 PRBS words of the ECSS sequence from the seed, continued from frame to frame
                Pos_v   := txFind(KindSif, 0);
                check_value(txWord(Pos_v), wordSif(x"00"), error, "First SIF");
                Idx_v   := txFind(KindSif, txFind(KindFull, 0));
                check_value(txWord(Idx_v), wordSif(x"04"), error, "SIF after the FCTs");
                State_v := PrbsEcssSeed_c;
                Cnt_v   := 0;
                N_v     := 0;
                Idx_v   := Pos_v + 1;

                while Idx_v < TxLog_v.count and N_v < 3 loop
                    Kind_v := txKind(Idx_v);
                    if Kind_v = KindData then
                        check_value(txWord(Idx_v), prbsWord(State_v), error, "PRBS word " & to_string(Cnt_v));
                        State_v := prbsNextState(State_v);
                        Cnt_v   := Cnt_v + 1;
                    elsif Kind_v = KindSif then
                        check_value(Cnt_v, 64, error, "64 PRBS words per idle frame");
                        Cnt_v := 0;
                        N_v   := N_v + 1;
                    end if;
                    Idx_v := Idx_v + 1;
                end loop;

                check_value(N_v, 3, error, "Three idle frames checked");

            -- TC-DL-11: received frames are acknowledged, at least 15 words between two ACKs
            elsif run("test_ack_spacing") then
                waitLinkInit(10 us);
                cycles(400);
                TxLog_v.clear;

                for i in 1 to 6 loop
                    rxFrame(0, 2, i, '0', 10 * i);
                end loop;

                waitRxIdle;
                cycles(100);
                check_value(VcRxLog0_v.count, 12, error, "Data words delivered");
                check_value(RowStat.RxErrState, "00", error, "Valid Positive");
                Last_v := -100;
                Pos_v  := txFind(KindAck, 0);
                N_v    := 0;

                while Pos_v >= 0 loop
                    check_value(Pos_v - Last_v >= 16, error, "At least 15 words between two ACKs");
                    Last_v := Pos_v;
                    N_v    := N_v + 1;
                    Pos_v  := txFind(KindAck, Pos_v + 1);
                end loop;

                check_value(N_v >= 1 and N_v < 6, error, "ACKs combined");
                check_value(txWord(Last_v), wordAck(x"06"), error, "Last ACK with the Receive Sequence Number");

            -- TC-DL-12: receive errors, NACK, receive error state machine
            elsif run("test_rx_errors") then
                waitLinkInit(10 us);
                cycles(400);
                -- Frame 1 accepted
                rxFrame(0, 3, 1);
                waitRxIdle;
                -- RXERR inside a data frame: NACK with positive polarity, Error Negative
                TxLog_v.clear;
                rxWord(wordSdf("00000"));
                rxData(x"11111111");
                rxWord(WordRxErr_c);
                waitRxIdle;
                Pos_v := txFind(KindNack, 0);
                check_value(Pos_v >= 0, error, "NACK after RXERR in a data frame");
                check_value(txWord(Pos_v), wordNack(x"01"), error, "NACK with the Receive Sequence Number");
                check_value(RowStat.RxErrState, "11", error, "Error Negative");
                -- A frame with negative polarity is accepted: ACK with negative polarity, Valid Negative
                TxLog_v.clear;
                rxFrame(0, 3, 2, '1', 100);
                waitRxIdle;
                cycles(50);
                check_value(RowStat.RxErrState, "01", error, "Valid Negative");
                Pos_v := txFind(KindAck, 0);
                check_value(txWord(Pos_v), wordAck(x"82"), error, "ACK with negative polarity");
                check_value(VcRxLog0_v.count, 6, error, "Two frames delivered");
                -- RXERR in an idle frame: no NACK
                TxLog_v.clear;
                rxWord(wordSif(x"82"));
                rxData(x"12345678");
                rxWord(WordRxErr_c);
                waitRxIdle;
                cycles(50);
                check_value(txCount(KindNack), 0, error, "No NACK after RXERR in an idle frame");
                -- Sequence error: NACK, Error Positive (negative polarity flag inverted for the NACK)
                rxFrame(0, 1, 5, '1');
                waitRxIdle;
                cycles(50);
                check_value(RowStat.SeqErrs, 1, error, "Sequence error");
                check_value(RowStat.RxErrState, "10", error, "Error Positive");
                Pos_v := txFind(KindNack, 0);
                check_value(txWord(Pos_v), wordNack(x"82"), error, "NACK with negative polarity");
                -- CRC-16 error of a data frame (positive polarity now expected): NACK, frame discarded
                TxLog_v.clear;
                rxFrame(0, 2, 3, '0', 0, '1');
                waitRxIdle;
                cycles(50);
                check_value(RowStat.Crc16Errs, 1, error, "CRC-16 error");
                check_value(txCount(KindNack), 1, error, "NACK after a CRC-16 error");
                check_value(VcRxLog0_v.count, 6, error, "Frame with a CRC error discarded");
                -- FCT with a CRC-8 error outside a frame: no NACK
                TxLog_v.clear;
                rxWord(wordFct("000", "00000", x"03") xor x"01000000");
                waitRxIdle;
                cycles(50);
                check_value(RowStat.Crc8Errs, 1, error, "CRC-8 error");
                check_value(txCount(KindNack), 0, error, "No NACK for a CRC error outside a frame");
                -- Sequence error with the expected polarity in Error Positive: Error Negative
                rxFrame(0, 1, 9);
                waitRxIdle;
                cycles(50);
                check_value(RowStat.SeqErrs, 2, error, "Second sequence error");
                check_value(RowStat.RxErrState, "11", error, "Error Negative after a sequence error in Error Positive");
                -- Sequence error with the expected polarity in Error Negative: Error Positive
                rxFrame(0, 1, 13, '1');
                waitRxIdle;
                cycles(50);
                check_value(RowStat.SeqErrs, 3, error, "Third sequence error");
                check_value(RowStat.RxErrState, "10", error, "Error Positive after a sequence error in Error Negative");

            -- TC-DL-26: two out-of-sequence words in consecutive cycles with positive polarity (frame 2
            -- lost, EDF of frame 3 and its SIF back to back): one error recovery only, Error Negative,
            -- every NACK with positive polarity
            elsif run("test_seq_error_pair") then
                waitLinkInit(10 us);
                cycles(400);
                rxFrame(0, 3, 1);
                waitRxIdle;
                TxLog_v.clear;
                rxWord(wordSdf("00000"));
                rxData(x"00000005");
                rxWord(wordEdf(x"03", x"0000"));
                rxWord(wordSif(x"03"));
                waitRxIdle;
                cycles(50);
                check_value(RowStat.SeqErrs, 2, error, "Two sequence errors");
                check_value(RowStat.RxErrState, "11", error, "Error Negative after the pair");
                check_value(txCount(KindNack) > 0, error, "NACK sent");

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindNack then
                        check_value(txWord(i), wordNack(x"01"), error, "NACK with positive polarity");
                    end if;
                end loop;

            -- TC-DL-27: CRC-8 errors of SIF, FULL, ACK and NACK outside a frame are counted and the word
            -- is ignored (no NACK, no retry); an SIF inside a data frame and an EDF inside an idle frame
            -- are frame errors and the data frame is discarded
            elsif run("test_ctrl_word_errors") then
                waitLinkInit(10 us);
                cycles(400);
                rxFrame(0, 3, 1);
                waitRxIdle;
                TxLog_v.clear;
                rxWord(wordSif(x"01") xor x"01000000");
                rxWord(wordFull(x"01") xor x"01000000");
                rxWord(wordAck(x"00") xor x"01000000");
                rxWord(wordNack(x"00") xor x"01000000");
                waitRxIdle;
                cycles(50);
                check_value(RowStat.Crc8Errs, 4, error, "CRC-8 errors of SIF, FULL, ACK and NACK");
                check_value(txCount(KindNack), 0, error, "No NACK for CRC errors outside a frame");
                check_value(RowStat.Retries, 0, error, "NACK with a CRC error ignored");
                check_value(RowStat.RxErrState, "00", error, "Still Valid Positive");
                -- SIF inside a data frame
                rxWord(wordSdf("00000"));
                rxData(x"22222222");
                rxWord(wordSif(x"01"));
                waitRxIdle;
                cycles(50);
                check_value(RowStat.FrameErrs, 1, error, "SIF inside a data frame: frame error");
                -- EDF inside an idle frame
                rxWord(wordSif(x"01"));
                rxData(x"33333333");
                rxWord(wordEdf(x"02", x"0000"));
                waitRxIdle;
                cycles(50);
                check_value(RowStat.FrameErrs, 2, error, "EDF inside an idle frame: frame error");
                check_value(VcRxLog0_v.count, 3, error, "Only frame 1 delivered");
                -- The next frame is accepted
                rxFrame(0, 2, 2, '0', 10);
                waitRxIdle;
                cycles(50);
                check_value(VcRxLog0_v.count, 5, error, "Frame 2 delivered");

            -- TC-DL-28: Interface Reset: in Link Initialised it resets the link and the quality of service
            -- configuration (time-slots 32 to 63, idle limit); in CheckFarEnd and in NearEndReset it
            -- restarts the link reset state machine
            elsif run("test_interface_reset") then
                waitLinkInit(10 us);
                cycles(400);
                -- VC 0 not allocated to time-slot 33, idle limit of 16 words, writes without a register (an
                -- offset in the VC range, an address outside the QoS registers)
                regWrite(16#40C#, x"FFFFFFFD");
                regWrite(16#050#, x"00000010");
                regWrite(16#402#, x"00000000");
                regWrite(16#054#, x"FFFFFFFF");
                schedule(33);
                rxFct(0, 1);
                waitRxIdle;
                TxLog_v.clear;
                userPacket(0, 10, 0);
                cycles(500);
                check_value(txPayload, 0, error, "VC 0 waits in time-slot 33");

                -- The idle VC 1 reaches the credit limit after 16384 words, 16 words later it under-uses
                -- its bandwidth
                for k in 0 to 20000 loop
                    exit when RowStat.BwUnder(1) = '1';
                    cycles(1);
                end loop;

                check_value(RowStat.BwUnder(1), '1', error, "Idle VC 1 under-uses its bandwidth (idle limit 16)");
                -- Interface Reset in Link Initialised
                RowCfg.IfReset <= '1';
                cycles(1);
                RowCfg.IfReset <= '0';
                cycles(2);
                check_value(RowStat.LinkState /= "11", error, "Link reset by the Interface Reset");
                waitLinkInit(20 us);
                rxFct(0, 1);
                waitRxIdle;
                TxLog_v.clear;
                userPacket(0, 10, 100);
                cycles(1000);
                check_value(txPayload, 10, error, "VC 0 sends in time-slot 33 after the Interface Reset");
                cycles(18000);
                check_value(RowStat.BwUnder(1), '0', error, "Idle limit back to its reset value (156250 words)");
                -- Interface Reset in CheckFarEnd (far end silent), held for three cycles: CheckFarEnd,
                -- ConfigReset, NearEndReset, ConfigReset
                RowCfg.AutoCap   <= false;
                RowCfg.LinkReset <= '1';
                cycles(1);
                RowCfg.LinkReset <= '0';
                cycles(20);
                check_value(RowStat.LinkState, "10", error, "CheckFarEnd without the far end");
                RowCfg.IfReset   <= '1';
                cycles(3);
                RowCfg.IfReset   <= '0';
                cycles(20);
                check_value(RowStat.LinkState, "10", error, "CheckFarEnd after the Interface Reset");
                RowCfg.AutoCap   <= true;
                RowCfg.LinkReset <= '1';
                cycles(1);
                RowCfg.LinkReset <= '0';
                waitLinkInit(20 us);

            -- TC-DL-29: a data frame for a VC that the core does not implement is acknowledged and
            -- discarded; input VC buffer overflow: the far end sends more data than the credit allows while
            -- the user does not read: the overflow is reported and the link is reset
            elsif run("test_input_overflow") then
                waitLinkInit(10 us);
                cycles(400);
                rxFrame(5, 2, 1);
                rxFrame(0, 2, 2);
                waitRxIdle;
                cycles(100);
                check_value(VcRxLog0_v.count, 2, error, "Only the frame for VC 0 delivered");
                check_value(RowStat.SeqErrs + RowStat.FrameErrs, 0, error, "Frame for VC 5 accepted");
                check_value(RowStat.LinkState, "11", error, "No link reset for a frame to an unknown VC");
                RowCfg.RxReadyPct <= 0;

                for f in 0 to 2 loop
                    rxFrame(0, 64, 3 + f, '0', 100 * f);
                end loop;

                for k in 0 to 2000 loop
                    exit when RowStat.LinkState /= "11";
                    cycles(1);
                end loop;

                check_value(RowStat.LinkState /= "11", error, "Link reset after the input buffer overflow");
                check_value(RowStat.InputOvfs > 0, error, "Input buffer overflow reported");
                -- The buffer is reset; the packet that the user had started ends with an EEP, held until the
                -- user is ready
                cycles(200);
                check_value(VcRxLog0_v.count, 2, error, "Nothing read while the user is not ready");
                RowCfg.RxReadyPct <= 100;
                waitLinkInit(20 us);
                cycles(100);
                check_value(VcRxLog0_v.count, 3, error, "EEP after the link reset");
                check_value(VcRxLog0_v.get(2), "1111" & CharFill_c & CharFill_c & CharFill_c & CharEep_c, error, "EEP word");

            -- TC-DL-30: continuous mode flush while a segment is copied into the error recovery buffer
            -- (no lane active during the copy, ten offsets): the words copied so far form the segment,
            -- the rest of the packet is discarded, the link continues; a packet afterwards is complete
            elsif run("test_continuous_flush_copy") then
                waitLinkInit(10 us);
                regWrite(16#400#, x"00000103");
                cycles(50);
                TxLog_v.clear;

                -- Each try starts after a link reset (no credit left), the packet waits for the FCT
                for k in 0 to 9 loop
                    RowCfg.LinkReset  <= '1';
                    cycles(1);
                    RowCfg.LinkReset  <= '0';
                    waitLinkInit(20 us);
                    cycles(50);
                    userPacket(0, 60, 1000 * k);
                    cycles(100);
                    rxFct(0, 1);
                    cycles(10 + 12 * k);
                    RowCfg.LaneActive <= '0';
                    cycles(100);
                    RowCfg.LaneActive <= '1';
                    cycles(300);
                end loop;

                check_value(RowStat.ProtErrs, 0, error, "No protocol error");
                check_value(RowStat.LinkState, "11", error, "No link reset");

                -- Every data word of the data frames belongs to the packets written, in order
                Last_v := -1;
                Idx_v  := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindSdf then
                        Idx_v := 1;
                    elsif txKind(i) = KindEdf then
                        Idx_v := 0;
                    elsif Idx_v = 1 and txKind(i) = KindData and TxLog_v.get(i)(35 downto 32) = KData_c then
                        check_value(unsigned(txWord(i)) < 10000, error, "Word of a packet");
                        check_value(to_integer(unsigned(txWord(i)(15 downto 0))) > Last_v, error, "Words in order");
                        Last_v := to_integer(unsigned(txWord(i)(15 downto 0)));
                    end if;
                end loop;

                TxLog_v.clear;
                userPacket(0, 5, 20000);
                rxFct(0, 2);
                waitRxIdle;
                cycles(300);
                Pos_v := txFind(KindSdf, 0);
                check_value(Pos_v >= 0, error, "Packet after the flushes sent");
                check_value(txPayload, 5, error, "Complete packet after the flushes");

            -- TC-DL-13: data word identification
            elsif run("test_word_id") then
                waitLinkInit(10 us);
                cycles(400);
                -- SDF inside a data frame: frame error, frame discarded
                rxWord(wordSdf("00000"));
                rxData(x"00000001");
                rxWord(wordSdf("00000"));
                rxData(x"00000002");
                rxWord(wordEdf(x"01", x"0000"));
                -- EDF and EBF in RxNothing are ignored
                rxWord(wordEbf("00", x"01", x"00"));
                waitRxIdle;
                check_value(RowStat.FrameErrs, 1, error, "Frame error for SDF in a data frame");
                check_value(VcRxLog0_v.count, 0, error, "Frame discarded");
                -- Broadcast frame inside a data frame, FCT inside, unknown control word ignored
                rxWord(wordSdf("00000"));
                rxData(x"00000010");
                rxWord(wordSbf(x"05", x"06"));
                rxData(x"AAAAAAAA");
                rxData(x"BBBBBBBB");
                Got_v(31 downto 0) := wordEbf("00", x"01", x"00");
                rxWord(wordEbf("00", x"01", crc8Chars(crc8Chars(crc8Chars(crc8Chars(Crc8Seed_c, wordSbf(x"05", x"06"),
                       4), x"AAAAAAAA", 4), x"BBBBBBBB", 4), Got_v(31 downto 0), 3)));
                rxFct(1, 2);
                rxWord(x"0000F1" & K28_7_c);
                rxData(x"00000011");
                rxWord(wordEdf(x"03", x"0000"));
                waitRxIdle;
                cycles(100);
                check_value(RowStat.FrameErrs, 1, error, "No further frame error");
                check_value(VcRxLog0_v.count, 2, error, "Data frame around the broadcast frame delivered");
                check_value(RowStat.BcRx, 1, error, "Broadcast message delivered");
                check_value(RowStat.HasCredit(1), '1', error, "FCT inside the data frame accepted");
                -- Data frame longer than 64 words: frame error
                rxFrame(0, 65, 4);
                waitRxIdle;
                check_value(RowStat.FrameErrs, 2, error, "Frame error for 65 data words");
                check_value(VcRxLog0_v.count, 2, error, "Too long frame discarded");
                -- Broadcast frame with one data word: frame error
                rxWord(wordSbf(x"05", x"06"));
                rxData(x"CCCCCCCC");
                Got_v(31 downto 0) := wordEbf("00", x"04", x"00");
                rxWord(wordEbf("00", x"04", crc8Chars(crc8Chars(crc8Chars(Crc8Seed_c, wordSbf(x"05", x"06"), 4),
                       x"CCCCCCCC", 4), Got_v(31 downto 0), 3)));
                waitRxIdle;
                check_value(RowStat.FrameErrs, 3, error, "Frame error for a short broadcast frame");
                check_value(RowStat.BcRx, 1, error, "Short broadcast frame discarded");

            -- TC-DL-14: ECSS Figure 5-46 broadcast frame and FCT
            elsif run("test_crc8_vectors") then
                waitLinkInit(10 us);
                cycles(400);
                -- FCT 0x01 0x01 0x4F: VC 1, sequence 1, accepted
                rxWord(x"4F" & x"01" & x"01" & K28_3_c);
                waitRxIdle;
                cycles(20);
                check_value(RowStat.HasCredit(1), '1', error, "Figure 5-46 FCT accepted");
                -- Broadcast frame with CRC 0x29 and sequence number 0x41: CRC correct, sequence error
                rxWord(wordSbf(x"00", x"00"));
                rxData(x"00000000");
                rxData(x"01010101");
                rxWord(x"29" & x"41" & x"00" & K28_2_c);
                waitRxIdle;
                check_value(RowStat.Crc8Errs, 0, error, "Figure 5-46 broadcast frame: CRC-8 correct");
                check_value(RowStat.SeqErrs, 1, error, "Figure 5-46 broadcast frame: sequence error");
                -- Same frame with a wrong CRC
                rxWord(wordSbf(x"00", x"00"));
                rxData(x"00000000");
                rxData(x"01010101");
                rxWord(x"28" & x"41" & x"00" & K28_2_c);
                waitRxIdle;
                check_value(RowStat.Crc8Errs, 1, error, "Wrong broadcast CRC-8 detected");

            -- TC-DL-15: NACK: RETRY, resend with new sequence numbers and inverted polarity in the order
            -- broadcast frames, FCTs, data frames; LATE on the resent broadcast frame
            elsif run("test_retry") then
                RowCfg.AutoAck <= false;
                waitLinkInit(10 us);
                rxFct(0, 1);
                rxFct(0, 2);
                waitRxIdle;
                userPacket(0, 10, 1000);
                cycles(300);
                userPacket(0, 5, 2000);
                cycles(300);
                BcTxData       <= x"0123456789ABCDEF";
                BcTxReq        <= 1;
                cycles(300);
                -- Outstanding: 4 FCTs (1 to 4), data frames and the broadcast frame
                check_value(RowStat.ErbEmpty, '0', error, "Items outstanding");
                TxLog_v.clear;
                rxWord(wordNack(x"02"));
                waitRxIdle;
                cycles(300);
                Pos_v := txFind(KindRetry, 0);
                check_value(Pos_v >= 0, error, "RETRY sent");
                check_value(RowStat.Retries, 1, error, "One error recovery attempt");
                -- First resent item: broadcast frame with sequence 3, negative polarity, LATE
                Idx_v := txFind(KindEbf, Pos_v);
                check_value(Idx_v >= 0, error, "Broadcast frame resent");
                check_value(txWord(Idx_v)(23 downto 16), x"83", error, "EBF sequence 3, negative");
                check_value(txWord(Idx_v)(8), '1', error, "LATE flag of the resent broadcast frame");
                -- Then the FCTs 3 and 4 (sequence 4 and 5), then the data frames (6, 7)
                Idx_v := txFind(KindFct, Pos_v);
                check_value(txWord(Idx_v)(23 downto 16), x"84", error, "First resent FCT");
                check_value(txFind(KindFct, Idx_v + 1) >= 0, error, "Second resent FCT");
                Idx_v := txFind(KindEdf, Pos_v);
                check_value(txWord(Idx_v)(15 downto 8), x"86", error, "First resent data frame");
                Idx_v := txFind(KindEdf, Idx_v + 1);
                check_value(txWord(Idx_v)(15 downto 8), x"87", error, "Second resent data frame");
                check_value(txFind(KindSdf, Pos_v) > txFind(KindFct, Pos_v), error, "Data after the FCTs");
                -- ACK of the last resent item with the new polarity empties the buffer
                Seq_v := 0;

                for i in Pos_v to TxLog_v.count - 1 loop
                    if txKind(i) = KindFct or txKind(i) = KindEbf then
                        Seq_v := seqOf(txWord(i));
                    elsif txKind(i) = KindEdf then
                        Seq_v := to_integer(unsigned(txWord(i)(14 downto 8)));
                    end if;
                end loop;

                rxWord(wordAck('1' & std_logic_vector(to_unsigned(Seq_v, 7))));
                waitErbEmpty(10 us);
                check_value(RowStat.ProtErrs, 0, error, "No protocol error");

            -- TC-DL-16: ACK with a sequence count outside the outstanding items: protocol error
            elsif run("test_protocol_error") then
                RowCfg.AutoAck <= false;
                waitLinkInit(10 us);
                cycles(300);
                -- Duplicate of the previous count (0): no error
                rxWord(wordAck(x"00"));
                waitRxIdle;
                check_value(RowStat.ProtErrs, 0, error, "Duplicate ACK accepted");
                -- Four FCTs outstanding: ACK 10 is inconsistent
                rxWord(wordAck(x"0A"));
                waitRxIdle;
                check_value(RowStat.ProtErrs, 1, error, "Protocol error");
                waitLinkInit(20 us);
                check_value(RowStat.LinkState, "11", error, "Link reset and initialised again");
                -- ACK with the other polarity is ignored
                rxWord(wordAck(x"8A"));
                waitRxIdle;
                check_value(RowStat.ProtErrs, 1, error, "ACK of the other polarity ignored");

            -- TC-DL-17: error recovery buffer full: FULL every 64 words, no new data frames
            elsif run("test_erb_full") then
                RowCfg.AutoAck <= false;
                waitLinkInit(10 us);

                for i in 1 to 8 loop
                    rxFct(0, i, '0', 0);
                end loop;

                waitRxIdle;

                for p in 0 to 9 loop
                    userPacket(0, 40, 100 * p);
                end loop;

                cycles(3000);
                N_v   := txPayload;
                check_value(N_v <= 256, error, "No more data than the buffer holds (" & to_string(N_v) & ")");
                check_value(N_v > 100, error, "Buffer filled with data (" & to_string(N_v) & ")");
                cycles(1000);
                check_value(txPayload, N_v, error, "No new data while the buffer is full");
                check_value(txCount(KindFull) >= 3, error, "FULL repeated while the buffer is full");
                Pos_v := txFind(KindFull, 400);
                Idx_v := txFind(KindFull, Pos_v + 1);
                check_value(Idx_v - Pos_v >= 64 and Idx_v - Pos_v <= 70, error, "FULL every 64 words");
                -- Acknowledge everything: the remaining data is sent
                Seq_v := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindEdf or txKind(i) = KindFct or txKind(i) = KindEbf then
                        Seq_v := Seq_v + 1;
                    end if;
                end loop;

                rxWord(wordAck(std_logic_vector(to_unsigned(Seq_v, 8))));
                cycles(3000);
                check_value(txPayload, 400, error, "All data sent after the ACK");
                -- Data item limit: separate small frames without ACK stop after eight frames (ErbDataItems_g).
                -- The frames sent after the first ACK are acknowledged first.
                Seq_v := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindEdf or txKind(i) = KindFct or txKind(i) = KindEbf then
                        Seq_v := Seq_v + 1;
                    end if;
                end loop;

                rxWord(wordAck(std_logic_vector(to_unsigned(Seq_v mod 128, 8))));
                cycles(200);
                TxLog_v.clear;

                for p in 0 to 11 loop
                    userPacket(0, 2, 1000 + 10 * p);
                    cycles(60);
                end loop;

                cycles(500);
                check_value(txCount(KindSdf), 8, error, "Eight data frames: all data items of the buffer used");
                check_value(txPayload, 16, error, "Eight packets sent");

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindEdf or txKind(i) = KindFct or txKind(i) = KindEbf then
                        Seq_v := Seq_v + 1;
                    end if;
                end loop;

                rxWord(wordAck(std_logic_vector(to_unsigned(Seq_v mod 128, 8))));
                cycles(1000);
                check_value(txPayload, 24, error, "All packets sent after the ACK");

            -- TC-DL-18: link reset rules of the VC buffers: spill on the output side, EEP on the input side
            elsif run("test_vc_link_reset") then
                waitLinkInit(10 us);
                cycles(300);
                -- Input side: a partial packet read by the user
                rxFrame(0, 3, 1);
                waitRxIdle;
                cycles(50);
                check_value(VcRxLog0_v.count, 3, error, "Partial packet read");
                -- Output side: a partial packet written before the link reset (no credit yet)
                VcTxQueue1_v.push('0' & KData_c & x"00000500");
                VcTxQueue1_v.push('0' & KData_c & x"00000501");
                cycles(100);
                RowCfg.LinkReset <= '1';
                cycles(1);
                RowCfg.LinkReset <= '0';
                waitLinkInit(20 us);
                cycles(100);
                check_value(VcRxLog0_v.count, 4, error, "EEP read after the link reset");
                check_value(VcRxLog0_v.get(3), "1111" & CharFill_c & CharFill_c & CharFill_c & CharEep_c, error, "EEP word");
                -- Rest of the partial packet (discarded up to the EOP) and a new packet
                userPacket(1, 3, 600);
                userPacket(1, 2, 700);
                rxFct(1, 1);
                waitRxIdle;
                TxLog_v.clear;
                cycles(500);
                Pos_v := txFind(KindSdf, 0);
                check_value(Pos_v >= 0, error, "Data frame on VC 1");
                check_value(txWord(Pos_v + 1), x"000002BC", error, "First word of the new packet");
                check_value(txPayload, 2, error, "Only the new packet sent");

            -- TC-DL-20: one FCT for every 64 words read by the user
            elsif run("test_fct_return") then
                waitLinkInit(10 us);
                cycles(400);
                N_v := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindFct and txWord(i)(12 downto 8) = "00000" then
                        N_v := N_v + 1;
                    end if;
                end loop;

                check_value(N_v, 2, error, "Two FCTs for VC 0 after link reset");
                rxFrame(0, 64, 1);
                rxFrame(0, 64, 2);
                waitRxIdle;
                cycles(500);
                check_value(VcRxLog0_v.count, 128, error, "128 words read");
                N_v := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindFct and txWord(i)(12 downto 8) = "00000" then
                        N_v := N_v + 1;
                    end if;
                end loop;

                check_value(N_v, 4, error, "Two more FCTs for VC 0 after 128 words read");
                check_value(RowStat.InputOvfs, 0, error, "No input buffer overflow");

            -- TC-DL-21: priority and schedule: frames of the higher priority VC first when both
            -- become ready at the same time (time-slot change)
            elsif run("test_qos_priority_schedule") then
                waitLinkInit(10 us);
                -- Both VCs not allocated to time-slot 1, bandwidth 100 %, VC 1 priority 0
                regWrite(16#408#, x"FFFFFFFD");
                regWrite(16#418#, x"FFFFFFFD");
                regWrite(16#404#, x"00000100");
                regWrite(16#414#, x"00000100");
                regWrite(16#410#, x"00000000");
                schedule(1);
                rxFct(0, 1);
                rxFct(0, 2);
                rxFct(1, 3);
                rxFct(1, 4);
                waitRxIdle;
                TxLog_v.clear;
                userPacket(0, 30, 0);
                userPacket(0, 30, 100);
                userPacket(1, 30, 200);
                userPacket(1, 30, 300);
                cycles(500);
                check_value(txPayload, 0, error, "No data frame in time-slot 1");
                schedule(0);
                cycles(1000);
                check_value(txPayload, 120, error, "All data sent in time-slot 0");
                Pos_v  := txFind(KindSdf, 0);
                check_value(txWord(Pos_v)(20 downto 16), "00001", error, "First data frame of VC 1");
                Last_v := -1;
                Idx_v  := 0;

                for i in 0 to TxLog_v.count - 1 loop
                    if txKind(i) = KindSdf then
                        if txWord(i)(20 downto 16) = "00001" then
                            Last_v := i;
                        elsif Idx_v = 0 then
                            Idx_v := i;
                        end if;
                    end if;
                end loop;

                check_value(Last_v < Idx_v, error, "All frames of VC 1 before those of VC 0");

            -- TC-DL-22: continuous mode: flush and EEP when the buffer is about to be full and when no
            -- lane is active, no back-pressure on the user
            elsif run("test_continuous_mode") then
                waitLinkInit(10 us);
                regWrite(16#400#, x"00000103");
                cycles(50);
                TxLog_v.clear;

                for p in 0 to 6 loop
                    userPacket(0, 20, 20 * p);
                end loop;

                cycles(600);
                check_value(VcTxQueue0_v.count, 0, error, "All words accepted without back-pressure");
                rxFct(0, 1);
                rxFct(0, 2);
                waitRxIdle;
                cycles(300);
                check_value(txPayload, 1, error, "Only the EEP after the flush");
                Pos_v := txFind(KindSdf, 0);
                check_value(TxLog_v.get(Pos_v + 1), "1111" & CharFill_c & CharFill_c & CharFill_c & CharEep_c, error,
                            "EEP word");
                -- No lane active: the first word of a packet causes a flush, the packet is discarded
                RowCfg.LaneActive <= '0';
                cycles(10);
                userPacket(0, 3, 500);
                cycles(200);
                RowCfg.LaneActive <= '1';
                cycles(300);
                check_value(txPayload, 2, error, "Second EEP after the flush without active lane");

            -- TC-DL-23: FULL after an RXERR when nothing else is to be sent but items wait for
            -- acknowledgement (ECSS 5.7.7.1r); no FULL with an empty error recovery buffer
            elsif run("test_full_after_rxerr") then
                waitLinkInit(10 us);
                cycles(400);
                waitErbEmpty(10 us);
                TxLog_v.clear;
                rxWord(WordRxErr_c);
                waitRxIdle;
                cycles(100);
                check_value(txCount(KindFull), 0, error, "No FULL after RXERR with an empty buffer");
                -- One data frame without acknowledgement
                RowCfg.AutoAck <= false;
                rxFct(0, 1);
                userPacket(0, 4);
                cycles(300);
                check_value(RowStat.ErbEmpty, '0', error, "Data frame waits for acknowledgement");
                TxLog_v.clear;
                cycles(200);
                check_value(txCount(KindFull), 0, error, "No FULL before the RXERR");
                rxWord(WordRxErr_c);
                waitRxIdle;
                cycles(100);
                Pos_v          := txFind(KindFull, 0);
                check_value(Pos_v >= 0, error, "FULL after RXERR with items waiting");
                check_value(txWord(Pos_v), wordFull(x"05"), error, "FULL with the current sequence number");

            -- TC-DL-24: a broadcast message that finds the broadcast input buffer full is discarded and
            -- counted
            elsif run("test_bc_input_discard") then
                waitLinkInit(10 us);
                cycles(400);
                RowCfg.BcReady <= '0';

                for i in 1 to 6 loop
                    rxBroadcast(i, std_logic_vector(to_unsigned(i, 64)));
                end loop;

                waitRxIdle;
                cycles(100);
                check_value(RowStat.BcDiscards, 2, error, "Two messages discarded (buffer of 4)");
                check_value(RowStat.SeqErrs, 0, error, "Broadcast frames in sequence");
                RowCfg.BcReady <= '1';
                cycles(100);
                check_value(RowStat.BcRx, 4, error, "Four messages delivered");

            -- TC-DL-19: FCT credit limits the data, credit overflow
            elsif run("test_credit") then
                waitLinkInit(10 us);
                cycles(300);
                TxLog_v.clear;
                userPacket(0, 100, 0);
                cycles(500);
                check_value(txPayload, 0, error, "No data without credit");
                rxFct(0, 1);
                waitRxIdle;
                cycles(500);
                check_value(txPayload, 64, error, "64 words for one FCT");
                rxFct(0, 2);
                waitRxIdle;
                cycles(500);
                check_value(txPayload, 100, error, "Rest after the second FCT");

                -- 64 FCTs exceed the 12-bit counter
                for i in 3 to 66 loop
                    rxFct(0, i);
                end loop;

                waitRxIdle;
                check_value(RowStat.CreditOvfs >= 1, error, "Credit counter overflow");

            -- TC-DL-25: Link Reset while a data frame is sent: the frame is stopped, the idle frames
            -- after the link reset start with the PRBS seed
            elsif run("test_link_reset_frame") then
                waitLinkInit(10 us);
                cycles(400);
                rxFct(1, 1);
                waitRxIdle;
                TxLog_v.clear;
                userPacket(1, 60, 800);

                while txFind(KindSdf, 0) < 0 loop
                    cycles(1);
                end loop;

                cycles(5);
                RowCfg.LinkReset <= '1';
                cycles(1);
                RowCfg.LinkReset <= '0';
                waitLinkInit(20 us);
                cycles(300);
                -- The data frame is stopped: no EDF, fewer than the 60 words of the packet
                Pos_v := txFind(KindSdf, 0);
                Cnt_v := 0;
                Idx_v := Pos_v + 1;

                while Idx_v < TxLog_v.count loop
                    exit when txKind(Idx_v) /= KindData;
                    Cnt_v := Cnt_v + 1;
                    Idx_v := Idx_v + 1;
                end loop;

                check_value(Cnt_v > 0 and Cnt_v < 60, error, "Data frame stopped after " & to_string(Cnt_v) & " words");
                check_value(txFind(KindEdf, 0), -1, error, "Stopped data frame not ended");
                check_value(txFind(KindSdf, Pos_v + 1), -1, error, "Packet flushed, no further data frame");
                -- First idle frame after the link reset: 64 PRBS words from the seed
                Idx_v   := txFind(KindSif, Pos_v) + 1;
                State_v := PrbsEcssSeed_c;
                Cnt_v   := 0;

                while Idx_v < TxLog_v.count loop
                    Kind_v := txKind(Idx_v);
                    exit when Kind_v = KindSif;
                    if Kind_v = KindData then
                        check_value(txWord(Idx_v), prbsWord(State_v), error, "PRBS word " & to_string(Cnt_v));
                        State_v := prbsNextState(State_v);
                        Cnt_v   := Cnt_v + 1;
                    end if;
                    Idx_v := Idx_v + 1;
                end loop;

                check_value(Cnt_v, 64, error, "64 PRBS words from the seed");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 5 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_dl_row_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
