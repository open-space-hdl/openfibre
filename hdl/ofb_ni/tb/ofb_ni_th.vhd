---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Network interface testbench: ofb_ni with two VCs, per VC a driver of the
-- packets to send, a monitor of the rows to the Data Link layer, a driver of the received rows and
-- a monitor of the received packets, all with random handshakes, and the event counters.
--
-- Documentation: hdl/ofb_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ni_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni_th is
    generic (
        NumLanes_g : positive range 1 to 4 := 1
    );
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ni_th is

    constant B_c  : positive := 4 * NumLanes_g;
    constant Dw_c : positive := 32 * NumLanes_g;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    signal SVcData  : std_logic_vector(Dw_c*NiVc_c-1 downto 0) := (others => '0');
    signal SVcKeep  : std_logic_vector(B_c*NiVc_c-1 downto 0)  := (others => '0');
    signal SVcLast  : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal SVcUser  : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal SVcValid : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal SVcReady : std_logic_vector(NiVc_c-1 downto 0);
    signal MVcData  : std_logic_vector(Dw_c*NiVc_c-1 downto 0);
    signal MVcKeep  : std_logic_vector(B_c*NiVc_c-1 downto 0);
    signal MVcLast  : std_logic_vector(NiVc_c-1 downto 0);
    signal MVcUser  : std_logic_vector(NiVc_c-1 downto 0);
    signal MVcValid : std_logic_vector(NiVc_c-1 downto 0);
    signal MVcReady : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal TxData   : std_logic_vector(Dw_c*NiVc_c-1 downto 0);
    signal TxK      : std_logic_vector(B_c*NiVc_c-1 downto 0);
    signal TxValid  : std_logic_vector(NiVc_c-1 downto 0);
    signal TxReady  : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal RxData   : std_logic_vector(Dw_c*NiVc_c-1 downto 0) := (others => '0');
    signal RxK      : std_logic_vector(B_c*NiVc_c-1 downto 0)  := (others => '0');
    signal RxValid  : std_logic_vector(NiVc_c-1 downto 0)      := (others => '0');
    signal RxReady  : std_logic_vector(NiVc_c-1 downto 0);
    signal EvTxErr  : std_logic_vector(NiVc_c-1 downto 0);
    signal EvRxErr  : std_logic_vector(NiVc_c-1 downto 0);
    signal EvEmpty  : std_logic_vector(NiVc_c-1 downto 0);

