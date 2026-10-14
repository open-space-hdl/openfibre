---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VC port of the Network interface (NI-1), transmit direction: converts the packets of the user
-- (bytes, TKEEP, TLAST, EEP flag) into beats of NumLanes_g words of data characters, EOP or EEP and
-- Fills (ECSS 5.3.7), and discards packets with an invalid TKEEP (framing error).
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
entity ofb_ni_vc_tx is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Control Ports
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Packets from the user
        In_Data     : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_Keep     : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Last     : in    std_logic;
        In_User     : in    std_logic; -- End the packet with an EEP (with In_Last)
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
architecture rtl of ofb_ni_vc_tx is

    -- Characters (bytes) per beat
    constant B_c : positive := 4 * NumLanes_g;

    type TwoProcess_r is record
        Started  : std_logic; -- Bytes of the current packet were passed
        Spill    : std_logic; -- Rest of a packet with a framing error: discarded up to TLAST
        EndPend  : std_logic; -- Additional beat with the end marker of a full last beat
        EndEep   : std_logic;
        FrameErr : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PlInData : std_logic_vector(36*NumLanes_g-1 downto 0);
    signal PlInVld  : std_logic;
    signal PlInRdy  : std_logic;
    signal PlOut    : std_logic_vector(36*NumLanes_g-1 downto 0);

    -- Beat with an end marker in character 0 and Fills in all other characters
    function endBeat (eep : std_logic) return std_logic_vector is
        variable Beat_v : std_logic_vector(36*NumLanes_g-1 downto 0);
    begin

        for c in 0 to B_c-1 loop
            Beat_v(8*c+7 downto 8*c) := CharFill_c;
        end loop;

        if eep = '1' then
            Beat_v(7 downto 0) := CharEep_c;
        else
            Beat_v(7 downto 0) := CharEop_c;
        end if;
        Beat_v(Beat_v'high downto 8*B_c) := (others => '1');
        return Beat_v;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable KeepOk_v : boolean;
        variable Full_v   : boolean;
        variable Beat_v   : std_logic_vector(36*NumLanes_g-1 downto 0);
        variable Take_v   : boolean;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.FrameErr := '0';

        -- TKEEP: bytes contiguous from byte 0, all bytes in a beat without TLAST (NI-TX-03)
        KeepOk_v := In_Keep(0) = '1';

        for c in 1 to B_c-1 loop
            if In_Keep(c) = '1' and In_Keep(c-1) = '0' then
                KeepOk_v := false;
            end if;
        end loop;

        Full_v := In_Keep(B_c-1) = '1';
        if In_Last = '0' and not Full_v then
            KeepOk_v := false;
        end if;

        -- Characters of the beat: data, then the end marker in the last beat, then Fills (NI-TX-01, 02)
        for c in 0 to B_c-1 loop
            if In_Keep(c) = '1' then
                Beat_v(8*c+7 downto 8*c) := In_Data(8*c+7 downto 8*c);
                Beat_v(8*B_c+c)          := '0';
            elsif In_Last = '1' and (c = 0 or In_Keep(c-1) = '1') then
                if In_User = '1' then
                    Beat_v(8*c+7 downto 8*c) := CharEep_c;
                else
                    Beat_v(8*c+7 downto 8*c) := CharEop_c;
                end if;
                Beat_v(8*B_c+c) := '1';
            else
                Beat_v(8*c+7 downto 8*c) := CharFill_c;
                Beat_v(8*B_c+c)          := '1';
            end if;
        end loop;

        -- Input ready from the state only (not from TKEEP or TDATA)
        if r.EndPend = '1' then
            In_Ready <= '0';
        elsif r.Spill = '1' then
            In_Ready <= '1';
        else
            In_Ready <= PlInRdy;
        end if;

        -- Beat to the pipeline stage
        PlInVld  <= '0';
        PlInData <= Beat_v;
        Take_v   := false;
        if r.EndPend = '1' then
            -- End marker of a full last beat
            PlInVld  <= '1';
            PlInData <= endBeat(r.EndEep);
            if PlInRdy = '1' then
                v.EndPend := '0';
            end if;
        elsif r.Spill = '1' then
            -- Rest of a packet with a framing error
            if In_Valid = '1' and In_Last = '1' then
                v.Spill := '0';
            end if;
        elsif not KeepOk_v then
            -- Framing error: the packet ends with an EEP when bytes of it were passed, otherwise it is
            -- discarded (no packet of zero length, ECSS 5.3.9h); the rest up to TLAST is discarded (NI-TX-04)
            PlInVld  <= In_Valid and r.Started;
            PlInData <= endBeat('1');
            Take_v   := In_Valid = '1' and PlInRdy = '1';
            if Take_v then
                v.FrameErr := '1';
                v.Started  := '0';
                v.Spill    := not In_Last;
            end if;
        else
            PlInVld <= In_Valid;
            Take_v  := In_Valid = '1' and PlInRdy = '1';
            if Take_v then
                v.Started := not In_Last;
                if In_Last = '1' and Full_v then
                    -- No character left for the end marker: additional beat
                    v.EndPend := '1';
                    v.EndEep  := In_User;
                end if;
            end if;
        end if;

        -- Outputs
        Ev_FrameErr <= r.FrameErr;

        -- Apply to record
        r_next <= v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Started  <= '0';
                r.Spill    <= '0';
                r.EndPend  <= '0';
                r.EndEep   <= '0';
                r.FrameErr <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Output register
    -----------------------------------------------------------------------------------------------
    i_pl : entity olo.olo_base_pl_stage
        generic map (
            Width_g => 36 * NumLanes_g
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

    Out_Data <= PlOut(32*NumLanes_g-1 downto 0);
    Out_K    <= PlOut(36*NumLanes_g-1 downto 32*NumLanes_g);

end architecture;
