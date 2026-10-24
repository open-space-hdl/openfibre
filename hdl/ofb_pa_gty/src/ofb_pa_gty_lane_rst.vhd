---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Reset sequencer of one lane of the GTY Physical adapter (PA-1), in the free-running clock domain. It drives the
-- channel reset ports of the transceiver for three sequences (AM002, "Recommended Receiver Resets for Common
-- Situations" and "Transceiver RX Reset in Response to GTRXRESET Pulse in Full Sequential Mode"):
--   1. Entire receiver reset (PA-RS-04): GTRXRESET with PCSRSVDIN[10] in sequential mode, all masks and
--      PCSRSVDIN[9:8] high until RXRESETDONE; or, in CDR-only mode, an RXCDRRESET pulse and a fixed wait.
--   2. Transmit buffer reset (PA-RS-06): GTTXRESET in single mode on the transmit PCS.
--   3. Receive elastic buffer reset (PA-RS-03): GTRXRESET in single mode on the receive elastic buffer.
-- Requests are served in this order of priority, one sequence at a time, at most once per holdoff time. A request
-- of a receiver reset that comes while a receiver reset runs, or within GapCycles_g after it, is dropped: a lane that
-- restarts while its receiver resets cannot start the next reset, and lanes with the initialisation timeout of the
-- standard (5000 words, shorter than a receiver reset) get initialisation attempts between two resets. Every wait
-- for the transceiver is bounded (PA-RS-05): on expiry the sequencer returns to idle and reports the timeout. A new
-- sequence starts only while the reset controller of the wizard reports the receivers ready; a running sequence is
-- not aborted by it.
--
-- Documentation: hdl/ofb_pa_gty/docs/architecture.md (section 5)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pa_gty_lane_rst is
    generic (
        -- Free-running clock cycles: masks stable before a reset pulse, pulse (at least one reference clock period),
        -- masks held after a single-mode pulse (no reset done in single mode), distance between two sequences
        SetupCycles_g      : positive                      := 8;
        PulseCycles_g      : positive                      := 16;
        HoldCycles_g       : positive                      := 128;
        HoldoffCycles_g    : positive                      := 256;
        -- CDR-only mode: wait after the RXCDRRESET pulse
        CdrWaitCycles_g    : positive                      := 10000;
        -- Gap after a receiver reset (entire or CDR-only, completed or timed out) in which requests of a receiver
        -- reset are dropped (default at 100 MHz: 4 ms)
        GapCycles_g        : natural                       := 400_000;
        -- Bounds of the waits for RXRESETDONE after the GTRXRESET pulse: low (the sequence started), then high (it
        -- completed). Defaults at 100 MHz: 10 ms and 150 ms (PG442 gives up to 150 ms for a full GT reset of a quad)
        DoneLowCycles_g    : positive                      := 1_000_000;
        DoneHighCycles_g   : positive                      := 15_000_000;
        -- PCSRSVDIN outside the reset sequences until the first sequence takes the configured value
        PcsRsvdInDefault_g : std_logic_vector(15 downto 0) := x"0360"
    );
    port (
        -- Control Ports
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Requests (synchronised to Clk): rising edges of Req_Full and Req_Buf, level of Req_Tx (transmit buffer
        -- error, kept by the transceiver until the reset)
        Req_Full         : in    std_logic;
        Req_Buf          : in    std_logic;
        Req_Tx           : in    std_logic;
        -- Configuration (static, synchronised to Clk): CDR-only mode of the receiver reset, PCSRSVDIN base value
        -- (taken at the start of every sequence)
        Cfg_CdrOnly      : in    std_logic;
        Cfg_PcsRsvdIn    : in    std_logic_vector(15 downto 0);
        -- Status of the transceiver (synchronised to Clk): receivers ready (reset controller of the wizard),
        -- RXRESETDONE of the channel
        Gt_MasterDone    : in    std_logic;
        Gt_RxResetDone   : in    std_logic;
        -- Channel reset ports of the transceiver
        Gt_RxReset       : out   std_logic;
        Gt_RxResetMode   : out   std_logic_vector(1 downto 0);
        Gt_RxPmaMask     : out   std_logic_vector(6 downto 0);
        Gt_RxPcsMask     : out   std_logic_vector(4 downto 0);
        Gt_RxCdrReset    : out   std_logic;
        Gt_TxReset       : out   std_logic;
        Gt_TxResetMode   : out   std_logic_vector(1 downto 0);
        Gt_TxPmaMask     : out   std_logic_vector(2 downto 0);
        Gt_TxPcsMask     : out   std_logic;
        Gt_PcsRsvdIn     : out   std_logic_vector(15 downto 0);
        -- Status: receiver reset (entire or CDR) in progress, receive buffer reset window, one-cycle events
        Stat_RxBusy      : out   std_logic;
        Stat_BufBusy     : out   std_logic;
        Ev_RxResetDone   : out   std_logic;
        Ev_Timeout       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_pa_gty_lane_rst is

    -- Values of the reset ports outside the sequences: the ties of the wizard without these optional ports
    -- (sequential mode, all masks set), as the master reset of the wizard requires
    constant RxModeSeq_c    : std_logic_vector(1 downto 0) := "00";
    constant RxModeSingle_c : std_logic_vector(1 downto 0) := "11";
    constant RxPmaAll_c     : std_logic_vector(6 downto 0) := "1111111";
    constant RxPmaNone_c    : std_logic_vector(6 downto 0) := "0000000";
    constant RxPcsAll_c     : std_logic_vector(4 downto 0) := "11111";
    constant RxPcsBuf_c     : std_logic_vector(4 downto 0) := "00100";
    constant TxPmaAll_c     : std_logic_vector(2 downto 0) := "111";
    constant TxPmaNone_c    : std_logic_vector(2 downto 0) := "000";
    -- PCSRSVDIN: bits 9:8 (RXDAPIRESETMASK) high during the entire receiver reset, bit 10 (RXDAPIRESET) with the
    -- GTRXRESET pulse (AM002); zero during the single-mode resets
    constant PcsMaskBits_c  : std_logic_vector(15 downto 0) := x"0300";
    constant PcsResetBit_c  : std_logic_vector(15 downto 0) := x"0400";

    function maxOf (a : natural; b : natural) return natural is
    begin
        if a > b then
            return a;
        end if;
        return b;
    end function;

    -- Largest counter value of all intervals and waits
    constant FixMax_c : positive := maxOf(maxOf(SetupCycles_g, PulseCycles_g), maxOf(HoldCycles_g, HoldoffCycles_g));
    constant CntMax_c : positive := maxOf(maxOf(FixMax_c, CdrWaitCycles_g), maxOf(DoneLowCycles_g, DoneHighCycles_g));

    type Fsm_t is (
        Idle_s, FullSetup_s, FullPulse_s, FullWaitLow_s, FullWaitHigh_s, CdrPulse_s, CdrWait_s,
        TxSetup_s, TxPulse_s, TxHold_s, BufSetup_s, BufPulse_s, BufHold_s, Holdoff_s
    );

    -- Outputs to the transceiver, all from registers: GTRXRESET, GTTXRESET and PCSRSVDIN are asynchronous inputs
    type Outs_r is record
        RxReset   : std_logic;
        RxMode    : std_logic_vector(1 downto 0);
        RxPmaMask : std_logic_vector(6 downto 0);
        RxPcsMask : std_logic_vector(4 downto 0);
        RxCdrRst  : std_logic;
        TxReset   : std_logic;
        TxMode    : std_logic_vector(1 downto 0);
        TxPmaMask : std_logic_vector(2 downto 0);
        TxPcsMask : std_logic;
        PcsRsvdIn : std_logic_vector(15 downto 0);
        RxBusy    : std_logic;
        BufBusy   : std_logic;
    end record;

    -- Port values of a state
    function decode (state : Fsm_t; pcs_base : std_logic_vector(15 downto 0)) return Outs_r is
        variable Out_v : Outs_r;
    begin
        -- Values outside the sequences
        Out_v := (RxReset => '0',
                  RxMode => RxModeSeq_c,
                  RxPmaMask => RxPmaAll_c,
                  RxPcsMask => RxPcsAll_c,
                  RxCdrRst => '0',
                  TxReset => '0',
                  TxMode => RxModeSeq_c,
                  TxPmaMask => TxPmaAll_c,
                  TxPcsMask => '1',
                  PcsRsvdIn => pcs_base,
                  RxBusy => '0',
                  BufBusy => '0');

        case state is
            when FullSetup_s | FullWaitLow_s | FullWaitHigh_s =>
                Out_v.PcsRsvdIn := pcs_base or PcsMaskBits_c;
                Out_v.RxBusy    := '1';
            when FullPulse_s =>
                Out_v.RxReset   := '1';
                Out_v.PcsRsvdIn := pcs_base or PcsMaskBits_c or PcsResetBit_c;
                Out_v.RxBusy    := '1';
            when CdrPulse_s =>
                Out_v.RxCdrRst := '1';
                Out_v.RxBusy   := '1';
            when CdrWait_s =>
                Out_v.RxBusy := '1';
            when TxSetup_s | TxHold_s =>
                Out_v.TxMode    := RxModeSingle_c;
                Out_v.TxPmaMask := TxPmaNone_c;
                Out_v.PcsRsvdIn := (others => '0');
            when TxPulse_s =>
                Out_v.TxReset   := '1';
                Out_v.TxMode    := RxModeSingle_c;
                Out_v.TxPmaMask := TxPmaNone_c;
                Out_v.PcsRsvdIn := (others => '0');
            when BufSetup_s | BufHold_s =>
                Out_v.RxMode    := RxModeSingle_c;
                Out_v.RxPmaMask := RxPmaNone_c;
                Out_v.RxPcsMask := RxPcsBuf_c;
                Out_v.PcsRsvdIn := (others => '0');
                Out_v.BufBusy   := '1';
            when BufPulse_s =>
                Out_v.RxReset   := '1';
                Out_v.RxMode    := RxModeSingle_c;
                Out_v.RxPmaMask := RxPmaNone_c;
                Out_v.RxPcsMask := RxPcsBuf_c;
                Out_v.PcsRsvdIn := (others => '0');
                Out_v.BufBusy   := '1';
            when others =>
                null;
        end case;

        return Out_v;
    end function;

    type TwoProcess_r is record
        State    : Fsm_t;
        Cnt      : natural range 0 to CntMax_c;
        FullLast : std_logic;
        BufLast  : std_logic;
        FullPend : std_logic;
        BufPend  : std_logic;
        Gap      : natural range 0 to GapCycles_g;
        PcsBase  : std_logic_vector(15 downto 0);
        RxDoneEv : std_logic;
        TimeoEv  : std_logic;
        Outs     : Outs_r;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v : TwoProcess_r;

        -- Next state at the end of a fixed interval (the counter is a parameter, not read from r inside)
        procedure step (constant cnt : natural; constant cycles : positive; constant next_s : Fsm_t) is
        begin
            if cnt >= cycles-1 then
                v.State := next_s;
                v.Cnt   := 0;
            else
                v.Cnt := cnt + 1;
            end if;
        end procedure;

    -- Next state
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.RxDoneEv := '0';
        v.TimeoEv  := '0';

        -- Requests: rising edges kept pending until served; a receiver reset request only outside a receiver reset
        -- and its gap
        v.FullLast := Req_Full;
        v.BufLast  := Req_Buf;
        if r.Gap /= 0 then
            v.Gap := r.Gap - 1;
        end if;
        if Req_Full = '1' and r.FullLast = '0' and r.Gap = 0 and
           r.State /= FullSetup_s and r.State /= FullPulse_s and r.State /= FullWaitLow_s and
           r.State /= FullWaitHigh_s and r.State /= CdrPulse_s and r.State /= CdrWait_s then
            v.FullPend := '1';
        end if;
        if Req_Buf = '1' and r.BufLast = '0' then
            v.BufPend := '1';
        end if;

        case r.State is

            when Idle_s =>
                v.Cnt := 0;
                -- New sequences only while the receivers of the wizard are ready; the configured PCSRSVDIN base
                -- takes effect here, at the start of a sequence
                if Gt_MasterDone = '1' then
                    if v.FullPend = '1' then
                        v.FullPend := '0';
                        -- The entire receiver reset includes the elastic buffer
                        v.BufPend := '0';
                        v.PcsBase := Cfg_PcsRsvdIn;
                        if Cfg_CdrOnly = '1' then
                            v.State := CdrPulse_s;
                        else
                            v.State := FullSetup_s;
                        end if;
                    elsif Req_Tx = '1' then
                        v.PcsBase := Cfg_PcsRsvdIn;
                        v.State   := TxSetup_s;
                    elsif v.BufPend = '1' then
                        v.BufPend := '0';
                        v.PcsBase := Cfg_PcsRsvdIn;
                        v.State   := BufSetup_s;
                    end if;
                end if;

            -- Entire receiver reset, sequential mode
            when FullSetup_s =>
                step(r.Cnt, SetupCycles_g, FullPulse_s);

            when FullPulse_s =>
                step(r.Cnt, PulseCycles_g, FullWaitLow_s);

            when FullWaitLow_s =>
                if Gt_RxResetDone = '0' then
                    v.State := FullWaitHigh_s;
                    v.Cnt   := 0;
                elsif r.Cnt >= DoneLowCycles_g-1 then
                    v.TimeoEv := '1';
                    v.Gap     := GapCycles_g;
                    v.State   := Holdoff_s;
                    v.Cnt     := 0;
                else
                    v.Cnt := r.Cnt + 1;
                end if;

            when FullWaitHigh_s =>
                if Gt_RxResetDone = '1' then
                    v.RxDoneEv := '1';
                    v.Gap      := GapCycles_g;
                    v.State    := Holdoff_s;
                    v.Cnt      := 0;
                elsif r.Cnt >= DoneHighCycles_g-1 then
                    v.TimeoEv := '1';
                    v.Gap     := GapCycles_g;
                    v.State   := Holdoff_s;
                    v.Cnt     := 0;
                else
                    v.Cnt := r.Cnt + 1;
                end if;

            -- CDR-only receiver reset: direct single reset port, no reset done
            when CdrPulse_s =>
                step(r.Cnt, PulseCycles_g, CdrWait_s);

            when CdrWait_s =>
                if r.Cnt >= CdrWaitCycles_g-1 then
                    v.RxDoneEv := '1';
                    v.Gap      := GapCycles_g;
                    v.State    := Holdoff_s;
                    v.Cnt      := 0;
                else
                    v.Cnt := r.Cnt + 1;
                end if;

            -- Transmit buffer reset, single mode on the transmit PCS
            when TxSetup_s =>
                step(r.Cnt, SetupCycles_g, TxPulse_s);

            when TxPulse_s =>
                step(r.Cnt, PulseCycles_g, TxHold_s);

            when TxHold_s =>
                step(r.Cnt, HoldCycles_g, Holdoff_s);

            -- Receive elastic buffer reset, single mode
            when BufSetup_s =>
                step(r.Cnt, SetupCycles_g, BufPulse_s);

            when BufPulse_s =>
                step(r.Cnt, PulseCycles_g, BufHold_s);

            when BufHold_s =>
                step(r.Cnt, HoldCycles_g, Holdoff_s);

            when Holdoff_s =>
                step(r.Cnt, HoldoffCycles_g, Idle_s);

            -- coverage off
            when others =>
                v.State := Idle_s;
                v.Cnt   := 0;
            -- coverage on

        end case;

        -- Registered outputs of the next state
        v.Outs := decode(v.State, v.PcsBase);

        -- Apply to record
        r_next <= v;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    Gt_RxReset     <= r.Outs.RxReset;
    Gt_RxResetMode <= r.Outs.RxMode;
    Gt_RxPmaMask   <= r.Outs.RxPmaMask;
    Gt_RxPcsMask   <= r.Outs.RxPcsMask;
    Gt_RxCdrReset  <= r.Outs.RxCdrRst;
    Gt_TxReset     <= r.Outs.TxReset;
    Gt_TxResetMode <= r.Outs.TxMode;
    Gt_TxPmaMask   <= r.Outs.TxPmaMask;
    Gt_TxPcsMask   <= r.Outs.TxPcsMask;
    Gt_PcsRsvdIn   <= r.Outs.PcsRsvdIn;
    Stat_RxBusy    <= r.Outs.RxBusy;
    Stat_BufBusy   <= r.Outs.BufBusy;
    Ev_RxResetDone <= r.RxDoneEv;
    Ev_Timeout     <= r.TimeoEv;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Idle_s;
                r.Cnt      <= 0;
                r.FullLast <= '0';
                r.BufLast  <= '0';
                r.FullPend <= '0';
                r.BufPend  <= '0';
                r.Gap      <= 0;
                r.PcsBase  <= PcsRsvdInDefault_g;
                r.RxDoneEv <= '0';
                r.TimeoEv  <= '0';
                r.Outs     <= decode(Idle_s, PcsRsvdInDefault_g);
            end if;
        end if;
    end process;

end architecture;
