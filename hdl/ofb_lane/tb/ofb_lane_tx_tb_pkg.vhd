---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the ofb_lane_tx unit testbench (two DUTs: 0 with PRBS words
-- after the INIT words and a short SKIP interval, 1 without PRBS words).
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
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_lane_tx_tb_pkg is

    type TxCtrl_t is record
        Mode      : TxMode_t;
        Cap       : Char_t;
        LosCause  : LosCause_t;
        Reason    : Char_t;
        LogEnable : boolean;
    end record;

    constant TxCtrlDefault_c : TxCtrl_t := (Mode => TxModeOff_c, Cap => x"00", LosCause => "00",
                                            Reason => x"00", LogEnable => false);

    type TxCtrlArray_t is array (0 to 1) of TxCtrl_t;

    signal TxCtrl : TxCtrlArray_t := (others => TxCtrlDefault_c);

    -- Events counted by the harness
    type TxStat_t is record
        Init3Sent   : natural;
        StandbySent : natural;
        LostSent    : natural;
    end record;

    type TxStatArray_t is array (0 to 1) of TxStat_t;

    signal TxStat : TxStatArray_t;

    -- Words sent to the Physical adapter while logging is enabled
    shared variable TxLog0_v : WordLog_t;
    shared variable TxLog1_v : WordLog_t;

    -- Generics of the DUTs
    constant TbPrbsWords_c    : natural  := 64;
    constant TbSkipInterval_c : positive := 20;

    -- VVC instance of the words of the Multi-Lane layer (DUT 0)
    constant VvcIn_c : natural := 1;

end package;
