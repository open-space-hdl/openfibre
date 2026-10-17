---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Physical adapter PA-1 for one AMD Versal GTY quad, mapped to the symbol stream interface of
-- ofb_core. Two architectures: struct (ofb_pa_gty_struct.vhd) is the transceiver wrapper for
-- synthesis and the AMD simulator; model (sim/ofb_pa_gty_model.vhd) is a behavioural model of the same
-- ports for GHDL and QuestaSim. A flow analyses exactly one of them (compile_order.txt for struct,
-- compile_order_sim.txt for model).
--
-- Documentation: hdl/ofb_pa_gty/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty is
    generic (
        NumLanes_g       : positive range 1 to 4             := 4;
        SimDevice_g      : string                            := "VERSAL_AI_CORE"; -- SIM_DEVICE of BUFG_GT (device family)
        RstPulseCycles_g : positive range 3 to positive'high := 1000; -- Minimum reset of the transceivers (FreeRunClk)
        -- Architecture mdl only: index of the control record of the instance (ofb_pa_model_pkg); struct
        -- ignores it
        ModelIdx_g       : natural                           := 0
    );
    port (
        -- Free-running clock of the transceiver reset controller; asynchronous reset (high active, any
        -- pulse width), synchronised and stretched to RstPulseCycles_g cycles of FreeRunClk inside
        FreeRunClk             : in    std_logic;
        Rst                    : in    std_logic;
        -- Reference clock of the quad (output O of the IBUFDS_GTE5 of the reference clock pins)
        RefClk                 : in    std_logic;
        -- Word clock of the lanes (transmit user clock of the quad, stopped while the transmitters are
        -- reset) and its reset (asserted while the transmitters are not ready, released synchronously)
        LaneClk                : out   std_logic;
        LaneRst                : out   std_logic;
        -- Serial lines
        Gt_TxP                 : out   std_logic_vector(NumLanes_g-1 downto 0);
        Gt_TxN                 : out   std_logic_vector(NumLanes_g-1 downto 0);
        Gt_RxP                 : in    std_logic_vector(NumLanes_g-1 downto 0);
        Gt_RxN                 : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Symbol streams (LaneClk), as the Physical adapter ports of ofb_core
        PhyTx_Data             : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyTx_K                : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Data             : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        PhyRx_K                : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_CodeErr          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_DispErr          : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        PhyRx_Valid            : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_TxEnable           : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxEnable           : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_CdrEnable          : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_RxInvert           : in    std_logic_vector(NumLanes_g-1 downto 0);
        Phy_NoSignal           : out   std_logic_vector(NumLanes_g-1 downto 0);
        -- Serial loopbacks (MIB, ECSS 5.4.2.2): near-end PMA and far-end PMA loopback of the channel
        Phy_SerialNearLoopback : in    std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
        Phy_SerialFarLoopback  : in    std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
        -- PRBS test (LaneClk): pattern generator and checker of the transceiver, bypassing 8B/10B
        -- (pattern 0: off, 1 PRBS-7, 2 PRBS-9, 3 PRBS-15, 4 PRBS-23, 5 PRBS-31), single-cycle force error
        -- and checker reset, checker error per word and lock
        Phy_PrbsTxSel          : in    std_logic_vector(4*NumLanes_g-1 downto 0) := (others => '0');
        Phy_PrbsRxSel          : in    std_logic_vector(4*NumLanes_g-1 downto 0) := (others => '0');
        Phy_PrbsForceErr       : in    std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
        Phy_PrbsCntReset       : in    std_logic_vector(NumLanes_g-1 downto 0)   := (others => '0');
        Phy_PrbsErr            : out   std_logic_vector(NumLanes_g-1 downto 0);
        Phy_PrbsLocked         : out   std_logic_vector(NumLanes_g-1 downto 0);
        -- Transmitters ready (FreeRunClk, register): for Phy_TxReady of ofb_core
        Stat_TxReady           : out   std_logic;
        -- Status (LaneClk)
        Stat_RxReady           : out   std_logic;
        Stat_Aligned           : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_RxBufErr          : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_ClkCor            : out   std_logic_vector(NumLanes_g-1 downto 0)
    );
end entity;
