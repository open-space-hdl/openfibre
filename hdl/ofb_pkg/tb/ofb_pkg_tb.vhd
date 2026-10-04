---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of ofb_pkg: characters, control words, CRC and PRBS against the values and examples of
-- ECSS-E-ST-50-11C.
--
-- Documentation: hdl/ofb_pkg/docs/verification_plan.md

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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pkg_tb is

    -- VVC instance indices (see ofb_pkg_th)
    constant VvcPrbs_c     : natural := 0;
    constant VvcCrc16In_c  : natural := 1;
    constant VvcCrc16Out_c : natural := 2;
    constant VvcCrc8In_c   : natural := 3;
    constant VvcCrc8Out_c  : natural := 4;

    -- Character value of Dx.y / Kx.y as defined in ECSS 5.3.2 (bits HGF = y, EDCBA = x)
    function code (
        x : natural;
        y : natural) return Char_t is
    begin
        return std_logic_vector(to_unsigned(y * 32 + x, 8));
    end function;

    -- Byte arrays of the ECSS examples (first byte transmitted first)
    type ByteArray_t is array (natural range <>) of Char_t;

    function toBytes (bytes : ByteArray_t) return t_slv_array is
        variable Arr_v : t_slv_array(0 to bytes'length-1)(7 downto 0);
    begin

        for i in 0 to bytes'length-1 loop
            Arr_v(i) := bytes(bytes'low + i);
        end loop;

        return Arr_v;
    end function;

    -- Expected CRC-16 on the 16-bit CRC output stream, as bytes (least significant byte first)
    function crcBytes (crc : std_logic_vector(15 downto 0)) return t_slv_array is
        variable Arr_v : t_slv_array(0 to 1)(7 downto 0);
    begin
        Arr_v(0) := crc(7 downto 0);
        Arr_v(1) := crc(15 downto 8);
        return Arr_v;
    end function;

    function crc16Of (bytes : ByteArray_t) return std_logic_vector is
        variable Crc_v : std_logic_vector(15 downto 0) := Crc16Seed_c;
    begin

        for i in bytes'range loop
            Crc_v := crc16Update(Crc_v, bytes(i));
        end loop;

        return Crc_v;
    end function;

    function crc8Of (bytes : ByteArray_t) return Char_t is
        variable Crc_v : Char_t := Crc8Seed_c;
    begin

        for i in bytes'range loop
            Crc_v := crc8Update(Crc_v, bytes(i));
        end loop;

        return Crc_v;
    end function;

    -- ECSS Figure 5-44: data frames up to and including the SEQ_NUM of the EDF, and their CRC-16
    constant CrcFrame1_c    : ByteArray_t := (x"FC", x"50", x"02", x"00", x"00", x"00", x"00", x"00",
                                           x"FD", x"FB", x"FB", x"FB", x"1C", x"41");
    constant CrcFrame2_c    : ByteArray_t := (x"FC", x"50", x"01", x"00", x"00", x"FD", x"FB", x"FB",
                                           x"1C", x"7D");
    constant CrcFrame3_c    : ByteArray_t := (x"FC", x"50", x"01", x"00", x"00", x"01", x"02", x"FD",
                                           x"1C", x"7E");
    -- ECSS Figure 5-46: broadcast frame up to the SEQ_NUM of the EBF (CRC-8 0x29) and FCT (0x4F)
    constant CrcBroadcast_c : ByteArray_t := (x"FC", x"5D", x"00", x"00", x"00", x"00", x"00", x"00",
                                              x"01", x"01", x"01", x"01", x"5C", x"00", x"41");
    constant CrcFct_c       : ByteArray_t := (x"7C", x"01", x"01");

    -- ECSS Figure 5-43: first three PRBS words of the first idle frame after a link reset
    constant IdlePrbs_c : WordArray_t(0 to 2) := (x"14C017FF", x"8202E7B2", x"A6286E72");

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable State_v : std_logic_vector(15 downto 0);
        variable Words_v : WordArray_t(0 to 999);
        variable Word_v  : Word_t;
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ID_POS_ACK);
        wait for 200 ns;

        while test_suite loop

            -- TC-PKG-01: K-codes and control word symbols (ECSS Tables 5-11, 5-12, 5-9, 5-10)
            if run("test_symbols") then
                check_value(K0_0_c, code(0, 0), error, "K0.0 RXERR");
                check_value(K28_0_c, code(28, 0), error, "K28.0 EDF");
                check_value(K28_2_c, code(28, 2), error, "K28.2 EBF");
                check_value(K28_3_c, code(28, 3), error, "K28.3 FCT");
                check_value(K28_5_c, code(28, 5), error, "K28.5 initialisation comma");
                check_value(K28_7_c, code(28, 7), error, "K28.7 comma");
                check_value(K27_7_c, code(27, 7), error, "K27.7 Fill");
                check_value(K29_7_c, code(29, 7), error, "K29.7 EOP");
                check_value(K30_7_c, code(30, 7), error, "K30.7 EEP");
                check_value(SymActive_c, code(0, 1), error, "D0.1 ACTIVE");
                check_value(SymAck_c, code(2, 5), error, "D2.5 ACK");
                check_value(SymSif_c, code(4, 2), error, "D4.2 SIF");
                check_value(SymLostSignal_c, code(4, 3), error, "D4.3 LOST_SIGNAL");
                check_value(SymInit1_c, code(6, 2), error, "D6.2 INIT1");
                check_value(SymInvInit1_c, code(25, 5), error, "D25.5 iINIT1");
                check_value(SymInit2_c, code(6, 5), error, "D6.5 INIT2");
                check_value(SymInvInit2_c, code(25, 2), error, "D25.2 iINIT2");
                check_value(SymRetry_c, code(7, 4), error, "D7.4 RETRY");
                check_value(SymLlcw_c, code(14, 6), error, "D14.6 LLCW");
                check_value(SymInvLlcw_c, code(17, 1), error, "D17.1 iLLCW");
                check_value(SymFull_c, code(15, 3), error, "D15.3 FULL");
                check_value(SymIdle_c, code(15, 6), error, "D15.6 IDLE");
                check_value(SymSdf_c, code(16, 2), error, "D16.2 SDF");
                check_value(SymAlign_c, code(23, 3), error, "D23.3 ALIGN");
                check_value(SymInit3_c, code(24, 1), error, "D24.1 INIT3");
                check_value(SymNack_c, code(27, 5), error, "D27.5 NACK");
                check_value(SymSbf_c, code(29, 2), error, "D29.2 SBF");
                check_value(SymStandby_c, code(30, 3), error, "D30.3 STANDBY");
                check_value(SymSkip_c, code(31, 3), error, "D31.3 SKIP");

            -- TC-PKG-02: control word layouts (ECSS Tables 5-3 to 5-8, character 0 in bits 7:0)
            elsif run("test_control_words") then
                check_value(WordSkip_c, code(31, 3) & code(31, 3) & code(14, 6) & code(28, 7), error, "SKIP");
                check_value(WordIdle_c, code(15, 6) & code(15, 6) & code(14, 6) & code(28, 7), error, "IDLE");
                check_value(WordInit1_c, code(6, 2) & code(6, 2) & code(14, 6) & code(28, 5), error, "INIT1");
                check_value(WordInvInit1_c, code(25, 5) & code(25, 5) & code(17, 1) & code(28, 5), error,
                            "iINIT1");
                check_value(WordInit2_c, code(6, 5) & code(6, 5) & code(14, 6) & code(28, 5), error, "INIT2");
                check_value(WordInvInit2_c, code(25, 2) & code(25, 2) & code(17, 1) & code(28, 5), error,
                            "iINIT2");
                check_value(wordInit3(x"A5"), x"A5" & code(24, 1) & code(14, 6) & code(28, 5), error, "INIT3");
                check_value(wordStandby(x"0B"), x"0B" & code(30, 3) & code(14, 6) & code(28, 7), error,
                            "STANDBY");
                check_value(wordLostSignal(LosCauseRxErr_c), x"01" & code(4, 3) & code(14, 6) & code(28, 7), error,
                            "LOST_SIGNAL");
                check_value(wordActive(x"1234"), x"12" & x"34" & code(0, 1) & code(28, 7), error, "ACTIVE");
                check_value(wordAlign("0100", "0010"), x"DB" & x"24" & code(23, 3) & code(28, 7), error, "ALIGN");
                check_value(WordPad_c, code(27, 7) & code(27, 7) & code(27, 7) & code(28, 7), error, "PAD");
                check_value(wordSdf("10101"), x"00" & x"15" & code(16, 2) & code(28, 7), error, "SDF");
                check_value(wordEdf(x"81", x"BEEF"), x"BE" & x"EF" & x"81" & code(28, 0), error, "EDF");
                check_value(wordSbf(x"07", x"C3"), x"C3" & x"07" & code(29, 2) & code(28, 7), error, "SBF");
                check_value(wordEbf("10", x"05", x"6A"), x"6A" & x"05" & x"02" & code(28, 2), error, "EBF");
                check_value(WordRetry_c, x"00" & x"00" & code(7, 4) & code(28, 7), error, "RETRY");
                check_value(WordRxErr_c, x"00" & x"00" & x"00" & code(0, 0), error, "RXERR");
                -- Words with a CRC-8 over their first three characters
                Word_v := wordSif(x"83");
                check_value(Word_v(23 downto 0), x"83" & code(4, 2) & code(28, 7), error, "SIF");
                check_value(Word_v(31 downto 24), crc8Of((code(28, 7), code(4, 2), x"83")), error, "SIF CRC");
                Word_v := wordFct("101", "00011", x"04");
                check_value(Word_v(23 downto 0), x"04" & x"A3" & code(28, 3), error, "FCT");
                check_value(Word_v(31 downto 24), crc8Of((code(28, 3), x"A3", x"04")), error, "FCT CRC");
                Word_v := wordAck(x"10");
                check_value(Word_v(23 downto 0), x"10" & code(2, 5) & code(28, 7), error, "ACK");
                check_value(Word_v(31 downto 24), crc8Of((code(28, 7), code(2, 5), x"10")), error, "ACK CRC");
                Word_v := wordNack(x"11");
                check_value(Word_v(23 downto 0), x"11" & code(27, 5) & code(28, 7), error, "NACK");
                check_value(Word_v(31 downto 24), crc8Of((code(28, 7), code(27, 5), x"11")), error, "NACK CRC");
                Word_v := wordFull(x"12");
                check_value(Word_v(23 downto 0), x"12" & code(15, 3) & code(28, 7), error, "FULL");
                check_value(Word_v(31 downto 24), crc8Of((code(28, 7), code(15, 3), x"12")), error, "FULL CRC");

            -- TC-PKG-03: CRC functions against ECSS Figures 5-44 and 5-46
            elsif run("test_crc_functions") then
                check_value(crc16Of(CrcFrame1_c), x"978A", error, "CRC-16 Figure 5-44 frame 1");
                check_value(crc16Of(CrcFrame2_c), x"353D", error, "CRC-16 Figure 5-44 frame 2");
                check_value(crc16Of(CrcFrame3_c), x"B7A1", error, "CRC-16 Figure 5-44 frame 3");
                -- CRC over the bytes and the CRC itself (LS byte first) is zero (ECSS 5.7.6.4 note 2)
                check_value(crc16Of(CrcFrame1_c & ByteArray_t'(x"8A", x"97")), x"0000", error,
                            "CRC-16 syndrome");
                check_value(crc8Of(CrcBroadcast_c), x"29", error, "CRC-8 Figure 5-46 broadcast frame");
                check_value(crc8Of(CrcFct_c), x"4F", error, "CRC-8 Figure 5-46 FCT");
                check_value(crc8Of(CrcFct_c & ByteArray_t'(0 => x"4F")), x"00", error, "CRC-8 syndrome");
                Word_v := wordFct("000", "00001", x"01");
                check_value(Word_v(31 downto 24), x"4F", error, "wordFct CRC of Figure 5-46");

            -- TC-PKG-04: olo_base_crc with the ofb_pkg settings computes the ECSS CRCs
            elsif run("test_crc_open_logic") then
                axistream_transmit(AXISTREAM_VVCT, VvcCrc16In_c, toBytes(CrcFrame1_c), "Figure 5-44 frame 1");
                axistream_expect(AXISTREAM_VVCT, VvcCrc16Out_c, crcBytes(x"978A"), "CRC-16 frame 1");
                axistream_transmit(AXISTREAM_VVCT, VvcCrc16In_c, toBytes(CrcFrame2_c), "Figure 5-44 frame 2");
                axistream_expect(AXISTREAM_VVCT, VvcCrc16Out_c, crcBytes(x"353D"), "CRC-16 frame 2");
                axistream_transmit(AXISTREAM_VVCT, VvcCrc16In_c, toBytes(CrcFrame3_c), "Figure 5-44 frame 3");
                axistream_expect(AXISTREAM_VVCT, VvcCrc16Out_c, crcBytes(x"B7A1"), "CRC-16 frame 3");
                axistream_transmit(AXISTREAM_VVCT, VvcCrc8In_c, toBytes(CrcBroadcast_c), "Figure 5-46 broadcast");
                axistream_expect(AXISTREAM_VVCT, VvcCrc8Out_c, t_slv_array'(0 => x"29"), "CRC-8 broadcast");
                axistream_transmit(AXISTREAM_VVCT, VvcCrc8In_c, toBytes(CrcFct_c), "Figure 5-46 FCT");
                axistream_expect(AXISTREAM_VVCT, VvcCrc8Out_c, t_slv_array'(0 => x"4F"), "CRC-8 FCT");
                await_completion(AXISTREAM_VVCT, VvcCrc16Out_c, 10 us, "CRC-16 results");
                await_completion(AXISTREAM_VVCT, VvcCrc8Out_c, 10 us, "CRC-8 results");

            -- TC-PKG-05: reference PRBS against ECSS Figures 5-43 and 5-42
            elsif run("test_prbs_reference") then
                State_v := PrbsEcssSeed_c;

                for i in IdlePrbs_c'range loop
                    check_value(prbsWord(State_v), IdlePrbs_c(i), error, "Figure 5-43 word " & to_string(i));
                    State_v := prbsNextState(State_v);
                end loop;

                -- Figure 5-42: scrambled data words of a short data frame (data XOR PRBS, re-seeded)
                State_v := PrbsEcssSeed_c;
                check_value(x"03020100" xor prbsWord(State_v), x"17C216FF", error, "Figure 5-42 word 1");
                State_v := prbsNextState(State_v);
                check_value(x"07060504" xor prbsWord(State_v), x"8504E2B6", error, "Figure 5-42 word 2");
                State_v := prbsNextState(State_v);
                check_value(x"08" xor prbsWord(State_v)(7 downto 0), x"7A", error, "Figure 5-42 word 3");

            -- TC-PKG-06: olo_base_prbs with the ofb_pkg settings produces the ECSS sequence
            elsif run("test_prbs_open_logic") then
                State_v := PrbsEcssSeed_c;

                for i in Words_v'range loop
                    Words_v(i) := prbsWord(State_v);
                    State_v    := prbsNextState(State_v);
                end loop;

                check_value(Words_v(0 to 2) = IdlePrbs_c, error, "Reference model reproduces Figure 5-43");
                axistream_expect(AXISTREAM_VVCT, VvcPrbs_c, toSlvArray(Words_v), "1000 PRBS words");
                await_completion(AXISTREAM_VVCT, VvcPrbs_c, 100 us, "PRBS words");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_pkg_th;

end architecture;
