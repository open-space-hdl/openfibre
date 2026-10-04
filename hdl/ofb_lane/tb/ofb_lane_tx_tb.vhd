---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the lane transmitter (LN-2): INIT words with PRBS data words, INIT3, Active
-- with SKIP and IDLE, STANDBY and LOST_SIGNAL.
--
-- Documentation: hdl/ofb_lane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

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
    use work.ofb_lane_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_lane_tx_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_tx_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_lane_tx_tb is

    signal Clk : std_logic;
    signal Rst : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable State_v    : std_logic_vector(15 downto 0);
        variable Words_v    : WordArray_t(0 to 199);
        variable Ks_v       : WordKArray_t(0 to 199);
        variable Got_v      : KWord_t;
        variable Next_v     : natural;
        variable LastSkip_v : integer;
        variable Skips_v    : natural;

        -- Wait for n clock cycles
        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- Set the mode of a DUT and log its words from the first word of the new mode on
        procedure setMode (
            dut  : natural;
            mode : TxMode_t) is
        begin
            TxCtrl(dut).Mode      <= mode;
            cycles(1);
            TxCtrl(dut).LogEnable <= true;
        end procedure;

        procedure checkWord (
            dut      : natural;
            idx      : natural;
            expected : Word_t;
            k        : WordK_t;
            msg      : string) is
            variable Got_v : KWord_t;
        begin
            if dut = 0 then
                Got_v := TxLog0_v.get(idx);
            else
                Got_v := TxLog1_v.get(idx);
            end if;
            check_value(Got_v, k & expected, error, msg & " (word " & to_string(idx) & ")");
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        wait until Rst = '0';
        cycles(2);

        while test_suite loop

            -- TC-LN-50: INIT1 followed by 64 PRBS words; a mode change starts with the new INIT word
            if run("test_init_prbs") then
                setMode(0, TxModeInit1_c);
                cycles(2 * (TbPrbsWords_c + 1) + 10);
                State_v := PrbsEcssSeed_c;

                for rep in 0 to 1 loop
                    checkWord(0, rep * (TbPrbsWords_c + 1), WordInit1_c, KCtrl_c, "INIT1");

                    for i in 1 to TbPrbsWords_c loop
                        checkWord(0, rep * (TbPrbsWords_c + 1) + i, prbsWord(State_v), KData_c, "PRBS word");
                        State_v := prbsNextState(State_v);
                    end loop;

                end loop;

                -- Mode change in the middle of the PRBS words
                TxCtrl(0).LogEnable <= false;
                cycles(1);
                TxLog0_v.clear;
                setMode(0, TxModeInit2_c);
                cycles(5);
                checkWord(0, 0, WordInit2_c, KCtrl_c, "INIT2 right after the mode change");
                Got_v               := TxLog0_v.get(1);
                check_value(Got_v(35 downto 32), KData_c, error, "PRBS data word after INIT2");

            -- TC-LN-51: without PRBS words only INIT words; INIT3 with capability and events
            elsif run("test_init_words") then
                setMode(1, TxModeInit1_c);
                cycles(10);

                for i in 0 to 9 loop
                    checkWord(1, i, WordInit1_c, KCtrl_c, "INIT1 only");
                end loop;

                TxCtrl(1).LogEnable <= false;
                TxCtrl(1).Cap       <= x"5A";
                cycles(1);
                TxLog1_v.clear;
                setMode(1, TxModeInit3_c);
                cycles(10);

                for i in 0 to 9 loop
                    checkWord(1, i, wordInit3(x"5A"), KCtrl_c, "INIT3 with capability");
                end loop;

                check_value(TxStat(1).Init3Sent >= 10, error, "INIT3 sent events");

            -- TC-LN-52: Active: words of the Multi-Lane layer, IDLE when none, SKIP every 20 words
            elsif run("test_active") then

                for i in Words_v'range loop
                    Words_v(i) := std_logic_vector(to_unsigned(i * 7919 + 13, 32));
                    Ks_v(i)    := KData_c;
                end loop;

                shared_axistream_vvc_config(VvcIn_c).bfm_config.valid_low_at_word_num := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcIn_c).bfm_config.valid_low_duration    := C_RANDOM;
                setMode(0, TxModeActive_c);
                axistream_transmit(AXISTREAM_VVCT, VvcIn_c, toSlvArray(Words_v), toUserArray(Ks_v), "200 words");
                await_completion(AXISTREAM_VVCT, VvcIn_c, 100 us, "Words sent");
                cycles(5);
                Next_v                                                                := 0;
                LastSkip_v                                                            := -1;
                Skips_v                                                               := 0;

                for i in 0 to TxLog0_v.count - 1 loop
                    Got_v := TxLog0_v.get(i);
                    if Got_v = KCtrl_c & WordSkip_c then
                        if LastSkip_v >= 0 then
                            check_value(i - LastSkip_v, TbSkipInterval_c, error, "SKIP interval");
                        end if;
                        LastSkip_v := i;
                        Skips_v    := Skips_v + 1;
                    elsif Got_v /= KCtrl_c & WordIdle_c then
                        if Next_v <= Words_v'high then
                            check_value(Got_v, Ks_v(Next_v) & Words_v(Next_v), error,
                                        "Word " & to_string(Next_v) & " in order");
                        end if;
                        Next_v := Next_v + 1;
                    end if;
                end loop;

                check_value(Next_v, Words_v'length, error, "All words sent, none duplicated");
                check_value(Skips_v >= 10, error, "SKIP words inserted");

            -- TC-LN-53: STANDBY with the Standby Reason, LOST_SIGNAL with the LOS_Cause, events
            elsif run("test_standby_lost_signal") then
                TxCtrl(1).Reason <= x"37";
                setMode(1, TxModeStandby_c);
                cycles(32);

                for i in 0 to 31 loop
                    checkWord(1, i, wordStandby(x"37"), KCtrl_c, "STANDBY");
                end loop;

                check_value(TxStat(1).StandbySent >= 32, error, "STANDBY sent events");
                TxCtrl(1).LogEnable <= false;
                TxCtrl(1).LosCause  <= LosCauseInit1_c;
                cycles(1);
                TxLog1_v.clear;
                setMode(1, TxModeLostSignal_c);
                cycles(32);

                for i in 0 to 31 loop
                    checkWord(1, i, wordLostSignal(LosCauseInit1_c), KCtrl_c, "LOST_SIGNAL");
                end loop;

                check_value(TxStat(1).LostSent >= 32, error, "LOST_SIGNAL sent events");
                -- Off: IDLE words
                TxCtrl(1).LogEnable <= false;
                cycles(1);
                TxLog1_v.clear;
                setMode(1, TxModeOff_c);
                cycles(4);
                checkWord(1, 0, WordIdle_c, KCtrl_c, "IDLE when the transmitter is off");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 1 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_lane_tx_th
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
