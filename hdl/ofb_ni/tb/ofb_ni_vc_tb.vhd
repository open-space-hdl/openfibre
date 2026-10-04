---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the VC port of the Network interface (NI-1): valid words, framing errors with
-- EEP and spill, words of four Fills.
--
-- Documentation: hdl/ofb_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni_vc_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ni_vc_tb is

    constant ClkPeriod_c : time    := 6 ns;
    constant Vvc_c       : natural := 1;

    signal Clk      : std_logic := '0';
    signal Rst      : std_logic := '1';
    signal InData   : Word_t;
    signal InK      : WordK_t;
    signal InValid  : std_logic;
    signal InReady  : std_logic;
    signal OutData  : Word_t;
    signal OutK     : WordK_t;
    signal OutValid : std_logic;
    signal OutReady : std_logic := '1';
    signal FrameErr : std_logic;
    signal ErrCnt   : natural   := 0;

    shared variable OutLog_v : WordLog_t;

    -- Characters
    constant D_c : Char_t := x"5A"; -- data
    constant E_c : Char_t := CharEop_c;
    constant P_c : Char_t := CharEep_c;
    constant F_c : Char_t := CharFill_c;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Words_v : WordArray_t(0 to 15);
        variable Ks_v    : WordKArray_t(0 to 15);
        variable N_v     : natural;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Add a word: four characters, K flag set for EOP, EEP, Fill and the K-code x"FC" (K28.7)
        procedure add (
            c0 : Char_t;
            c1 : Char_t;
            c2 : Char_t;
            c3 : Char_t) is
            variable Chars_v : Word_t;
        begin
            Chars_v      := c3 & c2 & c1 & c0;
            Words_v(N_v) := Chars_v;

            for i in 0 to 3 loop
                if Chars_v(8*i+7 downto 8*i) = D_c or Chars_v(8*i+7 downto 8*i) = x"00" then
                    Ks_v(N_v)(i) := '0';
                else
                    Ks_v(N_v)(i) := '1';
                end if;
            end loop;

            N_v := N_v + 1;
        end procedure;

        procedure send is
        begin
            axistream_transmit(AXISTREAM_VVCT, Vvc_c, toSlvArray(Words_v(0 to N_v-1)), toUserArray(Ks_v(0 to N_v-1)),
                               to_string(N_v) & " words");
            await_completion(AXISTREAM_VVCT, Vvc_c, 10 us, "Words sent");
            cycles(10);
            N_v := 0;
        end procedure;

        procedure expect (
            idx : natural;
            c0  : Char_t;
            c1  : Char_t;
            c2  : Char_t;
            c3  : Char_t;
            k   : WordK_t;
            msg : string) is
        begin
            check_value(OutLog_v.get(idx), k & c3 & c2 & c1 & c0, error, msg);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        N_v := 0;
        cycles(10);
        Rst <= '0';
        cycles(2);

        while test_suite loop

            -- TC-NI-01: valid words pass unchanged, also with back-pressure
            if run("test_valid_words") then
                shared_axistream_vvc_config(Vvc_c).bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(Vvc_c).bfm_config.valid_low_duration    := C_RANDOM;

                for i in 0 to 2 loop
                    add(D_c, D_c, D_c, D_c);
                    add(D_c, E_c, F_c, F_c);
                    add(F_c, F_c, F_c, D_c);
                    add(D_c, D_c, D_c, P_c);
                    add(E_c, F_c, F_c, F_c);
                end loop;

                send;
                check_value(OutLog_v.count, 15, error, "All words passed");
                expect(1, D_c, E_c, F_c, F_c, "1110", "EOP and Fills");
                expect(2, F_c, F_c, F_c, D_c, "0111", "Fills before data");
                expect(3, D_c, D_c, D_c, P_c, "1000", "EEP");
                check_value(ErrCnt, 0, error, "No framing error");

            -- TC-NI-02: framing errors: EEP, Fills, spill of the rest of the packet
            elsif run("test_framing_errors") then
                -- Data after EOP: Fills, the next packet's head is lost, so its rest is discarded
                add(D_c, E_c, D_c, D_c);
                add(D_c, D_c, D_c, D_c);
                add(D_c, E_c, F_c, F_c);
                add(D_c, D_c, E_c, F_c);
                send;
                check_value(OutLog_v.count, 2, error, "Rest of the packet discarded");
                expect(0, D_c, E_c, F_c, F_c, "1110", "Data after EOP replaced by Fills");
                expect(1, D_c, D_c, E_c, F_c, "1100", "Next packet passes");
                check_value(ErrCnt, 1, error, "One framing error");
                -- Second end marker: Fill, no spill (the word ends with a Fill)
                OutLog_v.clear;
                add(D_c, E_c, E_c, F_c);
                add(D_c, D_c, D_c, E_c);
                send;
                expect(0, D_c, E_c, F_c, F_c, "1110", "Second EOP replaced by Fill");
                expect(1, D_c, D_c, D_c, E_c, "1000", "Next word passes");
                check_value(ErrCnt, 2, error, "Second framing error");
                -- Other K-code inside a packet: EEP, rest discarded up to the user's EOP
                OutLog_v.clear;
                add(D_c, x"FC", D_c, D_c);
                add(D_c, D_c, D_c, D_c);
                add(D_c, D_c, E_c, F_c);
                add(D_c, D_c, D_c, E_c);
                send;
                check_value(OutLog_v.count, 2, error, "Packet ended with EEP, rest discarded");
                expect(0, D_c, P_c, F_c, F_c, "1110", "K-code replaced by EEP");
                expect(1, D_c, D_c, D_c, E_c, "1000", "Next packet passes");
                -- Other K-code in a word that ends with the user's EOP: EEP, no spill
                OutLog_v.clear;
                add(x"BC", D_c, D_c, E_c);
                add(D_c, D_c, D_c, E_c);
                send;
                check_value(OutLog_v.count, 2, error, "No spill");
                expect(0, P_c, F_c, F_c, F_c, "1111", "EEP and Fills");
                check_value(ErrCnt, 4, error, "Four framing errors");

            -- TC-NI-03: words of four Fills are dropped
            elsif run("test_fill_words") then
                add(D_c, E_c, F_c, F_c);
                add(F_c, F_c, F_c, F_c);
                add(F_c, F_c, F_c, F_c);
                add(D_c, D_c, D_c, E_c);
                send;
                check_value(OutLog_v.count, 2, error, "Fill words dropped");
                expect(1, D_c, D_c, D_c, E_c, "1000", "Following word passes");
                check_value(ErrCnt, 0, error, "No framing error");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

    -----------------------------------------------------------------------------------------------
    -- Harness
    -----------------------------------------------------------------------------------------------
    i_vvc : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => Vvc_c,
            DataWidth_g   => 32,
            UserWidth_g   => 4
        )
        port map (
            Clk       => Clk,
            Out_Data  => InData,
            Out_User  => InK,
            Out_Keep  => open,
            Out_Last  => open,
            Out_Valid => InValid,
            Out_Ready => InReady
        );

    i_dut : entity work.ofb_ni_vc
        port map (
            Clk         => Clk,
            Rst         => Rst,
            In_Data     => InData,
            In_K        => InK,
            In_Valid    => InValid,
            In_Ready    => InReady,
            Out_Data    => OutData,
            Out_K       => OutK,
            Out_Valid   => OutValid,
            Out_Ready   => OutReady,
            Ev_FrameErr => FrameErr
        );

    p_out : process (Clk) is
        variable Seed1_v : positive := 3;
        variable Seed2_v : positive := 5;
        variable Rand_v  : real;
    begin
        if rising_edge(Clk) then
            if OutValid = '1' and OutReady = '1' then
                OutLog_v.push(OutK & OutData);
            end if;
            if FrameErr = '1' then
                ErrCnt <= ErrCnt + 1;
            end if;
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Rand_v < 0.3 then
                OutReady <= '0';
            else
                OutReady <= '1';
            end if;
        end if;
    end process;

end architecture;
