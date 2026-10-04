---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Medium access controller of the Data Link layer (DT-4, ECSS 5.7.4): priority, bandwidth
-- reservation and scheduled quality of service. Selects the VC that sends the next data segment
-- by its precedence = priority precedence + bandwidth credit, among the VCs that have a segment
-- ready, are allocated to the current time-slot and have a bandwidth.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.12)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_mac is
    generic (
        NumVc_g       : positive range 1 to 32 := 8;
        NumPrio_g     : positive range 2 to 16 := 4;
        CreditLimit_g : positive               := 16384 -- Bandwidth Credit Limit B in words
    );
    port (
        -- Control Ports
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        Ctrl_ConfigReset : in    std_logic; -- Interface Reset: credits cleared
        -- Configuration per VC
        Cfg_Priority     : in    std_logic_vector(4*NumVc_g-1 downto 0);
        Cfg_BwFactor     : in    std_logic_vector(16*NumVc_g-1 downto 0); -- 1 / bandwidth, 8.8 fixed point
        Cfg_Slots        : in    std_logic_vector(64*NumVc_g-1 downto 0);
        Cfg_IdleLimit    : in    std_logic_vector(31 downto 0);           -- Words
        -- Current time-slot
        TimeSlot         : in    std_logic_vector(5 downto 0);
        -- Segments ready, selection
        Seg_Ready        : in    std_logic_vector(NumVc_g-1 downto 0);
        Grant            : out   std_logic_vector(NumVc_g-1 downto 0);
        Grant_Valid      : out   std_logic;
        -- Accounting: words sent on the link, segments admitted (data words of the segment)
        Ev_WordSent      : in    std_logic;
        Ev_SegSent       : in    std_logic;
        SegSent_Vc       : in    std_logic_vector(4 downto 0);
        SegSent_Words    : in    std_logic_vector(6 downto 0);
        -- Status levels per VC
        Stat_BwOver      : out   std_logic_vector(NumVc_g-1 downto 0);
        Stat_BwUnder     : out   std_logic_vector(NumVc_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_mac is

    constant FracBits_c   : natural                      := 8;
    constant CreditW_c    : positive                     := log2ceil(CreditLimit_g) + FracBits_c + 2;
    constant PrecW_c      : positive                     := log2ceil(2 * CreditLimit_g * NumPrio_g + 1) + 2;
    constant Limit_c      : signed(CreditW_c-1 downto 0) := to_signed(CreditLimit_g * 2**FracBits_c, CreditW_c);
    constant Threshold_c  : signed(CreditW_c-1 downto 0) := to_signed(-(CreditLimit_g * 9 / 10) * 2**FracBits_c, CreditW_c);
    constant UpdateIdle_c : natural                      := 66; -- Words of a full data frame

    -- Reduction tree of the selection (padded to 32 entries)
    constant Entries_c : positive := 32;

    type CreditArray_t is array (0 to NumVc_g-1) of signed(CreditW_c-1 downto 0);
    type PrecArray_t is array (0 to Entries_c-1) of signed(PrecW_c-1 downto 0);
    type IdleArray_t is array (0 to NumVc_g-1) of unsigned(31 downto 0);

    signal Credit   : CreditArray_t;
    signal Avail    : unsigned(15 downto 0);
    signal Prec     : PrecArray_t;
    signal Eligible : std_logic_vector(Entries_c-1 downto 0);
    signal IdleCnt  : IdleArray_t;

begin

    -----------------------------------------------------------------------------------------------
    -- Bandwidth credit (ECSS 5.7.4.5)
    -----------------------------------------------------------------------------------------------
    p_credit : process (Clk) is
        variable Avail_v  : unsigned(15 downto 0);
        variable Update_v : boolean;
        variable Sum_v    : signed(CreditW_c+16 downto 0);
        variable Cost_v   : unsigned(22 downto 0);
        variable Vc_v     : natural range 0 to 31;
    begin
        if rising_edge(Clk) then
            Avail_v := Avail;
            if Ev_WordSent = '1' and Avail /= x"FFFF" then
                Avail_v := Avail + 1;
            end if;
            Update_v := Ev_SegSent = '1' or Avail_v >= UpdateIdle_c;
            Vc_v     := to_integer(unsigned(SegSent_Vc));

            if Update_v then

                for c in 0 to NumVc_g-1 loop
                    -- + available bandwidth (all VCs), - used bandwidth / expected bandwidth (sending VC)
                    Sum_v := resize(Credit(c), Sum_v'length) + signed(resize(shift_left(resize(Avail_v, 24), FracBits_c),
                                                                             Sum_v'length));
                    if Ev_SegSent = '1' and Vc_v = c then
                        Cost_v := resize(unsigned(SegSent_Words) + 2, 7) * unsigned(Cfg_BwFactor(16*c+15 downto 16*c));
                        Sum_v  := Sum_v - signed(resize(Cost_v, Sum_v'length));
                    end if;
                    if Sum_v > resize(Limit_c, Sum_v'length) then
                        Sum_v := resize(Limit_c, Sum_v'length);
                    elsif Sum_v < -resize(Limit_c, Sum_v'length) then
                        Sum_v := -resize(Limit_c, Sum_v'length);
                    end if;
                    Credit(c) <= resize(Sum_v, CreditW_c);
                end loop;

                Avail <= (others => '0');
            else
                Avail <= Avail_v;
            end if;

            -- Under use: credit at the limit for the idle time limit
            for c in 0 to NumVc_g-1 loop
                if Credit(c) = Limit_c then
                    if Ev_WordSent = '1' and IdleCnt(c) /= x"FFFFFFFF" then
                        IdleCnt(c) <= IdleCnt(c) + 1;
                    end if;
                else
                    IdleCnt(c) <= (others => '0');
                end if;
            end loop;

            if Rst = '1' or Ctrl_ConfigReset = '1' then
                Credit  <= (others => (others => '0'));
                Avail   <= (others => '0');
                IdleCnt <= (others => (others => '0'));
            end if;
        end if;
    end process;

    g_stat : for c in 0 to NumVc_g-1 generate
        Stat_BwOver(c)  <= '1' when Credit(c) <= Threshold_c else '0';
        Stat_BwUnder(c) <= '1' when IdleCnt(c) >= unsigned(Cfg_IdleLimit) else '0';
    end generate;

    -----------------------------------------------------------------------------------------------
    -- Precedence (ECSS 5.7.4.4, 5.7.4.6), registered
    -----------------------------------------------------------------------------------------------
    p_prec : process (Clk) is
        variable Prio_v : natural;
        variable Base_v : integer;
        variable Slot_v : natural range 0 to 63;
        variable Cred_v : integer;
    begin
        if rising_edge(Clk) then
            Slot_v   := to_integer(unsigned(TimeSlot));
            Eligible <= (others => '0');
            Prec     <= (others => (others => '0'));

            for c in 0 to NumVc_g-1 loop
                Prio_v := minimum(to_integer(unsigned(Cfg_Priority(4*c+3 downto 4*c))), NumPrio_g - 1);
                Cred_v := to_integer(shift_right(Credit(c), FracBits_c));
                if Credit(c) < Threshold_c then
                    Base_v := 0;
                else
                    Base_v := 2 * CreditLimit_g * (NumPrio_g - 1 - Prio_v) + CreditLimit_g;
                end if;
                Prec(c) <= to_signed(Base_v + Cred_v, PrecW_c);
                if Seg_Ready(c) = '1' and Cfg_Slots(64*c+Slot_v) = '1' and unsigned(Cfg_BwFactor(16*c+15 downto 16*c)) /= 0 then
                    Eligible(c) <= '1';
                end if;
            end loop;

            if Rst = '1' then
                Eligible <= (others => '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Selection of the highest precedence (lowest VC on equal precedence), registered
    -----------------------------------------------------------------------------------------------
    p_select : process (Clk) is
        variable Val_v : PrecArray_t;
        variable Idx_v : integer_vector(0 to Entries_c-1);
        variable Vld_v : std_logic_vector(0 to Entries_c-1);
    begin
        if rising_edge(Clk) then

            for i in 0 to Entries_c-1 loop
                Val_v(i) := Prec(i);
                Idx_v(i) := i;
                Vld_v(i) := Eligible(i);
            end loop;

            -- Five levels of pairwise comparison
            for lvl in 1 to 5 loop

                for i in 0 to Entries_c / 2**lvl - 1 loop
                    if Vld_v(2*i+1) = '1' and (Vld_v(2*i) = '0' or Val_v(2*i+1) > Val_v(2*i)) then
                        Val_v(i) := Val_v(2*i+1);
                        Idx_v(i) := Idx_v(2*i+1);
                        Vld_v(i) := '1';
                    else
                        Val_v(i) := Val_v(2*i);
                        Idx_v(i) := Idx_v(2*i);
                        Vld_v(i) := Vld_v(2*i);
                    end if;
                end loop;

            end loop;

            Grant       <= (others => '0');
            Grant_Valid <= Vld_v(0);
            if Vld_v(0) = '1' and Idx_v(0) < NumVc_g then
                Grant(Idx_v(0)) <= '1';
            end if;
            if Rst = '1' then
                Grant_Valid <= '0';
            end if;
        end if;
    end process;

end architecture;
