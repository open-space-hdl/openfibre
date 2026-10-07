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

library uvvm_util;
    context uvvm_util.uvvm_util_context;

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
    generic (
        NumLanes_g   : positive range 1 to 4 := 1;
        CoreHalfPs_g : positive              := 3000 -- Half period of CoreClk in ps
    );
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

    constant N_c : positive := NumLanes_g;

    type VcDataArray_t is array (0 to 1) of std_logic_vector(32*N_c*CoreNumVc_c-1 downto 0);
    type VcKArray_t is array (0 to 1) of std_logic_vector(4*N_c*CoreNumVc_c-1 downto 0);
    type VcBitArray_t is array (0 to 1) of std_logic_vector(CoreNumVc_c-1 downto 0);
    type BcDataArray_t is array (0 to 1) of std_logic_vector(63 downto 0);
    type BcUserArray_t is array (0 to 1) of std_logic_vector(17 downto 0);
    type BitArray_t is array (0 to 1) of std_logic;
    type WordArray_t is array (0 to 1) of std_logic_vector(32*N_c-1 downto 0);
    type KArray_t is array (0 to 1) of std_logic_vector(4*N_c-1 downto 0);
    type LaneArray_t is array (0 to 1) of std_logic_vector(N_c-1 downto 0);
    type AddrArray_t is array (0 to 1) of std_logic_vector(11 downto 0);
    type DataArray_t is array (0 to 1) of std_logic_vector(31 downto 0);
    type StrbArray_t is array (0 to 1) of std_logic_vector(3 downto 0);
    type RespArray_t is array (0 to 1) of std_logic_vector(1 downto 0);
    type SlotArray_t is array (0 to 1) of std_logic_vector(5 downto 0);

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
    signal SchSlot  : SlotArray_t  := (others => (others => '0'));
    signal SchValid : BitArray_t   := (others => '0');

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
    signal PhyRxValid : LaneArray_t;
    signal TxEnable   : LaneArray_t;
    signal RxEnable   : LaneArray_t;
    signal CdrEnable  : LaneArray_t;
    signal RxInvert   : LaneArray_t;
    signal NoSignal   : LaneArray_t;
    signal SerNearLb  : LaneArray_t;
    signal SerFarLb   : LaneArray_t;
    signal BitSync    : LaneArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    UserClk <= not UserClk after 2.6 ns;
    CoreClk <= not CoreClk after CoreHalfPs_g * 1 ps;
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

        -- Bit synchronisation of the model: signal at the receiver and CDR enabled
        BitSync(i) <= not NoSignal(i) and CdrEnable(i);

        i_core : entity work.ofb_core
            generic map (
                NumVc_g     => CoreNumVc_c,
                NumLanes_g  => N_c,
                VcInDepth_g => 256 * N_c
            )
            port map (
                Rst                    => RstI,
                UserClk                => UserClk,
                CoreClk                => CoreClk,
                LaneClk                => LaneClk,
                MgmtClk                => MgmtI,
                S_Vc_TData             => SVcData(i),
                S_Vc_TUser             => SVcUser(i),
                S_Vc_TValid            => SVcValid(i),
                S_Vc_TReady            => SVcReady(i),
                M_Vc_TData             => MVcData(i),
                M_Vc_TUser             => MVcUser(i),
                M_Vc_TValid            => MVcValid(i),
                M_Vc_TReady            => MVcReady(i),
                S_Bc_TData             => SBcData(i),
                S_Bc_TUser             => SBcUser(i)(16 downto 0),
                S_Bc_TValid            => SBcValid(i),
                S_Bc_TReady            => SBcReady(i),
                M_Bc_TData             => MBcData(i),
                M_Bc_TUser             => MBcUser(i),
                M_Bc_TValid            => MBcValid(i),
                M_Bc_TReady            => '1',
                S_Sched_Slot           => SchSlot(i),
                S_Sched_Valid          => SchValid(i),
                S_AxiLite_ArAddr       => ArAddr(i),
                S_AxiLite_ArValid      => ArValid(i),
                S_AxiLite_ArReady      => ArReady(i),
                S_AxiLite_AwAddr       => AwAddr(i),
                S_AxiLite_AwValid      => AwValid(i),
                S_AxiLite_AwReady      => AwReady(i),
                S_AxiLite_WData        => WData(i),
                S_AxiLite_WStrb        => WStrb(i),
                S_AxiLite_WValid       => WValid(i),
                S_AxiLite_WReady       => WReady(i),
                S_AxiLite_BResp        => BResp(i),
                S_AxiLite_BValid       => BValid(i),
                S_AxiLite_BReady       => BReady(i),
                S_AxiLite_RData        => RData(i),
                S_AxiLite_RResp        => RResp(i),
                S_AxiLite_RValid       => RValid(i),
                S_AxiLite_RReady       => RReady(i),
                Irq                    => open,
                PhyTx_Data             => PhyTxData(i),
                PhyTx_K                => PhyTxK(i),
                PhyRx_Data             => PhyRxData(i),
                PhyRx_K                => PhyRxK(i),
                PhyRx_CodeErr          => PhyRxCode(i),
                PhyRx_DispErr          => PhyRxDisp(i),
                PhyRx_Valid            => PhyRxValid(i),
                Phy_TxEnable           => TxEnable(i),
                Phy_RxEnable           => RxEnable(i),
                Phy_CdrEnable          => CdrEnable(i),
                Phy_RxInvert           => RxInvert(i),
                Phy_NoSignal           => NoSignal(i),
                Phy_SerialNearLoopback => SerNearLb(i),
                Phy_SerialFarLoopback  => SerFarLb(i),
                Phy_BitSync            => BitSync(i)
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
                variable Pos_v   : natural  := 0;
                variable BeatD_v : std_logic_vector(32*N_c-1 downto 0);
                variable BeatK_v : std_logic_vector(4*N_c-1 downto 0);
                variable Cls_v   : natural range 0 to 3;

                impure function randInt (lo : natural; hi : natural) return natural is
                begin
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    return lo + natural(floor(Rand_v * real(hi - lo + 1)));
                end function;

                -- Word into the beat of N words; the beat is sent when it is full or flushed
                procedure sendWord (
                    data  : Word_t;
                    k     : WordK_t;
                    flush : boolean := false) is
                begin
                    BeatD_v(32*Pos_v+31 downto 32*Pos_v) := data;
                    BeatK_v(4*Pos_v+3 downto 4*Pos_v)    := k;
                    Pos_v                                := Pos_v + 1;
                    if flush then

                        -- Rest of the beat: Fill words
                        while Pos_v < N_c loop
                            BeatD_v(32*Pos_v+31 downto 32*Pos_v) := x"FBFBFBFB";
                            BeatK_v(4*Pos_v+3 downto 4*Pos_v)    := "1111";
                            Pos_v                                := Pos_v + 1;
                        end loop;

                    end if;
                    if Pos_v = N_c then
                        Pos_v                                      := 0;
                        SVcData(i)(32*N_c*(v+1)-1 downto 32*N_c*v) <= BeatD_v;
                        SVcUser(i)(4*N_c*(v+1)-1 downto 4*N_c*v)   <= BeatK_v;
                        SVcValid(i)(v)                             <= '1';

                        loop
                            wait until rising_edge(UserClk);
                            exit when SVcReady(i)(v) = '1';
                        end loop;

                        SVcValid(i)(v) <= '0';
                    end if;
                end procedure;

            -- Generator
            begin
                SVcValid(i)(v) <= '0';

                loop
                    wait until rising_edge(UserClk);
                    if i = 0 and v = 0 and RawQueue_v.count > 0 then
                        -- Raw words (expected words are added by the sequencer)
                        Raw_v := RawQueue_v.pop;
                        sendWord(Raw_v(31 downto 0), Raw_v(35 downto 32), true);
                    elsif Sent_v < CoreCfg(i).Vc(v).Packets then
                        if CoreCfg(i).Vc(v).LenClasses then
                            -- The length classes of the functional coverage in turn
                            Cls_v  := Sent_v mod 4;
                            Left_v := randInt(LenMin_c(Cls_v), LenMax_c(Cls_v));
                        else
                            Left_v := randInt(CoreCfg(i).Vc(v).MinLen, CoreCfg(i).Vc(v).MaxLen);
                        end if;
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
                            -- Every packet starts in a new beat
                            sendWord(Data_v, K_v, Term_v);
                        end loop;

                        Sent_v := Sent_v + 1;
                    end if;
                end loop;

            end process;

            p_rx : process (UserClk) is
                constant Inst_c  : positive := 1 + i * CoreNumVc_c + v;
                variable Seed1_v : positive := 5 + 13 * i + 7 * v;
                variable Seed2_v : positive := 3000 + 3 * i + 19 * v;
                variable Rand_v  : real;
                variable Word_v  : std_logic_vector(35 downto 0);
                variable Exp_v   : std_logic_vector(35 downto 0);
                variable InPkt_v : boolean  := false;
                variable Eeps_v  : natural  := 0;
                variable Lost_v  : natural  := 0;
                variable Words_v : natural  := 0;
                variable Bytes_v : natural  := 0;

                -- A character of the word is an EOP or EEP (with an EEP only: the EEP)
                function hasEnd (w : std_logic_vector(35 downto 0); eepOnly : boolean := false) return boolean is
                begin

                    for c in 0 to 3 loop
                        if w(32 + c) = '1' and (w(8*c+7 downto 8*c) = CharEep_c or
                                                (not eepOnly and w(8*c+7 downto 8*c) = CharEop_c)) then
                            return true;
                        end if;
                    end loop;

                    return false;
                end function;

                -- Lossy comparison: the expected word; or an EEP that ends the current packet early; or,
                -- between packets, the first word of a later packet (the packets before it were lost)
                procedure checkLossy (w : std_logic_vector(35 downto 0)) is
                begin
                    if not CoreSb_v.is_empty(Inst_c) and CoreSb_v.peek_expected(Inst_c) = w then
                        CoreSb_v.check_received(Inst_c, w);
                        InPkt_v := not hasEnd(w);
                    elsif hasEnd(w, true) then

                        -- Packet ended early: its remaining words are not expected any more
                        while InPkt_v and not CoreSb_v.is_empty(Inst_c) loop
                            Exp_v   := CoreSb_v.fetch_expected(Inst_c);
                            InPkt_v := not hasEnd(Exp_v);
                        end loop;

                        InPkt_v := false;
                        Eeps_v  := Eeps_v + 1;
                        log(ID_SEQUENCER, "Core " & to_string(i) & ", VC " & to_string(v) & ": packet ended with EEP");
                    elsif InPkt_v then
                        alert(error, "Core " & to_string(i) & ", VC " & to_string(v) & ": wrong word inside a packet " &
                              to_hstring(w));
                    else

                        -- Lost packets: drop whole expected packets up to one that starts with the word
                        while not CoreSb_v.is_empty(Inst_c) loop
                            exit when CoreSb_v.peek_expected(Inst_c) = w;

                            loop
                                Exp_v := CoreSb_v.fetch_expected(Inst_c);
                                exit when hasEnd(Exp_v) or CoreSb_v.is_empty(Inst_c);
                            end loop;

                            Lost_v := Lost_v + 1;
                            log(ID_SEQUENCER, "Core " & to_string(i) & ", VC " & to_string(v) & ": packet lost");
                        end loop;

                        if CoreSb_v.is_empty(Inst_c) then
                            alert(error, "Core " & to_string(i) & ", VC " & to_string(v) & ": unexpected word " &
                                  to_hstring(w));
                        else
                            CoreSb_v.check_received(Inst_c, w);
                            InPkt_v := not hasEnd(w);
                        end if;
                    end if;
                    CoreRxEep(i, v)  <= Eeps_v;
                    CoreRxLost(i, v) <= Lost_v;
                end procedure;

            -- Receiver
            begin
                if rising_edge(UserClk) then
                    if MVcValid(i)(v) = '1' and MVcReady(i)(v) = '1' then

                        -- Words of four Fills carry no N-Char and are not compared
                        for w in 0 to N_c-1 loop
                            if MVcUser(i)(4*(N_c*v+w)+3 downto 4*(N_c*v+w)) /= "1111" or
                               MVcData(i)(32*(N_c*v+w)+31 downto 32*(N_c*v+w)) /= x"FBFBFBFB" then
                                Word_v  := MVcUser(i)(4*(N_c*v+w)+3 downto 4*(N_c*v+w)) &
                                           MVcData(i)(32*(N_c*v+w)+31 downto 32*(N_c*v+w));
                                Words_v := Words_v + 1;
                                if CoreCfg(i).Lossy then
                                    checkLossy(Word_v);
                                else
                                    CoreSb_v.check_received(Inst_c, Word_v);
                                end if;

                                -- Functional coverage: length and end of the packets sent by the other core
                                for c in 0 to 3 loop
                                    if Word_v(32 + c) = '0' then
                                        Bytes_v := Bytes_v + 1;
                                    elsif Word_v(8*c+7 downto 8*c) = CharEop_c then
                                        CovPkt_v.sample_coverage((1 - i, v, Bytes_v));
                                        CovEnd_v.sample_coverage((1 - i, 0));
                                        Bytes_v := 0;
                                    elsif Word_v(8*c+7 downto 8*c) = CharEep_c then
                                        CovEnd_v.sample_coverage((1 - i, 1));
                                        Bytes_v := 0;
                                    end if;
                                end loop;

                            end if;
                        end loop;

                        CoreRxWords(i, v) <= Words_v;
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
            variable User_v  : std_logic_vector(16 downto 0);
            variable Del_v   : Char_t;

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

                    -- Random DELAYED flag, B_TYPE and channel
                    Del_v       := randByte;
                    User_v      := Del_v(0) & randByte & randByte;
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), "0000" & Data_v(31 downto 0));
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), "0000" & Data_v(63 downto 32));
                    CoreSb_v.add_expected(1 + 2 * CoreNumVc_c + (1 - i), x"0000" & "000" & User_v);
                    SBcData(i)  <= Data_v;
                    SBcUser(i)  <= '0' & User_v;
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
            constant Inst_c  : positive := 1 + 2 * CoreNumVc_c + i;
            variable Lost_v  : natural  := 0;
            variable Dummy_v : std_logic_vector(35 downto 0);
        begin
            if rising_edge(UserClk) then
                if MBcValid(i) = '1' then

                    -- Lossy comparison: messages before the received one may be lost (three elements each)
                    while CoreCfg(i).Lossy and not CoreSb_v.is_empty(Inst_c) loop
                        exit when CoreSb_v.peek_expected(Inst_c) = "0000" & MBcData(i)(31 downto 0);

                        for e in 0 to 2 loop
                            if not CoreSb_v.is_empty(Inst_c) then
                                Dummy_v := CoreSb_v.fetch_expected(Inst_c);
                            end if;
                        end loop;

                        Lost_v := Lost_v + 1;
                    end loop;

                    CoreBcLost(i) <= Lost_v;
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, "0000" & MBcData(i)(31 downto 0));
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, "0000" & MBcData(i)(63 downto 32));
                    -- DELAYED, B_TYPE and channel; LATE depends on the error recovery
                    CoreSb_v.check_received(1 + 2 * CoreNumVc_c + i, x"0000" & "000" & MBcUser(i)(16 downto 0));
                    CovBc_v.sample_coverage((1 - i, boolean'pos(MBcUser(i)(16) = '1')));
                    CovLate_v.sample_coverage((1 - i, boolean'pos(MBcUser(i)(17) = '1')));
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- SCHEDULE.request: one strobe per request of the sequencer
        -------------------------------------------------------------------------------------------
        p_sched : process (UserClk) is
            variable Done_v : natural := 0;
        begin
            if rising_edge(UserClk) then
                SchValid(i) <= '0';
                if CoreCfg(i).SchedReq /= Done_v then
                    Done_v      := Done_v + 1;
                    SchSlot(i)  <= std_logic_vector(to_unsigned(CoreCfg(i).Slot, 6));
                    SchValid(i) <= '1';
                end if;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Behavioural Physical adapters and channel (lane clock), one per lane
    -----------------------------------------------------------------------------------------------
    g_pa : for l in 0 to N_c-1 generate

        i_pa : entity work.ofb_tb_pa_model
            generic map (
                Instance_g => l
            )
            port map (
                Clk          => LaneClk,
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
                A_NearSerLb  => SerNearLb(0)(l),
                A_FarSerLb   => SerFarLb(0)(l),
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
                B_NoSignal   => NoSignal(1)(l),
                B_NearSerLb  => SerNearLb(1)(l),
                B_FarSerLb   => SerFarLb(1)(l)
            );

    end generate;

end architecture;
