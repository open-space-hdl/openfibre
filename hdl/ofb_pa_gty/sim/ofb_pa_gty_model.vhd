---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Architecture mdl of ofb_pa_gty: behavioural model of the Physical adapter for GHDL and QuestaSim
-- (simulation only). The serial pins carry the 8B/10B bit stream at the line rate (LaneClk / 40 per
-- bit, LaneClk = RefClk); the receiver decodes the bit stream with its own unit interval, aligns on
-- commas and passes the words through a receive buffer with clock correction into LaneClk.
-- Channel effects and the times of the reset sequence come from PaModelCtrl(ModelIdx_g)
-- (ofb_pa_model_pkg).
--
-- The reset sequencer of every lane is the same entity as in struct (ofb_pa_gty_lane_rst); the model answers
-- its channel resets: the entire receiver reset (GTRXRESET in sequential mode) clears the receiver and
-- returns RXRESETDONE after Lane(l).RxResetTime, the CDR reset relocks the receiver, the transmit buffer
-- reset clears the transmit buffer error.
--
-- What this model does NOT reproduce: analogue behaviour (equalisation, jitter), the lock process of
-- the PLL and the clock-data recovery (fixed delays instead), the power-up and DRP behaviour of the
-- transceiver, the reset of the transmit datapath of the quad on a far-end loopback change, the CDR
-- hold, the PCSRSVDIN bits, and the exact latency of the transceiver datapaths.
--
-- Documentation: hdl/ofb_pa_gty/docs/model.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_8b10b_pkg.all;
    use work.ofb_pa_model_pkg.all;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture mdl of ofb_pa_gty is

    constant N_c : positive := NumLanes_g;

    -- Receive buffer levels in words: output starts at Start_c, a SKIP word is removed above High_c and
    -- repeated below Low_c
    constant Start_c : positive := 16;
    constant High_c  : positive := 24;
    constant Low_c   : positive := 8;

    -- PRBS checker: correct bits in a row for the lock
    constant LockBits_c : positive := 64;

    -- NoSignalNever: words with code errors at the start of an idle period of the line (transceiver)
    constant IdleErrWords_c   : positive := 13;
    -- Reset window of the receive elastic buffer in struct (setup, pulse and hold: 152 cycles of FreeRunClk at
    -- 100 MHz) in cycles of LaneClk (PA-RS-03)
    constant BufWindowWords_c : positive := 238;

    type IntArray_t is array (0 to N_c-1) of natural;

    signal RstFree : std_logic                    := '1'; -- Rst stretched to RstPulseCycles_g cycles of FreeRunClk
    signal ClkRun  : boolean                      := false;
    signal TxRdy   : std_logic                    := '0';
    signal TxRdyF  : std_logic                    := '0'; -- Stat_TxReady: register of FreeRunClk
    signal TxDone  : std_logic                    := '0'; -- transmit reset done, with the state before the reset
    signal TxArmed : std_logic                    := '0'; -- TxDone was 0 since the release of the reset
    signal LaneRsr : std_logic_vector(1 downto 0) := "11"; -- LaneRst: set without a LaneClk edge
    signal RxRdy   : std_logic                    := '0';
    signal Ui      : time                         := 160 ps; -- unit interval: RefClk period / 40

    -- Lines: '0' and '1' are the bit value on P, 'Z' is electrical idle (P = N)
    signal TxLine : std_logic_vector(N_c-1 downto 0) := (others => 'Z'); -- transmitter
    signal RxLine : std_logic_vector(N_c-1 downto 0) := (others => 'Z'); -- receiver input (copy for the status)

    -- Receiver state shared with the LaneClk side
    signal Aligned   : std_logic_vector(N_c-1 downto 0) := (others => '0');
    signal PrbsErrs  : IntArray_t                       := (others => 0); -- bit errors seen while locked
    signal PrbsLock  : std_logic_vector(N_c-1 downto 0) := (others => '0');
    signal RxOverrun : IntArray_t                       := (others => 0); -- words lost (buffer full)
    signal PrbsRst   : IntArray_t                       := (others => 0); -- PRBS checker resets requested

    shared variable RxBuf_v : PaModelBuffer_t;

    -- Reset sequencer of every lane and the channel reset ports it drives (FreeRunClk)
    type Mode2_t is array (0 to N_c-1) of std_logic_vector(1 downto 0);
    type ReqCnts_t is array (0 to N_c-1) of natural range 0 to 15;

    signal FullReqL  : std_logic_vector(N_c-1 downto 0) := (others => '0'); -- request, stretched in LaneClk
    signal FullCnt   : ReqCnts_t                        := (others => 0);
    signal CdrEnLast : std_logic_vector(N_c-1 downto 0) := (others => '0');
    signal GtRxRst   : std_logic_vector(N_c-1 downto 0);
    signal GtRxMode  : Mode2_t;
    signal GtCdrRst  : std_logic_vector(N_c-1 downto 0);
    signal GtTxRst   : std_logic_vector(N_c-1 downto 0);
    signal RxRstDone : std_logic_vector(N_c-1 downto 0) := (others => '0'); -- RXRESETDONE of the channel
    signal RxRstCnt  : IntArray_t                       := (others => 0);   -- receiver resets (relock)
    signal TxBufErr  : std_logic_vector(N_c-1 downto 0) := (others => '0'); -- TXBUFSTATUS[1]
    signal RxBusyF   : std_logic_vector(N_c-1 downto 0);
    signal DoneEvF   : std_logic_vector(N_c-1 downto 0);
    signal TimeoEvF  : std_logic_vector(N_c-1 downto 0);
    signal DoneTgl   : std_logic_vector(N_c-1 downto 0) := (others => '0');
    signal TimeoTgl  : std_logic_vector(N_c-1 downto 0) := (others => '0');

    -- PRBS taps (x^a + x^b + 1: bit n = bit n-a xor bit n-b) of the transceiver encoding 1 to 5
    type Taps_t is array (1 to 5) of natural;

    constant TapA_c : Taps_t := (7, 9, 15, 23, 31);
    constant TapB_c : Taps_t := (6, 5, 14, 18, 28);

    -- Encoder table, built once: index (running disparity, K flag, character)
    type EncTable_t is array (0 to 1, 0 to 1, 0 to 255) of Encoded_t;

    function buildEnc return EncTable_t is
        variable Tab_v  : EncTable_t;
        variable Char_v : Char_t;
        variable Rd_v   : std_logic;
    begin

        for r in 0 to 1 loop

            for c in 0 to 255 loop
                Char_v := std_logic_vector(to_unsigned(c, 8));
                if r = 0 then
                    Rd_v := '0';
                else
                    Rd_v := '1';
                end if;
                Tab_v(r, 0, c) := encode(Char_v, '0', Rd_v);
                -- Characters that are no K-code are sent as data characters
                if isKcode(Char_v) then
                    Tab_v(r, 1, c) := encode(Char_v, '1', Rd_v);
                else
                    Tab_v(r, 1, c) := Tab_v(r, 0, c);
                end if;
            end loop;

        end loop;

        return Tab_v;
    end function;

    constant Enc_c : EncTable_t := buildEnc;

    -- Decoder table, built once: index (running disparity, code with bit a in bit 0)
    type DecEntry_t is record
        Char    : Char_t;
        K       : std_logic;
        CodeErr : std_logic;
        DispErr : std_logic;
        Rd      : natural range 0 to 1;
        Comma   : boolean; -- K28.1, K28.5 or K28.7
    end record;

    type DecTable_t is array (0 to 1, 0 to 1023) of DecEntry_t;

    function buildDec return DecTable_t is
        variable Tab_v : DecTable_t;
        variable Dec_v : Decoded_t;
        variable Rd_v  : std_logic;
    begin

        for r in 0 to 1 loop

            for c in 0 to 1023 loop
                if r = 0 then
                    Rd_v := '0';
                else
                    Rd_v := '1';
                end if;
                Dec_v               := decode(std_logic_vector(to_unsigned(c, 10)), Rd_v);
                Tab_v(r, c).Char    := Dec_v.Char;
                Tab_v(r, c).K       := Dec_v.K;
                Tab_v(r, c).CodeErr := Dec_v.CodeErr;
                Tab_v(r, c).DispErr := Dec_v.DispErr;
                Tab_v(r, c).Rd      := 0;
                if Dec_v.Rd = '1' then
                    Tab_v(r, c).Rd := 1;
                end if;
                Tab_v(r, c).Comma := Dec_v.K = '1' and Dec_v.CodeErr = '0' and
                                     (Dec_v.Char = K28_5_c or Dec_v.Char = K28_7_c or Dec_v.Char = x"3C");
            end loop;

        end loop;

        return Tab_v;
    end function;

    constant Dec_c : DecTable_t := buildDec;

    function prbsSel (sel : std_logic_vector(3 downto 0)) return natural is
        variable S_v : natural;
    begin
        S_v := to_integer(unsigned(sel));
        if S_v >= 1 and S_v <= 5 then
            return S_v;
        end if;
        return 0;
    end function;

