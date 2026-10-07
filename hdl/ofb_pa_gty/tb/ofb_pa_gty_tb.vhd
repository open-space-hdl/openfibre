---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the Physical adapter PA-1 with the transceiver model: the serial lines of the four
-- lanes are looped back; every lane sends a stream of comma words, SKIP words and counting data
-- words, which must be received in order, with K flags and without code or disparity errors.
-- Then the external loopback is removed and the near-end serial loopback of every lane enabled; the
-- words must again be received in order. Finally the PRBS-31 generator and checker of every channel
-- are tested with the external loopback (lock, no error, bit errors on one line, pattern mismatch).
--
-- Documentation: hdl/ofb_pa_gty/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.env.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_tb is
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_tb is

    constant Lanes_c      : positive := 4;
    constant RefPeriod_c  : time     := 6.4 ns;
    constant FreePeriod_c : time     := 10 ns;
    constant Words_c      : positive := 300;   -- data words checked per lane
    constant Timeout_c    : time     := 400 us;

    -- SpaceFibre characters
    constant K28_7_c    : std_logic_vector(7 downto 0)  := x"FC";
    constant SymLlcw_c  : std_logic_vector(7 downto 0)  := x"CE";
    constant SymSkip_c  : std_logic_vector(7 downto 0)  := x"7F";
    constant SymIdle_c  : std_logic_vector(7 downto 0)  := x"CF";
    constant WordSkip_c : std_logic_vector(31 downto 0) := SymSkip_c & SymSkip_c & SymLlcw_c & K28_7_c;
    constant WordIdle_c : std_logic_vector(31 downto 0) := SymIdle_c & SymIdle_c & SymLlcw_c & K28_7_c;

    type CntArray_t is array (0 to Lanes_c-1) of natural;

    signal RefClk     : std_logic                               := '0';
    signal FreeRunClk : std_logic                               := '0';
    signal Rst        : std_logic                               := '1';
    signal LaneClk    : std_logic;
    signal LaneRst    : std_logic;
    signal TxP        : std_logic_vector(Lanes_c-1 downto 0);
    signal TxN        : std_logic_vector(Lanes_c-1 downto 0);
    signal TxData     : std_logic_vector(32*Lanes_c-1 downto 0) := (others => '0');
    signal TxK        : std_logic_vector(4*Lanes_c-1 downto 0)  := (others => '0');
    signal RxData     : std_logic_vector(32*Lanes_c-1 downto 0);
    signal RxK        : std_logic_vector(4*Lanes_c-1 downto 0);
    signal RxCodeErr  : std_logic_vector(4*Lanes_c-1 downto 0);
    signal RxDispErr  : std_logic_vector(4*Lanes_c-1 downto 0);
    signal RxValid    : std_logic_vector(Lanes_c-1 downto 0);
    signal NoSignal   : std_logic_vector(Lanes_c-1 downto 0);
    signal TxReady    : std_logic;
    signal RxReady    : std_logic;
    signal Aligned    : std_logic_vector(Lanes_c-1 downto 0);
    signal RxBufErr   : std_logic_vector(Lanes_c-1 downto 0);

    signal ExtLoop : boolean                              := true;
    signal NearLb  : std_logic_vector(Lanes_c-1 downto 0) := (others => '0');
    signal CheckEn : std_logic                            := '1';
    signal RxLineP : std_logic_vector(Lanes_c-1 downto 0);
    signal RxLineN : std_logic_vector(Lanes_c-1 downto 0);
    signal LineInv : std_logic_vector(Lanes_c-1 downto 0) := (others => '0');

    signal Checked : CntArray_t := (others => 0);
    signal Errors  : CntArray_t := (others => 0);

    -- PRBS test (TC-PA-06)
    signal PrbsTxSel  : std_logic_vector(4*Lanes_c-1 downto 0) := (others => '0');
    signal PrbsRxSel  : std_logic_vector(4*Lanes_c-1 downto 0) := (others => '0');
    signal PrbsForce  : std_logic_vector(Lanes_c-1 downto 0)   := (others => '0');
    signal PrbsCntRst : std_logic_vector(Lanes_c-1 downto 0)   := (others => '0');
    signal PrbsErr    : std_logic_vector(Lanes_c-1 downto 0);
    signal PrbsLocked : std_logic_vector(Lanes_c-1 downto 0);
    signal PrbsCount  : boolean                                := false;
    signal PrbsErrCnt : CntArray_t                             := (others => 0);

