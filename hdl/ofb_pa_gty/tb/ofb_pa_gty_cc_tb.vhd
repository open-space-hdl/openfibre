---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of two Physical adapters PA-1 with the transceiver model, serial lines crossed. Every
-- lane sends counting data words, IDLE words and a SKIP word every 16 words, which must arrive in
-- order. With the reference clock of B slower than that of A (RefPpmB_g), the receive elastic
-- buffers insert SKIP words at A and remove SKIP words at B (clock correction). With FarLoopback_g,
-- B then enables the far-end serial loopback of every lane and A receives its own words in order.
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
entity ofb_pa_gty_cc_tb is
    generic (
        RefPpmB_g     : natural := 1000;  -- reference clock of B slower by this many ppm
        FarLoopback_g : boolean := false  -- second phase: far-end serial loopback at B
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pa_gty_cc_tb is

    constant Lanes_c      : positive := 4;
    constant FreePeriod_c : time     := 10 ns;
    constant Words_c      : positive := 3000;  -- data words checked per lane and end
    constant ClkCors_c    : natural  := 4 * boolean'pos(RefPpmB_g > 0); -- clock corrections expected per end
    constant Timeout_c    : time     := 300 us;

    -- SpaceFibre characters
    constant K28_7_c    : std_logic_vector(7 downto 0)  := x"FC";
    constant SymLlcw_c  : std_logic_vector(7 downto 0)  := x"CE";
    constant SymSkip_c  : std_logic_vector(7 downto 0)  := x"7F";
    constant SymIdle_c  : std_logic_vector(7 downto 0)  := x"CF";
    constant WordSkip_c : std_logic_vector(31 downto 0) := SymSkip_c & SymSkip_c & SymLlcw_c & K28_7_c;
    constant WordIdle_c : std_logic_vector(31 downto 0) := SymIdle_c & SymIdle_c & SymLlcw_c & K28_7_c;

    type Bit2_t is array (0 to 1) of std_logic;
    type Lanes2_t is array (0 to 1) of std_logic_vector(Lanes_c-1 downto 0);
    type Data2_t is array (0 to 1) of std_logic_vector(32*Lanes_c-1 downto 0);
    type K2_t is array (0 to 1) of std_logic_vector(4*Lanes_c-1 downto 0);
    type Cnt2_t is array (0 to 1, 0 to Lanes_c-1) of natural;
    type Nat2_t is array (0 to 1) of natural;
    type Time2_t is array (0 to 1) of time;

    constant RefHalf_c : Time2_t := (3200 ps, 3200 ps + RefPpmB_g * 3200 fs);

    signal RefClk     : Bit2_t                               := (others => '0');
    signal FreeRunClk : std_logic                            := '0';
    signal Rst        : std_logic                            := '1';
    signal LaneClk    : Bit2_t;
    signal TxReady    : Bit2_t;
    signal RxReady    : Bit2_t;
    signal TxP        : Lanes2_t;
    signal TxN        : Lanes2_t;
    signal TxData     : Data2_t                              := (others => (others => '0'));
    signal TxK        : K2_t                                 := (others => (others => '0'));
    signal RxData     : Data2_t;
    signal RxK        : K2_t;
    signal RxCodeErr  : K2_t;
    signal RxDispErr  : K2_t;
    signal RxValid    : Lanes2_t;
    signal Aligned    : Lanes2_t;
    signal RxBufErr   : Lanes2_t;
    signal ClkCor     : Lanes2_t;
    signal FarLb      : std_logic_vector(Lanes_c-1 downto 0) := (others => '0');
    signal FarLbOf    : Lanes2_t;
    signal CheckEn    : Bit2_t                               := (others => '1');

    signal Checked   : Cnt2_t := (others => (others => 0));
    signal Errors    : Cnt2_t := (others => (others => 0));
    signal ClkCorCnt : Nat2_t := (others => 0);
    signal BufErrCnt : Nat2_t := (others => 0);

begin

    FarLbOf(0) <= (others => '0');
    FarLbOf(1) <= FarLb;

    RefClk(0)  <= not RefClk(0) after RefHalf_c(0);
    RefClk(1)  <= not RefClk(1) after RefHalf_c(1);
    FreeRunClk <= not FreeRunClk after FreePeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Done_v : boolean;
        variable Fail_v : boolean := false;
        variable Base_v : Cnt2_t;
        variable Err_v  : Cnt2_t;
    begin
        Rst <= '1';
        wait for 200 ns;
        Rst <= '0';
        wait until RxReady(0) = '1' and RxReady(1) = '1' for Timeout_c;
        report "Receivers ready at " & time'image(now);

        loop
            wait for 2 us;
            Done_v := ClkCorCnt(0) >= ClkCors_c and ClkCorCnt(1) >= ClkCors_c;

            for e in 0 to 1 loop

                for l in 0 to Lanes_c-1 loop
                    if Checked(e, l) < Words_c then
                        Done_v := false;
                    end if;
                end loop;

            end loop;

            exit when Done_v or now > Timeout_c;
        end loop;

        for e in 0 to 1 loop

            for l in 0 to Lanes_c-1 loop
                report "End " & integer'image(e) & " lane " & integer'image(l) & ": " &
                       integer'image(Checked(e, l)) & " data words checked, " & integer'image(Errors(e, l)) &
                       " errors";
                if Checked(e, l) < Words_c or Errors(e, l) /= 0 then
                    report "FAIL: data words" severity error;
                    Fail_v := true;
                end if;
            end loop;

            report "End " & integer'image(e) & ": " & integer'image(ClkCorCnt(e)) & " clock corrections, " &
                   integer'image(BufErrCnt(e)) & " buffer errors";
            if ClkCorCnt(e) < ClkCors_c or BufErrCnt(e) /= 0 then
                report "FAIL: clock correction" severity error;
                Fail_v := true;
            end if;
        end loop;

        -- Far-end serial loopback at B: A receives its own words
        if not FarLoopback_g then
            if not Fail_v then
                report "Simulation done at " & time'image(now);
            end if;
            finish;
        end if;
        CheckEn <= (others => '0');
        FarLb   <= (others => '1');
        wait for 30 us;
        Base_v  := Checked;
        Err_v   := Errors;
        CheckEn <= ('1', '0');

        loop
            wait for 2 us;
            Done_v := true;

            for l in 0 to Lanes_c-1 loop
                if Checked(0, l) < Base_v(0, l) + Words_c then
                    Done_v := false;
                end if;
            end loop;

            exit when Done_v or now > Timeout_c + 200 us;
        end loop;

        for l in 0 to Lanes_c-1 loop
            report "End 0 lane " & integer'image(l) & " with far-end serial loopback at B: " &
                   integer'image(Checked(0, l) - Base_v(0, l)) & " data words checked, " &
                   integer'image(Errors(0, l) - Err_v(0, l)) & " errors";
            if Checked(0, l) < Base_v(0, l) + Words_c or Errors(0, l) /= Err_v(0, l) then
                report "FAIL: far-end serial loopback" severity error;
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

        i_dut : entity work.ofb_pa_gty
            generic map (
                NumLanes_g => Lanes_c
            )
            port map (
                FreeRunClk            => FreeRunClk,
                Rst                   => Rst,
                RefClk                => RefClk(e),
                LaneClk               => LaneClk(e),
                LaneRst               => open,
                Gt_TxP                => TxP(e),
                Gt_TxN                => TxN(e),
                Gt_RxP                => TxP(1 - e),
                Gt_RxN                => TxN(1 - e),
                PhyTx_Data            => TxData(e),
                PhyTx_K               => TxK(e),
                PhyRx_Data            => RxData(e),
                PhyRx_K               => RxK(e),
                PhyRx_CodeErr         => RxCodeErr(e),
                PhyRx_DispErr         => RxDispErr(e),
                PhyRx_Valid           => RxValid(e),
                Phy_TxEnable          => (others => '1'),
                Phy_RxEnable          => (others => '1'),
                Phy_CdrEnable         => (others => '1'),
                Phy_RxInvert          => (others => '0'),
                Phy_NoSignal          => open,
                Stat_TxReady          => TxReady(e),
                Stat_RxReady          => RxReady(e),
                Stat_Aligned          => Aligned(e),
                Stat_RxBufErr         => RxBufErr(e),
                Stat_ClkCor           => ClkCor(e),
                Phy_SerialFarLoopback => FarLbOf(e)
            );

        -------------------------------------------------------------------------------------------
        -- Transmitter: SKIP word every 16 words, IDLE word every 8 words, counting data words
        -------------------------------------------------------------------------------------------
        p_tx : process (LaneClk(e)) is
            variable Cnt_v : natural := 0;
        begin
            if rising_edge(LaneClk(e)) then
                Cnt_v := Cnt_v + 1;

                for l in 0 to Lanes_c-1 loop
                    if Cnt_v mod 16 = 0 then
                        TxData(e)(32*l+31 downto 32*l) <= WordSkip_c;
                        TxK(e)(4*l+3 downto 4*l)       <= "0001";
                    elsif Cnt_v mod 8 = 0 then
                        TxData(e)(32*l+31 downto 32*l) <= WordIdle_c;
                        TxK(e)(4*l+3 downto 4*l)       <= "0001";
                    else
                        TxData(e)(32*l+31 downto 32*l) <= std_logic_vector(to_unsigned(l, 8)) &
                                                          std_logic_vector(to_unsigned(Cnt_v mod 2**24, 24));
                        TxK(e)(4*l+3 downto 4*l)       <= "0000";
                    end if;
                end loop;

            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Clock corrections and buffer errors of the receivers
        -------------------------------------------------------------------------------------------
        p_stat : process (LaneClk(e)) is
        begin
            if rising_edge(LaneClk(e)) then

                for l in 0 to Lanes_c-1 loop
                    if ClkCor(e)(l) = '1' then
                        ClkCorCnt(e) <= ClkCorCnt(e) + 1;
                    end if;
                    if RxBufErr(e)(l) = '1' and RxReady(e) = '1' then
                        BufErrCnt(e) <= BufErrCnt(e) + 1;
                    end if;
                end loop;

            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Receivers: data words count up with gaps of at most one word
        -------------------------------------------------------------------------------------------
        g_rx : for l in 0 to Lanes_c-1 generate

            p_rx : process (LaneClk(e)) is
                variable Last_v : integer := -1;
                variable Word_v : std_logic_vector(31 downto 0);
                variable K_v    : std_logic_vector(3 downto 0);
                variable Val_v  : integer;
            begin
                if rising_edge(LaneClk(e)) then
                    Word_v := RxData(e)(32*l+31 downto 32*l);
                    K_v    := RxK(e)(4*l+3 downto 4*l);
                    if CheckEn(e) = '0' then
                        Last_v := -1;
                    elsif RxValid(e)(l) = '1' and Aligned(e)(l) = '1' then
                        if RxCodeErr(e)(4*l+3 downto 4*l) /= "0000" or RxDispErr(e)(4*l+3 downto 4*l) /= "0000" then
                            if Last_v >= 0 then
                                Errors(e, l) <= Errors(e, l) + 1;
                            end if;
                        elsif K_v = "0000" then
                            Val_v := to_integer(unsigned(Word_v(23 downto 0)));
                            if Last_v >= 0 then
                                if Word_v(31 downto 24) /= std_logic_vector(to_unsigned(l, 8)) or
                                   Val_v <= Last_v or Val_v > Last_v + 2 then
                                    Errors(e, l) <= Errors(e, l) + 1;
                                    report "End " & integer'image(e) & " lane " & integer'image(l) & ": word " &
                                           integer'image(Val_v) & " after " & integer'image(Last_v) severity warning;
                                end if;
                                Checked(e, l) <= Checked(e, l) + 1;
                            end if;
                            Last_v := Val_v;
                        elsif K_v /= "0001" or (Word_v /= WordIdle_c and Word_v /= WordSkip_c) then
                            if Last_v >= 0 then
                                Errors(e, l) <= Errors(e, l) + 1;
                            end if;
                        end if;
                    end if;
                end if;
            end process;

        end generate;

    end generate;

end architecture;