begin

    -----------------------------------------------------------------------------------------------
    -- Reset, clocks, ready
    -----------------------------------------------------------------------------------------------
    -- Asynchronous reset, released after RstPulseCycles_g cycles of FreeRunClk (as struct)
    p_rst : process (FreeRunClk, Rst) is
        variable Cnt_v : natural := 0;
    begin
        if Rst = '1' then
            RstFree <= '1';
            Cnt_v   := 0;
        elsif rising_edge(FreeRunClk) then
            if Cnt_v < RstPulseCycles_g then
                Cnt_v := Cnt_v + 1;
            else
                RstFree <= '0';
            end if;
        end if;
    end process;

    p_ui : process (RefClk) is
        variable Last_v : time := 0 fs;
    begin
        if rising_edge(RefClk) then
            if Last_v > 0 fs then
                Ui <= (now - Last_v) / 40;
            end if;
            Last_v := now;
        end if;
    end process;

    -- The reset sequence starts at the end of the stretched reset, not before PowerUpTime after the
    -- start of the simulation (the transceiver model completes its power-up first). LaneClk starts when
    -- the transmit PLL is locked (ClkDelay after the start), the transmitters are ready after
    -- TxReadyDelay, the receivers RxReadyDelay later; the transmit reset done shows the state before
    -- the reset for TxDoneStale after the release, as the reset controller of the wizard before its
    -- master reset starts, at the latest until LaneClk starts
    p_seq : process is
        variable Ctrl_v  : PaModelCtrl_t;
        variable Start_v : time;
        variable Stale_v : time;
    begin
        ClkRun <= false;
        TxRdy  <= '0';
        RxRdy  <= '0';
        if RstFree = '1' then
            wait until RstFree = '0';
        end if;
        Ctrl_v  := PaModelCtrl(ModelIdx_g);
        Start_v := maximum(now, Ctrl_v.PowerUpTime);
        Stale_v := minimum(now + Ctrl_v.TxDoneStale, Start_v + Ctrl_v.ClkDelay);
        -- Reset done of the previous start, until the master reset of the transceiver starts
        if Stale_v > now then
            TxDone <= '1';
            wait until RstFree = '1' for Stale_v - now;
        end if;
        TxDone <= '0';
        if RstFree = '0' then
            if Start_v + Ctrl_v.ClkDelay > now then
                wait until RstFree = '1' for Start_v + Ctrl_v.ClkDelay - now;
            end if;
            if RstFree = '0' then
                ClkRun <= true;
                if Start_v + Ctrl_v.TxReadyDelay > now then
                    wait until RstFree = '1' for Start_v + Ctrl_v.TxReadyDelay - now;
                end if;
                if RstFree = '0' then
                    TxRdy <= '1';
                    wait until RstFree = '1' for Ctrl_v.RxReadyDelay;
                    if RstFree = '0' then
                        RxRdy <= '1';
                        wait until RstFree = '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- The processes of the lane clock domain are clocked by the port itself: a design on LaneClk
    -- sees the edge in the same delta cycle as the model
    LaneClk <= RefClk when ClkRun else '0';

    -- Transmitters ready: a register of FreeRunClk, as the transmit reset done of the wizard, so that it
    -- falls while LaneClk stands still, and taken only after it was 0 once since the release of the
    -- reset (PA-ST-02, as struct)
    p_tx_ready : process (FreeRunClk) is
    begin
        if rising_edge(FreeRunClk) then
            if (TxDone or TxRdy) = '0' then
                TxArmed <= '1';
            end if;
            TxRdyF <= (TxDone or TxRdy) and TxArmed;
            if RstFree = '1' then
                TxArmed <= '0';
                TxRdyF  <= '0';
            end if;
        end if;
    end process;

    Stat_TxReady <= TxRdyF;

    -- Lane reset: set without a LaneClk edge while the transmitters are not ready, released after two
    -- LaneClk edges
    p_lane_rst : process (LaneClk, TxRdyF) is
    begin
        if TxRdyF = '0' then
            LaneRsr <= "11";
        elsif rising_edge(LaneClk) then
            LaneRsr <= LaneRsr(0) & '0';
        end if;
    end process;

    LaneRst <= LaneRsr(1);

    p_status : process (LaneClk, RstFree) is
    begin
        if RstFree = '1' then
            Stat_RxReady <= '0';
        elsif rising_edge(LaneClk) then
            if RxRdy = '1' and RxBusyF = (RxBusyF'range => '0') then
                Stat_RxReady <= '1';
            else
                Stat_RxReady <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Lanes
    -----------------------------------------------------------------------------------------------
    g_lane : for l in 0 to N_c-1 generate

        -- Request of the entire receiver reset (PA-RS-04): the lane leaves the states that use the line, or the
        -- command; stretched for the free-running clock, as struct
        p_req : process (LaneClk) is
        begin
            if rising_edge(LaneClk) then
                CdrEnLast(l) <= Phy_CdrEnable(l);
                if (CdrEnLast(l) = '1' and Phy_CdrEnable(l) = '0' and Cfg_RxResetOnDisc = '1') or
                   Cmd_RxReset(l) = '1' then
                    FullCnt(l)  <= 15;
                    FullReqL(l) <= '1';
                elsif FullCnt(l) /= 0 then
                    FullCnt(l) <= FullCnt(l) - 1;
                else
                    FullReqL(l) <= '0';
                end if;
            end if;
        end process;

        i_seq : entity work.ofb_pa_gty_lane_rst
            generic map (
                DoneHighCycles_g => RxRstDoneCycles_g,
                CdrWaitCycles_g  => CdrWaitCycles_g,
                GapCycles_g      => RxRstGapCycles_g
            )
            port map (
                Clk            => FreeRunClk,
                Rst            => RstFree,
                Req_Full       => FullReqL(l),
                Req_Buf        => '0',
                Req_Tx         => TxBufErr(l) and TxRdyF,
                Cfg_CdrOnly    => Cfg_RxResetCdrOnly,
                Cfg_PcsRsvdIn  => Cfg_PcsRsvdIn,
                Gt_MasterDone  => RxRdy,
                Gt_RxResetDone => RxRstDone(l),
                Gt_RxReset     => GtRxRst(l),
                Gt_RxResetMode => GtRxMode(l),
                Gt_RxPmaMask   => open,
                Gt_RxPcsMask   => open,
                Gt_RxCdrReset  => GtCdrRst(l),
                Gt_TxReset     => GtTxRst(l),
                Gt_TxResetMode => open,
                Gt_TxPmaMask   => open,
                Gt_TxPcsMask   => open,
                Gt_PcsRsvdIn   => open,
                Stat_RxBusy    => RxBusyF(l),
                Stat_BufBusy   => open,
                Ev_RxResetDone => DoneEvF(l),
                Ev_Timeout     => TimeoEvF(l)
            );

        -- Answer of the transceiver to the entire receiver reset: RXRESETDONE 1 when the receivers are ready, 0 from
        -- a GTRXRESET pulse in sequential mode until RxResetTime after its end (never with RxResetHang); every
        -- receiver reset and CDR reset relocks the receiver
        p_gtrst : process is
        begin
            RxRstDone(l) <= '0';
            wait until RstFree = '0' and RxRdy = '1';
            RxRstDone(l) <= '1';

            loop
                wait until (GtRxRst(l) = '1' and GtRxMode(l) = "00") or GtCdrRst(l) = '1' or RstFree = '1' or
                           RxRdy = '0';
                exit when RstFree = '1' or RxRdy = '0';
                RxRstCnt(l) <= RxRstCnt(l) + 1;
                if GtRxRst(l) = '1' then
                    RxRstDone(l) <= '0';
                    wait until GtRxRst(l) = '0' or RstFree = '1';
                    exit when RstFree = '1';
                    if not PaModelCtrl(ModelIdx_g).Lane(l).RxResetHang then
                        wait until RstFree = '1' for PaModelCtrl(ModelIdx_g).Lane(l).RxResetTime;
                        exit when RstFree = '1';
                        RxRstDone(l) <= '1';
                    end if;
                else
                    wait until GtCdrRst(l) = '0' or RstFree = '1';
                    exit when RstFree = '1';
                end if;
            end loop;

        end process;

        -- Transmit buffer error by control (TXBUFSTATUS[1]) until the transmit buffer reset; event toggles
        p_free : process (FreeRunClk) is
            variable Req_v : natural := 0;
        begin
            if rising_edge(FreeRunClk) then
                if PaModelCtrl(ModelIdx_g).Lane(l).TxBufErrReq /= Req_v then
                    Req_v       := PaModelCtrl(ModelIdx_g).Lane(l).TxBufErrReq;
                    TxBufErr(l) <= '1';
                elsif GtTxRst(l) = '1' then
                    TxBufErr(l) <= '0';
                end if;
                if DoneEvF(l) = '1' then
                    DoneTgl(l) <= not DoneTgl(l);
                end if;
                if TimeoEvF(l) = '1' then
                    TimeoTgl(l) <= not TimeoTgl(l);
                end if;
                if RstFree = '1' then
                    TxBufErr(l) <= '0';
                    DoneTgl(l)  <= '0';
                    TimeoTgl(l) <= '0';
                end if;
            end if;
        end process;

        -- Transmitter: four symbols per LaneClk cycle as 40 bits (symbol 0 first, bit a of a symbol
        -- first), or the PRBS pattern; electrical idle while not ready, disabled or idle by control
        p_tx : process (LaneClk, TxRdy) is
            variable Rd_v     : std_logic                     := '0';
            variable Enc_v    : Encoded_t;
            variable Bits_v   : std_logic_vector(39 downto 0);
            variable Lfsr_v   : std_logic_vector(31 downto 1) := (others => '1'); -- 1: newest bit
            variable Sel_v    : natural;
            variable Bit_v    : std_logic;
            variable ErrReq_v : natural                       := 0;
            variable BurstR_v : natural                       := 0;
            variable Every_v  : natural                       := 0;
            variable Lane_v   : PaModelLane_t;
            variable Delay_v  : time;
        begin
            if TxRdy = '0' then
                -- Electrical idle at once when the transmitters are not ready, also when a reset stops LaneClk in the
                -- same delta cycle (the bits already scheduled are discarded); the reset of the transmitters also
                -- resets the running disparity and the PRBS generator, as the transmit PCS of the transceiver
                TxLine(l) <= 'Z';
                Rd_v      := '0';
                Lfsr_v    := (others => '1');
            elsif rising_edge(LaneClk) then
                Lane_v := PaModelCtrl(ModelIdx_g).Lane(l);
                if Phy_TxEnable(l) = '0' or Lane_v.Idle then
                    TxLine(l) <= 'Z';
                    Rd_v      := '0';
                else
                    Sel_v := prbsSel(Phy_PrbsTxSel(4*l+3 downto 4*l));
                    if Sel_v = 0 then

                        for s in 0 to 3 loop
                            Enc_v                      := Enc_c(to_integer(unsigned'("" & Rd_v)),
                                                                to_integer(unsigned'("" & PhyTx_K(4*l+s))),
                                                                to_integer(unsigned(PhyTx_Data(32*l+8*s+7 downto 32*l+8*s))));
                            Rd_v                       := Enc_v.Rd;
                            Bits_v(10*s+9 downto 10*s) := Enc_v.Code;
                        end loop;

                    else

                        for b in 0 to 39 loop
                            Bit_v     := Lfsr_v(TapA_c(Sel_v)) xor Lfsr_v(TapB_c(Sel_v));
                            Lfsr_v    := Lfsr_v(30 downto 1) & Bit_v;
                            Bits_v(b) := Bit_v;
                        end loop;

                        if Phy_PrbsForceErr(l) = '1' then
                            Bits_v(0) := not Bits_v(0);
                        end if;
                    end if;
                    -- Error injection: single inverted bits, a burst of bits at '0' (a dropout of the line, which
                    -- 8B/10B always detects) and a bit error rate
                    if Lane_v.ErrReq /= ErrReq_v then
                        Bits_v(17) := not Bits_v(17);
                    end if;
                    if Lane_v.BurstReq /= BurstR_v then

                        for b in 0 to 39 loop
                            if b >= 5 and b < 5 + Lane_v.BurstLen then
                                Bits_v(b) := '0';
                            end if;
                        end loop;

                    end if;
                    if Lane_v.ErrEvery > 0 then

                        for b in 0 to 39 loop
                            Every_v := Every_v + 1;
                            if Every_v >= Lane_v.ErrEvery then
                                Every_v   := 0;
                                Bits_v(b) := not Bits_v(b);
                            end if;
                        end loop;

                    end if;

                    for b in 0 to 39 loop
                        Delay_v   := (Lane_v.SkewUi + b) * Ui;
                        TxLine(l) <= transport Bits_v(b) after Delay_v;
                    end loop;

                end if;
                ErrReq_v := Lane_v.ErrReq;
                BurstR_v := Lane_v.BurstReq;
            end if;
        end process;

        -- Pins: the transmitted bits, or the received bits in the far-end serial loopback; electrical
        -- idle drives both pins '0'; crossed pair by control. One process per lane (simulation speed)
        p_pins : process is
            variable Line_v : std_logic;
            variable Inv_v  : boolean;
        begin
            if Phy_SerialFarLoopback(l) = '1' then
                Line_v := RxLine(l);
            else
                Line_v := TxLine(l);
            end if;
            Inv_v := PaModelCtrl(ModelIdx_g).Lane(l).TxInvert;
            if Line_v = 'Z' then
                Gt_TxP(l) <= '0';
                Gt_TxN(l) <= '0';
            elsif Inv_v then
                Gt_TxP(l) <= not Line_v;
                Gt_TxN(l) <= Line_v;
            else
                Gt_TxP(l) <= Line_v;
                Gt_TxN(l) <= not Line_v;
            end if;
            -- A change of TxInvert takes effect with the next bit (no wait on the control record: speed)
            if Phy_SerialFarLoopback(l) = '1' then
                wait on RxLine(l), Phy_SerialFarLoopback(l);
            else
                wait on TxLine(l), Phy_SerialFarLoopback(l);
            end if;
        end process;

        -- Receiver: the bits since the last transition, counted in the own unit interval; symbol
        -- alignment on commas, decoding, words with the comma in symbol 0, receive buffer
        p_rx : process is
            variable Last_v      : time                          := 0 fs;
            variable Level_v     : std_logic                     := 'Z';
            variable N_v         : natural;
            variable B_v         : natural range 0 to 1;
            variable Sh_v        : natural range 0 to 1023       := 0;               -- last ten bits, newest in bit 9
            variable Cnt_v       : natural range 0 to 10         := 0;
            variable Align_v     : boolean                       := false;
            variable Rd_v        : natural range 0 to 1          := 0;
            variable Dec_v       : DecEntry_t;
            variable Sym_v       : natural range 0 to 4          := 0;
            variable Word_v      : PaModelWord_t;
            variable Hist_v      : std_logic_vector(31 downto 1) := (others => '0'); -- 1: newest bit
            variable Good_v      : natural                       := 0;
            variable Lock_v      : boolean                       := false;
            variable Sel_v       : natural                       := 0;
            variable Errs_v      : natural                       := 0;
            variable Lost_v      : natural                       := 0;
            variable Bit_v       : std_logic;
            variable Exp_v       : std_logic;
            variable In_v        : std_logic;
            variable Edge_v      : boolean;
            variable AlignOut_v  : boolean                       := false;
            variable LockOut_v   : boolean                       := false;
            variable ErrsOut_v   : natural                       := 0;
            variable LostOut_v   : natural                       := 0;
            variable RstSeen_v   : natural                       := 0;
            variable RxRstSeen_v : natural                       := 0;               -- receiver resets seen
            variable LockAt_v    : time                          := 0 fs;            -- CDR locked from then on
        begin
            -- Only the line wakes the receiver (simulation speed): the controls are read at every
            -- transition, a reset of the PRBS checker arrives as a count from the LaneClk side
            if Phy_SerialNearLoopback(l) = '1' then
                wait on TxLine(l), Phy_SerialNearLoopback(l);
                In_v := TxLine(l);
            else
                wait on Gt_RxP(l), Gt_RxN(l), Phy_SerialNearLoopback(l);
                if Gt_RxP(l) = Gt_RxN(l) then
                    In_v := 'Z';
                else
                    In_v := Gt_RxP(l);
                end if;
            end if;
            Edge_v := In_v /= Level_v;
            if Edge_v then
                RxLine(l) <= In_v;
            end if;
            -- Lock of the clock-data recovery: CdrLockTime after the first transition of a signal (after
            -- electrical idle or a reset of the adapter) and after a receiver or CDR reset of the lane; before, no
            -- word is decoded
            if RstFree = '1' or In_v = 'Z' or Level_v = 'Z' or RxRstCnt(l) /= RxRstSeen_v then
                RxRstSeen_v := RxRstCnt(l);
                LockAt_v    := now + PaModelCtrl(ModelIdx_g).CdrLockTime;
            end if;
            if RstFree = '1' or RxRdy = '0' or RxRstDone(l) = '0' or Phy_RxEnable(l) = '0' or
               In_v = 'Z' or now < LockAt_v then
                -- No data: alignment lost, buffer cleared
                Align_v := false;
                Cnt_v   := 0;
                Sym_v   := 0;
                Rd_v    := 0;
                RxBuf_v.clear(l);
            elsif Edge_v and Level_v /= 'Z' then
                -- The bits of the level that ends now (only at transitions, so a run is never split)
                N_v := (now - Last_v + Ui / 2) / Ui;
                if (Level_v = '1') xor (Phy_RxInvert(l) = '1') then
                    B_v := 1;
                else
                    B_v := 0;
                end if;
                if Sel_v /= 0 then
                    -- PRBS checker on the raw bits (bypasses 8B/10B): bit n = bit n-a xor bit n-b
                    Bit_v := '0';
                    if B_v = 1 then
                        Bit_v := '1';
                    end if;

                    for i in 1 to N_v loop
                        Exp_v := Hist_v(TapA_c(Sel_v)) xor Hist_v(TapB_c(Sel_v));
                        if Good_v >= LockBits_c then
                            if Bit_v /= Exp_v then
                                Errs_v := Errs_v + 1;
                            end if;
                        elsif Bit_v = Exp_v then
                            Good_v := Good_v + 1;
                        else
                            Good_v := 0;
                        end if;
                        Hist_v := Hist_v(30 downto 1) & Bit_v;
                    end loop;

                    Lock_v := Good_v >= LockBits_c;
                else

                    for i in 1 to N_v loop
                        Sh_v := Sh_v / 2 + B_v * 512;
                        -- Comma (0011111 or 1100000 in bits a to f): the symbol started 7 bits ago
                        if (Sh_v / 8 = 124 or Sh_v / 8 = 3) and (not Align_v or Cnt_v /= 6) then
                            Align_v := true;
                            Cnt_v   := 7;
                            Sym_v   := 0;
                        elsif Align_v then
                            Cnt_v := Cnt_v + 1;
                            if Cnt_v = 10 then
                                Cnt_v := 0;
                                Dec_v := Dec_c(Rd_v, Sh_v);
                                Rd_v  := Dec_v.Rd;
                                -- A comma symbol starts a word (comma in symbol 0)
                                if Dec_v.Comma then
                                    Sym_v := 0;
                                end if;
                                Word_v.Data(8*Sym_v+7 downto 8*Sym_v) := Dec_v.Char;
                                Word_v.K(Sym_v)                       := Dec_v.K;
                                Word_v.CodeErr(Sym_v)                 := Dec_v.CodeErr;
                                Word_v.DispErr(Sym_v)                 := Dec_v.DispErr;
                                Sym_v                                 := Sym_v + 1;
                                if Sym_v = 4 then
                                    Sym_v := 0;
                                    if RxBuf_v.level(l) < PaModelBufDepth_c then
                                        RxBuf_v.push(l, Word_v);
                                    else
                                        Lost_v := Lost_v + 1;
                                    end if;
                                end if;
                            end if;
                        end if;
                    end loop;

                end if;
            end if;
            -- PRBS checker selection and reset
            if prbsSel(Phy_PrbsRxSel(4*l+3 downto 4*l)) /= Sel_v or PrbsRst(l) /= RstSeen_v then
                RstSeen_v := PrbsRst(l);
                Sel_v     := prbsSel(Phy_PrbsRxSel(4*l+3 downto 4*l));
                Good_v    := 0;
                Lock_v    := false;
                Errs_v    := 0;
            end if;
            if Edge_v then
                Level_v := In_v;
                Last_v  := now;
            end if;
            -- Signals only on a change (every assignment costs simulation time)
            if Align_v /= AlignOut_v then
                AlignOut_v := Align_v;
                if Align_v then
                    Aligned(l) <= '1';
                else
                    Aligned(l) <= '0';
                end if;
            end if;
            if Lock_v /= LockOut_v then
                LockOut_v := Lock_v;
                if Lock_v then
                    PrbsLock(l) <= '1';
                else
                    PrbsLock(l) <= '0';
                end if;
            end if;
            if Errs_v /= ErrsOut_v then
                ErrsOut_v   := Errs_v;
                PrbsErrs(l) <= Errs_v;
            end if;
            if Lost_v /= LostOut_v then
                LostOut_v    := Lost_v;
                RxOverrun(l) <= Lost_v;
            end if;
        end process;

        -- Words into LaneClk: start at a fill level, clock correction with SKIP words
        p_rxout : process (LaneClk, RstFree) is
            variable Run_v    : boolean   := false;
            variable Word_v   : PaModelWord_t;
            variable Lvl_v    : natural;
            variable Errs_v   : natural   := 0;
            variable Lost_v   : natural   := 0;
            variable IsSkip_v : boolean;
            variable Ctrl_v   : PaModelCtrl_t;
            variable Idle_v   : natural   := 0;     -- words with code errors delivered in the current idle period
            variable Window_v : natural   := 0;     -- PA-RS-03: cycles left of the reset window of the buffer
            variable BufReq_v : natural   := 0;     -- forced buffer errors served (control record)
            variable Ran_v    : boolean   := false; -- the buffer delivered words since it was last started
            variable DoneL_v  : std_logic := '0';
            variable TimeoL_v : std_logic := '0';
        begin
            if RstFree = '1' then
                DoneL_v                         := '0';
                TimeoL_v                        := '0';
                Stat_TxBufErr(l)                <= '0';
                Stat_RxResetDone(l)             <= '0';
                Stat_RxResetBusy(l)             <= '0';
                Stat_CdrLock(l)                 <= '0';
                Stat_RxElecIdle(l)              <= '1';
                Ev_RxReset(l)                   <= '0';
                Ev_RxResetTimeout(l)            <= '0';
                Run_v                           := false;
                Window_v                        := 0;
                Ran_v                           := false;
                PhyRx_Data(32*l+31 downto 32*l) <= (others => '0');
                PhyRx_K(4*l+3 downto 4*l)       <= (others => '0');
                PhyRx_CodeErr(4*l+3 downto 4*l) <= (others => '0');
                PhyRx_DispErr(4*l+3 downto 4*l) <= (others => '0');
                PhyRx_Valid(l)                  <= '0';
                Stat_ClkCor(l)                  <= '0';
                Stat_RxBufErr(l)                <= '0';
                Phy_PrbsErr(l)                  <= '0';
                Phy_PrbsLocked(l)               <= '0';
                Stat_Aligned(l)                 <= '0';
                -- NoSignalNever: 0 also in reset, as struct
                if PaModelCtrl(ModelIdx_g).NoSignalMode = NoSignalNever then
                    Phy_NoSignal(l) <= '0';
                else
                    Phy_NoSignal(l) <= '1';
                end if;
            elsif rising_edge(LaneClk) then
                Ctrl_v           := PaModelCtrl(ModelIdx_g);
                PhyRx_Valid(l)   <= '0';
                Stat_ClkCor(l)   <= '0';
                Stat_RxBufErr(l) <= '0';
                Phy_PrbsErr(l)   <= '0';
                Lvl_v            := RxBuf_v.level(l);
                if Aligned(l) = '0' then
                    Run_v := false;
                elsif not Run_v and Lvl_v >= Start_c then
                    Run_v := true;
                end if;
                if Run_v then
                    Ran_v := true;
                end if;
                if Run_v then
                    if Lvl_v = 0 then
                        Stat_RxBufErr(l) <= '1';
                        Run_v            := false;
                        if RxBufReset_g then
                            Window_v := BufWindowWords_c;
                        end if;
                    else
                        Word_v   := RxBuf_v.peek(l);
                        IsSkip_v := Word_v.Data = WordSkip_c and Word_v.K = "0001";
                        if IsSkip_v and Lvl_v > High_c and Lvl_v > 1 then
                            -- Remove a SKIP word
                            RxBuf_v.pop(l, Word_v);
                            RxBuf_v.pop(l, Word_v);
                            Stat_ClkCor(l) <= '1';
                        elsif IsSkip_v and Lvl_v < Low_c then
                            -- Repeat a SKIP word: read it without removing it
                            Stat_ClkCor(l) <= '1';
                        else
                            RxBuf_v.pop(l, Word_v);
                        end if;
                        PhyRx_Data(32*l+31 downto 32*l) <= Word_v.Data;
                        PhyRx_K(4*l+3 downto 4*l)       <= Word_v.K;
                        PhyRx_CodeErr(4*l+3 downto 4*l) <= Word_v.CodeErr;
                        PhyRx_DispErr(4*l+3 downto 4*l) <= Word_v.DispErr;
                        PhyRx_Valid(l)                  <= '1';
                    end if;
                end if;
                -- NoSignalNever: while the line has been idle for NoSignalDelay, the receiver delivers words as the
                -- receiver of the transceiver model: IdleErrWords_c words with code errors, then words without errors
                -- that are not lane words. The Lane layer loses the word synchronisation, counts every word as RXERR
                -- and detects the loss when its counter overflows
                if Ctrl_v.NoSignalMode = NoSignalNever and RxRdy = '1' and Phy_RxEnable(l) = '1' and
                   RxLine(l) = 'Z' and RxLine(l)'last_event >= Ctrl_v.NoSignalDelay then
                    PhyRx_Data(32*l+31 downto 32*l) <= (others => '0');
                    PhyRx_K(4*l+3 downto 4*l)       <= "0000";
                    if Idle_v < IdleErrWords_c then
                        PhyRx_CodeErr(4*l+3 downto 4*l) <= "1111";
                        Idle_v                          := Idle_v + 1;
                    else
                        PhyRx_CodeErr(4*l+3 downto 4*l) <= "0000";
                        -- A running buffer loses its recovered clock when the line becomes idle: it reports an
                        -- error after the words with code errors, as in the transceiver model (not on a line that
                        -- never carried a signal since the buffer was last started)
                        if Ran_v then
                            Stat_RxBufErr(l) <= '1';
                            Ran_v            := false;
                            if RxBufReset_g then
                                Window_v := BufWindowWords_c;
                            end if;
                        end if;
                    end if;
                    PhyRx_DispErr(4*l+3 downto 4*l) <= "0000";
                    PhyRx_Valid(l)                  <= '1';
                else
                    Idle_v := 0;
                end if;
                if RxOverrun(l) /= Lost_v then
                    Stat_RxBufErr(l) <= '1';
                    -- PA-RS-03: the buffer is reset and starts again at the start level (an underflow already
                    -- restarts it there)
                    if RxBufReset_g then
                        RxBuf_v.clear(l);
                        Run_v    := false;
                        Window_v := BufWindowWords_c;
                    end if;
                end if;
                Lost_v := RxOverrun(l);
                -- Forced error of the receive buffer (control record, BufErrReq)
                if Ctrl_v.Lane(l).BufErrReq /= BufReq_v then
                    BufReq_v         := Ctrl_v.Lane(l).BufErrReq;
                    Stat_RxBufErr(l) <= '1';
                    if RxBufReset_g then
                        RxBuf_v.clear(l);
                        Run_v    := false;
                        Window_v := BufWindowWords_c;
                    end if;
                end if;
                -- PA-RS-03: the words of the reset window of the buffer are withheld (the zero words of the
                -- reset never pass as data); after the window the words are delivered as they come, so an idle
                -- line still drives the RXERR counter of the Lane layer
                if Window_v > 0 then
                    Window_v       := Window_v - 1;
                    PhyRx_Valid(l) <= '0';
                end if;
                if PrbsErrs(l) /= Errs_v then
                    Phy_PrbsErr(l) <= '1';
                end if;
                Errs_v := PrbsErrs(l);
                if Phy_PrbsCntReset(l) = '1' then
                    PrbsRst(l) <= PrbsRst(l) + 1;
                end if;
                Phy_PrbsLocked(l) <= PrbsLock(l);
                Stat_Aligned(l)   <= Aligned(l);
                -- Entire or CDR receiver reset in progress: no word is valid, as struct
                if RxBusyF(l) = '1' then
                    PhyRx_Valid(l) <= '0';
                end if;
                Stat_TxBufErr(l)    <= TxBufErr(l);
                Stat_RxResetDone(l) <= RxRstDone(l);
                Stat_RxResetBusy(l) <= RxBusyF(l);
                Stat_CdrLock(l)     <= Aligned(l);
                if RxLine(l) = 'Z' then
                    Stat_RxElecIdle(l) <= '1';
                else
                    Stat_RxElecIdle(l) <= '0';
                end if;
                Ev_RxReset(l)        <= DoneTgl(l) xor DoneL_v;
                Ev_RxResetTimeout(l) <= TimeoTgl(l) xor TimeoL_v;
                DoneL_v              := DoneTgl(l);
                TimeoL_v             := TimeoTgl(l);
                -- No signal: never (NoSignalNever, as struct), or while the line has been idle for NoSignalDelay
                -- (NoSignalLine)
                if Ctrl_v.NoSignalMode = NoSignalNever then
                    Phy_NoSignal(l) <= '0';
                elsif RxLine(l) = 'Z' and RxLine(l)'last_event >= Ctrl_v.NoSignalDelay then
                    Phy_NoSignal(l) <= '1';
                else
                    Phy_NoSignal(l) <= '0';
                end if;
            end if;
        end process;

    end generate;

end architecture;
