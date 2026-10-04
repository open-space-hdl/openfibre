---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Package of the Multi-Lane layer: word classification, data frame identification of a lane
-- column, scrambling of a data word and status encodings.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (sections 2.1 and 2.2)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ml_pkg is

    -- Kind of a word as seen by the column codec
    type WordKind_t is (
        KindData, KindSdf, KindEdf, KindSbf, KindEbf, KindSif, KindRetry, KindRxErr, KindPad, KindMlCtrl,
        KindOther
    );

    -- Frame state of a lane column: outside a data frame, inside a data frame, inside a broadcast
    -- frame that is sent within a data frame
    type FrameFsm_t is (None_s, Data_s, Bcst_s);

    -- Alignment state (ECSS 5.6.7) reported to the MIB
    subtype AlignState_t is std_logic_vector(1 downto 0);
    constant AlignNotReady_c      : AlignState_t := "00";
    constant AlignNearEndReady_c  : AlignState_t := "01";
    constant AlignBothEndsReady_c : AlignState_t := "10";

    function wordKind (
        data : in Word_t;
        k    : in WordK_t) return WordKind_t;

    function frameNext (
        state : in FrameFsm_t;
        kind  : in WordKind_t) return FrameFsm_t;

    -- XOR the data characters (K flag clear) of a word with the scrambling sequence, keep K-codes
    function scrambleWord (
        data : in Word_t;
        k    : in WordK_t;
        prbs : in Word_t) return Word_t;

    -- ACTIVE control word (ECSS 5.3.4.1)
    function isActive (
        data : in Word_t;
        k    : in WordK_t) return boolean;

    -- ALIGN control word with iLANES = not LANES (ECSS 5.6.6.3e)
    function alignCorrect (
        data : in Word_t;
        k    : in WordK_t) return boolean;

    -- ALIGN control word of a hot redundant lane: LANES = iLANES = 0 (ECSS 5.6.10i)
    function alignHot (
        data : in Word_t;
        k    : in WordK_t) return boolean;

    -- Words that may be sent or passed before data words that wait for a complete row
    function interleaved (kind : in WordKind_t) return boolean;

    -- Number of set bits
    function countOnes (vec : in std_logic_vector) return natural;

    -- Number of set bits below bit idx
    function countBelow (
        vec : in std_logic_vector;
        idx : in natural) return natural;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_ml_pkg is

    function wordKind (
        data : in Word_t;
        k    : in WordK_t) return WordKind_t is
        variable Char0_v : Char_t;
        variable Char1_v : Char_t;
        variable Kind_v  : WordKind_t;
    begin
        Char0_v := data(7 downto 0);
        Char1_v := data(15 downto 8);
        Kind_v  := KindOther;
        if k(0) = '0' or Char0_v = CharFill_c or Char0_v = CharEop_c or Char0_v = CharEep_c then
            Kind_v := KindData;
        elsif Char0_v = CharEdf_c then
            Kind_v := KindEdf;
        elsif Char0_v = CharEbf_c then
            Kind_v := KindEbf;
        elsif Char0_v = CharRxErr_c then
            Kind_v := KindRxErr;
        elsif Char0_v = CharComma_c then
            if k(1) = '1' then
                if Char1_v = K27_7_c then
                    Kind_v := KindPad;
                end if;
            elsif Char1_v = SymSdf_c then
                Kind_v := KindSdf;
            elsif Char1_v = SymSbf_c then
                Kind_v := KindSbf;
            elsif Char1_v = SymSif_c then
                Kind_v := KindSif;
            elsif Char1_v = SymRetry_c then
                Kind_v := KindRetry;
            elsif Char1_v = SymActive_c or Char1_v = SymAlign_c then
                Kind_v := KindMlCtrl;
            end if;
        end if;
        return Kind_v;
    end function;

    function frameNext (
        state : in FrameFsm_t;
        kind  : in WordKind_t) return FrameFsm_t is
        variable State_v : FrameFsm_t;
    begin
        State_v := state;

        case kind is
            when KindSdf =>
                State_v := Data_s;
            when KindEdf | KindSif | KindRetry | KindRxErr =>
                State_v := None_s;
            when KindSbf =>
                if state = Data_s then
                    State_v := Bcst_s;
                end if;
            when KindEbf =>
                if state = Bcst_s then
                    State_v := Data_s;
                end if;
            when others =>
                null;
        end case;

        return State_v;
    end function;

    function scrambleWord (
        data : in Word_t;
        k    : in WordK_t;
        prbs : in Word_t) return Word_t is
        variable Word_v : Word_t;
    begin
        Word_v := data;

        for i in 0 to CharsPerWord_c-1 loop
            if k(i) = '0' then
                Word_v(8*i+7 downto 8*i) := data(8*i+7 downto 8*i) xor prbs(8*i+7 downto 8*i);
            end if;
        end loop;

        return Word_v;
    end function;

    function isActive (
        data : in Word_t;
        k    : in WordK_t) return boolean is
    begin
        return k = KCtrl_c and data(15 downto 0) = SymActive_c & K28_7_c;
    end function;

    function alignCorrect (
        data : in Word_t;
        k    : in WordK_t) return boolean is
    begin
        return k = KCtrl_c and data(15 downto 0) = SymAlign_c & K28_7_c and
               data(31 downto 24) = not data(23 downto 16);
    end function;

    function alignHot (
        data : in Word_t;
        k    : in WordK_t) return boolean is
    begin
        return k = KCtrl_c and data(15 downto 0) = SymAlign_c & K28_7_c and data(31 downto 16) = x"0000";
    end function;

    function interleaved (kind : in WordKind_t) return boolean is
    begin
        return kind = KindData or kind = KindSbf or kind = KindEbf or kind = KindOther;
    end function;

    function countOnes (vec : in std_logic_vector) return natural is
        variable Cnt_v : natural;
    begin
        Cnt_v := 0;

        for i in vec'range loop
            if vec(i) = '1' then
                Cnt_v := Cnt_v + 1;
            end if;
        end loop;

        return Cnt_v;
    end function;

    function countBelow (
        vec : in std_logic_vector;
        idx : in natural) return natural is
        variable Cnt_v : natural;
    begin
        Cnt_v := 0;

        for i in vec'low to vec'high loop
            if i < idx and vec(i) = '1' then
                Cnt_v := Cnt_v + 1;
            end if;
        end loop;

        return Cnt_v;
    end function;

end package body;
