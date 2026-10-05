---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- End-to-end testbench: two OpenFibre cores with four lanes, each with its Physical adapter PA-1
-- and the transceiver model, connected by their serial lines. The reference clocks of the two ends
-- differ by 100 ppm. A starts the link through the MIB (B with AutoStart); packets on all VCs and
-- broadcast messages travel in both directions and are checked; no error is reported in the MIB.
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
entity ofb_pa_gty_core_tb is
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_core_tb is

    constant Lanes_c   : positive := 4;
    constant Vcs_c     : positive := 4;
    constant Packets_c : positive := 12;  -- packets per VC, direction and burst
    constant Bcs_c     : positive := 4;   -- broadcast messages per direction
    constant Timeout_c : time     := 1 ms;

    constant RefPeriodA_c : time := 6400 ps;
    constant RefPeriodB_c : time := 6401280 fs; -- 200 ppm slower
    constant FreePeriod_c : time := 10 ns;

    constant RegDlStatus_c : natural := 16#010#;
    constant RegDlErrors_c : natural := 16#014#;
    constant RegRetries_c  : natural := 16#018#;
    constant RegLaneCtrl_c : natural := 16#100#;
    constant RegLaneStat_c : natural := 16#104#;
    constant RegMlStatus_c : natural := 16#040#;

    constant Fill_c : std_logic_vector(7 downto 0) := x"FB";
    constant Eop_c  : std_logic_vector(7 downto 0) := x"FD";

    subtype Addr_t is std_logic_vector(11 downto 0);
    subtype Data_t is std_logic_vector(31 downto 0);

    type EndArray_t is array (0 to 1) of std_logic;
    type LaneVecArray_t is array (0 to 1) of std_logic_vector(Lanes_c-1 downto 0);
    type BeatArray_t is array (0 to 1) of std_logic_vector(32*Lanes_c*Vcs_c-1 downto 0);
    type BeatKArray_t is array (0 to 1) of std_logic_vector(4*Lanes_c*Vcs_c-1 downto 0);
    type VcVecArray_t is array (0 to 1) of std_logic_vector(Vcs_c-1 downto 0);
    type PhyDataArray_t is array (0 to 1) of std_logic_vector(32*Lanes_c-1 downto 0);
    type PhyKArray_t is array (0 to 1) of std_logic_vector(4*Lanes_c-1 downto 0);
    type BcDataArray_t is array (0 to 1) of std_logic_vector(63 downto 0);
    type BcUserArray_t is array (0 to 1) of std_logic_vector(17 downto 0);
    type AddrArray_t is array (0 to 1) of Addr_t;
    type DataArray_t is array (0 to 1) of Data_t;
    type RespArray_t is array (0 to 1) of std_logic_vector(1 downto 0);
    type CntArray_t is array (0 to 1, 0 to Vcs_c-1) of natural;
    type NatArray_t is array (0 to 1) of natural;
    type ErrArray_t is array (0 to 1, 0 to Vcs_c) of natural; -- per VC checker, broadcast checker (Vcs_c)

    -- Clocks and resets
    signal RefClk     : EndArray_t := (others => '0');
    signal FreeRunClk : std_logic  := '0';
    signal Rst        : std_logic  := '1';
    signal LaneClk    : EndArray_t;
    signal LaneRst    : EndArray_t;
    signal CoreRst    : EndArray_t;

    -- Serial lines
    signal TxP : LaneVecArray_t;
    signal TxN : LaneVecArray_t;

    -- Physical adapter interface
    signal PhyTxData : PhyDataArray_t;
    signal PhyTxK    : PhyKArray_t;
    signal PhyRxData : PhyDataArray_t;
    signal PhyRxK    : PhyKArray_t;
    signal PhyRxCode : PhyKArray_t;
    signal PhyRxDisp : PhyKArray_t;
    signal PhyRxVld  : LaneVecArray_t;
    signal TxEnable  : LaneVecArray_t;
    signal RxEnable  : LaneVecArray_t;
    signal CdrEnable : LaneVecArray_t;
    signal RxInvert  : LaneVecArray_t;
    signal NoSignal  : LaneVecArray_t;
    signal ClkCor    : LaneVecArray_t;

    -- Virtual channels and broadcast ports
    signal SVcData  : BeatArray_t   := (others => (others => '0'));
    signal SVcUser  : BeatKArray_t  := (others => (others => '0'));
    signal SVcValid : VcVecArray_t  := (others => (others => '0'));
    signal SVcReady : VcVecArray_t;
    signal MVcData  : BeatArray_t;
    signal MVcUser  : BeatKArray_t;
    signal MVcValid : VcVecArray_t;
    signal SBcData  : BcDataArray_t := (others => (others => '0'));
    signal SBcUser  : BcUserArray_t := (others => (others => '0'));
    signal SBcValid : EndArray_t    := (others => '0');
    signal SBcReady : EndArray_t;
    signal MBcData  : BcDataArray_t;
    signal MBcUser  : BcUserArray_t;
    signal MBcValid : EndArray_t;

    -- AXI4-Lite
    signal ArAddr  : AddrArray_t := (others => (others => '0'));
    signal ArValid : EndArray_t  := (others => '0');
    signal ArReady : EndArray_t;
    signal AwAddr  : AddrArray_t := (others => (others => '0'));
    signal AwValid : EndArray_t  := (others => '0');
    signal AwReady : EndArray_t;
    signal WData   : DataArray_t := (others => (others => '0'));
    signal WValid  : EndArray_t  := (others => '0');
    signal WReady  : EndArray_t;
    signal BResp   : RespArray_t;
    signal BValid  : EndArray_t;
    signal BReady  : EndArray_t  := (others => '0');
    signal RData   : DataArray_t;
    signal RResp   : RespArray_t;
    signal RValid  : EndArray_t;
    signal RReady  : EndArray_t  := (others => '0');

    -- Traffic
    signal StartTraffic : boolean    := false;
    signal StartBurst2  : boolean    := false;
    signal ClkCorCnt    : NatArray_t := (others => 0);
    signal Received     : CntArray_t := (others => (others => 0));
    signal BcReceived   : NatArray_t := (others => 0);
    signal Errors       : ErrArray_t := (others => (others => 0));

    -- Word w of packet p of VC v sent by end e
    function packetWord (
        e : natural;
        v : natural;
        p : natural;
        w : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(e, 4)) & std_logic_vector(to_unsigned(v, 4)) &
               std_logic_vector(to_unsigned(p, 8)) & std_logic_vector(to_unsigned(w, 16));
    end function;

    -- Length in words of packet p of VC v (data words, the EOP follows in its own word)
    function packetLen (
        v : natural;
        p : natural) return natural is
    begin
        return 1 + (7 * p + 13 * v) mod 40;
    end function;

