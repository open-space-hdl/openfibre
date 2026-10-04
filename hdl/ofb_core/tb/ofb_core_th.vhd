---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the core testbench: two ofb_core (A, B) connected through the behavioural
-- Physical adapter model, AXI4-Lite masters, packet and broadcast generators and receivers.
--
-- Documentation: hdl/ofb_core/docs/verification_plan.md

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
    use work.ofb_tb_pkg.all;
    use work.ofb_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_th is
    port (
        MgmtClk : out   std_logic;
        Rst     : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_core_th is

    signal UserClk : std_logic := '0';
    signal CoreClk : std_logic := '0';
    signal LaneClk : std_logic := '0';
    signal MgmtI   : std_logic := '0';
    signal RstI    : std_logic := '1';

    type VcDataArray_t is array (0 to 1) of std_logic_vector(32*CoreNumVc_c-1 downto 0);
    type VcKArray_t is array (0 to 1) of std_logic_vector(4*CoreNumVc_c-1 downto 0);
    type VcBitArray_t is array (0 to 1) of std_logic_vector(CoreNumVc_c-1 downto 0);
    type BcDataArray_t is array (0 to 1) of std_logic_vector(63 downto 0);
    type BcUserArray_t is array (0 to 1) of std_logic_vector(17 downto 0);
    type BitArray_t is array (0 to 1) of std_logic;
    type WordArray_t is array (0 to 1) of Word_t;
    type KArray_t is array (0 to 1) of WordK_t;
    type AddrArray_t is array (0 to 1) of std_logic_vector(11 downto 0);
    type DataArray_t is array (0 to 1) of std_logic_vector(31 downto 0);
    type StrbArray_t is array (0 to 1) of std_logic_vector(3 downto 0);
    type RespArray_t is array (0 to 1) of std_logic_vector(1 downto 0);

    signal SVcData  : VcDataArray_t;
    signal SVcUser  : VcKArray_t;
    signal SVcValid : VcBitArray_t := (others => (others => '0'));
    signal SVcReady : VcBitArray_t;
    signal MVcData  : VcDataArray_t;
    signal MVcUser  : VcKArray_t;
    signal MVcValid : VcBitArray_t;
    signal MVcReady : VcBitArray_t := (others => (others => '0'));
    signal SBcData  : BcDataArray_t;
    signal SBcUser  : BcUserArray_t;
    signal SBcValid : BitArray_t   := (others => '0');
    signal SBcReady : BitArray_t;
    signal MBcData  : BcDataArray_t;
    signal MBcUser  : BcUserArray_t;
    signal MBcValid : BitArray_t;

    signal ArAddr  : AddrArray_t;
    signal ArValid : BitArray_t;
    signal ArReady : BitArray_t;
    signal AwAddr  : AddrArray_t;
    signal AwValid : BitArray_t;
    signal AwReady : BitArray_t;
    signal WData   : DataArray_t;
    signal WStrb   : StrbArray_t;
    signal WValid  : BitArray_t;
    signal WReady  : BitArray_t;
    signal BResp   : RespArray_t;
    signal BValid  : BitArray_t;
    signal BReady  : BitArray_t;
    signal RData   : DataArray_t;
    signal RResp   : RespArray_t;
    signal RValid  : BitArray_t;
    signal RReady  : BitArray_t;

    signal PhyTxData  : WordArray_t;
    signal PhyTxK     : KArray_t;
    signal PhyRxData  : WordArray_t;
    signal PhyRxK     : KArray_t;
    signal PhyRxCode  : KArray_t;
    signal PhyRxDisp  : KArray_t;
    signal PhyRxValid : BitArray_t;
    signal TxEnable   : BitArray_t;
    signal RxEnable   : BitArray_t;
    signal CdrEnable  : BitArray_t;
    signal RxInvert   : BitArray_t;
    signal NoSignal   : BitArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    UserClk <= not UserClk after 2.6 ns;
    CoreClk <= not CoreClk after 3 ns;
    LaneClk <= not LaneClk after 3.2 ns;
    MgmtI   <= not MgmtI after 5 ns;
    MgmtClk <= MgmtI;
    Rst     <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 200 ns;
        RstI <= '0';
        wait;
    end process;

    g_core : for i in 0 to 1 generate

        i_axi : entity work.ofb_tb_axilite_master
            generic map (
                InstanceIdx_g => AxiA_c + i,
                AddrWidth_g   => 12
            )
            port map (
                Clk     => MgmtI,
                ArAddr  => ArAddr(i),
                ArValid => ArValid(i),
                ArReady => ArReady(i),
                AwAddr  => AwAddr(i),
                AwValid => AwValid(i),
                AwReady => AwReady(i),
                WData   => WData(i),
                WStrb   => WStrb(i),
                WValid  => WValid(i),
                WReady  => WReady(i),
                BResp   => BResp(i),
                BValid  => BValid(i),
                BReady  => BReady(i),
                RData   => RData(i),
                RResp   => RResp(i),
                RValid  => RValid(i),
                RReady  => RReady(i)
            );

        i_core : entity work.ofb_core
            generic map (
                NumVc_g => CoreNumVc_c
            )
            port map (
                Rst               => RstI,
                UserClk           => UserClk,
                CoreClk           => CoreClk,
                LaneClk           => LaneClk,
                MgmtClk           => MgmtI,
                S_Vc_TData        => SVcData(i),
                S_Vc_TUser        => SVcUser(i),
                S_Vc_TValid       => SVcValid(i),
                S_Vc_TReady       => SVcReady(i),
                M_Vc_TData        => MVcData(i),
                M_Vc_TUser        => MVcUser(i),
                M_Vc_TValid       => MVcValid(i),
                M_Vc_TReady       => MVcReady(i),
                S_Bc_TData        => SBcData(i),
                S_Bc_TUser        => SBcUser(i)(16 downto 0),
                S_Bc_TValid       => SBcValid(i),
                S_Bc_TReady       => SBcReady(i),
                M_Bc_TData        => MBcData(i),
                M_Bc_TUser        => MBcUser(i),
                M_Bc_TValid       => MBcValid(i),
                M_Bc_TReady       => '1',
                S_AxiLite_ArAddr  => ArAddr(i),
                S_AxiLite_ArValid => ArValid(i),
                S_AxiLite_ArReady => ArReady(i),
                S_AxiLite_AwAddr  => AwAddr(i),
                S_AxiLite_AwValid => AwValid(i),
                S_AxiLite_AwReady => AwReady(i),
                S_AxiLite_WData   => WData(i),
                S_AxiLite_WStrb   => WStrb(i),
                S_AxiLite_WValid  => WValid(i),
                S_AxiLite_WReady  => WReady(i),
                S_AxiLite_BResp   => BResp(i),
                S_AxiLite_BValid  => BValid(i),
                S_AxiLite_BReady  => BReady(i),
                S_AxiLite_RData   => RData(i),
                S_AxiLite_RResp   => RResp(i),
                S_AxiLite_RValid  => RValid(i),
                S_AxiLite_RReady  => RReady(i),
                Irq               => open,
                PhyTx_Data        => PhyTxData(i),
                PhyTx_K           => PhyTxK(i),
                PhyRx_Data        => PhyRxData(i),
                PhyRx_K           => PhyRxK(i),
                PhyRx_CodeErr     => PhyRxCode(i),
                PhyRx_DispErr     => PhyRxDisp(i),
                PhyRx_Valid(0)    => PhyRxValid(i),
                Phy_TxEnable(0)   => TxEnable(i),
                Phy_RxEnable(0)   => RxEnable(i),
                Phy_CdrEnable(0)  => CdrEnable(i),
                Phy_RxInvert(0)   => RxInvert(i),
                Phy_NoSignal(0)   => NoSignal(i)
            );

        -------------------------------------------------------------------------------------------
        -- Packet generators and receivers per VC
        -------------------------------------------------------------------------------------------
        g_vc : for v in 0 to CoreNumVc_c-1 generate

            p_gen : process is
                variable Seed1_v : positive := 1 + 17 * i + 3 * v;
                variable Seed2_v : positive := 1000 + 7 * i + 11 * v;
                variable Rand_v  : real;
                variable Sent_v  : natural  := 0;
                variable Left_v  : natural;
                variable Term_v  : boolean;
                variable Data_v  : Word_t;
                variable K_v     : WordK_t;
                variable Raw_v   : std_logic_vector(36 downto 0);

                impure function randInt (lo : natural; hi : natural) return natural is
                begin
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    return lo + natural(floor(Rand_v * real(hi - lo + 1)));
                end function;

                procedure sendWord (
                    data : Word_t;
                    k    : WordK_t) is
                begin
                    SVcData(i)(32*v+31 downto 32*v) <= data;
                    SVcUser(i)(4*v+3 downto 4*v)    <= k;
                    SVcValid(i)(v)                  <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when SVcReady(i)(v) = '1';
                    end loop;

                    SVcValid(i)(v) <= '0';
                end procedure;

            -- Generator
            begin
                SVcValid(i)(v) <= '0';

                loop
                    wait until rising_edge(UserClk);
                    if i = 0 and v = 0 and RawQueue_v.count > 0 then
                        -- Raw words (expected words are added by the sequencer)
                        Raw_v := RawQueue_v.pop;
                        sendWord(Raw_v(31 downto 0), Raw_v(35 downto 32));
                    elsif Sent_v < CoreCfg(i).Vc(v).Packets then
                        Left_v := randInt(1, CoreCfg(i).Vc(v).MaxLen);
                        Term_v := false;

                        while not Term_v loop

                            for c in 0 to 3 loop
                                if Left_v > 0 then
                                    Data_v(8*c+7 downto 8*c) := std_logic_vector(to_unsigned(randInt(0, 255), 8));
                                    K_v(c)                   := '0';
                                    Left_v                   := Left_v - 1;
                                elsif not Term_v then
                                    Data_v(8*c+7 downto 8*c) := CharEop_c;
                                    K_v(c)                   := '1';
                                    Term_v                   := true;
                                else
                                    Data_v(8*c+7 downto 8*c) := CharFill_c;
                                    K_v(c)                   := '1';
                                end if;
                            end loop;

                            CoreSb_v.add_expected(1 + (1 - i) * CoreNumVc_c + v, K_v & Data_v);
                            sendWord(Data_v, K_v);
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
                    if MVcValid(i)(v) = '1' and MVcReady(i)(v) = '1' then
                        CoreSb_v.check_received(1 + i * CoreNumVc_c + v,
                                                MVcUser(i)(4*v+3 downto 4*v) & MVcData(i)(32*v+31 downto 32*v));
                    end if;
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    if Rand_v * 100.0 < real(CoreCfg(i).Vc(v).ReadyPct) then
                        MVcReady(i)(v) <= '1';
                    else
                        MVcReady(i)(v) <= '0';
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
            variable User_v  : std_logic_vector(15 downto 0);

            impure function randByte return Char_t is
            begin
                uniform(Seed1_v, Seed2_v, Rand_v);
                return std_logic_vector(to_unsigned(natural(floor(Rand_v * 256.0)), 8));
            end function;

        -- Generator
        begin
            SBcValid(i) <= '0';

            loop
                wait until rising_edge(UserClk);
                if Sent_v < CoreCfg(i).BcSend then

                    for b in 0 to 7 loop
                        Data_v(8*b+7 downto 8*b) := randByte;
                    end loop;

                    User_v      := randByte & randByte;
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), "0000" & Data_v(31 downto 0));
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), "0000" & Data_v(63 downto 32));
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), x"00000" & User_v);
                    SBcData(i)  <= Data_v;
                    SBcUser(i)  <= "00" & User_v;
                    SBcValid(i) <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when SBcReady(i) = '1';
                    end loop;

                    SBcValid(i) <= '0';
                    Sent_v      := Sent_v + 1;
                end if;
            end loop;

        end process;

        p_bc_rx : process (UserClk) is
        begin
            if rising_edge(UserClk) then
                if MBcValid(i) = '1' then
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, "0000" & MBcData(i)(31 downto 0));
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, "0000" & MBcData(i)(63 downto 32));
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, x"00000" & MBcUser(i)(15 downto 0));
                end if;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Behavioural Physical adapters and channel (lane clock)
    -----------------------------------------------------------------------------------------------
    i_pa : entity work.ofb_tb_pa_model
        generic map (
            Instance_g => 0
        )
        port map (
            Clk          => LaneClk,
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
