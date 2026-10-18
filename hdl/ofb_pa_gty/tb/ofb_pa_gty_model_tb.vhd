---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the behavioural model of ofb_pa_gty (architecture mdl): two models A and B
-- connected pin to pin with 1 to 4 lanes. Each end sends per lane numbered data words, SKIP words
-- and IDLE words (or a PRBS pattern); each end checks the order of the received data words, the
-- error flags and the clock corrections. The reference clocks of the two ends can differ (ppm).
--
-- Documentation: hdl/ofb_pa_gty/docs/verification_plan.md

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
    use work.ofb_tb_pkg.all;
    use work.ofb_pa_model_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_model_tb is
    generic (
        runner_cfg : string;
        Lanes_g    : positive range 1 to 4 := 1;
        PpmB_g     : integer               := 0 -- reference clock of B against A
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_model_tb is

    constant N_c        : positive := Lanes_g;
    constant RefHalf_c  : time     := 3200 ps;
    constant FreeHalf_c : time     := 5 ns;
    constant RstCyc_c   : positive := 10;

    type LaneVec_t is array (0 to 1) of std_logic_vector(N_c-1 downto 0);
    type Data_t is array (0 to 1) of std_logic_vector(32*N_c-1 downto 0);
    type K_t is array (0 to 1) of std_logic_vector(4*N_c-1 downto 0);
    type Sel_t is array (0 to 1) of std_logic_vector(4*N_c-1 downto 0);
    type Sl_t is array (0 to 1) of std_logic;
    type LaneCount_t is array (0 to 3) of natural;
    type Count_t is array (0 to 1) of LaneCount_t; -- per end: one driver per end

    signal RefClk  : Sl_t      := (others => '0');
    signal FreeClk : std_logic := '0';
    signal Rst     : std_logic := '1';
    signal LaneClk : Sl_t;
    signal LaneRst : Sl_t;
    signal TxP     : LaneVec_t;
    signal TxN     : LaneVec_t;
    signal TxData  : Data_t    := (others => (others => '0'));
    signal TxK     : K_t       := (others => (others => '0'));
    signal RxData  : Data_t;
    signal RxK     : K_t;
    signal RxCode  : K_t;
    signal RxDisp  : K_t;
    signal RxVld   : LaneVec_t;

    -- Line control per end and lane
    signal TxEn      : LaneVec_t := (others => (others => '1'));
    signal RxEn      : LaneVec_t := (others => (others => '1'));
    signal CdrEn     : LaneVec_t := (others => (others => '1'));
    signal RxInv     : LaneVec_t := (others => (others => '0'));
    signal NearLb    : LaneVec_t := (others => (others => '0'));
    signal FarLb     : LaneVec_t := (others => (others => '0'));
    signal NoSig     : LaneVec_t;
    signal PrbsTx    : Sel_t     := (others => (others => '0'));
    signal PrbsRx    : Sel_t     := (others => (others => '0'));
    signal PrbsForce : LaneVec_t := (others => (others => '0'));
    signal PrbsRst   : LaneVec_t := (others => (others => '0'));
    signal PrbsErr   : LaneVec_t;
    signal PrbsLock  : LaneVec_t;
    signal TxRdy     : Sl_t;
    signal RxRdy     : Sl_t;
    signal Aligned   : LaneVec_t;
    signal BufErr    : LaneVec_t;
    signal ClkCor    : LaneVec_t;

    -- Generator: SKIP words on (every 8th word), sources of the checked data words (loopback: own end)
    signal SkipOn  : boolean   := true;
    signal OwnData : LaneVec_t := (others => (others => '0'));

    -- Checker counts per end and lane, cleared by an increment of ClrReq
    signal ClrReq   : natural := 0;
    signal Good     : Count_t := (others => (others => 0)); -- data words in order
    signal Bad      : Count_t := (others => (others => 0)); -- data words out of order or of the wrong source
    signal ErrWords : Count_t := (others => (others => 0)); -- words with a code or disparity error
    signal Cors     : Count_t := (others => (others => 0)); -- clock corrections
    signal BufErrs  : Count_t := (others => (others => 0));
    signal PrbsErrs : Count_t := (others => (others => 0));

    -- LaneClk edges at which an output of the lane clock domain changed in the same delta cycle, and
    -- edges after which the received data changed (proof that the monitor sees the outputs)
    type EndCount_t is array (0 to 1) of natural;

    signal SameDelta : EndCount_t := (others => 0);
    signal DataEdges : EndCount_t := (others => 0);

    -- Reset of one end only, in addition to Rst
    signal RstEnd : Sl_t := (others => '0');

    -- Event times of the reset sequence of A: first LaneClk edge, release of Rst, first LaneClk edge after a stop
    signal ClkStart   : time := 0 fs;
    signal RstRel     : time := 0 fs;
    signal ClkRestart : time := 0 fs;

begin

    RefClk(0) <= not RefClk(0) after RefHalf_c;
    RefClk(1) <= not RefClk(1) after RefHalf_c * (1.0 + real(PpmB_g) * 1.0e-6);
    FreeClk   <= not FreeClk after FreeHalf_c;

    -----------------------------------------------------------------------------------------------
    -- Two models, pins crossed
    -----------------------------------------------------------------------------------------------
    g_end : for e in 0 to 1 generate

        i_pa : entity work.ofb_pa_gty(mdl)
            generic map (
                NumLanes_g       => N_c,
                RstPulseCycles_g => RstCyc_c,
                ModelIdx_g       => e
            )
            port map (
                FreeRunClk             => FreeClk,
                Rst                    => Rst or RstEnd(e),
                RefClk                 => RefClk(e),
                LaneClk                => LaneClk(e),
                LaneRst                => LaneRst(e),
                Gt_TxP                 => TxP(e),
                Gt_TxN                 => TxN(e),
                Gt_RxP                 => TxP(1 - e),
                Gt_RxN                 => TxN(1 - e),
                PhyTx_Data             => TxData(e),
                PhyTx_K                => TxK(e),
                PhyRx_Data             => RxData(e),
                PhyRx_K                => RxK(e),
                PhyRx_CodeErr          => RxCode(e),
                PhyRx_DispErr          => RxDisp(e),
                PhyRx_Valid            => RxVld(e),
                Phy_TxEnable           => TxEn(e),
                Phy_RxEnable           => RxEn(e),
                Phy_CdrEnable          => CdrEn(e),
                Phy_RxInvert           => RxInv(e),
                Phy_NoSignal           => NoSig(e),
                Phy_SerialNearLoopback => NearLb(e),
                Phy_SerialFarLoopback  => FarLb(e),
                Phy_PrbsTxSel          => PrbsTx(e),
                Phy_PrbsRxSel          => PrbsRx(e),
                Phy_PrbsForceErr       => PrbsForce(e),
                Phy_PrbsCntReset       => PrbsRst(e),
                Phy_PrbsErr            => PrbsErr(e),
                Phy_PrbsLocked         => PrbsLock(e),
                Stat_TxReady           => TxRdy(e),
                Stat_RxReady           => RxRdy(e),
                Stat_Aligned           => Aligned(e),
                Stat_RxBufErr          => BufErr(e),
                Stat_ClkCor            => ClkCor(e)
            );

        -- Generator per lane: SKIP word every 8th word, IDLE word every 32nd, else data words with
        -- the sequence number in bits 31:16, the end in bits 15:8 and the lane in bits 7:0
        p_gen : process (LaneClk(e)) is
            variable Cyc_v : natural := 0;
            type     Seq_t is array (0 to 3) of natural;

            variable Seq_v : Seq_t := (others => 0);
        begin
            if rising_edge(LaneClk(e)) then
                Cyc_v := Cyc_v + 1;

                for l in 0 to N_c-1 loop
                    if Cyc_v mod 8 = 0 and SkipOn then
                        TxData(e)(32*l+31 downto 32*l) <= WordSkip_c;
                        TxK(e)(4*l+3 downto 4*l)       <= "0001";
                    elsif Cyc_v mod 32 = 1 then
                        TxData(e)(32*l+31 downto 32*l) <= WordIdle_c;
                        TxK(e)(4*l+3 downto 4*l)       <= "0001";
                    else
                        Seq_v(l)                       := (Seq_v(l) + 1) mod 65536;
                        TxData(e)(32*l+31 downto 32*l) <= std_logic_vector(to_unsigned(Seq_v(l), 16)) &
                                                          std_logic_vector(to_unsigned(e, 8)) &
                                                          std_logic_vector(to_unsigned(l, 8));
                        TxK(e)(4*l+3 downto 4*l)       <= "0000";
                    end if;
                end loop;

            end if;
        end process;

        -- Outputs of the lane clock domain change after the edge of the LaneClk port, never in its delta
        -- cycle: a design on LaneClk samples the values of the previous edge (PA-MD-11)
        p_delta : process is
        begin
            wait until rising_edge(LaneClk(e));
            if RxData(e)'event or RxK(e)'event or RxCode(e)'event or RxDisp(e)'event or RxVld(e)'event or
               NoSig(e)'event or PrbsErr(e)'event or PrbsLock(e)'event or TxRdy(e)'event or RxRdy(e)'event or
               LaneRst(e)'event or Aligned(e)'event or BufErr(e)'event or ClkCor(e)'event then
                SameDelta(e) <= SameDelta(e) + 1;
            end if;
            wait on RxData(e), LaneClk(e);
            if RxData(e)'event and LaneClk(e) = '1' then
                DataEdges(e) <= DataEdges(e) + 1;
            end if;
        end process;

        -- Checker per lane: data words of the source end in order (sequence + 1)
        p_chk : process (LaneClk(e)) is
            type Seq_t is array (0 to 3) of integer;

            variable Prev_v : Seq_t   := (others => -1);
            variable Seq_v  : natural;
            variable Src_v  : natural;
            variable Clr_v  : natural := 0;
            variable Word_v : std_logic_vector(31 downto 0);
        begin
            if rising_edge(LaneClk(e)) then
                if ClrReq /= Clr_v then
                    Clr_v := ClrReq;

                    for l in 0 to 3 loop
                        Good(e)(l)     <= 0;
                        Bad(e)(l)      <= 0;
                        ErrWords(e)(l) <= 0;
                        Cors(e)(l)     <= 0;
                        BufErrs(e)(l)  <= 0;
                        PrbsErrs(e)(l) <= 0;
                        Prev_v(l)      := -1;
                    end loop;

                else

                    for l in 0 to N_c-1 loop
                        if ClkCor(e)(l) = '1' then
                            Cors(e)(l) <= Cors(e)(l) + 1;
                        end if;
                        if BufErr(e)(l) = '1' then
                            BufErrs(e)(l) <= BufErrs(e)(l) + 1;
                        end if;
                        if PrbsErr(e)(l) = '1' then
                            PrbsErrs(e)(l) <= PrbsErrs(e)(l) + 1;
                        end if;
                        if RxVld(e)(l) = '1' then
                            Word_v := RxData(e)(32*l+31 downto 32*l);
                            if RxCode(e)(4*l+3 downto 4*l) /= "0000" or RxDisp(e)(4*l+3 downto 4*l) /= "0000" then
                                ErrWords(e)(l) <= ErrWords(e)(l) + 1;
                                Prev_v(l)      := -1;
                            elsif RxK(e)(4*l+3 downto 4*l) = "0000" then
                                Seq_v := to_integer(unsigned(Word_v(31 downto 16)));
                                Src_v := to_integer(unsigned(Word_v(15 downto 8)));
                                if (OwnData(e)(l) = '1' and Src_v /= e) or (OwnData(e)(l) = '0' and Src_v /= 1 - e) or
                                   to_integer(unsigned(Word_v(7 downto 0))) /= l or
                                   (Prev_v(l) >= 0 and Seq_v /= (Prev_v(l) + 1) mod 65536) then
                                    Bad(e)(l) <= Bad(e)(l) + 1;
                                else
                                    Good(e)(l) <= Good(e)(l) + 1;
                                end if;
                                Prev_v(l) := Seq_v;
                            end if;
                        end if;
                    end loop;

                end if;
            end if;
        end process;

    end generate;

    -- Reset sequence of A: first LaneClk edge
    p_clk_start : process is
    begin
        wait until Rst = '0';
        wait until rising_edge(FreeClk) and Rst = '0';
        RstRel   <= now;
        wait until rising_edge(LaneClk(0));
        ClkStart <= now;
        wait;
    end process;

    p_clk_restart : process is
        variable Last_v : time := 0 fs;
    begin
        wait until rising_edge(LaneClk(0));
        if Last_v > 0 fs and now - Last_v > 1 us then
            ClkRestart <= now;
        end if;
        Last_v := now;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable T_v : time;

        procedure waitUs (n : natural) is
        begin
            wait for n * 1 us;
        end procedure;

        -- Reset of A while its reset sequence runs (TC-PA-10): a first reset request, a second one offset after the end
        -- of the first stretched reset, in the given phase (1: reset done of the previous start shown, 2: before
        -- LaneClk, 3: before TX ready, 4: before RX ready). The sequence starts again from its top: LaneClk, TX ready
        -- and RX ready follow the end of the second stretched reset with the full delays
        procedure resetInPhase (offset : time; phase : positive; name : string) is
            variable T1_v : time;
            variable T2_v : time;
            variable Tx_v : time;
        begin
            RstEnd(0) <= '1';
            wait for 100 ns;
            RstEnd(0) <= '0';
            T1_v      := now;
            wait for RstCyc_c * 2 * FreeHalf_c + offset;

            case phase is
                when 1 | 2 =>
                    check_value(ClkRestart < T1_v, error, name & ": LaneClk of A still stopped");
                when 3 =>
                    check_value(ClkRestart > T1_v and TxRdy(0) = '0', error, name & ": LaneClk of A runs, TX ready 0");
                when others =>
                    check_value(TxRdy(0) = '1' and RxRdy(0) = '0', error, name & ": TX ready of A 1, RX ready 0");
            end case;

            RstEnd(0) <= '1';
            wait for 100 ns;
            RstEnd(0) <= '0';
            T2_v      := now;
            wait until TxRdy(0) = '1' for RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay + 1 us;
            Tx_v      := now;
            log(ID_LOG_HDR, name & ": LaneClk again " & to_string(ClkRestart - T2_v) & ", TX ready " &
                to_string(Tx_v - T2_v) & " after the second reset request");
            check_value(ClkRestart - T2_v >= RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.ClkDelay and
                        ClkRestart - T2_v < (RstCyc_c + 2) * 2 * FreeHalf_c + PaModelCtrlDefault_c.ClkDelay + 7 ns,
                        error, name & ": LaneClk restarts ClkDelay after the end of the second stretched reset");
            check_value(TxRdy(0) = '1' and
                        Tx_v - T2_v >= RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay and
                        Tx_v - T2_v < (RstCyc_c + 2) * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay + 20 ns,
                        error, name & ": TX ready TxReadyDelay after the end of the second stretched reset");
            wait until RxRdy(0) = '1' for PaModelCtrlDefault_c.RxReadyDelay + 1 us;
            check_value(RxRdy(0) = '1' and now - Tx_v >= PaModelCtrlDefault_c.RxReadyDelay - 20 ns and
                        now - Tx_v < PaModelCtrlDefault_c.RxReadyDelay + 20 ns, error,
                        name & ": RX ready RxReadyDelay after TX ready");
        end procedure;

        procedure clearCounts is
        begin
            ClrReq <= ClrReq + 1;
            wait until rising_edge(LaneClk(0));
            wait until rising_edge(LaneClk(0));
            wait until rising_edge(LaneClk(1));
            wait until rising_edge(LaneClk(1));
        end procedure;

        -- Every lane of both ends received at least n data words in order, no error word
        procedure checkClean (n : natural; msg : string) is
        begin

            for e in 0 to 1 loop

                for l in 0 to N_c-1 loop
                    check_value(Good(e)(l) >= n, error, msg & ": data words at end " & to_string(e) & ", lane " &
                                to_string(l) & ": " & to_string(Good(e)(l)));
                    check_value(Bad(e)(l), 0, error, msg & ": words out of order at end " & to_string(e) &
                                ", lane " & to_string(l));
                    check_value(ErrWords(e)(l), 0, error, msg & ": error words at end " & to_string(e) & ", lane " &
                                to_string(l));
                    check_value(BufErrs(e)(l), 0, error, msg & ": buffer errors at end " & to_string(e) &
                                ", lane " & to_string(l));
                end loop;

            end loop;

        end procedure;

        -- Short reset sequence for the tests that do not check it
        procedure fastStart is
        begin

            for e in 0 to 1 loop
                PaModelCtrl(e).PowerUpTime  <= 0 ns;
                PaModelCtrl(e).TxDoneStale  <= 500 ns;
                PaModelCtrl(e).ClkDelay     <= 1 us;
                PaModelCtrl(e).TxReadyDelay <= 2 us;
                PaModelCtrl(e).RxReadyDelay <= 200 ns;
                PaModelCtrl(e).CdrLockTime  <= 500 ns;
                PaModelCtrl(e).NoSignalTime <= 2.1 us;
            end loop;

            wait for 1 ns;
            Rst <= '0';
            wait until RxRdy(0) = '1' and RxRdy(1) = '1' for 20 us;
            waitUs(5);
            clearCounts;
        end procedure;

        variable N_v : natural;
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);

        while test_suite loop

            -- TC-PA-10: reset sequence with the default times. Power-up: the stretched reset of B ends 5 us
            -- after that of A, both before PowerUpTime: LaneClk and TX ready of both ends follow PowerUpTime by
            -- ClkDelay and TxReadyDelay; the reset done of the previous start, 1 for TxDoneStale after the
            -- release, does not show as TX ready; the receivers align CdrLockTime after the signal of the far end
            -- starts. Then data words in order on every lane, and a reset of A in operation: the sequence starts
            -- at the end of its stretched reset, LaneClk restarts after ClkDelay and TX ready follows after
            -- TxReadyDelay, although TxDoneStale lasts beyond ClkDelay (the reset done of the previous start ends
            -- when LaneClk starts)
            if run("test_link") then
                RstEnd(1) <= '1';
                wait for 100 ns;
                Rst       <= '0';
                wait for 5 us;
                RstEnd(1) <= '0';
                wait until TxRdy(0) = '1' or TxRdy(1) = '1' for PaModelCtrlDefault_c.TxDoneStale;
                check_value(TxRdy(0) = '0' and TxRdy(1) = '0', error,
                            "No TX ready from the reset done of the previous start (TxDoneStale)");
                wait until TxRdy(0) = '1' for 100 us;
                T_v       := now;
                log(ID_LOG_HDR, "Power-up: LaneClk at " & to_string(ClkStart) & ", TX ready at " & to_string(T_v));
                check_value(ClkStart >= PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.ClkDelay and
                            ClkStart < PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.ClkDelay + 7 ns,
                            error, "LaneClk starts ClkDelay after PowerUpTime");
                check_value(T_v >= PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.TxReadyDelay and
                            T_v < PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.TxReadyDelay + 20 ns,
                            error, "TX ready TxReadyDelay after PowerUpTime");
                if TxRdy(1) /= '1' then
                    wait until TxRdy(1) = '1' for 100 ns;
                end if;
                check_value(TxRdy(1) = '1' and now - T_v < 20 ns, error,
                            "TX ready of B at the same time, its stretched reset ended 5 us later");
                wait until LaneRst(0) = '0' for 50 ns;
                check_value(LaneRst(0), '0', error, "LaneRst released after TX ready");
                -- Phy_NoSignal (NoSignalSequence): 1 after TX ready, 0 at both ends NoSignalTime after the start of
                -- the sequence
                check_value(NoSig(0) = (N_c-1 downto 0 => '1') and NoSig(1) = (N_c-1 downto 0 => '1'), error,
                            "No signal at both ends after TX ready");
                wait until NoSig(0) = (N_c-1 downto 0 => '0') for PaModelCtrlDefault_c.NoSignalTime;
                check_value(now >= PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.NoSignalTime and
                            now < PaModelCtrlDefault_c.PowerUpTime + PaModelCtrlDefault_c.NoSignalTime + 7 ns,
                            error, "No signal falls at A NoSignalTime after the start of the sequence");
                wait for 7 ns;
                check_value(NoSig(1), (N_c-1 downto 0 => '0'), error, "No signal falls at B at the same time");
                wait until RxRdy(0) = '1' for PaModelCtrlDefault_c.RxReadyDelay + 1 us;
                check_value(now - T_v >= PaModelCtrlDefault_c.RxReadyDelay - 20 ns, error,
                            "RX ready after RxReadyDelay");
                wait until Aligned(1) = (N_c-1 downto 0 => '1') for PaModelCtrlDefault_c.CdrLockTime + 2 us;
                log(ID_LOG_HDR, "Lanes of B aligned " & to_string(now - T_v) & " after TX ready");
                check_value(Aligned(1), (N_c-1 downto 0 => '1'), error, "Every lane aligned at B");
                check_value(now - T_v >= PaModelCtrlDefault_c.CdrLockTime and
                            now - T_v < PaModelCtrlDefault_c.CdrLockTime + 1 us, error,
                            "Lanes of B aligned CdrLockTime after the signal of A starts");
                waitUs(5);
                check_value(NoSig(1), (N_c-1 downto 0 => '0'), error, "Signal on every lane at B");
                clearCounts;
                waitUs(20);
                checkClean(2000, "Link");
                check_value(DataEdges(0) > 1000 and DataEdges(1) > 1000, error, "Received data observed after the edges");
                check_value(SameDelta(0) + SameDelta(1), 0, error,
                            "No output changes in the delta cycle of the LaneClk edge");
                -- Reset of A in operation
                RstEnd(0) <= '1';
                wait for 100 ns;
                RstEnd(0) <= '0';
                T_v       := now;
                wait for 50 ns;
                check_value(TxRdy(0), '0', error, "TX ready of A falls with its reset");
                wait until TxRdy(0) = '1' for RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay + 1 us;
                log(ID_LOG_HDR, "Reset of A in operation: LaneClk again " & to_string(ClkRestart - T_v) &
                    ", TX ready " & to_string(now - T_v) & " after the reset request");
                check_value(ClkRestart - T_v >= RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.ClkDelay and
                            ClkRestart - T_v < (RstCyc_c + 2) * 2 * FreeHalf_c + PaModelCtrlDefault_c.ClkDelay + 7 ns,
                            error, "LaneClk restarts ClkDelay after the end of the stretched reset");
                check_value(TxRdy(0) = '1' and
                            now - T_v >= RstCyc_c * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay and
                            now - T_v < (RstCyc_c + 2) * 2 * FreeHalf_c + PaModelCtrlDefault_c.TxReadyDelay + 20 ns,
                            error, "TX ready of A TxReadyDelay after the end of the stretched reset");
                wait until Aligned(1) = (N_c-1 downto 0 => '1') for PaModelCtrlDefault_c.CdrLockTime + 3 us;
                check_value(Aligned(1), (N_c-1 downto 0 => '1'), error, "Every lane aligned at B after the reset of A");
                waitUs(5);
                clearCounts;
                waitUs(20);
                checkClean(2000, "Link after the reset of A");
                -- Resets of A during its reset sequence. In operation the reset done of the previous start lasts until
                -- LaneClk starts; a short TxDoneStale lets the sequence wait for LaneClk after it
                PaModelCtrl(0).TxDoneStale <= 1 us;
                resetInPhase(500 ns, 1, "Reset while the reset done of the previous start shows");
                resetInPhase(10 us, 2, "Reset before LaneClk starts");
                resetInPhase((PaModelCtrlDefault_c.ClkDelay + PaModelCtrlDefault_c.TxReadyDelay) / 2, 3,
                             "Reset before TX ready");
                resetInPhase(PaModelCtrlDefault_c.TxReadyDelay + PaModelCtrlDefault_c.RxReadyDelay / 2, 4,
                             "Reset before RX ready");
                PaModelCtrl(0).TxDoneStale <= PaModelCtrlDefault_c.TxDoneStale;
                wait until Aligned(1) = (N_c-1 downto 0 => '1') for PaModelCtrlDefault_c.CdrLockTime + 3 us;
                check_value(Aligned(1), (N_c-1 downto 0 => '1'), error,
                            "Every lane aligned at B after the resets during the sequence");
                waitUs(5);
                clearCounts;
                waitUs(20);
                checkClean(2000, "Link after the resets during the sequence");

            -- TC-PA-11: clock correction with different reference clocks (configurations ppm), no word
            -- lost or repeated
            elsif run("test_clock_correction") then
                fastStart;
                waitUs(300);
                checkClean(30000, "Clock correction");

                for e in 0 to 1 loop

                    for l in 0 to N_c-1 loop
                        if PpmB_g /= 0 then
                            check_value(Cors(e)(l) > 0, error, "Clock corrections at end " & to_string(e) & ", lane " &
                                        to_string(l));
                        end if;
                    end loop;

                end loop;

            -- TC-PA-12: skew between the lanes, and a shift of the bit stream during traffic: the
            -- receiver aligns again on the next comma
            elsif run("test_align") then

                for l in 0 to N_c-1 loop
                    PaModelCtrl(0).Lane(l).SkewUi <= 7 * l + 3;
                end loop;

                fastStart;
                waitUs(10);
                checkClean(1000, "Skew between lanes");
                PaModelCtrl(0).Lane(0).SkewUi <= 3 + 40 + 5;
                waitUs(2);
                check_value(Aligned(1)(0), '1', error, "Lane 0 of B aligned again");
                clearCounts;
                waitUs(10);
                checkClean(1000, "After the shift");

            -- TC-PA-13: crossed pair: errors at B until B inverts the received bits
            elsif run("test_invert") then
                PaModelCtrl(0).Lane(0).TxInvert <= true;
                fastStart;
                waitUs(5);
                check_value(ErrWords(1)(0) > 0 or Bad(1)(0) > 0 or Good(1)(0) = 0, error,
                            "No correct words at B without RX inversion");
                RxInv(1)(0)                     <= '1';
                waitUs(3);
                clearCounts;
                waitUs(10);
                checkClean(1000, "Inverted pair and RX inversion");

            -- TC-PA-14: bit errors: single errors, a burst and a bit error rate give words with code or
            -- disparity errors at B
            elsif run("test_errors") then
                fastStart;

                for i in 1 to 10 loop
                    PaModelCtrl(0).Lane(0).ErrReq <= i;
                    waitUs(1);
                end loop;

                check_value(ErrWords(1)(0) >= 10 and ErrWords(1)(0) <= 30, error,
                            "Error words for 10 bit errors: " & to_string(ErrWords(1)(0)));
                clearCounts;
                PaModelCtrl(0).Lane(0).BurstLen <= 20;
                PaModelCtrl(0).Lane(0).BurstReq <= 1;
                waitUs(2);
                check_value(ErrWords(1)(0) >= 1, error, "Error words for a burst");
                waitUs(3);
                clearCounts;
                -- One error every 100000 bits: about 62 in 1 ms of 6.25 Gbit/s
                PaModelCtrl(0).Lane(0).ErrEvery <= 100000;
                wait for 1 ms;
                N_v                             := ErrWords(1)(0);
                -- A bit error gives one to three error words (running disparity)
                check_value(N_v >= 50 and N_v <= 200, error, "Error words at a bit error rate of 1e-5: " &
                            to_string(N_v));
                PaModelCtrl(0).Lane(0).ErrEvery <= 0;
                waitUs(3);
                clearCounts;
                waitUs(10);
                checkClean(1000, "After the errors");

            -- TC-PA-15: electrical idle and disabled receivers: no signal after NoSignalDelay, no
            -- words, alignment again when the signal returns
            elsif run("test_idle") then
                PaModelCtrl(0).NoSignalMode <= NoSignalLine;
                PaModelCtrl(1).NoSignalMode <= NoSignalLine;
                fastStart;
                TxEn(0)(0)                  <= '0';
                wait until NoSig(1)(0) = '1' for 1 us;
                T_v                         := TxEn(0)(0)'last_event;
                check_value(NoSig(1)(0), '1', error, "No signal at B");
                check_value(T_v >= PaModelCtrlDefault_c.NoSignalDelay and T_v < PaModelCtrlDefault_c.NoSignalDelay + 50 ns,
                            error, "No signal after NoSignalDelay: " & to_string(T_v));
                check_value(Aligned(1)(0), '0', error, "Lane 0 of B not aligned");
                TxEn(0)(0)                  <= '1';
                waitUs(2);
                check_value(NoSig(1)(0), '0', error, "Signal at B again");
                PaModelCtrl(0).Lane(0).Idle <= true;
                waitUs(1);
                check_value(NoSig(1)(0), '1', error, "No signal at B with the idle control");
                PaModelCtrl(0).Lane(0).Idle <= false;
                RxEn(1)(0)                  <= '0';
                waitUs(2);
                clearCounts;
                waitUs(5);
                check_value(Good(1)(0), 0, error, "No words at B with the receiver disabled");
                RxEn(1)(0)                  <= '1';
                CdrEn(1)(0)                 <= '0';
                waitUs(2);
                clearCounts;
                waitUs(5);
                check_value(Good(1)(0), 0, error, "No words at B with the CDR disabled");
                CdrEn(1)(0)                 <= '1';
                waitUs(3);
                clearCounts;
                waitUs(10);
                checkClean(1000, "Signal back");
                -- NoSignalSequence: the line is ignored after NoSignalTime
                PaModelCtrl(1).NoSignalMode <= NoSignalSequence;
                waitUs(1);
                check_value(NoSig(1)(0), '0', error, "Sequence mode: signal at B");
                clearCounts;
                TxEn(0)(0)                  <= '0';
                waitUs(2);
                check_value(NoSig(1)(0), '0', error, "Sequence mode: line ignored, A off");
                -- Idle line: 13 words with code errors, then words without errors (no lane words)
                check_value(ErrWords(1)(0), 13, error, "Sequence mode: words with code errors at B, line idle");
                check_value(Good(1)(0) + Bad(1)(0) > 200, error, "Sequence mode: words without errors after them");
                check_value(Aligned(1)(0), '0', error, "Sequence mode: lane 0 of B not aligned");
                TxEn(0)(0) <= '1';
                waitUs(3);
                clearCounts;
                waitUs(10);
                checkClean(1000, "Sequence mode: signal back");

            -- TC-PA-16: serial loopbacks: near-end at A (A receives its own words), far-end at B (A
            -- receives its own words through B)
            elsif run("test_loopback") then
                fastStart;
                NearLb(0)  <= (others => '1');
                OwnData(0) <= (others => '1');
                waitUs(3);
                clearCounts;
                waitUs(10);

                for l in 0 to N_c-1 loop
                    check_value(Good(0)(l) >= 1000 and Bad(0)(l) = 0 and ErrWords(0)(l) = 0, error,
                                "Near-end loopback of lane " & to_string(l));
                end loop;

                NearLb(0) <= (others => '0');
                FarLb(1)  <= (others => '1');
                waitUs(3);
                clearCounts;
                waitUs(10);

                for l in 0 to N_c-1 loop
                    check_value(Good(0)(l) >= 1000 and Bad(0)(l) = 0 and ErrWords(0)(l) = 0, error,
                                "Far-end loopback of lane " & to_string(l));
                end loop;

            -- TC-PA-17: PRBS generator and checker for every pattern: lock, no error, a forced error is
            -- counted once, the checker reset restarts the lock
            elsif run("test_prbs") then
                fastStart;

                for p in 1 to 5 loop
                    PrbsTx(0) <= (others => '0');
                    PrbsRx(1) <= (others => '0');

                    for l in 0 to N_c-1 loop
                        PrbsTx(0)(4*l+3 downto 4*l) <= std_logic_vector(to_unsigned(p, 4));
                        PrbsRx(1)(4*l+3 downto 4*l) <= std_logic_vector(to_unsigned(p, 4));
                    end loop;

                    waitUs(2);
                    check_value(PrbsLock(1), (N_c-1 downto 0 => '1'), error, "PRBS " & to_string(p) & " locked");
                    clearCounts;
                    waitUs(5);

                    for l in 0 to N_c-1 loop
                        check_value(PrbsErrs(1)(l), 0, error, "No PRBS error, pattern " & to_string(p));
                    end loop;

                    wait until rising_edge(LaneClk(0));
                    PrbsForce(0) <= (others => '1');
                    wait until rising_edge(LaneClk(0));
                    PrbsForce(0) <= (others => '0');
                    waitUs(1);

                    -- The self-synchronising checker sees a wrong bit at its taps a and b as well
                    for l in 0 to N_c-1 loop
                        check_value(PrbsErrs(1)(l) >= 1 and PrbsErrs(1)(l) <= 3, error,
                                    "Forced error counted, pattern " & to_string(p) & ": " & to_string(PrbsErrs(1)(l)));
                    end loop;

                    wait until rising_edge(LaneClk(1));
                    PrbsRst(1) <= (others => '1');
                    wait until rising_edge(LaneClk(1));
                    PrbsRst(1) <= (others => '0');
                    waitUs(1);
                    check_value(PrbsLock(1), (N_c-1 downto 0 => '1'), error, "PRBS " & to_string(p) &
                                " locked after the checker reset");
                end loop;

            -- TC-PA-18: receive buffer error: without SKIP words the buffer of the faster end overflows
            -- or the slower runs empty (configurations ppm)
            elsif run("test_buffer") then
                fastStart;
                SkipOn <= false;
                wait for 1 ms;
                N_v    := 0;

                for e in 0 to 1 loop

                    for l in 0 to N_c-1 loop
                        N_v := N_v + BufErrs(e)(l);
                    end loop;

                end loop;

                if PpmB_g /= 0 then
                    check_value(N_v > 0, error, "Receive buffer errors without SKIP words");
                else
                    check_value(N_v, 0, error, "No receive buffer error with equal clocks");
                end if;
            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

end architecture;
