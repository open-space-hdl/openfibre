---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane manager of the Multi-Lane layer (ML-1): lane control for unidirectional lanes (TxOnly,
-- RxOnly, FarEndActive, LaneReset), data-sending and hot redundant lanes, bypass selection,
-- capability exchange with the Data Link layer and scramble enables.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md (section 2.5)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_lane_mgr is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        -- Control Ports
        Clk                     : in    std_logic;
        Rst                     : in    std_logic;
        -- Management parameters
        Cfg_TxEn                : in    std_logic_vector(NumLanes_g-1 downto 0);
        Cfg_RxEn                : in    std_logic_vector(NumLanes_g-1 downto 0);
        Cfg_MaxDataLanes        : in    std_logic_vector(2 downto 0);
        Cfg_Bypass              : in    std_logic;
        -- Data Link layer
        Dl_LaneReset            : in    std_logic;
        Dl_NearCapability       : in    Char_t;
        Dl_FarCapability        : out   Char_t;
        Dl_FarCapabilityValid   : out   std_logic;
        Dl_FarCapabilityIdle    : out   std_logic; -- With the event: no lane was Active
        Dl_LaneActive           : out   std_logic;
        -- Lane layers
        Lane_Reset              : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_TxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_RxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_FarEndActive       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NearCapability     : out   std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_State              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Lane_FarCapability      : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarCapabilityValid : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Valid ACTIVE word received (lane alignment)
        Al_FarAct               : in    std_logic_vector(15 downto 0) := (others => '0');
        Al_FarActValid          : in    std_logic                     := '0';
        -- Lane sets for the distributor and the alignment
        Bypass                  : out   std_logic;
        ActLanes                : out   std_logic_vector(NumLanes_g-1 downto 0);
        TxLanes                 : out   std_logic_vector(NumLanes_g-1 downto 0);
        DataLanes               : out   std_logic_vector(NumLanes_g-1 downto 0);
        HotLanes                : out   std_logic_vector(NumLanes_g-1 downto 0);
        RxLanes                 : out   std_logic_vector(NumLanes_g-1 downto 0);
        NumTxLanes              : out   std_logic_vector(3 downto 0);
        NumRxLanes              : out   std_logic_vector(3 downto 0);
        -- Column codec
        Enc_Scramble            : out   std_logic_vector(NumLanes_g-1 downto 0);
        Dec_Unscramble          : out   std_logic_vector(NumLanes_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ml_lane_mgr is

    type TwoProcess_r is record
        BypassFar : std_logic;
        MaxLanes  : natural range 1 to NumLanes_g;
        NearCap   : std_logic_vector(8*NumLanes_g-1 downto 0);
        Scramble  : std_logic_vector(NumLanes_g-1 downto 0);
        RxOnly    : std_logic_vector(NumLanes_g-1 downto 0);
        FarActive : std_logic_vector(NumLanes_g-1 downto 0);
        CapSeen   : std_logic_vector(NumLanes_g-1 downto 0);
        FarScr    : std_logic;
        ResetHold : std_logic_vector(NumLanes_g-1 downto 0);
        Act       : std_logic_vector(NumLanes_g-1 downto 0);
        Tx        : std_logic_vector(NumLanes_g-1 downto 0);
        Data      : std_logic_vector(NumLanes_g-1 downto 0);
        Rx        : std_logic_vector(NumLanes_g-1 downto 0);
        NumTx     : unsigned(3 downto 0);
        NumRx     : unsigned(3 downto 0);
        CapValid  : std_logic;
        Cap       : Char_t;
        CapIdle   : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal ResetCond : std_logic_vector(NumLanes_g-1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v          : TwoProcess_r;
        variable State_v    : LaneState_t;
        variable Active_v   : std_logic_vector(NumLanes_g-1 downto 0);
        variable Clear_v    : std_logic_vector(NumLanes_g-1 downto 0);
        variable Bypass_v   : std_logic;
        variable BidirAct_v : boolean;
        variable TxOnly_v   : std_logic_vector(NumLanes_g-1 downto 0);
        variable Max_v      : natural range 0 to 7;
        variable Cnt_v      : natural range 0 to NumLanes_g;
        variable Cond_v     : std_logic_vector(NumLanes_g-1 downto 0);
    begin
        -- Hold variables stable
        v := r;

        -- Lane states
        for i in 0 to NumLanes_g-1 loop
            State_v     := Lane_State(4*i+3 downto 4*i);
            Active_v(i) := '0';
            Clear_v(i)  := '0';
            if State_v = LaneStateActive_c then
                Active_v(i) := '1';
            end if;
            if State_v = LaneStateClearLine_c then
                Clear_v(i) := '1';
            end if;
        end loop;

        -- Bypass (ML-LM-07): far end of lane 0 not Multi-Lane capable
        if Lane_FarCapabilityValid(0) = '1' then
            v.BypassFar := not Lane_FarCapability(CapMultiLane_c);
        end if;
        if NumLanes_g = 1 or Cfg_Bypass = '1' or r.BypassFar = '1' then
            Bypass_v := '1';
        else
            Bypass_v := '0';
        end if;

        -- Bidirectional lane in Active (ECSS 5.6.9.4a.1, 5.6.9.5a.3)
        BidirAct_v := false;

        for i in 0 to NumLanes_g-1 loop
            if Active_v(i) = '1' and Cfg_TxEn(i) = '1' and Cfg_RxEn(i) = '1' then
                BidirAct_v := true;
            end if;
        end loop;

        for i in 0 to NumLanes_g-1 loop
            -- Near-end capability, held while the lane is in Connected (ML-LM-03, ML-LM-08)
            if Lane_State(4*i+3 downto 4*i) /= LaneStateConnected_c then
                v.NearCap(8*i+7 downto 8*i) := Dl_NearCapability;
                if NumLanes_g > 1 and Cfg_Bypass = '0' then
                    v.NearCap(8*i+CapMultiLane_c) := '1';
                else
                    v.NearCap(8*i+CapMultiLane_c) := '0';
                end if;
            end if;
            -- Scramble enable: the value sent in INIT3, held while the lane is Active (ML-LM-05)
            if Active_v(i) = '0' then
                v.Scramble(i) := r.NearCap(8*i+CapDataScrambled_c);
            end if;

            -- TxOnly (ECSS 5.6.9.3)
            if Cfg_TxEn(i) = '1' and Cfg_RxEn(i) = '0' and Clear_v(i) = '0' then
                TxOnly_v(i) := '1';
            else
                TxOnly_v(i) := '0';
            end if;

            -- RxOnly (ECSS 5.6.9.4)
            if Cfg_TxEn(i) = '1' or Cfg_RxEn(i) = '0' then
                v.RxOnly(i) := '0';
            elsif BidirAct_v then
                v.RxOnly(i) := '1';
            end if;

            -- FarEndActive (ECSS 5.6.9.2)
            if Al_FarActValid = '1' then
                v.FarActive(i) := Al_FarAct(i);
            end if;
            if Clear_v(i) = '1' then
                v.FarActive(i) := '0';
            end if;

            -- LaneReset (ECSS 5.6.9.5): request until the lane is in ClearLine
            Cond_v(i) := Dl_LaneReset;
            if Active_v(i) = '1' and TxOnly_v(i) = '1' and (r.FarActive(i) = '0' or not BidirAct_v) then
                Cond_v(i) := '1';
            end if;
            if Cfg_TxEn(i) = '0' and Cfg_RxEn(i) = '0' then
                Cond_v(i) := '1';
            end if;
            if Bypass_v = '1' and i > 0 then
                Cond_v(i) := '1';
            end if;
            v.ResetHold(i) := (Cond_v(i) or r.ResetHold(i)) and not Clear_v(i);
        end loop;

        -- Lane sets (ML-LM-13): data-sending lanes are the lowest active transmitting lanes
        -- The maximum is taken over on link reset or while no lane is Active (Table 5-36)
        Max_v := to_integer(unsigned(Cfg_MaxDataLanes));
        if Max_v = 0 or Max_v > NumLanes_g then
            Max_v := NumLanes_g;
        end if;
        if Dl_LaneReset = '1' or Active_v = (Active_v'range => '0') then
            v.MaxLanes := Max_v;
        end if;
        Max_v  := r.MaxLanes;
        v.Act  := Active_v;
        v.Tx   := (others => '0');
        v.Data := (others => '0');
        v.Rx   := (others => '0');
        Cnt_v  := 0;
        v.Tx   := Active_v and Cfg_TxEn;
        v.Rx   := Active_v and Cfg_RxEn;
        if Bypass_v = '1' then
            -- Bypass: lane 0 only
            v.Tx(NumLanes_g-1 downto 1) := (others => '0');
            v.Rx(NumLanes_g-1 downto 1) := (others => '0');
        end if;

        for i in 0 to NumLanes_g-1 loop
            if v.Tx(i) = '1' and Cnt_v < Max_v then
                v.Data(i) := '1';
                Cnt_v     := Cnt_v + 1;
            end if;
        end loop;

        v.NumTx := to_unsigned(countOnes(v.Tx), 4);
        v.NumRx := to_unsigned(countOnes(v.Rx), 4);

        -- Capability events: lowest lane with an event (ML-LM-14)
        v.CapValid := '0';

        for i in NumLanes_g-1 downto 0 loop
            if Lane_FarCapabilityValid(i) = '1' and (Bypass_v = '0' or i = 0) then
                v.CapValid := '1';
                v.Cap      := Lane_FarCapability(8*i+7 downto 8*i);
            end if;
        end loop;

        if Active_v = (Active_v'range => '0') then
            v.CapIdle := '1';
        else
            v.CapIdle := '0';
        end if;

        -- Unscramble enable: INIT3DataScrambled of the lane; a receive-only lane enters Active
        -- without INIT3 (ECSS 5.5.2.10e.3) and uses the last capability of any lane (ML-LM-15)
        if v.CapValid = '1' then
            v.FarScr := v.Cap(CapDataScrambled_c);
        end if;

        for i in 0 to NumLanes_g-1 loop
            if Lane_FarCapabilityValid(i) = '1' then
                v.CapSeen(i) := '1';
            end if;
            if Clear_v(i) = '1' then
                v.CapSeen(i) := '0';
            end if;
            if r.CapSeen(i) = '1' then
                Dec_Unscramble(i) <= Lane_FarCapability(8*i+CapDataScrambled_c);
            else
                Dec_Unscramble(i) <= r.FarScr;
            end if;
        end loop;

        -- Outputs
        ResetCond   <= Cond_v;
        Lane_TxOnly <= TxOnly_v;
        Bypass      <= Bypass_v;

        -- Apply to record
        r_next <= v;

    end process;

    -- Lane control
    Lane_Reset          <= ResetCond or r.ResetHold;
    Lane_RxOnly         <= r.RxOnly;
    Lane_FarEndActive   <= r.FarActive;
    Lane_NearCapability <= r.NearCap;

    -- Lane sets
    ActLanes   <= r.Act;
    TxLanes    <= r.Tx;
    DataLanes  <= r.Data;
    HotLanes   <= r.Tx and not r.Data;
    RxLanes    <= r.Rx;
    NumTxLanes <= std_logic_vector(r.NumTx);
    NumRxLanes <= std_logic_vector(r.NumRx);

    -- Data Link layer
    Dl_FarCapability      <= r.Cap;
    Dl_FarCapabilityValid <= r.CapValid;
    Dl_FarCapabilityIdle  <= r.CapIdle;
    Dl_LaneActive         <= '0' when r.Act = (r.Act'range => '0') else '1';

    -- Column codec
    Enc_Scramble <= r.Scramble;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.BypassFar <= '0';
                r.MaxLanes  <= NumLanes_g;
                r.NearCap   <= (others => '0');
                r.Scramble  <= (others => '0');
                r.RxOnly    <= (others => '0');
                r.FarActive <= (others => '0');
                r.ResetHold <= (others => '0');
                r.Act       <= (others => '0');
                r.Tx        <= (others => '0');
                r.Data      <= (others => '0');
                r.Rx        <= (others => '0');
                r.NumTx     <= (others => '0');
                r.NumRx     <= (others => '0');
                r.CapValid  <= '0';
                r.CapIdle   <= '1';
                r.CapSeen   <= (others => '0');
                r.FarScr    <= '0';
            end if;
        end if;
    end process;

end architecture;
