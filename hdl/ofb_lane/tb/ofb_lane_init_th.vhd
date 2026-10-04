---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of ofb_lane_init: clock, reset and the DUT connected to the signals of
-- ofb_lane_init_tb_pkg.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_lane_init_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_init_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_init_th is

    constant ClkPeriod_c : time := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

begin

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 10 * ClkPeriod_c;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    i_dut : entity work.ofb_lane_init
        generic map (
            ClkFrequency_g     => 156.25e6,
            InitTimeoutWords_g => TbInitTimeoutWords_c
        )
        port map (
            Clk                     => ClkI,
            Rst                     => RstI,
            Cfg_LaneStart           => InitIn.LaneStart,
            Cfg_AutoStart           => InitIn.AutoStart,
            Cfg_LaneReset           => InitIn.CfgLaneReset,
            Ctrl_LaneReset          => InitIn.CtrlLaneReset,
            Ctrl_TxOnly             => InitIn.TxOnly,
            Ctrl_RxOnly             => InitIn.RxOnly,
            Ctrl_FarEndActive       => InitIn.FarEndActive,
            Ctrl_NearCapability     => InitIn.NearCap,
            Ctrl_State              => InitOut.State,
            Ctrl_FarCapability      => InitOut.FarCap,
            Ctrl_FarCapabilityValid => InitOut.FarCapValid,
            Phy_NoSignal            => InitIn.NoSignal,
            Phy_TxEnable            => InitOut.TxEnable,
            Phy_RxEnable            => InitOut.RxEnable,
            Phy_CdrEnable           => InitOut.CdrEnable,
            Phy_RxInvert            => InitOut.RxInvert,
            Tx_Mode                 => InitOut.TxMode,
            Tx_Capability           => InitOut.TxCap,
            Tx_LosCause             => InitOut.LosCause,
            Tx_Init3Sent            => InitIn.Init3Sent,
            Tx_StandbySent          => InitIn.StandbySent,
            Tx_LostSignalSent       => InitIn.LostSent,
            Rx_SyncReset            => InitOut.SyncReset,
            Rx_Active               => InitOut.Active,
            Rx_ErrClear             => InitOut.ErrClear,
            Rx_Word                 => InitIn.Word,
            Rx_RxErr                => InitIn.RxErr,
            Rx_Init1                => InitIn.Init1,
            Rx_Init2                => InitIn.Init2,
            Rx_InvInit1             => InitIn.InvInit1,
            Rx_InvInit2             => InitIn.InvInit2,
            Rx_Init3                => InitIn.Init3,
            Rx_Standby              => InitIn.Standby,
            Rx_LostSignal           => InitIn.LostSignal,
            Rx_Comma                => InitIn.Comma,
            Rx_Skip                 => InitIn.Skip,
            Rx_Param                => InitIn.Param,
            Rx_ErrOverflow          => InitIn.ErrOverflow,
            Stat_Timeout            => InitOut.Timeout,
            Stat_RxPolarity         => InitOut.RxPolarity
        );

end architecture;
