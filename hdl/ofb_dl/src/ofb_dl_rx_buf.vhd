---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receive frame buffer of the Data Link layer (DR-5): stores the data words of the current frame,
-- passes accepted frames to the input VC buffers and discards the others (ECSS 5.7.6.7a, b).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.8)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_rx_buf is
    generic (
        NumVc_g    : positive range 1 to 32 := 8;
        NumLanes_g : positive range 1 to 4  := 1;
        Depth_g    : positive               := 128 -- Rows
    );
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        -- Data frame rows from the receive checks
        Fr_Data        : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        Fr_K           : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Fr_Mask        : in    std_logic_vector(NumLanes_g-1 downto 0);
        Fr_Vc          : in    std_logic_vector(4 downto 0);
        Fr_Valid       : in    std_logic;
        Fr_Commit      : in    std_logic;
        Fr_Drop        : in    std_logic;
        -- Rows to the input VC buffers (no back-pressure: a full buffer is an overflow)
        Vc_Data        : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Vc_K           : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Vc_Mask        : out   std_logic_vector(NumLanes_g-1 downto 0);
        Vc_Valid       : out   std_logic_vector(NumVc_g-1 downto 0);
        Vc_Ready       : in    std_logic_vector(NumVc_g-1 downto 0);
        -- Overflow of an input VC buffer (one cycle per VC), overflow of the frame buffer
        Ev_VcOverflow  : out   std_logic_vector(NumVc_g-1 downto 0);
        Ev_BufOverflow : out   std_logic;
        -- EDAC (MG-3)
        EccInj_Valid   : in    std_logic := '0';
        EccInj_Double  : in    std_logic := '0';
        Ev_EccSec      : out   std_logic;
        Ev_EccDed      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_rx_buf is

    constant N_c     : positive := NumLanes_g;
    constant Width_c : positive := 37 * N_c + 5;

    -- Held last row of the current frame
    signal HeldData  : std_logic_vector(Width_c-1 downto 0);
    signal HeldValid : std_logic;

    signal FifoRst  : std_logic;
    signal InData   : std_logic_vector(Width_c-1 downto 0);
    signal InValid  : std_logic;
    signal InLast   : std_logic;
    signal InDrop   : std_logic;
    signal InReady  : std_logic;
    signal OutData  : std_logic_vector(Width_c-1 downto 0);
    signal OutValid : std_logic;
    signal OutVc    : natural range 0 to 31;
    signal FifoSec  : std_logic;
    signal FifoDed  : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Hold the last row: written as a normal row with the next row, with Last on commit, with Last
    -- and Drop on drop
    -----------------------------------------------------------------------------------------------
    p_hold : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Fr_Valid = '1' then
                HeldData  <= Fr_Vc & Fr_Mask & Fr_K & Fr_Data;
                HeldValid <= '1';
            elsif Fr_Commit = '1' or Fr_Drop = '1' then
                HeldValid <= '0';
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                HeldValid <= '0';
            end if;
        end if;
    end process;

    InData  <= HeldData;
    InValid <= HeldValid and (Fr_Valid or Fr_Commit or Fr_Drop);
    InLast  <= Fr_Commit or Fr_Drop;
    InDrop  <= Fr_Drop;

    -- The frame buffer never back-pressures: a row that does not fit is an overflow
    Ev_BufOverflow <= InValid and not InReady;

    FifoRst <= Rst or Ctrl_LinkReset;

    i_fifo : entity olo.olo_ft_fifo_packet
        generic map (
            Width_g      => Width_c,
            Depth_g      => Depth_g,
            FeatureSet_g => "DROP_SKIP_ONLY",
            MaxPackets_g => 16
        )
        port map (
            Clk               => Clk,
            Rst               => FifoRst,
            In_Valid          => InValid,
            In_Ready          => InReady,
            In_Data           => InData,
            In_Last           => InLast,
            In_Drop           => InDrop,
            Out_Valid         => OutValid,
            Out_Ready         => '1',
            Out_Data          => OutData,
            Out_EccSec        => FifoSec,
            Out_EccDed        => FifoDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(Width_c), EccInj_Double),
            In_ErrInj_Valid   => EccInj_Valid
        );

    Ev_EccSec <= FifoSec and OutValid;
    Ev_EccDed <= FifoDed and OutValid;

    -----------------------------------------------------------------------------------------------
    -- Distribution to the input VC buffers
    -----------------------------------------------------------------------------------------------
    OutVc   <= to_integer(unsigned(OutData(Width_c-1 downto Width_c-5)));
    Vc_Data <= OutData(32*N_c-1 downto 0);
    Vc_K    <= OutData(36*N_c-1 downto 32*N_c);
    Vc_Mask <= OutData(37*N_c-1 downto 36*N_c);

    p_demux : process (all) is
    begin
        Vc_Valid      <= (others => '0');
        Ev_VcOverflow <= (others => '0');
        -- A row with an uncorrectable error is not passed on (the link is reset, DL-ED-01)
        if OutValid = '1' and FifoDed = '0' then
            if OutVc < NumVc_g then
                Vc_Valid(OutVc) <= '1';
                if Vc_Ready(OutVc) = '0' then
                    Ev_VcOverflow(OutVc) <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture;