begin

    ClkI <= not ClkI after 3 ns;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 60 ns;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.ofb_ni
        generic map (
            NumVc_g    => NiVc_c,
            NumLanes_g => NumLanes_g
        )
        port map (
            Clk           => ClkI,
            Rst           => RstI,
            S_Vc_TData    => SVcData,
            S_Vc_TKeep    => SVcKeep,
            S_Vc_TLast    => SVcLast,
            S_Vc_TUser    => SVcUser,
            S_Vc_TValid   => SVcValid,
            S_Vc_TReady   => SVcReady,
            M_Vc_TData    => MVcData,
            M_Vc_TKeep    => MVcKeep,
            M_Vc_TLast    => MVcLast,
            M_Vc_TUser    => MVcUser,
            M_Vc_TValid   => MVcValid,
            M_Vc_TReady   => MVcReady,
            S_Bc_TData    => (others => '0'),
            S_Bc_TUser    => (others => '0'),
            S_Bc_TValid   => '0',
            S_Bc_TReady   => open,
            M_Bc_TData    => open,
            M_Bc_TUser    => open,
            M_Bc_TValid   => open,
            M_Bc_TReady   => '1',
            S_Sched_Slot  => (others => '0'),
            S_Sched_Valid => '0',
            TxVc_Data     => TxData,
            TxVc_K        => TxK,
            TxVc_Valid    => TxValid,
            TxVc_Ready    => TxReady,
            RxVc_Data     => RxData,
            RxVc_K        => RxK,
            RxVc_Valid    => RxValid,
            RxVc_Ready    => RxReady,
            TxBc_Data     => open,
            TxBc_Channel  => open,
            TxBc_Type     => open,
            TxBc_Delayed  => open,
            TxBc_Valid    => open,
            TxBc_Ready    => '1',
            RxBc_Data     => (others => '0'),
            RxBc_Channel  => (others => '0'),
            RxBc_Type     => (others => '0'),
            RxBc_Delayed  => '0',
            RxBc_Late     => '0',
            RxBc_Valid    => '0',
            RxBc_Ready    => open,
            TxSched_Slot  => open,
            TxSched_Valid => open,
            Ev_FrameErr   => EvTxErr,
            Ev_RxFrameErr => EvRxErr,
            Ev_RxEmpty    => EvEmpty
        );

    g_vc : for v in 0 to NiVc_c-1 generate

        -------------------------------------------------------------------------------------------
        -- Driver of the packets to send (queue v)
        -------------------------------------------------------------------------------------------
        p_tx_drv : process (ClkI) is
            variable Seed1_v : positive := 11 + 7 * v;
            variable Seed2_v : positive := 101 + 3 * v;
            variable Rand_v  : real;
            variable Entry_v : NiEntry_t;
        begin
            if rising_edge(ClkI) then
                if SVcValid(v) = '0' or SVcReady(v) = '1' then
                    SVcValid(v) <= '0';
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    if RstI = '0' and NiQueue_v.count(v) > 0 and Rand_v * 100.0 < real(NiHs.TxValid) then
                        Entry_v                             := NiQueue_v.pop(v);
                        SVcData(Dw_c*(v+1)-1 downto Dw_c*v) <= Entry_v(Dw_c-1 downto 0);
                        SVcKeep(B_c*(v+1)-1 downto B_c*v)   <= Entry_v(128+B_c-1 downto 128);
                        SVcLast(v)                          <= Entry_v(144);
                        SVcUser(v)                          <= Entry_v(145);
                        SVcValid(v)                         <= '1';
                    end if;
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Monitor of the rows to the Data Link layer: every word compared (instance 1 + v)
        -------------------------------------------------------------------------------------------
        p_tx_mon : process (ClkI) is
            variable Seed1_v : positive := 21 + 5 * v;
            variable Seed2_v : positive := 211 + 13 * v;
            variable Rand_v  : real;
            variable Rows_v  : natural  := 0;
        begin
            if rising_edge(ClkI) then
                if TxValid(v) = '1' and TxReady(v) = '1' then

                    for w in 0 to NumLanes_g-1 loop
                        NiSb_v.check_received(1 + v, TxK(B_c*v+4*w+3 downto B_c*v+4*w) &
                                                     TxData(Dw_c*v+32*w+31 downto Dw_c*v+32*w));
                    end loop;

                    Rows_v        := Rows_v + 1;
                    NiTxRowCnt(v) <= Rows_v;
                end if;
                uniform(Seed1_v, Seed2_v, Rand_v);
                if Rand_v * 100.0 < real(NiHs.TxReady) then
                    TxReady(v) <= '1';
                else
                    TxReady(v) <= '0';
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Driver of the rows from the Data Link layer (queue NiVc_c + v)
        -------------------------------------------------------------------------------------------
        p_rx_drv : process (ClkI) is
            variable Seed1_v : positive := 31 + 3 * v;
            variable Seed2_v : positive := 307 + 17 * v;
            variable Rand_v  : real;
            variable Entry_v : NiEntry_t;
        begin
            if rising_edge(ClkI) then
                if RxValid(v) = '0' or RxReady(v) = '1' then
                    RxValid(v) <= '0';
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    if RstI = '0' and NiQueue_v.count(NiVc_c + v) > 0 and Rand_v * 100.0 < real(NiHs.RxValid) then
                        Entry_v                            := NiQueue_v.pop(NiVc_c + v);
                        RxData(Dw_c*(v+1)-1 downto Dw_c*v) <= Entry_v(Dw_c-1 downto 0);
                        RxK(B_c*(v+1)-1 downto B_c*v)      <= Entry_v(128+B_c-1 downto 128);
                        RxValid(v)                         <= '1';
                    end if;
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Monitor of the received packets: format of TKEEP, every byte compared with its position
        -- (last byte, EEP) in instance 1 + NiVc_c + v
        -------------------------------------------------------------------------------------------
        p_rx_mon : process (ClkI) is
            variable Seed1_v : positive := 41 + 7 * v;
            variable Seed2_v : positive := 401 + 19 * v;
            variable Rand_v  : real;
            variable Keep_v  : std_logic_vector(B_c-1 downto 0);
            variable Last_v  : std_logic;
            variable Eep_v   : std_logic;
            variable Beats_v : natural  := 0;
        begin
            if rising_edge(ClkI) then
                if MVcValid(v) = '1' and MVcReady(v) = '1' then
                    Keep_v := MVcKeep(B_c*(v+1)-1 downto B_c*v);
                    check_value(Keep_v(0), '1', error, "VC " & to_string(v) & ": byte 0 of a beat valid");

                    for c in 1 to B_c-1 loop
                        if Keep_v(c) = '1' and Keep_v(c-1) = '0' then
                            alert(error, "VC " & to_string(v) & ": TKEEP not contiguous " & to_string(Keep_v));
                        end if;
                    end loop;

                    if MVcLast(v) = '0' and Keep_v /= (Keep_v'range => '1') then
                        alert(error, "VC " & to_string(v) & ": TKEEP of a beat without TLAST " & to_string(Keep_v));
                    end if;

                    for c in 0 to B_c-1 loop
                        if Keep_v(c) = '1' then
                            Last_v := '0';
                            Eep_v  := '0';
                            if MVcLast(v) = '1' and (c = B_c-1 or Keep_v(minimum(c+1, B_c-1)) = '0') then
                                Last_v := '1';
                                Eep_v  := MVcUser(v);
                            end if;
                            NiSb_v.check_received(1 + NiVc_c + v, "00" & Eep_v & Last_v & x"000000" &
                                                                  MVcData(Dw_c*v+8*c+7 downto Dw_c*v+8*c));
                        end if;
                    end loop;

                    Beats_v        := Beats_v + 1;
                    NiRxBeatCnt(v) <= Beats_v;
                end if;
                uniform(Seed1_v, Seed2_v, Rand_v);
                if Rand_v * 100.0 < real(NiHs.RxReady) then
                    MVcReady(v) <= '1';
                else
                    MVcReady(v) <= '0';
                end if;
            end if;
        end process;

        -------------------------------------------------------------------------------------------
        -- Event counters
        -------------------------------------------------------------------------------------------
        p_events : process (ClkI) is
        begin
            if rising_edge(ClkI) then
                if EvTxErr(v) = '1' then
                    NiTxErrCnt(v) <= NiTxErrCnt(v) + 1;
                end if;
                if EvRxErr(v) = '1' then
                    NiRxErrCnt(v) <= NiRxErrCnt(v) + 1;
                end if;
                if EvEmpty(v) = '1' then
                    NiEmptyCnt(v) <= NiEmptyCnt(v) + 1;
                end if;
            end if;
        end process;

    end generate;

end architecture;
