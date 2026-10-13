---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- VC port of the Network interface (NI-1), receive direction: converts the beats of N-Chars and Fills
-- of the input VC buffer into packets for the user (bytes aligned to byte 0, TKEEP, TLAST, EEP flag).
-- Removes the Fills, discards packets of zero length and checks the character rules (ECSS 5.3.7).
--
-- Documentation: hdl/ofb_ni/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni_vc_rx is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Control Ports
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Beats from the Data Link layer (a beat ends after the word with an EOP or EEP)
        In_Data     : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        In_K        : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        In_Valid    : in    std_logic;
        In_Ready    : out   std_logic;
        -- Packets to the user
        Out_Data    : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Out_Keep    : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Out_Last    : out   std_logic;
        Out_User    : out   std_logic; -- The packet ended with an EEP (with Out_Last)
        Out_Valid   : out   std_logic;
        Out_Ready   : in    std_logic;
        -- Events (one cycle)
        Ev_FrameErr : out   std_logic; -- Character rule violation
        Ev_Empty    : out   std_logic  -- Packet of zero length discarded
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ni_vc_rx is

    -- Characters (bytes) per beat
    constant B_c : positive := 4 * NumLanes_g;

    subtype Mask_t is std_logic_vector(B_c-1 downto 0);
    subtype Beat_t is std_logic_vector(8*B_c-1 downto 0);
    -- Offset of a packet: word (0 to NumLanes_g - 1) and character in the word (0 to 3)
    subtype Off_t is std_logic_vector(1 downto 0);

    type TwoProcess_r is record
        InPkt    : std_logic; -- A packet is open (its first data character was received)
        Discard  : std_logic; -- Rest of a packet with a violation: discarded up to a clean end
        OffW     : Off_t;     -- Offset of the open packet: word
        OffC     : Off_t;     -- Offset of the open packet: character
        SelMask  : Mask_t;    -- Output positions taken from the current beat ('1' for i >= B - offset)
        Hold     : Beat_t;    -- Rotated previous beat of the open packet, or the pending tail
        TailVld  : std_logic;
        TailKeep : Mask_t;
        TailUser : std_logic;
        OutVld   : std_logic;
        OutData  : Beat_t;
        OutKeep  : Mask_t;
        OutLast  : std_logic;
        OutUser  : std_logic;
        FrameErr : std_logic;
        Empty    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Input stage
    -- Input stage: data, K flags, the class of every character (EOP or EEP, EEP, Fill, other K-code) and
    -- the offset of the first data character (word, character), decoded before the stage (timing)
    constant StW_c : positive := 8 * B_c + 5 * B_c + 4;

    signal InCls : std_logic_vector(4*B_c-1 downto 0);
    signal InOff : std_logic_vector(3 downto 0);
    signal StIn  : std_logic_vector(StW_c-1 downto 0);
    signal StOut : std_logic_vector(StW_c-1 downto 0);
    signal StVld : std_logic;
    signal StRdy : std_logic;

    -- Beat rotated by the offset: byte i of the result is byte (i + 4 x offw + offc) mod B, as a rotation by
    -- whole words followed by a rotation by 0 to 3 bytes (two multiplexers of up to four inputs per bit)
    function rotBeat (
        data : Beat_t;
        offw : Off_t;
        offc : Off_t) return Beat_t is
        variable W_v   : natural range 0 to 3;
        variable C_v   : natural range 0 to 3;
        variable Wrd_v : Beat_t;
        variable Res_v : Beat_t;
    begin
        W_v := to_integer(unsigned(offw)) mod NumLanes_g;
        C_v := to_integer(unsigned(offc));

        Wrd_v := data;
        Res_v := data;

        for w in 0 to NumLanes_g-1 loop

            for k in 1 to NumLanes_g-1 loop
                if W_v = k then
                    Wrd_v(32*w+31 downto 32*w) := data(32*((w+k) mod NumLanes_g)+31 downto 32*((w+k) mod NumLanes_g));
                end if;
            end loop;

        end loop;

        for i in 0 to B_c-1 loop
            Res_v(8*i+7 downto 8*i) := Wrd_v(8*i+7 downto 8*i);

            for k in 1 to 3 loop
                if C_v = k then
                    Res_v(8*i+7 downto 8*i) := Wrd_v(8*((i+k) mod B_c)+7 downto 8*((i+k) mod B_c));
                end if;
            end loop;

        end loop;

        return Res_v;
    end function;

    function rotMask (
        mask : Mask_t;
        offw : Off_t;
        offc : Off_t) return Mask_t is
        variable W_v   : natural range 0 to 3;
        variable C_v   : natural range 0 to 3;
        variable Wrd_v : Mask_t;
        variable Res_v : Mask_t;
    begin
        W_v := to_integer(unsigned(offw)) mod NumLanes_g;
        C_v := to_integer(unsigned(offc));

        Wrd_v := mask;

        for w in 0 to NumLanes_g-1 loop

            for k in 1 to NumLanes_g-1 loop
                if W_v = k then
                    Wrd_v(4*w+3 downto 4*w) := mask(4*((w+k) mod NumLanes_g)+3 downto 4*((w+k) mod NumLanes_g));
                end if;
            end loop;

        end loop;

        for i in 0 to B_c-1 loop
            Res_v(i) := Wrd_v(i);

            for k in 1 to 3 loop
                if C_v = k then
                    Res_v(i) := Wrd_v((i+k) mod B_c);
                end if;
            end loop;

        end loop;

        return Res_v;
    end function;

    -- Output positions taken from the current beat: i >= B - offset (none for offset 0)
    function selMaskOf (
        offw : Off_t;
        offc : Off_t) return Mask_t is
        variable Off_v : natural range 0 to 15;
        variable Res_v : Mask_t := (others => '0');
    begin
        Off_v := 4 * (to_integer(unsigned(offw)) mod NumLanes_g) + to_integer(unsigned(offc));

        for i in 0 to B_c-1 loop
            if Off_v > 0 and i >= B_c - Off_v then
                Res_v(i) := '1';
            end if;
        end loop;

        return Res_v;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Input stage
    -----------------------------------------------------------------------------------------------
    p_cls : process (all) is
        variable Char_v : Char_t;
        variable PreD_v : std_logic;
        variable Off_v  : std_logic_vector(3 downto 0);
    begin
        InCls <= (others => '0');
        -- Offset of the first character with a clear K flag (OR of the bits of the one-hot position)
        PreD_v := '0';
        Off_v  := (others => '0');

        for c in 0 to B_c-1 loop
            Off_v  := Off_v or (std_logic_vector(to_unsigned(c, 4)) and
                                (3 downto 0 => not In_K(c) and not PreD_v));
            PreD_v := PreD_v or not In_K(c);
        end loop;

        InOff <= Off_v;

        for c in 0 to B_c-1 loop
            Char_v := In_Data(8*c+7 downto 8*c);
            if In_K(c) = '1' then
                if Char_v = CharEop_c then
                    InCls(4*c) <= '1';
                elsif Char_v = CharEep_c then
                    InCls(4*c)   <= '1';
                    InCls(4*c+1) <= '1';
                elsif Char_v = CharFill_c then
                    InCls(4*c+2) <= '1';
                else
                    InCls(4*c+3) <= '1';
                end if;
            end if;
        end loop;

    end process;

    StIn <= InOff & InCls & In_K & In_Data;

    i_stage : entity olo.olo_base_pl_stage
        generic map (
            Width_g => StW_c
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Valid  => In_Valid,
            In_Ready  => In_Ready,
            In_Data   => StIn,
            Out_Valid => StVld,
            Out_Ready => StRdy,
            Out_Data  => StOut
        );

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Data_v    : Beat_t;
        variable IsD_v     : Mask_t;  -- Data character
        variable IsE_v     : Mask_t;  -- EOP or EEP
        variable IsX_v     : Mask_t;  -- EEP
        variable IsF_v     : Mask_t;  -- Fill
        variable IsO_v     : Mask_t;  -- Other K-code
        variable PreD_v    : Mask_t;  -- A data character before the position
        variable PreE_v    : Mask_t;  -- An end marker before the position
        variable SufF_v    : Mask_t;  -- Only Fills after the position
        variable NewW_v    : Off_t;   -- Offset of a packet that starts in the beat
        variable NewC_v    : Off_t;
        variable Viol_v    : boolean;
        variable Clean_v   : boolean; -- An end marker followed by Fills only
        variable HasD_v    : boolean;
        variable HasE_v    : boolean;
        variable Eep_v     : std_logic;
        variable OffW_v    : Off_t;
        variable OffC_v    : Off_t;
        variable Rot_v     : Beat_t;
        variable RotD_v    : Mask_t;
        variable UseRot_v  : Mask_t;  -- Output bytes from the rotated beat, the others from Hold
        variable Tail_v    : Mask_t;
        variable OutFree_v : boolean;
        variable Take_v    : boolean;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.FrameErr := '0';
        v.Empty    := '0';

        -- Classes of the characters
        Data_v := StOut(8*B_c-1 downto 0);

        for c in 0 to B_c-1 loop
            IsD_v(c) := not StOut(8*B_c+c);
            IsE_v(c) := StOut(9*B_c+4*c);
            IsX_v(c) := StOut(9*B_c+4*c+1);
            IsF_v(c) := StOut(9*B_c+4*c+2);
            IsO_v(c) := StOut(9*B_c+4*c+3);
        end loop;

        -- Prefix and suffix terms
        PreD_v(0)     := '0';
        PreE_v(0)     := '0';
        SufF_v(B_c-1) := '1';

        for c in 1 to B_c-1 loop
            PreD_v(c)       := PreD_v(c-1) or IsD_v(c-1);
            PreE_v(c)       := PreE_v(c-1) or IsE_v(c-1);
            SufF_v(B_c-1-c) := SufF_v(B_c-c) and IsF_v(B_c-c);
        end loop;

        -- Character rules (NI-RX-03), clean end, EEP as the first end marker, offset of the first data
        -- character (OR of the bits of the one-hot position)
        Viol_v  := false;
        Clean_v := false;
        HasD_v  := false;
        HasE_v  := false;
        Eep_v   := '0';

        for c in 0 to B_c-1 loop
            if IsO_v(c) = '1' or (PreE_v(c) = '1' and (IsD_v(c) = '1' or IsE_v(c) = '1')) or
               (IsF_v(c) = '1' and PreE_v(c) = '0' and (r.InPkt = '1' or PreD_v(c) = '1')) then
                Viol_v := true;
            end if;
            if IsE_v(c) = '1' and SufF_v(c) = '1' then
                Clean_v := true;
            end if;
            if IsD_v(c) = '1' then
                HasD_v := true;
            end if;
            if IsE_v(c) = '1' then
                HasE_v := true;
            end if;
            if IsX_v(c) = '1' and PreE_v(c) = '0' then
                Eep_v := '1';
            end if;
        end loop;

        -- Offset of the first data character (decoded before the input stage)
        NewW_v := StOut(StW_c-1 downto StW_c-2);
        NewC_v := StOut(StW_c-3 downto StW_c-4);

        -- Rotation by the offset of the packet: of the open packet, or of the packet that starts
        if r.InPkt = '1' then
            OffW_v := r.OffW;
            OffC_v := r.OffC;
        else
            OffW_v := NewW_v;
            OffC_v := NewC_v;
        end if;
        Rot_v  := rotBeat(Data_v, OffW_v, OffC_v);
        RotD_v := rotMask(IsD_v, OffW_v, OffC_v);

        -- Bytes of the end beat that follow in an additional output beat
        Tail_v := RotD_v and not r.SelMask;

        -- Output register free in this cycle; the input is read when no tail is pending
        OutFree_v := r.OutVld = '0' or Out_Ready = '1';
        if r.OutVld = '1' and Out_Ready = '1' then
            v.OutVld := '0';
        end if;
        if r.TailVld = '1' and OutFree_v then
            -- Tail of a packet (from Hold)
            v.OutVld  := '1';
            v.OutKeep := r.TailKeep;
            v.OutLast := '1';
            v.OutUser := r.TailUser;
            v.TailVld := '0';
        end if;
        if OutFree_v and r.TailVld = '0' then
            StRdy <= '1';
        else
            StRdy <= '0';
        end if;
        Take_v := StVld = '1' and OutFree_v and r.TailVld = '0';

        if Take_v then
            if r.Discard = '1' then
                -- Rest of a packet with a violation
                if Clean_v then
                    v.Discard := '0';
                end if;
            elsif Viol_v then
                -- Violation: an open packet ends with the bytes of its earlier beats (from Hold) and an EEP
                v.FrameErr := '1';
                if r.InPkt = '1' then
                    v.OutVld  := '1';
                    v.OutKeep := not r.SelMask;
                    v.OutLast := '1';
                    v.OutUser := '1';
                end if;
                v.InPkt := '0';
                if not Clean_v then
                    v.Discard := '1';
                end if;
            elsif r.InPkt = '0' then
                if HasD_v and HasE_v then
                    -- Packet within one beat
                    v.OutVld  := '1';
                    v.OutKeep := RotD_v;
                    v.OutLast := '1';
                    v.OutUser := Eep_v;
                elsif HasD_v then
                    -- First beat of a packet
                    v.InPkt   := '1';
                    v.OffW    := NewW_v;
                    v.OffC    := NewC_v;
                    v.SelMask := selMaskOf(NewW_v, NewC_v);
                elsif HasE_v then
                    -- Packet of zero length (NI-RX-02)
                    v.Empty := '1';
                end if;
            else
                -- Beat of the open packet: the held bytes completed by the current beat
                v.OutVld := '1';
                if not HasE_v then
                    v.OutKeep := (others => '1');
                    v.OutLast := '0';
                    v.OutUser := '0';
                else
                    v.InPkt   := '0';
                    v.OutKeep := not r.SelMask or RotD_v;
                    v.OutUser := Eep_v;
                    if Tail_v = (Tail_v'range => '0') then
                        v.OutLast := '1';
                    else
                        v.OutLast  := '0';
                        v.OutUser  := '0';
                        v.TailVld  := '1';
                        v.TailKeep := Tail_v;
                        v.TailUser := Eep_v;
                    end if;
                end if;
            end if;
        end if;

        -- Data registers: their selects and enables depend on registers only, not on the decisions above
        -- (timing). The output register takes the bytes of the rotated beat or of Hold whenever it is free:
        -- the tail from Hold; inside a packet the held bytes from Hold and the rest from the rotated beat
        -- (after a violation only the held bytes are valid); a packet within one beat from the rotated
        -- beat. Bytes outside TKEEP are not used. Hold takes every rotated beat read.
        if r.TailVld = '1' then
            UseRot_v := (others => '0');
        elsif r.InPkt = '1' then
            UseRot_v := r.SelMask;
        else
            UseRot_v := (others => '1');
        end if;
        if OutFree_v then

            for i in 0 to B_c-1 loop
                if UseRot_v(i) = '1' then
                    v.OutData(8*i+7 downto 8*i) := Rot_v(8*i+7 downto 8*i);
                else
                    v.OutData(8*i+7 downto 8*i) := r.Hold(8*i+7 downto 8*i);
                end if;
            end loop;

        end if;
        if Take_v then
            v.Hold := Rot_v;
        end if;

        -- Outputs
        Out_Valid   <= r.OutVld;
        Out_Data    <= r.OutData;
        Out_Keep    <= r.OutKeep;
        Out_Last    <= r.OutLast;
        Out_User    <= r.OutUser;
        Ev_FrameErr <= r.FrameErr;
        Ev_Empty    <= r.Empty;

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
                r.InPkt    <= '0';
                r.Discard  <= '0';
                r.OffW     <= (others => '0');
                r.OffC     <= (others => '0');
                r.SelMask  <= (others => '0');
                r.TailVld  <= '0';
                r.OutVld   <= '0';
                r.FrameErr <= '0';
                r.Empty    <= '0';
            end if;
        end if;
    end process;

end architecture;
