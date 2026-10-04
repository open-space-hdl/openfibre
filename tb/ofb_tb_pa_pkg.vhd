---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Channel control of the behavioural Physical adapter model (ofb_tb_pa_model). The test sequencer
-- drives PaCtrl (one entry per model instance); the models only read it.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_tb_pa_pkg is

    -- Control of one direction of a channel
    type PaDirCtrl_t is record
        Cut    : boolean;              -- Cable disconnected: no signal at the receiver
        Invert : boolean;              -- Crossed differential pair: every received bit inverted
        Offset : natural range 0 to 3; -- Additional delay in symbols (word misalignment)
        Flips  : natural;              -- Number of single bit errors requested so far; every
        -- increment flips one bit of the next symbol
        Skew   : natural range 0 to 7; -- Additional delay in words (lane skew); a change while
    -- words flow drops or repeats words (lane slip)
    end record;

    type PaCtrl_t is record
        AtoB : PaDirCtrl_t;
        BtoA : PaDirCtrl_t;
    end record;

    constant PaDirCtrlDefault_c : PaDirCtrl_t := (Cut => false, Invert => false, Offset => 0, Flips => 0, Skew => 0);
    constant PaCtrlDefault_c    : PaCtrl_t    := (AtoB => PaDirCtrlDefault_c, BtoA => PaDirCtrlDefault_c);

    type PaCtrlArray_t is array (natural range <>) of PaCtrl_t;

    -- One entry per model instance (generic Instance_g of ofb_tb_pa_model)
    signal PaCtrl : PaCtrlArray_t(0 to 15) := (others => PaCtrlDefault_c);

end package;
