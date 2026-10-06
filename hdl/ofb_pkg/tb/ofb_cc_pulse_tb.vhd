---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of ofb_cc_pulse: every input pulse gives exactly one single-cycle output pulse within
-- the latency, pending pulses, merging, minimum spacing and reset of either side, for a faster
-- input clock, a faster output clock and nearly equal clocks (VUnit configurations).
--
-- Documentation: hdl/ofb_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_cc_pulse_tb is
    generic (
        runner_cfg    : string;
        InPeriodPs_g  : positive := 6667;
        OutPeriodPs_g : positive := 6400
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_cc_pulse_tb is

    constant InPeriod_c  : time := InPeriodPs_g * 1 ps;
    constant OutPeriod_c : time := OutPeriodPs_g * 1 ps;

    -- Guaranteed minimum spacing and latency (specification PKG-11)
    constant Spacing_c       : time := 5 * InPeriod_c + 5 * OutPeriod_c;
    -- Minimum spacing in input clock cycles
    constant SpacingCycles_c : positive := 5 + (5 * OutPeriodPs_g + InPeriodPs_g - 1) / InPeriodPs_g;
    constant Latency_c       : time     := 3 * InPeriod_c + 4 * OutPeriod_c;

    signal InClk    : std_logic                    := '0';
    signal OutClk   : std_logic                    := '0';
    signal InRst    : std_logic                    := '1';
    signal OutRst   : std_logic                    := '1';
    signal InPulse  : std_logic_vector(1 downto 0) := "00";
    signal OutPulse : std_logic_vector(1 downto 0);

    -- Output monitor
    type Count_t is array (0 to 1) of natural;

    signal OutCount : Count_t := (0, 0);
    signal LastOut  : time    := 0 ns;

begin

    InClk  <= not InClk after InPeriod_c / 2;
    OutClk <= not OutClk after OutPeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk    => InClk,
            In_Rst    => InRst,
            In_Pulse  => InPulse,
            Out_Clk   => OutClk,
            Out_Rst   => OutRst,
            Out_Pulse => OutPulse
        );

    -----------------------------------------------------------------------------------------------
    -- Output monitor: counts the pulses per bit, a pulse lasts one cycle
    -----------------------------------------------------------------------------------------------
    p_monitor : process (OutClk) is
        variable Prev_v : std_logic_vector(1 downto 0) := "00";
    begin
        if rising_edge(OutClk) then

            for b in 0 to 1 loop
                if OutPulse(b) = '1' then
                    OutCount(b) <= OutCount(b) + 1;
                    LastOut     <= now;
                    check_value(Prev_v(b), '0', error, "Output pulse " & to_string(b) & " lasts one cycle");
                end if;
            end loop;

            Prev_v := OutPulse;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Seed1_v : positive := 7;
        variable Seed2_v : positive := 13;
        variable Rand_v  : real;
        variable Exp_v   : Count_t;
        variable Start_v : Count_t;
        variable Sent_v  : time;

        -- Input pulses of the bits in Bits_v, Cycles_v consecutive cycles
        procedure pulse (
            Bits_v   : std_logic_vector(1 downto 0);
            Cycles_v : positive := 1) is
        begin
            wait until rising_edge(InClk);
            InPulse <= Bits_v;

            for c in 2 to Cycles_v loop
                wait until rising_edge(InClk);
            end loop;

            wait until rising_edge(InClk);
            InPulse <= "00";
        end procedure;

        procedure resetBoth is
        begin
            wait until rising_edge(InClk);
            InRst  <= '1';
            OutRst <= '1';
            wait for 10 * (InPeriod_c + OutPeriod_c);
            wait until rising_edge(InClk);
            InRst  <= '0';
            OutRst <= '0';
            -- Release of the coupled resets of both sides
            wait for 10 * (InPeriod_c + OutPeriod_c);
        end procedure;

        procedure checkCount (
            Exp : Count_t;
            Msg : string) is
        begin
            wait for 2 * Spacing_c;
            check_value(OutCount(0), Exp(0), error, Msg & ", bit 0");
            check_value(OutCount(1), Exp(1), error, Msg & ", bit 1");
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        log(ID_LOG_HDR, "Input clock " & to_string(InPeriod_c) & ", output clock " & to_string(OutPeriod_c));
        resetBoth;

        while test_suite loop

            -- TC-PKG-07: single pulses with random spacing of at least the minimum, both bits independent
            if run("test_single_pulses") then
                Start_v := OutCount;
                Exp_v   := OutCount;

                for i in 1 to 200 loop
                    uniform(Seed1_v, Seed2_v, Rand_v);

                    if Rand_v < 0.4 then
                        pulse("01");
                        Exp_v(0) := Exp_v(0) + 1;
                    elsif Rand_v < 0.8 then
                        pulse("10");
                        Exp_v(1) := Exp_v(1) + 1;
                    else
                        pulse("11");
                        Exp_v(0) := Exp_v(0) + 1;
                        Exp_v(1) := Exp_v(1) + 1;
                    end if;

                    Sent_v := now;
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    wait for Spacing_c + Rand_v * Spacing_c;

                    -- Every pulse is out within the latency
                    check_value(LastOut > Sent_v - InPeriod_c and LastOut <= Sent_v + Latency_c, error,
                                "Output pulse within the latency");
                end loop;

                checkCount(Exp_v, "One output pulse per input pulse");
                check_value(OutCount(0) - Start_v(0) > 50 and OutCount(1) - Start_v(1) > 50, error,
                            "Both bits exercised");

            -- TC-PKG-08: pulses at exactly the minimum spacing
            elsif run("test_min_spacing") then
                Exp_v := OutCount;

                for i in 1 to 100 loop
                    wait until rising_edge(InClk);
                    InPulse <= "11";
                    wait until rising_edge(InClk);
                    InPulse <= "00";

                    for c in 3 to SpacingCycles_c loop
                        wait until rising_edge(InClk);
                    end loop;

                end loop;

                Exp_v(0) := Exp_v(0) + 100;
                Exp_v(1) := Exp_v(1) + 100;
                checkCount(Exp_v, "No pulse lost at the minimum spacing");

            -- TC-PKG-09: a pulse during a transfer is pending and follows, further pulses merge with it
            elsif run("test_pending") then
                Exp_v    := OutCount;
                pulse("01", 2);
                Exp_v(0) := Exp_v(0) + 2;
                checkCount(Exp_v, "Two consecutive pulses give two output pulses");

                pulse("10", 2);
                wait for 2 * InPeriod_c;
                pulse("10");
                Exp_v(1) := Exp_v(1) + 2;
                checkCount(Exp_v, "Pulse pending during a transfer is sent afterwards");

                pulse("11", 5);
                Exp_v(0) := Exp_v(0) + 2;
                Exp_v(1) := Exp_v(1) + 2;
                checkCount(Exp_v, "Five consecutive pulses give two output pulses (merged)");

            -- TC-PKG-10: reset of either side, during a transfer and idle
            elsif run("test_reset") then
                -- Reset while idle: no output pulse
                Exp_v := OutCount;
                resetBoth;
                checkCount(Exp_v, "No output pulse from a reset");

                -- Reset of the input side during a transfer: at most one output pulse, none after the reset
                Start_v := OutCount;
                pulse("11");
                wait for InPeriod_c;
                wait until rising_edge(InClk);
                InRst   <= '1';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                Exp_v   := OutCount;
                check_value(Exp_v(0) - Start_v(0) <= 1 and Exp_v(1) - Start_v(1) <= 1, error,
                            "At most one output pulse per input pulse at the input reset");
                wait until rising_edge(InClk);
                InRst   <= '0';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                checkCount(Exp_v, "No output pulse during and after the input reset");

                -- Reset of the output side during a transfer
                Start_v := OutCount;
                pulse("11");
                wait for InPeriod_c;
                wait until rising_edge(OutClk);
                OutRst  <= '1';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                Exp_v   := OutCount;
                check_value(Exp_v(0) - Start_v(0) <= 1 and Exp_v(1) - Start_v(1) <= 1, error,
                            "At most one output pulse per input pulse at the output reset");
                wait until rising_edge(OutClk);
                OutRst  <= '0';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                checkCount(Exp_v, "No output pulse during and after the output reset");

                -- Pending pulse at a reset is dropped
                pulse("11", 2);
                wait until rising_edge(InClk);
                InRst <= '1';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                Exp_v := OutCount;
                wait until rising_edge(InClk);
                InRst <= '0';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                checkCount(Exp_v, "Pending pulse dropped by the reset");

                -- Operation after the resets
                pulse("11");
                Exp_v(0) := Exp_v(0) + 1;
                Exp_v(1) := Exp_v(1) + 1;
                checkCount(Exp_v, "Pulse after the resets");

                -- Pulse while the input side is in reset: dropped
                wait until rising_edge(InClk);
                InRst   <= '1';
                InPulse <= "11";
                wait until rising_edge(InClk);
                InPulse <= "00";
                wait for 10 * (InPeriod_c + OutPeriod_c);
                wait until rising_edge(InClk);
                InRst   <= '0';
                wait for 10 * (InPeriod_c + OutPeriod_c);
                checkCount(Exp_v, "Pulse during the reset dropped");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 10 ms);

end architecture;
