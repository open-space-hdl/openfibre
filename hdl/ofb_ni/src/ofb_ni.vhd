---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network interface of an OpenFibre node: AXI4-Stream ports of the virtual channels (NI-1) with the
-- framing check of the transmitted words, and of the broadcast messages (NI-3).
--
-- Documentation: hdl/ofb_ni/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ni is
    generic (
        NumVc_g : positive range 1 to 32 := 8
    );
    port (
        -- Control Ports (user clock)
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- User: words to send per VC (TUSER: K flag per character)
        S_Vc_TData    : in    std_logic_vector(32*NumVc_g-1 downto 0);
        S_Vc_TUser    : in    std_logic_vector(4*NumVc_g-1 downto 0);
        S_Vc_TValid   : in    std_logic_vector(NumVc_g-1 downto 0);
        S_Vc_TReady   : out   std_logic_vector(NumVc_g-1 downto 0);
        -- User: received words per VC
        M_Vc_TData    : out   std_logic_vector(32*NumVc_g-1 downto 0);
        M_Vc_TUser    : out   std_logic_vector(4*NumVc_g-1 downto 0);
        M_Vc_TValid   : out   std_logic_vector(NumVc_g-1 downto 0);
        M_Vc_TReady   : in    std_logic_vector(NumVc_g-1 downto 0);
        -- User: broadcast messages to send (TUSER: channel 7:0, B_TYPE 15:8, DELAYED 16)
        S_Bc_TData    : in    std_logic_vector(63 downto 0);
        S_Bc_TUser    : in    std_logic_vector(16 downto 0);
        S_Bc_TValid   : in    std_logic;
        S_Bc_TReady   : out   std_logic;
        -- User: received broadcast messages (TUSER: channel 7:0, B_TYPE 15:8, DELAYED 16, LATE 17)
        M_Bc_TData    : out   std_logic_vector(63 downto 0);
        M_Bc_TUser    : out   std_logic_vector(17 downto 0);
        M_Bc_TValid   : out   std_logic;
        M_Bc_TReady   : in    std_logic;
        -- User: SCHEDULE.request (time-slot number)
        S_Sched_Slot  : in    std_logic_vector(5 downto 0) := (others => '0');
        S_Sched_Valid : in    std_logic                    := '0';
        -- Data Link layer
        TxVc_Data     : out   std_logic_vector(32*NumVc_g-1 downto 0);
        TxVc_K        : out   std_logic_vector(4*NumVc_g-1 downto 0);
        TxVc_Valid    : out   std_logic_vector(NumVc_g-1 downto 0);
        TxVc_Ready    : in    std_logic_vector(NumVc_g-1 downto 0);
        RxVc_Data     : in    std_logic_vector(32*NumVc_g-1 downto 0);
        RxVc_K        : in    std_logic_vector(4*NumVc_g-1 downto 0);
        RxVc_Valid    : in    std_logic_vector(NumVc_g-1 downto 0);
        RxVc_Ready    : out   std_logic_vector(NumVc_g-1 downto 0);
        TxBc_Data     : out   std_logic_vector(63 downto 0);
        TxBc_Channel  : out   Char_t;
        TxBc_Type     : out   Char_t;
        TxBc_Delayed  : out   std_logic;
        TxBc_Valid    : out   std_logic;
        TxBc_Ready    : in    std_logic;
        RxBc_Data     : in    std_logic_vector(63 downto 0);
        RxBc_Channel  : in    Char_t;
        RxBc_Type     : in    Char_t;
        RxBc_Delayed  : in    std_logic;
        RxBc_Late     : in    std_logic;
        RxBc_Valid    : in    std_logic;
        RxBc_Ready    : out   std_logic;
        TxSched_Slot  : out   std_logic_vector(5 downto 0);
        TxSched_Valid : out   std_logic;
        -- Status
        Ev_FrameErr   : out   std_logic_vector(NumVc_g-1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_ni is

begin

    -- VC ports (NI-1)
    g_vc : for i in 0 to NumVc_g-1 generate

        i_vc : entity work.ofb_ni_vc
            port map (
                Clk         => Clk,
                Rst         => Rst,
                In_Data     => S_Vc_TData(32*i+31 downto 32*i),
                In_K        => S_Vc_TUser(4*i+3 downto 4*i),
                In_Valid    => S_Vc_TValid(i),
                In_Ready    => S_Vc_TReady(i),
                Out_Data    => TxVc_Data(32*i+31 downto 32*i),
                Out_K       => TxVc_K(4*i+3 downto 4*i),
                Out_Valid   => TxVc_Valid(i),
                Out_Ready   => TxVc_Ready(i),
                Ev_FrameErr => Ev_FrameErr(i)
            );

    end generate;

    M_Vc_TData  <= RxVc_Data;
    M_Vc_TUser  <= RxVc_K;
    M_Vc_TValid <= RxVc_Valid;
    RxVc_Ready  <= M_Vc_TReady;

    -- Broadcast port (NI-3)
    TxBc_Data    <= S_Bc_TData;
    TxBc_Channel <= S_Bc_TUser(7 downto 0);
    TxBc_Type    <= S_Bc_TUser(15 downto 8);
    TxBc_Delayed <= S_Bc_TUser(16);
    TxBc_Valid   <= S_Bc_TValid;
    S_Bc_TReady  <= TxBc_Ready;

    -- Schedule port (NI-4)
    TxSched_Slot  <= S_Sched_Slot;
    TxSched_Valid <= S_Sched_Valid;

    M_Bc_TData  <= RxBc_Data;
    M_Bc_TUser  <= RxBc_Late & RxBc_Delayed & RxBc_Type & RxBc_Channel;
    M_Bc_TValid <= RxBc_Valid;
    RxBc_Ready  <= M_Bc_TReady;

end architecture;
