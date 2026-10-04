---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Common package of OpenFibre: ECSS-E-ST-50-11C characters, control words, word format, CRC and
-- PRBS definitions shared by all layers.
--
-- Documentation: hdl/ofb_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_pkg is

    -----------------------------------------------------------------------------------------------
    -- Characters and words
    -----------------------------------------------------------------------------------------------
    -- One 8-bit character (data value of a D-code or K-code)
    subtype Char_t is std_logic_vector(7 downto 0);

    -- One word of four characters. Character 0 (bits 7:0) is the least significant character and is
    -- sent first (ECSS 5.3.3.2a and following).
    subtype Word_t is std_logic_vector(31 downto 0);

    -- K flag of each character of a word, bit i belongs to character i
    subtype WordK_t is std_logic_vector(3 downto 0);

    -- Number of characters per word
    constant CharsPerWord_c : positive := 4;

    -- K flags of a control word that starts with a K-code and continues with three D-codes
    constant KCtrl_c : WordK_t := "0001";
    -- K flags of a data word
    constant KData_c : WordK_t := "0000";
    -- K flags of the PAD control word (four K-codes)
    constant KPad_c  : WordK_t := "1111";

    -----------------------------------------------------------------------------------------------
    -- K-codes (ECSS Table 5-11), value of Kx.y = y * 32 + x
    -----------------------------------------------------------------------------------------------
    constant K0_0_c  : Char_t := x"00"; -- Rx error symbol of RXERR (never transmitted)
    constant K28_0_c : Char_t := x"1C"; -- EDF
    constant K28_2_c : Char_t := x"5C"; -- EBF
    constant K28_3_c : Char_t := x"7C"; -- FCT
    constant K28_5_c : Char_t := x"BC"; -- Initialisation comma
    constant K28_7_c : Char_t := x"FC"; -- Comma
    constant K27_7_c : Char_t := x"FB"; -- SpaceFibre Fill
    constant K29_7_c : Char_t := x"FD"; -- SpaceFibre EOP
    constant K30_7_c : Char_t := x"FE"; -- SpaceFibre EEP

    -- Names by function
    constant CharComma_c     : Char_t := K28_7_c;
    constant CharInitComma_c : Char_t := K28_5_c;
    constant CharEdf_c       : Char_t := K28_0_c;
    constant CharEbf_c       : Char_t := K28_2_c;
    constant CharFct_c       : Char_t := K28_3_c;
    constant CharFill_c      : Char_t := K27_7_c;
    constant CharEop_c       : Char_t := K29_7_c;
    constant CharEep_c       : Char_t := K30_7_c;
    constant CharRxErr_c     : Char_t := K0_0_c;

    -----------------------------------------------------------------------------------------------
    -- Control word symbols (ECSS Table 5-12), value of Dx.y = y * 32 + x
    -----------------------------------------------------------------------------------------------
    constant SymActive_c     : Char_t := x"20"; -- D0.1
    constant SymAck_c        : Char_t := x"A2"; -- D2.5
    constant SymSif_c        : Char_t := x"44"; -- D4.2
    constant SymLostSignal_c : Char_t := x"64"; -- D4.3
    constant SymInit1_c      : Char_t := x"46"; -- D6.2
    constant SymInvInit1_c   : Char_t := x"B9"; -- D25.5
    constant SymInit2_c      : Char_t := x"A6"; -- D6.5
    constant SymInvInit2_c   : Char_t := x"59"; -- D25.2
    constant SymRetry_c      : Char_t := x"87"; -- D7.4
    constant SymLlcw_c       : Char_t := x"CE"; -- D14.6
    constant SymInvLlcw_c    : Char_t := x"31"; -- D17.1
    constant SymFull_c       : Char_t := x"6F"; -- D15.3
    constant SymIdle_c       : Char_t := x"CF"; -- D15.6
    constant SymSdf_c        : Char_t := x"50"; -- D16.2
    constant SymAlign_c      : Char_t := x"77"; -- D23.3
    constant SymInit3_c      : Char_t := x"38"; -- D24.1
    constant SymNack_c       : Char_t := x"BB"; -- D27.5
    constant SymSbf_c        : Char_t := x"5D"; -- D29.2
    constant SymStandby_c    : Char_t := x"7E"; -- D30.3
    constant SymSkip_c       : Char_t := x"7F"; -- D31.3

    -----------------------------------------------------------------------------------------------
    -- Fixed control words (ECSS Tables 5-3, 5-4, 5-7, 5-8), character 0 in bits 7:0
    -----------------------------------------------------------------------------------------------
    -- Lane control words, K flags KCtrl_c
    constant WordSkip_c     : Word_t := SymSkip_c & SymSkip_c & SymLlcw_c & K28_7_c;
    constant WordIdle_c     : Word_t := SymIdle_c & SymIdle_c & SymLlcw_c & K28_7_c;
    constant WordInit1_c    : Word_t := SymInit1_c & SymInit1_c & SymLlcw_c & K28_5_c;
    constant WordInvInit1_c : Word_t := SymInvInit1_c & SymInvInit1_c & SymInvLlcw_c & K28_5_c;
    constant WordInit2_c    : Word_t := SymInit2_c & SymInit2_c & SymLlcw_c & K28_5_c;
    constant WordInvInit2_c : Word_t := SymInvInit2_c & SymInvInit2_c & SymInvLlcw_c & K28_5_c;
    -- Multi-Lane PAD control word, K flags KPad_c
    constant WordPad_c      : Word_t := K27_7_c & K27_7_c & K27_7_c & K28_7_c;
    -- Data Link RETRY control word, K flags KCtrl_c
    constant WordRetry_c    : Word_t := x"00" & x"00" & SymRetry_c & K28_7_c;
    -- Receive error indication, K flags KCtrl_c (generated in the receiver only, ECSS 5.3.6)
    constant WordRxErr_c    : Word_t := x"00" & x"00" & x"00" & K0_0_c;

    -----------------------------------------------------------------------------------------------
    -- Fields of control words
    -----------------------------------------------------------------------------------------------
    -- INIT3 capability field (ECSS 5.3.3.8e), bit indices
    constant CapLinkReset_c     : natural := 0;
    constant CapLaneStart_c     : natural := 1;
    constant CapDataScrambled_c : natural := 2;
    constant CapMultiLane_c     : natural := 3;
    constant CapRoutingSwitch_c : natural := 4;

    -- LOST_SIGNAL reason, LOS_Cause in bits 1:0 (ECSS 5.3.3.10f)
    subtype LosCause_t is std_logic_vector(1 downto 0);
    constant LosCauseNoSignal_c : LosCause_t := "00";
    constant LosCauseRxErr_c    : LosCause_t := "01";
    constant LosCauseInit1_c    : LosCause_t := "10";

    -- EBF status field (ECSS 5.3.5.1.6c), bit indices
    constant EbfLate_c    : natural := 0;
    constant EbfDelayed_c : natural := 1;

    -- Sequence number (ECSS 5.3.5.1.2): bits 6:0 sequence count, bit 7 polarity flag
    subtype SeqNum_t is std_logic_vector(7 downto 0);
    constant SeqPolarity_c : natural := 7;

    -----------------------------------------------------------------------------------------------
    -- Control word construction (character 0 in bits 7:0, K flags KCtrl_c)
    -----------------------------------------------------------------------------------------------
    function wordInit3 (capability : in Char_t) return Word_t;

    function wordStandby (reason : in Char_t) return Word_t;

    function wordLostSignal (cause : in LosCause_t) return Word_t;

    function wordActive (act : in std_logic_vector(15 downto 0)) return Word_t;

    -- numLanes: number of active lanes (0 means 16), laneNumber: lane sending the ALIGN
    function wordAlign (
        numLanes   : in std_logic_vector(3 downto 0);
        laneNumber : in std_logic_vector(3 downto 0)) return Word_t;

    function wordSdf (vc : in std_logic_vector(4 downto 0)) return Word_t;

    function wordSbf (
        channel : in Char_t;
        bType   : in Char_t) return Word_t;

    -- Words that carry an 8-bit CRC over their first three characters (CRC computed here)
    function wordSif (seqNum : in SeqNum_t) return Word_t;

    function wordFct (
        multiplier : in std_logic_vector(2 downto 0);
        vc         : in std_logic_vector(4 downto 0);
        seqNum     : in SeqNum_t) return Word_t;

    function wordAck (seqNum : in SeqNum_t) return Word_t;

    function wordNack (seqNum : in SeqNum_t) return Word_t;

    function wordFull (seqNum : in SeqNum_t) return Word_t;

    -- EDF and EBF carry frame CRCs computed by the caller
    function wordEdf (
        seqNum : in SeqNum_t;
        crc    : in std_logic_vector(15 downto 0)) return Word_t;

    function wordEbf (
        status : in std_logic_vector(1 downto 0);
        seqNum : in SeqNum_t;
        crc    : in Char_t) return Word_t;

    -----------------------------------------------------------------------------------------------
    -- CRC (ECSS 5.7.6.4 and 5.7.6.5)
    -----------------------------------------------------------------------------------------------
    -- Both CRCs process the least significant bit of a character first and use the data value of
    -- K-codes (the K flag is ignored). The result needs no output reflection or XOR.
    -- CRC-16: x^16 + x^12 + x^5 + 1, seed 0xFFFF (data frames, per lane)
    constant Crc16Polynomial_c  : std_logic_vector(15 downto 0) := x"1021";
    constant Crc16Seed_c        : std_logic_vector(15 downto 0) := x"FFFF";
    -- CRC-8: x^8 + x^2 + x + 1, seed 0x00 (broadcast frames, SIF, FCT, ACK, NACK, FULL)
    constant Crc8Polynomial_c   : Char_t := x"07";
    constant Crc8Seed_c         : Char_t := x"00";
    -- Generics of olo_base_crc (DataWidth_g = 32) that compute both CRCs as ECSS specifies, together
    -- with the polynomial and seed constants above
    constant CrcBitOrder_c      : string  := "LSB_FIRST";
    constant CrcByteOrder_c     : string  := "LSB_FIRST";
    constant CrcBitflipOutput_c : boolean := true;

    -- Update a CRC with one character
    function crc16Update (
        crc  : in std_logic_vector(15 downto 0);
        char : in Char_t) return std_logic_vector;

    function crc8Update (
        crc  : in Char_t;
        char : in Char_t) return Char_t;

    -- CRC-8 over the first three characters of a word (control words with a CRC in character 3)
    function crc8Word3 (word : in Word_t) return Char_t;

    -----------------------------------------------------------------------------------------------
    -- PRBS (ECSS 5.7.6.2): idle frame PRBS and data scrambling, G(x) = x^16 + x^5 + x^4 + x^3 + 1,
    -- seed 0xFFFF
    -----------------------------------------------------------------------------------------------
    -- Generics of olo_base_prbs (BitsPerSymbol_g = 32) that produce the ECSS sequence, with bit 0 of
    -- Out_Data being the first bit (least significant bit of character 0). olo_base_prbs is a
    -- Fibonacci LFSR, so it uses the reciprocal polynomial and the state that follows from the
    -- ECSS seed.
    constant PrbsPolynomial_c : std_logic_vector(15 downto 0) := "1001110000000000";
    constant PrbsSeed_c       : std_logic_vector(15 downto 0) := x"FFE8";

    -- Reference implementation of the ECSS random number generator (Figure 5-41): advances the
    -- 16-bit state by 32 bits and returns the new state; prbsWord returns the 32 PRBS bits of the
    -- current state (bit 0 first).
    constant PrbsEcssSeed_c : std_logic_vector(15 downto 0) := x"FFFF";

    function prbsWord (state : in std_logic_vector(15 downto 0)) return Word_t;

    function prbsNextState (state : in std_logic_vector(15 downto 0)) return std_logic_vector;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_pkg is

    function wordInit3 (capability : in Char_t) return Word_t is
    begin
        return capability & SymInit3_c & SymLlcw_c & K28_5_c;
    end function;

    function wordStandby (reason : in Char_t) return Word_t is
    begin
        return reason & SymStandby_c & SymLlcw_c & K28_7_c;
    end function;

    function wordLostSignal (cause : in LosCause_t) return Word_t is
    begin
        return "000000" & cause & SymLostSignal_c & SymLlcw_c & K28_7_c;
    end function;

    function wordActive (act : in std_logic_vector(15 downto 0)) return Word_t is
    begin
        return act(15 downto 8) & act(7 downto 0) & SymActive_c & K28_7_c;
    end function;

    function wordAlign (
        numLanes   : in std_logic_vector(3 downto 0);
        laneNumber : in std_logic_vector(3 downto 0)) return Word_t is
        variable Lanes_v : Char_t;
    begin
        Lanes_v := laneNumber & numLanes;
        return (not Lanes_v) & Lanes_v & SymAlign_c & K28_7_c;
    end function;

    function wordSdf (vc : in std_logic_vector(4 downto 0)) return Word_t is
    begin
        return x"00" & "000" & vc & SymSdf_c & K28_7_c;
    end function;

    function wordSbf (
        channel : in Char_t;
        bType   : in Char_t) return Word_t is
    begin
        return bType & channel & SymSbf_c & K28_7_c;
    end function;

    -- Word with an 8-bit CRC over characters 0 to 2 in character 3
    function withCrc8 (word : in Word_t) return Word_t is
    begin
        return crc8Word3(word) & word(23 downto 0);
    end function;

    function wordSif (seqNum : in SeqNum_t) return Word_t is
    begin
        return withCrc8(x"00" & seqNum & SymSif_c & K28_7_c);
    end function;

    function wordFct (
        multiplier : in std_logic_vector(2 downto 0);
        vc         : in std_logic_vector(4 downto 0);
        seqNum     : in SeqNum_t) return Word_t is
    begin
        return withCrc8(x"00" & seqNum & multiplier & vc & K28_3_c);
    end function;

    function wordAck (seqNum : in SeqNum_t) return Word_t is
    begin
        return withCrc8(x"00" & seqNum & SymAck_c & K28_7_c);
    end function;

    function wordNack (seqNum : in SeqNum_t) return Word_t is
    begin
        return withCrc8(x"00" & seqNum & SymNack_c & K28_7_c);
    end function;

    function wordFull (seqNum : in SeqNum_t) return Word_t is
    begin
        return withCrc8(x"00" & seqNum & SymFull_c & K28_7_c);
    end function;

    function wordEdf (
        seqNum : in SeqNum_t;
        crc    : in std_logic_vector(15 downto 0)) return Word_t is
    begin
        return crc(15 downto 8) & crc(7 downto 0) & seqNum & K28_0_c;
    end function;

    function wordEbf (
        status : in std_logic_vector(1 downto 0);
        seqNum : in SeqNum_t;
        crc    : in Char_t) return Word_t is
    begin
        return crc & seqNum & "000000" & status & K28_2_c;
    end function;

    -- Bit-serial, LSB first: equivalent to the LFSR of ECSS Figure 5-45 with reflected output
    function crc16Update (
        crc  : in std_logic_vector(15 downto 0);
        char : in Char_t) return std_logic_vector is
        variable Crc_v : std_logic_vector(15 downto 0);
    begin
        Crc_v := crc;

        for i in 0 to 7 loop
            if (Crc_v(0) xor char(i)) = '1' then
                Crc_v := ('0' & Crc_v(15 downto 1)) xor x"8408"; -- reflected 0x1021
            else
                Crc_v := '0' & Crc_v(15 downto 1);
            end if;
        end loop;

        return Crc_v;
    end function;

    -- Bit-serial, LSB first: equivalent to the LFSR of ECSS Figure 5-47 with reflected output
    function crc8Update (
        crc  : in Char_t;
        char : in Char_t) return Char_t is
        variable Crc_v : Char_t;
    begin
        Crc_v := crc;

        for i in 0 to 7 loop
            if (Crc_v(0) xor char(i)) = '1' then
                Crc_v := ('0' & Crc_v(7 downto 1)) xor x"E0"; -- reflected 0x07
            else
                Crc_v := '0' & Crc_v(7 downto 1);
            end if;
        end loop;

        return Crc_v;
    end function;

    function crc8Word3 (word : in Word_t) return Char_t is
        variable Crc_v : Char_t;
    begin
        Crc_v := Crc8Seed_c;

        for i in 0 to 2 loop
            Crc_v := crc8Update(Crc_v, word(8*i+7 downto 8*i));
        end loop;

        return Crc_v;
    end function;

    -- One step of the Galois LFSR of ECSS Figure 5-41: output D15, shift towards D15, feedback into
    -- D0, D3, D4 and D5
    function prbsWord (state : in std_logic_vector(15 downto 0)) return Word_t is
        variable State_v : std_logic_vector(15 downto 0);
        variable Word_v  : Word_t;
    begin
        State_v := state;

        for i in 0 to 31 loop
            Word_v(i) := State_v(15);
            if State_v(15) = '1' then
                State_v := (State_v(14 downto 0) & '0') xor x"0039";
            else
                State_v := State_v(14 downto 0) & '0';
            end if;
        end loop;

        return Word_v;
    end function;

    function prbsNextState (state : in std_logic_vector(15 downto 0)) return std_logic_vector is
        variable State_v : std_logic_vector(15 downto 0);
    begin
        State_v := state;

        for i in 0 to 31 loop
            if State_v(15) = '1' then
                State_v := (State_v(14 downto 0) & '0') xor x"0039";
            else
                State_v := State_v(14 downto 0) & '0';
            end if;
        end loop;

        return State_v;
    end function;

end package body;
