---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the multi-lane link: two ends A (0) and B (1), each an ofb_multilane with
-- NumLanes_g lanes and one ofb_lane per lane, connected lane by lane through the behavioural
-- Physical adapter model; row drivers fed from the row queues, monitors of the received rows
-- (compared with the expected streams) and of the words sent on the lanes.
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

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_ml_link_tb_pkg.all;
    use work.ofb_ml_row_queue_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_link_th is
    generic (
        NumLanes_g : positive range 2 to 4 := 2
    );
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_link_th is

    constant N_c         : positive := NumLanes_g;
    constant ClkPeriod_c : time     := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    subtype Words_t is std_logic_vector(32*N_c-1 downto 0);
    subtype Ks_t is std_logic_vector(4*N_c-1 downto 0);
    subtype Lanes_t is std_logic_vector(N_c-1 downto 0);
    subtype Caps_t is std_logic_vector(8*N_c-1 downto 0);

    type WordsArray_t is array (0 to 1) of Words_t;
    type KsArray_t is array (0 to 1) of Ks_t;
    type LanesArray_t is array (0 to 1) of Lanes_t;
    type CapsArray_t is array (0 to 1) of Caps_t;
    type BitArray_t is array (0 to 1) of std_logic;
    type CharArray_t is array (0 to 1) of Char_t;
    type AlignArray_t is array (0 to 1) of AlignState_t;

    -- Data Link side
    signal TxRowData   : WordsArray_t;
    signal TxRowK      : KsArray_t;
    signal TxRowMask   : LanesArray_t;
    signal TxRowRep    : BitArray_t;
    signal TxRowPois   : BitArray_t;
    signal TxRowValid  : BitArray_t;
    signal TxRowReady  : BitArray_t;
    signal RxRowData   : WordsArray_t;
    signal RxRowK      : KsArray_t;
    signal RxRowMask   : LanesArray_t;
    signal RxRowCrcErr : BitArray_t;
    signal RxRowValid  : BitArray_t;
    signal FarCap      : CharArray_t;
    signal DlActive    : BitArray_t;
    signal DataSending : LanesArray_t;
    signal DataRecv    : LanesArray_t;
    signal AlignState  : AlignArray_t;
    signal Bypass      : BitArray_t;
    signal Misaligned  : BitArray_t;

    -- Multi-Lane to Lane
    signal LaneTxData   : WordsArray_t;
    signal LaneTxK      : KsArray_t;
    signal LaneTxValid  : LanesArray_t;
    signal LaneTxReady  : LanesArray_t;
    signal SkipReq      : BitArray_t;
    signal LaneRxData   : WordsArray_t;
    signal LaneRxK      : KsArray_t;
    signal LaneRxValid  : LanesArray_t;
    signal LaneReset    : LanesArray_t;
    signal LaneTxOnly   : LanesArray_t;
    signal LaneRxOnly   : LanesArray_t;
    signal LaneFarAct   : LanesArray_t;
    signal LaneNearCap  : CapsArray_t;
    signal LaneState    : KsArray_t;
    signal LaneFarCap   : CapsArray_t;
    signal LaneCapValid : LanesArray_t;

    -- Lane to Physical adapter
    signal PhyTxData  : WordsArray_t;
    signal PhyTxK     : KsArray_t;
    signal PhyRxData  : WordsArray_t;
    signal PhyRxK     : KsArray_t;
    signal PhyRxCode  : KsArray_t;
    signal PhyRxDisp  : KsArray_t;
    signal PhyRxValid : LanesArray_t;
    signal NoSignal   : LanesArray_t;
    signal TxEnable   : LanesArray_t;
    signal RxEnable   : LanesArray_t;
    signal CdrEnable  : LanesArray_t;
    signal RxInvert   : LanesArray_t;

