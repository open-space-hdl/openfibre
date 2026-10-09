---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Column encoder of one lane (ML-3): scrambles the data words of data frames and places the
-- CRC-16 of the lane column (SDF, scrambled data words, EDF code and sequence number) into the
-- EDF. All other words pass unchanged. An input register stage decouples the word assembly of the
-- Multi-Lane transmitter from the scrambler and the CRC (timing).
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.3)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_col_enc is
    port (
        -- Control Ports
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Control
        Cfg_Scramble : in    std_logic;
        Ctrl_Flush   : in    std_logic := '0'; -- Link reset: discard the held word, end the frame
        -- Input words
        In_Data      : in    Word_t;
        In_K         : in    WordK_t;
        In_Poison    : in    std_logic := '0'; -- Corrupted word: the CRC-16 of the next EDF is inverted
        In_Valid     : in    std_logic;
        In_Ready     : out   std_logic;
        -- Output words
        Out_Data     : out   Word_t;
        Out_K        : out   WordK_t;
        Out_Valid    : out   std_logic;
        Out_Ready    : in    std_logic := '1'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_col_enc is

    type TwoProcess_r is record
        State    : FrameFsm_t;
        OutData  : Word_t;
        OutK     : WordK_t;
        OutValid : std_logic;
        OutCrc   : std_logic;
        OutInv   : std_logic;
        Poison   : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PrbsData    : Word_t;
    signal PrbsAdvance : std_logic;
    signal PrbsSet     : std_logic;
    signal CrcData     : Word_t;
    signal CrcValid    : std_logic;
    signal CrcFirst    : std_logic;
    signal CrcLast     : std_logic;
    signal CrcBe       : WordK_t;
    signal CrcOut      : std_logic_vector(15 downto 0);
    signal StgIn       : std_logic_vector(36 downto 0);
    signal StgOut      : std_logic_vector(36 downto 0);
    signal StgRst      : std_logic;
    signal StgValid    : std_logic;
    signal StgReady    : std_logic;
    signal StgData     : Word_t;
    signal StgK        : WordK_t;
    signal StgPoison   : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Input register stage; the flush discards a word held in it
    -----------------------------------------------------------------------------------------------
    StgIn  <= In_Poison & In_K & In_Data;
    StgRst <= Rst or Ctrl_Flush;

    i_stage : entity olo.olo_base_pl_stage
        generic map (
            Width_g => 37
        )
        port map (
            Clk       => Clk,
            Rst       => StgRst,
            In_Valid  => In_Valid,
            In_Ready  => In_Ready,
            In_Data   => StgIn,
            Out_Valid => StgValid,
            Out_Ready => StgReady,
            Out_Data  => StgOut
        );

    StgData   <= StgOut(31 downto 0);
    StgK      <= StgOut(35 downto 32);
    StgPoison <= StgOut(36);

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Ready_v   : std_logic;
        variable Kind_v    : WordKind_t;
        variable Word_v    : Word_t;
        variable Advance_v : std_logic;
        variable Set_v     : std_logic;
        variable CrcVld_v  : std_logic;
        variable First_v   : std_logic;
        variable Last_v    : std_logic;
        variable Be_v      : WordK_t;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        Advance_v := '0';
        Set_v     := '0';
        CrcVld_v  := '0';
        First_v   := '0';
        Last_v    := '0';
        Be_v      := "1111";
        Kind_v    := wordKind(StgData, StgK);
        Word_v    := StgData;

        -- Output register
        if r.OutValid = '1' and Out_Ready = '1' then
            v.OutValid := '0';
            v.OutCrc   := '0';
            v.OutInv   := '0';
        end if;
        Ready_v := (not r.OutValid or Out_Ready) and not Ctrl_Flush;

        -- Word taken
        if StgValid = '1' and Ready_v = '1' then
            -- A corrupted word poisons the column up to the next EDF
            if StgPoison = '1' then
                v.Poison := '1';
            end if;

            case Kind_v is
                when KindSdf =>
                    -- New column: re-seed the scrambler, restart the CRC with the SDF
                    Set_v    := '1';
                    CrcVld_v := '1';
                    First_v  := '1';
                when KindData =>
                    if r.State = Data_s then
                        if Cfg_Scramble = '1' then
                            Word_v := scrambleWord(StgData, StgK, PrbsData);
                        end if;
                        Advance_v := '1';
                        CrcVld_v  := '1';
                    end if;
                when KindEdf =>
                    -- EDF code and sequence number end the CRC, the result goes into characters 2, 3
                    if r.State = Data_s then
                        CrcVld_v := '1';
                        Last_v   := '1';
                        Be_v     := "0011";
                        v.OutCrc := '1';
                        v.OutInv := r.Poison or StgPoison;
                        v.Poison := '0';
                    end if;
                when others =>
                    null;
            end case;

            v.State    := frameNext(r.State, Kind_v);
            v.OutData  := Word_v;
            v.OutK     := StgK;
            v.OutValid := '1';
        end if;

        -- Flush on link reset
        if Ctrl_Flush = '1' then
            v.State    := None_s;
            v.OutValid := '0';
            v.OutCrc   := '0';
            v.OutInv   := '0';
            v.Poison   := '0';
        end if;

        -- Outputs
        StgReady    <= Ready_v;
        PrbsAdvance <= Advance_v;
        PrbsSet     <= Set_v;
        CrcData     <= Word_v;
        CrcValid    <= CrcVld_v;
        CrcFirst    <= First_v;
        CrcLast     <= Last_v;
        CrcBe       <= Be_v;

        -- Apply to record
        r_next <= v;

    end process;

    Out_Data  <= (CrcOut xor (CrcOut'range => r.OutInv)) & r.OutData(15 downto 0) when r.OutCrc = '1' else r.OutData;
    Out_K     <= r.OutK;
    Out_Valid <= r.OutValid;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= None_s;
                r.OutValid <= '0';
                r.OutCrc   <= '0';
                r.OutInv   <= '0';
                r.Poison   <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Scrambling sequence
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
            Out_Ready => PrbsAdvance,
            State_New => PrbsSeed_c,
            State_Set => PrbsSet
        );

    -----------------------------------------------------------------------------------------------
    -- CRC-16 of the column
    -----------------------------------------------------------------------------------------------
    i_crc : entity olo.olo_base_crc
        generic map (
            DataWidth_g     => 32,
            Polynomial_g    => Crc16Polynomial_c,
            InitialValue_g  => Crc16Seed_c,
            BitOrder_g      => CrcBitOrder_c,
            ByteOrder_g     => CrcByteOrder_c,
            BitflipOutput_g => CrcBitflipOutput_c
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Data   => CrcData,
            In_Valid  => CrcValid,
            In_Ready  => open,
            In_Last   => CrcLast,
            In_First  => CrcFirst,
            In_Be     => CrcBe,
            Out_Crc   => CrcOut,
            Out_Valid => open,
            Out_Ready => '1'
        );

end architecture;
