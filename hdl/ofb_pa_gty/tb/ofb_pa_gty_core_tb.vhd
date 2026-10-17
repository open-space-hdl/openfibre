---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- End-to-end testbench: two OpenFibre cores with one to four lanes, each with its Physical adapter
-- ofb_pa_gty, connected by their serial lines. The reference clocks of the two ends differ by
-- 200 ppm. A starts the link through the MIB (B with AutoStart); packets on all VCs and broadcast
-- messages travel in both directions and are checked; no error is reported in the MIB. The full run
-- then resets the adapter of A with the link up (its lane clock stops) and checks the hold of the
-- link, TX_LOST and the recovery with a third burst. The AMD simulator runs it with the transceiver
-- model (architecture struct, tools/run_xsim.py), GHDL and QuestaSim with the architecture mdl
-- through the VUnit wrapper ofb_pa_gty_model_core_tb (Finish_g = false). Every run reports the
-- timeline of the lane initialisation at the ports (enables, NoSignal, kinds of the words sent on
-- lane 0) and the lane timeouts and events of the MIB. With Relock_g, the short run then disables
-- the transmitter of lane 0 of B at its adapter for CutNs_g (the core of B is not told), so that the
-- lane of A loses the signal and both ends restart the lane; the run reports when the signal is back
-- at each receiver, the first lane word decoded after it, the lane states, the lane timeouts and the
-- return of the lane to Active at both ends, and delivers a second burst.
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

