---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Pulse clock domain crossing with single-cycle output pulses, TMR-hardened and free of latches.
-- Per pulse bit a two-phase handshake: the input side toggles a request level, the output side
-- emits one pulse per toggle and returns the level as acknowledge. A pulse that arrives while a
-- transfer is in progress is stored and sent after the acknowledge; further pulses during the
-- same transfer are merged with the stored one. Request, pending and output state registers are
-- triplicated with majority voters, the level crossings use olo_ft_cc_bits, the resets of both
-- sides are coupled by olo_ft_cc_reset.
--
-- Documentation: hdl/ofb_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library olo;
    use olo.olo_base_pkg_attribute.all;
    use olo.olo_ft_pkg_attribute.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_cc_pulse is
    generic (
        NumPulses_g : positive := 1
    );
    port (
        -- Input clock domain
        In_Clk    : in    std_logic;
        In_Rst    : in    std_logic := '0';
        In_Pulse  : in    std_logic_vector(NumPulses_g-1 downto 0);
        -- Output clock domain
        Out_Clk   : in    std_logic;
        Out_Rst   : in    std_logic := '0';
        Out_Pulse : out   std_logic_vector(NumPulses_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_cc_pulse is

    -- One entry per TMR copy
    type Tmr_t is array (0 to 2) of std_logic_vector(NumPulses_g-1 downto 0);

    function vote (
        r : Tmr_t) return std_logic_vector is
    begin
        return (r(0) and r(1)) or (r(1) and r(2)) or (r(0) and r(2));
    end function;

    -- Resets of both sides
    signal RstIn  : std_logic;
    signal RstOut : std_logic;

    -- Input side: request level, pending pulse
    signal ReqR  : Tmr_t := (others => (others => '0'));
    signal PendR : Tmr_t := (others => (others => '0'));
    signal ReqV  : std_logic_vector(NumPulses_g-1 downto 0);
    signal PendV : std_logic_vector(NumPulses_g-1 downto 0);
    signal AckIn : std_logic_vector(NumPulses_g-1 downto 0);
    signal Want  : std_logic_vector(NumPulses_g-1 downto 0);
    signal Fire  : std_logic_vector(NumPulses_g-1 downto 0);

    -- Output side: synchronised request level, level of the previous cycle
    signal ReqOut : std_logic_vector(NumPulses_g-1 downto 0);
    signal LastR  : Tmr_t := (others => (others => '0'));
    signal LastV  : std_logic_vector(NumPulses_g-1 downto 0);

    -- Manual TMR: no vendor TMR insertion, no merging of the copies
    attribute syn_radhardlevel of rtl : architecture is SynRadhardlevel_None_c;

    attribute dont_merge of ReqR  : signal is DontMerge_SuppressChanges_c;
    attribute dont_merge of PendR : signal is DontMerge_SuppressChanges_c;
    attribute dont_merge of LastR : signal is DontMerge_SuppressChanges_c;

    attribute preserve of ReqR  : signal is Preserve_SuppressChanges_c;
    attribute preserve of PendR : signal is Preserve_SuppressChanges_c;
    attribute preserve of LastR : signal is Preserve_SuppressChanges_c;

    attribute syn_preserve of ReqR  : signal is SynPreserve_SuppressChanges_c;
    attribute syn_preserve of PendR : signal is SynPreserve_SuppressChanges_c;
    attribute syn_preserve of LastR : signal is SynPreserve_SuppressChanges_c;

    attribute syn_keep of ReqR  : signal is SynKeep_SuppressChanges_c;
    attribute syn_keep of PendR : signal is SynKeep_SuppressChanges_c;
    attribute syn_keep of LastR : signal is SynKeep_SuppressChanges_c;

    attribute dont_touch of ReqR  : signal is DontTouch_SuppressChanges_c;
    attribute dont_touch of PendR : signal is DontTouch_SuppressChanges_c;
    attribute dont_touch of LastR : signal is DontTouch_SuppressChanges_c;

begin

    i_rst : entity olo.olo_ft_cc_reset
        port map (
            A_Clk    => In_Clk,
            A_RstIn  => In_Rst,
            A_RstOut => RstIn,
            B_Clk    => Out_Clk,
            B_RstIn  => Out_Rst,
            B_RstOut => RstOut
        );

    -----------------------------------------------------------------------------------------------
    -- Input side: a new request toggles the level when no transfer is in progress (level equal to
    -- the acknowledge); otherwise the pulse waits as pending
    -----------------------------------------------------------------------------------------------
    ReqV  <= vote(ReqR);
    PendV <= vote(PendR);
    Want  <= PendV or In_Pulse;
    Fire  <= Want and not (ReqV xor AckIn);

    p_in : process (In_Clk) is
    begin
        if rising_edge(In_Clk) then

            for i in 0 to 2 loop
                ReqR(i)  <= ReqV xor Fire;
                PendR(i) <= Want and not Fire;
            end loop;

            if RstIn = '1' then
                ReqR  <= (others => (others => '0'));
                PendR <= (others => (others => '0'));
            end if;
        end if;
    end process;

    i_req_cc : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => NumPulses_g
        )
        port map (
            In_Clk   => In_Clk,
            In_Rst   => RstIn,
            In_Data  => ReqV,
            Out_Clk  => Out_Clk,
            Out_Rst  => RstOut,
            Out_Data => ReqOut
        );

    -----------------------------------------------------------------------------------------------
    -- Output side: one pulse per change of the synchronised request level, which returns as acknowledge
    -----------------------------------------------------------------------------------------------
    LastV <= vote(LastR);

    p_out : process (Out_Clk) is
    begin
        if rising_edge(Out_Clk) then

            for i in 0 to 2 loop
                LastR(i) <= ReqOut;
            end loop;

            if RstOut = '1' then
                LastR <= (others => (others => '0'));
            end if;
        end if;
    end process;

    Out_Pulse <= (ReqOut xor LastV) when RstOut = '0' else (others => '0');

    i_ack_cc : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => NumPulses_g
        )
        port map (
            In_Clk   => Out_Clk,
            In_Rst   => RstOut,
            In_Data  => ReqOut,
            Out_Clk  => In_Clk,
            Out_Rst  => RstIn,
            Out_Data => AckIn
        );

end architecture;
