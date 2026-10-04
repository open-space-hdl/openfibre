---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Package of the Data Link layer: classification of received words, item kinds of the error
-- recovery buffer, sequence number and CRC-8 helpers.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 2)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_dl_pkg is

    -- Kind of a received word
    type DlKind_t is (
        KindData, KindSdf, KindEdf, KindSbf, KindEbf, KindSif, KindFct, KindAck, KindNack, KindFull, KindRetry,
        KindRxErr, KindUnknown
    );

    -- Item kinds of the error recovery buffer (2 bits)
    subtype ErbKind_t is std_logic_vector(1 downto 0);
    constant ErbBc_c   : ErbKind_t := "00";
    constant ErbFct_c  : ErbKind_t := "01";
    constant ErbData_c : ErbKind_t := "10";

    -- Words per data frame, PRBS words per idle frame, broadcast frame data words (one lane)
    constant MaxFrameWords_c : positive := 64;
    constant BcDataWords_c   : positive := 2;

    -- Broadcast message: data (64), channel (8), B_TYPE (8), DELAYED, LATE
    constant BcWidth_c : positive := 82;

    -- Sequence numbers
    subtype SeqCount_t is unsigned(6 downto 0);

    function seqCount (seqNum : in SeqNum_t) return SeqCount_t;

    -- (a - b) mod 128
    function seqDiff (
        a : in SeqCount_t;
        b : in SeqCount_t) return natural;

    function dlWordKind (
        data : in Word_t;
        k    : in WordK_t) return DlKind_t;

    -- CRC-8 over the first n characters of a word
    function crc8Chars (
        crc  : in Char_t;
        word : in Word_t;
        n    : in natural) return Char_t;

    -- The word contains an EOP or EEP
    function wordHasEnd (
        data : in Word_t;
        k    : in WordK_t) return boolean;

    -- Character 3 of the word is an EOP, EEP or Fill (the word ends a packet or contains no data)
    function wordLastIsEnd (
        data : in Word_t;
        k    : in WordK_t) return boolean;

    -- Word of four Fills, K flags all set
    constant WordFill_c : Word_t := CharFill_c & CharFill_c & CharFill_c & CharFill_c;

    -- A word of a row (index i, row of n words)
    function rowWord (
        data : in std_logic_vector;
        i    : in natural) return Word_t;

    function rowKflags (
        k : in std_logic_vector;
        i : in natural) return WordK_t;

    -- Number of set bits of a word mask
    function countMask (mask : in std_logic_vector) return natural;

    -- Data segment and idle frame size in rows of n words for P data-sending lanes: 64 x P words
    function segmentRows (
        p : in natural;
        n : in positive) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_dl_pkg is

    function seqCount (seqNum : in SeqNum_t) return SeqCount_t is
    begin
        return unsigned(seqNum(6 downto 0));
    end function;

    function seqDiff (
        a : in SeqCount_t;
        b : in SeqCount_t) return natural is
    begin
        return to_integer(a - b);
    end function;

    function dlWordKind (
        data : in Word_t;
        k    : in WordK_t) return DlKind_t is
        variable Char0_v : Char_t;
        variable Char1_v : Char_t;
        variable Kind_v  : DlKind_t;
    begin
        Char0_v := data(7 downto 0);
        Char1_v := data(15 downto 8);
        Kind_v  := KindUnknown;
        if k(0) = '0' or Char0_v = CharFill_c or Char0_v = CharEop_c or Char0_v = CharEep_c then
            Kind_v := KindData;
        elsif Char0_v = CharEdf_c then
            Kind_v := KindEdf;
        elsif Char0_v = CharEbf_c then
            Kind_v := KindEbf;
        elsif Char0_v = CharFct_c then
            Kind_v := KindFct;
        elsif Char0_v = CharRxErr_c then
            Kind_v := KindRxErr;
        elsif Char0_v = CharComma_c and k(1) = '0' then
            if Char1_v = SymSdf_c then
                Kind_v := KindSdf;
            elsif Char1_v = SymSbf_c then
                Kind_v := KindSbf;
            elsif Char1_v = SymSif_c then
                Kind_v := KindSif;
            elsif Char1_v = SymAck_c then
                Kind_v := KindAck;
            elsif Char1_v = SymNack_c then
                Kind_v := KindNack;
            elsif Char1_v = SymFull_c then
                Kind_v := KindFull;
            elsif Char1_v = SymRetry_c then
                Kind_v := KindRetry;
            end if;
        end if;
        return Kind_v;
    end function;

    function crc8Chars (
        crc  : in Char_t;
        word : in Word_t;
        n    : in natural) return Char_t is
        variable Crc_v : Char_t;
    begin
        Crc_v := crc;

        for i in 0 to CharsPerWord_c-1 loop
            if i < n then
                Crc_v := crc8Update(Crc_v, word(8*i+7 downto 8*i));
            end if;
        end loop;

        return Crc_v;
    end function;

    function wordHasEnd (
        data : in Word_t;
        k    : in WordK_t) return boolean is
        variable End_v : boolean;
    begin
        End_v := false;

        for i in 0 to CharsPerWord_c-1 loop
            if k(i) = '1' and (data(8*i+7 downto 8*i) = CharEop_c or data(8*i+7 downto 8*i) = CharEep_c) then
                End_v := true;
            end if;
        end loop;

        return End_v;
    end function;

    function wordLastIsEnd (
        data : in Word_t;
        k    : in WordK_t) return boolean is
        variable Char3_v : Char_t;
    begin
        Char3_v := data(31 downto 24);
        return k(3) = '1' and (Char3_v = CharEop_c or Char3_v = CharEep_c or Char3_v = CharFill_c);
    end function;

    function rowWord (
        data : in std_logic_vector;
        i    : in natural) return Word_t is
        variable Data_v : std_logic_vector(data'length-1 downto 0);
    begin
        Data_v := data;
        return Data_v(32*i+31 downto 32*i);
    end function;

    function rowKflags (
        k : in std_logic_vector;
        i : in natural) return WordK_t is
        variable K_v : std_logic_vector(k'length-1 downto 0);
    begin
        K_v := k;
        return K_v(4*i+3 downto 4*i);
    end function;

    function countMask (mask : in std_logic_vector) return natural is
        variable Cnt_v : natural;
    begin
        Cnt_v := 0;

        for i in mask'range loop
            if mask(i) = '1' then
                Cnt_v := Cnt_v + 1;
            end if;
        end loop;

        return Cnt_v;
    end function;

    function segmentRows (
        p : in natural;
        n : in positive) return natural is
    begin
        return (MaxFrameWords_c * p) / n;
    end function;

end package body;
