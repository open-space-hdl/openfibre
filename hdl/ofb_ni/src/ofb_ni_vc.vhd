---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VC port of the Network interface (NI-1), transmit direction: checks the packet framing of every
-- word of a beat of NumLanes_g words (ECSS 5.3.7), ends a packet with a framing error with an EEP,
-- replaces the rest of that packet by Fill words and drops beats of Fill words only.
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
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Control Ports
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Beats from the user
        In_Data     : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K        : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Valid    : in    std_logic;
        In_Ready    : out   std_logic;
        -- Beats to the Data Link layer
        Out_Data    : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Out_K       : out   std_logic_vector(4*NumLanes_g-1 downto 0);
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

    constant N_c : positive := NumLanes_g;

    constant WordFill_c : Word_t := CharFill_c & CharFill_c & CharFill_c & CharFill_c;

    signal Spill    : std_logic;
    signal ChkData  : std_logic_vector(32*N_c-1 downto 0);
    signal ChkK     : std_logic_vector(4*N_c-1 downto 0);
    signal ChkErr   : std_logic;
    signal ChkSpill : std_logic;
    signal ChkDrop  : std_logic;
    signal PlInData : std_logic_vector(36*N_c-1 downto 0);
    signal PlInVld  : std_logic;
    signal PlInRdy  : std_logic;
    signal PlOut    : std_logic_vector(36*N_c-1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Framing check of the words of a beat, in order
    -----------------------------------------------------------------------------------------------
    p_check : process (all) is
        variable Data_v   : Word_t;
        variable K_v      : WordK_t;
        variable InD_v    : Word_t;
        variable InK_v    : WordK_t;
        variable Ended_v  : boolean;
        variable Err_v    : boolean;
        variable AnyErr_v : boolean;
        variable Spill_v  : boolean;
        variable End_v    : boolean;
        variable Char_v   : Char_t;
        variable Fills_v  : boolean;
    begin
        Spill_v  := Spill = '1';
        AnyErr_v := false;
        Fills_v  := true;

        for w in 0 to N_c-1 loop
            InD_v   := In_Data(32*w+31 downto 32*w);
            InK_v   := In_K(4*w+3 downto 4*w);
            Data_v  := InD_v;
            K_v     := InK_v;
            Ended_v := false;
            Err_v   := false;
            End_v   := false;

            for i in 0 to CharsPerWord_c-1 loop
                Char_v := InD_v(8*i+7 downto 8*i);
                if InK_v(i) = '1' and (Char_v = CharEop_c or Char_v = CharEep_c) then
                    End_v := true;
                end if;
            end loop;

            if Spill_v then
                -- Rest of a packet with a framing error: discarded up to and including the word
                -- with the next EOP or EEP
                Data_v := WordFill_c;
                K_v    := "1111";
                if End_v then
                    Spill_v := false;
                end if;
            else

                for i in 0 to CharsPerWord_c-1 loop
                    Char_v := InD_v(8*i+7 downto 8*i);
                    if Err_v then
                        -- Characters after the first offending one become Fills
                        Data_v(8*i+7 downto 8*i) := CharFill_c;
                        K_v(i)                   := '1';
                    elsif InK_v(i) = '1' and (Char_v = CharEop_c or Char_v = CharEep_c) and not Ended_v then
                        Ended_v := true;
                    elsif (InK_v(i) = '1' and Char_v = CharFill_c) or (InK_v(i) = '0' and not Ended_v) then
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

                if Err_v then
                    AnyErr_v := true;
                    -- The rest of the user's packet is discarded, unless the word ends with an end
                    -- marker or Fill
                    if not (InK_v(3) = '1' and (InD_v(31 downto 24) = CharEop_c or InD_v(31 downto 24) = CharEep_c or
                                                InD_v(31 downto 24) = CharFill_c)) then
                        Spill_v := true;
                    end if;
                end if;
            end if;

            ChkData(32*w+31 downto 32*w) <= Data_v;
            ChkK(4*w+3 downto 4*w)       <= K_v;
            if Data_v /= WordFill_c or K_v /= "1111" then
                Fills_v := false;
            end if;
        end loop;

        ChkErr   <= '0';
        ChkSpill <= '0';
        if AnyErr_v then
            ChkErr <= '1';
        end if;
        if Spill_v then
            ChkSpill <= '1';
        end if;

        -- Beats of Fill words only are not sent
        if Fills_v then
            ChkDrop <= '1';
        else
            ChkDrop <= '0';
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Spill state: carried from beat to beat
    -----------------------------------------------------------------------------------------------
    p_spill : process (Clk) is
    begin
        if rising_edge(Clk) then
            Ev_FrameErr <= '0';
            if In_Valid = '1' and (ChkDrop = '1' or PlInRdy = '1') then
                Spill       <= ChkSpill;
                Ev_FrameErr <= ChkErr;
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
            Width_g => 36 * N_c
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

    Out_Data <= PlOut(32*N_c-1 downto 0);
    Out_K    <= PlOut(36*N_c-1 downto 32*N_c);

end architecture;
