---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the row-level Data Link layer testbench: one ofb_dl with a far-end model at the
-- row interface, user ports driven from queues, status collection.
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
    use work.ofb_dl_pkg.all;
    use work.ofb_dl_row_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_row_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_dl_row_th is

    constant ClkPeriod_c  : time := 6.4 ns;
    constant UserPeriod_c : time := 5.2 ns;

    signal ClkI    : std_logic := '0';
    signal RstI    : std_logic := '1';
    signal UserClk : std_logic := '0';
    signal UserRst : std_logic := '1';

    signal TxVcData  : std_logic_vector(32*RowNumVc_c-1 downto 0);
    signal TxVcK     : std_logic_vector(4*RowNumVc_c-1 downto 0);
    signal TxVcValid : std_logic_vector(RowNumVc_c-1 downto 0) := (others => '0');
    signal TxVcReady : std_logic_vector(RowNumVc_c-1 downto 0);
    signal RxVcData  : std_logic_vector(32*RowNumVc_c-1 downto 0);
    signal RxVcK     : std_logic_vector(4*RowNumVc_c-1 downto 0);
    signal RxVcValid : std_logic_vector(RowNumVc_c-1 downto 0);
    signal RxVcReady : std_logic_vector(RowNumVc_c-1 downto 0) := (others => '0');

    signal TxRowData  : Word_t;
    signal TxRowK     : WordK_t;
    signal TxRowValid : std_logic;
    signal TxRowReady : std_logic := '0';
    signal RxRowData  : Word_t;
    signal RxRowK     : WordK_t;
    signal RxRowCrc   : std_logic;
    signal RxRowValid : std_logic := '0';
    signal FarCap     : Char_t    := x"00";
    signal FarCapV    : std_logic := '0';
    signal LinkState  : std_logic_vector(1 downto 0);

    signal RxBcData  : std_logic_vector(63 downto 0);
    signal RxBcValid : std_logic;
    signal BcTxValid : std_logic := '0';
    signal BcTxReady : std_logic;

    signal HasCredit : std_logic_vector(RowNumVc_c-1 downto 0);
    signal CreditOvf : std_logic_vector(RowNumVc_c-1 downto 0);
    signal InOvf     : std_logic_vector(RowNumVc_c-1 downto 0);
    signal EvCrc16   : std_logic;
    signal EvCrc8    : std_logic;
    signal EvFrame   : std_logic;
    signal EvSeq     : std_logic;
    signal EvRetry   : std_logic;
    signal EvProt    : std_logic;
    signal EvFarRst  : std_logic;
    signal ErbEmpty  : std_logic;
    signal RxErrSt   : std_logic_vector(1 downto 0);
    signal WordIdSt  : std_logic_vector(2 downto 0);
    signal FarRxSeq  : natural   := 0;
    signal FarPol    : std_logic := '0';

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

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_dl
        generic map (
            NumVc_g        => RowNumVc_c,
            VcOutDepth_g   => 128,
            VcInDepth_g    => 128,
            ErbWords_g     => 256,
            ErbDataItems_g => 8,
            ErbFctItems_g  => 4,
            ErbBcItems_g   => 2
        )
        port map (
            Clk                   => ClkI,
            Rst                   => RstI,
            UserClk               => UserClk,
            UserRst               => UserRst,
            TxVc_Data             => TxVcData,
            TxVc_K                => TxVcK,
            TxVc_Valid            => TxVcValid,
            TxVc_Ready            => TxVcReady,
            RxVc_Data             => RxVcData,
            RxVc_K                => RxVcK,
            RxVc_Valid            => RxVcValid,
            RxVc_Ready            => RxVcReady,
            TxBc_Data             => BcTxData,
            TxBc_Channel          => BcTxChannel,
            TxBc_Type             => BcTxType,
            TxBc_Valid            => BcTxValid,
            TxBc_Ready            => BcTxReady,
            RxBc_Data             => RxBcData,
            RxBc_Channel          => open,
            RxBc_Type             => open,
            RxBc_Delayed          => open,
            RxBc_Late             => open,
            RxBc_Valid            => RxBcValid,
            RxBc_Ready            => '1',
            TxRow_Data            => TxRowData,
            TxRow_K               => TxRowK,
            TxRow_Mask            => open,
            TxRow_Replicate       => open,
            TxRow_Valid           => TxRowValid,
            TxRow_Ready           => TxRowReady,
            RxRow_Data            => RxRowData,
            RxRow_K               => RxRowK,
            RxRow_Mask            => "1",
            RxRow_CrcErr          => RxRowCrc,
            RxRow_Valid           => RxRowValid,
            Ml_LinkReset          => open,
            Ml_LaneReset          => open,
            Ml_NearCapability     => open,
            Ml_FarCapability      => FarCap,
            Ml_FarCapabilityValid => FarCapV,
            Ml_LaneActive         => RowCfg.LaneActive,
            Cfg_LinkReset         => RowCfg.LinkReset,
            Cfg_BcInterval        => RowCfg.BcInterval,
            Stat_HasCredit        => HasCredit,
            Ev_CreditOverflow     => CreditOvf,
            Ev_InputOverflow      => InOvf,
            Ev_Crc16Err           => EvCrc16,
            Ev_Crc8Err            => EvCrc8,
            Ev_FrameErr           => EvFrame,
            Ev_SeqErr             => EvSeq,
            Ev_Retry              => EvRetry,
            Ev_ProtocolError      => EvProt,
            Ev_FarEndLinkReset    => EvFarRst,
            Stat_ErbEmpty         => ErbEmpty,
            Stat_LinkResetState   => LinkState,
            Stat_RxErrState       => RxErrSt,
            Stat_WordIdState      => WordIdSt
        );

    -----------------------------------------------------------------------------------------------
    -- Far-end model: transmit rows (log, automatic ACK), receive rows (queue), capability
    -----------------------------------------------------------------------------------------------
    p_tx_rows : process (ClkI) is
        variable Seed1_v : positive := 3;
        variable Seed2_v : positive := 7;
        variable Rand_v  : real;
        variable Kind_v  : DlKind_t;
        variable Seq_v   : SeqNum_t;
        variable RxSeq_v : natural  := 0;
    begin
        if rising_edge(ClkI) then
            if TxRowValid = '1' and TxRowReady = '1' then
                if RowCfg.TxLogOn then
                    TxLog_v.push(TxRowK & TxRowData);
                end if;
                Kind_v := dlWordKind(TxRowData, TxRowK);
                if Kind_v = KindEdf then
                    Seq_v := TxRowData(15 downto 8);
                else
                    Seq_v := TxRowData(23 downto 16);
                end if;
                if (Kind_v = KindEdf or Kind_v = KindEbf or Kind_v = KindFct) and
                   to_integer(unsigned(Seq_v(6 downto 0))) = (RxSeq_v + 1) mod 128 and Seq_v(7) = FarPolCmd then
                    RxSeq_v := (RxSeq_v + 1) mod 128;
                    if RowCfg.AutoAck then
                        RxQueue_v.push('0' & KCtrl_c & wordAck(FarPolCmd & std_logic_vector(to_unsigned(RxSeq_v, 7))));
                    end if;
                end if;
            end if;
            if RstI = '1' or LinkState = "01" then
                RxSeq_v := 0;
            end if;
            FarRxSeq <= RxSeq_v;
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Rand_v * 100.0 < real(RowCfg.TxReadyPct) then
                TxRowReady <= '1';
            else
                TxRowReady <= '0';
            end if;
        end if;
    end process;

    p_rx_rows : process (ClkI) is
        variable Word_v : std_logic_vector(36 downto 0);
    begin
        if rising_edge(ClkI) then
            RxRowValid <= '0';
            if RstI = '0' and RxQueue_v.count > 0 then
                Word_v     := RxQueue_v.pop;
                RxRowData  <= Word_v(31 downto 0);
                RxRowK     <= Word_v(35 downto 32);
                RxRowCrc   <= Word_v(36);
                RxRowValid <= '1';
            end if;
        end if;
    end process;

    p_cap : process (ClkI) is
        variable Prev_v : std_logic_vector(1 downto 0) := "00";
    begin
        if rising_edge(ClkI) then
            FarCapV <= '0';
            if RowCfg.AutoCap and LinkState = "10" and Prev_v /= "10" then
                FarCap  <= x"05";
                FarCapV <= '1';
            end if;
            Prev_v := LinkState;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- User side: VC ports from queues to logs, broadcast messages
    -----------------------------------------------------------------------------------------------
    g_vc : for v in 0 to RowNumVc_c-1 generate

        p_vc_tx : process is
            variable Word_v : std_logic_vector(36 downto 0);
        begin
            TxVcValid(v) <= '0';
            wait until UserRst = '0';

            loop
                wait until rising_edge(UserClk);
                if (v = 0 and VcTxQueue0_v.count > 0) or (v = 1 and VcTxQueue1_v.count > 0) then
                    if v = 0 then
                        Word_v := VcTxQueue0_v.pop;
                    else
                        Word_v := VcTxQueue1_v.pop;
                    end if;
                    TxVcData(32*v+31 downto 32*v) <= Word_v(31 downto 0);
                    TxVcK(4*v+3 downto 4*v)       <= Word_v(35 downto 32);
                    TxVcValid(v)                  <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when TxVcReady(v) = '1';
                    end loop;

                    TxVcValid(v) <= '0';
                end if;
            end loop;

        end process;

        p_vc_rx : process (UserClk) is
            variable Seed1_v : positive := 11 + v;
            variable Seed2_v : positive := 13 + v;
            variable Rand_v  : real;
        begin
            if rising_edge(UserClk) then
                if RxVcValid(v) = '1' and RxVcReady(v) = '1' then
                    if v = 0 then
                        VcRxLog0_v.push(RxVcK(4*v+3 downto 4*v) & RxVcData(32*v+31 downto 32*v));
                    else
                        VcRxLog1_v.push(RxVcK(4*v+3 downto 4*v) & RxVcData(32*v+31 downto 32*v));
                    end if;
                end if;
                uniform(Seed1_v, Seed2_v, Rand_v);
                if Rand_v * 100.0 < real(RowCfg.RxReadyPct) then
                    RxVcReady(v) <= '1';
                else
                    RxVcReady(v) <= '0';
                end if;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Status
    -----------------------------------------------------------------------------------------------
    p_stat : process (ClkI) is
        variable Stat_v : RowStat_t;
        variable Init_v : boolean := true;
    begin
        if rising_edge(ClkI) then
            if Init_v then
                Stat_v := (LinkState => "00",
                           RxErrState => "00",
                           WordIdState => "000",
                           ErbEmpty => '1',
                           HasCredit => (others => '0'),
                           FarRxSeq => 0,
                           FarPol => '0',
                           Retries => 0,
                           Crc16Errs => 0,
                           Crc8Errs => 0,
                           FrameErrs => 0,
                           SeqErrs => 0,
                           ProtErrs => 0,
                           CreditOvfs => 0,
                           InputOvfs => 0,
                           FarEndResets => 0,
                           BcRx => 0);
                Init_v := false;
            end if;
            if EvRetry = '1' then
                Stat_v.Retries := Stat_v.Retries + 1;
            end if;
            if EvCrc16 = '1' then
                Stat_v.Crc16Errs := Stat_v.Crc16Errs + 1;
            end if;
            if EvCrc8 = '1' then
                Stat_v.Crc8Errs := Stat_v.Crc8Errs + 1;
            end if;
            if EvFrame = '1' then
                Stat_v.FrameErrs := Stat_v.FrameErrs + 1;
            end if;
            if EvSeq = '1' then
                Stat_v.SeqErrs := Stat_v.SeqErrs + 1;
            end if;
            if EvProt = '1' then
                Stat_v.ProtErrs := Stat_v.ProtErrs + 1;
            end if;
            if CreditOvf /= (CreditOvf'range => '0') then
                Stat_v.CreditOvfs := Stat_v.CreditOvfs + 1;
            end if;
            if InOvf /= (InOvf'range => '0') then
                Stat_v.InputOvfs := Stat_v.InputOvfs + 1;
            end if;
            if EvFarRst = '1' then
                Stat_v.FarEndResets := Stat_v.FarEndResets + 1;
            end if;
            Stat_v.LinkState   := LinkState;
            Stat_v.RxErrState  := RxErrSt;
            Stat_v.WordIdState := WordIdSt;
            Stat_v.ErbEmpty    := ErbEmpty;
            Stat_v.HasCredit   := HasCredit;
            Stat_v.FarRxSeq    := FarRxSeq;
            Stat_v.FarPol      := FarPolCmd;
            Stat_v.BcRx        := BcRxCount;
            RowStat            <= Stat_v;
        end if;
    end process;

    p_bc_tx : process is
        variable Sent_v : natural := 0;
    begin
        BcTxValid <= '0';
        wait until UserRst = '0';

        loop
            wait until rising_edge(UserClk);
            if Sent_v < BcTxReq then
                BcTxValid <= '1';

                loop
                    wait until rising_edge(UserClk);
                    exit when BcTxReady = '1';
                end loop;

                BcTxValid <= '0';
                Sent_v    := Sent_v + 1;
            end if;
        end loop;

    end process;

    p_bc_rx : process (UserClk) is
        variable Cnt_v : natural := 0;
    begin
        if rising_edge(UserClk) then
            if RxBcValid = '1' then
                Cnt_v := Cnt_v + 1;
            end if;
            BcRxCount <= Cnt_v;
        end if;
    end process;

end architecture;
