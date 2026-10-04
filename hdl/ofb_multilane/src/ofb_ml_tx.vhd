---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Row distributor of the Multi-Lane layer (ML-2): spreads the rows of the Data Link layer over
-- the data-sending lanes (gearbox from N words to L lanes, PAD before the end of a data frame,
-- replicated words), sends IDLE rows, ACTIVE and ALIGN words according to the alignment state,
-- PRBS words on hot redundant lanes, and requests SKIP from all lanes at once.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.6)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_tx is
    generic (
        NumLanes_g          : positive range 1 to 4 := 2;
        SkipIntervalWords_g : positive              := 5000
    );
    port (
        -- Control Ports
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        Ctrl_Flush      : in    std_logic; -- Link reset
        -- Lane sets and alignment state
        Bypass          : in    std_logic;
        AlignState      : in    AlignState_t;
        ActLanes        : in    std_logic_vector(NumLanes_g-1 downto 0);
        TxLanes         : in    std_logic_vector(NumLanes_g-1 downto 0);
        DataLanes       : in    std_logic_vector(NumLanes_g-1 downto 0);
        HotLanes        : in    std_logic_vector(NumLanes_g-1 downto 0);
        NumTxLanes      : in    std_logic_vector(3 downto 0);
        -- Rows from the Data Link layer
        TxRow_Data      : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        TxRow_K         : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        TxRow_Mask      : in    std_logic_vector(NumLanes_g-1 downto 0);
        TxRow_Replicate : in    std_logic;
        TxRow_Valid     : in    std_logic;
        TxRow_Ready     : out   std_logic;
        -- Words to the column encoders
        Enc_Data        : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Enc_K           : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Enc_Valid       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Enc_Ready       : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- SKIP request to all Lane layers
        Lane_SkipReq    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_tx is

    constant QSize_c : positive := 2 * NumLanes_g;

    type QData_t is array (0 to QSize_c-1) of Word_t;
    type QK_t is array (0 to QSize_c-1) of WordK_t;

    type TwoProcess_r is record
        QData    : QData_t;
        QK       : QK_t;
        Cnt      : natural range 0 to QSize_c;
        Rep      : Word_t;
        RepK     : WordK_t;
        RepValid : std_logic;
        RepIl    : std_logic;
        Slot     : natural range 0 to 7;
        SkipCnt  : natural range 0 to SkipIntervalWords_g-1;
        SkipReq  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PrbsData    : Word_t;
    signal PrbsAdvance : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable L_v       : natural range 0 to NumLanes_g;
        variable Advance_v : boolean;
        variable DataRow_v : boolean;
        variable Emit_v    : natural range 0 to NumLanes_g;
        variable RowData_v : QData_t;
        variable RowK_v    : QK_t;
        variable Idx_v     : natural range 0 to NumLanes_g;
        variable Word_v    : Word_t;
        variable WordK_v   : WordK_t;
        variable Ready_v   : std_logic;
        variable NotRdy_v  : boolean;
        variable Pos_v     : natural range 0 to QSize_c;
        variable Prbs_v    : std_logic;
        variable State_v   : AlignState_t;
        variable RepFree_v : boolean;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        Enc_Data  <= (others => '0');
        Enc_K     <= (others => '0');
        Enc_Valid <= (others => '0');
        Ready_v   := '0';
        Prbs_v    := '0';
        Emit_v    := 0;
        RepFree_v := false;
        L_v       := countOnes(DataLanes);
        -- Bypass: lane 0 is the only data-sending lane, no ACTIVE and ALIGN words (ECSS 5.6.3)
        if Bypass = '1' then
            State_v := AlignBothEndsReady_c;
        else
            State_v := AlignState;
        end if;
        NotRdy_v := State_v = AlignNotReady_c;

        -- SKIP request every SkipIntervalWords_g cycles (ECSS 5.6.4.5a)
        v.SkipReq := '0';
        if r.SkipCnt = SkipIntervalWords_g-1 then
            v.SkipCnt := 0;
            v.SkipReq := '1';
        else
            v.SkipCnt := r.SkipCnt + 1;
        end if;

        -------------------------------------------------------------------------------------------
        -- All active transmitting lanes take a word in the same cycle
        -------------------------------------------------------------------------------------------
        Advance_v := TxLanes /= (TxLanes'range => '0') and (Enc_Ready or not TxLanes) = (TxLanes'range => '1');
        DataRow_v := not NotRdy_v and (r.Slot /= 7 or State_v = AlignBothEndsReady_c);

        -- Gearbox row for the data-sending lanes (ML-DS-01 to ML-DS-04)
        RowData_v := (others => WordIdle_c);
        RowK_v    := (others => KCtrl_c);
        if DataRow_v then
            if r.Cnt >= L_v and L_v > 0 then

                -- Complete sending row of data words
                for i in 0 to NumLanes_g-1 loop
                    RowData_v(i) := r.QData(i);
                    RowK_v(i)    := r.QK(i);
                end loop;

                Emit_v := L_v;
            elsif r.RepValid = '1' and (r.Cnt = 0 or r.RepIl = '1') then
                -- Replicated word; FCT, ACK, NACK, FULL, broadcast words pass waiting data
                RowData_v := (others => r.Rep);
                RowK_v    := (others => r.RepK);
                if Advance_v then
                    v.RepValid := '0';
                    RepFree_v  := true;
                end if;
            elsif r.RepValid = '1' then

                -- End of a data frame: incomplete row filled with PAD words (ECSS 5.6.4.2b)
                for i in 0 to NumLanes_g-1 loop
                    if i < r.Cnt then
                        RowData_v(i) := r.QData(i);
                        RowK_v(i)    := r.QK(i);
                    else
                        RowData_v(i) := WordPad_c;
                        RowK_v(i)    := KPad_c;
                    end if;
                end loop;

                Emit_v := r.Cnt;
            end if;
        end if;

        -- Words per lane
        for i in 0 to NumLanes_g-1 loop
            Idx_v := countBelow(DataLanes, i);
            if NotRdy_v and r.Slot /= 7 then
                -- Not Ready: seven ACTIVE words ... (ECSS 5.6.7.2b.1)
                Word_v  := wordActive(std_logic_vector(resize(unsigned(ActLanes), 16)));
                WordK_v := KCtrl_c;
            elsif not DataRow_v then
                -- ... and one ALIGN word (ECSS 5.6.7.2b.1, 5.6.7.3b.3, 5.6.10i)
                if DataLanes(i) = '1' then
                    Word_v := wordAlign(NumTxLanes, std_logic_vector(to_unsigned(i, 4)));
                else
                    Word_v := x"0000" & SymAlign_c & K28_7_c;
                end if;
                WordK_v := KCtrl_c;
            elsif DataLanes(i) = '1' then
                Word_v  := RowData_v(Idx_v);
                WordK_v := RowK_v(Idx_v);
            else
                -- Hot redundant lane: PRBS (ECSS 5.6.10g)
                Word_v  := PrbsData;
                WordK_v := KData_c;
            end if;
            Enc_Data(32*i+31 downto 32*i) <= Word_v;
            Enc_K(4*i+3 downto 4*i)       <= WordK_v;
            if Advance_v and TxLanes(i) = '1' then
                Enc_Valid(i) <= '1';
            end if;
        end loop;

        if Advance_v then
            if DataRow_v and HotLanes /= (HotLanes'range => '0') then
                Prbs_v := '1';
            end if;
            if State_v = AlignBothEndsReady_c then
                v.Slot := 0;
            elsif r.Slot = 7 then
                v.Slot := 0;
            else
                v.Slot := r.Slot + 1;
            end if;
        else
            Emit_v := 0;
        end if;

        -- Shift out the words sent
        if Emit_v > 0 then

            for i in 0 to QSize_c-1 loop
                if i + Emit_v < QSize_c then
                    v.QData(i) := r.QData(i + Emit_v);
                    v.QK(i)    := r.QK(i + Emit_v);
                end if;
            end loop;

            v.Cnt := r.Cnt - Emit_v;
        end if;

        -- Take a row from the Data Link layer (registers only, ML-IF-01)
        -- A replicated word sent in this cycle makes room for the next row (no IDLE row in between)
        if not NotRdy_v and (r.RepValid = '0' or RepFree_v) and r.Cnt <= NumLanes_g then
            Ready_v := '1';
        end if;
        if Ready_v = '1' and TxRow_Valid = '1' then
            if TxRow_Replicate = '1' then
                v.Rep      := TxRow_Data(31 downto 0);
                v.RepK     := TxRow_K(3 downto 0);
                v.RepValid := '1';
                if interleaved(wordKind(TxRow_Data(31 downto 0), TxRow_K(3 downto 0))) then
                    v.RepIl := '1';
                else
                    v.RepIl := '0';
                end if;
            else
                Pos_v := v.Cnt;

                for i in 0 to NumLanes_g-1 loop
                    if TxRow_Mask(i) = '1' then
                        v.QData(Pos_v) := TxRow_Data(32*i+31 downto 32*i);
                        v.QK(Pos_v)    := TxRow_K(4*i+3 downto 4*i);
                        Pos_v          := Pos_v + 1;
                    end if;
                end loop;

                v.Cnt := Pos_v;
            end if;
        end if;

        -- Not Ready: words held are discarded (ML-DS-11)
        if NotRdy_v then
            v.Cnt      := 0;
            v.RepValid := '0';
        end if;

        if Ctrl_Flush = '1' then
            v.Cnt      := 0;
            v.RepValid := '0';
            v.Slot     := 0;
        end if;

        -- Outputs
        TxRow_Ready <= Ready_v;
        PrbsAdvance <= Prbs_v;

        -- Apply to record
        r_next <= v;

    end process;

    Lane_SkipReq <= r.SkipReq;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Cnt      <= 0;
                r.RepValid <= '0';
                r.Slot     <= 0;
                r.SkipCnt  <= 0;
                r.SkipReq  <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- PRBS words of the hot redundant lanes (ECSS 5.6.10g, 5.7.6.2.3)
    -----------------------------------------------------------------------------------------------
    i_prbs : entity olo.olo_base_prbs
        generic map (
            Polynomial_g    => PrbsPolynomial_c,
            Seed_g          => PrbsSeed_c,
            BitsPerSymbol_g => 32
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            Out_Data  => PrbsData,
            Out_Ready => PrbsAdvance
        );

end architecture;
