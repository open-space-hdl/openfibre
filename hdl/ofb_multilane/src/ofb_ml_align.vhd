---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane alignment of the Multi-Lane layer (ML-5): reception of ACTIVE and ALIGN words, data-
-- receiving lanes, alignment FIFOs, reading and classification of the receiving rows and the
-- alignment state machine (ECSS 5.6.5 to 5.6.7).
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.7)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_align is
    generic (
        NumLanes_g     : positive range 1 to 4 := 2;
        ClkFrequency_g : real                  := 156.25e6
    );
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_Flush     : in    std_logic; -- Link reset
        -- Lane sets
        Bypass         : in    std_logic;
        ActLanes       : in    std_logic_vector(NumLanes_g-1 downto 0);
        RxLanes        : in    std_logic_vector(NumLanes_g-1 downto 0);
        NumRxLanes     : in    std_logic_vector(3 downto 0);
        -- Words of the column decoders
        In_Data        : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K           : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_CrcErr      : in    std_logic_vector(NumLanes_g-1 downto 0);
        In_Valid       : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Receiving rows (data words compacted from word 0, or one control word in word 0)
        Row_Data       : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Row_K          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Row_Count      : out   std_logic_vector(2 downto 0); -- Data rows: number of data words
        Row_Data_Row   : out   std_logic;                    -- 1: data row, 0: control word
        Row_CrcErr     : out   std_logic;
        Row_Valid      : out   std_logic;
        -- Far-end active lanes (valid ACTIVE word)
        FarAct         : out   std_logic_vector(15 downto 0);
        FarActValid    : out   std_logic;
        -- Status
        RecvLanes      : out   std_logic_vector(NumLanes_g-1 downto 0);
        AlignState     : out   AlignState_t;
        Ev_Misaligned  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_align is

    constant FifoDepth_c : positive := 4;
    constant Timer_c     : positive := integer(ceil(4.0e-6 * ClkFrequency_g));

    type FifoData_t is array (0 to FifoDepth_c-1) of Word_t;
    type FifoK_t is array (0 to FifoDepth_c-1) of WordK_t;

    type LaneFifoData_t is array (0 to NumLanes_g-1) of FifoData_t;
    type LaneFifoK_t is array (0 to NumLanes_g-1) of FifoK_t;
    type LaneFifoBits_t is array (0 to NumLanes_g-1) of std_logic_vector(FifoDepth_c-1 downto 0);
    type LaneCnt_t is array (0 to NumLanes_g-1) of natural range 0 to FifoDepth_c;
    type LaneAct_t is array (0 to NumLanes_g-1) of std_logic_vector(15 downto 0);
    type RowData_t is array (0 to NumLanes_g-1) of Word_t;
    type RowK_t is array (0 to NumLanes_g-1) of WordK_t;

    type TwoProcess_r is record
        -- Reception of ACTIVE and ALIGN words
        PrevAct     : LaneAct_t;
        PrevActV    : std_logic_vector(NumLanes_g-1 downto 0);
        Seen        : std_logic_vector(NumLanes_g-1 downto 0); -- ALIGN received since Active
        Recv        : std_logic_vector(NumLanes_g-1 downto 0);
        FarAct      : std_logic_vector(15 downto 0);
        FarActValid : std_logic;
        ActPrev     : std_logic_vector(NumLanes_g-1 downto 0);
        BypassPrev  : std_logic;
        -- Alignment FIFOs (head at index 0)
        FData       : LaneFifoData_t;
        FK          : LaneFifoK_t;
        FCrc        : LaneFifoBits_t;
        FAlign      : LaneFifoBits_t;
        FCnt        : LaneCnt_t;
        -- Alignment state machine
        Aligned     : std_logic;
        State       : AlignState_t;
        Timer       : natural range 0 to Timer_c;
        Misaligned  : std_logic;
        -- Receiving row
        RowData     : RowData_t;
        RowK        : RowK_t;
        RowCount    : natural range 0 to NumLanes_g;
        RowDataRow  : std_logic;
        RowCrcErr   : std_logic;
        RowValid    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Word_v    : Word_t;
        variable K_v       : WordK_t;
        variable Act_v     : std_logic_vector(15 downto 0);
        variable AlValid_v : std_logic_vector(NumLanes_g-1 downto 0);
        variable Write_v   : std_logic_vector(NumLanes_g-1 downto 0);
        variable Pop_v     : std_logic_vector(NumLanes_g-1 downto 0);
        variable Flush_v   : std_logic_vector(NumLanes_g-1 downto 0);
        variable FarNew_v  : boolean;
        variable Mis_v     : boolean;
        variable R_v       : std_logic_vector(NumLanes_g-1 downto 0);
        variable Avail_v   : boolean;
        variable AllAl_v   : boolean;
        variable Held_v    : boolean;
        variable Kind_v    : WordKind_t;
        variable NonMl_v   : boolean;
        variable AllAct_v  : boolean;
        variable AnyAct_v  : boolean;
        variable AnyErr_v  : boolean;
        variable AnyData_v : boolean;
        variable AnyPad_v  : boolean;
        variable AnyCtl_v  : boolean;
        variable First_v   : boolean;
        variable Crc_v     : std_logic;
        variable OutErr_v  : boolean;
        variable OutData_v : boolean;
        variable OutCtl_v  : boolean;
        variable ActEv_v   : boolean;
        variable Cnt_v     : natural range 0 to FifoDepth_c;
        variable Pos_v     : natural range 0 to NumLanes_g;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.FarActValid := '0';
        v.RowValid    := '0';
        v.Misaligned  := '0';
        FarNew_v      := false;
        Mis_v         := false;
        Write_v       := (others => '0');
        Flush_v       := (others => '0');
        AlValid_v     := (others => '0');

        -------------------------------------------------------------------------------------------
        -- Reception of ACTIVE and ALIGN words, data-receiving lanes
        -------------------------------------------------------------------------------------------
        for i in 0 to NumLanes_g-1 loop
            Word_v := In_Data(32*i+31 downto 32*i);
            K_v    := In_K(4*i+3 downto 4*i);
            if In_Valid(i) = '1' then
                -- Valid ACTIVE: two consecutive ACTIVE words with the same value (ECSS 5.6.6.3b)
                if isActive(Word_v, K_v) then
                    Act_v := Word_v(31 downto 16);
                    if r.PrevActV(i) = '1' and r.PrevAct(i) = Act_v and not FarNew_v then
                        FarNew_v      := true;
                        v.FarActValid := '1';
                        v.FarAct      := Act_v;
                        if Act_v /= r.FarAct then
                            Mis_v := true;
                        end if;
                    end if;
                    v.PrevAct(i)  := Act_v;
                    v.PrevActV(i) := '1';
                end if;
                -- ALIGN words (ECSS 5.6.6.3e to h, 5.6.10j)
                if alignCorrect(Word_v, K_v) then
                    if Word_v(19 downto 16) = NumRxLanes and unsigned(Word_v(23 downto 20)) = i then
                        AlValid_v(i) := '1';
                    elsif RxLanes(i) = '1' then
                        Mis_v := true;
                    end if;
                    v.Recv(i) := '1';
                    v.Seen(i) := '1';
                elsif alignHot(Word_v, K_v) then
                    v.Recv(i) := '0';
                    v.Seen(i) := '1';
                end if;
            end if;
            if ActLanes(i) = '0' then
                v.PrevActV(i) := '0';
            end if;
            if RxLanes(i) = '0' then
                v.Recv(i) := '0';
                v.Seen(i) := '0';
            elsif Bypass = '1' then
                -- Bypass: lane 0 is the data-receiving lane, ALIGN words are not used
                v.Recv(i)    := '1';
                AlValid_v(i) := '0';
            end if;
            Write_v(i) := In_Valid(i) and v.Recv(i);
            -- FIFO flush: lane enters Active, lane stops being a data-receiving lane (ECSS 5.6.6.4i)
            if (ActLanes(i) = '1' and r.ActPrev(i) = '0') or (r.Recv(i) = '1' and v.Recv(i) = '0') then
                Flush_v(i) := '1';
            end if;
        end loop;

        v.ActPrev    := ActLanes;
        v.BypassPrev := Bypass;
        -- Near-end active lanes or data-receiving lanes changed
        if ActLanes /= r.ActPrev or v.Recv /= r.Recv then
            Mis_v := true;
        end if;

        -------------------------------------------------------------------------------------------
        -- Row reading (ECSS 5.6.6.4d to g)
        -------------------------------------------------------------------------------------------
        R_v     := r.Recv;
        Avail_v := R_v /= (R_v'range => '0');
        AllAl_v := true;
        Held_v  := false;

        for i in 0 to NumLanes_g-1 loop
            if R_v(i) = '1' then
                if r.FCnt(i) = 0 then
                    Avail_v := false;
                elsif r.FAlign(i)(0) = '1' then
                    Held_v := true;
                else
                    AllAl_v := false;
                end if;
            end if;
        end loop;

        if not Avail_v then
            Held_v  := false;
            AllAl_v := false;
        elsif AllAl_v then
            Held_v := false;
        end if;

        Pop_v := (others => '0');
        if Avail_v then

            for i in 0 to NumLanes_g-1 loop
                if R_v(i) = '1' and (AllAl_v or r.FAlign(i)(0) = '0') then
                    Pop_v(i) := '1';
                end if;
            end loop;

        end if;

        -------------------------------------------------------------------------------------------
        -- Row classification (ECSS 5.6.5, 5.6.6.2, 5.6.6.3i)
        -------------------------------------------------------------------------------------------
        NonMl_v   := false;
        AllAct_v  := true;
        AnyAct_v  := false;
        AnyErr_v  := false;
        AnyData_v := false;
        AnyPad_v  := false;
        AnyCtl_v  := false;
        First_v   := true;
        Crc_v     := '0';
        Pos_v     := 0;

        for i in 0 to NumLanes_g-1 loop
            if Pop_v(i) = '1' then
                Word_v := r.FData(i)(0);
                K_v    := r.FK(i)(0);
                Kind_v := wordKind(Word_v, K_v);
                if Kind_v /= KindMlCtrl then
                    NonMl_v := true;
                end if;
                if isActive(Word_v, K_v) then
                    AnyAct_v := true;
                else
                    AllAct_v := false;
                end if;

                case Kind_v is
                    when KindData =>
                        AnyData_v        := true;
                        v.RowData(Pos_v) := Word_v;
                        v.RowK(Pos_v)    := K_v;
                        Pos_v            := Pos_v + 1;
                    when KindPad =>
                        AnyPad_v := true;
                    when KindRxErr =>
                        AnyErr_v := true;
                    when others =>
                        AnyCtl_v := true;
                end case;

                if r.FCrc(i)(0) = '1' then
                    Crc_v := '1';
                end if;
                -- Control row: the word of the lowest data-receiving lane (ECSS 5.6.5e)
                if First_v and Kind_v /= KindData and Kind_v /= KindPad then
                    First_v := false;
                    if not AnyData_v then
                        v.RowData(0) := Word_v;
                        v.RowK(0)    := K_v;
                    end if;
                end if;
            end if;
        end loop;

        OutErr_v  := false;
        OutData_v := false;
        OutCtl_v  := false;
        ActEv_v   := false;
        if AllAl_v then
            -- All lanes aligned (ECSS 5.6.6.4f), once every active receiving lane has received an
            -- ALIGN word and is known to be a data-receiving lane or not
            if (RxLanes and not r.Seen) = (RxLanes'range => '0') then
                v.Aligned := '1';
            end if;
        elsif Held_v then
            -- Valid ALIGN held in some lanes: part of the alignment, or a lane slip after it
            if r.Aligned = '1' then
                Mis_v := true;
                if r.State /= AlignNotReady_c then
                    OutErr_v := true;
                end if;
            end if;
            if NonMl_v and r.State = AlignNotReady_c then
                OutErr_v := true;
            end if;
        elsif Avail_v then
            -- Invalid receiving row (ECSS 5.6.6.2b)
            if (AnyData_v or AnyPad_v) and AnyCtl_v then
                Mis_v := true;
            end if;
            if AnyAct_v then
                ActEv_v := true;
            end if;
            if r.State = AlignNotReady_c then
                -- Not Ready: rows with Data Link words are replaced by RXERR (ECSS 5.6.7.2b.2)
                if NonMl_v then
                    OutErr_v := true;
                end if;
            elsif AllAct_v then
                null;
            elsif AnyAct_v or AnyErr_v or (AnyCtl_v and (AnyData_v or AnyPad_v)) then
                -- ECSS 5.6.6.3i, 5.6.5f
                OutErr_v := true;
            elsif AnyData_v then
                OutData_v := true;
            elsif AnyPad_v then
                null;
            else
                OutCtl_v := true;
            end if;
        end if;

        -- RXERR within 4 us of entering Near-End Ready (ECSS 5.6.7.1c.6)
        if OutErr_v and r.State = AlignNearEndReady_c and r.Timer /= 0 then
            Mis_v := true;
        end if;

        -------------------------------------------------------------------------------------------
        -- Alignment FIFOs: pop, overflow, write, flush (ECSS 5.6.6.4)
        -------------------------------------------------------------------------------------------
        for i in 0 to NumLanes_g-1 loop
            if Write_v(i) = '1' and r.FCnt(i) = FifoDepth_c and Pop_v(i) = '0' then
                -- Overflow: all FIFOs are flushed (ECSS 5.6.6.4h)
                Mis_v   := true;
                Flush_v := (others => '1');
            end if;
        end loop;

        for i in 0 to NumLanes_g-1 loop
            Cnt_v := r.FCnt(i);
            if Pop_v(i) = '1' then

                for j in 0 to FifoDepth_c-2 loop
                    v.FData(i)(j)  := r.FData(i)(j+1);
                    v.FK(i)(j)     := r.FK(i)(j+1);
                    v.FCrc(i)(j)   := r.FCrc(i)(j+1);
                    v.FAlign(i)(j) := r.FAlign(i)(j+1);
                end loop;

                Cnt_v := Cnt_v - 1;
            end if;
            if Write_v(i) = '1' and Cnt_v < FifoDepth_c then
                v.FData(i)(Cnt_v)  := In_Data(32*i+31 downto 32*i);
                v.FK(i)(Cnt_v)     := In_K(4*i+3 downto 4*i);
                v.FCrc(i)(Cnt_v)   := In_CrcErr(i);
                v.FAlign(i)(Cnt_v) := AlValid_v(i);
                Cnt_v              := Cnt_v + 1;
            end if;
            v.FCnt(i) := Cnt_v;
            if Flush_v(i) = '1' or Ctrl_Flush = '1' or Bypass /= r.BypassPrev then
                v.FCnt(i) := 0;
            end if;
        end loop;

        -------------------------------------------------------------------------------------------
        -- Alignment state machine (ECSS 5.6.7, Figure 5-37)
        -------------------------------------------------------------------------------------------
        if r.Timer /= 0 then
            v.Timer := r.Timer - 1;
        end if;
        if Bypass = '1' then
            -- Bypass: one lane, always aligned (ECSS 5.6.3)
            Mis_v := false;
        end if;
        if Mis_v then
            v.Aligned := '0';
            if r.State /= AlignNotReady_c then
                -- Words may have been lost (ML-CO-04)
                v.Misaligned := '1';
                OutErr_v     := true;
            end if;
            v.State := AlignNotReady_c;
        else

            case r.State is
                when AlignNotReady_c =>
                    if r.Aligned = '1' and r.FarAct = std_logic_vector(resize(unsigned(ActLanes), 16)) then
                        v.State := AlignNearEndReady_c;
                        v.Timer := Timer_c;
                    end if;
                when AlignNearEndReady_c =>
                    if OutData_v then
                        v.State := AlignBothEndsReady_c;
                    end if;
                when others =>
                    if ActEv_v then
                        v.State := AlignNearEndReady_c;
                        v.Timer := Timer_c;
                    end if;
            end case;

        end if;
        if Bypass = '1' then
            v.State   := AlignBothEndsReady_c;
            v.Aligned := '1';
        elsif Ctrl_Flush = '1' or r.BypassPrev = '1' then
            v.State   := AlignNotReady_c;
            v.Aligned := '0';
            OutErr_v  := false;
            OutData_v := false;
            OutCtl_v  := false;
        end if;

        -------------------------------------------------------------------------------------------
        -- Receiving row to the concentrator
        -------------------------------------------------------------------------------------------
        v.RowCrcErr  := Crc_v;
        v.RowCount   := Pos_v;
        v.RowDataRow := '0';
        if OutErr_v then
            v.RowValid   := '1';
            v.RowData(0) := WordRxErr_c;
            v.RowK(0)    := KCtrl_c;
            v.RowCrcErr  := '0';
        elsif OutData_v then
            v.RowValid   := '1';
            v.RowDataRow := '1';
        elsif OutCtl_v then
            v.RowValid := '1';
        end if;

        -- Apply to record
        r_next <= v;

    end process;

    -- Outputs
    g_row : for i in 0 to NumLanes_g-1 generate
        Row_Data(32*i+31 downto 32*i) <= r.RowData(i);
        Row_K(4*i+3 downto 4*i)       <= r.RowK(i);
    end generate;

    Row_Count     <= std_logic_vector(to_unsigned(r.RowCount, 3));
    Row_Data_Row  <= r.RowDataRow;
    Row_CrcErr    <= r.RowCrcErr;
    Row_Valid     <= r.RowValid;
    FarAct        <= r.FarAct;
    FarActValid   <= r.FarActValid;
    RecvLanes     <= r.Recv;
    AlignState    <= r.State;
    Ev_Misaligned <= r.Misaligned;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.PrevActV    <= (others => '0');
                r.Recv        <= (others => '0');
                r.Seen        <= (others => '0');
                r.FarAct      <= (others => '0');
                r.FarActValid <= '0';
                r.ActPrev     <= (others => '0');
                r.BypassPrev  <= '0';
                r.FCnt        <= (others => 0);
                r.Aligned     <= '0';
                r.State       <= AlignNotReady_c;
                r.Timer       <= 0;
                r.Misaligned  <= '0';
                r.RowValid    <= '0';
            end if;
        end if;
    end process;

end architecture;
