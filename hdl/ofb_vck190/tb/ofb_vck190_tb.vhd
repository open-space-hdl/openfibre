---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Top-level testbench of the VCK190 reference design with the transceiver model: the QSFP lanes
-- of the design are connected to a far end (OpenFibre core with PA-1, reference clock 100 ppm
-- slower). The far end starts the link; packets on all VCs and broadcast messages sent by the far
-- end come back (echo) unchanged; the LEDs show the link state.
--
-- Documentation: hdl/ofb_vck190/docs/verification_plan.md

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
entity ofb_vck190_tb is
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_vck190_tb is

    constant Lanes_c   : positive := 4;
    constant Vcs_c     : positive := 8;
    constant Packets_c : positive := 6;   -- packets per VC
    constant Bcs_c     : positive := 4;   -- broadcast messages
    constant Timeout_c : time     := 1 ms;

    constant Fill_c : std_logic_vector(7 downto 0) := x"FB";
    constant Eop_c  : std_logic_vector(7 downto 0) := x"FD";

    constant RegDlStatus_c : natural := 16#010#;
    constant RegDlErrors_c : natural := 16#014#;
    constant RegRetries_c  : natural := 16#018#;
    constant RegLaneCtrl_c : natural := 16#100#;

    subtype Data_t is std_logic_vector(31 downto 0);

    type CntArray_t is array (0 to Vcs_c-1) of natural;
    type ErrArray_t is array (0 to Vcs_c) of natural;

    -- Design under test
    signal SysClk   : std_logic := '0';
    signal GtRefClk : std_logic := '0';
    signal Led      : std_logic_vector(3 downto 0);
    signal DutTxP   : std_logic_vector(Lanes_c-1 downto 0);
    signal DutTxN   : std_logic_vector(Lanes_c-1 downto 0);
    signal FarTxP   : std_logic_vector(Lanes_c-1 downto 0);
    signal FarTxN   : std_logic_vector(Lanes_c-1 downto 0);

    -- Far end
    signal FarRefClk  : std_logic                                     := '0';
    signal FreeRunClk : std_logic                                     := '0';
    signal Rst        : std_logic                                     := '1';
    signal LaneClk    : std_logic;
    signal LaneRst    : std_logic;
    signal CoreRst    : std_logic;
    signal PhyTxData  : std_logic_vector(32*Lanes_c-1 downto 0);
    signal PhyTxK     : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxData  : std_logic_vector(32*Lanes_c-1 downto 0);
    signal PhyRxK     : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxCode  : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxDisp  : std_logic_vector(4*Lanes_c-1 downto 0);
    signal PhyRxVld   : std_logic_vector(Lanes_c-1 downto 0);
    signal TxEnable   : std_logic_vector(Lanes_c-1 downto 0);
    signal RxEnable   : std_logic_vector(Lanes_c-1 downto 0);
    signal CdrEnable  : std_logic_vector(Lanes_c-1 downto 0);
    signal RxInvert   : std_logic_vector(Lanes_c-1 downto 0);
    signal NoSignal   : std_logic_vector(Lanes_c-1 downto 0);
    signal SVcData    : std_logic_vector(32*Lanes_c*Vcs_c-1 downto 0) := (others => '0');
    signal SVcUser    : std_logic_vector(4*Lanes_c*Vcs_c-1 downto 0)  := (others => '0');
    signal SVcValid   : std_logic_vector(Vcs_c-1 downto 0)            := (others => '0');
    signal SVcReady   : std_logic_vector(Vcs_c-1 downto 0);
    signal MVcData    : std_logic_vector(32*Lanes_c*Vcs_c-1 downto 0);
    signal MVcUser    : std_logic_vector(4*Lanes_c*Vcs_c-1 downto 0);
    signal MVcValid   : std_logic_vector(Vcs_c-1 downto 0);
    signal SBcData    : std_logic_vector(63 downto 0)                 := (others => '0');
    signal SBcUser    : std_logic_vector(16 downto 0)                 := (others => '0');
    signal SBcValid   : std_logic                                     := '0';
    signal SBcReady   : std_logic;
    signal MBcData    : std_logic_vector(63 downto 0);
    signal MBcUser    : std_logic_vector(17 downto 0);
    signal MBcValid   : std_logic;
    signal ArAddr     : std_logic_vector(11 downto 0)                 := (others => '0');
    signal ArValid    : std_logic                                     := '0';
    signal ArReady    : std_logic;
    signal AwAddr     : std_logic_vector(11 downto 0)                 := (others => '0');
    signal AwValid    : std_logic                                     := '0';
    signal AwReady    : std_logic;
    signal WData      : Data_t                                        := (others => '0');
    signal WValid     : std_logic                                     := '0';
    signal WReady     : std_logic;
    signal BValid     : std_logic;
    signal BReady     : std_logic                                     := '0';
    signal RData      : Data_t;
    signal RValid     : std_logic;
    signal RReady     : std_logic                                     := '0';

    -- Traffic
    signal StartTraffic : boolean    := false;
    signal Received     : CntArray_t := (others => 0);
    signal BcReceived   : natural    := 0;
    signal Errors       : ErrArray_t := (others => 0);

    -- Word w of packet p of VC v
    function packetWord (
        v : natural;
        p : natural;
        w : natural) return std_logic_vector is
    begin
        return x"A" & std_logic_vector(to_unsigned(v, 4)) & std_logic_vector(to_unsigned(p, 8)) &
               std_logic_vector(to_unsigned(w, 16));
    end function;

    -- Length in data words of packet p of VC v
    function packetLen (
        v : natural;
        p : natural) return natural is
    begin
        return 1 + (5 * p + 11 * v) mod 30;
    end function;

