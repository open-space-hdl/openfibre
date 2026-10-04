---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Row concentrator of the Multi-Lane layer (ML-6): passes the receiving rows of the lane
-- alignment to the Data Link layer, one word of replicated broadcast and idle rows, data words of
-- a data frame packed into rows of N words.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.8)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_rx is
    generic (
        NumLanes_g : positive range 1 to 4 := 2
    );
    port (
        -- Control Ports
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        Ctrl_Flush   : in    std_logic; -- Link reset
        -- Receiving rows of the lane alignment
        In_Data      : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K         : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Count     : in    std_logic_vector(2 downto 0);
        In_DataRow   : in    std_logic;
        In_CrcErr    : in    std_logic;
        In_Valid     : in    std_logic;
        -- Rows to the Data Link layer
        RxRow_Data   : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        RxRow_K      : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        RxRow_Mask   : out   std_logic_vector(NumLanes_g-1 downto 0);
        RxRow_CrcErr : out   std_logic;
        RxRow_Valid  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_rx is

    constant AccSize_c : positive := 2 * NumLanes_g;
    constant OqSize_c  : positive := 4;

    type FrameState_t is (None_s, Data_s, BcstIn_s, BcstOut_s, Idle_s);

    type AccData_t is array (0 to AccSize_c-1) of Word_t;
    type AccK_t is array (0 to AccSize_c-1) of WordK_t;

    type Row_t is record
        Data   : std_logic_vector(32*NumLanes_g-1 downto 0);
        K      : std_logic_vector(4*NumLanes_g-1 downto 0);
        Mask   : std_logic_vector(NumLanes_g-1 downto 0);
        CrcErr : std_logic;
    end record;

    type Oq_t is array (0 to OqSize_c-1) of Row_t;

    type TwoProcess_r is record
        Fs    : FrameState_t;
        AData : AccData_t;
        AK    : AccK_t;
        ACnt  : natural range 0 to AccSize_c;
        Oq    : Oq_t;
        OqCnt : natural range 0 to OqSize_c;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Word_v  : Word_t;
        variable K_v     : WordK_t;
        variable Kind_v  : WordKind_t;
        variable Flush_v : boolean;
        variable Push_v  : boolean;
        variable Row_v   : Row_t;
        variable Part_v  : Row_t;
        variable Cnt_v   : natural range 0 to NumLanes_g;
        variable Pos_v   : natural range 0 to AccSize_c;

        -- Append a row to the output queue
        procedure push (row : in Row_t) is
        begin
            -- coverage off
            assert v.OqCnt < OqSize_c
                report "ofb_ml_rx: output queue overflow"
                severity error;
            -- coverage on
            if v.OqCnt < OqSize_c then
                v.Oq(v.OqCnt) := row;
                v.OqCnt       := v.OqCnt + 1;
            end if;
        end procedure;

        -- Row of the waiting words of the data frame
        function partRow (
            data : AccData_t;
            k    : AccK_t;
            cnt  : natural) return Row_t is
            variable Row_v : Row_t;
        begin
            Row_v.Data   := (others => '0');
            Row_v.K      := (others => '0');
            Row_v.Mask   := (others => '0');
            Row_v.CrcErr := '0';

            for i in 0 to NumLanes_g-1 loop
                if i < cnt then
                    Row_v.Data(32*i+31 downto 32*i) := data(i);
                    Row_v.K(4*i+3 downto 4*i)       := k(i);
                    Row_v.Mask(i)                   := '1';
                end if;
            end loop;

            return Row_v;
        end function;

    -- Row processing
    begin
        -- Hold variables stable
        v := r;

        -- Output queue: the head is passed (no back-pressure)
        if r.OqCnt > 0 then

            for i in 0 to OqSize_c-2 loop
                v.Oq(i) := r.Oq(i+1);
            end loop;

            v.OqCnt := r.OqCnt - 1;
        end if;

        -- Row of the lane alignment
        Word_v := In_Data(31 downto 0);
        K_v    := In_K(3 downto 0);
        Kind_v := wordKind(Word_v, K_v);

        -- Single word row (control word, word of a replicated row)
        Row_v.Data              := (others => '0');
        Row_v.K                 := (others => '0');
        Row_v.Mask              := (others => '0');
        Row_v.Data(31 downto 0) := Word_v;
        Row_v.K(3 downto 0)     := K_v;
        Row_v.Mask(0)           := '1';
        Row_v.CrcErr            := In_CrcErr;
        Flush_v                 := false;
        Push_v                  := false;

        if In_Valid = '1' then
            if In_DataRow = '1' then
                if r.Fs = BcstIn_s or r.Fs = BcstOut_s or r.Fs = Idle_s then
                    -- Replicated row: one word (ML-CO-05)
                    Push_v := true;
                else
                    -- Data words of a data frame: packed into rows of N words (ML-CO-06)
                    Cnt_v := to_integer(unsigned(In_Count));
                    Pos_v := r.ACnt;

                    for i in 0 to NumLanes_g-1 loop
                        if i < Cnt_v then
                            v.AData(Pos_v) := In_Data(32*i+31 downto 32*i);
                            v.AK(Pos_v)    := In_K(4*i+3 downto 4*i);
                            Pos_v          := Pos_v + 1;
                        end if;
                    end loop;

                    if Pos_v >= NumLanes_g then
                        Row_v  := partRow(v.AData, v.AK, NumLanes_g);
                        Push_v := true;

                        for i in 0 to NumLanes_g-1 loop
                            if i + NumLanes_g < AccSize_c then
                                v.AData(i) := v.AData(i + NumLanes_g);
                                v.AK(i)    := v.AK(i + NumLanes_g);
                            end if;
                        end loop;

                        Pos_v := Pos_v - NumLanes_g;
                    end if;
                    v.ACnt := Pos_v;
                end if;
            else

                -- Control word: frame state; words that end a data frame flush the waiting words
                case Kind_v is
                    when KindSdf =>
                        Flush_v := true;
                        v.Fs    := Data_s;
                    when KindSif =>
                        Flush_v := true;
                        v.Fs    := Idle_s;
                    when KindEdf | KindRetry | KindRxErr =>
                        Flush_v := true;
                        v.Fs    := None_s;
                    when KindSbf =>
                        if r.Fs = Data_s then
                            v.Fs := BcstIn_s;
                        else
                            v.Fs := BcstOut_s;
                        end if;
                    when KindEbf =>
                        if r.Fs = BcstIn_s then
                            v.Fs := Data_s;
                        else
                            v.Fs := None_s;
                        end if;
                    when others =>
                        null;
                end case;

                Push_v := true;
            end if;
        end if;

        if Flush_v and r.ACnt > 0 then
            Part_v := partRow(r.AData, r.AK, r.ACnt);
            push(Part_v);
            v.ACnt := 0;
        end if;
        if Push_v then
            push(Row_v);
        end if;

        if Ctrl_Flush = '1' then
            v.Fs    := None_s;
            v.ACnt  := 0;
            v.OqCnt := 0;
        end if;

        -- Apply to record
        r_next <= v;

    end process;

    -- Outputs: head of the output queue
    RxRow_Data   <= r.Oq(0).Data;
    RxRow_K      <= r.Oq(0).K;
    RxRow_Mask   <= r.Oq(0).Mask;
    RxRow_CrcErr <= r.Oq(0).CrcErr;
    RxRow_Valid  <= '1' when r.OqCnt > 0 else '0';

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Fs    <= None_s;
                r.ACnt  <= 0;
                r.OqCnt <= 0;
            end if;
        end if;
    end process;

end architecture;
