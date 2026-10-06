---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Unit testbench of the receive side of the Multi-Lane layer with four lanes: lane alignment
-- (ofb_ml_align) and row concentrator (ofb_ml_rx), driven with words per lane from the test
-- sequencer (alignment FIFOs, row rules, alignment state machine, packing into rows).
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_align_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_align_tb is

    constant N_c         : positive := 4;
    constant ClkPeriod_c : time     := 6.4 ns;

    -- Words per lane: bit 37 gap (no word in this cycle), bit 36 CRC error flag, 35:32 K, 31:0 data
    subtype Entry_t is std_logic_vector(37 downto 0);

    type LaneQueue_t is protected

        procedure push (
            lane  : natural;
            entry : Entry_t);

        impure function pop (lane : natural) return Entry_t;
        impure function count (lane : natural) return natural;

        procedure clear;
    end protected;

    type LaneQueue_t is protected body

        type Entries_t is array (0 to 4095) of Entry_t;
        type Lanes_t is array (0 to N_c-1) of Entries_t;
        type Nat_t is array (0 to N_c-1) of natural;

        variable Entries_v : Lanes_t;
        variable Head_v    : Nat_t := (others => 0);
        variable Count_v   : Nat_t := (others => 0);

        procedure push (
            lane  : natural;
            entry : Entry_t) is
        begin
            assert Count_v(lane) < Entries_t'length
                report "LaneQueue_t full"
                severity failure;
            Entries_v(lane)((Head_v(lane) + Count_v(lane)) mod Entries_t'length) := entry;
            Count_v(lane)                                                        := Count_v(lane) + 1;
        end procedure;

        impure function pop (lane : natural) return Entry_t is
            variable Entry_v : Entry_t;
        begin
            Entry_v       := Entries_v(lane)(Head_v(lane));
            Head_v(lane)  := (Head_v(lane) + 1) mod Entries_t'length;
            Count_v(lane) := Count_v(lane) - 1;
            return Entry_v;
        end function;

        impure function count (lane : natural) return natural is
        begin
            return Count_v(lane);
        end function;

        procedure clear is
        begin
            Count_v := (others => 0);
        end procedure;

    end protected body;

    -- Rows passed to the Data Link layer
    type Row_t is record
        Data   : std_logic_vector(32*N_c-1 downto 0);
        K      : std_logic_vector(4*N_c-1 downto 0);
        Mask   : std_logic_vector(N_c-1 downto 0);
        CrcErr : std_logic;
    end record;

    type RowLog_t is protected

        procedure push (row : Row_t);

        impure function get (idx : natural) return Row_t;
        impure function count return natural;

        procedure clear;
    end protected;

    type RowLog_t is protected body

        type Rows_t is array (0 to 4095) of Row_t;

        variable Rows_v  : Rows_t;
        variable Count_v : natural := 0;

        procedure push (row : Row_t) is
        begin
            if Count_v < Rows_t'length then
                Rows_v(Count_v) := row;
            end if;
            Count_v := Count_v + 1;
        end procedure;

        impure function get (idx : natural) return Row_t is
        begin
            return Rows_v(idx);
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

    shared variable Queue_v  : LaneQueue_t;
    shared variable RowLog_v : RowLog_t;

    signal Clk        : std_logic                           := '0';
    signal Rst        : std_logic                           := '1';
    signal Flush      : std_logic                           := '0';
    signal ActLanes   : std_logic_vector(N_c-1 downto 0)    := "1111";
    signal RxLanes    : std_logic_vector(N_c-1 downto 0)    := "1111";
    signal NumRxLanes : std_logic_vector(3 downto 0)        := "0100";
    signal InData     : std_logic_vector(32*N_c-1 downto 0) := (others => '0');
    signal InK        : std_logic_vector(4*N_c-1 downto 0)  := (others => '0');
    signal InCrcErr   : std_logic_vector(N_c-1 downto 0)    := (others => '0');
    signal InValid    : std_logic_vector(N_c-1 downto 0)    := (others => '0');
    signal RowData    : std_logic_vector(32*N_c-1 downto 0);
    signal RowK       : std_logic_vector(4*N_c-1 downto 0);
    signal RowCount   : std_logic_vector(2 downto 0);
    signal RowIsData  : std_logic;
    signal RowCrcErr  : std_logic;
    signal RowValid   : std_logic;
    signal FarAct     : std_logic_vector(15 downto 0);
    signal FarActV    : std_logic;
    signal RecvLanes  : std_logic_vector(N_c-1 downto 0);
    signal AlignState : AlignState_t;
    signal Misaligned : std_logic;
    signal RxData     : std_logic_vector(32*N_c-1 downto 0);
    signal RxK        : std_logic_vector(4*N_c-1 downto 0);
    signal RxMask     : std_logic_vector(N_c-1 downto 0);
    signal RxCrcErr   : std_logic;
    signal RxValid    : std_logic;

    -- Event counters of the monitor
    signal MisCnt    : natural := 0;
    signal FarActCnt : natural := 0;

    -- Skew of each lane in words; a change while words flow drops or repeats words (slip)
    type Skew_t is array (0 to N_c-1) of natural range 0 to 7;

    signal Skew : Skew_t := (others => 0);

    -- Words used by the tests
    constant Fct_c  : Word_t := x"0000_00" & CharFct_c;
    constant Ebf_c  : Word_t := x"0000_00" & CharEbf_c;
    constant Sif_c  : Word_t := x"0000" & SymSif_c & K28_7_c;
    constant Act4_c : Word_t := wordActive(x"000F");

    function edf (seq : natural) return Word_t is
    begin
        return x"0000" & std_logic_vector(to_unsigned(seq, 8)) & CharEdf_c;
    end function;

    function dataWord (n : natural) return Word_t is
    begin
        return std_logic_vector(to_unsigned(n, 32));
    end function;

begin

    Clk <= not Clk after ClkPeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Read_v : natural := 0; -- Next row of the log to check
        variable Row_v  : Row_t;
        variable Num_v  : natural;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until falling_edge(Clk);
            end loop;

        end procedure;

        -- One word for a lane
        procedure word (
            lane : natural;
            data : Word_t;
            k    : WordK_t   := KData_c;
            crc  : std_logic := '0') is
        begin
            Queue_v.push(lane, '0' & crc & k & data);
        end procedure;

        -- Cycles without a word on a lane (slip)
        procedure gap (
            lane : natural;
            n    : natural) is
        begin

            for i in 1 to n loop
                Queue_v.push(lane, "10" & x"0" & x"0000_0000");
            end loop;

        end procedure;

        -- The same word on the lanes of mask
        procedure row (
            data : Word_t;
            k    : WordK_t                          := KCtrl_c;
            mask : std_logic_vector(N_c-1 downto 0) := "1111") is
        begin

            for i in 0 to N_c-1 loop
                if mask(i) = '1' then
                    word(i, data, k);
                end if;
            end loop;

        end procedure;

        -- A row of data words n, n+1, ... on the lanes of mask
        procedure dataRow (
            n    : natural;
            mask : std_logic_vector(N_c-1 downto 0) := "1111") is
            variable Pos_v : natural;
        begin
            Pos_v := 0;

            for i in 0 to N_c-1 loop
                if mask(i) = '1' then
                    word(i, dataWord(n + Pos_v));
                    Pos_v := Pos_v + 1;
                end if;
            end loop;

        end procedure;

        -- Seven ACTIVE words and one ALIGN word on every lane of mask, rounds times
        procedure alignSeq (
            rounds : natural;
            act    : std_logic_vector(15 downto 0)    := x"000F";
            num    : natural                          := 4;
            mask   : std_logic_vector(N_c-1 downto 0) := "1111") is
        begin

            for j in 1 to rounds loop
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);
                row(wordActive(act), KCtrl_c, mask);

                for i in 0 to N_c-1 loop
                    if mask(i) = '1' then
                        word(i, wordAlign(std_logic_vector(to_unsigned(num mod 16, 4)),
                                          std_logic_vector(to_unsigned(i, 4))), KCtrl_c);
                    end if;
                end loop;

            end loop;

        end procedure;

        -- Wait until all queued words are sent and a few more cycles
        procedure drain is
        begin

            for i in 0 to N_c-1 loop

                while Queue_v.count(i) > 0 loop
                    cycles(1);
                end loop;

            end loop;

            cycles(10);
        end procedure;

        procedure waitState (
            state : AlignState_t;
            msg   : string) is
            variable Start_v : time;
        begin
            Start_v := now;

            while AlignState /= state loop
                cycles(1);
                if now - Start_v > 50 us then
                    alert(error, "Timeout: " & msg);
                    exit;
                end if;
            end loop;

        end procedure;

        -- Align from Not Ready to Both-Ends Ready with the lanes of mask
        procedure align (
            mask : std_logic_vector(N_c-1 downto 0) := "1111";
            act  : std_logic_vector(15 downto 0)    := x"000F";
            num  : natural                          := 0) is
            variable Num_v : natural;
        begin
            Num_v := num;
            if Num_v = 0 then
                Num_v := countOnes(mask);
            end if;
            alignSeq(3, act, Num_v, mask);
            drain;
            check_value(AlignState, AlignNearEndReady_c, error, "Near-End Ready after alignment");
            row(Fct_c, KCtrl_c, mask);
            dataRow(16#FFFF00#, mask);
            row(edf(0), KCtrl_c, mask);
            drain;
            check_value(AlignState, AlignBothEndsReady_c, error, "Both-Ends Ready after a data word");
            Read_v := RowLog_v.count;
        end procedure;

        -- Check the next row of the log
        procedure expectRow (
            data : std_logic_vector(32*N_c-1 downto 0);
            k    : std_logic_vector(4*N_c-1 downto 0);
            mask : std_logic_vector(N_c-1 downto 0);
            crc  : std_logic;
            msg  : string) is
        begin
            if Read_v >= RowLog_v.count then
                alert(error, msg & ": row missing");
            else
                Row_v := RowLog_v.get(Read_v);
                check_value(Row_v.Mask, mask, error, msg & ": mask");

                for i in 0 to N_c-1 loop
                    if mask(i) = '1' then
                        check_value(Row_v.Data(32*i+31 downto 32*i), data(32*i+31 downto 32*i), error,
                                    msg & ": word " & to_string(i));
                        check_value(Row_v.K(4*i+3 downto 4*i), k(4*i+3 downto 4*i), error,
                                    msg & ": K flags " & to_string(i));
                    end if;
                end loop;

                check_value(Row_v.CrcErr, crc, error, msg & ": CRC error flag");
            end if;
            Read_v := Read_v + 1;
        end procedure;

        -- Next row: one control word
        procedure expectCtrl (
            data : Word_t;
            msg  : string;
            crc  : std_logic := '0';
            k    : WordK_t   := KCtrl_c) is
            variable Data_v : std_logic_vector(32*N_c-1 downto 0) := (others => '0');
            variable K_v    : std_logic_vector(4*N_c-1 downto 0)  := (others => '0');
        begin
            Data_v(31 downto 0) := data;
            K_v(3 downto 0)     := k;
            expectRow(Data_v, K_v, "0001", crc, msg);
        end procedure;

        -- Next row: data words n, n+1, ... (cnt words)
        procedure expectData (
            n   : natural;
            cnt : positive;
            msg : string) is
            variable Data_v : std_logic_vector(32*N_c-1 downto 0) := (others => '0');
            variable Mask_v : std_logic_vector(N_c-1 downto 0)    := (others => '0');
        begin

            for i in 0 to cnt-1 loop
                Data_v(32*i+31 downto 32*i) := dataWord(n + i);
                Mask_v(i)                   := '1';
            end loop;

            expectRow(Data_v, (others => '0'), Mask_v, '0', msg);
        end procedure;

        procedure expectEnd (msg : string) is
        begin
            check_value(RowLog_v.count, Read_v, error, msg & ": number of rows");
            Read_v := RowLog_v.count;
        end procedure;

        procedure linkReset is
        begin
            Flush  <= '1';
            cycles(1);
            Flush  <= '0';
            cycles(2);
            Read_v := RowLog_v.count;
        end procedure;

    -- Test cases
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        cycles(5);
        Rst <= '0';
        cycles(5);

        while test_suite loop

            -- TC-ML-40: alignment FIFOs, skew, overflow
            if run("test_alignment_fifo") then
                -- Figure 5-36: skew of 0, 1, 2 and 3 words
                Skew <= (0, 1, 2, 3);
                align;
                check_value(RecvLanes, "1111", error, "All lanes are data-receiving lanes");

                -- Rows are read across the skew
                for j in 0 to 9 loop
                    dataRow(16 * j);
                end loop;

                drain;

                for j in 0 to 9 loop
                    expectData(16 * j, 4, "Aligned row " & to_string(j));
                end loop;

                expectEnd("Aligned rows");

                -- Skew of four words: the FIFO of lane 0 overflows, the lanes never align
                linkReset;
                Skew <= (0, 1, 2, 4);
                alignSeq(6);

                -- The words keep flowing after the last ALIGN, as on a link
                for j in 1 to 8 loop
                    row(Act4_c);
                end loop;

                drain;
                check_value(AlignState, AlignNotReady_c, error, "No alignment with a skew of 4 words");
                -- Back to a skew of 3 words: alignment
                Skew <= (1, 1, 2, 4);
                alignSeq(3);

                for j in 1 to 8 loop
                    row(Act4_c);
                end loop;

                drain;
                check_value(AlignState, AlignNearEndReady_c, error, "Alignment with a skew of 3 words");
                -- Slip of one lane after alignment: Misaligned, RXERR, new alignment
                align;
                Num_v := MisCnt;

                for j in 0 to 3 loop
                    dataRow(16 * j);
                end loop;

                -- Slip: an additional word on lane 2 (a delay of an early lane is absorbed by the FIFO)
                word(2, dataWord(16#9999#));

                for j in 4 to 7 loop
                    dataRow(16 * j);
                end loop;

                -- Data rows of two rows mixed are not detected; the next control row is invalid
                row(Fct_c);
                drain;
                check_value(MisCnt, Num_v + 1, error, "Slip of lane 2: Misaligned");
                check_value(AlignState, AlignNotReady_c, error, "Not Ready after the slip");
                align;
                dataRow(1000);
                drain;
                expectData(1000, 4, "Row after the new alignment");

            -- TC-ML-41: row classification
            elsif run("test_row_rules") then
                align;
                -- Data frame: SDF, data rows, data and PAD, EDF with a CRC error of lane 2
                row(wordSdf("00011"));
                dataRow(100);
                dataRow(104);
                dataRow(108, "0011");
                word(2, WordPad_c, KPad_c);
                word(3, WordPad_c, KPad_c);
                word(0, edf(1), KCtrl_c);
                word(1, edf(1), KCtrl_c);
                word(2, edf(1), KCtrl_c, '1');
                word(3, edf(1), KCtrl_c);
                -- Control row: one word
                row(Fct_c);
                -- PAD only: nothing passed
                row(WordPad_c, KPad_c);
                drain;
                expectCtrl(wordSdf("00011"), "SDF");
                expectData(100, 4, "Data row 1");
                expectData(104, 4, "Data row 2");
                expectData(108, 2, "Data words before the EDF");
                expectCtrl(edf(1), "EDF with the CRC error of lane 2", '1');
                expectCtrl(Fct_c, "FCT row");
                expectEnd("Valid rows");
                check_value(MisCnt, 0, error, "No Misaligned condition with valid rows");

                -- RXERR in one lane: one RXERR, no Misaligned condition after 4 us
                dataRow(200, "1011");
                word(2, WordRxErr_c, KCtrl_c);
                dataRow(204);
                drain;
                expectCtrl(WordRxErr_c, "RXERR row");
                expectData(204, 4, "Row after RXERR");
                expectEnd("RXERR");
                check_value(MisCnt, 0, error, "No Misaligned condition with an RXERR row");
                check_value(AlignState, AlignBothEndsReady_c, error, "Both-Ends Ready after RXERR");

                -- ACTIVE in some lanes: RXERR, Near-End Ready
                row(Act4_c, KCtrl_c, "0011");
                row(Fct_c, KCtrl_c, "1100");
                drain;
                expectCtrl(WordRxErr_c, "Row with some ACTIVE words");
                expectEnd("Partial ACTIVE");
                check_value(AlignState, AlignNearEndReady_c, error, "ACTIVE received: Near-End Ready");
                dataRow(300);
                drain;
                expectData(300, 4, "Data row in Near-End Ready");
                check_value(AlignState, AlignBothEndsReady_c, error, "Both-Ends Ready again");

                -- Invalid row: data and control words
                Num_v := MisCnt;
                dataRow(400, "0011");
                row(Fct_c, KCtrl_c, "1100");
                drain;
                expectCtrl(WordRxErr_c, "Invalid row");
                expectEnd("Invalid row");
                check_value(MisCnt, Num_v + 1, error, "Misaligned condition with an invalid row");
                check_value(AlignState, AlignNotReady_c, error, "Not Ready after an invalid row");

                -- Valid ALIGN held in one lane after alignment: Misaligned
                align;
                Num_v := MisCnt;
                word(0, wordAlign("0100", "0000"), KCtrl_c);
                dataRow(500, "1110");
                word(0, dataWord(503));
                drain;
                check_value(MisCnt, Num_v + 1, error, "Misaligned condition with a held ALIGN after alignment");
                check_value(RowLog_v.count > Read_v, error, "RXERR passed");
                Row_v := RowLog_v.get(Read_v);
                check_value(Row_v.Data(31 downto 0), WordRxErr_c, error, "RXERR passed for the slip");

            -- TC-ML-42: alignment state machine
            elsif run("test_align_states") then
                -- Valid ACTIVE needs two equal words; far-end active lanes differ: no Near-End Ready
                Num_v := FarActCnt;
                row(wordActive(x"0007"));
                row(wordActive(x"000F"));
                row(wordActive(x"0007"));
                drain;
                check_value(FarActCnt, Num_v, error, "No valid ACTIVE from different words");
                alignSeq(3, x"0007");
                drain;
                check_value(FarAct, x"0007", error, "Far-end active lanes");
                check_value(AlignState, AlignNotReady_c, error, "Far-end active lanes differ: Not Ready");
                alignSeq(3, x"000F");
                drain;
                check_value(AlignState, AlignNearEndReady_c, error, "Far-end active lanes equal: Near-End Ready");
                -- RXERR within 4 us of entering Near-End Ready: Misaligned
                Num_v := MisCnt;
                row(WordRxErr_c);
                drain;
                check_value(MisCnt, Num_v + 1, error, "RXERR within 4 us: Misaligned");
                check_value(AlignState, AlignNotReady_c, error, "Not Ready after the early RXERR");
                -- RXERR after 4 us: passed, Near-End Ready kept
                alignSeq(3);
                drain;
                check_value(AlignState, AlignNearEndReady_c, error, "Near-End Ready again");
                cycles(700);
                Read_v := RowLog_v.count;
                Num_v  := MisCnt;
                row(WordRxErr_c);
                drain;
                check_value(MisCnt, Num_v, error, "RXERR after 4 us: no Misaligned condition");
                expectCtrl(WordRxErr_c, "RXERR after 4 us passed");
                check_value(AlignState, AlignNearEndReady_c, error, "Near-End Ready kept");
                -- Data word: Both-Ends Ready; ACTIVE: Near-End Ready
                dataRow(10);
                drain;
                check_value(AlignState, AlignBothEndsReady_c, error, "Data word: Both-Ends Ready");
                row(Act4_c);
                drain;
                check_value(AlignState, AlignNearEndReady_c, error, "ACTIVE: Near-End Ready");
                -- Correct but invalid ALIGN (#Lanes 3 with four receiving lanes): Misaligned
                Num_v := MisCnt;
                alignSeq(1, x"000F", 3);
                drain;
                check_value(MisCnt, Num_v + 1, error, "Invalid ALIGN: Misaligned");
                check_value(AlignState, AlignNotReady_c, error, "Not Ready after the invalid ALIGN");
                -- ALIGN of a hot redundant lane on lane 3: not a data-receiving lane
                word(3, x"0000" & SymAlign_c & K28_7_c, KCtrl_c);
                drain;
                check_value(RecvLanes, "0111", error, "Lane 3 is not a data-receiving lane");
                align("0111", x"000F", 4);
                row(wordSdf("00000"), KCtrl_c, "0111");
                dataRow(20, "0111");
                row(edf(5), KCtrl_c, "0111");
                drain;
                expectCtrl(wordSdf("00000"), "SDF over three lanes");
                expectData(20, 3, "Row of three lanes");
                expectCtrl(edf(5), "EDF over three lanes");
                -- Near-end active lanes change: Misaligned
                Num_v      := MisCnt;
                ActLanes   <= "0111";
                RxLanes    <= "0111";
                NumRxLanes <= "0011";
                cycles(5);
                check_value(MisCnt, Num_v + 1, error, "Near-end active lanes changed: Misaligned");
                -- An incorrect ALIGN (#Lanes 4) on a lane that is active but not data-receiving is ignored
                ActLanes <= "1111";
                cycles(5);
                align("0111", x"000F", 3);
                Num_v    := MisCnt;
                word(3, wordAlign(x"4", x"3"), KCtrl_c);
                drain;
                check_value(MisCnt, Num_v, error, "Incorrect ALIGN on a lane that is not data-receiving ignored");
                check_value(AlignState, AlignBothEndsReady_c, error, "Both-Ends Ready kept");

            -- TC-ML-43: packing of data words into rows of four words with three data-receiving lanes
            elsif run("test_packing") then
                ActLanes   <= "0111";
                RxLanes    <= "0111";
                NumRxLanes <= "0011";
                cycles(2);
                align("0111", x"0007");
                row(wordSdf("00001"), KCtrl_c, "0111");
                dataRow(0, "0111");
                row(Fct_c, KCtrl_c, "0111");
                dataRow(3, "0111");
                row(wordSbf(x"05", x"06"), KCtrl_c, "0111");
                row(x"CAFE0001", KData_c, "0111");
                row(x"CAFE0002", KData_c, "0111");
                row(Ebf_c, KCtrl_c, "0111");
                dataRow(6, "0111");
                dataRow(9, "0001");
                word(1, WordPad_c, KPad_c);
                word(2, WordPad_c, KPad_c);
                row(edf(2), KCtrl_c, "0111");
                -- Idle frame: one word per replicated row
                row(Sif_c, KCtrl_c, "0111");
                row(x"12345678", KData_c, "0111");
                -- RETRY and RXERR flush waiting words
                row(wordSdf("00010"), KCtrl_c, "0111");
                dataRow(20, "0111");
                row(WordRetry_c, KCtrl_c, "0111");
                row(wordSdf("00011"), KCtrl_c, "0111");
                dataRow(30, "0011");
                word(2, WordPad_c, KPad_c);
                row(WordRxErr_c, KCtrl_c, "0111");
                drain;
                expectCtrl(wordSdf("00001"), "SDF");
                expectCtrl(Fct_c, "FCT passes three waiting data words");
                expectData(0, 4, "Row of words 0 to 3");
                expectCtrl(wordSbf(x"05", x"06"), "SBF passes waiting data words");
                expectCtrl(x"CAFE0001", "Broadcast word 1", '0', KData_c);
                expectCtrl(x"CAFE0002", "Broadcast word 2", '0', KData_c);
                expectCtrl(Ebf_c, "EBF");
                expectData(4, 4, "Row of words 4 to 7");
                expectData(8, 2, "Incomplete row before the EDF");
                expectCtrl(edf(2), "EDF");
                expectCtrl(Sif_c, "SIF");
                expectCtrl(x"12345678", "Idle word: one word", '0', KData_c);
                expectCtrl(wordSdf("00010"), "SDF 2");
                expectData(20, 3, "Incomplete row before RETRY");
                expectCtrl(WordRetry_c, "RETRY");
                expectCtrl(wordSdf("00011"), "SDF 3");
                expectData(30, 2, "Incomplete row before RXERR");
                expectCtrl(WordRxErr_c, "RXERR");
                expectEnd("Packing");

            -- TC-ML-47: frame structure errors at the receiver: an SIF inside a data frame passes the
            -- waiting words and starts an idle frame; a second SBF without EBF, an SDF after a broadcast
            -- frame and an SIF inside a broadcast frame (inside and outside a data frame) change the
            -- packing as the new frame requires
            elsif run("test_packing_errors") then
                ActLanes   <= "0111";
                RxLanes    <= "0111";
                NumRxLanes <= "0011";
                cycles(2);
                align("0111", x"0007");
                -- SIF inside a data frame
                row(wordSdf("00001"), KCtrl_c, "0111");
                dataRow(0, "0011");
                word(2, WordPad_c, KPad_c);
                row(Sif_c, KCtrl_c, "0111");
                row(x"12345678", KData_c, "0111");
                -- SBF inside a data frame, a second SBF, SDF after the broadcast frame
                row(wordSdf("00010"), KCtrl_c, "0111");
                row(wordSbf(x"05", x"06"), KCtrl_c, "0111");
                row(wordSbf(x"07", x"08"), KCtrl_c, "0111");
                row(x"CAFE0003", KData_c, "0111");
                row(wordSdf("00011"), KCtrl_c, "0111");
                dataRow(40, "0111");
                row(edf(3), KCtrl_c, "0111");
                -- SIF inside a broadcast frame inside and outside a data frame
                row(wordSdf("00100"), KCtrl_c, "0111");
                row(wordSbf(x"09", x"0A"), KCtrl_c, "0111");
                row(Sif_c, KCtrl_c, "0111");
                row(wordSbf(x"0B", x"0C"), KCtrl_c, "0111");
                row(Sif_c, KCtrl_c, "0111");
                row(x"9ABCDEF0", KData_c, "0111");
                drain;
                expectCtrl(wordSdf("00001"), "SDF 1");
                expectData(0, 2, "Waiting words passed by the SIF");
                expectCtrl(Sif_c, "SIF inside a data frame");
                expectCtrl(x"12345678", "Idle word after the SIF: one word", '0', KData_c);
                expectCtrl(wordSdf("00010"), "SDF 2");
                expectCtrl(wordSbf(x"05", x"06"), "SBF inside the data frame");
                expectCtrl(wordSbf(x"07", x"08"), "Second SBF");
                expectCtrl(x"CAFE0003", "Broadcast word: one word", '0', KData_c);
                expectCtrl(wordSdf("00011"), "SDF after the broadcast frame");
                expectData(40, 3, "Data words packed again");
                expectCtrl(edf(3), "EDF 3");
                expectCtrl(wordSdf("00100"), "SDF 4");
                expectCtrl(wordSbf(x"09", x"0A"), "SBF inside data frame 4");
                expectCtrl(Sif_c, "SIF inside the broadcast frame");
                expectCtrl(wordSbf(x"0B", x"0C"), "SBF outside a data frame");
                expectCtrl(Sif_c, "SIF inside the broadcast frame outside a data frame");
                expectCtrl(x"9ABCDEF0", "Idle word: one word", '0', KData_c);
                expectEnd("Packing after frame structure errors");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

    test_runner_watchdog(runner, 5 ms);

    -----------------------------------------------------------------------------------------------
    -- Word drivers of the lanes and monitor
    -----------------------------------------------------------------------------------------------
    p_drive : process (Clk) is
        type Line_t is array (0 to 7) of Entry_t;
        type Lines_t is array (0 to N_c-1) of Line_t;

        variable Line_v  : Lines_t := (others => (others => (37 => '1', others => '0')));
        variable Entry_v : Entry_t;
    begin
        if rising_edge(Clk) then
            InValid <= (others => '0');

            for i in 0 to N_c-1 loop

                -- Delay line of the skew
                for j in 7 downto 1 loop
                    Line_v(i)(j) := Line_v(i)(j-1);
                end loop;

                Line_v(i)(0) := (37 => '1',
                                 others => '0');
                if Queue_v.count(i) > 0 then
                    Line_v(i)(0) := Queue_v.pop(i);
                end if;
                Entry_v := Line_v(i)(Skew(i));
                if Entry_v(37) = '0' then
                    InData(32*i+31 downto 32*i) <= Entry_v(31 downto 0);
                    InK(4*i+3 downto 4*i)       <= Entry_v(35 downto 32);
                    InCrcErr(i)                 <= Entry_v(36);
                    InValid(i)                  <= '1';
                end if;
            end loop;

        end if;
    end process;

    p_monitor : process (Clk) is
        variable Row_v : Row_t;
    begin
        if rising_edge(Clk) then
            if RxValid = '1' then
                Row_v := (Data => RxData,
                          K => RxK,
                          Mask => RxMask,
                          CrcErr => RxCrcErr);
                RowLog_v.push(Row_v);
            end if;
            if Misaligned = '1' then
                MisCnt <= MisCnt + 1;
            end if;
            if FarActV = '1' then
                FarActCnt <= FarActCnt + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- DUT: lane alignment and row concentrator
    -----------------------------------------------------------------------------------------------
    i_align : entity work.ofb_ml_align
        generic map (
            NumLanes_g     => N_c,
            ClkFrequency_g => 156.25e6
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            Ctrl_Flush    => Flush,
            Bypass        => '0',
            ActLanes      => ActLanes,
            RxLanes       => RxLanes,
            NumRxLanes    => NumRxLanes,
            In_Data       => InData,
            In_K          => InK,
            In_CrcErr     => InCrcErr,
            In_Valid      => InValid,
            Row_Data      => RowData,
            Row_K         => RowK,
            Row_Count     => RowCount,
            Row_Data_Row  => RowIsData,
            Row_CrcErr    => RowCrcErr,
            Row_Valid     => RowValid,
            FarAct        => FarAct,
            FarActValid   => FarActV,
            RecvLanes     => RecvLanes,
            AlignState    => AlignState,
            Ev_Misaligned => Misaligned
        );

    i_rx : entity work.ofb_ml_rx
        generic map (
            NumLanes_g => N_c
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            Ctrl_Flush   => Flush,
            In_Data      => RowData,
            In_K         => RowK,
            In_Count     => RowCount,
            In_DataRow   => RowIsData,
            In_CrcErr    => RowCrcErr,
            In_Valid     => RowValid,
            RxRow_Data   => RxData,
            RxRow_K      => RxK,
            RxRow_Mask   => RxMask,
            RxRow_CrcErr => RxCrcErr,
            RxRow_Valid  => RxValid
        );

end architecture;
