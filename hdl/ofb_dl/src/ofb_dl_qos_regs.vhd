---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Configuration registers of the quality of service and the continuous mode per VC in the core
-- clock domain. They are written by the MIB through its register write channel (the MIB keeps a
-- copy for reading) and take their reset values on reset and on Interface Reset (ECSS 5.7.4.5q, r,
-- 5.7.4.6h, Table 5-36).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.12)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_qos_regs is
    generic (
        NumVc_g   : positive range 1 to 32 := 8;
        NumPrio_g : positive range 2 to 16 := 4
    );
    port (
        -- Control Ports
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        Ctrl_ConfigReset : in    std_logic;
        -- Register writes from the MIB
        Reg_Wr           : in    std_logic;
        Reg_Addr         : in    std_logic_vector(11 downto 0);
        Reg_Data         : in    std_logic_vector(31 downto 0);
        -- Configuration
        Cfg_Priority     : out   std_logic_vector(4*NumVc_g-1 downto 0);
        Cfg_BwFactor     : out   std_logic_vector(16*NumVc_g-1 downto 0);
        Cfg_Slots        : out   std_logic_vector(64*NumVc_g-1 downto 0);
        Cfg_Continuous   : out   std_logic_vector(NumVc_g-1 downto 0);
        Cfg_IdleLimit    : out   std_logic_vector(31 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_qos_regs is

    constant AddrIdle_c   : natural := 16#050#;
    constant AddrVcBase_c : natural := 16#400#;

    -- Reset values: lowest priority, 10 % for VC0, minimum bandwidth for the others, all slots
    constant IdleReset_c : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(156250, 32));

begin

    p_regs : process (Clk) is
        variable Addr_v : natural;
        variable Vc_v   : natural;
        variable Reg_v  : natural;
    begin
        if rising_edge(Clk) then
            Addr_v := to_integer(unsigned(Reg_Addr));
            Vc_v   := (Addr_v / 16) mod 32;
            Reg_v  := Addr_v mod 16;
            if Reg_Wr = '1' then
                if Addr_v = AddrIdle_c then
                    Cfg_IdleLimit <= Reg_Data;
                elsif Addr_v >= AddrVcBase_c and Addr_v < AddrVcBase_c + 16 * NumVc_g then

                    case Reg_v is
                        when 0 =>
                            Cfg_Priority(4*Vc_v+3 downto 4*Vc_v) <= Reg_Data(3 downto 0);
                            Cfg_Continuous(Vc_v)                 <= Reg_Data(8);
                        when 4 =>
                            Cfg_BwFactor(16*Vc_v+15 downto 16*Vc_v) <= Reg_Data(15 downto 0);
                        when 8 =>
                            Cfg_Slots(64*Vc_v+31 downto 64*Vc_v) <= Reg_Data;
                        when 12 =>
                            Cfg_Slots(64*Vc_v+63 downto 64*Vc_v+32) <= Reg_Data;
                        when others =>
                            null;
                    end case;

                end if;
            end if;
            if Rst = '1' or Ctrl_ConfigReset = '1' then
                Cfg_IdleLimit  <= IdleReset_c;
                Cfg_Slots      <= (others => '1');
                Cfg_Continuous <= (others => '0');

                for c in 0 to NumVc_g-1 loop
                    Cfg_Priority(4*c+3 downto 4*c) <= std_logic_vector(to_unsigned(NumPrio_g - 1, 4));
                    if c = 0 then
                        Cfg_BwFactor(15 downto 0) <= x"0A00";
                    else
                        Cfg_BwFactor(16*c+15 downto 16*c) <= x"FFFF";
                    end if;
                end loop;

            end if;
        end if;
    end process;

end architecture;
