---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reference model and stimulus generator of the Multi-Lane layer testbenches. A stream holds the
-- words the Data Link layer sends and, computed with the ofb_pkg reference functions while the
-- stream is built, the expected column encoder output, the expected decoded words and the
-- expected CRC error flags. The role of every word is known from the way it is added, so the
-- model does not depend on the word classification of the RTL.
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

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ml_tb_pkg is

    constant MaxStream_c : positive := 8192;

    -- Effect of a control word on the frame state of the model
    type Effect_t is (EffNone, EffEnd, EffBcstStart, EffBcstEnd);

    type Stream_t is record
        Data     : WordArray_t(0 to MaxStream_c-1);      -- Words sent by the Data Link layer
        K        : WordKArray_t(0 to MaxStream_c-1);
        Enc      : WordArray_t(0 to MaxStream_c-1);      -- Expected column encoder output
        Dec      : WordArray_t(0 to MaxStream_c-1);      -- Expected column decoder output
        CrcErr   : std_logic_vector(0 to MaxStream_c-1); -- Expected CRC error flag
        Drop     : std_logic_vector(0 to MaxStream_c-1); -- Multi-Lane control word (not passed up)
        Count    : natural;
        Scramble : boolean;
        InFrame  : boolean;
        InBcst   : boolean;
        Prbs     : std_logic_vector(15 downto 0);
        Crc      : std_logic_vector(15 downto 0);
    end record;

    procedure streamClear (
        s        : inout Stream_t;
        scramble : in    boolean);

    procedure addSdf (
        s  : inout Stream_t;
        vc : in    natural);

    procedure addData (
        s    : inout Stream_t;
        data : in    Word_t;
        k    : in    WordK_t := KData_c);

    procedure addEdf (
        s   : inout Stream_t;
        seq : in    natural);

    procedure addCtrl (
        s      : inout Stream_t;
        data   : in    Word_t;
        k      : in    WordK_t  := KCtrl_c;
        effect : in    Effect_t := EffNone;
        drop   : in    boolean  := false);

    -- Random data word, sometimes with EOP / EEP / Fill characters
    impure function randomDataWord return std_logic_vector;

    -- Random Data Link control word that does not change the frame state (FCT, ACK, NACK, FULL,
    -- unknown control word)
    impure function randomCtrlWord return Word_t;

    -- Data frame with len data words; with interleave, control words, PAD (pad) and broadcast
    -- frames are inserted between the data words
    procedure addRandomFrame (
        s          : inout Stream_t;
        len        : in    positive;
        interleave : in    boolean;
        pad        : in    boolean := true);

    -- Mix of data frames, idle frames, broadcast frames and control words of at least n words
    procedure addRandomStream (
        s          : inout Stream_t;
        n          : in    positive;
        interleave : in    boolean;
        pad        : in    boolean := true);

    -- Log of output words with a flag
    type CodecLog_t is protected

        procedure push (
            word : KWord_t;
            flag : std_logic);

        procedure clear;
        impure function count return natural;
        impure function get (idx : natural) return KWord_t;
        impure function getFlag (idx : natural) return std_logic;
    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_ml_tb_pkg is

    procedure push (
        s      : inout Stream_t;
        data   : in    Word_t;
        k      : in    WordK_t;
        enc    : in    Word_t;
        dec    : in    Word_t;
        crcErr : in    std_logic;
        drop   : in    boolean) is
    begin
        assert s.Count < MaxStream_c
            report "ofb_ml_tb_pkg: stream full"
            severity failure;
        s.Data(s.Count)   := data;
        s.K(s.Count)      := k;
        s.Enc(s.Count)    := enc;
        s.Dec(s.Count)    := dec;
        s.CrcErr(s.Count) := crcErr;
        if drop then
            s.Drop(s.Count) := '1';
        else
            s.Drop(s.Count) := '0';
        end if;
        s.Count := s.Count + 1;
    end procedure;

    procedure crcChars (
        s     : inout Stream_t;
        word  : in    Word_t;
        chars : in    natural) is
    begin

        for i in 0 to chars-1 loop
            s.Crc := crc16Update(s.Crc, word(8*i+7 downto 8*i));
        end loop;

    end procedure;

    procedure streamClear (
        s        : inout Stream_t;
        scramble : in    boolean) is
    begin
        s.Count    := 0;
        s.Scramble := scramble;
        s.InFrame  := false;
        s.InBcst   := false;
        s.Prbs     := PrbsEcssSeed_c;
        s.Crc      := Crc16Seed_c;
    end procedure;

    procedure addSdf (
        s  : inout Stream_t;
        vc : in    natural) is
        variable Word_v : Word_t;
    begin
        Word_v    := wordSdf(std_logic_vector(to_unsigned(vc, 5)));
        s.InFrame := true;
        s.InBcst  := false;
        s.Prbs    := PrbsEcssSeed_c;
        s.Crc     := Crc16Seed_c;
        crcChars(s, Word_v, 4);
        push(s, Word_v, KCtrl_c, Word_v, Word_v, '0', false);
    end procedure;

    procedure addData (
        s    : inout Stream_t;
        data : in    Word_t;
        k    : in    WordK_t := KData_c) is
        variable Enc_v  : Word_t;
        variable Prbs_v : Word_t;
    begin
        Enc_v := data;
        if s.InFrame and not s.InBcst then
            if s.Scramble then
                Prbs_v := prbsWord(s.Prbs);

                for i in 0 to 3 loop
                    if k(i) = '0' then
                        Enc_v(8*i+7 downto 8*i) := data(8*i+7 downto 8*i) xor Prbs_v(8*i+7 downto 8*i);
                    end if;
                end loop;

            end if;
            s.Prbs := prbsNextState(s.Prbs);
            crcChars(s, Enc_v, 4);
        end if;
        push(s, data, k, Enc_v, data, '0', false);
    end procedure;

    procedure addEdf (
        s   : inout Stream_t;
        seq : in    natural) is
        variable Word_v : Word_t;
        variable Enc_v  : Word_t;
        variable Err_v  : std_logic;
    begin
        Word_v := wordEdf(std_logic_vector(to_unsigned(seq, 8)), x"0000");
        Enc_v  := Word_v;
        Err_v  := '1';
        if s.InFrame and not s.InBcst then
            crcChars(s, Word_v, 2);
            Enc_v := wordEdf(std_logic_vector(to_unsigned(seq, 8)), s.Crc);
            Err_v := '0';
        end if;
        s.InFrame := false;
        s.InBcst  := false;
        push(s, Word_v, KCtrl_c, Enc_v, Enc_v, Err_v, false);
    end procedure;

    procedure addCtrl (
        s      : inout Stream_t;
        data   : in    Word_t;
        k      : in    WordK_t  := KCtrl_c;
        effect : in    Effect_t := EffNone;
        drop   : in    boolean  := false) is
    begin

        case effect is
            when EffEnd =>
                s.InFrame := false;
                s.InBcst  := false;
            when EffBcstStart =>
                s.InBcst := s.InFrame;
            when EffBcstEnd =>
                s.InBcst := false;
            when others =>
                null;
        end case;

        push(s, data, k, data, data, '0', drop);
    end procedure;

    impure function randomDataWord return std_logic_vector is
        variable Word_v : Word_t;
        variable K_v    : WordK_t;
        variable Pos_v  : natural;
    begin
        Word_v := random(32);
        K_v    := KData_c;
        -- One word in eight ends a packet: EOP or EEP followed by Fill characters
        if random(0, 7) = 0 then
            Pos_v := random(0, 3);
            if random(0, 1) = 0 then
                Word_v(8*Pos_v+7 downto 8*Pos_v) := CharEop_c;
            else
                Word_v(8*Pos_v+7 downto 8*Pos_v) := CharEep_c;
            end if;
            K_v(Pos_v) := '1';

            for i in Pos_v+1 to 3 loop
                Word_v(8*i+7 downto 8*i) := CharFill_c;
                K_v(i)                   := '1';
            end loop;

        end if;
        return K_v & Word_v;
    end function;

    impure function randomCtrlWord return Word_t is
        variable Seq_v  : SeqNum_t;
        variable Word_v : Word_t;
    begin
        Seq_v := random(8);

        case random(0, 4) is
            when 0 =>
                Word_v := wordFct(random(3), random(5), Seq_v);
            when 1 =>
                Word_v := wordAck(Seq_v);
            when 2 =>
                Word_v := wordNack(Seq_v);
            when 3 =>
                Word_v := wordFull(Seq_v);
            when others =>
                -- Unknown control word (symbol not defined by ECSS)
                Word_v := random(8) & random(8) & x"F1" & K28_7_c;
        end case;

        return Word_v;
    end function;

    procedure addRandomFrame (
        s          : inout Stream_t;
        len        : in    positive;
        interleave : in    boolean;
        pad        : in    boolean := true) is
        variable Rnd_v : std_logic_vector(35 downto 0);
    begin
        addSdf(s, random(0, 31));

        for i in 1 to len loop
            if interleave and random(0, 7) = 0 then

                case random(0, 3) is
                    when 0 =>
                        if pad then
                            addCtrl(s, WordPad_c, KPad_c);
                        else
                            addCtrl(s, randomCtrlWord);
                        end if;
                    when 1 =>
                        -- Broadcast frame inside the data frame
                        addCtrl(s, wordSbf(random(8), random(8)), KCtrl_c, EffBcstStart);
                        addData(s, random(32));
                        addData(s, random(32));
                        addCtrl(s, wordEbf(random(2), random(8), random(8)), KCtrl_c, EffBcstEnd);
                    when others =>
                        addCtrl(s, randomCtrlWord);
                end case;

            end if;
            Rnd_v := randomDataWord;
            addData(s, Rnd_v(31 downto 0), Rnd_v(35 downto 32));
        end loop;

        addEdf(s, random(0, 255));
    end procedure;

    procedure addRandomStream (
        s          : inout Stream_t;
        n          : in    positive;
        interleave : in    boolean;
        pad        : in    boolean := true) is
        variable Start_v : natural;
    begin
        Start_v := s.Count;

        while s.Count - Start_v < n loop

            case random(0, 9) is
                when 0 =>
                    -- Idle frame
                    addCtrl(s, wordSif(random(8)), KCtrl_c, EffEnd);

                    for i in 1 to random(1, 8) loop
                        addData(s, random(32));
                    end loop;

                when 1 =>
                    -- Broadcast frame outside a data frame
                    addCtrl(s, wordSbf(random(8), random(8)), KCtrl_c, EffBcstStart);
                    addData(s, random(32));
                    addData(s, random(32));
                    addCtrl(s, wordEbf(random(2), random(8), random(8)), KCtrl_c, EffBcstEnd);
                when 2 =>
                    addCtrl(s, randomCtrlWord);
                when others =>
                    addRandomFrame(s, random(1, 64), interleave, pad);
            end case;

        end loop;

    end procedure;

    type CodecLog_t is protected body

        type KWordArray_t is array (0 to 16383) of KWord_t;

        variable Words_v : KWordArray_t;
        variable Flags_v : std_logic_vector(0 to 16383);
        variable Count_v : natural := 0;

        procedure push (
            word : KWord_t;
            flag : std_logic) is
        begin
            if Count_v <= KWordArray_t'high then
                Words_v(Count_v) := word;
                Flags_v(Count_v) := flag;
            end if;
            Count_v := Count_v + 1;
        end procedure;

        procedure clear is
        begin
            Count_v := 0;
        end procedure;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        impure function get (idx : natural) return KWord_t is
        begin
            return Words_v(idx);
        end function;

        impure function getFlag (idx : natural) return std_logic is
        begin
            return Flags_v(idx);
        end function;

    end protected body;

end package body;
