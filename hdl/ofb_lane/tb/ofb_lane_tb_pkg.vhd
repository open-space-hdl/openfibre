---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Shared objects of the Lane layer testbench: configuration driven by the test sequencer, status
-- collected by the harness, scoreboard of the received words.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_tb_kword_sb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_lane_tb_pkg is

    -- Inputs of one lane end, driven by the test sequencer
    type LaneCfg_t is record
        LaneStart      : std_logic;
        AutoStart      : std_logic;
        LaneReset      : std_logic;
        NearLoopback   : std_logic;
        FarLoopback    : std_logic;
        StandbyReason  : Char_t;
        CtrlLaneReset  : std_logic;
        TxOnly         : std_logic;
        RxOnly         : std_logic;
        FarEndActive   : std_logic;
        NearCapability : Char_t;
        SbCheck        : boolean; -- check the received words against the scoreboard
    end record;

    constant LaneCfgDefault_c : LaneCfg_t := (
        LaneStart      => '0',
        AutoStart      => '0',
        LaneReset      => '0',
        NearLoopback   => '0',
        FarLoopback    => '0',
        StandbyReason  => x"00",
        CtrlLaneReset  => '0',
        TxOnly         => '0',
        RxOnly         => '0',
        FarEndActive   => '0',
        NearCapability => x"00",
        SbCheck        => true
    );

    -- Outputs of one lane end, collected by the harness (event outputs are counted)
    type LaneStat_t is record
        State            : LaneState_t;
        RxErrCount       : Char_t;
        RxPolarity       : std_logic;
        FarCapability    : Char_t;
        CtrlFarCap       : Char_t;
        TimeoutCnt       : natural;
        OverflowCnt      : natural;
        FarStandbyCnt    : natural;
        FarStandbyReason : Char_t;
        FarLostCnt       : natural;
        FarLostReason    : Char_t;
        CapEventCnt      : natural;
        RxWordCnt        : natural; -- words passed to the Multi-Lane layer
        RxErrWordCnt     : natural; -- RXERR words among them
        SkipCnt          : natural; -- SKIP words sent to the Physical adapter
        SkipGapMin       : natural; -- smallest number of words between two SKIP words
        SkipGapMax       : natural; -- largest number of words between two SKIP words
        ActiveCnt        : natural; -- number of entries into the Active state
        TxEnable         : std_logic;
    end record;

    type LaneCfgArray_t is array (0 to 1) of LaneCfg_t;
    type LaneStatArray_t is array (0 to 1) of LaneStat_t;

    signal LaneCfg  : LaneCfgArray_t := (others => LaneCfgDefault_c);
    signal LaneStat : LaneStatArray_t;

    -- Scoreboard of the words passed to the Multi-Lane layer: instance 1 = lane end A, 2 = B
    shared variable RxSb_v : t_generic_sb;

    -- VVC instance indices of the transmit words of lane end A and B
    constant VvcTxA_c : natural := 1;
    constant VvcTxB_c : natural := 2;

end package;
