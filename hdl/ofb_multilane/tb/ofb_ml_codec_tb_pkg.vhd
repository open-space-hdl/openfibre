---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the column codec unit testbench.
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_ml_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ml_codec_tb_pkg is

    type CodecCtrl_t is record
        Scramble    : std_logic;
        Unscramble  : std_logic;
        Flush       : std_logic;
        Loopback    : boolean; -- Decoder input from the encoder output instead of its VVC
        RandomReady : boolean; -- Random back-pressure at the encoder output
        HoldReady   : boolean; -- Encoder output not ready
    end record;

    constant CodecCtrlDefault_c : CodecCtrl_t := (Scramble => '0', Unscramble => '0', Flush => '0',
                                                  Loopback => false, RandomReady => false, HoldReady => false);

    signal CodecCtrl : CodecCtrl_t := CodecCtrlDefault_c;

    -- Words leaving the encoder (flag: 0) and the decoder (flag: CRC error)
    shared variable EncLog_v : CodecLog_t;
    shared variable DecLog_v : CodecLog_t;

    -- VVC instances
    constant VvcEnc_c : natural := 1;
    constant VvcDec_c : natural := 2;

end package;
