---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Crossing between the Data Link layer (core clock) and the Multi-Lane layer (lane clock): row
-- FIFOs in both directions, link reset and LaneReset pulses, near-end capability, lane active and
-- far-end capability events. The core clock must not be slower than the lane clock.
--
-- Documentation: hdl/ofb_core/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_cc is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Core clock domain (Data Link layer)
        CoreClk                 : in    std_logic;
        CoreRst                 : in    std_logic;
        Dl_TxRow_Data           : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        Dl_TxRow_K              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Dl_TxRow_Mask           : in    std_logic_vector(NumLanes_g-1 downto 0);
        Dl_TxRow_Replicate      : in    std_logic;
        Dl_TxRow_Valid          : in    std_logic;
        Dl_TxRow_Ready          : out   std_logic;
        Dl_RxRow_Data           : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Dl_RxRow_K              : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Dl_RxRow_Mask           : out   std_logic_vector(NumLanes_g-1 downto 0);
        Dl_RxRow_CrcErr         : out   std_logic;
        Dl_RxRow_Valid          : out   std_logic;
        Dl_LinkReset            : in    std_logic;
        Dl_LaneReset            : in    std_logic;
        Dl_NearCapability       : in    Char_t;
        Dl_FarCapability        : out   Char_t;
        Dl_FarCapabilityValid   : out   std_logic;
        Dl_FarCapabilityIdle    : out   std_logic;
        Dl_LaneActive           : out   std_logic;
        -- Lane clock domain (Multi-Lane layer)
        LaneClk                 : in    std_logic;
        LaneRst                 : in    std_logic;
        Ml_TxRow_Data           : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Ml_TxRow_K              : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Ml_TxRow_Mask           : out   std_logic_vector(NumLanes_g-1 downto 0);
        Ml_TxRow_Replicate      : out   std_logic;
        Ml_TxRow_Valid          : out   std_logic;
        Ml_TxRow_Ready          : in    std_logic;
        Ml_RxRow_Data           : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        Ml_RxRow_K              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Ml_RxRow_Mask           : in    std_logic_vector(NumLanes_g-1 downto 0);
        Ml_RxRow_CrcErr         : in    std_logic;
        Ml_RxRow_Valid          : in    std_logic;
        Ml_LinkReset            : out   std_logic;
        Ml_LaneReset            : out   std_logic;
        Ml_NearCapability       : out   Char_t;
        Ml_FarCapability        : in    Char_t;
        Ml_FarCapabilityValid   : in    std_logic;
        Ml_FarCapabilityIdle    : in    std_logic;
        Ml_LaneActive           : in    std_logic;
        -- Receive row lost because the crossing FIFO was full (lane clock, one cycle)
        Ev_RxOverflow           : out   std_logic;
        -- EDAC (MG-3): SEC events in bits EccChannels_c-1:0, DED events above, in the clock domain
        -- of the read side; injection commands (single, double) in the clock domain of the write side
        Ecc_Core                : out   std_logic_vector(2*EccChannels_c-1 downto 0);
        Ecc_Lane                : out   std_logic_vector(2*EccChannels_c-1 downto 0);
        EccInj_Core             : in    std_logic_vector(2*EccChannels_c-1 downto 0) := (others => '0');
        EccInj_Lane             : in    std_logic_vector(2*EccChannels_c-1 downto 0) := (others => '0')
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_core_cc is

    constant RowW_c : positive := 37 * NumLanes_g + 1;
    constant Ch_c   : positive := EccChannels_c;

    signal TxIn      : std_logic_vector(RowW_c-1 downto 0);
    signal TxOut     : std_logic_vector(RowW_c-1 downto 0);
    signal RxIn      : std_logic_vector(RowW_c-1 downto 0);
    signal RxOut     : std_logic_vector(RowW_c-1 downto 0);
    signal RxReady   : std_logic;
    signal Active    : std_logic_vector(0 downto 0);
    signal CoreFlush : std_logic;
    signal ActiveIn  : std_logic_vector(0 downto 0);
    signal CapIn     : std_logic_vector(8 downto 0);
    signal CapOut    : std_logic_vector(8 downto 0);
    signal CapValid  : std_logic;
    signal TxValid   : std_logic;
    signal RxValid   : std_logic;
    signal TxSec     : std_logic;
    signal TxDed     : std_logic;
    signal RxSec     : std_logic;
    signal RxDed     : std_logic;
    signal CapSec    : std_logic;
    signal CapDed    : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Rows
    -----------------------------------------------------------------------------------------------
    -- Rows of the time before a link reset are discarded
    CoreFlush <= CoreRst or Dl_LinkReset;

    TxIn               <= Dl_TxRow_Replicate & Dl_TxRow_Mask & Dl_TxRow_K & Dl_TxRow_Data;
    Ml_TxRow_Data      <= TxOut(32*NumLanes_g-1 downto 0);
    Ml_TxRow_K         <= TxOut(36*NumLanes_g-1 downto 32*NumLanes_g);
    Ml_TxRow_Mask      <= TxOut(37*NumLanes_g-1 downto 36*NumLanes_g);
    Ml_TxRow_Replicate <= TxOut(37*NumLanes_g);

    i_tx_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => RowW_c,
            Depth_g         => 16,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => CoreClk,
            In_Rst            => CoreFlush,
            In_Data           => TxIn,
            In_Valid          => Dl_TxRow_Valid,
            In_Ready          => Dl_TxRow_Ready,
            Out_Clk           => LaneClk,
            Out_Rst           => LaneRst,
            Out_Data          => TxOut,
            Out_Valid         => TxValid,
            Out_Ready         => Ml_TxRow_Ready,
            Out_EccSec        => TxSec,
            Out_EccDed        => TxDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(RowW_c), EccInj_Core(Ch_c + EccChCcTx_c)),
            In_ErrInj_Valid   => EccInj_Core(EccChCcTx_c) or EccInj_Core(Ch_c + EccChCcTx_c)
        );

    Ml_TxRow_Valid <= TxValid;

    RxIn            <= Ml_RxRow_CrcErr & Ml_RxRow_Mask & Ml_RxRow_K & Ml_RxRow_Data;
    Dl_RxRow_Data   <= RxOut(32*NumLanes_g-1 downto 0);
    Dl_RxRow_K      <= RxOut(36*NumLanes_g-1 downto 32*NumLanes_g);
    Dl_RxRow_Mask   <= RxOut(37*NumLanes_g-1 downto 36*NumLanes_g);
    Dl_RxRow_CrcErr <= RxOut(37*NumLanes_g);
    Ev_RxOverflow   <= Ml_RxRow_Valid and not RxReady;

    i_rx_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => RowW_c,
            Depth_g => 16
        )
        port map (
            In_Clk            => LaneClk,
            In_Rst            => LaneRst,
            In_Data           => RxIn,
            In_Valid          => Ml_RxRow_Valid,
            In_Ready          => RxReady,
            Out_Clk           => CoreClk,
            Out_Rst           => CoreFlush,
            Out_Data          => RxOut,
            Out_Valid         => RxValid,
            Out_Ready         => '1',
            Out_EccSec        => RxSec,
            Out_EccDed        => RxDed,
            In_ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(RowW_c), EccInj_Lane(Ch_c + EccChCcRx_c)),
            In_ErrInj_Valid   => EccInj_Lane(EccChCcRx_c) or EccInj_Lane(Ch_c + EccChCcRx_c)
        );

    Dl_RxRow_Valid <= RxValid;

    -----------------------------------------------------------------------------------------------
    -- Control
    -----------------------------------------------------------------------------------------------
    i_resets : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk       => CoreClk,
            In_Rst       => CoreRst,
            In_Pulse(0)  => Dl_LinkReset,
            In_Pulse(1)  => Dl_LaneReset,
            Out_Clk      => LaneClk,
            Out_Rst      => LaneRst,
            Out_Pulse(0) => Ml_LinkReset,
            Out_Pulse(1) => Ml_LaneReset
        );

    i_near_cap : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => 8
        )
        port map (
            In_Clk   => CoreClk,
            In_Rst   => CoreRst,
            In_Data  => Dl_NearCapability,
            Out_Clk  => LaneClk,
            Out_Rst  => LaneRst,
            Out_Data => Ml_NearCapability
        );

    ActiveIn(0) <= Ml_LaneActive;

    i_active : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => 1
        )
        port map (
            In_Clk   => LaneClk,
            In_Rst   => LaneRst,
            In_Data  => ActiveIn,
            Out_Clk  => CoreClk,
            Out_Rst  => CoreRst,
            Out_Data => Active
        );

    Dl_LaneActive <= Active(0);

    -- The capability event crosses together with its qualifier (no lane active at the event): the
    -- lane may become active right after the event, and a separately crossed lane active level
    -- could arrive first
    CapIn                <= Ml_FarCapabilityIdle & Ml_FarCapability;
    Dl_FarCapability     <= CapOut(7 downto 0);
    Dl_FarCapabilityIdle <= CapOut(8);

    i_far_cap : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => 9,
            Depth_g => 4
        )
        port map (
            In_Clk     => LaneClk,
            In_Rst     => LaneRst,
            In_Data    => CapIn,
            In_Valid   => Ml_FarCapabilityValid,
            Out_Clk    => CoreClk,
            Out_Rst    => CoreRst,
            Out_Data   => CapOut,
            Out_Valid  => CapValid,
            Out_Ready  => '1',
            Out_EccSec => CapSec,
            Out_EccDed => CapDed
        );

    Dl_FarCapabilityValid <= CapValid;

    -----------------------------------------------------------------------------------------------
    -- EDAC events of the words read (MG-3)
    -----------------------------------------------------------------------------------------------
    p_ecc : process (all) is
    begin
        Ecc_Core                     <= (others => '0');
        Ecc_Lane                     <= (others => '0');
        Ecc_Lane(EccChCcTx_c)        <= TxSec and TxValid and Ml_TxRow_Ready;
        Ecc_Lane(Ch_c + EccChCcTx_c) <= TxDed and TxValid and Ml_TxRow_Ready;
        Ecc_Core(EccChCcRx_c)        <= RxSec and RxValid;
        Ecc_Core(Ch_c + EccChCcRx_c) <= RxDed and RxValid;
        Ecc_Core(EccChCtrl_c)        <= CapSec and CapValid;
        Ecc_Core(Ch_c + EccChCtrl_c) <= CapDed and CapValid;
    end process;

end architecture;
