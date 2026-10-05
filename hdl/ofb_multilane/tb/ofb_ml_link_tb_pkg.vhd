---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Package of the multi-lane link testbench: configuration and status of the two ends, transmit
-- row queues, expected streams per direction and the generator of random traffic at row level.
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
    use work.ofb_ml_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_ml_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ml_link_tb_pkg is

    constant MaxLanes_c : positive := 4;

    -- Row of the Data Link layer (words beyond NumLanes_g are not used)
    type TbRow_t is record
        Data      : std_logic_vector(32*MaxLanes_c-1 downto 0);
        K         : std_logic_vector(4*MaxLanes_c-1 downto 0);
        Mask      : std_logic_vector(MaxLanes_c-1 downto 0);
        Replicate : std_logic;
    end record;

    type RowQueue_t is protected

        procedure push (row : TbRow_t);

        impure function pop return TbRow_t;
        impure function count return natural;

        procedure clear;
    end protected;

    -- Inputs of one end, driven by the test sequencer
    type LinkCfg_t is record
        NearCapability : Char_t;
        LinkReset      : std_logic;
        LaneReset      : std_logic;
        LaneStart      : std_logic_vector(MaxLanes_c-1 downto 0);
        TxEn           : std_logic_vector(MaxLanes_c-1 downto 0);
        RxEn           : std_logic_vector(MaxLanes_c-1 downto 0);
        MaxDataLanes   : std_logic_vector(2 downto 0);
        Bypass         : std_logic;
        Check          : boolean;   -- Compare the received rows with the expected stream
        Poison         : std_logic; -- Rows sent are marked as corrupted (TxRow_Poison)
    end record;

    constant LinkCfgDefault_c : LinkCfg_t := (
        NearCapability => x"04",
        LinkReset      => '0',
        LaneReset      => '0',
        LaneStart      => (others => '0'),
        TxEn           => (others => '1'),
        RxEn           => (others => '1'),
        MaxDataLanes   => "000",
        Bypass         => '0',
        Check          => true,
        Poison         => '0'
    );

    -- Outputs of one end, collected by the harness
    type LinkStat_t is record
        AlignState    : AlignState_t;
        DataSending   : std_logic_vector(MaxLanes_c-1 downto 0);
        DataReceiving : std_logic_vector(MaxLanes_c-1 downto 0);
        Bypass        : std_logic;
        LaneActive    : std_logic_vector(MaxLanes_c-1 downto 0); -- Lane layer in Active
        LaneReset     : std_logic_vector(MaxLanes_c-1 downto 0);
        ResetSeen     : std_logic_vector(MaxLanes_c-1 downto 0); -- LaneReset asserted since the start
        TxOnly        : std_logic_vector(MaxLanes_c-1 downto 0);
        RxOnly        : std_logic_vector(MaxLanes_c-1 downto 0);
        FarEndActive  : std_logic_vector(MaxLanes_c-1 downto 0);
        NearCap0      : Char_t;                                  -- Near-end capability of lane 0
        FarCapability : Char_t;                                  -- Dl_FarCapability
        -- Rows passed to the Data Link layer
        Frames        : natural;                                 -- Complete data frames
        CtrlWords     : natural;                                 -- Control words and broadcast words compared
        RxErrs        : natural;                                 -- RXERR rows
        AnyErrs       : natural;                                 -- RXERR rows and EDF with CRC error
        CrcErrs       : natural;                                 -- EDF with CRC error while checking
        CheckErrs     : natural;                                 -- Mismatches with the expected stream
        MidPartial    : natural;                                 -- Incomplete data row inside a frame while checking
        Misaligned    : natural;                                 -- Ev_Misaligned
        -- Words sent on the lanes
        SkipAsync     : natural;                                 -- Cycles with SKIP on some but not all transmitting lanes
        Skips         : natural;                                 -- Cycles with SKIP on all transmitting lanes
        NrActive      : natural;                                 -- ACTIVE words in Not Ready
        NrAlign       : natural;                                 -- ALIGN words in Not Ready
        NerAlign      : natural;                                 -- ALIGN words in Near-End Ready
        BerMlWords    : natural;                                 -- ACTIVE and ALIGN words in Both-Ends Ready
        PatternErr    : natural;                                 -- Not 7 words between two ALIGN words (Not Ready, Near-End Ready)
        PadMisuse     : natural;                                 -- PAD not followed by the end of a data frame on its lane
        HotDlWords    : natural;                                 -- Data Link framing words on lanes that are not data-sending
        IdleWords     : natural;                                 -- IDLE words on data-sending lanes in Both-Ends Ready
        LastAlign     : WordArray_t(0 to MaxLanes_c-1);          -- Last ALIGN word sent per lane
        LastActive    : Word_t;                                  -- Last ACTIVE word sent
    end record;

    type LinkCfgArray_t is array (0 to 1) of LinkCfg_t;
    type LinkStatArray_t is array (0 to 1) of LinkStat_t;

    signal LinkCfg  : LinkCfgArray_t := (others => LinkCfgDefault_c);
    signal LinkStat : LinkStatArray_t;

    -- Transmit rows of A and B
    shared variable TxQueueA_v : RowQueue_t;
    shared variable TxQueueB_v : RowQueue_t;

    -- Expected streams: data frames (SDF, data words, EDF) and other words (control words, SBF,
    -- broadcast words, EBF, SIF) sent by A (received at B) and sent by B
    shared variable ExpFrameA_v : WordQueue_t;
    shared variable ExpCtrlA_v  : WordQueue_t;
    shared variable ExpFrameB_v : WordQueue_t;
    shared variable ExpCtrlB_v  : WordQueue_t;

    -- Traffic generator: rows of n words sent by end src
    procedure txRow (
        src : natural;
        row : TbRow_t);

    procedure txReplicated (
        src  : natural;
        word : Word_t;
        k    : WordK_t := KCtrl_c);

    -- Data frame with len data words over rows of n words; with interleave, control words and
    -- broadcast frames between the rows
    procedure txFrame (
        src        : natural;
        n          : positive;
        vc         : natural;
        len        : positive;
        seq        : natural;
        interleave : boolean);

    -- Mix of data frames, control words, broadcast frames and idle frames
    procedure txTraffic (
        src    : natural;
        n      : positive;
        frames : positive;
        maxLen : positive := 200);

    -- All rows sent and all expected words received
    impure function trafficDone return boolean;

    -- All rows sent
    impure function rowsSent return boolean;

    procedure clearTraffic;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_ml_link_tb_pkg is

    type RowQueue_t is protected body

        type Rows_t is array (0 to 16383) of TbRow_t;

        variable Rows_v  : Rows_t;
        variable Head_v  : natural := 0;
        variable Count_v : natural := 0;

        procedure push (row : TbRow_t) is
        begin
            assert Count_v < Rows_t'length
                report "RowQueue_t full"
                severity failure;
            Rows_v((Head_v + Count_v) mod Rows_t'length) := row;
            Count_v                                      := Count_v + 1;
        end procedure;

        impure function pop return TbRow_t is
            variable Row_v : TbRow_t;
        begin
            Row_v   := Rows_v(Head_v);
            Head_v  := (Head_v + 1) mod Rows_t'length;
            Count_v := Count_v - 1;
            return Row_v;
        end function;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        procedure clear is
        begin
            Count_v := 0;
        end procedure;

    end protected body;

    procedure expFrame (
        src  : natural;
        word : Word_t;
        k    : WordK_t) is
    begin
        if src = 0 then
            ExpFrameA_v.push('0' & k & word);
        else
            ExpFrameB_v.push('0' & k & word);
        end if;
    end procedure;

    procedure expCtrl (
        src  : natural;
        word : Word_t;
        k    : WordK_t) is
    begin
        if src = 0 then
            ExpCtrlA_v.push('0' & k & word);
        else
            ExpCtrlB_v.push('0' & k & word);
        end if;
    end procedure;

    procedure txRow (
        src : natural;
        row : TbRow_t) is
    begin
        if src = 0 then
            TxQueueA_v.push(row);
        else
            TxQueueB_v.push(row);
        end if;
    end procedure;

    procedure txReplicated (
        src  : natural;
        word : Word_t;
        k    : WordK_t := KCtrl_c) is
        variable Row_v : TbRow_t;
    begin
        Row_v.Data              := (others => '0');
        Row_v.K                 := (others => '0');
        Row_v.Mask              := "0001";
        Row_v.Replicate         := '1';
        Row_v.Data(31 downto 0) := word;
        Row_v.K(3 downto 0)     := k;
        txRow(src, Row_v);
    end procedure;

    -- Control word between or inside frames (FCT, ACK, NACK, FULL, unknown)
    procedure txCtrl (src : natural) is
        variable Word_v : Word_t;
    begin
        Word_v := randomCtrlWord;
        txReplicated(src, Word_v);
        expCtrl(src, Word_v, KCtrl_c);
    end procedure;

    -- Broadcast frame: SBF, two broadcast words, EBF
    procedure txBroadcast (src : natural) is
        variable Word_v : Word_t;
    begin
        Word_v := wordSbf(random(8), random(8));
        txReplicated(src, Word_v);
        expCtrl(src, Word_v, KCtrl_c);

        for i in 1 to 2 loop
            Word_v := random(32);
            txReplicated(src, Word_v, KData_c);
            expCtrl(src, Word_v, KData_c);
        end loop;

        Word_v := random(8) & random(8) & random(8) & CharEbf_c;
        txReplicated(src, Word_v);
        expCtrl(src, Word_v, KCtrl_c);
    end procedure;

    procedure txFrame (
        src        : natural;
        n          : positive;
        vc         : natural;
        len        : positive;
        seq        : natural;
        interleave : boolean) is
        variable Row_v  : TbRow_t;
        variable Word_v : std_logic_vector(35 downto 0);
        variable Pos_v  : natural;
        variable Left_v : natural;
        variable Edf_v  : Word_t;
    begin
        txReplicated(src, wordSdf(std_logic_vector(to_unsigned(vc mod 32, 5))));
        expFrame(src, wordSdf(std_logic_vector(to_unsigned(vc mod 32, 5))), KCtrl_c);
        Left_v := len;

        while Left_v > 0 loop
            Row_v.Data      := (others => '0');
            Row_v.K         := (others => '0');
            Row_v.Mask      := (others => '0');
            Row_v.Replicate := '0';
            Pos_v           := 0;

            while Pos_v < n and Left_v > 0 loop
                Word_v                                  := randomDataWord;
                Row_v.Data(32*Pos_v+31 downto 32*Pos_v) := Word_v(31 downto 0);
                Row_v.K(4*Pos_v+3 downto 4*Pos_v)       := Word_v(35 downto 32);
                Row_v.Mask(Pos_v)                       := '1';
                expFrame(src, Word_v(31 downto 0), Word_v(35 downto 32));
                Pos_v                                   := Pos_v + 1;
                Left_v                                  := Left_v - 1;
            end loop;

            txRow(src, Row_v);
            if interleave and Left_v > 0 then

                case random(0, 15) is
                    when 0 | 1 | 2 =>
                        txCtrl(src);
                    when 3 =>
                        txBroadcast(src);
                    when others =>
                        null;
                end case;

            end if;
        end loop;

        Edf_v := x"0000" & std_logic_vector(to_unsigned(seq mod 256, 8)) & CharEdf_c;
        txReplicated(src, Edf_v);
        expFrame(src, Edf_v, KCtrl_c);
    end procedure;

    procedure txTraffic (
        src    : natural;
        n      : positive;
        frames : positive;
        maxLen : positive := 200) is
        variable Word_v : Word_t;
    begin

        for f in 1 to frames loop
            txFrame(src, n, random(0, 31), random(1, maxLen), f, true);

            case random(0, 7) is
                when 0 =>
                    txCtrl(src);
                when 1 =>
                    txBroadcast(src);
                when 2 =>
                    -- Idle frame: SIF and replicated PRBS words (not compared)
                    Word_v := x"0000" & SymSif_c & K28_7_c;
                    txReplicated(src, Word_v);
                    expCtrl(src, Word_v, KCtrl_c);

                    for i in 1 to random(1, 5) loop
                        txReplicated(src, random(32), KData_c);
                    end loop;

                when others =>
                    null;
            end case;

        end loop;

    end procedure;

    impure function trafficDone return boolean is
    begin
        return TxQueueA_v.count = 0 and TxQueueB_v.count = 0 and ExpFrameA_v.count = 0 and
               ExpCtrlA_v.count = 0 and ExpFrameB_v.count = 0 and ExpCtrlB_v.count = 0;
    end function;

    impure function rowsSent return boolean is
    begin
        return TxQueueA_v.count = 0 and TxQueueB_v.count = 0;
    end function;

    procedure clearTraffic is
    begin
        TxQueueA_v.clear;
        TxQueueB_v.clear;
        ExpFrameA_v.clear;
        ExpCtrlA_v.clear;
        ExpFrameB_v.clear;
        ExpCtrlB_v.clear;
    end procedure;

end package body;
