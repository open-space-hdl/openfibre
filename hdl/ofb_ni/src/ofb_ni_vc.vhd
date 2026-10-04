---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VC port of the Network interface (NI-1), transmit direction: checks the packet framing of every
-- word (ECSS 5.3.7), ends a packet with a framing error with an EEP, discards the rest of that
-- packet and drops words of four Fills.
--
-- Documentation: hdl/ofb_ni/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni_vc is
    port (
        -- Control Ports
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Words from the user
        In_Data     : in    Word_t;
        In_K        : in    WordK_t;
        In_Valid    : in    std_logic;
        In_Ready    : out   std_logic;
        -- Words to the Data Link layer
        Out_Data    : out   Word_t;
        Out_K       : out   WordK_t;
        Out_Valid   : out   std_logic;
        Out_Ready   : in    std_logic;
        -- Framing error (one cycle)
        Ev_FrameErr : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ni_vc is

    signal Spill    : std_logic;
    signal ChkData  : Word_t;
    signal ChkK     : WordK_t;
    signal ChkErr   : std_logic;
    signal ChkSpill : std_logic;
    signal ChkDrop  : std_logic;
    signal PlInData : std_logic_vector(35 downto 0);
    signal PlInVld  : std_logic;
    signal PlInRdy  : std_logic;
    signal PlOut    : std_logic_vector(35 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Framing check of one word
    -----------------------------------------------------------------------------------------------
    p_check : process (all) is
        variable Data_v  : Word_t;
        variable K_v     : WordK_t;
        variable Ended_v : boolean;
        variable Err_v   : boolean;
        variable Char_v  : Char_t;
        variable Fills_v : boolean;
    begin
        Data_v  := In_Data;
        K_v     := In_K;
        Ended_v := false;
        Err_v   := false;

        for i in 0 to CharsPerWord_c-1 loop
            Char_v := In_Data(8*i+7 downto 8*i);
            if Err_v then
                -- Characters after the first offending one become Fills
                Data_v(8*i+7 downto 8*i) := CharFill_c;
                K_v(i)                   := '1';
            elsif In_K(i) = '1' and (Char_v = CharEop_c or Char_v = CharEep_c) and not Ended_v then
                Ended_v := true;
            elsif (In_K(i) = '1' and Char_v = CharFill_c) or (In_K(i) = '0' and not Ended_v) then
                null;
            else
                -- Second end marker, other K-code, or data after the end marker
                Err_v  := true;
                K_v(i) := '1';
                if Ended_v then
                    Data_v(8*i+7 downto 8*i) := CharFill_c;
                else
                    Data_v(8*i+7 downto 8*i) := CharEep_c;
                end if;
            end if;
        end loop;

        ChkData <= Data_v;
        ChkK    <= K_v;

        -- After an error the rest of the user's packet is discarded, unless the word ends with an end
        -- marker or Fill
        ChkErr   <= '0';
        ChkSpill <= '0';
        if Err_v then
            ChkErr <= '1';
            if not (In_K(3) = '1' and (In_Data(31 downto 24) = CharEop_c or In_Data(31 downto 24) = CharEep_c or
                                       In_Data(31 downto 24) = CharFill_c)) then
                ChkSpill <= '1';
            end if;
        end if;

        -- Words of four Fills are not sent
        Fills_v := K_v = "1111";

        for i in 0 to CharsPerWord_c-1 loop
            if Data_v(8*i+7 downto 8*i) /= CharFill_c then
                Fills_v := false;
            end if;
        end loop;

        if Fills_v or Spill = '1' then
            ChkDrop <= '1';
        else
            ChkDrop <= '0';
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Spill state: discard up to and including the next word with an EOP or EEP
    -----------------------------------------------------------------------------------------------
    p_spill : process (Clk) is
        variable End_v : boolean;
    begin
        if rising_edge(Clk) then
            Ev_FrameErr <= '0';
            if In_Valid = '1' and (ChkDrop = '1' or PlInRdy = '1') then
                if Spill = '1' then
                    End_v := false;

                    for i in 0 to CharsPerWord_c-1 loop
                        if In_K(i) = '1' and (In_Data(8*i+7 downto 8*i) = CharEop_c or
                                              In_Data(8*i+7 downto 8*i) = CharEep_c) then
                            End_v := true;
                        end if;
                    end loop;

                    if End_v then
                        Spill <= '0';
                    end if;
                else
                    Spill       <= ChkSpill;
                    Ev_FrameErr <= ChkErr;
                end if;
            end if;
            if Rst = '1' then
                Spill       <= '0';
                Ev_FrameErr <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Output register
    -----------------------------------------------------------------------------------------------
    PlInData <= ChkK & ChkData;
    PlInVld  <= In_Valid and not ChkDrop;
    In_Ready <= '1' when ChkDrop = '1' else PlInRdy;

    i_pl : entity olo.olo_base_pl_stage
        generic map (
            Width_g => 36
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Valid  => PlInVld,
            In_Ready  => PlInRdy,
            In_Data   => PlInData,
            Out_Valid => Out_Valid,
            Out_Ready => Out_Ready,
            Out_Data  => PlOut
        );

    Out_Data <= PlOut(31 downto 0);
    Out_K    <= PlOut(35 downto 32);

end architecture;