library work;
    use work.ofb_pkg.all;
    use work.ofb_pa_gty_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_core_tb is
    generic (
        Lanes_g  : positive range 1 to 4 := 4;
        -- Link initialisation and the first burst only (the lane counts below four)
        Short_g  : boolean               := false;
        -- With Short_g: restart of lane 0 by an interruption of the transmitter of B after the first burst
        Relock_g : boolean               := false;
        -- Length of the interruption of the transmitter of B in ns (Relock_g)
        CutNs_g  : positive              := 5000;
        -- Stop the simulation at the end; false: only PaCoreTbEnd and PaCoreTbPass are set
        Finish_g : boolean               := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_core_tb is

    constant Lanes_c   : positive := Lanes_g;
    constant Vcs_c     : positive := 4;
    constant Packets_c : positive := 12;  -- packets per VC, direction and burst
    constant Bcs_c     : positive := 4;   -- broadcast messages per direction
    constant Timeout_c : time     := 1 ms;

    constant CutTime_c   : time := CutNs_g * 1 ns; -- interruption of the transmitter of lane 0 of B (Relock_g)
    constant RelockMax_c : time := 300 us;         -- bound for the return of the lane after the interruption

    constant RefPeriodA_c : time := 6400 ps;
    constant RefPeriodB_c : time := 6401280 fs; -- 200 ppm slower
    constant FreePeriod_c : time := 10 ns;

    constant RegDlStatus_c : natural := 16#010#;
    constant RegDlErrors_c : natural := 16#014#;
    constant RegRetries_c  : natural := 16#018#;
    constant RegLaneCtrl_c : natural := 16#100#;
    constant RegLaneStat_c : natural := 16#104#;
    constant RegLaneEv_c   : natural := 16#108#;
    constant RegLaneTo_c   : natural := 16#110#;
    constant RegMlStatus_c : natural := 16#040#;

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
    type TimeArray_t is array (0 to 1) of time;

    -- Clocks and resets
    signal RefClk     : EndArray_t := (others => '0');
    signal FreeRunClk : std_logic  := '0';
    signal Rst        : std_logic  := '1';
    signal LaneClk    : EndArray_t;
    signal TxReady    : EndArray_t;
    signal RxReady    : EndArray_t;
    signal Aligned    : LaneVecArray_t;

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
    signal SVcKeep  : BeatKArray_t  := (others => (others => '0'));
    signal SVcLast  : VcVecArray_t  := (others => (others => '0'));
    signal SVcValid : VcVecArray_t  := (others => (others => '0'));
    signal SVcReady : VcVecArray_t;
    signal MVcData  : BeatArray_t;
    signal MVcKeep  : BeatKArray_t;
    signal MVcLast  : VcVecArray_t;
    signal MVcUser  : VcVecArray_t;
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

    -- Reset of one adapter only (transmitter reset in operation)
    signal PaRstReq   : EndArray_t  := (others => '0');
    signal PaRst      : EndArray_t;
    signal LaneEdge   : TimeArray_t := (others => 0 fs); -- last rising edge of LaneClk
    signal AllAligned : EndArray_t;

    -- Interruption of the transmitter of lane 0 at the adapter of an end (Relock_g)
    signal TxOff    : EndArray_t  := (others => '0');
    signal TxEnGt   : LaneVecArray_t;                  -- transmitter enables at the adapter ports
    signal RelockOn : boolean     := false;            -- relock phase: timeline of lane 0 again
    signal SigBack  : TimeArray_t := (others => 0 fs); -- signal back at the receiver pins of lane 0
    signal SigCnt   : NatArray_t  := (others => 0);    -- number of returns of the signal

    -- Traffic: bursts of Packets_c packets per VC and direction, released one after the other
    signal StartTraffic : boolean    := false;
    signal BurstGo      : natural    := 1;
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

    -- Name padded to 12 characters
    function pad12 (
        s : string) return string is
        variable R_v : string(1 to 12) := (others => ' ');
    begin
        R_v(1 to s'length) := s;
        return R_v;
    end function;

    -- Kind of a word sent on a lane, for the timeline of the lane initialisation
    function wordKindName (
        w : std_logic_vector(31 downto 0);
        k : std_logic_vector(3 downto 0)) return string is
    begin
        if k(0) = '1' and w(15 downto 8) /= SymLlcw_c and w(15 downto 8) /= SymInvLlcw_c then
            return pad12("control");
        elsif k(0) = '1' and w(7 downto 0) = K28_5_c then
            if w(23 downto 16) = SymInit1_c or w(23 downto 16) = SymInvInit1_c then
                return pad12("INIT1");
            elsif w(23 downto 16) = SymInit2_c or w(23 downto 16) = SymInvInit2_c then
                return pad12("INIT2");
            elsif w(23 downto 16) = SymInit3_c then
                return pad12("INIT3");
            end if;
            return pad12("K28.5 word");
        elsif k(0) = '1' and w(7 downto 0) = K28_7_c then
            if w(23 downto 16) = SymIdle_c then
                return pad12("IDLE");
            elsif w(23 downto 16) = SymSkip_c then
                return pad12("SKIP");
            elsif w(23 downto 16) = SymLostSignal_c then
                return pad12("LOST_SIGNAL");
            elsif w(23 downto 16) = SymStandby_c then
                return pad12("STANDBY");
            end if;
            return pad12("K28.7 word");
        elsif k /= "0000" then
            return pad12("control");
        end if;
        return pad12("data");
    end function;

    -- Name of a lane state of LANE_STATUS
    function laneStateName (
        code : std_logic_vector(3 downto 0)) return string is
    begin

        case to_integer(unsigned(code)) is
            when 0 =>
                return "ClearLine";
            when 1 =>
                return "Disabled";
            when 2 =>
                return "Wait";
            when 3 =>
                return "Started";
            when 4 =>
                return "InvertRxPolarity";
            when 5 =>
                return "Connecting";
            when 6 =>
                return "Connected";
            when 7 =>
                return "Active";
            when 8 =>
                return "PrepareStandby";
            when 9 =>
                return "LossOfSignal";
            when others =>
                return "unknown";
        end case;

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
        variable T_v    : time;
        variable B_v    : Data_t;
        variable Done_v : boolean;
        variable Fail_v : boolean := false;
        variable To_v   : NatArray_t;
        variable Ls_v   : DataArray_t;
        variable Dl_v   : DataArray_t;
        variable Left_v : boolean := false; -- lane 0 of A left Active during the interruption

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

        -- Result of the testbench; stops the simulation with Finish_g
        procedure endSim is
        begin
            if not Fail_v then
                report "Simulation done at " & time'image(now);
            end if;
            PaCoreTbPass <= not Fail_v;
            PaCoreTbEnd  <= true;
            if Finish_g then
                finish;
            end if;
            wait;
        end procedure;

    -- Sequence
    begin
        Rst <= '1';
        wait for 200 ns;
        Rst <= '0';
        wait until TxReady(0) = '1' and TxReady(1) = '1' for Timeout_c;
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
        report "Traffic started at " & time'image(now);
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

        if Short_g then

            for e in 0 to 1 loop

                for l in 0 to Lanes_c-1 loop
                    rd(e, RegLaneTo_c + 16#20# * l, A_v);
                    rd(e, RegLaneEv_c + 16#20# * l, B_v);
                    report "End " & integer'image(e) & " lane " & integer'image(l) & ": LANE_TIMEOUT_COUNT " &
                           integer'image(to_integer(unsigned(A_v(15 downto 0)))) & ", LANE_EVENTS " &
                           to_hstring(B_v(3 downto 0));
                end loop;

            end loop;

            for e in 0 to 1 loop

                for v in 0 to Vcs_c-1 loop
                    if Received(e, v) /= Packets_c then
                        report "FAIL: packets missing" severity error;
                        Fail_v := true;
                    end if;
                end loop;

                if BcReceived(e) /= Bcs_c or errorSum(e) /= 0 then
                    report "FAIL: broadcast messages missing or errors" severity error;
                    Fail_v := true;
                end if;
                rd(e, RegDlErrors_c, A_v);
                report "End " & integer'image(e) & ": DL_ERRORS " & to_hstring(A_v);
                if A_v(12 downto 0) /= "0000000000000" then
                    report "FAIL: errors reported in the MIB" severity error;
                    Fail_v := true;
                end if;
            end loop;

            -- Restart of lane 0: the transmitter of lane 0 of B is disabled at its adapter for CutTime_c, A loses
            -- the signal and restarts its lane, B follows. The lane states are polled every microsecond; lane 0
            -- must be Active again at both ends within RelockMax_c, then the second burst is delivered.
            if Relock_g then

                for e in 0 to 1 loop
                    rd(e, RegLaneTo_c, A_v);
                    To_v(e) := to_integer(unsigned(A_v(15 downto 0)));
                    Ls_v(e) := (others => '1');
                    Dl_v(e) := (others => '1');
                end loop;

                RelockOn <= true;
                wait for 1 us;
                TxOff(1) <= '1';
                report "Transmitter of lane 0 of B disabled at its adapter at " & time'image(now);
                T_v      := now;

                loop
                    wait for 1 us;

                    for e in 0 to 1 loop
                        rd(e, RegLaneStat_c, A_v);
                        rd(e, RegDlStatus_c, B_v);
                        if A_v(5 downto 0) /= Ls_v(e)(5 downto 0) or B_v(1 downto 0) /= Dl_v(e)(1 downto 0) then
                            report "End " & integer'image(e) & ": lane 0 " & laneStateName(A_v(3 downto 0)) &
                                   ", NO_SIGNAL " & std_logic'image(A_v(5)) & ", RXERR_COUNT " &
                                   integer'image(to_integer(unsigned(A_v(15 downto 8)))) & ", link state " &
                                   integer'image(to_integer(unsigned(B_v(1 downto 0)))) & " at " & time'image(now);
                        end if;
                        Ls_v(e) := A_v;
                        Dl_v(e) := B_v;
                    end loop;

                    if Ls_v(0)(3 downto 0) /= "0111" then
                        Left_v := true;
                    end if;

                    if TxOff(1) = '1' and now - T_v >= CutTime_c then
                        TxOff(1) <= '0';
                        T_v      := now;
                        report "Transmitter of lane 0 of B enabled again at its adapter at " & time'image(now);
                    elsif TxOff(1) = '0' and Ls_v(0)(3 downto 0) = "0111" and Ls_v(1)(3 downto 0) = "0111" then
                        exit;
                    end if;
                    exit when TxOff(1) = '0' and now - T_v > RelockMax_c;
                end loop;

                if not Left_v then
                    report "FAIL: lane 0 of A did not leave Active during the interruption (no restart)" severity error;
                    Fail_v := true;
                end if;
                if Ls_v(0)(3 downto 0) = "0111" and Ls_v(1)(3 downto 0) = "0111" then
                    report "Lane 0 Active again at both ends at " & time'image(now) & " (" & time'image(now - T_v) &
                           " after the transmitter of B was enabled again)";
                else
                    report "FAIL: lane 0 not Active again at both ends within " & time'image(RelockMax_c) &
                           " after the transmitter of B was enabled again" severity error;
                    Fail_v := true;
                end if;

                for e in 0 to 1 loop
                    rd(e, RegLaneTo_c, A_v);
                    rd(e, RegLaneEv_c, B_v);
                    report "End " & integer'image(e) & " lane 0 after the restart: LANE_TIMEOUT_COUNT " &
                           integer'image(to_integer(unsigned(A_v(15 downto 0)))) & " (" &
                           integer'image(to_integer(unsigned(A_v(15 downto 0))) - To_v(e)) &
                           " during the restart), LANE_EVENTS " & to_hstring(B_v(3 downto 0));
                    rd(e, RegDlErrors_c, A_v);
                    report "End " & integer'image(e) & " after the restart: DL_ERRORS " & to_hstring(A_v);
                end loop;

                -- Second burst over the restarted link
                if not Fail_v then
                    BurstGo <= 2;
                    T_v     := now;

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

                        exit when Done_v or now - T_v > 200 us;
                    end loop;

                    report "Second burst delivered at " & time'image(now);

                    for e in 0 to 1 loop

                        for v in 0 to Vcs_c-1 loop
                            if Received(e, v) /= 2 * Packets_c then
                                report "FAIL: packets missing after the restart" severity error;
                                Fail_v := true;
                            end if;
                        end loop;

                        if errorSum(e) /= 0 then
                            report "FAIL: errors after the restart" severity error;
                            Fail_v := true;
                        end if;
                    end loop;

                end if;
            end if;

            endSim;
        end if;

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
        BurstGo <= 2;

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
            if A_v(12 downto 0) /= "0000000000000" or unsigned(B_v) /= 0 then
                report "FAIL: errors or retries reported in the MIB" severity error;
                Fail_v := true;
            end if;
        end loop;

        -- Transmitter reset in operation (CORE-PL-04, PA-ST-02): the adapter of A is reset with the
        -- link up and no traffic. Its reset controller clears the BUFG_GT, so LaneClk of A stops; the
        -- MIB of A reports TX_READY 0 and TX_LOST while LaneClk stands still; both ends initialise the
        -- link again when the transmitters are ready, and a third burst is delivered.
        PaRstReq(0) <= '1';
        wait for 100 ns;
        PaRstReq(0) <= '0';
        T_v         := now;
        report "Reset request of the adapter of A from " & time'image(now - 100 ns) & " to " & time'image(now);

        loop
            wait for 100 ns;
            exit when now - LaneEdge(0) > 1 us or now - T_v > 100 us;
        end loop;

        if now - LaneEdge(0) > 1 us then
            report "Lane clock of A stopped at " & time'image(LaneEdge(0));
        else
            report "FAIL: the lane clock of A did not stop" severity error;
            Fail_v := true;
        end if;
        rd(0, RegDlStatus_c, A_v);
        rd(0, RegDlErrors_c, B_v);
        report "A with its lane clock stopped: DL_STATUS " & to_hstring(A_v) & ", DL_ERRORS " & to_hstring(B_v);
        if A_v(9) /= '0' or B_v(12) /= '1' then
            report "FAIL: TX_READY or TX_LOST of A while its lane clock stands still" severity error;
            Fail_v := true;
        end if;
        wait until TxReady(0) = '1' for 1 ms;
        report "Transceivers of A ready again at " & time'image(now);

        loop
            wait for 2 us;
            rd(0, RegDlStatus_c, A_v);
            rd(1, RegDlStatus_c, B_v);
            exit when (A_v(1 downto 0) = "11" and B_v(1 downto 0) = "11") or now - T_v > 1 ms;
        end loop;

        report "Link initialised again at " & time'image(now);
        if A_v(1 downto 0) /= "11" or B_v(1 downto 0) /= "11" then
            report "FAIL: link not initialised after the transmitter reset" severity error;
            Fail_v := true;
        end if;
        BurstGo <= 3;

        loop
            wait for 2 us;
            Done_v := true;

            for e in 0 to 1 loop

                for v in 0 to Vcs_c-1 loop
                    if Received(e, v) < 3 * Packets_c then
                        Done_v := false;
                    end if;
                end loop;

            end loop;

            exit when Done_v or now - T_v > 2 ms;
        end loop;

        report "Third burst delivered at " & time'image(now);

        for e in 0 to 1 loop

            for v in 0 to Vcs_c-1 loop
                if Received(e, v) /= 3 * Packets_c then
                    report "FAIL: packets missing after the transmitter reset" severity error;
                    Fail_v := true;
                end if;
            end loop;

            if errorSum(e) /= 0 then
                report "FAIL: errors after the transmitter reset" severity error;
                Fail_v := true;
            end if;
        end loop;

        for e in 0 to 1 loop

            for l in 0 to Lanes_c-1 loop
                rd(e, RegLaneTo_c + 16#20# * l, A_v);
                rd(e, RegLaneEv_c + 16#20# * l, B_v);
                report "End " & integer'image(e) & " lane " & integer'image(l) & ": LANE_TIMEOUT_COUNT " &
                       integer'image(to_integer(unsigned(A_v(15 downto 0)))) & ", LANE_EVENTS " &
                       to_hstring(B_v(3 downto 0));
            end loop;

        end loop;

        rd(0, RegDlErrors_c, A_v);
        rd(1, RegDlErrors_c, B_v);
        report "After the transmitter reset of A: DL_ERRORS A " & to_hstring(A_v) & ", B " & to_hstring(B_v);
        if A_v(12) /= '1' then
            report "FAIL: TX_LOST of A not kept" severity error;
            Fail_v := true;
        end if;
        if B_v(12) /= '0' then
            report "FAIL: TX_LOST of B set, its transmitters were not reset" severity error;
            Fail_v := true;
        end if;

        endSim;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Exact time of the completion of the first burst: the last packet of every VC and the last
    -- broadcast message received at both ends (the sequencer only polls it)
    -----------------------------------------------------------------------------------------------
    p_burst_done : process is
        variable Done_v  : boolean;
        variable Start_v : time;
    begin
        wait until StartTraffic;
        Start_v := now;

        loop
            wait on Received, BcReceived;
            Done_v := BcReceived(0) = Bcs_c and BcReceived(1) = Bcs_c;

            for e in 0 to 1 loop

                for v in 0 to Vcs_c-1 loop
                    if Received(e, v) < Packets_c then
                        Done_v := false;
                    end if;
                end loop;

            end loop;

            exit when Done_v;
        end loop;

        report "First burst complete at " & time'image(now) & " (" & time'image(now - Start_v) &
               " after the start of the traffic)";
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Two ends
    -----------------------------------------------------------------------------------------------
    g_end : for e in 0 to 1 generate

        PaRst(e) <= Rst or PaRstReq(e);

        -- Last rising edge of the lane clock (the reset controller stops it during a transmitter reset); the first edge
        -- after a stop of more than 1 us is reported
        p_lane_edge : process (LaneClk(e)) is
        begin
            if rising_edge(LaneClk(e)) then
                if LaneEdge(e) > 0 fs and now - LaneEdge(e) > 1 us then
                    report "End " & integer'image(e) & ": LaneClk runs again at " & time'image(now) &
                           " (stopped after " & time'image(LaneEdge(e)) & ")";
                end if;
                LaneEdge(e) <= now;
            end if;
        end process;

        -- Timestamps of the first LaneClk edge and of every edge of Stat_TxReady
        p_lane_first : process is
        begin
            wait until rising_edge(LaneClk(e));
            report "End " & integer'image(e) & ": first LaneClk edge at " & time'image(now);
            wait;
        end process;

        p_tx_ready_edges : process is
        begin
            wait on TxReady(e);
            report "End " & integer'image(e) & ": Stat_TxReady " & std_logic'image(TxReady(e)) & " at " &
                   time'image(now);
        end process;

        -- Invariant of the transmitter ready status (CORE-PL-04, PA-ST-02): while Stat_TxReady is 1, LaneClk of
        -- the end runs. Stat_TxReady is a register of FreeRunClk and may follow a stop of LaneClk by two cycles.
        p_tx_ready_clk : process (FreeRunClk) is
        begin
            if rising_edge(FreeRunClk) then
                if TxReady(e) = '1' and now - LaneEdge(e) > 2 * RefPeriodB_c + 2 * FreePeriod_c then
                    report "FAIL: end " & integer'image(e) & ": Stat_TxReady 1 while LaneClk stands still (last edge at " &
                           time'image(LaneEdge(e)) & ")" severity error;
                end if;
            end if;
        end process;

        -- Timeline of the receivers: every change of the receivers ready status and of the alignment of all lanes
        AllAligned(e) <= and Aligned(e);

        p_rx_timeline : process is
        begin
            wait on RxReady(e), AllAligned(e);
            if RxReady(e)'event then
                report "End " & integer'image(e) & ": receivers ready " & std_logic'image(RxReady(e)) & " at " &
                       time'image(now);
            end if;
            if AllAligned(e)'event then
                report "End " & integer'image(e) & ": all lanes aligned " & std_logic'image(AllAligned(e)) & " at " &
                       time'image(now);
            end if;
        end process;

        -- Timeline of the lane initialisation at the ports: transmitter, receiver and CDR enables and NoSignal of the
        -- lanes, and every change of the kind of the lane words sent on lane 0 (INIT1, INIT2, INIT3, IDLE, LOST_SIGNAL,
        -- STANDBY; the PRBS words of the initialisation, the Data Link words and SKIP are left out); at most 60 lines
        p_lane_enables : process is
            variable N_v     : natural := 0;
            variable Again_v : boolean := false;
        begin
            wait on TxEnable(e), RxEnable(e), CdrEnable(e), NoSignal(e);
            if RelockOn and not Again_v then
                N_v     := 0;
                Again_v := true;
            end if;
            if N_v < 60 then
                report "End " & integer'image(e) & ": TxEnable " & to_string(TxEnable(e)) & ", RxEnable " &
                       to_string(RxEnable(e)) & ", CdrEnable " & to_string(CdrEnable(e)) & ", NoSignal " &
                       to_string(NoSignal(e)) & " at " & time'image(now);
                N_v := N_v + 1;
            end if;
        end process;

        -- Timeline of the receive side at the adapter outputs (lane 0): the first valid word, the first 40 words with a
        -- code or disparity error, and the end of the first run of 1023 consecutive valid words without an error (the
        -- condition of the Lane layer to leave Started)
        p_rx_words : process (LaneClk(e)) is
            variable First_v : boolean := true;
            variable NErr_v  : natural := 0;
            variable Run_v   : natural := 0;
            variable Done_v  : boolean := false;
        begin
            if rising_edge(LaneClk(e)) then
                if PhyRxVld(e)(0) = '1' then
                    if First_v then
                        report "End " & integer'image(e) & ": first valid received word on lane 0 at " & time'image(now);
                        First_v := false;
                    end if;
                    if (PhyRxCode(e)(3 downto 0) or PhyRxDisp(e)(3 downto 0)) /= "0000" then
                        NErr_v := NErr_v + 1;
                        Run_v  := 0;
                        if NErr_v <= 40 then
                            report "End " & integer'image(e) & ": received word " & integer'image(NErr_v) &
                                   " with errors (code " & to_string(PhyRxCode(e)(3 downto 0)) & ", disparity " &
                                   to_string(PhyRxDisp(e)(3 downto 0)) & ") at " & time'image(now);
                        end if;
                    elsif not Done_v then
                        Run_v := Run_v + 1;
                        if Run_v = 1023 then
                            report "End " & integer'image(e) & ": 1023 consecutive received words without error at " &
                                   time'image(now) & " (" & integer'image(NErr_v) & " words with errors before)";
                            Done_v := true;
                        end if;
                    end if;
                end if;
            end if;
        end process;

        p_lane_words : process (LaneClk(e)) is
            variable Last_v  : string(1 to 12) := (others => ' ');
            variable Name_v  : string(1 to 12);
            variable N_v     : natural         := 0;
            variable Again_v : boolean         := false;
        begin
            if rising_edge(LaneClk(e)) then
                if RelockOn and not Again_v then
                    N_v     := 0;
                    Again_v := true;
                end if;
                Name_v := wordKindName(PhyTxData(e)(31 downto 0), PhyTxK(e)(3 downto 0));
                if Name_v /= Last_v and Name_v /= pad12("SKIP") and Name_v /= pad12("data") and
                   Name_v /= pad12("control") and N_v < 60 then
                    report "End " & integer'image(e) & ": lane 0 sends " & Name_v & " from " & time'image(now);
                    Last_v := Name_v;
                    N_v    := N_v + 1;
                end if;
            end if;
        end process;

        -- Transmitter enables at the adapter: lane 0 disabled while TxOff (Relock_g)
        p_tx_enable : process (TxEnable(e), TxOff(e)) is
        begin
            TxEnGt(e)    <= TxEnable(e);
            TxEnGt(e)(0) <= TxEnable(e)(0) and not TxOff(e);
        end process;

        -- Relock phase: the signal of lane 0 at the receiver pins of this end lost (no transition for 100 ns, or a
        -- value other than 0 and 1) and back (the first transition to 0 or 1 after it); at most 40 lines
        p_line : process is
            variable On_v   : boolean := true;
            variable N_v    : natural := 0;
            variable Last_v : time    := 0 fs;
        begin
            wait on TxP(1 - e)(0) for 100 ns;
            if TxP(1 - e)(0)'event and (TxP(1 - e)(0) = '0' or TxP(1 - e)(0) = '1') then
                if not On_v then
                    On_v := true;
                    if RelockOn then
                        SigBack(e) <= now;
                        SigCnt(e)  <= SigCnt(e) + 1;
                        if N_v < 40 then
                            report "End " & integer'image(e) & ": signal on lane 0 back at the receiver at " &
                                   time'image(now) & " (transmitter enable of the far end " &
                                   std_logic'image(TxEnGt(1 - e)(0)) & ")";
                            N_v := N_v + 1;
                        end if;
                    end if;
                end if;
                Last_v := now;
            elsif On_v and (now - Last_v >= 100 ns or TxP(1 - e)(0)'event) then
                On_v := false;
                if RelockOn and N_v < 40 then
                    report "End " & integer'image(e) & ": signal on lane 0 lost at the receiver after " &
                           time'image(Last_v) & " (transmitter enable of the far end " &
                           std_logic'image(TxEnGt(1 - e)(0)) & ")";
                    N_v := N_v + 1;
                end if;
            end if;
        end process;

        -- Relock phase: after every return of the signal, the first lane word (K28.5 or K28.7) decoded without an
        -- error on lane 0 and the end of the first run of 1023 words without an error; at most 40 lines
        p_relock : process (LaneClk(e)) is
            variable Seen_v : natural := 0;
            variable Word_v : boolean := false;
            variable Run_v  : natural := 0;
            variable NErr_v : natural := 0;
            variable N_v    : natural := 0;
        begin
            if rising_edge(LaneClk(e)) then
                if SigCnt(e) /= Seen_v then
                    Seen_v := SigCnt(e);
                    Word_v := true;
                    Run_v  := 0;
                    NErr_v := 0;
                end if;
                if Seen_v > 0 and PhyRxVld(e)(0) = '1' then
                    if (PhyRxCode(e)(3 downto 0) or PhyRxDisp(e)(3 downto 0)) /= "0000" then
                        NErr_v := NErr_v + 1;
                        Run_v  := 0;
                    else
                        if Word_v and PhyRxK(e)(0) = '1' and
                           (PhyRxData(e)(7 downto 0) = K28_5_c or PhyRxData(e)(7 downto 0) = K28_7_c) then
                            Word_v := false;
                            if N_v < 40 then
                                report "End " & integer'image(e) & ": first lane word on lane 0 after the return of " &
                                       "the signal at " & time'image(now) & " (" & time'image(now - SigBack(e)) &
                                       " after it, " & integer'image(NErr_v) & " words with errors before)";
                                N_v := N_v + 1;
                            end if;
                        end if;
                        if Run_v < 1023 then
                            Run_v := Run_v + 1;
                            if Run_v = 1023 and N_v < 40 then
                                report "End " & integer'image(e) & ": 1023 words without error on lane 0 at " &
                                       time'image(now) & " (" & time'image(now - SigBack(e)) &
                                       " after the return of the signal)";
                                N_v := N_v + 1;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end process;

        i_pa : entity work.ofb_pa_gty
            generic map (
                NumLanes_g => Lanes_c
            )
            port map (
                FreeRunClk    => FreeRunClk,
                Rst           => PaRst(e),
                RefClk        => RefClk(e),
                LaneClk       => LaneClk(e),
                LaneRst       => open,
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
                Phy_TxEnable  => TxEnGt(e),
                Phy_RxEnable  => RxEnable(e),
                Phy_CdrEnable => CdrEnable(e),
                Phy_RxInvert  => RxInvert(e),
                Phy_NoSignal  => NoSignal(e),
                Stat_TxReady  => TxReady(e),
                Stat_RxReady  => RxReady(e),
                Stat_Aligned  => Aligned(e),
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
                Rst               => Rst,
                UserClk           => LaneClk(e),
                CoreClk           => LaneClk(e),
                LaneClk           => LaneClk(e),
                MgmtClk           => FreeRunClk,
                S_Vc_TData        => SVcData(e),
                S_Vc_TKeep        => SVcKeep(e),
                S_Vc_TLast        => SVcLast(e),
                S_Vc_TUser        => (others => '0'),
                S_Vc_TValid       => SVcValid(e),
                S_Vc_TReady       => SVcReady(e),
                M_Vc_TData        => MVcData(e),
                M_Vc_TKeep        => MVcKeep(e),
                M_Vc_TLast        => MVcLast(e),
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
                Phy_NoSignal      => NoSignal(e),
                Phy_TxReady       => TxReady(e)
            );

        -------------------------------------------------------------------------------------------
        -- Packet generator per VC: packets of whole words, beats of Lanes_c words, TLAST on the last
        -- beat
        -------------------------------------------------------------------------------------------
        g_vc : for v in 0 to Vcs_c-1 generate

            p_gen : process is
                variable Beat_v : std_logic_vector(32*Lanes_c-1 downto 0);
                variable Keep_v : std_logic_vector(4*Lanes_c-1 downto 0);
                variable Pos_v  : natural;
                variable Len_v  : natural;
            begin
                wait until StartTraffic;

                for p in 0 to 3 * Packets_c-1 loop
                    if p mod Packets_c = 0 and p / Packets_c >= BurstGo then
                        wait until BurstGo > p / Packets_c;
                    end if;
                    Len_v := packetLen(v, p);
                    Pos_v := 0;

                    while Pos_v < Len_v loop

                        for l in 0 to Lanes_c-1 loop
                            if Pos_v + l < Len_v then
                                Beat_v(32*l+31 downto 32*l) := packetWord(e, v, p, Pos_v + l);
                                Keep_v(4*l+3 downto 4*l)    := "1111";
                            else
                                Beat_v(32*l+31 downto 32*l) := (others => '0');
                                Keep_v(4*l+3 downto 4*l)    := "0000";
                            end if;
                        end loop;

                        wait until rising_edge(LaneClk(e));
                        SVcData(e)(32*Lanes_c*(v+1)-1 downto 32*Lanes_c*v) <= Beat_v;
                        SVcKeep(e)(4*Lanes_c*(v+1)-1 downto 4*Lanes_c*v)   <= Keep_v;
                        if Pos_v + Lanes_c >= Len_v then
                            SVcLast(e)(v) <= '1';
                        else
                            SVcLast(e)(v) <= '0';
                        end if;
                        SVcValid(e)(v) <= '1';

                        loop
                            wait until rising_edge(LaneClk(e));
                            exit when SVcReady(e)(v) = '1';
                        end loop;

                        SVcValid(e)(v) <= '0';
                        Pos_v          := Pos_v + Lanes_c;
                    end loop;

                end loop;

                wait;
            end process;

            ---------------------------------------------------------------------------------------
            -- Packet checker per VC: data words in order, TLAST after the last word of a packet,
            -- no EEP
            ---------------------------------------------------------------------------------------
            p_check : process (LaneClk(e)) is
                variable P_v    : natural := 0;
                variable W_v    : natural := 0;
                variable Word_v : std_logic_vector(31 downto 0);
                variable Keep_v : std_logic_vector(3 downto 0);
                variable Base_v : natural;
            begin
                if rising_edge(LaneClk(e)) then
                    if MVcValid(e)(v) = '1' then

                        for w in 0 to Lanes_c-1 loop
                            Base_v := 32*Lanes_c*v + 32*w;
                            Word_v := MVcData(e)(Base_v+31 downto Base_v);
                            Keep_v := MVcKeep(e)(4*Lanes_c*v+4*w+3 downto 4*Lanes_c*v+4*w);
                            if Keep_v = "1111" then
                                if Word_v /= packetWord(1 - e, v, P_v, W_v) then
                                    report "End " & integer'image(e) & " VC " & integer'image(v) & ": word " &
                                           to_hstring(Word_v) & ", expected " &
                                           to_hstring(packetWord(1 - e, v, P_v, W_v)) severity error;
                                    Errors(e, v) <= Errors(e, v) + 1;
                                end if;
                                W_v := W_v + 1;
                            elsif Keep_v /= "0000" or MVcLast(e)(v) = '0' then
                                report "End " & integer'image(e) & " VC " & integer'image(v) & ": TKEEP " &
                                       to_hstring(Keep_v) & " of word " & integer'image(w) severity error;
                                Errors(e, v) <= Errors(e, v) + 1;
                            end if;
                        end loop;

                        if MVcLast(e)(v) = '1' then
                            if W_v /= packetLen(v, P_v) or MVcUser(e)(v) = '1' then
                                report "End " & integer'image(e) & " VC " & integer'image(v) & ": end of the packet after " &
                                       integer'image(W_v) & " words, EEP " & std_logic'image(MVcUser(e)(v)) severity error;
                                Errors(e, v) <= Errors(e, v) + 1;
                            end if;
                            P_v            := P_v + 1;
                            W_v            := 0;
                            Received(e, v) <= P_v;
                        end if;
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
