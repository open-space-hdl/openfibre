---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Lane transmitter (LN-2): sends the lane control words of the current initialisation state, the
-- words of the Multi-Lane layer in Active, IDLE when there is nothing to send and a SKIP every
-- SkipIntervalWords_g words, or on the SKIP request of the Multi-Lane layer (SkipExternal_g).
--
-- Documentation: hdl/ofb_lane/docs/architecture.md (section 2.2)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_lane_tx is
    generic (
        InitPrbsWords_g     : natural range 0 to 64 := 64;
        SkipIntervalWords_g : positive              := 5000;
        SkipExternal_g      : boolean               := false
    );
    port (
        -- Control Ports
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- Control from the lane initialisation state machine
        Ctrl_Mode          : in    TxMode_t;
        Ctrl_Capability    : in    Char_t;
        Ctrl_LosCause      : in    LosCause_t;
        Ctrl_StandbyReason : in    Char_t;
        Ctrl_SkipReq       : in    std_logic := '0'; -- SKIP request of the Multi-Lane layer
        -- Words of the Multi-Lane layer
        In_Data            : in    Word_t;
        In_K               : in    WordK_t;
        In_Valid           : in    std_logic;
        In_Ready           : out   std_logic;
        -- Words to the Physical adapter (one per clock cycle)
        Out_Data           : out   Word_t;
        Out_K              : out   WordK_t;
        -- Events (one per word sent)
        Ev_Init3Sent       : out   std_logic;
        Ev_StandbySent     : out   std_logic;
        Ev_LostSignalSent  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_lane_tx is

    type TwoProcess_r is record
        Data           : Word_t;
        K              : WordK_t;
        Mode           : TxMode_t;
        PrbsLeft       : natural range 0 to 64;
        SkipCnt        : natural range 0 to SkipIntervalWords_g-1;
        Init3Sent      : std_logic;
        StandbySent    : std_logic;
        LostSignalSent : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PrbsData    : Word_t;
    signal PrbsAdvance : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable SkipDue_v : boolean;
        variable Ready_v   : std_logic;
        variable Advance_v : std_logic;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.Init3Sent      := '0';
        v.StandbySent    := '0';
        v.LostSignalSent := '0';
        v.Mode           := Ctrl_Mode;
        Ready_v          := '0';
        Advance_v        := '0';
        if SkipExternal_g then
            -- All lanes of a multi-lane link send SKIP in the same cycle (ECSS 5.6.4.5a)
            SkipDue_v := Ctrl_SkipReq = '1';
        else
            SkipDue_v := (r.SkipCnt = SkipIntervalWords_g-1);
        end if;

        case Ctrl_Mode is

            -- INIT1 / INIT2 followed by PRBS data words (ECSS 5.5.2.7e, 5.5.2.9e)
            when TxModeInit1_c | TxModeInit2_c =>
                if Ctrl_Mode /= r.Mode or r.PrbsLeft = 0 then
                    if Ctrl_Mode = TxModeInit1_c then
                        v.Data := WordInit1_c;
                    else
                        v.Data := WordInit2_c;
                    end if;
                    v.K        := KCtrl_c;
                    v.PrbsLeft := InitPrbsWords_g;
                else
                    v.Data     := PrbsData;
                    v.K        := KData_c;
                    v.PrbsLeft := r.PrbsLeft - 1;
                    Advance_v  := '1';
                end if;

            -- INIT3 with the capability field (ECSS 5.5.2.10b.3)
            when TxModeInit3_c =>
                v.Data      := wordInit3(Ctrl_Capability);
                v.K         := KCtrl_c;
                v.Init3Sent := '1';

            -- Active: SKIP, words of the Multi-Lane layer, IDLE (ECSS 5.5.3d, 5.5.4a, 5.3.10c)
            when TxModeActive_c =>
                if SkipDue_v then
                    v.Data    := WordSkip_c;
                    v.K       := KCtrl_c;
                    v.SkipCnt := 0;
                else
                    Ready_v := '1';
                    -- The own interval only counts without the SKIP request of the Multi-Lane layer
                    if not SkipExternal_g then
                        v.SkipCnt := r.SkipCnt + 1;
                    end if;
                    if In_Valid = '1' then
                        v.Data := In_Data;
                        v.K    := In_K;
                    else
                        v.Data := WordIdle_c;
                        v.K    := KCtrl_c;
                    end if;
                end if;

            -- 32 STANDBY / LOST_SIGNAL words, counted by LN-1 (ECSS 5.5.2.12b.3, 5.5.2.13b.3)
            when TxModeStandby_c =>
                v.Data        := wordStandby(Ctrl_StandbyReason);
                v.K           := KCtrl_c;
                v.StandbySent := '1';

            when TxModeLostSignal_c =>
                v.Data           := wordLostSignal(Ctrl_LosCause);
                v.K              := KCtrl_c;
                v.LostSignalSent := '1';

            -- Transmitter disabled
            when others =>
                v.Data := WordIdle_c;
                v.K    := KCtrl_c;

        end case;

        -- SKIP interval only counts in Active
        if Ctrl_Mode /= TxModeActive_c then
            v.SkipCnt := 0;
        end if;

        -- Outputs
        In_Ready    <= Ready_v;
        PrbsAdvance <= Advance_v;

        -- Apply to record
        r_next <= v;

    end process;

    Out_Data          <= r.Data;
    Out_K             <= r.K;
    Ev_Init3Sent      <= r.Init3Sent;
    Ev_StandbySent    <= r.StandbySent;
    Ev_LostSignalSent <= r.LostSignalSent;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Data           <= WordIdle_c;
                r.K              <= KCtrl_c;
                r.Mode           <= TxModeOff_c;
                r.PrbsLeft       <= 0;
                r.SkipCnt        <= 0;
                r.Init3Sent      <= '0';
                r.StandbySent    <= '0';
                r.LostSignalSent <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- PRBS data words during initialisation
    -----------------------------------------------------------------------------------------------
    i_prbs : entity olo.olo_base_prbs
        generic map (
            Polynomial_g    => PrbsPolynomial_c,
            Seed_g          => PrbsSeed_c,
            BitsPerSymbol_g => 32
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            Out_Data  => PrbsData,
            Out_Ready => PrbsAdvance
        );

end architecture;
