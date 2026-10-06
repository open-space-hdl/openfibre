---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Row and row queue of the multi-lane link testbench. In its own package, so that the shared
-- variables of ofb_ml_link_tb_pkg are declared after the elaboration of the protected type body
-- (required by QuestaSim, vcom-1257).
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ml_row_queue_pkg is

    constant MaxLanes_c : positive := 4;

    -- Row of the Data Link layer (words beyond NumLanes_g are not used)
    type TbRow_t is record
        Data      : std_logic_vector(32*MaxLanes_c-1 downto 0);
        K         : std_logic_vector(4*MaxLanes_c-1 downto 0);
        Mask      : std_logic_vector(MaxLanes_c-1 downto 0);
        Replicate : std_logic;
    end record;

    type RowQueue_t is protected

        procedure push (row : TbRow_t);

        impure function pop return TbRow_t;
        impure function count return natural;

        procedure clear;
    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_ml_row_queue_pkg is

    type RowQueue_t is protected body

        type Rows_t is array (0 to 16383) of TbRow_t;

        variable Rows_v  : Rows_t;
        variable Head_v  : natural := 0;
        variable Count_v : natural := 0;

        procedure push (row : TbRow_t) is
        begin
            assert Count_v < Rows_t'length
                report "RowQueue_t full"
                severity failure;
            Rows_v((Head_v + Count_v) mod Rows_t'length) := row;
            Count_v                                      := Count_v + 1;
        end procedure;

        impure function pop return TbRow_t is
            variable Row_v : TbRow_t;
        begin
            Row_v   := Rows_v(Head_v);
            Head_v  := (Head_v + 1) mod Rows_t'length;
            Count_v := Count_v - 1;
            return Row_v;
        end function;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        procedure clear is
        begin
            Count_v := 0;
        end procedure;

    end protected body;

end package body;