begin

    RefClk     <= not RefClk after RefPeriod_c / 2;
    FreeRunClk <= not FreeRunClk after FreePeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Done_v : boolean;
        variable Base_v : CntArray_t;
    begin
        Rst <= '1';
        wait for 200 ns;
        Rst <= '0';
        wait until TxReady = '1' for Timeout_c;
        report "TX ready: " & std_logic'image(TxReady) & " at " & time'image(now);
        wait until RxReady = '1' for Timeout_c;
        report "RX ready: " & std_logic'image(RxReady) & " at " & time'image(now);

        loop
            wait for 1 us;
            Done_v := true;

            for l in 0 to Lanes_c-1 loop
                if Checked(l) < Words_c then
                    Done_v := false;
                end if;
            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        for l in 0 to Lanes_c-1 loop
            report "Lane " & integer'image(l) & ": " & integer'image(Checked(l)) & " data words checked, " &
                   integer'image(Errors(l)) & " errors, aligned " & std_logic'image(Aligned(l)) &
                   ", no signal " & std_logic'image(NoSignal(l));
            assert Checked(l) >= Words_c
                report "FAIL: lane " & integer'image(l) & " too few words"
                severity error;
            assert Errors(l) = 0
                report "FAIL: lane " & integer'image(l) & " errors"
                severity error;
        end loop;

        -- Near-end serial loopback: the external loopback is removed
        CheckEn <= '0';
        ExtLoop <= false;
        NearLb  <= (others => '1');
        wait for 20 us;
        Base_v  := Checked;
        CheckEn <= '1';

        loop
            wait for 1 us;
            Done_v := true;

            for l in 0 to Lanes_c-1 loop
                if Checked(l) < Base_v(l) + Words_c then
                    Done_v := false;
                end if;
            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        for l in 0 to Lanes_c-1 loop
            report "Lane " & integer'image(l) & " in near-end serial loopback: " &
                   integer'image(Checked(l) - Base_v(l)) & " data words checked, " & integer'image(Errors(l)) &
                   " errors";
            assert Checked(l) >= Base_v(l) + Words_c
                report "FAIL: lane " & integer'image(l) & " too few words in near-end serial loopback"
                severity error;
            assert Errors(l) = 0
                report "FAIL: lane " & integer'image(l) & " errors in near-end serial loopback"
                severity error;
        end loop;

        -- TC-PA-06: PRBS-31 generator and checker of every channel with the external loopback (bypassing
        -- 8B/10B): lock, no error, bit errors on one line counted on that lane only, a checker with another
        -- pattern counts errors. The transceiver model does not insert the forced error of the generator
        -- (TXPRBSFORCEERR); the forced error is tested on the hardware.
        CheckEn    <= '0';
        NearLb     <= (others => '0');
        ExtLoop    <= true;
        PrbsTxSel  <= x"5555";
        PrbsRxSel  <= x"5555";
        wait for 10 us;
        wait until rising_edge(LaneClk);
        PrbsCntRst <= (others => '1');
        wait until rising_edge(LaneClk);
        PrbsCntRst <= (others => '0');
        wait until PrbsLocked = "1111" for 20 us;
        report "PRBS-31 checkers locked: " & to_string(PrbsLocked) & " at " & time'image(now);
        assert PrbsLocked = "1111"
            report "FAIL: PRBS checkers not locked"
            severity error;
        PrbsCount  <= true;
        wait for 5 us;

        for l in 0 to Lanes_c-1 loop
            assert PrbsErrCnt(l) = 0
                report "FAIL: lane " & integer'image(l) & " PRBS errors without forced error"
                severity error;
        end loop;

        -- Bit errors: the line of one lane is inverted for 1 ns (about six bits)
        for l in 0 to Lanes_c-1 loop
            Base_v     := PrbsErrCnt;
            LineInv(l) <= '1';
            wait for 1 ns;
            LineInv(l) <= '0';
            wait for 2 us;

            for k in 0 to Lanes_c-1 loop
                if k = l then
                    report "Lane " & integer'image(l) & ": " & integer'image(PrbsErrCnt(k) - Base_v(k)) &
                           " word(s) with error after bit errors on the line";
                    assert PrbsErrCnt(k) > Base_v(k)
                        report "FAIL: bit errors of lane " & integer'image(l) & " not detected"
                        severity error;
                    assert PrbsLocked(k) = '1'
                        report "FAIL: PRBS checker of lane " & integer'image(l) & " lost lock"
                        severity error;
                else
                    assert PrbsErrCnt(k) = Base_v(k)
                        report "FAIL: bit errors of lane " & integer'image(l) & " seen on lane " &
                               integer'image(k)
                        severity error;
                end if;
            end loop;

        end loop;

        -- After the bit errors, no further error
        Base_v := PrbsErrCnt;
        wait for 5 us;

        for l in 0 to Lanes_c-1 loop
            assert PrbsErrCnt(l) = Base_v(l)
                report "FAIL: lane " & integer'image(l) & " PRBS errors after the bit errors"
                severity error;
        end loop;

        -- Checker of lane 0 set to PRBS-7 while PRBS-31 is received: errors
        Base_v                := PrbsErrCnt;
        PrbsRxSel(3 downto 0) <= x"1";
        wait for 5 us;
        report "Lane 0 with PRBS-7 checker on PRBS-31: " & integer'image(PrbsErrCnt(0) - Base_v(0)) &
               " words with errors";
        assert PrbsErrCnt(0) > Base_v(0)
            report "FAIL: pattern mismatch not detected"
            severity error;

        report "Simulation done at " & time'image(now);
        finish;
    end process;

    -- PRBS checker errors per lane (words with at least one error)
    p_prbs_cnt : process (LaneClk) is
    begin
        if rising_edge(LaneClk) then

            for l in 0 to Lanes_c-1 loop
                if PrbsCount and PrbsErr(l) = '1' then
                    PrbsErrCnt(l) <= PrbsErrCnt(l) + 1;
                end if;
            end loop;

        end if;
    end process;

    -- External loopback of the serial lines (a disconnected line is static, LineInv inverts a line)
    RxLineP <= (TxP xor LineInv) when ExtLoop else (others => '0');
    RxLineN <= (TxN xor LineInv) when ExtLoop else (others => '1');

    -----------------------------------------------------------------------------------------------
    -- Transmitters: per lane IDLE words, a SKIP word every 64 words, counting data words
    -----------------------------------------------------------------------------------------------
    p_tx : process (LaneClk) is
        variable Cnt_v : natural := 0;
    begin
        if rising_edge(LaneClk) then
            Cnt_v := Cnt_v + 1;

            for l in 0 to Lanes_c-1 loop
                if Cnt_v mod 64 = 0 then
                    TxData(32*l+31 downto 32*l) <= WordSkip_c;
                    TxK(4*l+3 downto 4*l)       <= "0001";
                elsif Cnt_v mod 8 = 0 then
                    TxData(32*l+31 downto 32*l) <= WordIdle_c;
                    TxK(4*l+3 downto 4*l)       <= "0001";
                else
                    TxData(32*l+31 downto 32*l) <= std_logic_vector(to_unsigned(l, 8)) &
                                                   std_logic_vector(to_unsigned(Cnt_v mod 2**24, 24));
                    TxK(4*l+3 downto 4*l)       <= "0000";
                end if;
            end loop;

        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Receivers: data words count up (gaps where IDLE or SKIP words were sent), comma words carry
    -- the K flag of character 0 only, no code or disparity error
    -----------------------------------------------------------------------------------------------
    g_rx : for l in 0 to Lanes_c-1 generate

        p_rx : process (LaneClk) is
            variable Last_v : integer := -1;
            variable Word_v : std_logic_vector(31 downto 0);
            variable K_v    : std_logic_vector(3 downto 0);
            variable Val_v  : integer;
        begin
            if rising_edge(LaneClk) then
                Word_v := RxData(32*l+31 downto 32*l);
                K_v    := RxK(4*l+3 downto 4*l);
                if CheckEn = '0' then
                    Last_v := -1;
                elsif RxValid(l) = '1' and Aligned(l) = '1' then
                    if RxCodeErr(4*l+3 downto 4*l) /= "0000" or RxDispErr(4*l+3 downto 4*l) /= "0000" then
                        if Last_v >= 0 then
                            Errors(l) <= Errors(l) + 1;
                            report "Lane " & integer'image(l) & ": code or disparity error" severity warning;
                        end if;
                    elsif K_v = "0000" then
                        if Word_v(31 downto 24) /= std_logic_vector(to_unsigned(l, 8)) then
                            if Last_v >= 0 then
                                Errors(l) <= Errors(l) + 1;
                                report "Lane " & integer'image(l) & ": data word of another lane" severity warning;
                            end if;
                        else
                            Val_v := to_integer(unsigned(Word_v(23 downto 0)));
                            if Last_v >= 0 then
                                if Val_v <= Last_v or Val_v > Last_v + 2 then
                                    Errors(l) <= Errors(l) + 1;
                                    report "Lane " & integer'image(l) & ": data word " & integer'image(Val_v) &
                                           " after " & integer'image(Last_v) severity warning;
                                end if;
                                Checked(l) <= Checked(l) + 1;
                            end if;
                            Last_v := Val_v;
                        end if;
                    elsif K_v = "0001" then
                        if Word_v /= WordIdle_c and Word_v /= WordSkip_c and Last_v >= 0 then
                            Errors(l) <= Errors(l) + 1;
                            report "Lane " & integer'image(l) & ": unknown control word" severity warning;
                        end if;
                    elsif Last_v >= 0 then
                        Errors(l) <= Errors(l) + 1;
                        report "Lane " & integer'image(l) & ": unexpected K flags" severity warning;
                    end if;
                end if;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- DUT with serial loopback
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_pa_gty
        generic map (
            NumLanes_g => Lanes_c
        )
        port map (
            FreeRunClk             => FreeRunClk,
            Rst                    => Rst,
            RefClk                 => RefClk,
            LaneClk                => LaneClk,
            LaneRst                => LaneRst,
            Gt_TxP                 => TxP,
            Gt_TxN                 => TxN,
            Gt_RxP                 => RxLineP,
            Gt_RxN                 => RxLineN,
            PhyTx_Data             => TxData,
            PhyTx_K                => TxK,
            PhyRx_Data             => RxData,
            PhyRx_K                => RxK,
            PhyRx_CodeErr          => RxCodeErr,
            PhyRx_DispErr          => RxDispErr,
            PhyRx_Valid            => RxValid,
            Phy_TxEnable           => (others => '1'),
            Phy_RxEnable           => (others => '1'),
            Phy_CdrEnable          => (others => '1'),
            Phy_RxInvert           => (others => '0'),
            Phy_NoSignal           => NoSignal,
            Stat_TxReady           => TxReady,
            Stat_RxReady           => RxReady,
            Stat_Aligned           => Aligned,
            Stat_RxBufErr          => RxBufErr,
            Stat_ClkCor            => open,
            Phy_SerialNearLoopback => NearLb,
            Phy_PrbsTxSel          => PrbsTxSel,
            Phy_PrbsRxSel          => PrbsRxSel,
            Phy_PrbsForceErr       => PrbsForce,
            Phy_PrbsCntReset       => PrbsCntRst,
            Phy_PrbsErr            => PrbsErr,
            Phy_PrbsLocked         => PrbsLocked
        );

end architecture;
