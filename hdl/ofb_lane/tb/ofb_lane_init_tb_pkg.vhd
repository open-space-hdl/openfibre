---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation signals of the ofb_lane_init unit testbench.
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

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_lane_init_tb_pkg is

    -- Inputs of ofb_lane_init, driven by the test sequencer
    type InitIn_t is record
        LaneStart     : std_logic;
        AutoStart     : std_logic;
        CfgLaneReset  : std_logic;
        CtrlLaneReset : std_logic;
        TxOnly        : std_logic;
        RxOnly        : std_logic;
        FarEndActive  : std_logic;
        NearCap       : Char_t;
        NoSignal      : std_logic;
        Init3Sent     : std_logic;
        StandbySent   : std_logic;
        LostSent      : std_logic;
        Word          : std_logic;
        RxErr         : std_logic;
        Init1         : std_logic;
        Init2         : std_logic;
        InvInit1      : std_logic;
        InvInit2      : std_logic;
        Init3         : std_logic;
        Standby       : std_logic;
        LostSignal    : std_logic;
        Comma         : std_logic;
        Skip          : std_logic;
        Param         : Char_t;
        ErrOverflow   : std_logic;
    end record;

    constant InitInDefault_c : InitIn_t := (
        LaneStart     => '0',
        AutoStart     => '0',
        CfgLaneReset  => '0',
        CtrlLaneReset => '0',
        TxOnly        => '0',
        RxOnly        => '0',
        FarEndActive  => '0',
        NearCap       => x"00",
        NoSignal      => '1',
        Init3Sent     => '0',
        StandbySent   => '0',
        LostSent      => '0',
        Word          => '0',
        RxErr         => '0',
        Init1         => '0',
        Init2         => '0',
        InvInit1      => '0',
        InvInit2      => '0',
        Init3         => '0',
        Standby       => '0',
        LostSignal    => '0',
        Comma         => '0',
        Skip          => '0',
        Param         => x"00",
        ErrOverflow   => '0'
    );

    -- Outputs of ofb_lane_init
    type InitOut_t is record
        State       : LaneState_t;
        FarCap      : Char_t;
        FarCapValid : std_logic;
        TxEnable    : std_logic;
        RxEnable    : std_logic;
        CdrEnable   : std_logic;
        RxInvert    : std_logic;
        TxMode      : TxMode_t;
        TxCap       : Char_t;
        LosCause    : LosCause_t;
        SyncReset   : std_logic;
        Active      : std_logic;
        ErrClear    : std_logic;
        Timeout     : std_logic;
        RxPolarity  : std_logic;
    end record;

    signal InitIn  : InitIn_t := InitInDefault_c;
    signal InitOut : InitOut_t;

    -- Initialisation timeout of the unit test (ECSS value)
    constant TbInitTimeoutWords_c : positive := 5000;

end package;
