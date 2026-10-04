---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of ofb_lane_tx: two DUTs (with and without PRBS words), an AXI-Stream VVC for the
-- words of the Multi-Lane layer and monitors that log the transmitted words.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_tx_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_tx_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_tx_th is

    constant ClkPeriod_c : time := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    signal InData  : Word_t;
    signal InK     : WordK_t;
    signal InValid : std_logic;
    signal InReady : std_logic;

    type WordArray_t is array (0 to 1) of Word_t;
    type KArray_t is array (0 to 1) of WordK_t;
    type BitArray_t is array (0 to 1) of std_logic;

    signal OutData   : WordArray_t;
    signal OutK      : KArray_t;
    signal EvInit3   : BitArray_t;
    signal EvStandby : BitArray_t;
    signal EvLost    : BitArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

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

    i_vvc_in : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => VvcIn_c,
            DataWidth_g   => 32,
            UserWidth_g   => 4
        )
        port map (
            Clk       => ClkI,
            Out_Data  => InData,
            Out_User  => InK,
            Out_Keep  => open,
            Out_Last  => open,
            Out_Valid => InValid,
            Out_Ready => InReady
        );

    i_dut0 : entity work.ofb_lane_tx
        generic map (
            InitPrbsWords_g     => TbPrbsWords_c,
            SkipIntervalWords_g => TbSkipInterval_c
        )
        port map (
            Clk                => ClkI,
            Rst                => RstI,
            Ctrl_Mode          => TxCtrl(0).Mode,
            Ctrl_Capability    => TxCtrl(0).Cap,
            Ctrl_LosCause      => TxCtrl(0).LosCause,
            Ctrl_StandbyReason => TxCtrl(0).Reason,
            In_Data            => InData,
            In_K               => InK,
            In_Valid           => InValid,
            In_Ready           => InReady,
            Out_Data           => OutData(0),
            Out_K              => OutK(0),
            Ev_Init3Sent       => EvInit3(0),
            Ev_StandbySent     => EvStandby(0),
            Ev_LostSignalSent  => EvLost(0)
        );

    i_dut1 : entity work.ofb_lane_tx
        generic map (
            InitPrbsWords_g     => 0,
            SkipIntervalWords_g => 5000
        )
        port map (
            Clk                => ClkI,
            Rst                => RstI,
            Ctrl_Mode          => TxCtrl(1).Mode,
            Ctrl_Capability    => TxCtrl(1).Cap,
            Ctrl_LosCause      => TxCtrl(1).LosCause,
            Ctrl_StandbyReason => TxCtrl(1).Reason,
            In_Data            => (others => '0'),
            In_K               => (others => '0'),
            In_Valid           => '0',
            In_Ready           => open,
            Out_Data           => OutData(1),
            Out_K              => OutK(1),
            Ev_Init3Sent       => EvInit3(1),
            Ev_StandbySent     => EvStandby(1),
            Ev_LostSignalSent  => EvLost(1)
        );

    g_monitor : for i in 0 to 1 generate

        p_monitor : process (ClkI) is
            variable Stat_v : TxStat_t := (Init3Sent => 0, StandbySent => 0, LostSent => 0);
        begin
            if rising_edge(ClkI) then
                if TxCtrl(i).LogEnable then
                    if i = 0 then
                        TxLog0_v.push(OutK(i) & OutData(i));
                    else
                        TxLog1_v.push(OutK(i) & OutData(i));
                    end if;
                end if;
                if EvInit3(i) = '1' then
                    Stat_v.Init3Sent := Stat_v.Init3Sent + 1;
                end if;
                if EvStandby(i) = '1' then
                    Stat_v.StandbySent := Stat_v.StandbySent + 1;
                end if;
                if EvLost(i) = '1' then
                    Stat_v.LostSent := Stat_v.LostSent + 1;
                end if;
                TxStat(i) <= Stat_v;
            end if;
        end process;

    end generate;

end architecture;
