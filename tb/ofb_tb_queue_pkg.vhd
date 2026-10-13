---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Queues of beats of the VC ports for the testbenches of the Network interface and of the core: bytes
-- or characters 127:0 (byte 0 in bits 7:0), TKEEP or K flags 143:128, TLAST 144, TUSER 145.
--
-- Documentation: hdl/ofb_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_tb_queue_pkg is

    subtype BeatEntry_t is std_logic_vector(145 downto 0);

    -- Four queues of 8192 beats
    type BeatQueues_t is protected

        procedure push (
            q     : natural;
            entry : BeatEntry_t);

        impure function pop (q : natural) return BeatEntry_t;
        impure function count (q : natural) return natural;

    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_tb_queue_pkg is

    type BeatQueues_t is protected body

        type Entries_t is array (0 to 3, 0 to 8191) of BeatEntry_t;
        type Index_t is array (0 to 3) of natural;

        variable Entries_v : Entries_t;
        variable Head_v    : Index_t := (others => 0);
        variable Count_v   : Index_t := (others => 0);

        procedure push (
            q     : natural;
            entry : BeatEntry_t) is
        begin
            assert Count_v(q) < 8192
                report "BeatQueues_t: queue full"
                severity failure;
            Entries_v(q, (Head_v(q) + Count_v(q)) mod 8192) := entry;
            Count_v(q)                                      := Count_v(q) + 1;
        end procedure;

        impure function pop (q : natural) return BeatEntry_t is
            variable Entry_v : BeatEntry_t;
        begin
            Entry_v    := Entries_v(q, Head_v(q));
            Head_v(q)  := (Head_v(q) + 1) mod 8192;
            Count_v(q) := Count_v(q) - 1;
            return Entry_v;
        end function;

        impure function count (q : natural) return natural is
        begin
            return Count_v(q);
        end function;

    end protected body;

end package body;
