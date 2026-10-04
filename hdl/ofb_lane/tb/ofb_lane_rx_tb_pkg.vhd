---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the ofb_lane_rx unit testbench.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_lane_rx_tb_pkg is

    -- Inputs of ofb_lane_rx, driven by the test sequencer
    type RxIn_t is record
        SyncReset : std_logic;
        Active    : std_logic;
        ErrClear  : std_logic;
        Data      : Word_t;
        K         : WordK_t;
        CodeErr   : WordK_t;
        DispErr   : WordK_t;
        Valid     : std_logic;
    end record;

    constant RxInDefault_c : RxIn_t := (
        SyncReset => '0',
        Active    => '0',
        ErrClear  => '0',
        Data      => (others => '0'),
        K         => (others => '0'),
        CodeErr   => (others => '0'),
        DispErr   => (others => '0'),
        Valid     => '0'
    );

    signal RxIn : RxIn_t := RxInDefault_c;

    -- Outputs, collected by the harness (events are counted)
    type RxStat_t is record
        Words      : natural;
        RxErrs     : natural;
        Init1      : natural;
        Init2      : natural;
        InvInit1   : natural;
        InvInit2   : natural;
        Init3      : natural;
        Standby    : natural;
        LostSignal : natural;
        Comma      : natural;
        Skip       : natural;
        LastParam  : Char_t;
        ErrCount   : Char_t;
        Overflow   : std_logic;
        OverflowEv : natural;
    end record;

    signal RxStat : RxStat_t;

    -- Log of the words passed to the Multi-Lane layer
    shared variable OutLog_v : WordLog_t;

    -- Leak interval of the RXERR counter in the unit test
    constant TbRxErrLeakWords_c : positive := 64;

end package;