begin

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    g_end : for e in 0 to 1 generate

        -------------------------------------------------------------------------------------------
        -- Row driver: rows of the queue of this end
        -------------------------------------------------------------------------------------------
        p_tx : process (ClkI) is
            variable Row_v : TbRow_t;
        begin
            if rising_edge(ClkI) then
                if TxRowValid(e) = '1' and TxRowReady(e) = '1' then
                    TxRowValid(e) <= '0';
                end if;
                if (TxRowValid(e) = '0' or TxRowReady(e) = '1') and RstI = '0' then
                    if (e = 0 and TxQueueA_v.count > 0) or (e = 1 and TxQueueB_v.count > 0) then
                        if e = 0 then
                            Row_v := TxQueueA_v.pop;
                        else
                            Row_v := TxQueueB_v.pop;
                        end if;
                        TxRowData(e)  <= Row_v.Data(32*N_c-1 downto 0);
                        TxRowK(e)     <= Row_v.K(4*N_c-1 downto 0);
                        TxRowMask(e)  <= Row_v.Mask(N_c-1 downto 0);
                        TxRowRep(e)   <= Row_v.Replicate;
                        TxRowPois(e)  <= LinkCfg(e).Poison;
                        TxRowValid(e) <= '1';
                    end if;
                end if;
                if RstI = '1' then
                    TxRowValid(e) <= '0';
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Multi-Lane layer
        -------------------------------------------------------------------------------------------
        i_ml : entity work.ofb_multilane
            generic map (
                NumLanes_g          => N_c,
                ClkFrequency_g      => 156.25e6,
                SkipIntervalWords_g => 300
            )
            port map (
                Clk                     => ClkI,
                Rst                     => RstI,
                TxRow_Data              => TxRowData(e),
                TxRow_K                 => TxRowK(e),
                TxRow_Mask              => TxRowMask(e),
                TxRow_Replicate         => TxRowRep(e),
                TxRow_Poison            => TxRowPois(e),
                TxRow_Valid             => TxRowValid(e),
                TxRow_Ready             => TxRowReady(e),
                RxRow_Data              => RxRowData(e),
                RxRow_K                 => RxRowK(e),
                RxRow_Mask              => RxRowMask(e),
                RxRow_CrcErr            => RxRowCrcErr(e),
                RxRow_Valid             => RxRowValid(e),
                Dl_LinkReset            => LinkCfg(e).LinkReset,
                Dl_LaneReset            => LinkCfg(e).LaneReset,
                Dl_NearCapability       => LinkCfg(e).NearCapability,
                Dl_FarCapability        => FarCap(e),
                Dl_FarCapabilityValid   => open,
                Dl_FarCapabilityIdle    => open,
                Dl_LaneActive           => DlActive(e),
                Cfg_TxEn                => LinkCfg(e).TxEn(N_c-1 downto 0),
                Cfg_RxEn                => LinkCfg(e).RxEn(N_c-1 downto 0),
                Cfg_MaxDataLanes        => LinkCfg(e).MaxDataLanes,
                Cfg_Bypass              => LinkCfg(e).Bypass,
                LaneTx_Data             => LaneTxData(e),
                LaneTx_K                => LaneTxK(e),
                LaneTx_Valid            => LaneTxValid(e),
                LaneTx_Ready            => LaneTxReady(e),
                Lane_SkipReq            => SkipReq(e),
                LaneRx_Data             => LaneRxData(e),
                LaneRx_K                => LaneRxK(e),
                LaneRx_Valid            => LaneRxValid(e),
                Lane_Reset              => LaneReset(e),
                Lane_TxOnly             => LaneTxOnly(e),
                Lane_RxOnly             => LaneRxOnly(e),
                Lane_FarEndActive       => LaneFarAct(e),
                Lane_NearCapability     => LaneNearCap(e),
                Lane_State              => LaneState(e),
                Lane_FarCapability      => LaneFarCap(e),
                Lane_FarCapabilityValid => LaneCapValid(e),
                Stat_DataSendingLanes   => DataSending(e),
                Stat_DataReceivingLanes => DataRecv(e),
                Stat_AlignState         => AlignState(e),
                Stat_Bypass             => Bypass(e),
                Ev_Misaligned           => Misaligned(e)
            );

        -------------------------------------------------------------------------------------------
        -- Lane layers
        -------------------------------------------------------------------------------------------
        g_lane : for l in 0 to N_c-1 generate

            i_lane : entity work.ofb_lane
                generic map (
                    SkipExternal_g => true
                )
                port map (
                    Clk                      => ClkI,
                    Rst                      => RstI,
                    TxWord_Data              => LaneTxData(e)(32*l+31 downto 32*l),
                    TxWord_K                 => LaneTxK(e)(4*l+3 downto 4*l),
                    TxWord_Valid             => LaneTxValid(e)(l),
                    TxWord_Ready             => LaneTxReady(e)(l),
                    RxWord_Data              => LaneRxData(e)(32*l+31 downto 32*l),
                    RxWord_K                 => LaneRxK(e)(4*l+3 downto 4*l),
                    RxWord_Valid             => LaneRxValid(e)(l),
                    Ctrl_LaneReset           => LaneReset(e)(l),
                    Ctrl_SkipReq             => SkipReq(e),
                    Ctrl_TxOnly              => LaneTxOnly(e)(l),
                    Ctrl_RxOnly              => LaneRxOnly(e)(l),
                    Ctrl_FarEndActive        => LaneFarAct(e)(l),
                    Ctrl_NearCapability      => LaneNearCap(e)(8*l+7 downto 8*l),
                    Ctrl_State               => LaneState(e)(4*l+3 downto 4*l),
                    Ctrl_FarCapability       => LaneFarCap(e)(8*l+7 downto 8*l),
                    Ctrl_FarCapabilityValid  => LaneCapValid(e)(l),
                    PhyTx_Data               => PhyTxData(e)(32*l+31 downto 32*l),
                    PhyTx_K                  => PhyTxK(e)(4*l+3 downto 4*l),
                    PhyRx_Data               => PhyRxData(e)(32*l+31 downto 32*l),
                    PhyRx_K                  => PhyRxK(e)(4*l+3 downto 4*l),
                    PhyRx_CodeErr            => PhyRxCode(e)(4*l+3 downto 4*l),
                    PhyRx_DispErr            => PhyRxDisp(e)(4*l+3 downto 4*l),
                    PhyRx_Valid              => PhyRxValid(e)(l),
                    Phy_TxEnable             => TxEnable(e)(l),
                    Phy_RxEnable             => RxEnable(e)(l),
                    Phy_CdrEnable            => CdrEnable(e)(l),
                    Phy_RxInvert             => RxInvert(e)(l),
                    Phy_NoSignal             => NoSignal(e)(l),
                    Cfg_LaneStart            => LinkCfg(e).LaneStart(l),
                    Cfg_AutoStart            => '1',
                    Cfg_LaneReset            => '0',
                    Stat_State               => open,
                    Stat_RxErrCount          => open,
                    Stat_RxErrOverflow       => open,
                    Stat_Timeout             => open,
                    Stat_FarStandby          => open,
                    Stat_FarStandbyReason    => open,
                    Stat_FarLostSignal       => open,
                    Stat_FarLostSignalReason => open,
                    Stat_FarCapability       => open,
                    Stat_RxPolarity          => open
                );

        end generate;

        -------------------------------------------------------------------------------------------
        -- Monitor of the received rows (parsed into frames and other words, compared with the
        -- expected stream of the far end) and of the words sent on the lanes
        -------------------------------------------------------------------------------------------
        p_monitor : process (ClkI) is
            type NatArray_t is array (0 to N_c-1) of natural;
            type BoolArray_t is array (0 to N_c-1) of boolean;
            type StateHist_t is array (0 to 3) of AlignState_t;

            variable Stat_v     : LinkStat_t;
            variable Init_v     : boolean := true;
            variable InFrame_v  : boolean := false;
            variable InBcst_v   : boolean := false;
            variable InIdle_v   : boolean := false;
            variable Partial_v  : boolean := false;
            variable Check_v    : boolean := true;
            variable Word_v     : Word_t;
            variable K_v        : WordK_t;
            variable Kind_v     : WordKind_t;
            variable Exp_v      : std_logic_vector(36 downto 0);
            -- Lane words
            variable Hist_v     : StateHist_t := (others => AlignNotReady_c);
            variable Stable_v   : boolean;
            variable ActCnt_v   : NatArray_t  := (others => 0);
            variable SinceAl_v  : NatArray_t  := (others => 0);
            variable PatOk_v    : BoolArray_t := (others => false);
            variable PadPend_v  : BoolArray_t := (others => false);
            variable TxLane_v   : BoolArray_t;
            variable NumTx_v    : natural;
            variable NumSkip_v  : natural;
            variable LaneWord_v : Word_t;
            variable LaneK_v    : WordK_t;
            variable LaneKind_v : WordKind_t;
            variable IsSkip_v   : boolean;
            variable IsIdle_v   : boolean;
            variable IsMl_v     : boolean;
            variable IsFrame_v  : boolean;

            -- Compare a received word with the head of an expected queue of the far end
            procedure compare (
                frame : boolean;
                word  : Word_t;
                k     : WordK_t;
                mask  : Word_t;
                msg   : string) is
                variable Cnt_v : natural;
            begin
                if not Check_v then
                    return;
                end if;
                if e = 1 and frame then
                    Cnt_v := ExpFrameA_v.count;
                elsif e = 1 then
                    Cnt_v := ExpCtrlA_v.count;
                elsif frame then
                    Cnt_v := ExpFrameB_v.count;
                else
                    Cnt_v := ExpCtrlB_v.count;
                end if;
                if Cnt_v = 0 then
                    alert(error, "End " & to_string(e) & ": unexpected " & msg & " " & to_hstring(word));
                    Stat_v.CheckErrs := Stat_v.CheckErrs + 1;
                    return;
                end if;
                if e = 1 and frame then
                    Exp_v := ExpFrameA_v.pop;
                elsif e = 1 then
                    Exp_v := ExpCtrlA_v.pop;
                elsif frame then
                    Exp_v := ExpFrameB_v.pop;
                else
                    Exp_v := ExpCtrlB_v.pop;
                end if;
                if (word and mask) /= (Exp_v(31 downto 0) and mask) or k /= Exp_v(35 downto 32) then
                    alert(error, "End " & to_string(e) & ": " & msg & " " & to_hstring(k & word) &
                                 ", expected " & to_hstring(Exp_v(35 downto 0)));
                    Stat_v.CheckErrs := Stat_v.CheckErrs + 1;
                end if;
            end procedure;

        -- Monitor
        begin
            if rising_edge(ClkI) then
                if Init_v then
                    Stat_v := (AlignState => AlignNotReady_c,
                               DataSending => (others => '0'),
                               DataReceiving => (others => '0'),
                               Bypass => '0',
                               LaneActive => (others => '0'),
                               LaneReset => (others => '0'),
                               ResetSeen => (others => '0'),
                               TxOnly => (others => '0'),
                               RxOnly => (others => '0'),
                               FarEndActive => (others => '0'),
                               NearCap0 => x"00",
                               FarCapability => x"00",
                               Frames => 0,
                               CtrlWords => 0,
                               RxErrs => 0,
                               AnyErrs => 0,
                               CrcErrs => 0,
                               CheckErrs => 0,
                               MidPartial => 0,
                               Misaligned => 0,
                               SkipAsync => 0,
                               Skips => 0,
                               NrActive => 0,
                               NrAlign => 0,
                               NerAlign => 0,
                               BerMlWords => 0,
                               PatternErr => 0,
                               PadMisuse => 0,
                               HotDlWords => 0,
                               IdleWords => 0,
                               LastAlign => (others => (others => '0')),
                               LastActive => (others => '0'));
                    Init_v := false;
                end if;
                -- Checking switched on: the parser starts outside a frame
                if LinkCfg(e).Check and not Check_v then
                    InFrame_v := false;
                    InBcst_v  := false;
                    InIdle_v  := false;
                    Partial_v := false;
                end if;
                Check_v := LinkCfg(e).Check;

                if RxRowValid(e) = '1' and RstI = '0' then
                    Word_v := RxRowData(e)(31 downto 0);
                    K_v    := RxRowK(e)(3 downto 0);
                    Kind_v := wordKind(Word_v, K_v);
                    if Kind_v /= KindData then
                        -- Control word: one word in the row
                        if Check_v and Partial_v and Kind_v /= KindEdf and Kind_v /= KindRetry and
                           Kind_v /= KindRxErr and Kind_v /= KindSif and Kind_v /= KindSdf then
                            Stat_v.MidPartial := Stat_v.MidPartial + 1;
                        end if;
                        Partial_v := false;
                        if Check_v and RxRowMask(e) /= std_logic_vector(to_unsigned(1, N_c)) then
                            alert(error, "End " & to_string(e) & ": control row with more than one word");
                            Stat_v.CheckErrs := Stat_v.CheckErrs + 1;
                        end if;

                        case Kind_v is
                            when KindSdf =>
                                compare(true, Word_v, K_v, x"FFFFFFFF", "SDF");
                                InFrame_v := true;
                                InIdle_v  := false;
                            when KindEdf =>
                                compare(true, Word_v, K_v, x"0000FFFF", "EDF");
                                if RxRowCrcErr(e) = '1' then
                                    Stat_v.AnyErrs := Stat_v.AnyErrs + 1;
                                    if Check_v then
                                        Stat_v.CrcErrs := Stat_v.CrcErrs + 1;
                                        alert(error, "End " & to_string(e) & ": CRC error");
                                    end if;
                                end if;
                                InFrame_v     := false;
                                Stat_v.Frames := Stat_v.Frames + 1;
                            when KindSbf =>
                                compare(false, Word_v, K_v, x"FFFFFFFF", "SBF");
                                InBcst_v         := true;
                                InIdle_v         := false;
                                Stat_v.CtrlWords := Stat_v.CtrlWords + 1;
                            when KindEbf =>
                                compare(false, Word_v, K_v, x"FFFFFFFF", "EBF");
                                InBcst_v         := false;
                                Stat_v.CtrlWords := Stat_v.CtrlWords + 1;
                            when KindSif =>
                                compare(false, Word_v, K_v, x"FFFFFFFF", "SIF");
                                InIdle_v         := true;
                                InFrame_v        := false;
                                Stat_v.CtrlWords := Stat_v.CtrlWords + 1;
                            when KindRxErr =>
                                Stat_v.RxErrs  := Stat_v.RxErrs + 1;
                                Stat_v.AnyErrs := Stat_v.AnyErrs + 1;
                                if Check_v then
                                    alert(error, "End " & to_string(e) & ": RXERR");
                                end if;
                            when others =>
                                compare(false, Word_v, K_v, x"FFFFFFFF", "control word");
                                Stat_v.CtrlWords := Stat_v.CtrlWords + 1;
                        end case;

                    elsif InBcst_v then
                        compare(false, Word_v, K_v, x"FFFFFFFF", "broadcast word");
                        Stat_v.CtrlWords := Stat_v.CtrlWords + 1;
                    elsif InIdle_v then
                        null;
                    else
                        -- Data words of a data frame
                        if Check_v and Partial_v then
                            Stat_v.MidPartial := Stat_v.MidPartial + 1;
                        end if;
                        Partial_v := RxRowMask(e) /= (RxRowMask(e)'range => '1');
                        if Check_v and not InFrame_v then
                            alert(error, "End " & to_string(e) & ": data row outside a frame");
                            Stat_v.CheckErrs := Stat_v.CheckErrs + 1;
                        end if;

                        for i in 0 to N_c-1 loop
                            if RxRowMask(e)(i) = '1' then
                                compare(true, RxRowData(e)(32*i+31 downto 32*i), RxRowK(e)(4*i+3 downto 4*i),
                                        x"FFFFFFFF", "data word");
                            end if;
                        end loop;

                    end if;
                end if;
                if Misaligned(e) = '1' then
                    Stat_v.Misaligned := Stat_v.Misaligned + 1;
                end if;

                -- Status
                Stat_v.AlignState    := AlignState(e);
                Stat_v.DataSending   := (others => '0');
                Stat_v.DataReceiving := (others => '0');
                Stat_v.LaneActive    := (others => '0');
                Stat_v.LaneReset     := (others => '0');
                Stat_v.TxOnly        := (others => '0');
                Stat_v.RxOnly        := (others => '0');
                Stat_v.FarEndActive  := (others => '0');

                for l in 0 to N_c-1 loop
                    Stat_v.DataSending(l)   := DataSending(e)(l);
                    Stat_v.DataReceiving(l) := DataRecv(e)(l);
                    if LaneState(e)(4*l+3 downto 4*l) = LaneStateActive_c then
                        Stat_v.LaneActive(l) := '1';
                    end if;
                    Stat_v.LaneReset(l)    := LaneReset(e)(l);
                    Stat_v.ResetSeen(l)    := Stat_v.ResetSeen(l) or LaneReset(e)(l);
                    Stat_v.TxOnly(l)       := LaneTxOnly(e)(l);
                    Stat_v.RxOnly(l)       := LaneRxOnly(e)(l);
                    Stat_v.FarEndActive(l) := LaneFarAct(e)(l);
                end loop;

                Stat_v.Bypass        := Bypass(e);
                Stat_v.NearCap0      := LaneNearCap(e)(7 downto 0);
                Stat_v.FarCapability := FarCap(e);

                -- Words sent on the lanes. Alignment state stable for four cycles (pipeline to the lane)
                Hist_v(1 to 3) := Hist_v(0 to 2);
                Hist_v(0)      := AlignState(e);
                Stable_v       := Hist_v(1) = Hist_v(0) and Hist_v(2) = Hist_v(0) and Hist_v(3) = Hist_v(0);
                NumTx_v        := 0;
                NumSkip_v      := 0;

                for l in 0 to N_c-1 loop
                    -- Transmitting lane: Active for four cycles, transmitter enabled
                    if Stat_v.LaneActive(l) = '1' and TxEnable(e)(l) = '1' then
                        if ActCnt_v(l) < 4 then
                            ActCnt_v(l) := ActCnt_v(l) + 1;
                        end if;
                    else
                        ActCnt_v(l) := 0;
                    end if;
                    TxLane_v(l) := ActCnt_v(l) = 4;
                    if not Stable_v then
                        PatOk_v(l) := false;
                    end if;
                    if TxLane_v(l) then
                        LaneWord_v := PhyTxData(e)(32*l+31 downto 32*l);
                        LaneK_v    := PhyTxK(e)(4*l+3 downto 4*l);
                        LaneKind_v := wordKind(LaneWord_v, LaneK_v);
                        IsSkip_v   := LaneWord_v = WordSkip_c and LaneK_v = KCtrl_c;
                        IsIdle_v   := LaneWord_v = WordIdle_c and LaneK_v = KCtrl_c;
                        NumTx_v    := NumTx_v + 1;
                        if IsSkip_v then
                            NumSkip_v := NumSkip_v + 1;
                        end if;
                        IsMl_v := isActive(LaneWord_v, LaneK_v) or alignCorrect(LaneWord_v, LaneK_v) or
                                  alignHot(LaneWord_v, LaneK_v);
                        if Stable_v and AlignState(e) = AlignBothEndsReady_c and IsMl_v then
                            Stat_v.BerMlWords := Stat_v.BerMlWords + 1;
                        end if;
                        if isActive(LaneWord_v, LaneK_v) then
                            Stat_v.LastActive := LaneWord_v;
                            if Stable_v and AlignState(e) = AlignNotReady_c then
                                Stat_v.NrActive := Stat_v.NrActive + 1;
                            end if;
                        end if;
                        if alignCorrect(LaneWord_v, LaneK_v) or alignHot(LaneWord_v, LaneK_v) then
                            Stat_v.LastAlign(l) := LaneWord_v;
                            if Stable_v and AlignState(e) = AlignNotReady_c then
                                Stat_v.NrAlign := Stat_v.NrAlign + 1;
                            elsif Stable_v and AlignState(e) = AlignNearEndReady_c then
                                Stat_v.NerAlign := Stat_v.NerAlign + 1;
                            end if;
                            -- Seven words between two ALIGN words (ECSS 5.6.7.2b.1, 5.6.7.3b.3)
                            if PatOk_v(l) and SinceAl_v(l) /= 7 then
                                Stat_v.PatternErr := Stat_v.PatternErr + 1;
                            end if;
                            SinceAl_v(l) := 0;
                            PatOk_v(l)   := Stable_v and AlignState(e) /= AlignBothEndsReady_c;
                        elsif not IsSkip_v then
                            SinceAl_v(l) := SinceAl_v(l) + 1;
                        end if;
                        -- PAD only before the end of a data frame
                        if not (IsSkip_v or IsIdle_v or LaneKind_v = KindMlCtrl) then
                            if PadPend_v(l) and LaneKind_v /= KindPad and LaneKind_v /= KindEdf and
                               LaneKind_v /= KindSdf and LaneKind_v /= KindSif and LaneKind_v /= KindRetry and
                               LaneKind_v /= KindRxErr then
                                Stat_v.PadMisuse := Stat_v.PadMisuse + 1;
                            end if;
                            PadPend_v(l) := LaneKind_v = KindPad;
                        end if;
                        -- Lanes that are not data-sending: no Data Link framing words
                        IsFrame_v := LaneKind_v = KindSdf or LaneKind_v = KindEdf or LaneKind_v = KindSbf or
                                     LaneKind_v = KindEbf or LaneKind_v = KindSif;
                        if DataSending(e)(l) = '0' and Bypass(e) = '0' and IsFrame_v then
                            Stat_v.HotDlWords := Stat_v.HotDlWords + 1;
                        end if;
                        if IsIdle_v and DataSending(e)(l) = '1' and Stable_v and
                           AlignState(e) = AlignBothEndsReady_c then
                            Stat_v.IdleWords := Stat_v.IdleWords + 1;
                        end if;
                    end if;
                end loop;

                -- SKIP on all transmitting lanes in the same cycle (ECSS 5.6.4.5a)
                if NumSkip_v > 0 and NumSkip_v /= NumTx_v then
                    Stat_v.SkipAsync := Stat_v.SkipAsync + 1;
                elsif NumSkip_v > 0 then
                    Stat_v.Skips := Stat_v.Skips + 1;
                end if;

                LinkStat(e) <= Stat_v;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Physical adapter models, one per lane (lane l of A to lane l of B)
    -----------------------------------------------------------------------------------------------
    g_pa : for l in 0 to N_c-1 generate

        i_pa : entity work.ofb_tb_pa_model
            generic map (
                Instance_g => l
            )
            port map (
                Clk          => ClkI,
                A_Tx_Data    => PhyTxData(0)(32*l+31 downto 32*l),
                A_Tx_K       => PhyTxK(0)(4*l+3 downto 4*l),
                A_TxEnable   => TxEnable(0)(l),
                A_RxEnable   => RxEnable(0)(l),
                A_CdrEnable  => CdrEnable(0)(l),
                A_RxInvert   => RxInvert(0)(l),
                A_Rx_Data    => PhyRxData(0)(32*l+31 downto 32*l),
                A_Rx_K       => PhyRxK(0)(4*l+3 downto 4*l),
                A_Rx_CodeErr => PhyRxCode(0)(4*l+3 downto 4*l),
                A_Rx_DispErr => PhyRxDisp(0)(4*l+3 downto 4*l),
                A_Rx_Valid   => PhyRxValid(0)(l),
                A_NoSignal   => NoSignal(0)(l),
                B_Tx_Data    => PhyTxData(1)(32*l+31 downto 32*l),
                B_Tx_K       => PhyTxK(1)(4*l+3 downto 4*l),
                B_TxEnable   => TxEnable(1)(l),
                B_RxEnable   => RxEnable(1)(l),
                B_CdrEnable  => CdrEnable(1)(l),
                B_RxInvert   => RxInvert(1)(l),
                B_Rx_Data    => PhyRxData(1)(32*l+31 downto 32*l),
                B_Rx_K       => PhyRxK(1)(4*l+3 downto 4*l),
                B_Rx_CodeErr => PhyRxCode(1)(4*l+3 downto 4*l),
                B_Rx_DispErr => PhyRxDisp(1)(4*l+3 downto 4*l),
                B_Rx_Valid   => PhyRxValid(1)(l),
                B_NoSignal   => NoSignal(1)(l)
            );

    end generate;

end architecture;
