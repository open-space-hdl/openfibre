---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of ofb_lane_rx: clock, reset, the DUT and a monitor that logs the output words and
-- counts the events.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_rx_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_rx_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_rx_th is

    constant ClkPeriod_c : time := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    signal OutData      : Word_t;
    signal OutK         : WordK_t;
    signal OutValid     : std_logic;
    signal EvWord       : std_logic;
    signal EvRxErr      : std_logic;
    signal EvInit1      : std_logic;
    signal EvInit2      : std_logic;
    signal EvInvInit1   : std_logic;
    signal EvInvInit2   : std_logic;
    signal EvInit3      : std_logic;
    signal EvStandby    : std_logic;
    signal EvLostSignal : std_logic;
    signal EvComma      : std_logic;
    signal EvSkip       : std_logic;
    signal EvParam      : Char_t;
    signal ErrCount     : Char_t;
    signal Overflow     : std_logic;
    signal EvOverflow   : std_logic;

begin

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 10 * ClkPeriod_c;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    i_dut : entity work.ofb_lane_rx
        generic map (
            RxErrLeakWords_g => TbRxErrLeakWords_c
        )
        port map (
            Clk                => ClkI,
            Rst                => RstI,
            Ctrl_SyncReset     => RxIn.SyncReset,
            Ctrl_Active        => RxIn.Active,
            Ctrl_RxErrClear    => RxIn.ErrClear,
            In_Data            => RxIn.Data,
            In_K               => RxIn.K,
            In_CodeErr         => RxIn.CodeErr,
            In_DispErr         => RxIn.DispErr,
            In_Valid           => RxIn.Valid,
            Out_Data           => OutData,
            Out_K              => OutK,
            Out_Valid          => OutValid,
            Ev_Word            => EvWord,
            Ev_RxErr           => EvRxErr,
            Ev_Init1           => EvInit1,
            Ev_Init2           => EvInit2,
            Ev_InvInit1        => EvInvInit1,
            Ev_InvInit2        => EvInvInit2,
            Ev_Init3           => EvInit3,
            Ev_Standby         => EvStandby,
            Ev_LostSignal      => EvLostSignal,
            Ev_Comma           => EvComma,
            Ev_Skip            => EvSkip,
            Ev_Param           => EvParam,
            Stat_RxErrCount    => ErrCount,
            Stat_RxErrOverflow => Overflow,
            Ev_RxErrOverflow   => EvOverflow
        );

    p_monitor : process (ClkI) is
        variable Stat_v : RxStat_t := (Words => 0, RxErrs => 0, Init1 => 0, Init2 => 0, InvInit1 => 0,
                                        InvInit2 => 0, Init3 => 0, Standby => 0, LostSignal => 0, Comma => 0,
                                       Skip => 0, LastParam => x"00", ErrCount => x"00", Overflow => '0',
                                       OverflowEv => 0);

        procedure count (
            ev  : std_logic;
            cnt : inout natural) is
        begin
            if ev = '1' then
                cnt := cnt + 1;
            end if;
        end procedure;

    -- Log and count
    begin
        if rising_edge(ClkI) then
            if OutValid = '1' then
                OutLog_v.push(OutK & OutData);
            end if;
            count(EvWord, Stat_v.Words);
            count(EvRxErr, Stat_v.RxErrs);
            count(EvInit1, Stat_v.Init1);
            count(EvInit2, Stat_v.Init2);
            count(EvInvInit1, Stat_v.InvInit1);
            count(EvInvInit2, Stat_v.InvInit2);
            count(EvInit3, Stat_v.Init3);
            count(EvStandby, Stat_v.Standby);
            count(EvLostSignal, Stat_v.LostSignal);
            count(EvComma, Stat_v.Comma);
            count(EvSkip, Stat_v.Skip);
            count(EvOverflow, Stat_v.OverflowEv);
            if (EvInit3 or EvStandby or EvLostSignal) = '1' then
                Stat_v.LastParam := EvParam;
            end if;
            Stat_v.ErrCount := ErrCount;
            Stat_v.Overflow := Overflow;
            RxStat          <= Stat_v;
        end if;
    end process;

end architecture;