begin

    SysClk     <= not SysClk after 2.5 ns;
    GtRefClk   <= not GtRefClk after 3200 ps;
    FarRefClk  <= not FarRefClk after 3200320 fs;
    FreeRunClk <= not FreeRunClk after 5 ns;

    -----------------------------------------------------------------------------------------------
    -- Progress of the simulation (the transceiver model is slow)
    -----------------------------------------------------------------------------------------------
    p_progress : process is
    begin
        wait for 50 us;
        report "Progress: " & time'image(now);
    end process;

    -----------------------------------------------------------------------------------------------
    -- Sequencer (far end)
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable A_v    : Data_t;
        variable B_v    : Data_t;
        variable Done_v : boolean;
        variable Fail_v : boolean := false;

        procedure wr (
            addr : natural;
            data : Data_t) is
        begin
            wait until rising_edge(FreeRunClk);
            AwAddr  <= std_logic_vector(to_unsigned(addr, 12));
            AwValid <= '1';
            WData   <= data;
            WValid  <= '1';
            BReady  <= '1';

            loop
                wait until rising_edge(FreeRunClk);
                if AwReady = '1' then
                    AwValid <= '0';
                end if;
                if WReady = '1' then
                    WValid <= '0';
                end if;
                exit when BValid = '1';
            end loop;

            BReady <= '0';
        end procedure;

        procedure rd (
            addr : natural;
            data : out Data_t) is
        begin
            wait until rising_edge(FreeRunClk);
            ArAddr  <= std_logic_vector(to_unsigned(addr, 12));
            ArValid <= '1';
            RReady  <= '1';

            loop
                wait until rising_edge(FreeRunClk);
                if ArReady = '1' then
                    ArValid <= '0';
                end if;
                exit when RValid = '1';
            end loop;

            data   := RData;
            RReady <= '0';
        end procedure;

        impure function errorSum return natural is
            variable Sum_v : natural := 0;
        begin

            for v in 0 to Vcs_c loop
                Sum_v := Sum_v + Errors(v);
            end loop;

            return Sum_v;
        end function;

    -- Sequence
    begin
        Rst <= '1';
        wait for 200 ns;
        Rst <= '0';
        wait until CoreRst = '0' and Led(0) = '1' for Timeout_c;
        report "Transceivers ready at " & time'image(now);
        wait for 1 us;

        -- The far end starts all lanes, the design starts with AutoStart
        for l in 0 to Lanes_c-1 loop
            wr(RegLaneCtrl_c + 16#20# * l, x"00000063");
        end loop;

        loop
            rd(RegDlStatus_c, A_v);
            exit when A_v(1 downto 0) = "11" and A_v(8) = '1';
            wait for 1 us;
            if now > Timeout_c then
                report "FAIL: link not initialised" severity error;
                Fail_v := true;
                exit;
            end if;
        end loop;

        report "Link initialised at " & time'image(now);
        StartTraffic <= true;

        loop
            wait for 2 us;
            Done_v := BcReceived = Bcs_c;

            for v in 0 to Vcs_c-1 loop
                if Received(v) < Packets_c then
                    Done_v := false;
                end if;
            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        for v in 0 to Vcs_c-1 loop
            report "VC " & integer'image(v) & ": " & integer'image(Received(v)) & " packets back";
            if Received(v) /= Packets_c then
                report "FAIL: packets missing" severity error;
                Fail_v := true;
            end if;
        end loop;

        report integer'image(BcReceived) & " broadcast messages back, " & integer'image(errorSum) & " errors";
        if BcReceived /= Bcs_c or errorSum /= 0 then
            report "FAIL: broadcast messages missing or errors" severity error;
            Fail_v := true;
        end if;
        rd(RegDlErrors_c, A_v);
        rd(RegRetries_c, B_v);
        report "Far end: DL_ERRORS " & to_hstring(A_v) & ", retries " & integer'image(to_integer(unsigned(B_v)));
        if A_v(9 downto 0) /= "0000000000" or unsigned(B_v) /= 0 then
            report "FAIL: errors or retries at the far end" severity error;
            Fail_v := true;
        end if;

        -- The LED of the link state follows within one poll interval (1024 system clock cycles)
        if Led /= "1111" then
            wait until Led = "1111" for 20 us;
        end if;
        report "LEDs " & to_string(Led);
        if Led /= "1111" then
            report "FAIL: LEDs" severity error;
            Fail_v := true;
        end if;

        if not Fail_v then
            report "Simulation done at " & time'image(now);
        end if;
        finish;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Design under test
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_vck190_top
        generic map (
            NumVc_g       => Vcs_c,
            LedPollBits_g => 10
        )
        port map (
            SysClk_P   => SysClk,
            SysClk_N   => not SysClk,
            GtRefClk_P => GtRefClk,
            GtRefClk_N => not GtRefClk,
            Qsfp_TxP   => DutTxP,
            Qsfp_TxN   => DutTxN,
            Qsfp_RxP   => FarTxP,
            Qsfp_RxN   => FarTxN,
            Led        => Led
        );

    -----------------------------------------------------------------------------------------------
    -- Far end
    -----------------------------------------------------------------------------------------------
    CoreRst <= Rst or LaneRst;

    i_pa : entity work.ofb_pa_gty
        generic map (
            NumLanes_g => Lanes_c
        )
        port map (
            FreeRunClk    => FreeRunClk,
            Rst           => Rst,
            RefClk        => FarRefClk,
            LaneClk       => LaneClk,
            LaneRst       => LaneRst,
            Gt_TxP        => FarTxP,
            Gt_TxN        => FarTxN,
            Gt_RxP        => DutTxP,
            Gt_RxN        => DutTxN,
            PhyTx_Data    => PhyTxData,
            PhyTx_K       => PhyTxK,
            PhyRx_Data    => PhyRxData,
            PhyRx_K       => PhyRxK,
            PhyRx_CodeErr => PhyRxCode,
            PhyRx_DispErr => PhyRxDisp,
            PhyRx_Valid   => PhyRxVld,
            Phy_TxEnable  => TxEnable,
            Phy_RxEnable  => RxEnable,
            Phy_CdrEnable => CdrEnable,
            Phy_RxInvert  => RxInvert,
            Phy_NoSignal  => NoSignal,
            Stat_TxReady  => open,
            Stat_RxReady  => open,
            Stat_Aligned  => open,
            Stat_RxBufErr => open,
            Stat_ClkCor   => open
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
            Rst               => CoreRst,
            UserClk           => LaneClk,
            CoreClk           => LaneClk,
            LaneClk           => LaneClk,
            MgmtClk           => FreeRunClk,
            S_Vc_TData        => SVcData,
            S_Vc_TUser        => SVcUser,
            S_Vc_TValid       => SVcValid,
            S_Vc_TReady       => SVcReady,
            M_Vc_TData        => MVcData,
            M_Vc_TUser        => MVcUser,
            M_Vc_TValid       => MVcValid,
            M_Vc_TReady       => (others => '1'),
            S_Bc_TData        => SBcData,
            S_Bc_TUser        => SBcUser,
            S_Bc_TValid       => SBcValid,
            S_Bc_TReady       => SBcReady,
            M_Bc_TData        => MBcData,
            M_Bc_TUser        => MBcUser,
            M_Bc_TValid       => MBcValid,
            M_Bc_TReady       => '1',
            S_AxiLite_ArAddr  => ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => WData,
            S_AxiLite_WStrb   => "1111",
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => open,
            S_AxiLite_BValid  => BValid,
            S_AxiLite_BReady  => BReady,
            S_AxiLite_RData   => RData,
            S_AxiLite_RResp   => open,
            S_AxiLite_RValid  => RValid,
            S_AxiLite_RReady  => RReady,
            Irq               => open,
            PhyTx_Data        => PhyTxData,
            PhyTx_K           => PhyTxK,
            PhyRx_Data        => PhyRxData,
            PhyRx_K           => PhyRxK,
            PhyRx_CodeErr     => PhyRxCode,
            PhyRx_DispErr     => PhyRxDisp,
            PhyRx_Valid       => PhyRxVld,
            Phy_TxEnable      => TxEnable,
            Phy_RxEnable      => RxEnable,
            Phy_CdrEnable     => CdrEnable,
            Phy_RxInvert      => RxInvert,
            Phy_NoSignal      => NoSignal
        );

    -----------------------------------------------------------------------------------------------
    -- Packet generator and checker per VC of the far end
    -----------------------------------------------------------------------------------------------
    g_vc : for v in 0 to Vcs_c-1 generate

        p_gen : process is
            variable Beat_v : std_logic_vector(32*Lanes_c-1 downto 0);
            variable K_v    : std_logic_vector(4*Lanes_c-1 downto 0);
            variable Pos_v  : natural;
            variable Len_v  : natural;
        begin
            wait until StartTraffic;

            for p in 0 to Packets_c-1 loop
                Len_v := packetLen(v, p);
                Pos_v := 0;

                for w in 0 to Len_v loop
                    if w < Len_v then
                        Beat_v(32*Pos_v+31 downto 32*Pos_v) := packetWord(v, p, w);
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

                        wait until rising_edge(LaneClk);
                        SVcData(32*Lanes_c*(v+1)-1 downto 32*Lanes_c*v) <= Beat_v;
                        SVcUser(4*Lanes_c*(v+1)-1 downto 4*Lanes_c*v)   <= K_v;
                        SVcValid(v)                                     <= '1';

                        loop
                            wait until rising_edge(LaneClk);
                            exit when SVcReady(v) = '1';
                        end loop;

                        SVcValid(v) <= '0';
                        Pos_v       := 0;
                    end if;
                end loop;

            end loop;

            wait;
        end process;

        p_check : process (LaneClk) is
            variable P_v    : natural := 0;
            variable W_v    : natural := 0;
            variable Word_v : std_logic_vector(31 downto 0);
            variable K_v    : std_logic_vector(3 downto 0);
            variable Base_v : natural;
        begin
            if rising_edge(LaneClk) then
                if MVcValid(v) = '1' then

                    for w in 0 to Lanes_c-1 loop
                        Base_v := 32*Lanes_c*v + 32*w;
                        Word_v := MVcData(Base_v+31 downto Base_v);
                        K_v    := MVcUser(4*Lanes_c*v+4*w+3 downto 4*Lanes_c*v+4*w);
                        if K_v = "0000" then
                            if Word_v /= packetWord(v, P_v, W_v) then
                                report "VC " & integer'image(v) & ": word " & to_hstring(Word_v) & ", expected " &
                                       to_hstring(packetWord(v, P_v, W_v)) severity error;
                                Errors(v) <= Errors(v) + 1;
                            end if;
                            W_v := W_v + 1;
                        elsif K_v = "1111" and Word_v(7 downto 0) = Eop_c then
                            if W_v /= packetLen(v, P_v) then
                                report "VC " & integer'image(v) & ": EOP after " & integer'image(W_v) & " words"
                                    severity error;
                                Errors(v) <= Errors(v) + 1;
                            end if;
                            P_v         := P_v + 1;
                            W_v         := 0;
                            Received(v) <= P_v;
                        elsif not (K_v = "1111" and Word_v = Fill_c & Fill_c & Fill_c & Fill_c) then
                            report "VC " & integer'image(v) & ": word " & to_hstring(Word_v) & " K " & to_hstring(K_v)
                                severity error;
                            Errors(v) <= Errors(v) + 1;
                        end if;
                    end loop;

                end if;
            end if;
        end process;

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Broadcast messages of the far end
    -----------------------------------------------------------------------------------------------
    p_bc_gen : process is
    begin
        wait until StartTraffic;

        for b in 0 to Bcs_c-1 loop
            wait until rising_edge(LaneClk);
            SBcData  <= packetWord(15, b, 1) & packetWord(15, b, 0);
            SBcUser  <= '0' & std_logic_vector(to_unsigned(b, 8)) & x"07";
            SBcValid <= '1';

            loop
                wait until rising_edge(LaneClk);
                exit when SBcReady = '1';
            end loop;

            SBcValid <= '0';
            wait for 1 us;
        end loop;

        wait;
    end process;

    p_bc_check : process (LaneClk) is
        variable B_v    : natural := 0;
        variable ExpD_v : std_logic_vector(63 downto 0);
        variable ExpU_v : std_logic_vector(15 downto 0);
    begin
        if rising_edge(LaneClk) then
            if MBcValid = '1' then
                ExpD_v := packetWord(15, B_v, 1) & packetWord(15, B_v, 0);
                ExpU_v := std_logic_vector(to_unsigned(B_v, 8)) & x"07";
                if MBcData /= ExpD_v or MBcUser(15 downto 0) /= ExpU_v then
                    report "Broadcast message " & integer'image(B_v) & " wrong" severity error;
                    Errors(Vcs_c) <= Errors(Vcs_c) + 1;
                end if;
                B_v        := B_v + 1;
                BcReceived <= B_v;
            end if;
        end if;
    end process;

end architecture;
