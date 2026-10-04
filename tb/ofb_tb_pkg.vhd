---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenFibre testbenches (VUnit runner plus UVVM).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_tb_pkg is

    -- AXI-Stream BFM configuration of the OpenFibre testbenches: element bits map 1:1 to TDATA
    -- (LOWER_BYTE_RIGHT) and the timeouts suit protocol latencies.
    constant OfbAxisBfmConfig_c : t_axistream_bfm_config := (
        max_wait_cycles                => 100000,
        max_wait_cycles_severity       => error,
        clock_period                   => C_UNDEFINED_TIME,
        clock_period_margin            => 0 ns,
        clock_margin_severity          => TB_ERROR,
        setup_time                     => C_UNDEFINED_TIME,
        hold_time                      => C_UNDEFINED_TIME,
        bfm_sync                       => SYNC_ON_CLOCK_ONLY,
        match_strictness               => MATCH_EXACT,
        byte_endianness                => LOWER_BYTE_RIGHT,
        valid_low_at_word_num          => 0,
        valid_low_multiple_random_prob => 0.5,
        valid_low_duration             => 0,
        valid_low_max_random_duration  => 5,
        check_packet_length            => false,
        protocol_error_severity        => error,
        ready_low_at_word_num          => 0,
        ready_low_multiple_random_prob => 0.5,
        ready_low_duration             => 0,
        ready_low_max_random_duration  => 5,
        ready_default_value            => '0',
        id_for_bfm                     => ID_BFM
    );

    -- Array of words with their K flags
    type WordArray_t is array (natural range <>) of Word_t;
    type WordKArray_t is array (natural range <>) of WordK_t;

    -- Word with K flags in bits 35:32 and a log of such words (monitors push, test sequencers read)
    subtype KWord_t is std_logic_vector(35 downto 0);

    type WordLog_t is protected

        procedure push (word : KWord_t);

        procedure clear;
        impure function count return natural;
        impure function get (idx : natural) return KWord_t;
    end protected;

    -- Queue of words with K flags and one flag bit (bit 36)
    type WordQueue_t is protected

        procedure push (word : std_logic_vector(36 downto 0));

        impure function pop return std_logic_vector;
        impure function count return natural;

        procedure clear;
    end protected;

    -- Ends a test: prints the UVVM alert summary, raises a TB_ERROR when an unexpected alert occurred
    -- or an expected alert did not occur (this stops the simulation and fails the VUnit test) and
    -- hands over to the VUnit runner.
    procedure ofbTestEnd (signal runner : inout runner_sync_t);

    -- Conversion of word arrays for the AXI-Stream VVC procedures
    function toSlvArray (words : in WordArray_t) return t_slv_array;

    function toUserArray (kflags : in WordKArray_t) return t_user_array;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_tb_pkg is

    type WordLog_t is protected body

        type KWordArray_t is array (0 to 16383) of KWord_t;

        variable Words_v : KWordArray_t;
        variable Count_v : natural := 0;

        procedure push (word : KWord_t) is
        begin
            if Count_v <= KWordArray_t'high then
                Words_v(Count_v) := word;
            end if;
            Count_v := Count_v + 1;
        end procedure;

        procedure clear is
        begin
            Count_v := 0;
        end procedure;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        impure function get (idx : natural) return KWord_t is
        begin
            return Words_v(idx);
        end function;

    end protected body;

    type WordQueue_t is protected body

        type Entries_t is array (0 to 16383) of std_logic_vector(36 downto 0);

        variable Entries_v : Entries_t;
        variable Head_v    : natural := 0;
        variable Count_v   : natural := 0;

        procedure push (word : std_logic_vector(36 downto 0)) is
        begin
            assert Count_v <= Entries_t'high
                report "WordQueue_t full"
                severity failure;
            Entries_v((Head_v + Count_v) mod Entries_v'length) := word;
            Count_v                                            := Count_v + 1;
        end procedure;

        impure function pop return std_logic_vector is
            variable Word_v : std_logic_vector(36 downto 0);
        begin
            Word_v  := Entries_v(Head_v);
            Head_v  := (Head_v + 1) mod Entries_v'length;
            Count_v := Count_v - 1;
            return Word_v;
        end function;

        impure function count return natural is
        begin
            return Count_v;
        end function;

        procedure clear is
        begin
            Count_v := 0;
        end procedure;

    end protected body;

    procedure ofbTestEnd (signal runner : inout runner_sync_t) is
    begin
        report_alert_counters(FINAL);
        if shared_uvvm_status.mismatch_on_expected_simulation_warnings_or_worse /= 0 then
            alert(TB_ERROR, "UVVM alert counters do not match the expected alerts", "ofbTestEnd");
        end if;
        test_runner_cleanup(runner);
    end procedure;

    function toSlvArray (words : in WordArray_t) return t_slv_array is
        variable Arr_v : t_slv_array(0 to words'length-1)(31 downto 0);
    begin

        for i in 0 to words'length-1 loop
            Arr_v(i) := words(words'low + i);
        end loop;

        return Arr_v;
    end function;

    function toUserArray (kflags : in WordKArray_t) return t_user_array is
        variable Arr_v : t_user_array(0 to kflags'length-1) := (others => (others => '0'));
    begin

        for i in 0 to kflags'length-1 loop
            Arr_v(i)(3 downto 0) := kflags(kflags'low + i);
        end loop;

        return Arr_v;
    end function;

end package body;
