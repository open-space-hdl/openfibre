---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6). This issue implements the
-- Multi-Lane bypass for one lane (NumLanes_g = 1) with the column codec (data scrambling and
-- CRC-16 per lane) and the lane manager.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_multilane is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Control Ports
        Clk                     : in    std_logic;
        Rst                     : in    std_logic;
        -- Transmit rows from the Data Link layer
        TxRow_Data              : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        TxRow_K                 : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        TxRow_Mask              : in    std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
        TxRow_Replicate         : in    std_logic                               := '0';
        TxRow_Valid             : in    std_logic;
        TxRow_Ready             : out   std_logic;
        -- Receive rows to the Data Link layer
        RxRow_Data              : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        RxRow_K                 : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        RxRow_Mask              : out   std_logic_vector(NumLanes_g-1 downto 0);
        RxRow_CrcErr            : out   std_logic;
        RxRow_Valid             : out   std_logic;
        -- Data Link layer control and status
        Dl_LinkReset            : in    std_logic                               := '0';
        Dl_LaneReset            : in    std_logic                               := '0';
        Dl_NearCapability       : in    Char_t;
        Dl_FarCapability        : out   Char_t;
        Dl_FarCapabilityValid   : out   std_logic;
        Dl_FarCapabilityIdle    : out   std_logic;
        Dl_LaneActive           : out   std_logic;
        -- Lane layers: words
        LaneTx_Data             : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        LaneTx_K                : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        LaneTx_Valid            : out   std_logic_vector(NumLanes_g-1 downto 0);
        LaneTx_Ready            : in    std_logic_vector(NumLanes_g-1 downto 0);
        LaneRx_Data             : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        LaneRx_K                : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        LaneRx_Valid            : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Lane layers: control and state
        Lane_Reset              : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_TxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_RxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_FarEndActive       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NearCapability     : out   std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_State              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Lane_FarCapability      : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarCapabilityValid : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Status
        Stat_DataSendingLanes   : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_DataReceivingLanes : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_AlignState         : out   AlignState_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_multilane is

    signal Scramble   : std_logic;
    signal Unscramble : std_logic;
    signal DecData    : Word_t;
    signal DecK       : WordK_t;
    signal DecCrcErr  : std_logic;
    signal DecValid   : std_logic;

begin

    assert NumLanes_g = 1
        report "ofb_multilane: only NumLanes_g = 1 (Multi-Lane bypass) is implemented"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Lane manager (ML-1)
    -----------------------------------------------------------------------------------------------
    i_lane_mgr : entity work.ofb_ml_lane_mgr
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Dl_LaneReset            => Dl_LaneReset,
            Dl_NearCapability       => Dl_NearCapability,
            Dl_FarCapability        => Dl_FarCapability,
            Dl_FarCapabilityValid   => Dl_FarCapabilityValid,
            Dl_FarCapabilityIdle    => Dl_FarCapabilityIdle,
            Dl_LaneActive           => Dl_LaneActive,
            Lane_Reset              => Lane_Reset(0),
            Lane_TxOnly             => Lane_TxOnly(0),
            Lane_RxOnly             => Lane_RxOnly(0),
            Lane_FarEndActive       => Lane_FarEndActive(0),
            Lane_NearCapability     => Lane_NearCapability(7 downto 0),
            Lane_State              => Lane_State(3 downto 0),
            Lane_FarCapability      => Lane_FarCapability(7 downto 0),
            Lane_FarCapabilityValid => Lane_FarCapabilityValid(0),
            Enc_Scramble            => Scramble,
            Dec_Unscramble          => Unscramble,
            Stat_DataSendingLanes   => Stat_DataSendingLanes(0),
            Stat_DataReceivingLanes => Stat_DataReceivingLanes(0),
            Stat_AlignState         => Stat_AlignState
        );

    -----------------------------------------------------------------------------------------------
    -- Transmit: bypass of the row distributor (ML-2) and column encoder (ML-3)
    -----------------------------------------------------------------------------------------------
    i_col_enc : entity work.ofb_ml_col_enc
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Cfg_Scramble => Scramble,
            Ctrl_Flush   => Dl_LinkReset,
            In_Data      => TxRow_Data(31 downto 0),
            In_K         => TxRow_K(3 downto 0),
            In_Valid     => TxRow_Valid,
            In_Ready     => TxRow_Ready,
            Out_Data     => LaneTx_Data(31 downto 0),
            Out_K        => LaneTx_K(3 downto 0),
            Out_Valid    => LaneTx_Valid(0),
            Out_Ready    => LaneTx_Ready(0)
        );

    -----------------------------------------------------------------------------------------------
    -- Receive: column decoder (ML-4) and bypass of the row concentrator (ML-6)
    -----------------------------------------------------------------------------------------------
    i_col_dec : entity work.ofb_ml_col_dec
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Cfg_Unscramble => Unscramble,
            Ctrl_Flush     => Dl_LinkReset,
            In_Data        => LaneRx_Data(31 downto 0),
            In_K           => LaneRx_K(3 downto 0),
            In_Valid       => LaneRx_Valid(0),
            Out_Data       => DecData,
            Out_K          => DecK,
            Out_CrcErr     => DecCrcErr,
            Out_Valid      => DecValid
        );

    -- Multi-Lane control words are not passed to the Data Link layer
    p_rx_row : process (all) is
        variable Kind_v : WordKind_t;
    begin
        Kind_v       := wordKind(DecData, DecK);
        RxRow_Data   <= DecData;
        RxRow_K      <= DecK;
        RxRow_Mask   <= (others => '1');
        RxRow_CrcErr <= DecCrcErr;
        if Kind_v = KindPad or Kind_v = KindMlCtrl then
            RxRow_Valid <= '0';
        else
            RxRow_Valid <= DecValid;
        end if;
    end process;

end architecture;
