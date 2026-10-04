---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6) for 1 to 4 lanes: lane manager,
-- row distributor, column codec per lane, lane alignment and row concentrator. With one lane it
-- is the Multi-Lane bypass.
--
-- Documentation: hdl/ofb_multilane/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_lane_pkg.all;
    use work.ofb_ml_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_multilane is
    generic (
        NumLanes_g          : positive range 1 to 4 := 1;
        ClkFrequency_g      : real                  := 156.25e6;
        SkipIntervalWords_g : positive              := 5000
    );
    port (
        -- Control Ports
        Clk                     : in    std_logic;
        Rst                     : in    std_logic;
        -- Transmit rows from the Data Link layer
        TxRow_Data              : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        TxRow_K                 : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        TxRow_Mask              : in    std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
        TxRow_Replicate         : in    std_logic                               := '0';
        TxRow_Valid             : in    std_logic;
        TxRow_Ready             : out   std_logic;
        -- Receive rows to the Data Link layer
        RxRow_Data              : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        RxRow_K                 : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        RxRow_Mask              : out   std_logic_vector(NumLanes_g-1 downto 0);
        RxRow_CrcErr            : out   std_logic;
        RxRow_Valid             : out   std_logic;
        -- Data Link layer control and status
        Dl_LinkReset            : in    std_logic                               := '0';
        Dl_LaneReset            : in    std_logic                               := '0';
        Dl_NearCapability       : in    Char_t;
        Dl_FarCapability        : out   Char_t;
        Dl_FarCapabilityValid   : out   std_logic;
        Dl_FarCapabilityIdle    : out   std_logic;
        Dl_LaneActive           : out   std_logic;
        -- Management parameters
        Cfg_TxEn                : in    std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
        Cfg_RxEn                : in    std_logic_vector(NumLanes_g-1 downto 0) := (others => '1');
        Cfg_MaxDataLanes        : in    std_logic_vector(2 downto 0)            := "000";
        Cfg_Bypass              : in    std_logic                               := '0';
        -- Lane layers: words
        LaneTx_Data             : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        LaneTx_K                : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        LaneTx_Valid            : out   std_logic_vector(NumLanes_g-1 downto 0);
        LaneTx_Ready            : in    std_logic_vector(NumLanes_g-1 downto 0);
        Lane_SkipReq            : out   std_logic;
        LaneRx_Data             : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        LaneRx_K                : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        LaneRx_Valid            : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Lane layers: control and state
        Lane_Reset              : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_TxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_RxOnly             : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_FarEndActive       : out   std_logic_vector(NumLanes_g-1 downto 0);
        Lane_NearCapability     : out   std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_State              : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        Lane_FarCapability      : in    std_logic_vector(8*NumLanes_g-1 downto 0);
        Lane_FarCapabilityValid : in    std_logic_vector(NumLanes_g-1 downto 0);
        -- Status
        Stat_DataSendingLanes   : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_DataReceivingLanes : out   std_logic_vector(NumLanes_g-1 downto 0);
        Stat_AlignState         : out   AlignState_t;
        Stat_Bypass             : out   std_logic;
        Ev_Misaligned           : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_multilane is

    -- Lane manager
    signal Bypass     : std_logic;
    signal ActLanes   : std_logic_vector(NumLanes_g-1 downto 0);
    signal TxLanes    : std_logic_vector(NumLanes_g-1 downto 0);
    signal DataLanes  : std_logic_vector(NumLanes_g-1 downto 0);
    signal HotLanes   : std_logic_vector(NumLanes_g-1 downto 0);
    signal RxLanes    : std_logic_vector(NumLanes_g-1 downto 0);
    signal NumTxLanes : std_logic_vector(3 downto 0);
    signal NumRxLanes : std_logic_vector(3 downto 0);
    signal Scramble   : std_logic_vector(NumLanes_g-1 downto 0);
    signal Unscramble : std_logic_vector(NumLanes_g-1 downto 0);
    signal FarAct     : std_logic_vector(15 downto 0);
    signal FarActV    : std_logic;

    -- Column codec
    signal EncData   : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal EncK      : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal EncValid  : std_logic_vector(NumLanes_g-1 downto 0);
    signal EncReady  : std_logic_vector(NumLanes_g-1 downto 0);
    signal EncFlush  : std_logic_vector(NumLanes_g-1 downto 0);
    signal DecData   : std_logic_vector(32*NumLanes_g-1 downto 0);
    signal DecK      : std_logic_vector(4*NumLanes_g-1 downto 0);
    signal DecCrcErr : std_logic_vector(NumLanes_g-1 downto 0);
    signal DecValid  : std_logic_vector(NumLanes_g-1 downto 0);

    -- Lane alignment
    signal AlignState : AlignState_t;
    signal RecvLanes  : std_logic_vector(NumLanes_g-1 downto 0);
    signal Lane0Act   : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Lane manager (ML-1)
    -----------------------------------------------------------------------------------------------
    i_lane_mgr : entity work.ofb_ml_lane_mgr
        generic map (
            NumLanes_g => NumLanes_g
        )
        port map (
            Clk                     => Clk,
            Rst                     => Rst,
            Cfg_TxEn                => Cfg_TxEn,
            Cfg_RxEn                => Cfg_RxEn,
            Cfg_MaxDataLanes        => Cfg_MaxDataLanes,
            Cfg_Bypass              => Cfg_Bypass,
            Dl_LaneReset            => Dl_LaneReset,
            Dl_NearCapability       => Dl_NearCapability,
            Dl_FarCapability        => Dl_FarCapability,
            Dl_FarCapabilityValid   => Dl_FarCapabilityValid,
            Dl_FarCapabilityIdle    => Dl_FarCapabilityIdle,
            Dl_LaneActive           => Dl_LaneActive,
            Lane_Reset              => Lane_Reset,
            Lane_TxOnly             => Lane_TxOnly,
            Lane_RxOnly             => Lane_RxOnly,
            Lane_FarEndActive       => Lane_FarEndActive,
            Lane_NearCapability     => Lane_NearCapability,
            Lane_State              => Lane_State,
            Lane_FarCapability      => Lane_FarCapability,
            Lane_FarCapabilityValid => Lane_FarCapabilityValid,
            Al_FarAct               => FarAct,
            Al_FarActValid          => FarActV,
            Bypass                  => Bypass,
            ActLanes                => ActLanes,
            TxLanes                 => TxLanes,
            DataLanes               => DataLanes,
            HotLanes                => HotLanes,
            RxLanes                 => RxLanes,
            NumTxLanes              => NumTxLanes,
            NumRxLanes              => NumRxLanes,
            Enc_Scramble            => Scramble,
            Dec_Unscramble          => Unscramble
        );

    -----------------------------------------------------------------------------------------------
    -- Column encoders (ML-3) and decoders (ML-4), one per lane
    -----------------------------------------------------------------------------------------------
    g_lane : for i in 0 to NumLanes_g-1 generate

        i_col_enc : entity work.ofb_ml_col_enc
            port map (
                Clk          => Clk,
                Rst          => Rst,
                Cfg_Scramble => Scramble(i),
                Ctrl_Flush   => EncFlush(i),
                In_Data      => EncData(32*i+31 downto 32*i),
                In_K         => EncK(4*i+3 downto 4*i),
                In_Valid     => EncValid(i),
                In_Ready     => EncReady(i),
                Out_Data     => LaneTx_Data(32*i+31 downto 32*i),
                Out_K        => LaneTx_K(4*i+3 downto 4*i),
                Out_Valid    => LaneTx_Valid(i),
                Out_Ready    => LaneTx_Ready(i)
            );

        i_col_dec : entity work.ofb_ml_col_dec
            port map (
                Clk            => Clk,
                Rst            => Rst,
                Cfg_Unscramble => Unscramble(i),
                Ctrl_Flush     => Dl_LinkReset,
                In_Data        => LaneRx_Data(32*i+31 downto 32*i),
                In_K           => LaneRx_K(4*i+3 downto 4*i),
                In_Valid       => LaneRx_Valid(i),
                Out_Data       => DecData(32*i+31 downto 32*i),
                Out_K          => DecK(4*i+3 downto 4*i),
                Out_CrcErr     => DecCrcErr(i),
                Out_Valid      => DecValid(i)
            );

        -- Encoder flush: link reset; in the multi-lane case also while the lane does not transmit
        EncFlush(i) <= Dl_LinkReset or (not Bypass and not TxLanes(i));

    end generate;

    Lane0Act <= ActLanes(0);

    -----------------------------------------------------------------------------------------------
    -- One lane: Multi-Lane bypass (ML-2, ML-6)
    -----------------------------------------------------------------------------------------------
    g_single : if NumLanes_g = 1 generate

        EncData      <= TxRow_Data;
        EncK         <= TxRow_K;
        EncValid(0)  <= TxRow_Valid;
        TxRow_Ready  <= EncReady(0);
        Lane_SkipReq <= '0';

        -- Multi-Lane control words are not passed to the Data Link layer
        p_rx_row : process (all) is
            variable Kind_v : WordKind_t;
        begin
            Kind_v       := wordKind(DecData, DecK);
            RxRow_Data   <= DecData;
            RxRow_K      <= DecK;
            RxRow_Mask   <= (others => '1');
            RxRow_CrcErr <= DecCrcErr(0);
            if Kind_v = KindPad or Kind_v = KindMlCtrl then
                RxRow_Valid <= '0';
            else
                RxRow_Valid <= DecValid(0);
            end if;
        end process;

        AlignState    <= AlignBothEndsReady_c when Lane0Act = '1' else AlignNotReady_c;
        RecvLanes     <= ActLanes;
        Ev_Misaligned <= '0';
        FarAct        <= (others => '0');
        FarActV       <= '0';

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Several lanes: row distributor (ML-2), lane alignment (ML-5), row concentrator (ML-6)
    -----------------------------------------------------------------------------------------------
    g_multi : if NumLanes_g > 1 generate

        signal AlState  : AlignState_t;
        signal AlRecv   : std_logic_vector(NumLanes_g-1 downto 0);
        signal AlMis    : std_logic;
        signal RowData  : std_logic_vector(32*NumLanes_g-1 downto 0);
        signal RowK     : std_logic_vector(4*NumLanes_g-1 downto 0);
        signal RowCount : std_logic_vector(2 downto 0);
        signal RowIsDat : std_logic;
        signal RowCrc   : std_logic;
        signal RowValid : std_logic;

    begin

        i_tx : entity work.ofb_ml_tx
            generic map (
                NumLanes_g          => NumLanes_g,
                SkipIntervalWords_g => SkipIntervalWords_g
            )
            port map (
                Clk             => Clk,
                Rst             => Rst,
                Ctrl_Flush      => Dl_LinkReset,
                Bypass          => Bypass,
                AlignState      => AlState,
                ActLanes        => ActLanes,
                TxLanes         => TxLanes,
                DataLanes       => DataLanes,
                HotLanes        => HotLanes,
                NumTxLanes      => NumTxLanes,
                TxRow_Data      => TxRow_Data,
                TxRow_K         => TxRow_K,
                TxRow_Mask      => TxRow_Mask,
                TxRow_Replicate => TxRow_Replicate,
                TxRow_Valid     => TxRow_Valid,
                TxRow_Ready     => TxRow_Ready,
                Enc_Data        => EncData,
                Enc_K           => EncK,
                Enc_Valid       => EncValid,
                Enc_Ready       => EncReady,
                Lane_SkipReq    => Lane_SkipReq
            );

        i_align : entity work.ofb_ml_align
            generic map (
                NumLanes_g     => NumLanes_g,
                ClkFrequency_g => ClkFrequency_g
            )
            port map (
                Clk           => Clk,
                Rst           => Rst,
                Ctrl_Flush    => Dl_LinkReset,
                Bypass        => Bypass,
                ActLanes      => ActLanes,
                RxLanes       => RxLanes,
                NumRxLanes    => NumRxLanes,
                In_Data       => DecData,
                In_K          => DecK,
                In_CrcErr     => DecCrcErr,
                In_Valid      => DecValid,
                Row_Data      => RowData,
                Row_K         => RowK,
                Row_Count     => RowCount,
                Row_Data_Row  => RowIsDat,
                Row_CrcErr    => RowCrc,
                Row_Valid     => RowValid,
                FarAct        => FarAct,
                FarActValid   => FarActV,
                RecvLanes     => AlRecv,
                AlignState    => AlState,
                Ev_Misaligned => AlMis
            );

        i_rx : entity work.ofb_ml_rx
            generic map (
                NumLanes_g => NumLanes_g
            )
            port map (
                Clk          => Clk,
                Rst          => Rst,
                Ctrl_Flush   => Dl_LinkReset,
                In_Data      => RowData,
                In_K         => RowK,
                In_Count     => RowCount,
                In_DataRow   => RowIsDat,
                In_CrcErr    => RowCrc,
                In_Valid     => RowValid,
                RxRow_Data   => RxRow_Data,
                RxRow_K      => RxRow_K,
                RxRow_Mask   => RxRow_Mask,
                RxRow_CrcErr => RxRow_CrcErr,
                RxRow_Valid  => RxRow_Valid
            );

        -- Status: in bypass as with one lane
        p_status : process (all) is
        begin
            if Bypass = '1' then
                if Lane0Act = '1' then
                    AlignState <= AlignBothEndsReady_c;
                else
                    AlignState <= AlignNotReady_c;
                end if;
                RecvLanes    <= (others => '0');
                RecvLanes(0) <= Lane0Act;
            else
                AlignState <= AlState;
                RecvLanes  <= AlRecv;
            end if;
        end process;

        Ev_Misaligned <= AlMis;

    end generate;

    -- Status (ML-LM-16)
    p_stat_send : process (all) is
    begin
        Stat_DataSendingLanes <= DataLanes;
        if Bypass = '1' then
            Stat_DataSendingLanes    <= (others => '0');
            Stat_DataSendingLanes(0) <= Lane0Act;
        end if;
    end process;

    Stat_DataReceivingLanes <= RecvLanes;
    Stat_AlignState         <= AlignState;
    Stat_Bypass             <= Bypass;

end architecture;
