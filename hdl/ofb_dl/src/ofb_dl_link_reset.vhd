---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Link reset state machine of the Data Link layer (DC-1, ECSS 5.7.9): resets both ends of the link
-- when one end is reset. The far-end capability is used as an event, not as a stored level.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.11)

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
entity ofb_dl_link_reset is
    port (
        -- Control Ports
        Clk                   : in    std_logic;
        Rst                   : in    std_logic; -- Power-on reset
        -- Commands and errors
        Cfg_InterfaceReset    : in    std_logic; -- Interface Reset management parameter (pulse)
        Cfg_LinkReset         : in    std_logic; -- Link Reset management parameter (pulse)
        Err_LinkReset         : in    std_logic; -- Protocol error or input buffer overflow (pulse)
        -- Far-end capability event and lane state
        Ml_FarCapability      : in    Char_t;
        Ml_FarCapabilityValid : in    std_logic;
        Ml_LaneActive         : in    std_logic;
        -- Outputs
        Ctrl_LinkReset        : out   std_logic; -- One cycle
        Ctrl_LaneReset        : out   std_logic; -- One cycle
        Ctrl_ConfigReset      : out   std_logic; -- One cycle: reset of the configuration parameters
        Ctrl_LinkResetFlag    : out   std_logic; -- INIT3LinkResetFlag of the near-end capability
        Ev_FarEndLinkReset    : out   std_logic;
        -- 0 ConfigReset, 1 NearEndReset, 2 CheckFarEnd, 3 LinkInit
        Stat_State            : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_link_reset is

    type LinkResetFsm_t is (ConfigReset_s, NearEndReset_s, CheckFarEnd_s, LinkInit_s);

    signal State    : LinkResetFsm_t;
    signal FarReset : std_logic;
    signal FarEv    : std_logic;

begin

    FarReset <= Ml_FarCapabilityValid and Ml_FarCapability(CapLinkReset_c);

    p_fsm : process (Clk) is
    begin
        if rising_edge(Clk) then
            FarEv <= '0';

            case State is
                when ConfigReset_s =>
                    State <= NearEndReset_s;
                when NearEndReset_s =>
                    if Cfg_InterfaceReset = '1' then
                        State <= ConfigReset_s;
                    else
                        State <= CheckFarEnd_s;
                    end if;
                when CheckFarEnd_s =>
                    if Cfg_InterfaceReset = '1' then
                        State <= ConfigReset_s;
                    elsif Cfg_LinkReset = '1' or Err_LinkReset = '1' then
                        State <= NearEndReset_s;
                    elsif FarReset = '1' then
                        State <= LinkInit_s;
                    end if;
                when LinkInit_s =>
                    if Cfg_InterfaceReset = '1' then
                        State <= ConfigReset_s;
                    elsif Cfg_LinkReset = '1' or Err_LinkReset = '1' then
                        State <= NearEndReset_s;
                    elsif FarReset = '1' and Ml_LaneActive = '0' then
                        State <= NearEndReset_s;
                        FarEv <= '1';
                    end if;
                -- coverage off
                when others =>
                    State <= ConfigReset_s;
                -- coverage on
            end case;

            if Rst = '1' then
                State <= ConfigReset_s;
                FarEv <= '0';
            end if;
        end if;
    end process;

    Ctrl_LinkReset     <= '1' when State = ConfigReset_s or State = NearEndReset_s else '0';
    Ctrl_LaneReset     <= '1' when State = ConfigReset_s or State = NearEndReset_s else '0';
    Ctrl_ConfigReset   <= '1' when State = ConfigReset_s else '0';
    Ctrl_LinkResetFlag <= '0' when State = LinkInit_s else '1';
    Ev_FarEndLinkReset <= FarEv;

    with State select Stat_State <=
         "00" when ConfigReset_s,
         "01" when NearEndReset_s,
         "10" when CheckFarEnd_s,
         "11" when others;

end architecture;