begin

    RefClk(0)  <= not RefClk(0) after RefPeriodA_c / 2;
    RefClk(1)  <= not RefClk(1) after RefPeriodB_c / 2;
    FreeRunClk <= not FreeRunClk after FreePeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Progress of the simulation (the transceiver model is slow)
    -----------------------------------------------------------------------------------------------
    p_progress : process is
    begin
        wait for 50 us;
        report "Progress: " & time'image(now);
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable A_v    : Data_t;
        variable B_v    : Data_t;
        variable Done_v : boolean;
        variable Fail_v : boolean := false;

        impure function errorSum (e : natural) return natural is
            variable Sum_v : natural := 0;
        begin

            for v in 0 to Vcs_c loop
                Sum_v := Sum_v + Errors(e, v);
            end loop;

            return Sum_v;
        end function;

        procedure wr (
            e    : natural;
            addr : natural;
            data : Data_t) is
        begin
            wait until rising_edge(FreeRunClk);
            AwAddr(e)  <= std_logic_vector(to_unsigned(addr, 12));
            AwValid(e) <= '1';
            WData(e)   <= data;
            WValid(e)  <= '1';
            BReady(e)  <= '1';

            loop
                wait until rising_edge(FreeRunClk);
                if AwReady(e) = '1' then
                    AwValid(e) <= '0';
                end if;
                if WReady(e) = '1' then
                    WValid(e) <= '0';
                end if;
                exit when BValid(e) = '1';
            end loop;

            BReady(e) <= '0';
        end procedure;

        procedure rd (
            e    : natural;
            addr : natural;
            data : out Data_t) is
        begin
            wait until rising_edge(FreeRunClk);
            ArAddr(e)  <= std_logic_vector(to_unsigned(addr, 12));
            ArValid(e) <= '1';
            RReady(e)  <= '1';

            loop
                wait until rising_edge(FreeRunClk);
                if ArReady(e) = '1' then
                    ArValid(e) <= '0';
                end if;
                exit when RValid(e) = '1';
            end loop;

            data      := RData(e);
            RReady(e) <= '0';
        end procedure;

    -- Sequence
    begin
        Rst <= '1';
        wait for 200 ns;
        Rst <= '0';
        wait until CoreRst(0) = '0' and CoreRst(1) = '0' for Timeout_c;
        report "Transceivers ready at " & time'image(now);
        wait for 1 us;

        -- A starts all lanes, B keeps AutoStart
        for l in 0 to Lanes_c-1 loop
            wr(0, RegLaneCtrl_c + 16#20# * l, x"00000063");
        end loop;

        -- Link initialised at both ends
        loop
            rd(0, RegDlStatus_c, A_v);
            rd(1, RegDlStatus_c, B_v);
            exit when A_v(1 downto 0) = "11" and B_v(1 downto 0) = "11" and A_v(8) = '1' and B_v(8) = '1';
            wait for 1 us;
            if now > Timeout_c then
                report "FAIL: link not initialised" severity error;
                Fail_v := true;
                exit;
            end if;
        end loop;

        report "Link initialised at " & time'image(now);
        rd(0, RegMlStatus_c, A_v);
        rd(1, RegMlStatus_c, B_v);
        report "ML_STATUS A " & to_hstring(A_v) & ", B " & to_hstring(B_v);
        StartTraffic <= true;

        -- First burst and the broadcast messages delivered
        loop
            wait for 2 us;
            Done_v := BcReceived(0) = Bcs_c and BcReceived(1) = Bcs_c;

            for e in 0 to 1 loop

                for v in 0 to Vcs_c-1 loop
                    if Received(e, v) < Packets_c then
                        Done_v := false;
                    end if;
                end loop;

            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        report "First burst delivered at " & time'image(now);

        -- Clock correction at both ends (200 ppm: one word every 5000 words), then the second burst
        loop
            wait for 2 us;
            exit when (ClkCorCnt(0) > 0 and ClkCorCnt(1) > 0) or now > Timeout_c;
        end loop;

        report "Clock corrections: A " & integer'image(ClkCorCnt(0)) & ", B " & integer'image(ClkCorCnt(1)) &
               " at " & time'image(now);
        if ClkCorCnt(0) = 0 or ClkCorCnt(1) = 0 then
            report "FAIL: no clock correction" severity error;
            Fail_v := true;
        end if;
        StartBurst2 <= true;

        loop
            wait for 2 us;
            Done_v := true;

            for e in 0 to 1 loop

                for v in 0 to Vcs_c-1 loop
                    if Received(e, v) < 2 * Packets_c then
                        Done_v := false;
                    end if;
                end loop;

            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        for e in 0 to 1 loop

            for v in 0 to Vcs_c-1 loop
                report "End " & integer'image(e) & " VC " & integer'image(v) & ": " &
                       integer'image(Received(e, v)) & " packets received";
                if Received(e, v) /= 2 * Packets_c then
                    report "FAIL: packets missing" severity error;
                    Fail_v := true;
                end if;
            end loop;

            report "End " & integer'image(e) & ": " & integer'image(BcReceived(e)) & " broadcast messages, " &
                   integer'image(errorSum(e)) & " errors";
            if BcReceived(e) /= Bcs_c or errorSum(e) /= 0 then
                report "FAIL: broadcast messages missing or errors" severity error;
                Fail_v := true;
            end if;
            rd(e, RegDlErrors_c, A_v);
            rd(e, RegRetries_c, B_v);
            report "End " & integer'image(e) & ": DL_ERRORS " & to_hstring(A_v) & ", retries " &
                   integer'image(to_integer(unsigned(B_v)));
            if A_v(9 downto 0) /= "0000000000" or unsigned(B_v) /= 0 then
                report "FAIL: errors or retries reported in the MIB" severity error;
                Fail_v := true;
            end if;
        end loop;

        if not Fail_v then
            report "Simulation done at " & time'image(now);
        end if;
        finish;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Two ends
    -----------------------------------------------------------------------------------------------
    g_end : for e in 0 to 1 generate

        CoreRst(e) <= Rst or LaneRst(e);

        i_pa : entity work.ofb_pa_gty
            generic map (
                NumLanes_g => Lanes_c
            )
            port map (
                FreeRunClk    => FreeRunClk,
                Rst           => Rst,
                RefClk        => RefClk(e),
                LaneClk       => LaneClk(e),
                LaneRst       => LaneRst(e),
                Gt_TxP        => TxP(e),
                Gt_TxN        => TxN(e),
                Gt_RxP        => TxP(1 - e),
                Gt_RxN        => TxN(1 - e),
                PhyTx_Data    => PhyTxData(e),
                PhyTx_K       => PhyTxK(e),
                PhyRx_Data    => PhyRxData(e),
                PhyRx_K       => PhyRxK(e),
                PhyRx_CodeErr => PhyRxCode(e),
                PhyRx_DispErr => PhyRxDisp(e),
                PhyRx_Valid   => PhyRxVld(e),
                Phy_TxEnable  => TxEnable(e),
                Phy_RxEnable  => RxEnable(e),
                Phy_CdrEnable => CdrEnable(e),
                Phy_RxInvert  => RxInvert(e),
                Phy_NoSignal  => NoSignal(e),
                Stat_TxReady  => open,
                Stat_RxReady  => open,
                Stat_Aligned  => open,
                Stat_RxBufErr => open,
                Stat_ClkCor   => ClkCor(e)
            );

        i_core : entity work.ofb_core
            generic map (
                NumVc_g       => Vcs_c,
                NumLanes_g    => Lanes_c,
                LaneClkFreq_g => 156.25e6,
                CoreClkFreq_g => 156.25e6,
                VcInDepth_g   => 256 * Lanes_c
            )
            port map (
                Rst               => CoreRst(e),
                UserClk           => LaneClk(e),
                CoreClk           => LaneClk(e),
                LaneClk           => LaneClk(e),
                MgmtClk           => FreeRunClk,
                S_Vc_TData        => SVcData(e),
                S_Vc_TUser        => SVcUser(e),
                S_Vc_TValid       => SVcValid(e),
                S_Vc_TReady       => SVcReady(e),
                M_Vc_TData        => MVcData(e),
                M_Vc_TUser        => MVcUser(e),
                M_Vc_TValid       => MVcValid(e),
                M_Vc_TReady       => (others => '1'),
                S_Bc_TData        => SBcData(e),
                S_Bc_TUser        => SBcUser(e)(16 downto 0),
                S_Bc_TValid       => SBcValid(e),
                S_Bc_TReady       => SBcReady(e),
                M_Bc_TData        => MBcData(e),
                M_Bc_TUser        => MBcUser(e),
                M_Bc_TValid       => MBcValid(e),
                M_Bc_TReady       => '1',
                S_AxiLite_ArAddr  => ArAddr(e),
                S_AxiLite_ArValid => ArValid(e),
                S_AxiLite_ArReady => ArReady(e),
                S_AxiLite_AwAddr  => AwAddr(e),
                S_AxiLite_AwValid => AwValid(e),
                S_AxiLite_AwReady => AwReady(e),
                S_AxiLite_WData   => WData(e),
                S_AxiLite_WStrb   => "1111",
                S_AxiLite_WValid  => WValid(e),
                S_AxiLite_WReady  => WReady(e),
                S_AxiLite_BResp   => BResp(e),
                S_AxiLite_BValid  => BValid(e),
                S_AxiLite_BReady  => BReady(e),
                S_AxiLite_RData   => RData(e),
                S_AxiLite_RResp   => RResp(e),
                S_AxiLite_RValid  => RValid(e),
                S_AxiLite_RReady  => RReady(e),
                Irq               => open,
                PhyTx_Data        => PhyTxData(e),
                PhyTx_K           => PhyTxK(e),
                PhyRx_Data        => PhyRxData(e),
                PhyRx_K           => PhyRxK(e),
                PhyRx_CodeErr     => PhyRxCode(e),
                PhyRx_DispErr     => PhyRxDisp(e),
                PhyRx_Valid       => PhyRxVld(e),
                Phy_TxEnable      => TxEnable(e),
                Phy_RxEnable      => RxEnable(e),
                Phy_CdrEnable     => CdrEnable(e),
                Phy_RxInvert      => RxInvert(e),
                Phy_NoSignal      => NoSignal(e)
            );

        -------------------------------------------------------------------------------------------
        -- Packet generator per VC: beats of Lanes_c words, the EOP in its own word, Fill words
        -- after it
        -------------------------------------------------------------------------------------------
        g_vc : for v in 0 to Vcs_c-1 generate

            p_gen : process is
                variable Beat_v : std_logic_vector(32*Lanes_c-1 downto 0);
                variable K_v    : std_logic_vector(4*Lanes_c-1 downto 0);
                variable Pos_v  : natural;
                variable Len_v  : natural;
            begin
                wait until StartTraffic;

                for p in 0 to 2 * Packets_c-1 loop
                    if p = Packets_c and not StartBurst2 then
                        wait until StartBurst2;
                    end if;
                    Len_v := packetLen(v, p);
                    Pos_v := 0;

                    for w in 0 to Len_v loop
                        if w < Len_v then
                            Beat_v(32*Pos_v+31 downto 32*Pos_v) := packetWord(e, v, p, w);
                            K_v(4*Pos_v+3 downto 4*Pos_v)       := "0000";
                        else
                            Beat_v(32*Pos_v+31 downto 32*Pos_v) := Fill_c & Fill_c & Fill_c & Eop_c;
                            K_v(4*Pos_v+3 downto 4*Pos_v)       := "1111";
                        end if;
                        Pos_v := Pos_v + 1;
                        if Pos_v = Lanes_c or w = Len_v then

                            while Pos_v < Lanes_c loop
                                Beat_v(32*Pos_v+31 downto 32*Pos_v) := Fill_c & Fill_c & Fill_c & Fill_c;
                                K_v(4*Pos_v+3 downto 4*Pos_v)       := "1111";
                                Pos_v                               := Pos_v + 1;
                            end loop;

                            wait until rising_edge(LaneClk(e));
                            SVcData(e)(32*Lanes_c*(v+1)-1 downto 32*Lanes_c*v) <= Beat_v;
                            SVcUser(e)(4*Lanes_c*(v+1)-1 downto 4*Lanes_c*v)   <= K_v;
                            SVcValid(e)(v)                                     <= '1';

                            loop
                                wait until rising_edge(LaneClk(e));
                                exit when SVcReady(e)(v) = '1';
                            end loop;

                            SVcValid(e)(v) <= '0';
                            Pos_v          := 0;
                        end if;
                    end loop;

                end loop;

                wait;
            end process;

            ---------------------------------------------------------------------------------------
            -- Packet checker per VC: data words in order, EOP after the last word of a packet
            ---------------------------------------------------------------------------------------
            p_check : process (LaneClk(e)) is
                variable P_v    : natural := 0;
                variable W_v    : natural := 0;
                variable Word_v : std_logic_vector(31 downto 0);
                variable K_v    : std_logic_vector(3 downto 0);
                variable Base_v : natural;
            begin
                if rising_edge(LaneClk(e)) then
                    if MVcValid(e)(v) = '1' then

                        for w in 0 to Lanes_c-1 loop
                            Base_v := 32*Lanes_c*v + 32*w;
                            Word_v := MVcData(e)(Base_v+31 downto Base_v);
                            K_v    := MVcUser(e)(4*Lanes_c*v+4*w+3 downto 4*Lanes_c*v+4*w);
                            if K_v = "0000" then
                                if Word_v /= packetWord(1 - e, v, P_v, W_v) then
                                    report "End " & integer'image(e) & " VC " & integer'image(v) & ": word " &
                                           to_hstring(Word_v) & ", expected " &
                                           to_hstring(packetWord(1 - e, v, P_v, W_v)) severity error;
                                    Errors(e, v) <= Errors(e, v) + 1;
                                end if;
                                W_v := W_v + 1;
                            elsif K_v = "1111" and Word_v(7 downto 0) = Eop_c then
                                if W_v /= packetLen(v, P_v) then
                                    report "End " & integer'image(e) & " VC " & integer'image(v) &
                                           ": EOP after " & integer'image(W_v) & " words" severity error;
                                    Errors(e, v) <= Errors(e, v) + 1;
                                end if;
                                P_v            := P_v + 1;
                                W_v            := 0;
                                Received(e, v) <= P_v;
                            elsif not (K_v = "1111" and Word_v = Fill_c & Fill_c & Fill_c & Fill_c) then
                                report "End " & integer'image(e) & " VC " & integer'image(v) & ": word " &
                                       to_hstring(Word_v) & " K " & to_hstring(K_v) severity error;
                                Errors(e, v) <= Errors(e, v) + 1;
                            end if;
                        end loop;

                    end if;
                end if;
            end process;

        end generate;

        -------------------------------------------------------------------------------------------
        -- Clock correction events of the receive elastic buffers
        -------------------------------------------------------------------------------------------
        p_clkcor : process (LaneClk(e)) is
        begin
            if rising_edge(LaneClk(e)) then

                for l in 0 to Lanes_c-1 loop
                    if ClkCor(e)(l) = '1' then
                        ClkCorCnt(e) <= ClkCorCnt(e) + 1;
                    end if;
                end loop;

            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Broadcast messages: channel = end, B_TYPE = message number
        -------------------------------------------------------------------------------------------
        p_bc_gen : process is
        begin
            wait until StartTraffic;

            for b in 0 to Bcs_c-1 loop
                wait until rising_edge(LaneClk(e));
                SBcData(e)  <= packetWord(e, 15, b, 1) & packetWord(e, 15, b, 0);
                SBcUser(e)  <= "00" & std_logic_vector(to_unsigned(b, 8)) & std_logic_vector(to_unsigned(e, 8));
                SBcValid(e) <= '1';

                loop
                    wait until rising_edge(LaneClk(e));
                    exit when SBcReady(e) = '1';
                end loop;

                SBcValid(e) <= '0';
                wait for 1 us;
            end loop;

            wait;
        end process;

        p_bc_check : process (LaneClk(e)) is
            variable B_v    : natural := 0;
            variable ExpD_v : std_logic_vector(63 downto 0);
            variable ExpU_v : std_logic_vector(15 downto 0);
        begin
            if rising_edge(LaneClk(e)) then
                if MBcValid(e) = '1' then
                    ExpD_v := packetWord(1 - e, 15, B_v, 1) & packetWord(1 - e, 15, B_v, 0);
                    ExpU_v := std_logic_vector(to_unsigned(B_v, 8)) & std_logic_vector(to_unsigned(1 - e, 8));
                    if MBcData(e) /= ExpD_v or MBcUser(e)(15 downto 0) /= ExpU_v then
                        report "End " & integer'image(e) & ": broadcast message " & integer'image(B_v) & " wrong"
                            severity error;
                        Errors(e, Vcs_c) <= Errors(e, Vcs_c) + 1;
                    end if;
                    B_v           := B_v + 1;
                    BcReceived(e) <= B_v;
                end if;
            end if;
        end process;

    end generate;

end architecture;
