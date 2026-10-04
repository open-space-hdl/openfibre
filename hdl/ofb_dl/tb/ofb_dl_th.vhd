---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Data Link layer: two ends A (0) and B (1), each ofb_dl + ofb_multilane +
-- ofb_lane, connected through the behavioural Physical adapter model; packet generators and
-- receivers per VC, broadcast generators and receivers, status collection.
--
-- Documentation: hdl/ofb_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_dl_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_dl_th is

    constant ClkPeriod_c  : time := 6.4 ns;
    constant UserPeriod_c : time := 5.2 ns;

    signal ClkI    : std_logic := '0';
    signal RstI    : std_logic := '1';
    signal UserClk : std_logic := '0';
    signal UserRst : std_logic := '1';

    type WordArray_t is array (0 to 1) of Word_t;
    type KArray_t is array (0 to 1) of WordK_t;
    type BitArray_t is array (0 to 1) of std_logic;
    type CharArray_t is array (0 to 1) of Char_t;
    type StateArray_t is array (0 to 1) of LaneState_t;
    type VcDataArray_t is array (0 to 1) of std_logic_vector(32*TbNumVc_c-1 downto 0);
    type VcKArray_t is array (0 to 1) of std_logic_vector(4*TbNumVc_c-1 downto 0);
    type VcBitArray_t is array (0 to 1) of std_logic_vector(TbNumVc_c-1 downto 0);
    type BcDataArray_t is array (0 to 1) of std_logic_vector(63 downto 0);
    type State2Array_t is array (0 to 1) of std_logic_vector(1 downto 0);

    -- User side
    signal TxVcData  : VcDataArray_t;
    signal TxVcK     : VcKArray_t;
    signal TxVcValid : VcBitArray_t := (others => (others => '0'));
    signal TxVcReady : VcBitArray_t;
    signal RxVcData  : VcDataArray_t;
    signal RxVcK     : VcKArray_t;
    signal RxVcValid : VcBitArray_t;
    signal RxVcReady : VcBitArray_t := (others => (others => '0'));
    signal TxBcData  : BcDataArray_t;
    signal TxBcCh    : CharArray_t;
    signal TxBcType  : CharArray_t;
    signal TxBcValid : BitArray_t   := (others => '0');
    signal TxBcReady : BitArray_t;
    signal RxBcData  : BcDataArray_t;
    signal RxBcCh    : CharArray_t;
    signal RxBcType  : CharArray_t;
    signal RxBcLate  : BitArray_t;
    signal RxBcValid : BitArray_t;

    -- Data Link to Multi-Lane
    signal TxRowData    : WordArray_t;
    signal TxRowK       : KArray_t;
    signal TxRowMask    : BitArray_t;
    signal TxRowRepl    : BitArray_t;
    signal TxRowValid   : BitArray_t;
    signal TxRowReady   : BitArray_t;
    signal RxRowData    : WordArray_t;
    signal RxRowK       : KArray_t;
    signal RxRowCrc     : BitArray_t;
    signal RxRowValid   : BitArray_t;
    signal MlLinkRst    : BitArray_t;
    signal MlLaneRst    : BitArray_t;
    signal MlNearCap    : CharArray_t;
    signal MlFarCap     : CharArray_t;
    signal MlFarCapV    : BitArray_t;
    signal MlFarCapIdle : BitArray_t;
    signal MlActive     : BitArray_t;

    -- Multi-Lane to Lane
    signal LaneTxData  : WordArray_t;
    signal LaneTxK     : KArray_t;
    signal LaneTxValid : BitArray_t;
    signal LaneTxReady : BitArray_t;
    signal LaneRxData  : WordArray_t;
    signal LaneRxK     : KArray_t;
    signal LaneRxValid : BitArray_t;
    signal LaneReset   : BitArray_t;
    signal LaneTxOnly  : BitArray_t;
    signal LaneRxOnly  : BitArray_t;
    signal LaneFarAct  : BitArray_t;
    signal LaneNearCap : CharArray_t;
    signal LaneState   : StateArray_t;
    signal LaneFarCap  : CharArray_t;
    signal LaneCapV    : BitArray_t;

    -- Lane to Physical adapter
    signal PhyTxData  : WordArray_t;
    signal PhyTxK     : KArray_t;
    signal PhyRxData  : WordArray_t;
    signal PhyRxK     : KArray_t;
    signal PhyRxCode  : KArray_t;
    signal PhyRxDisp  : KArray_t;
    signal PhyRxValid : BitArray_t;
    signal NoSignal   : BitArray_t;
    signal TxEnable   : BitArray_t;
    signal RxEnable   : BitArray_t;
    signal CdrEnable  : BitArray_t;
    signal RxInvert   : BitArray_t;

    -- Status
    signal HasCredit  : VcBitArray_t;
    signal CreditOvf  : VcBitArray_t;
    signal InOvf      : VcBitArray_t;
    signal EvCrc16    : BitArray_t;
    signal EvCrc8     : BitArray_t;
    signal EvFrame    : BitArray_t;
    signal EvSeq      : BitArray_t;
    signal EvRetry    : BitArray_t;
    signal EvProt     : BitArray_t;
    signal EvFarReset : BitArray_t;
    signal EvBcDisc   : BitArray_t;
    signal ErbEmpty   : BitArray_t;
    signal LinkState  : State2Array_t;

    type EndNatArray_t is array (0 to 1) of natural;

    signal BcSentCnt : EndNatArray_t := (others => 0);
    signal BcRxCnt   : EndNatArray_t := (others => 0);
    signal BcLateCnt : EndNatArray_t := (others => 0);

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    ClkI    <= not ClkI after ClkPeriod_c / 2;
    UserClk <= not UserClk after UserPeriod_c / 2;
    Clk     <= ClkI;
    Rst     <= RstI;

    p_rst : process is
    begin
        RstI    <= '1';
        UserRst <= '1';
        wait for 20 * ClkPeriod_c;
        wait until rising_edge(UserClk);
        UserRst <= '0';
        wait until rising_edge(ClkI);
        RstI    <= '0';
        wait;
    end process;

    g_end : for i in 0 to 1 generate

        -------------------------------------------------------------------------------------------
        -- Data Link layer, Multi-Lane layer, Lane layer
        -------------------------------------------------------------------------------------------
        i_dl : entity work.ofb_dl
            generic map (
                NumVc_g => TbNumVc_c
            )
            port map (
                Clk                   => ClkI,
                Rst                   => RstI,
                UserClk               => UserClk,
                UserRst               => UserRst,
                TxVc_Data             => TxVcData(i),
                TxVc_K                => TxVcK(i),
                TxVc_Valid            => TxVcValid(i),
                TxVc_Ready            => TxVcReady(i),
                RxVc_Data             => RxVcData(i),
                RxVc_K                => RxVcK(i),
                RxVc_Valid            => RxVcValid(i),
                RxVc_Ready            => RxVcReady(i),
                TxBc_Data             => TxBcData(i),
                TxBc_Channel          => TxBcCh(i),
                TxBc_Type             => TxBcType(i),
                TxBc_Valid            => TxBcValid(i),
                TxBc_Ready            => TxBcReady(i),
                RxBc_Data             => RxBcData(i),
                RxBc_Channel          => RxBcCh(i),
                RxBc_Type             => RxBcType(i),
                RxBc_Delayed          => open,
                RxBc_Late             => RxBcLate(i),
                RxBc_Valid            => RxBcValid(i),
                RxBc_Ready            => '1',
                TxRow_Data            => TxRowData(i),
                TxRow_K               => TxRowK(i),
                TxRow_Mask(0)         => TxRowMask(i),
                TxRow_Replicate       => TxRowRepl(i),
                TxRow_Valid           => TxRowValid(i),
                TxRow_Ready           => TxRowReady(i),
                RxRow_Data            => RxRowData(i),
                RxRow_K               => RxRowK(i),
                RxRow_Mask            => "1",
                RxRow_CrcErr          => RxRowCrc(i),
                RxRow_Valid           => RxRowValid(i),
                Ml_LinkReset          => MlLinkRst(i),
                Ml_LaneReset          => MlLaneRst(i),
                Ml_NearCapability     => MlNearCap(i),
                Ml_FarCapability      => MlFarCap(i),
                Ml_FarCapabilityValid => MlFarCapV(i),
                Ml_FarCapabilityIdle  => MlFarCapIdle(i),
                Ml_LaneActive         => MlActive(i),
                Cfg_DataScrambled     => DlCfg(i).DataScrambled,
                Cfg_LinkReset         => DlCfg(i).LinkReset,
                Cfg_BcInterval        => DlCfg(i).BcInterval,
                Stat_HasCredit        => HasCredit(i),
                Ev_CreditOverflow     => CreditOvf(i),
                Ev_InputOverflow      => InOvf(i),
                Ev_Crc16Err           => EvCrc16(i),
                Ev_Crc8Err            => EvCrc8(i),
                Ev_FrameErr           => EvFrame(i),
                Ev_SeqErr             => EvSeq(i),
                Ev_Retry              => EvRetry(i),
                Ev_ProtocolError      => EvProt(i),
                Ev_FarEndLinkReset    => EvFarReset(i),
                Ev_BcDiscard          => EvBcDisc(i),
                Stat_ErbEmpty         => ErbEmpty(i),
                Stat_LinkResetState   => LinkState(i)
            );

        i_ml : entity work.ofb_multilane
            generic map (
                NumLanes_g => 1
            )
            port map (
                Clk                        => ClkI,
                Rst                        => RstI,
                TxRow_Data                 => TxRowData(i),
                TxRow_K                    => TxRowK(i),
                TxRow_Mask(0)              => TxRowMask(i),
                TxRow_Replicate            => TxRowRepl(i),
                TxRow_Valid                => TxRowValid(i),
                TxRow_Ready                => TxRowReady(i),
                RxRow_Data                 => RxRowData(i),
                RxRow_K                    => RxRowK(i),
                RxRow_Mask                 => open,
                RxRow_CrcErr               => RxRowCrc(i),
                RxRow_Valid                => RxRowValid(i),
                Dl_LinkReset               => MlLinkRst(i),
                Dl_LaneReset               => MlLaneRst(i),
                Dl_NearCapability          => MlNearCap(i),
                Dl_FarCapability           => MlFarCap(i),
                Dl_FarCapabilityValid      => MlFarCapV(i),
                Dl_FarCapabilityIdle       => MlFarCapIdle(i),
                Dl_LaneActive              => MlActive(i),
                LaneTx_Data                => LaneTxData(i),
                LaneTx_K                   => LaneTxK(i),
                LaneTx_Valid(0)            => LaneTxValid(i),
                LaneTx_Ready(0)            => LaneTxReady(i),
                LaneRx_Data                => LaneRxData(i),
                LaneRx_K                   => LaneRxK(i),
                LaneRx_Valid(0)            => LaneRxValid(i),
                Lane_Reset(0)              => LaneReset(i),
                Lane_TxOnly(0)             => LaneTxOnly(i),
                Lane_RxOnly(0)             => LaneRxOnly(i),
                Lane_FarEndActive(0)       => LaneFarAct(i),
                Lane_NearCapability        => LaneNearCap(i),
                Lane_State                 => LaneState(i),
                Lane_FarCapability         => LaneFarCap(i),
                Lane_FarCapabilityValid(0) => LaneCapV(i),
                Stat_DataSendingLanes      => open,
                Stat_DataReceivingLanes    => open,
                Stat_AlignState            => open
            );

        i_lane : entity work.ofb_lane
            port map (
                Clk                      => ClkI,
                Rst                      => RstI,
                TxWord_Data              => LaneTxData(i),
                TxWord_K                 => LaneTxK(i),
                TxWord_Valid             => LaneTxValid(i),
                TxWord_Ready             => LaneTxReady(i),
                RxWord_Data              => LaneRxData(i),
                RxWord_K                 => LaneRxK(i),
                RxWord_Valid             => LaneRxValid(i),
                Ctrl_LaneReset           => LaneReset(i),
                Ctrl_TxOnly              => LaneTxOnly(i),
                Ctrl_RxOnly              => LaneRxOnly(i),
                Ctrl_FarEndActive        => LaneFarAct(i),
                Ctrl_NearCapability      => LaneNearCap(i),
                Ctrl_State               => LaneState(i),
                Ctrl_FarCapability       => LaneFarCap(i),
                Ctrl_FarCapabilityValid  => LaneCapV(i),
                PhyTx_Data               => PhyTxData(i),
                PhyTx_K                  => PhyTxK(i),
                PhyRx_Data               => PhyRxData(i),
                PhyRx_K                  => PhyRxK(i),
                PhyRx_CodeErr            => PhyRxCode(i),
                PhyRx_DispErr            => PhyRxDisp(i),
                PhyRx_Valid              => PhyRxValid(i),
                Phy_TxEnable             => TxEnable(i),
                Phy_RxEnable             => RxEnable(i),
                Phy_CdrEnable            => CdrEnable(i),
                Phy_RxInvert             => RxInvert(i),
                Phy_NoSignal             => NoSignal(i),
                Cfg_LaneStart            => DlCfg(i).LaneStart,
                Cfg_AutoStart            => '0',
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

        -------------------------------------------------------------------------------------------
        -- Packet generators and receivers per VC
        -------------------------------------------------------------------------------------------
        g_vc : for v in 0 to TbNumVc_c-1 generate

            p_gen : process is
                variable Seed1_v : positive := 1 + 17 * i + 3 * v;
                variable Seed2_v : positive := 1000 + 7 * i + 11 * v;
                variable Rand_v  : real;
                variable Sent_v  : natural  := 0;
                variable Left_v  : natural;
                variable Term_v  : boolean;
                variable Data_v  : Word_t;
                variable K_v     : WordK_t;
                variable Eep_v   : boolean;

                impure function randInt (lo : natural; hi : natural) return natural is
                begin
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    return lo + natural(floor(Rand_v * real(hi - lo + 1)));
                end function;

            -- Generator
            begin
                TxVcValid(i)(v) <= '0';
                wait until UserRst = '0';

                loop
                    wait until rising_edge(UserClk);
                    if Sent_v < DlCfg(i).Vc(v).Packets then
                        Left_v := randInt(1, DlCfg(i).Vc(v).MaxLen);
                        Eep_v  := randInt(0, 99) < DlCfg(i).Vc(v).EepPct;
                        Term_v := false;

                        while not Term_v loop

                            -- Build one word: data bytes, then the terminator, then Fills
                            for c in 0 to 3 loop
                                if Left_v > 0 then
                                    Data_v(8*c+7 downto 8*c) := std_logic_vector(to_unsigned(randInt(0, 255), 8));
                                    K_v(c)                   := '0';
                                    Left_v                   := Left_v - 1;
                                elsif not Term_v then
                                    if Eep_v then
                                        Data_v(8*c+7 downto 8*c) := CharEep_c;
                                    else
                                        Data_v(8*c+7 downto 8*c) := CharEop_c;
                                    end if;
                                    K_v(c) := '1';
                                    Term_v := true;
                                else
                                    Data_v(8*c+7 downto 8*c) := CharFill_c;
                                    K_v(c)                   := '1';
                                end if;
                            end loop;

                            Sb_v.add_expected(sbVc(1 - i, v), K_v & Data_v);

                            -- Random gap, then hand over the word
                            while randInt(0, 99) < DlCfg(i).Vc(v).GapPct loop
                                wait until rising_edge(UserClk);
                            end loop;

                            TxVcData(i)(32*v+31 downto 32*v) <= Data_v;
                            TxVcK(i)(4*v+3 downto 4*v)       <= K_v;
                            TxVcValid(i)(v)                  <= '1';

                            loop
                                wait until rising_edge(UserClk);
                                exit when TxVcReady(i)(v) = '1';
                            end loop;

                            TxVcValid(i)(v) <= '0';
                        end loop;

                        Sent_v := Sent_v + 1;
                    end if;
                end loop;

            end process;

            p_rx : process (UserClk) is
                variable Seed1_v : positive := 5 + 13 * i + 7 * v;
                variable Seed2_v : positive := 3000 + 3 * i + 19 * v;
                variable Rand_v  : real;
            begin
                if rising_edge(UserClk) then
                    if RxVcValid(i)(v) = '1' and RxVcReady(i)(v) = '1' then
                        Sb_v.check_received(sbVc(i, v), RxVcK(i)(4*v+3 downto 4*v) & RxVcData(i)(32*v+31 downto 32*v));
                    end if;
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    if Rand_v * 100.0 < real(DlCfg(i).Vc(v).ReadyPct) then
                        RxVcReady(i)(v) <= '1';
                    else
                        RxVcReady(i)(v) <= '0';
                    end if;
                end if;
            end process;

        end generate;

        -------------------------------------------------------------------------------------------
        -- Broadcast generator and receiver
        -------------------------------------------------------------------------------------------
        p_bc_gen : process is
            variable Seed1_v : positive := 77 + i;
            variable Seed2_v : positive := 99 + 5 * i;
            variable Rand_v  : real;
            variable Sent_v  : natural  := 0;
            variable Data_v  : std_logic_vector(63 downto 0);
            variable Ch_v    : Char_t;
            variable Type_v  : Char_t;

            impure function randByte return Char_t is
            begin
                uniform(Seed1_v, Seed2_v, Rand_v);
                return std_logic_vector(to_unsigned(natural(floor(Rand_v * 256.0)), 8));
            end function;

        -- Generator
        begin
            TxBcValid(i) <= '0';
            wait until UserRst = '0';

            loop
                wait until rising_edge(UserClk);
                if Sent_v < DlCfg(i).BcSend then

                    for b in 0 to 7 loop
                        Data_v(8*b+7 downto 8*b) := randByte;
                    end loop;

                    Ch_v         := randByte;
                    Type_v       := randByte;
                    Sb_v.add_expected(sbBc(1 - i), "0000" & Data_v(31 downto 0));
                    Sb_v.add_expected(sbBc(1 - i), "0000" & Data_v(63 downto 32));
                    Sb_v.add_expected(sbBc(1 - i), x"00000" & Type_v & Ch_v);
                    TxBcData(i)  <= Data_v;
                    TxBcCh(i)    <= Ch_v;
                    TxBcType(i)  <= Type_v;
                    TxBcValid(i) <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when TxBcReady(i) = '1';
                    end loop;

                    TxBcValid(i) <= '0';
                    Sent_v       := Sent_v + 1;
                    BcSentCnt(i) <= Sent_v;
                end if;
            end loop;

        end process;

        p_bc_rx : process (UserClk) is
        begin
            if rising_edge(UserClk) then
                if RxBcValid(i) = '1' then
                    Sb_v.check_received(sbBc(i), "0000" & RxBcData(i)(31 downto 0));
                    Sb_v.check_received(sbBc(i), "0000" & RxBcData(i)(63 downto 32));
                    Sb_v.check_received(sbBc(i), x"00000" & RxBcType(i) & RxBcCh(i));
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Status collection
        -------------------------------------------------------------------------------------------
        p_stat : process (ClkI) is
            variable Stat_v : EndStat_t;
            variable Init_v : boolean := true;
        begin
            if rising_edge(ClkI) then
                if Init_v then
                    Stat_v := (Sent => (others => 0),
                               RxWords => (others => 0),
                               BcSent => 0,
                               BcRx => 0,
                               BcRxLate => 0,
                               LinkState => "00",
                               LaneActive => '0',
                               HasCredit => (others => '0'),
                               ErbEmpty => '1',
                               Retries => 0,
                               Crc16Errs => 0,
                               Crc8Errs => 0,
                               FrameErrs => 0,
                               SeqErrs => 0,
                               ProtErrs => 0,
                               FarEndResets => 0,
                               Overflows => 0,
                               CreditOvfs => 0,
                               BcDiscards => 0);
                    Init_v := false;
                end if;
                if RstI = '0' then
                    if EvRetry(i) = '1' then
                        Stat_v.Retries := Stat_v.Retries + 1;
                    end if;
                    if EvCrc16(i) = '1' then
                        Stat_v.Crc16Errs := Stat_v.Crc16Errs + 1;
                    end if;
                    if EvCrc8(i) = '1' then
                        Stat_v.Crc8Errs := Stat_v.Crc8Errs + 1;
                    end if;
                    if EvFrame(i) = '1' then
                        Stat_v.FrameErrs := Stat_v.FrameErrs + 1;
                    end if;
                    if EvSeq(i) = '1' then
                        Stat_v.SeqErrs := Stat_v.SeqErrs + 1;
                    end if;
                    if EvProt(i) = '1' then
                        Stat_v.ProtErrs := Stat_v.ProtErrs + 1;
                    end if;
                    if EvFarReset(i) = '1' then
                        Stat_v.FarEndResets := Stat_v.FarEndResets + 1;
                    end if;
                    if InOvf(i) /= (InOvf(i)'range => '0') then
                        Stat_v.Overflows := Stat_v.Overflows + 1;
                    end if;
                    if CreditOvf(i) /= (CreditOvf(i)'range => '0') then
                        Stat_v.CreditOvfs := Stat_v.CreditOvfs + 1;
                    end if;
                    if EvBcDisc(i) = '1' then
                        Stat_v.BcDiscards := Stat_v.BcDiscards + 1;
                    end if;
                end if;
                Stat_v.LinkState  := LinkState(i);
                Stat_v.LaneActive := MlActive(i);
                Stat_v.HasCredit  := HasCredit(i);
                Stat_v.ErbEmpty   := ErbEmpty(i);
                Stat_v.BcSent     := BcSentCnt(i);
                Stat_v.BcRx       := BcRxCnt(i);
                Stat_v.BcRxLate   := BcLateCnt(i);
                DlStat(i)         <= Stat_v;
            end if;
        end process;

        p_bc_cnt : process (UserClk) is
            variable Rx_v   : natural := 0;
            variable Late_v : natural := 0;
        begin
            if rising_edge(UserClk) then
                if RxBcValid(i) = '1' then
                    Rx_v := Rx_v + 1;
                    if RxBcLate(i) = '1' then
                        Late_v := Late_v + 1;
                    end if;
                end if;
                BcRxCnt(i)   <= Rx_v;
                BcLateCnt(i) <= Late_v;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Lane: behavioural Physical adapters and channel
    -----------------------------------------------------------------------------------------------
    i_pa : entity work.ofb_tb_pa_model
        generic map (
            Instance_g => 0
        )
        port map (
            Clk          => ClkI,
            A_Tx_Data    => PhyTxData(0),
            A_Tx_K       => PhyTxK(0),
            A_TxEnable   => TxEnable(0),
            A_RxEnable   => RxEnable(0),
            A_CdrEnable  => CdrEnable(0),
            A_RxInvert   => RxInvert(0),
            A_Rx_Data    => PhyRxData(0),
            A_Rx_K       => PhyRxK(0),
            A_Rx_CodeErr => PhyRxCode(0),
            A_Rx_DispErr => PhyRxDisp(0),
            A_Rx_Valid   => PhyRxValid(0),
            A_NoSignal   => NoSignal(0),
            B_Tx_Data    => PhyTxData(1),
            B_Tx_K       => PhyTxK(1),
            B_TxEnable   => TxEnable(1),
            B_RxEnable   => RxEnable(1),
            B_CdrEnable  => CdrEnable(1),
            B_RxInvert   => RxInvert(1),
            B_Rx_Data    => PhyRxData(1),
            B_Rx_K       => PhyRxK(1),
            B_Rx_CodeErr => PhyRxCode(1),
            B_Rx_DispErr => PhyRxDisp(1),
            B_Rx_Valid   => PhyRxValid(1),
            B_NoSignal   => NoSignal(1)
        );

end architecture;
