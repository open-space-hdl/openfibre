---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the Multi-Lane layer testbench (two ends A and B, one lane
-- each, connected through Lane layers and the behavioural Physical adapter model).
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;
    use work.ofb_ml_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_multilane_tb_pkg is

    -- Inputs of one end, driven by the test sequencer
    type MlCfg_t is record
        NearCapability : Char_t;    -- Data Link layer near-end capability
        LinkReset      : std_logic; -- Data Link layer link reset
        LaneReset      : std_logic; -- Data Link layer LaneReset of all lanes
        LaneStart      : std_logic; -- Lane management parameters
        AutoStart      : std_logic;
    end record;

    constant MlCfgDefault_c : MlCfg_t := (
        NearCapability => x"00",
        LinkReset      => '0',
        LaneReset      => '0',
        LaneStart      => '0',
        AutoStart      => '0'
    );

    -- Outputs of one end, collected by the harness
    type MlStat_t is record
        LaneState     : LaneState_t;
        LaneActive    : std_logic;                    -- Dl_LaneActive
        FarCapability : Char_t;                       -- Dl_FarCapability
        FarCapCnt     : natural;                      -- Dl_FarCapabilityValid events
        LaneCtrl      : std_logic_vector(3 downto 0); -- Lane_Reset, TxOnly, RxOnly, FarEndActive
        LaneCtrlSeen  : std_logic_vector(3 downto 0); -- bits that have been 1 since the start
        LaneNearCap   : Char_t;                       -- Lane_NearCapability
        DataSending   : std_logic;
        DataReceiving : std_logic;
        AlignState    : AlignState_t;
        ActiveCnt     : natural;                      -- entries into the Active state of the lane
    end record;

    type MlCfgArray_t is array (0 to 1) of MlCfg_t;
    type MlStatArray_t is array (0 to 1) of MlStat_t;

    signal MlCfg  : MlCfgArray_t := (others => MlCfgDefault_c);
    signal MlStat : MlStatArray_t;

    -- Rows passed to the Data Link layer at A and B (flag: CRC error)
    shared variable RxLogA_v : CodecLog_t;
    shared variable RxLogB_v : CodecLog_t;

    -- VVC instances of the transmit rows of A and B
    constant VvcA_c : natural := 1;
    constant VvcB_c : natural := 2;

end package;
