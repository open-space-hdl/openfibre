---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the Network interface: packets to N-Char rows (end markers, Fills, framing errors)
-- and N-Char rows to packets (Fill removal, alignment of every offset, packets of zero length,
-- character rule violations), with random handshakes, on two VCs.
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

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_ni_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni_tb is
    generic (
        runner_cfg : string;
        NumLanes_g : positive range 1 to 4 := 1
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ni_tb is

    constant B_c : positive := 4 * NumLanes_g;

    signal Clk : std_logic;
    signal Rst : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        type Counts_t is array (0 to NiVc_c-1) of natural;
        type Chars_t is array (0 to NiVc_c-1, 0 to 15) of Char_t;
        type Ks_t is array (0 to NiVc_c-1) of std_logic_vector(15 downto 0);

        -- Data values: running counters per VC (transmit, receive)
        variable TxCnt_v : Counts_t := (others => 0);
        variable RxCnt_v : Counts_t := (others => 0);
        -- Row under construction per VC (receive direction)
        variable RowD_v  : Chars_t;
        variable RowK_v  : Ks_t;
        variable RowN_v  : Counts_t := (others => 0);
        -- Expected events per VC
        variable ExpTx_v : Counts_t := (others => 0);
        variable ExpRx_v : Counts_t := (others => 0);
        variable ExpEm_v : Counts_t := (others => 0);
        variable Seed1_v : positive := 7;
        variable Seed2_v : positive := 77;
        variable Rand_v  : real;
        variable T0_v    : time;
        variable N_v     : natural;
        variable Lead_v  : natural;
        variable Len_v   : natural;
        variable Eep_v   : std_logic;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        impure function randInt (
            lo : natural;
            hi : natural) return natural is
        begin
            uniform(Seed1_v, Seed2_v, Rand_v);
            return minimum(hi, lo + natural(floor(Rand_v * real(hi - lo + 1))));
        end function;

        function rep (
            c : character;
            n : natural) return string is
            variable S_v : string(1 to maximum(n, 1)) := (others => c);
        begin
            if n = 0 then
                return "";
            end if;
            return S_v;
        end function;

        function byteOf (n : natural) return Char_t is
        begin
            return std_logic_vector(to_unsigned(n mod 256, 8));
        end function;

        -- Invalid TKEEP: 'g' gap (bytes 0 and 2), 'l' all bytes but the last one (invalid without
        -- TLAST), 'h' all bytes but byte 0
        function badKeep (kind : character) return std_logic_vector is
            variable Keep_v : std_logic_vector(B_c-1 downto 0) := (others => '0');
        begin

            case kind is

                when 'g' =>
                    Keep_v(0) := '1';
                    Keep_v(2) := '1';

                when 'l' =>
                    Keep_v          := (others => '1');
                    Keep_v(B_c - 1) := '0';

                when others =>
                    Keep_v    := (others => '1');
                    Keep_v(0) := '0';

            end case;

            return Keep_v;
        end function;

        -------------------------------------------------------------------------------------------
        -- Transmit direction
        -------------------------------------------------------------------------------------------

        -- Expected row of characters: data bytes first..first+n-1 (K flag clear), then 'E' (EOP), 'X'
        -- (EEP) or nothing at position n, Fills up to the end of the row
        procedure expTxRow (
            vc    : natural;
            first : natural;
            n     : natural;
            fin   : character) is
            variable Word_v : Word_t;
            variable K_v    : WordK_t;
            variable P_v    : natural;
        begin

            for w in 0 to NumLanes_g-1 loop

                for i in 0 to 3 loop
                    P_v := 4 * w + i;
                    if P_v < n then
                        Word_v(8*i+7 downto 8*i) := byteOf(first + P_v);
                        K_v(i)                   := '0';
                    elsif P_v = n and fin = 'E' then
                        Word_v(8*i+7 downto 8*i) := CharEop_c;
                        K_v(i)                   := '1';
                    elsif P_v = n and fin = 'X' then
                        Word_v(8*i+7 downto 8*i) := CharEep_c;
                        K_v(i)                   := '1';
                    else
                        Word_v(8*i+7 downto 8*i) := CharFill_c;
                        K_v(i)                   := '1';
                    end if;
                end loop;

                NiSb_v.add_expected(1 + vc, K_v & Word_v);
            end loop;

        end procedure;

        -- Beat to send with the bytes first..first+n-1 and the given TKEEP, TLAST and TUSER
        procedure txBeat (
            vc    : natural;
            first : natural;
            keep  : std_logic_vector;
            last  : std_logic;
            user  : std_logic := '0') is
            variable Entry_v : NiEntry_t := (others => '0');
        begin

            for c in 0 to B_c-1 loop
                Entry_v(8*c+7 downto 8*c) := byteOf(first + c);
            end loop;

            Entry_v(128+B_c-1 downto 128) := keep;
            Entry_v(144)                  := last;
            Entry_v(145)                  := user;
            NiQueue_v.push(vc, Entry_v);
        end procedure;

        -- Packet of len bytes from the running counter, ended with EOP or EEP, and its expected rows
        procedure txPacket (
            vc  : natural;
            len : positive;
            eep : std_logic := '0') is
            variable Pos_v  : natural := 0;
            variable Keep_v : std_logic_vector(B_c-1 downto 0);
            variable Fin_v  : character;
        begin
            Fin_v := 'E';
            if eep = '1' then
                Fin_v := 'X';
            end if;

            while Pos_v < len loop

                for c in 0 to B_c-1 loop
                    if Pos_v + c < len then
                        Keep_v(c) := '1';
                    else
                        Keep_v(c) := '0';
                    end if;
                end loop;

                if Pos_v + B_c >= len then
                    txBeat(vc, TxCnt_v(vc) + Pos_v, Keep_v, '1', eep);
                    expTxRow(vc, TxCnt_v(vc) + Pos_v, len - Pos_v, Fin_v);
                    if len - Pos_v = B_c then
                        -- Full last beat: the end marker in an additional row
                        expTxRow(vc, 0, 0, Fin_v);
                    end if;
                else
                    txBeat(vc, TxCnt_v(vc) + Pos_v, Keep_v, '0');
                    expTxRow(vc, TxCnt_v(vc) + Pos_v, B_c, 'F');
                end if;
                Pos_v := Pos_v + B_c;
            end loop;

            TxCnt_v(vc) := TxCnt_v(vc) + len;
        end procedure;

        -------------------------------------------------------------------------------------------
        -- Receive direction
        -------------------------------------------------------------------------------------------

        -- One character into the row of the VC; a full row goes to the driver
        procedure rxChar (
            vc   : natural;
            char : Char_t;
            k    : std_logic) is
            variable Entry_v : NiEntry_t := (others => '0');
        begin
            RowD_v(vc, RowN_v(vc)) := char;
            RowK_v(vc)(RowN_v(vc)) := k;
            RowN_v(vc)             := RowN_v(vc) + 1;
            if RowN_v(vc) = B_c then

                for c in 0 to B_c-1 loop
                    Entry_v(8*c+7 downto 8*c) := RowD_v(vc, c);
                end loop;

                Entry_v(128+B_c-1 downto 128) := RowK_v(vc)(B_c-1 downto 0);
                NiQueue_v.push(NiVc_c + vc, Entry_v);
                RowN_v(vc)                    := 0;
            end if;
        end procedure;

        -- Characters of a pattern: 'D' data from the running counter, 'E' EOP, 'X' EEP, 'F' Fill, 'K'
        -- K28.5. A pattern that ends with an end marker completes the row with Fills (a row of the
        -- input VC buffer ends after the word with the end marker)
        procedure rxPat (
            vc  : natural;
            pat : string) is
        begin

            for i in pat'range loop

                case pat(i) is

                    when 'D' =>
                        rxChar(vc, byteOf(RxCnt_v(vc)), '0');
                        RxCnt_v(vc) := RxCnt_v(vc) + 1;

                    when 'E' =>
                        rxChar(vc, CharEop_c, '1');

                    when 'X' =>
                        rxChar(vc, CharEep_c, '1');

                    when 'K' =>
                        rxChar(vc, CharInitComma_c, '1');

                    when others =>
                        rxChar(vc, CharFill_c, '1');

                end case;

            end loop;

            if pat(pat'high) = 'E' or pat(pat'high) = 'X' then

                while RowN_v(vc) /= 0 loop
                    rxChar(vc, CharFill_c, '1');
                end loop;

            end if;
        end procedure;

        -- Expected received bytes: n bytes from the counter value first, the last one ends the packet
        procedure expRx (
            vc    : natural;
            first : natural;
            n     : natural;
            eep   : std_logic := '0') is
            variable Last_v : std_logic;
            variable Eep_v  : std_logic;
        begin

            for i in 0 to n-1 loop
                Last_v := '0';
                Eep_v  := '0';
                if i = n-1 then
                    Last_v := '1';
                    Eep_v  := eep;
                end if;
                NiSb_v.add_expected(1 + NiVc_c + vc, "00" & Eep_v & Last_v & x"000000" & byteOf(first + i));
            end loop;

        end procedure;

        -- Packet after lead Fills with len data characters (0: packet of zero length) and its expectation
        procedure rxPacket (
            vc   : natural;
            lead : natural;
            len  : natural;
            eep  : std_logic := '0') is
        begin
            if len = 0 then
                ExpEm_v(vc) := ExpEm_v(vc) + 1;
            else
                expRx(vc, RxCnt_v(vc), len, eep);
            end if;
            if eep = '1' then
                rxPat(vc, rep('F', lead) & rep('D', len) & "X");
            else
                rxPat(vc, rep('F', lead) & rep('D', len) & "E");
            end if;
        end procedure;

        -------------------------------------------------------------------------------------------
        -- Completion
        -------------------------------------------------------------------------------------------
        procedure waitDone (timeout : time) is
            variable Start_v   : time;
            variable Pending_v : natural;
        begin
            Start_v := now;

            loop
                cycles(20);
                Pending_v := 0;

                for q in 0 to 2 * NiVc_c-1 loop
                    Pending_v := Pending_v + NiQueue_v.count(q) + NiSb_v.get_pending_count(1 + q);
                end loop;

                exit when Pending_v = 0;
                if now - Start_v > timeout then
                    alert(error, "Timeout: " & to_string(Pending_v) & " beats or elements pending");
                    exit;
                end if;
            end loop;

            cycles(20);

            for vc in 0 to NiVc_c-1 loop
                check_value(NiTxErrCnt(vc), ExpTx_v(vc), error, "Transmit framing errors of VC " & to_string(vc));
                check_value(NiRxErrCnt(vc), ExpRx_v(vc), error, "Receive framing errors of VC " & to_string(vc));
                check_value(NiEmptyCnt(vc), ExpEm_v(vc), error, "Packets of zero length of VC " & to_string(vc));
            end loop;

        end procedure;

        procedure randomHandshakes is
        begin
            NiHs <= (TxValid => 70, TxReady => 60, RxValid => 70, RxReady => 60);
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        NiSb_v.set_scope("NI_SB");

        for inst in 1 to 2 * NiVc_c loop
            NiSb_v.enable(inst);
            NiSb_v.disable_log_msg(inst, ID_DATA);
        end loop;

        wait until Rst = '0';
        cycles(5);

        while test_suite loop

            -- TC-NI-01: packets of every length from 1 to 3 x B + 1 bytes with EOP or EEP, random
            -- handshakes: data in stream order, end marker, Fills, additional row after a full last beat
            if run("test_tx_packets") then
                randomHandshakes;

                for len in 1 to 3 * B_c + 1 loop

                    for vc in 0 to NiVc_c-1 loop
                        if (len + vc) mod 3 = 0 then
                            txPacket(vc, len, '1');
                        else
                            txPacket(vc, len);
                        end if;
                    end loop;

                end loop;

                waitDone(1 ms);

            -- TC-NI-02: invalid TKEEP: in the first beat of a packet (nothing passed), in a later beat
            -- (EEP after the bytes passed), with TLAST (no spill), every kind of invalid TKEEP; the
            -- following packets pass
            elsif run("test_tx_framing") then
                randomHandshakes;

                for vc in 0 to NiVc_c-1 loop
                    -- Gap in TKEEP in the first beat: discarded up to TLAST, nothing passed
                    txBeat(vc, 0, badKeep('g'), '0');
                    txBeat(vc, 0, (B_c-1 downto 0 => '1'), '0');
                    txBeat(vc, 0, (B_c-1 downto 0 => '1'), '1');
                    ExpTx_v(vc) := ExpTx_v(vc) + 1;
                    txPacket(vc, 5);
                    -- Partial TKEEP in a later beat without TLAST: EEP after the first beat, spill
                    txBeat(vc, TxCnt_v(vc), (B_c-1 downto 0 => '1'), '0');
                    expTxRow(vc, TxCnt_v(vc), B_c, 'F');
                    expTxRow(vc, 0, 0, 'X');
                    txBeat(vc, 0, badKeep('l'), '0');
                    txBeat(vc, 0, (B_c-1 downto 0 => '1'), '0');
                    txBeat(vc, 0, badKeep('l'), '1');
                    ExpTx_v(vc) := ExpTx_v(vc) + 1;
                    TxCnt_v(vc) := TxCnt_v(vc) + B_c;
                    txPacket(vc, B_c);
                    -- TKEEP all zero with TLAST after a valid beat: EEP, no spill
                    txBeat(vc, TxCnt_v(vc), (B_c-1 downto 0 => '1'), '0');
                    expTxRow(vc, TxCnt_v(vc), B_c, 'F');
                    expTxRow(vc, 0, 0, 'X');
                    txBeat(vc, 0, (B_c-1 downto 0 => '0'), '1');
                    ExpTx_v(vc) := ExpTx_v(vc) + 1;
                    TxCnt_v(vc) := TxCnt_v(vc) + B_c;
                    txPacket(vc, 1);
                    -- TKEEP not starting at byte 0, single beat with TLAST: nothing passed
                    txBeat(vc, 0, badKeep('h'), '1');
                    ExpTx_v(vc) := ExpTx_v(vc) + 1;
                    txPacket(vc, 2 * B_c + 3, '1');
                end loop;

                waitDone(1 ms);

            -- TC-NI-03: received packets after 0 to 2 x B + 3 leading Fills (every offset in the word
            -- and in the beat, whole Fill words) with 1 to 2 x B + 2 bytes, EOP and EEP, random
            -- handshakes: bytes aligned to byte 0, TKEEP, TLAST, TUSER
            elsif run("test_rx_packets") then
                randomHandshakes;

                for lead in 0 to 2 * B_c + 3 loop

                    for len in 1 to 2 * B_c + 2 loop

                        for vc in 0 to NiVc_c-1 loop
                            if (lead + len + vc) mod 4 = 0 then
                                rxPacket(vc, lead, len, '1');
                            else
                                rxPacket(vc, lead, len);
                            end if;
                        end loop;

                    end loop;

                end loop;

                waitDone(5 ms);

            -- TC-NI-04: received packets of zero length (end marker after the end of the previous
            -- packet, after Fills, EEP of a link reset) are discarded and counted
            elsif run("test_rx_empty") then
                randomHandshakes;

                for vc in 0 to NiVc_c-1 loop
                    rxPacket(vc, 0, 0);
                    rxPacket(vc, 0, 3);
                    rxPacket(vc, 2, 0, '1');
                    rxPacket(vc, B_c + 1, 0);
                    rxPacket(vc, 1, B_c);
                    rxPacket(vc, 0, 0, '1');
                    rxPacket(vc, B_c - 1, 0);
                    rxPacket(vc, 3, 2 * B_c + 1, '1');
                end loop;

                waitDone(1 ms);

            -- TC-NI-05: character rule violations in received beats: Fill inside an open packet (offset 0
            -- and offset 1), data after an end marker, K28.5 inside a packet with an end in the beat, a
            -- second end marker, Fill after the first data character; the packet ends with an EEP after
            -- its earlier beats, the rest is discarded up to a clean end, no further event while discarding
            elsif run("test_rx_framing") then
                randomHandshakes;

                for vc in 0 to NiVc_c-1 loop
                    -- Fill inside an open packet (offset 0): first beat passed with EEP, discard to the end
                    expRx(vc, RxCnt_v(vc), B_c, '1');
                    rxPat(vc, rep('D', B_c));
                    rxPat(vc, "DF" & rep('D', B_c - 2));
                    rxPat(vc, "DE");
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 0, 3);
                    -- Fill inside an open packet (offset 1)
                    expRx(vc, RxCnt_v(vc), B_c - 1, '1');
                    rxPat(vc, "F" & rep('D', B_c - 1));
                    rxPat(vc, "DDDF" & rep('D', B_c - 4));
                    rxPat(vc, "X");
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 2, B_c + 1);
                    -- Data after an end marker in the same word: discarded up to the next clean end
                    rxPat(vc, "DEDF" & rep('F', B_c - 4));
                    rxPat(vc, "DDE");
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 0, 2);
                    -- K28.5 inside an open packet, clean end in the same beat: no discard
                    expRx(vc, RxCnt_v(vc), B_c, '1');
                    rxPat(vc, rep('D', B_c));
                    rxPat(vc, "DKDE");
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 1, 1);
                    -- Second end marker in a beat between packets
                    rxPat(vc, "EFEF" & rep('F', B_c - 4));
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 0, B_c);
                    -- Fill after the first data character without an end: discarded up to the next clean
                    -- end, the violation while discarding is not reported again
                    rxPat(vc, "FDFF" & rep('F', B_c - 4));
                    rxPat(vc, "DFDD" & rep('D', B_c - 4));
                    rxPat(vc, "DE");
                    ExpRx_v(vc) := ExpRx_v(vc) + 1;
                    rxPacket(vc, 0, 2 * B_c, '1');
                end loop;

                waitDone(1 ms);

            -- TC-NI-06: random received traffic: random leading Fills, lengths, EOP or EEP, packets of zero
            -- length, random handshakes
            elsif run("test_rx_random") then
                randomHandshakes;

                for p in 1 to 300 loop

                    for vc in 0 to NiVc_c-1 loop
                        Lead_v := randInt(0, B_c + 1);
                        if randInt(0, 9) = 0 then
                            Lead_v := randInt(0, 3 * B_c);
                        end if;
                        Len_v := randInt(1, 5 * B_c);
                        if randInt(0, 19) = 0 then
                            Len_v := 0;
                        end if;
                        Eep_v := '0';
                        if randInt(0, 9) = 0 then
                            Eep_v := '1';
                        end if;
                        rxPacket(vc, Lead_v, Len_v, Eep_v);
                    end loop;

                end loop;

                waitDone(10 ms);

            -- TC-NI-07: throughput with the handshakes always ready: one row or beat per cycle inside a
            -- packet, one additional cycle per packet (end marker row of a full last beat, tail beat)
            elsif run("test_throughput") then
                N_v := 20;

                -- Transmit: packets of 4 x B bytes, 5 rows each
                for p in 1 to N_v loop
                    txPacket(0, 4 * B_c);
                end loop;

                wait until NiTxRowCnt(0) = 1;
                T0_v := now;
                wait until NiTxRowCnt(0) = 5 * N_v;
                log(ID_LOG_HDR, "Transmit: " & to_string(5 * N_v) & " rows in " &
                    to_string((now - T0_v) / 6 ns + 1) & " cycles");
                check_value((now - T0_v) / 6 ns + 1 <= 5 * N_v + 1, error, "Transmit: one row per cycle");
                waitDone(1 ms);

                -- Receive: packets of 4 x B + 1 bytes at offset 0, 5 rows and 5 beats each (tail beat)
                for p in 1 to N_v loop
                    rxPacket(0, 0, 4 * B_c + 1);
                end loop;

                wait until NiRxBeatCnt(0) = 1;
                T0_v := now;
                wait until NiRxBeatCnt(0) = 5 * N_v;
                log(ID_LOG_HDR, "Receive: " & to_string(5 * N_v) & " beats in " &
                    to_string((now - T0_v) / 6 ns + 1) & " cycles");
                check_value((now - T0_v) / 6 ns + 1 <= 6 * N_v + 1, error, "Receive: one additional cycle per packet");
                waitDone(1 ms);

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 50 ms);

    -----------------------------------------------------------------------------------------------
    -- Test harness
    -----------------------------------------------------------------------------------------------
    i_th : entity work.ofb_ni_th
        generic map (
            NumLanes_g => NumLanes_g
        )
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
