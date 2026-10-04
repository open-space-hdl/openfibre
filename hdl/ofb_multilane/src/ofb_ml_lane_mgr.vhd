---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane manager of the Multi-Lane layer (ML-1) for a single lane (Multi-Lane bypass): lane
-- control, capability exchange with the Data Link layer, scramble enables and status.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.5)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_lane_mgr is
    port (
        -- Control Ports
        Clk                     : in    std_logic;
        Rst                     : in    std_logic;
        -- Data Link layer
        Dl_LaneReset            : in    std_logic;
        Dl_NearCapability       : in    Char_t;
        Dl_FarCapability        : out   Char_t;
        Dl_FarCapabilityValid   : out   std_logic;
        Dl_FarCapabilityIdle    : out   std_logic; -- With the event: no lane was Active
        Dl_LaneActive           : out   std_logic;
        -- Lane layer
        Lane_Reset              : out   std_logic;
        Lane_TxOnly             : out   std_logic;
        Lane_RxOnly             : out   std_logic;
        Lane_FarEndActive       : out   std_logic;
        Lane_NearCapability     : out   Char_t;
        Lane_State              : in    LaneState_t;
        Lane_FarCapability      : in    Char_t;
        Lane_FarCapabilityValid : in    std_logic;
        -- Column codec
        Enc_Scramble            : out   std_logic;
        Dec_Unscramble          : out   std_logic;
        -- Status
        Stat_DataSendingLanes   : out   std_logic;
        Stat_DataReceivingLanes : out   std_logic;
        Stat_AlignState         : out   AlignState_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_lane_mgr is

    signal Active   : std_logic;
    signal Scramble : std_logic;
    signal NearCap  : Char_t;

begin

    Active <= '1' when Lane_State = LaneStateActive_c else '0';

    -- Near-end capability: held while the lane is in Connected, so that all INIT3 words of one
    -- initialisation carry the same value (the INIT3LinkResetFlag may change in the middle).
    -- Scramble enable: the DataScrambled bit sent in INIT3, held while the lane is Active.
    p_cap : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Lane_State /= LaneStateConnected_c then
                NearCap <= Dl_NearCapability(7 downto CapMultiLane_c + 1) & '0' &
                           Dl_NearCapability(CapMultiLane_c - 1 downto 0);
            end if;
            if Active = '0' then
                Scramble <= NearCap(CapDataScrambled_c);
            end if;
            if Rst = '1' then
                NearCap  <= (others => '0');
                Scramble <= '0';
            end if;
        end if;
    end process;

    -- Lane control (one lane: bidirectional, far end never reported active)
    Lane_Reset          <= Dl_LaneReset;
    Lane_TxOnly         <= '0';
    Lane_RxOnly         <= '0';
    Lane_FarEndActive   <= '0';
    Lane_NearCapability <= NearCap;

    -- Data Link layer
    Dl_FarCapability      <= Lane_FarCapability;
    Dl_FarCapabilityValid <= Lane_FarCapabilityValid;
    Dl_FarCapabilityIdle  <= not Active;
    Dl_LaneActive         <= Active;

    -- Column codec
    Enc_Scramble   <= Scramble;
    Dec_Unscramble <= Lane_FarCapability(CapDataScrambled_c);

    -- Status
    Stat_DataSendingLanes   <= Active;
    Stat_DataReceivingLanes <= Active;
    Stat_AlignState         <= AlignBothEndsReady_c when Active = '1' else AlignNotReady_c;

end architecture;
