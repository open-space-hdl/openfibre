---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- UVVM scoreboard for words with K flags (36 bits: K flags in 35:32, data in 31:0).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_tb_sb_support_pkg is

    function kwordToString (word : std_logic_vector) return string;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_tb_sb_support_pkg is

    function kwordToString (word : std_logic_vector) return string is
        variable Word_v : std_logic_vector(35 downto 0);
    begin
        Word_v := word;
        return "K=" & to_hstring(Word_v(35 downto 32)) & " D=" & to_hstring(Word_v(31 downto 0));
    end function;

end package body;

---------------------------------------------------------------------------------------------------
-- Scoreboard package instance
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library bitvis_vip_scoreboard;

library work;
    use work.ofb_tb_sb_support_pkg.all;

package ofb_tb_kword_sb_pkg is new bitvis_vip_scoreboard.generic_sb_pkg
    generic map (
        t_element                => std_logic_vector(35 downto 0),
        element_match            => std_match,
        to_string_element        => kwordToString,
        GC_QUEUE_COUNT_MAX       => 1000000,
        GC_QUEUE_COUNT_THRESHOLD => 1000000
    );
