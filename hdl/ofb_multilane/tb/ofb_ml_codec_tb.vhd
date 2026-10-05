---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the column codec (ML-3, ML-4): ECSS examples, words interleaved in data
-- frames, back-pressure, CRC errors and loopback of random frames against the reference model.
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

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_ml_tb_pkg.all;
    use work.ofb_ml_codec_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_codec_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_codec_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

    -- ECSS Figure 5-44: three short data frames without scrambling (input and expected EDF)
    constant Fig44In_c  : WordArray_t(0 to 10)  := (
        wordSdf("00010"), x"00000000", CharFill_c & CharFill_c & CharFill_c & CharEop_c, wordEdf(x"41", x"0000"),
        wordSdf("00001"), CharFill_c & CharFill_c & CharEop_c & x"00", wordEdf(x"7D", x"0000"),
        wordSdf("00001"), CharEop_c & x"02" & x"01" & x"00", wordEdf(x"7E", x"0000"),
        x"00000000"
    );
    constant Fig44K_c   : WordKArray_t(0 to 10) := (
        KCtrl_c, KData_c, "1111", KCtrl_c,
        KCtrl_c, "1110", KCtrl_c,
        KCtrl_c, "1000", KCtrl_c,
        KData_c
    );
    constant Fig44Out_c : WordArray_t(0 to 10)  := (
        Fig44In_c(0), Fig44In_c(1), Fig44In_c(2), x"97" & x"8A" & x"41" & K28_0_c,
        Fig44In_c(4), Fig44In_c(5), x"35" & x"3D" & x"7D" & K28_0_c,
        Fig44In_c(7), Fig44In_c(8), x"B7" & x"A1" & x"7E" & K28_0_c,
        Fig44In_c(10)
    );

    -- ECSS Figure 5-42: scrambling of a short data frame (input and scrambled frame)
    constant Fig42In_c  : WordArray_t(0 to 4)  := (
        wordSdf("00000"), x"03020100", x"07060504", CharFill_c & CharFill_c & CharEop_c & x"08",
        wordEdf(x"22", x"0000")
    );
    constant Fig42K_c   : WordKArray_t(0 to 4) := (KCtrl_c, KData_c, KData_c, "1110", KCtrl_c);
    constant Fig42Out_c : WordArray_t(0 to 4)  := (
        Fig42In_c(0), x"17C216FF", x"8504E2B6", CharFill_c & CharFill_c & CharEop_c & x"7A",
        x"DA" & x"98" & x"22" & K28_0_c
    );
    -- Figure 5-42 without scrambling: the EDF carries the CRC of the original data
    constant Fig42Edf_c : Word_t := x"A8" & x"28" & x"22" & K28_0_c;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable S_v    : Stream_t;
        variable Corr_v : Stream_t;
        variable Sdf_v  : natural;
        variable Edf_v  : natural;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Send words of a stream (chunks of at most 512 words per VVC command)
        procedure sendWords (
            vvc   : natural;
            words : WordArray_t;
            ks    : WordKArray_t) is
            variable Pos_v : natural;
            variable Len_v : natural;
        begin
            Pos_v := words'low;

            while Pos_v <= words'high loop
                Len_v := minimum(words'high - Pos_v + 1, 512);
                axistream_transmit(AXISTREAM_VVCT, vvc, toSlvArray(words(Pos_v to Pos_v + Len_v - 1)),
                                   toUserArray(ks(Pos_v to Pos_v + Len_v - 1)), to_string(Len_v) & " words");
                Pos_v := Pos_v + Len_v;
            end loop;

            await_completion(AXISTREAM_VVCT, vvc, 10 ms, "Words sent");
            cycles(10);
        end procedure;

        -- Compare a log with expected words and flags
        procedure checkLog (
            enc      : boolean;
            words    : WordArray_t;
            ks       : WordKArray_t;
            flags    : std_logic_vector;
            checkFlg : boolean;
            msg      : string) is
            variable Cnt_v  : natural;
            variable Got_v  : KWord_t;
            variable Flag_v : std_logic;
        begin
            if enc then
                Cnt_v := EncLog_v.count;
            else
                Cnt_v := DecLog_v.count;
            end if;
            check_value(Cnt_v, words'length, error, msg & ": number of words");

            for i in 0 to minimum(Cnt_v, words'length) - 1 loop
                if enc then
                    Got_v  := EncLog_v.get(i);
                    Flag_v := EncLog_v.getFlag(i);
                else
                    Got_v  := DecLog_v.get(i);
                    Flag_v := DecLog_v.getFlag(i);
                end if;
                check_value(Got_v, ks(ks'low + i) & words(words'low + i), error, msg & ": word " & to_string(i));
                if checkFlg then
                    check_value(Flag_v, flags(flags'low + i), error, msg & ": CRC error flag of word " & to_string(i));
                end if;
            end loop;

        end procedure;

        procedure clearLogs is
        begin
            EncLog_v.clear;
            DecLog_v.clear;
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

            -- TC-ML-01: ECSS Figure 5-44, CRC-16 without scrambling
            if run("test_enc_crc_vectors") then
                sendWords(VvcEnc_c, Fig44In_c, Fig44K_c);
                checkLog(true, Fig44Out_c, Fig44K_c, "", false, "Figure 5-44");

            -- TC-ML-45: corrupted words (poison) invert the CRC-16 of the next EDF only: a poisoned
            -- frame, a poisoned word between frames (inverts the CRC of the next frame), a clean frame
            elsif run("test_enc_poison") then
                CodecCtrl.Poison <= '1';
                sendWords(VvcEnc_c, Fig44In_c(0 to 3), Fig44K_c(0 to 3));
                sendWords(VvcEnc_c, Fig44In_c(10 to 10), Fig44K_c(10 to 10));
                CodecCtrl.Poison <= '0';
                sendWords(VvcEnc_c, Fig44In_c(4 to 10), Fig44K_c(4 to 10));
                checkLog(true, Fig44Out_c(0 to 2) & (Fig44Out_c(3) xor x"FFFF0000") & Fig44Out_c(10) &
                         Fig44Out_c(4 to 5) & (Fig44Out_c(6) xor x"FFFF0000") & Fig44Out_c(7 to 10),
                         Fig44K_c(0 to 3) & Fig44K_c(10) & Fig44K_c(4 to 10), "", false, "Poisoned words");

            -- TC-ML-02: ECSS Figure 5-42, scrambling and CRC-16 over the scrambled data
            elsif run("test_enc_scramble_vector") then
                CodecCtrl.Scramble <= '1';
                sendWords(VvcEnc_c, Fig42In_c, Fig42K_c);
                -- Twice: the scrambler is re-seeded with every SDF
                sendWords(VvcEnc_c, Fig42In_c, Fig42K_c);
                checkLog(true, Fig42Out_c & Fig42Out_c, Fig42K_c & Fig42K_c, "", false, "Figure 5-42 scrambled");
                -- Without scrambling the EDF carries the CRC of the original data
                clearLogs;
                CodecCtrl.Scramble <= '0';
                sendWords(VvcEnc_c, Fig42In_c, Fig42K_c);
                checkLog(true, Fig42In_c(0 to 3) & Fig42Edf_c, Fig42K_c, "", false, "Figure 5-42 not scrambled");

            -- TC-ML-03: interleaved words, PAD, broadcast frames, words outside data frames
            elsif run("test_enc_interleaved") then

                for scr in 0 to 1 loop
                    clearLogs;
                    streamClear(S_v, scr = 1);
                    if scr = 1 then
                        CodecCtrl.Scramble <= '1';
                    else
                        CodecCtrl.Scramble <= '0';
                    end if;
                    -- Directed frame with every kind of word inside
                    addSdf(S_v, 3);
                    addData(S_v, x"11223344");
                    addCtrl(S_v, wordFct("010", "00011", x"05"));
                    addData(S_v, x"55667788");
                    addCtrl(S_v, wordAck(x"06"));
                    addCtrl(S_v, wordNack(x"87"));
                    addCtrl(S_v, wordFull(x"08"));
                    addCtrl(S_v, WordPad_c, KPad_c);
                    addCtrl(S_v, x"0000F1" & K28_7_c);
                    addData(S_v, x"99AABBCC");
                    addCtrl(S_v, wordSbf(x"21", x"03"), KCtrl_c, EffBcstStart);
                    addData(S_v, x"01020304");
                    addData(S_v, x"05060708");
                    addCtrl(S_v, wordEbf("00", x"09", x"5A"), KCtrl_c, EffBcstEnd);
                    addData(S_v, CharFill_c & CharEop_c & x"DDEE", "1100");
                    addEdf(S_v, 10);
                    -- Second frame right after the first one
                    addSdf(S_v, 4);
                    addData(S_v, x"CAFEBABE");
                    addEdf(S_v, 11);
                    -- Outside data frames: idle frame, broadcast frame, EDF without SDF
                    addCtrl(S_v, wordSif(x"0B"), KCtrl_c, EffEnd);
                    addData(S_v, x"DEADBEEF");
                    addCtrl(S_v, wordSbf(x"22", x"04"), KCtrl_c, EffBcstStart);
                    addData(S_v, x"0A0B0C0D");
                    addData(S_v, x"0E0F1011");
                    addCtrl(S_v, wordEbf("01", x"0C", x"A5"), KCtrl_c, EffBcstEnd);
                    addEdf(S_v, 12);
                    -- Random frames with interleaved words
                    addRandomStream(S_v, 1500, true);
                    sendWords(VvcEnc_c, S_v.Data(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                    checkLog(true, S_v.Enc(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), "", false,
                             "Interleaved words, scrambling " & to_string(scr));
                end loop;

            -- TC-ML-04: random input gaps and output back-pressure
            elsif run("test_enc_backpressure") then
                CodecCtrl.Scramble                                                     <= '1';
                CodecCtrl.RandomReady                                                  <= true;
                streamClear(S_v, true);
                addRandomStream(S_v, 2000, true);
                shared_axistream_vvc_config(VvcEnc_c).bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcEnc_c).bfm_config.valid_low_duration    := C_RANDOM;
                sendWords(VvcEnc_c, S_v.Data(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                cycles(50);
                checkLog(true, S_v.Enc(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), "", false, "Back-pressure");

            -- TC-ML-05: RETRY and SIF end a data frame, flush discards the held word
            elsif run("test_enc_abort_flush") then
                CodecCtrl.Scramble <= '1';
                streamClear(S_v, true);
                addSdf(S_v, 1);
                addData(S_v, x"12345678");
                addCtrl(S_v, WordRetry_c, KCtrl_c, EffEnd);
                addData(S_v, x"9ABCDEF0");
                addEdf(S_v, 1);
                addSdf(S_v, 2);
                addData(S_v, x"0F0F0F0F");
                addCtrl(S_v, wordSif(x"01"), KCtrl_c, EffEnd);
                addData(S_v, x"F0F0F0F0");
                addEdf(S_v, 2);
                sendWords(VvcEnc_c, S_v.Data(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                checkLog(true, S_v.Enc(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), "", false, "RETRY / SIF");
                -- Flush with a word held in the output register and inside a data frame
                clearLogs;
                CodecCtrl.HoldReady <= true;
                streamClear(S_v, true);
                addSdf(S_v, 5);
                sendWords(VvcEnc_c, S_v.Data(0 to 0), S_v.K(0 to 0));
                CodecCtrl.Flush     <= '1';
                cycles(1);
                CodecCtrl.Flush     <= '0';
                CodecCtrl.HoldReady <= false;
                cycles(5);
                check_value(EncLog_v.count, 0, error, "Held word discarded by the flush");
                -- After the flush the frame is ended: data words and EDF pass unchanged
                streamClear(S_v, true);
                addData(S_v, x"13579BDF");
                addEdf(S_v, 6);
                sendWords(VvcEnc_c, S_v.Data(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                checkLog(true, S_v.Enc(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), "", false, "After flush");

            -- TC-ML-06: decoder with the ECSS examples
            elsif run("test_dec_vectors") then
                sendWords(VvcDec_c, Fig44Out_c, Fig44K_c);
                checkLog(false, Fig44Out_c, Fig44K_c, "00000000000", true, "Figure 5-44 decoded");
                clearLogs;
                CodecCtrl.Unscramble <= '1';
                sendWords(VvcDec_c, Fig42Out_c, Fig42K_c);
                checkLog(false, Fig42In_c(0 to 3) & Fig42Out_c(4), Fig42K_c, "00000", true, "Figure 5-42 unscrambled");

            -- TC-ML-07: CRC errors
            elsif run("test_dec_crc_errors") then
                CodecCtrl.Unscramble <= '1';
                streamClear(S_v, true);

                for i in 0 to 4 loop
                    addRandomFrame(S_v, 10, false);
                end loop;

                addEdf(S_v, 99);
                Corr_v := S_v;

                -- Each frame: SDF at 12 f, data words at 12 f + 1 to 12 f + 10, EDF at 12 f + 11.
                -- Frame 0 correct; frame 1: SDF bit error; frame 2: data bit error; frame 3: EDF
                -- sequence number bit error; frame 4: CRC field bit error; then an EDF without SDF
                for f in 1 to 4 loop
                    Sdf_v := 12 * f;
                    Edf_v := 12 * f + 11;

                    case f is
                        when 1 =>
                            Corr_v.Enc(Sdf_v)(20) := not Corr_v.Enc(Sdf_v)(20);
                        when 2 =>
                            Corr_v.Enc(Sdf_v + 3)(5) := not Corr_v.Enc(Sdf_v + 3)(5);
                        when 3 =>
                            Corr_v.Enc(Edf_v)(9) := not Corr_v.Enc(Edf_v)(9);
                        when others =>
                            Corr_v.Enc(Edf_v)(30) := not Corr_v.Enc(Edf_v)(30);
                    end case;

                    Corr_v.CrcErr(Edf_v) := '1';
                end loop;

                sendWords(VvcDec_c, Corr_v.Enc(0 to Corr_v.Count-1), Corr_v.K(0 to Corr_v.Count-1));
                check_value(DecLog_v.count, Corr_v.Count, error, "Number of words");

                for i in 0 to minimum(DecLog_v.count, Corr_v.Count) - 1 loop
                    check_value(DecLog_v.getFlag(i), Corr_v.CrcErr(i), error, "CRC error flag of word " & to_string(i));
                end loop;

                check_value(Corr_v.CrcErr(Corr_v.Count-1), '1', error, "Model: EDF without SDF");

            -- TC-ML-08: decoder with interleaved words
            elsif run("test_dec_interleaved") then

                for scr in 0 to 1 loop
                    clearLogs;
                    streamClear(S_v, scr = 1);
                    if scr = 1 then
                        CodecCtrl.Unscramble <= '1';
                    else
                        CodecCtrl.Unscramble <= '0';
                    end if;
                    addRandomStream(S_v, 1500, true);
                    addEdf(S_v, 3);
                    sendWords(VvcDec_c, S_v.Enc(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                    checkLog(false, S_v.Dec(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), S_v.CrcErr(0 to S_v.Count-1),
                             true, "Interleaved words decoded, scrambling " & to_string(scr));
                end loop;

            -- TC-ML-09: loopback of random frames through encoder and decoder
            elsif run("test_codec_loopback") then
                CodecCtrl.Loopback    <= true;
                CodecCtrl.RandomReady <= true;

                for scr in 0 to 1 loop
                    clearLogs;
                    streamClear(S_v, scr = 1);
                    if scr = 1 then
                        CodecCtrl.Scramble   <= '1';
                        CodecCtrl.Unscramble <= '1';
                    else
                        CodecCtrl.Scramble   <= '0';
                        CodecCtrl.Unscramble <= '0';
                    end if;
                    addRandomStream(S_v, 3000, true);
                    sendWords(VvcEnc_c, S_v.Data(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1));
                    cycles(50);
                    checkLog(false, S_v.Dec(0 to S_v.Count-1), S_v.K(0 to S_v.Count-1), S_v.CrcErr(0 to S_v.Count-1),
                             true, "Loopback, scrambling " & to_string(scr));
                end loop;

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 10 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_ml_codec_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
