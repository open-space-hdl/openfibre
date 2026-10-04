---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Parallel loopback of the Lane layer (LN-4), ECSS-E-ST-50-11C clause 5.5.5: near-end loopback
-- (received words replaced by the transmitted words) and far-end loopback (transmitted words
-- replaced by the received words).
--
-- Documentation: hdl/ofb_lane/docs/architecture.md (section 2.4)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_loopback is
    port (
        -- Configuration
        Cfg_NearLoopback : in    std_logic;
        Cfg_FarLoopback  : in    std_logic;
        -- Lane transmitter (LN-2)
        LaneTx_Data      : in    Word_t;
        LaneTx_K         : in    WordK_t;
        -- Lane receiver (LN-3)
        LaneRx_Data      : out   Word_t;
        LaneRx_K         : out   WordK_t;
        LaneRx_CodeErr   : out   WordK_t;
        LaneRx_DispErr   : out   WordK_t;
        LaneRx_Valid     : out   std_logic;
        -- Physical adapter
        PhyTx_Data       : out   Word_t;
        PhyTx_K          : out   WordK_t;
        PhyRx_Data       : in    Word_t;
        PhyRx_K          : in    WordK_t;
        PhyRx_CodeErr    : in    WordK_t;
        PhyRx_DispErr    : in    WordK_t;
        PhyRx_Valid      : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_lane_loopback is

begin

    p_mux : process (all) is
    begin
        -- Near-end loopback (ECSS 5.5.5c)
        if Cfg_NearLoopback = '1' then
            LaneRx_Data    <= LaneTx_Data;
            LaneRx_K       <= LaneTx_K;
            LaneRx_CodeErr <= (others => '0');
            LaneRx_DispErr <= (others => '0');
            LaneRx_Valid   <= '1';
        else
            LaneRx_Data    <= PhyRx_Data;
            LaneRx_K       <= PhyRx_K;
            LaneRx_CodeErr <= PhyRx_CodeErr;
            LaneRx_DispErr <= PhyRx_DispErr;
            LaneRx_Valid   <= PhyRx_Valid;
        end if;

        -- Far-end loopback (ECSS 5.5.5d); IDLE while no word is received
        if Cfg_FarLoopback = '1' then
            if PhyRx_Valid = '1' then
                PhyTx_Data <= PhyRx_Data;
                PhyTx_K    <= PhyRx_K;
            else
                PhyTx_Data <= WordIdle_c;
                PhyTx_K    <= KCtrl_c;
            end if;
        else
            PhyTx_Data <= LaneTx_Data;
            PhyTx_K    <= LaneTx_K;
        end if;
    end process;

end architecture;
