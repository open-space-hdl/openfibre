---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Column decoder of one lane (ML-4): unscrambles the data words of data frames and checks the
-- CRC-16 of the lane column; the result is passed with the EDF. All other words pass unchanged.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.4)

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
entity ofb_ml_col_dec is
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Control
        Cfg_Unscramble : in    std_logic;
        Ctrl_Flush     : in    std_logic := '0'; -- Link reset: end the frame
        -- Input words
        In_Data        : in    Word_t;
        In_K           : in    WordK_t;
        In_Valid       : in    std_logic;
        -- Output words
        Out_Data       : out   Word_t;
        Out_K          : out   WordK_t;
        Out_CrcErr     : out   std_logic; -- With an EDF: CRC-16 error or EDF outside a data frame
        Out_Valid      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_col_dec is

    type TwoProcess_r is record
        State    : FrameFsm_t;
        OutData  : Word_t;
        OutK     : WordK_t;
        OutValid : std_logic;
        OutEdf   : std_logic; -- Output word is an EDF
        OutCrc   : std_logic; -- Output word is an EDF that ends a data frame (CRC computed)
    end record;

    signal r, r_next : TwoProcess_r;

    signal PrbsData    : Word_t;
    signal PrbsAdvance : std_logic;
    signal PrbsSet     : std_logic;
    signal CrcValid    : std_logic;
    signal CrcFirst    : std_logic;
    signal CrcLast     : std_logic;
    signal CrcBe       : WordK_t;
    signal CrcOut      : std_logic_vector(15 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
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
        Advance_v  := '0';
        Set_v      := '0';
        CrcVld_v   := '0';
        First_v    := '0';
        Last_v     := '0';
        Be_v       := "1111";
        Kind_v     := wordKind(In_Data, In_K);
        Word_v     := In_Data;
        v.OutValid := In_Valid;
        v.OutEdf   := '0';
        v.OutCrc   := '0';

        if In_Valid = '1' then

            case Kind_v is
                when KindSdf =>
                    Set_v    := '1';
                    CrcVld_v := '1';
                    First_v  := '1';
                when KindData =>
                    if r.State = Data_s then
                        if Cfg_Unscramble = '1' then
                            Word_v := scrambleWord(In_Data, In_K, PrbsData);
                        end if;
                        Advance_v := '1';
                        CrcVld_v  := '1';
                    end if;
                when KindEdf =>
                    v.OutEdf := '1';
                    if r.State = Data_s then
                        CrcVld_v := '1';
                        Last_v   := '1';
                        Be_v     := "0011";
                        v.OutCrc := '1';
                    end if;
                when others =>
                    null;
            end case;

            v.State   := frameNext(r.State, Kind_v);
            v.OutData := Word_v;
            v.OutK    := In_K;
        end if;

        -- Flush on link reset
        if Ctrl_Flush = '1' then
            v.State := None_s;
        end if;

        -- Outputs
        PrbsAdvance <= Advance_v;
        PrbsSet     <= Set_v;
        CrcValid    <= CrcVld_v;
        CrcFirst    <= First_v;
        CrcLast     <= Last_v;
        CrcBe       <= Be_v;

        -- Apply to record
        r_next <= v;

    end process;

    Out_Data   <= r.OutData;
    Out_K      <= r.OutK;
    Out_Valid  <= r.OutValid;
    Out_CrcErr <= '1' when r.OutEdf = '1' and (r.OutCrc = '0' or CrcOut /= r.OutData(31 downto 16)) else '0';

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
                r.OutEdf   <= '0';
                r.OutCrc   <= '0';
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
    -- CRC-16 of the column, computed over the received (scrambled) words
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
            In_Data   => In_Data,
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
