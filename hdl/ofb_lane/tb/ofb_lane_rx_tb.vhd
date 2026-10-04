---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the lane receiver (LN-3): word alignment, receive synchronisation, RXERR
-- words, lane control word detection and filtering, RXERR word counter.
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
    use work.ofb_tb_pkg.all;
    use work.ofb_lane_rx_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_rx_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_rx_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

    constant RxErrWord_c : KWord_t := KCtrl_c & WordRxErr_c;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        -- Character stream of a test: character, K flag, error flag
        type Chars_t is array (0 to 65535) of Char_t;
        type Flags_t is array (0 to 65535) of std_logic;

        variable Chars_v  : Chars_t;
        variable Ks_v     : Flags_t;
        variable Errs_v   : Flags_t;
        variable NChars_v : natural := 0;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        procedure addWord (
            word    : Word_t;
            k       : WordK_t;
            errMask : WordK_t := "0000") is
        begin

            for i in 0 to 3 loop
                Chars_v(NChars_v) := word(8*i+7 downto 8*i);
                Ks_v(NChars_v)    := k(i);
                Errs_v(NChars_v)  := errMask(i);
                NChars_v          := NChars_v + 1;
            end loop;

        end procedure;

        -- Data characters that shift the word boundary on the line
        procedure addFill (n : natural) is
        begin

            for i in 1 to n loop
                Chars_v(NChars_v) := x"5A";
                Ks_v(NChars_v)    := '0';
                Errs_v(NChars_v)  := '0';
                NChars_v          := NChars_v + 1;
            end loop;

        end procedure;

        -- Comma words that synchronise the receiver (filtered when received)
        procedure addPreamble is
        begin

            for i in 1 to 4 loop
                addWord(WordIdle_c, KCtrl_c);
            end loop;

        end procedure;

        -- Drive the character stream, four characters per cycle; characters that do not fill a word are
        -- kept for the next call, so the stream on the line stays continuous
        procedure feed is
            variable Idx_v  : natural := 0;
            variable Rest_v : natural;
        begin

            while Idx_v + 4 <= NChars_v loop

                for i in 0 to 3 loop
                    RxIn.Data(8*i+7 downto 8*i) <= Chars_v(Idx_v + i);
                    RxIn.K(i)                   <= Ks_v(Idx_v + i);
                    RxIn.CodeErr(i)             <= Errs_v(Idx_v + i);
                end loop;

                RxIn.Valid <= '1';
                Idx_v      := Idx_v + 4;
                cycles(1);
            end loop;

            RxIn.Valid <= '0';
            Rest_v     := NChars_v - Idx_v;

            for i in 0 to Rest_v - 1 loop
                Chars_v(i) := Chars_v(Idx_v + i);
                Ks_v(i)    := Ks_v(Idx_v + i);
                Errs_v(i)  := Errs_v(Idx_v + i);
            end loop;

            NChars_v := Rest_v;
        end procedure;

        -- Idle stream after a test sequence so that the pipeline empties
        procedure drain is
        begin
            addPreamble;
            feed;
            cycles(8);
        end procedure;

        -- Synchronise the receiver and empty the output log
        procedure syncUp is
        begin
            addPreamble;
            feed;
            cycles(8);
            OutLog_v.clear;
        end procedure;

        procedure checkLog (
            expected : WordArray_t;
            ks       : WordKArray_t;
            msg      : string) is
        begin
            check_value(OutLog_v.count, expected'length, error, "Number of words passed up: " & msg);

            for i in 0 to minimum(expected'length, OutLog_v.count) - 1 loop
                check_value(OutLog_v.get(i), ks(i) & expected(i), error, "Word " & to_string(i) & ": " & msg);
            end loop;

        end procedure;

        variable Words_v  : WordArray_t(0 to 9);
        variable WordKs_v : WordKArray_t(0 to 9);
        variable Cnt_v    : natural;
        variable Base_v   : natural;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        wait until Rst = '0';
        wait until falling_edge(Clk);

        for i in Words_v'range loop
            Words_v(i)  := std_logic_vector(to_unsigned(16#01020304# * (i + 1), 32));
            WordKs_v(i) := KData_c;
        end loop;

        Words_v(3)  := wordSif(x"05");
        WordKs_v(3) := KCtrl_c;
        Words_v(7)  := x"FDFBFB12";
        WordKs_v(7) := "1110";

        while test_suite loop

            -- TC-LN-40: words are aligned to the comma for every symbol offset (ECSS 5.5.7)
            if run("test_alignment") then
                RxIn.Active <= '1';

                for offset in 0 to 3 loop
                    addFill(offset);
                    addPreamble;
                    feed;
                    cycles(8);
                    OutLog_v.clear;

                    for i in Words_v'range loop
                        addWord(Words_v(i), WordKs_v(i));
                    end loop;

                    drain;
                    checkLog(Words_v, WordKs_v, "offset " & to_string(offset));
                end loop;

            -- TC-LN-41: realignment: the realigned word is RXERR, words pass again after the next comma
            elsif run("test_realignment") then
                RxIn.Active <= '1';
                syncUp;
                addFill(1);
                addPreamble;

                for i in Words_v'range loop
                    addWord(Words_v(i), WordKs_v(i));
                end loop;

                drain;
                check_value(OutLog_v.count >= Words_v'length + 1, error, "RXERR and the words after the realignment");
                check_value(OutLog_v.get(0), RxErrWord_c, error, "Realigned word passed up as RXERR");
                Base_v := OutLog_v.count - Words_v'length;

                for i in Words_v'range loop
                    check_value(OutLog_v.get(Base_v + i), WordKs_v(i) & Words_v(i), error, "Word " & to_string(i));
                end loop;

            -- TC-LN-42: a symbol error turns its word and the previous word into RXERR (ECSS 5.5.7j to l)
            elsif run("test_error_rule") then
                RxIn.Active <= '1';
                syncUp;

                for i in Words_v'range loop
                    if i = 5 then
                        addWord(Words_v(i), WordKs_v(i), "0100");
                    else
                        addWord(Words_v(i), WordKs_v(i));
                    end if;
                end loop;

                drain;
                checkLog((Words_v(0), Words_v(1), Words_v(2), Words_v(3), WordRxErr_c, WordRxErr_c, Words_v(6),
                          Words_v(7), Words_v(8), Words_v(9)),
                         (WordKs_v(0), WordKs_v(1), WordKs_v(2), WordKs_v(3), KCtrl_c, KCtrl_c, WordKs_v(6),
                          WordKs_v(7), WordKs_v(8), WordKs_v(9)),
                         "error in word 5");

            -- TC-LN-43: more than four error words in CheckSync lose synchronisation (ECSS 5.5.8.3c.3)
            elsif run("test_lost_sync") then
                RxIn.Active <= '1';
                syncUp;

                for i in 1 to 5 loop
                    addWord(Words_v(0), KData_c, "0001");
                end loop;

                for i in 0 to 3 loop
                    addWord(Words_v(i), WordKs_v(i));
                end loop;

                feed;
                cycles(8);
                -- The aligned word lags the input by one word and the error rule holds one more word: of
                -- the four data words two are passed up
                Cnt_v := OutLog_v.count;
                check_value(Cnt_v, 1 + 5 + 2, error, "Previous word, error words and words in LostSync");

                for i in 0 to Cnt_v - 1 loop
                    check_value(OutLog_v.get(i), RxErrWord_c, error, "RXERR " & to_string(i));
                end loop;

                -- A comma restores the synchronisation
                OutLog_v.clear;
                addPreamble;

                for i in Words_v'range loop
                    addWord(Words_v(i), WordKs_v(i));
                end loop;

                drain;
                Base_v := OutLog_v.count - Words_v'length;

                for i in Words_v'range loop
                    check_value(OutLog_v.get(Base_v + i), WordKs_v(i) & Words_v(i), error, "Word " & to_string(i));
                end loop;

            -- TC-LN-44: lane control words are detected and filtered; INIT1, STANDBY, LOST_SIGNAL become RXERR
            elsif run("test_lane_words") then
                RxIn.Active <= '1';
                syncUp;
                Base_v      := RxStat.Comma;
                addWord(WordSkip_c, KCtrl_c);
                addWord(WordIdle_c, KCtrl_c);
                addWord(WordInit1_c, KCtrl_c);
                addWord(WordInit2_c, KCtrl_c);
                addWord(WordInvInit1_c, KCtrl_c);
                addWord(WordInvInit2_c, KCtrl_c);
                addWord(wordInit3(x"5A"), KCtrl_c);
                addWord(wordStandby(x"21"), KCtrl_c);
                addWord(wordLostSignal(LosCauseRxErr_c), KCtrl_c);
                addWord(Words_v(0), KData_c);
                addWord(wordSif(x"07"), KCtrl_c);
                drain;
                checkLog((WordRxErr_c, WordRxErr_c, WordRxErr_c, Words_v(0), wordSif(x"07")),
                         (KCtrl_c, KCtrl_c, KCtrl_c, KData_c, KCtrl_c), "lane control words filtered");
                check_value(RxStat.Skip, 1, error, "SKIP event");
                check_value(RxStat.Init1, 1, error, "INIT1 event");
                check_value(RxStat.Init2, 1, error, "INIT2 event");
                check_value(RxStat.InvInit1, 1, error, "iINIT1 event");
                check_value(RxStat.InvInit2, 1, error, "iINIT2 event");
                check_value(RxStat.Init3, 1, error, "INIT3 event");
                check_value(RxStat.Standby, 1, error, "STANDBY event");
                check_value(RxStat.LostSignal, 1, error, "LOST_SIGNAL event");
                check_value(RxStat.LastParam, x"01", error, "LOS_Cause of the LOST_SIGNAL");
                check_value(RxStat.Comma - Base_v, 5 + 4, error, "K28.7 words: SKIP, IDLE, STANDBY, LOST_SIGNAL, SIF, 4 IDLE");
                -- Outside Active nothing is passed up
                RxIn.Active <= '0';
                cycles(2);
                OutLog_v.clear;
                addWord(Words_v(0), KData_c);
                addWord(WordInit1_c, KCtrl_c);
                drain;
                check_value(OutLog_v.count, 0, error, "No words passed up outside Active");
                check_value(RxStat.Init1, 2, error, "Events also outside Active");

            -- TC-LN-45: RXERR word counter: increment, leak, overflow, clear (ECSS 5.5.2.2, 5.5.2.11)
            elsif run("test_rxerr_counter") then
                RxIn.Active <= '1';
                syncUp;
                -- The start-up in LostSync already produced RXERR words
                Base_v := to_integer(unsigned(RxStat.ErrCount));

                -- 10 RXERR words (5 error words, each with its previous word)
                for i in 1 to 5 loop
                    addWord(Words_v(0), KData_c);
                    addWord(Words_v(1), KData_c, "1000");
                    addPreamble;
                end loop;

                feed;
                cycles(8);
                Cnt_v := to_integer(unsigned(RxStat.ErrCount)) - Base_v;
                check_value(Cnt_v >= 9 and Cnt_v <= 10, error,
                            "Counter after 10 RXERR words (one leak possible): +" & to_string(Cnt_v));
                Cnt_v := to_integer(unsigned(RxStat.ErrCount));
                -- 4 x 64 error-free words: four decrements
                Base_v := Cnt_v;

                for i in 1 to 4 * TbRxErrLeakWords_c loop
                    addWord(Words_v(2), KData_c);
                end loop;

                feed;
                cycles(8);
                Cnt_v := to_integer(unsigned(RxStat.ErrCount));
                check_value(Base_v - Cnt_v >= 4 and Base_v - Cnt_v <= 5, error, "Leak of the counter");

                -- Overflow
                for i in 1 to 400 loop
                    addWord(Words_v(0), KData_c, "0001");
                end loop;

                feed;
                cycles(8);
                check_value(RxStat.ErrCount, x"FF", error, "Counter saturates at 255");
                check_value(RxStat.Overflow, '1', error, "Overflow flag");
                check_value(RxStat.OverflowEv, 1, error, "One overflow event");
                -- Not cleared by leaving Active, cleared by the clear input only
                RxIn.Active   <= '0';
                cycles(10);
                check_value(RxStat.ErrCount, x"FF", error, "Counter kept outside Active");
                check_value(RxStat.Overflow, '1', error, "Overflow kept outside Active");
                RxIn.ErrClear <= '1';
                cycles(2);
                RxIn.ErrClear <= '0';
                cycles(2);
                check_value(RxStat.ErrCount, x"00", error, "Counter cleared");
                check_value(RxStat.Overflow, '0', error, "Overflow cleared");
                -- Outside Active RXERR words do not count
                addWord(Words_v(0), KData_c, "0001");
                drain;
                check_value(RxStat.ErrCount, x"00", error, "No counting outside Active");

            -- TC-LN-46: one RXERR word is passed up when Active is left (ECSS 5.5.2.11e.7)
            elsif run("test_active_exit") then
                RxIn.Active <= '1';
                syncUp;
                RxIn.Active <= '0';
                cycles(5);
                check_value(OutLog_v.count, 1, error, "One word passed up when Active is left");
                check_value(OutLog_v.get(0), RxErrWord_c, error, "RXERR passed up when Active is left");

            -- TC-LN-47: SyncReset (LaneReset, CDR disabled) loses the synchronisation
            elsif run("test_sync_reset") then
                RxIn.Active    <= '1';
                syncUp;
                RxIn.SyncReset <= '1';
                cycles(2);
                RxIn.SyncReset <= '0';
                OutLog_v.clear;
                addWord(Words_v(0), KData_c);
                addWord(Words_v(1), KData_c);
                addWord(Words_v(2), KData_c);
                feed;
                cycles(8);
                check_value(OutLog_v.count, 2, error, "Words passed up in LostSync (the third is held)");
                check_value(OutLog_v.get(0), RxErrWord_c, error, "LostSync: word 0 is RXERR");
                check_value(OutLog_v.get(1), RxErrWord_c, error, "LostSync: word 1 is RXERR");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 2 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_lane_rx_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
