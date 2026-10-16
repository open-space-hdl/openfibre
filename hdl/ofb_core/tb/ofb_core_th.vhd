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

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_core_th is
    generic (
        NumLanes_g      : positive range 1 to 4  := 1;
        NumVc_g         : positive range 1 to 32 := 4;
        CoreHalfPs_g    : positive               := 3000; -- Half period of CoreClk in ps
        LaneHalfPs_g    : positive               := 3200; -- Half period of LaneClk in ps
        VcOutDepth_g    : positive               := 128;
        VcInDepth_g     : natural                := 0;    -- 0: 256 x NumLanes_g words
        ErbRows_g       : positive               := 512;
        InitPrbsWords_g : natural range 0 to 64  := 64;
        LaneStartA_g    : boolean                := false; -- LaneStart_g of core A (B: false)
        AutoStart_g     : boolean                := true   -- AutoStart_g of both cores
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

    signal UserClk  : std_logic := '0';
    signal CoreClkG : std_logic := '0'; -- generated core clock
    signal LaneClkG : std_logic := '0'; -- generated lane clock
    signal MgmtI    : std_logic := '0';
    signal RstI     : std_logic := '1';

    constant N_c : positive := NumLanes_g;

    -- Bytes per beat of the VC ports
    constant B_c : positive := 4 * N_c;

    constant VcInDepth_c : positive := choose(VcInDepth_g = 0, 256 * N_c, VcInDepth_g);

    type VcDataArray_t is array (0 to 1) of std_logic_vector(32*N_c*NumVc_g-1 downto 0);
    type VcKeepArray_t is array (0 to 1) of std_logic_vector(B_c*NumVc_g-1 downto 0);
    type VcBitArray_t is array (0 to 1) of std_logic_vector(NumVc_g-1 downto 0);
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
    signal SVcKeep  : VcKeepArray_t;
    signal SVcLast  : VcBitArray_t;
    signal SVcUser  : VcBitArray_t;
    signal SVcValid : VcBitArray_t := (others => (others => '0'));
    signal SVcReady : VcBitArray_t;
    signal MVcData  : VcDataArray_t;
    signal MVcKeep  : VcKeepArray_t;
    signal MVcLast  : VcBitArray_t;
    signal MVcUser  : VcBitArray_t;
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
    signal TxReady    : std_logic_vector(0 to 1) := "00";

    -- Clocks of the cores and of the channel model: one delta cycle after the generated clocks, the
    -- clocks of a core gated by its run flags (taken while the generated clock is low)
    type ClkArray_t is array (0 to 1) of std_logic;

    signal CoreClk    : ClkArray_t;
    signal LaneClk    : ClkArray_t;
    signal ModelClk   : std_logic;
    signal CoreRun    : ClkArray_t := (others => '1');
    signal LaneRun    : ClkArray_t := (others => '1');
    signal PrbsTxSel  : KArray_t;
    signal PrbsRxSel  : KArray_t;
    signal PrbsForce  : LaneArray_t;
    signal PrbsCntRst : LaneArray_t;
    signal PrbsErr    : LaneArray_t;
    signal PrbsLocked : LaneArray_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    UserClk  <= not UserClk after 2.6 ns;
    CoreClkG <= not CoreClkG after CoreHalfPs_g * 1 ps;
    LaneClkG <= not LaneClkG after LaneHalfPs_g * 1 ps;
    ModelClk <= LaneClkG;
    MgmtI    <= not MgmtI after 5 ns;
    MgmtClk  <= MgmtI;
    Rst      <= RstI;

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

        CoreLaneOn(i) <= or (TxEnable(i) or RxEnable(i) or CdrEnable(i));

        -- Transmitters ready from the sequencer, a register of the free-running management clock like
        -- Stat_TxReady of the adapter (FreeRunClk)
        p_tx_ready : process (MgmtI) is
        begin
            if rising_edge(MgmtI) then
                TxReady(i) <= CoreTxReady(i);
            end if;
        end process;

        -- Clocks of the core: they stop and start while the generated clock is low (no short pulses)
        p_run : process (CoreClkG, LaneClkG) is
        begin
            if falling_edge(CoreClkG) then
                CoreRun(i) <= CoreCoreClkRun(i);
            end if;
            if falling_edge(LaneClkG) then
                LaneRun(i) <= CoreLaneClkRun(i);
            end if;
        end process;

        CoreClk(i) <= CoreClkG when CoreRun(i) = '1' else '0';
        LaneClk(i) <= LaneClkG when LaneRun(i) = '1' else '0';

        i_core : entity work.ofb_core
            generic map (
                NumVc_g         => NumVc_g,
                NumLanes_g      => N_c,
                -- The frequency generics match the generated clocks
                LaneClkFreq_g   => 1.0e12 / real(2 * LaneHalfPs_g),
                CoreClkFreq_g   => 1.0e12 / real(2 * CoreHalfPs_g),
                VcOutDepth_g    => VcOutDepth_g,
                VcInDepth_g     => VcInDepth_c,
                ErbRows_g       => ErbRows_g,
                InitPrbsWords_g => InitPrbsWords_g,
                LaneStart_g     => LaneStartA_g and i = 0,
                AutoStart_g     => AutoStart_g
            )
            port map (
                Rst                    => RstI or CoreRstReq(i),
                UserClk                => UserClk,
                CoreClk                => CoreClk(i),
                LaneClk                => LaneClk(i),
                MgmtClk                => MgmtI,
                S_Vc_TData             => SVcData(i),
                S_Vc_TKeep             => SVcKeep(i),
                S_Vc_TLast             => SVcLast(i),
                S_Vc_TUser             => SVcUser(i),
                S_Vc_TValid            => SVcValid(i),
                S_Vc_TReady            => SVcReady(i),
                M_Vc_TData             => MVcData(i),
                M_Vc_TKeep             => MVcKeep(i),
                M_Vc_TLast             => MVcLast(i),
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
                Irq                    => CoreIrq(i),
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
                Phy_TxReady            => TxReady(i),
                Phy_SerialNearLoopback => SerNearLb(i),
                Phy_SerialFarLoopback  => SerFarLb(i),
                Phy_BitSync            => BitSync(i),
                Phy_PrbsTxSel          => PrbsTxSel(i),
                Phy_PrbsRxSel          => PrbsRxSel(i),
                Phy_PrbsForceErr       => PrbsForce(i),
                Phy_PrbsCntReset       => PrbsCntRst(i),
                Phy_PrbsErr            => PrbsErr(i),
                Phy_PrbsLocked         => PrbsLocked(i)
            );

        -------------------------------------------------------------------------------------------
        -- Packet generators and receivers per VC
        -------------------------------------------------------------------------------------------
        g_vc : for v in 0 to NumVc_g-1 generate

            p_gen : process is
                variable Seed1_v : positive := 1 + 17 * i + 3 * v;
                variable Seed2_v : positive := 1000 + 7 * i + 11 * v;
                variable Rand_v  : real;
                variable Sent_v  : natural  := 0;
                variable Len_v   : natural;
                variable Pos_v   : natural;
                variable Raw_v   : RawBeat_t;
                variable BeatD_v : std_logic_vector(32*N_c-1 downto 0);
                variable BeatK_v : std_logic_vector(B_c-1 downto 0);
                variable Word_v  : Word_t;
                variable K_v     : WordK_t;
                variable Cls_v   : natural range 0 to 3;

                impure function randInt (lo : natural; hi : natural) return natural is
                begin
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    return lo + natural(floor(Rand_v * real(hi - lo + 1)));
                end function;

                -- One beat to the VC port
                procedure sendBeat (
                    data : std_logic_vector;
                    keep : std_logic_vector;
                    last : std_logic;
                    user : std_logic) is
                begin
                    SVcData(i)(32*N_c*(v+1)-1 downto 32*N_c*v) <= data;
                    SVcKeep(i)(B_c*(v+1)-1 downto B_c*v)       <= keep;
                    SVcLast(i)(v)                              <= last;
                    SVcUser(i)(v)                              <= user;
                    SVcValid(i)(v)                             <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when SVcReady(i)(v) = '1';
                    end loop;

                    SVcValid(i)(v) <= '0';
                end procedure;

            -- Generator
            begin
                SVcValid(i)(v) <= '0';
                SVcLast(i)(v)  <= '0';
                SVcUser(i)(v)  <= '0';

                loop
                    wait until rising_edge(UserClk);
                    if i = 0 and v = 0 and RawQueue_v.count(0) > 0 then
                        -- Raw beats (expected words are added by the sequencer)
                        Raw_v := RawQueue_v.pop(0);
                        sendBeat(Raw_v(32*N_c-1 downto 0), Raw_v(128+B_c-1 downto 128), Raw_v(144), Raw_v(145));
                    elsif Sent_v < CoreCfg(i).Vc(v).Packets then
                        if CoreCfg(i).Vc(v).LenClasses then
                            -- The length classes of the functional coverage in turn
                            Cls_v := Sent_v mod 4;
                            Len_v := randInt(LenMin_c(Cls_v), LenMax_c(Cls_v));
                        else
                            Len_v := randInt(CoreCfg(i).Vc(v).MinLen, CoreCfg(i).Vc(v).MaxLen);
                        end if;
                        Pos_v := 0;

                        -- Beats of random bytes; the expected words of the receiver: four bytes per word, the
                        -- last bytes with the EOP and Fills
                        while Pos_v <= Len_v loop

                            for c in 0 to B_c-1 loop
                                if Pos_v + c < Len_v then
                                    BeatD_v(8*c+7 downto 8*c) := std_logic_vector(to_unsigned(randInt(0, 255), 8));
                                    BeatK_v(c)                := '1';
                                else
                                    BeatD_v(8*c+7 downto 8*c) := x"00";
                                    BeatK_v(c)                := '0';
                                end if;
                            end loop;

                            for w in 0 to N_c-1 loop
                                if Pos_v + 4 * w <= Len_v then

                                    for c in 0 to 3 loop
                                        if Pos_v + 4 * w + c < Len_v then
                                            Word_v(8*c+7 downto 8*c) := BeatD_v(32*w+8*c+7 downto 32*w+8*c);
                                            K_v(c)                   := '0';
                                        elsif Pos_v + 4 * w + c = Len_v then
                                            Word_v(8*c+7 downto 8*c) := CharEop_c;
                                            K_v(c)                   := '1';
                                        else
                                            Word_v(8*c+7 downto 8*c) := CharFill_c;
                                            K_v(c)                   := '1';
                                        end if;
                                    end loop;

                                    CoreSb_v.add_expected(1 + (1 - i) * CoreMaxVc_c + v, K_v & Word_v);
                                end if;
                            end loop;

                            if Pos_v < Len_v then
                                if Pos_v + B_c >= Len_v then
                                    sendBeat(BeatD_v, BeatK_v, '1', '0');
                                else
                                    sendBeat(BeatD_v, BeatK_v, '0', '0');
                                end if;
                            end if;
                            Pos_v := Pos_v + B_c;
                        end loop;

                        Sent_v := Sent_v + 1;
                    end if;
                end loop;

            end process;

            p_rx : process (UserClk) is
                constant Inst_c  : positive := 1 + i * CoreMaxVc_c + v;
                variable Seed1_v : positive := 5 + 13 * i + 7 * v;
                variable Seed2_v : positive := 3000 + 3 * i + 19 * v;
                variable Rand_v  : real;
                variable Word_v  : std_logic_vector(35 downto 0);
                variable WordN_v : natural  := 0;
                variable Exp_v   : std_logic_vector(35 downto 0);
                variable Keep_v  : std_logic_vector(B_c-1 downto 0);
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

                -- A word of the received packet to the scoreboard
                procedure checkWord is
                begin
                    Words_v := Words_v + 1;
                    if CoreCfg(i).Lossy then
                        checkLossy(Word_v);
                    else
                        CoreSb_v.check_received(Inst_c, Word_v);
                    end if;
                    WordN_v := 0;
                end procedure;

            -- Receiver: the bytes of the packets as words of four bytes; the last word of a packet with the
            -- remaining bytes, the EOP or EEP and Fills
            begin
                if rising_edge(UserClk) then
                    if MVcValid(i)(v) = '1' and MVcReady(i)(v) = '1' then
                        Keep_v := MVcKeep(i)(B_c*(v+1)-1 downto B_c*v);
                        if MVcLast(i)(v) = '0' and Keep_v /= (Keep_v'range => '1') then
                            alert(error, "Core " & to_string(i) & ", VC " & to_string(v) & ": TKEEP " &
                                  to_string(Keep_v) & " without TLAST");
                        end if;

                        for c in 0 to B_c-1 loop
                            if Keep_v(c) = '1' then
                                Word_v(8*WordN_v+7 downto 8*WordN_v) := MVcData(i)(32*N_c*v+8*c+7 downto 32*N_c*v+8*c);
                                Word_v(32 + WordN_v)                 := '0';
                                WordN_v                              := WordN_v + 1;
                                Bytes_v                              := Bytes_v + 1;
                                if WordN_v = 4 then
                                    checkWord;
                                end if;
                            elsif c > 0 and Keep_v(c-1) = '1' and Keep_v(B_c-1 downto c) /= (B_c-1 downto c => '0') then
                                alert(error, "Core " & to_string(i) & ", VC " & to_string(v) & ": TKEEP " &
                                      to_string(Keep_v) & " not contiguous");
                            end if;
                        end loop;

                        if MVcLast(i)(v) = '1' then
                            -- End marker and Fills
                            if MVcUser(i)(v) = '1' then
                                Word_v(8*WordN_v+7 downto 8*WordN_v) := CharEep_c;
                                -- Functional coverage: end of the packets sent by the other core
                                CovEnd_v.sample_coverage((1 - i, 1));
                            else
                                Word_v(8*WordN_v+7 downto 8*WordN_v) := CharEop_c;
                                CovPkt_v.sample_coverage((1 - i, v, Bytes_v));
                                CovEnd_v.sample_coverage((1 - i, 0));
                            end if;
                            Word_v(32 + WordN_v) := '1';

                            for c in WordN_v + 1 to 3 loop
                                Word_v(8*c+7 downto 8*c) := CharFill_c;
                                Word_v(32 + c)           := '1';
                            end loop;

                            checkWord;
                            Bytes_v := 0;
                        end if;
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
                    CoreSb_v.add_expected(1 + 2 * CoreMaxVc_c + (1 - i), "0000" & Data_v(31 downto 0));
                    CoreSb_v.add_expected(1 + 2 * CoreMaxVc_c + (1 - i), "0000" & Data_v(63 downto 32));
                    CoreSb_v.add_expected(1 + 2 * CoreMaxVc_c + (1 - i), x"0000" & "000" & User_v);
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
            constant Inst_c  : positive := 1 + 2 * CoreMaxVc_c + i;
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
                    CoreSb_v.check_received(1 + 2 * CoreMaxVc_c + i, "0000" & MBcData(i)(31 downto 0));
                    CoreSb_v.check_received(1 + 2 * CoreMaxVc_c + i, "0000" & MBcData(i)(63 downto 32));
                    -- DELAYED, B_TYPE and channel; LATE depends on the error recovery
                    CoreSb_v.check_received(1 + 2 * CoreMaxVc_c + i, x"0000" & "000" & MBcUser(i)(16 downto 0));
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
                Clk          => ModelClk,
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
                A_PrbsTxSel  => PrbsTxSel(0)(4*l+3 downto 4*l),
                A_PrbsRxSel  => PrbsRxSel(0)(4*l+3 downto 4*l),
                A_PrbsForce  => PrbsForce(0)(l),
                A_PrbsCntRst => PrbsCntRst(0)(l),
                A_PrbsErr    => PrbsErr(0)(l),
                A_PrbsLocked => PrbsLocked(0)(l),
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
                B_FarSerLb   => SerFarLb(1)(l),
                B_PrbsTxSel  => PrbsTxSel(1)(4*l+3 downto 4*l),
                B_PrbsRxSel  => PrbsRxSel(1)(4*l+3 downto 4*l),
                B_PrbsForce  => PrbsForce(1)(l),
                B_PrbsCntRst => PrbsCntRst(1)(l),
                B_PrbsErr    => PrbsErr(1)(l),
                B_PrbsLocked => PrbsLocked(1)(l)
            );

    end generate;

end architecture;
