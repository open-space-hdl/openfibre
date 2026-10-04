---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Data Link layer of OpenFibre (ECSS-E-ST-50-11C clause 5.7): virtual channels with flow control,
-- broadcast messages, framing, error recovery and link reset. This issue implements one lane
-- (rows of one word) and round-robin medium access.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl is
    generic (
        NumVc_g          : positive range 1 to 32 := 8;
        NumLanes_g       : positive range 1 to 4  := 1;
        VcOutDepth_g     : positive               := 128;
        VcInDepth_g      : positive               := 256;
        BcOutDepth_g     : positive               := 4;
        BcInDepth_g      : positive               := 4;
        FrameBufDepth_g  : positive               := 128;
        ErbWords_g       : positive               := 512;
        ErbDataItems_g   : positive               := 32;
        ErbFctItems_g    : positive               := 16;
        ErbBcItems_g     : positive               := 4;
        CreditWidth_g    : positive               := 12
    );
    port (
        -- Clocks and resets
        Clk                   : in    std_logic;
        Rst                   : in    std_logic;
        UserClk               : in    std_logic;
        UserRst               : in    std_logic;
        -- Virtual channels (UserClk)
        TxVc_Data             : in    std_logic_vector(32*NumVc_g-1 downto 0);
        TxVc_K                : in    std_logic_vector(4*NumVc_g-1 downto 0);
        TxVc_Valid            : in    std_logic_vector(NumVc_g-1 downto 0);
        TxVc_Ready            : out   std_logic_vector(NumVc_g-1 downto 0);
        RxVc_Data             : out   std_logic_vector(32*NumVc_g-1 downto 0);
        RxVc_K                : out   std_logic_vector(4*NumVc_g-1 downto 0);
        RxVc_Valid            : out   std_logic_vector(NumVc_g-1 downto 0);
        RxVc_Ready            : in    std_logic_vector(NumVc_g-1 downto 0);
        -- Broadcast messages (UserClk)
        TxBc_Data             : in    std_logic_vector(63 downto 0);
        TxBc_Channel          : in    Char_t;
        TxBc_Type             : in    Char_t;
        TxBc_Delayed          : in    std_logic                     := '0';
        TxBc_Valid            : in    std_logic;
        TxBc_Ready            : out   std_logic;
        RxBc_Data             : out   std_logic_vector(63 downto 0);
        RxBc_Channel          : out   Char_t;
        RxBc_Type             : out   Char_t;
        RxBc_Delayed          : out   std_logic;
        RxBc_Late             : out   std_logic;
        RxBc_Valid            : out   std_logic;
        RxBc_Ready            : in    std_logic                     := '1';
        -- Rows to and from the Multi-Lane layer
        TxRow_Data            : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        TxRow_K               : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        TxRow_Mask            : out   std_logic_vector(NumLanes_g-1 downto 0);
        TxRow_Replicate       : out   std_logic;
        TxRow_Valid           : out   std_logic;
        TxRow_Ready           : in    std_logic;
        RxRow_Data            : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        RxRow_K               : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        RxRow_Mask            : in    std_logic_vector(NumLanes_g-1 downto 0);
        RxRow_CrcErr          : in    std_logic;
        RxRow_Valid           : in    std_logic;
        -- Multi-Lane layer control
        Ml_LinkReset          : out   std_logic;
        Ml_LaneReset          : out   std_logic;
        Ml_NearCapability     : out   Char_t;
        Ml_FarCapability      : in    Char_t;
        Ml_FarCapabilityValid : in    std_logic;
        Ml_FarCapabilityIdle  : in    std_logic;
        Ml_LaneActive         : in    std_logic;
        -- Configuration
        Cfg_DataScrambled     : in    std_logic                     := '1';
        Cfg_LinkReset         : in    std_logic                     := '0';
        Cfg_InterfaceReset    : in    std_logic                     := '0';
        Cfg_BcInterval        : in    std_logic_vector(15 downto 0) := x"0028";
        -- Status (Ev_*: one-cycle events)
        Stat_HasCredit        : out   std_logic_vector(NumVc_g-1 downto 0);
        Ev_CreditOverflow     : out   std_logic_vector(NumVc_g-1 downto 0);
        Ev_InputOverflow      : out   std_logic_vector(NumVc_g-1 downto 0);
        Ev_Crc16Err           : out   std_logic;
        Ev_Crc8Err            : out   std_logic;
        Ev_FrameErr           : out   std_logic;
        Ev_SeqErr             : out   std_logic;
        Ev_Retry              : out   std_logic;
        Ev_ProtocolError      : out   std_logic;
        Ev_FarEndLinkReset    : out   std_logic;
        Ev_BcDiscard          : out   std_logic;
        Ctrl_ConfigReset      : out   std_logic;
        Stat_ErbEmpty         : out   std_logic;
        Stat_LinkResetState   : out   std_logic_vector(1 downto 0);
        Stat_RxErrState       : out   std_logic_vector(1 downto 0);
        Stat_WordIdState      : out   std_logic_vector(2 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl is

    constant FreeWidth_c : positive := log2ceil(ErbWords_g + 1);

    -- Link reset
    signal LinkReset  : std_logic;
    signal LaneReset  : std_logic;
    signal ResetFlag  : std_logic;
    signal ErrLinkRst : std_logic;
    signal ProtErr    : std_logic;

    -- Output VC buffers
    signal SegReady   : std_logic_vector(NumVc_g-1 downto 0);
    signal SegWords   : std_logic_vector(7*NumVc_g-1 downto 0);
    signal VcRdData   : std_logic_vector(32*NumVc_g-1 downto 0);
    signal VcRdK      : std_logic_vector(4*NumVc_g-1 downto 0);
    signal VcRdValid  : std_logic_vector(NumVc_g-1 downto 0);
    signal VcRdReady  : std_logic_vector(NumVc_g-1 downto 0);
    signal VcEmpty    : std_logic_vector(NumVc_g-1 downto 0);
    signal FctRxVc    : std_logic_vector(4 downto 0);
    signal FctRxMult  : std_logic_vector(2 downto 0);
    signal FctRxValid : std_logic;

    -- Broadcast output buffer
    signal BcData    : std_logic_vector(63 downto 0);
    signal BcChannel : Char_t;
    signal BcType    : Char_t;
    signal BcDelayed : std_logic;
    signal BcLate    : std_logic;
    signal BcValid   : std_logic;
    signal BcReady   : std_logic;
    signal BcCredit  : std_logic;

    -- Input VC buffers
    signal FctReq      : std_logic_vector(NumVc_g-1 downto 0);
    signal FctAck      : std_logic_vector(NumVc_g-1 downto 0);
    signal VcWrData    : Word_t;
    signal VcWrK       : WordK_t;
    signal VcWrValid   : std_logic_vector(NumVc_g-1 downto 0);
    signal VcWrReady   : std_logic_vector(NumVc_g-1 downto 0);
    signal VcOverflow  : std_logic_vector(NumVc_g-1 downto 0);
    signal BufOverflow : std_logic;

    -- Error recovery buffer
    signal WrDataData   : Word_t;
    signal WrDataK      : WordK_t;
    signal WrDataValid  : std_logic;
    signal WrDataCommit : std_logic;
    signal WrDataVc     : std_logic_vector(4 downto 0);
    signal WrFctValid   : std_logic;
    signal WrFctVc      : std_logic_vector(4 downto 0);
    signal WrFctMult    : std_logic_vector(2 downto 0);
    signal WrBcValid    : std_logic;
    signal WrBcData     : std_logic_vector(63 downto 0);
    signal WrBcChannel  : Char_t;
    signal WrBcType     : Char_t;
    signal WrBcDelayed  : std_logic;
    signal WrBcLate     : std_logic;
    signal FreeWords    : std_logic_vector(FreeWidth_c-1 downto 0);
    signal DataItemFree : std_logic;
    signal FctItemFree  : std_logic;
    signal BcItemFree   : std_logic;
    signal SndBcValid   : std_logic;
    signal SndBcData    : std_logic_vector(63 downto 0);
    signal SndBcChannel : Char_t;
    signal SndBcType    : Char_t;
    signal SndBcDelayed : std_logic;
    signal SndBcLate    : std_logic;
    signal SndFctValid  : std_logic;
    signal SndFctVc     : std_logic_vector(4 downto 0);
    signal SndFctMult   : std_logic_vector(2 downto 0);
    signal SndDataValid : std_logic;
    signal SndDataVc    : std_logic_vector(4 downto 0);
    signal SndDataLen   : std_logic_vector(6 downto 0);
    signal PayData      : Word_t;
    signal PayK         : WordK_t;
    signal PayValid     : std_logic;
    signal PayReady     : std_logic;
    signal SentValid    : std_logic;
    signal SentKind     : ErbKind_t;
    signal RetryReq     : std_logic;
    signal RetrySeq     : std_logic_vector(6 downto 0);
    signal RetryDone    : std_logic;
    signal ErbFull      : std_logic;
    signal ErbEmpty     : std_logic;

    -- Transmit framer
    signal TxIdle     : std_logic;
    signal TxPolarity : std_logic;
    signal WordSent   : std_logic;
    signal BcSent     : std_logic;

    -- Receive checks
    signal RxPolarity  : std_logic;
    signal RxSeqCount  : std_logic_vector(6 downto 0);
    signal FrData      : Word_t;
    signal FrK         : WordK_t;
    signal FrVc        : std_logic_vector(4 downto 0);
    signal FrValid     : std_logic;
    signal FrCommit    : std_logic;
    signal FrDrop      : std_logic;
    signal RxBcData    : std_logic_vector(63 downto 0);
    signal RxBcChannel : Char_t;
    signal RxBcType    : Char_t;
    signal RxBcDelayed : std_logic;
    signal RxBcLate    : std_logic;
    signal RxBcValid   : std_logic;
    signal AckNackSeq  : SeqNum_t;
    signal AckValid    : std_logic;
    signal NackValid   : std_logic;
    signal AckReq      : std_logic;
    signal NackReq     : std_logic;
    signal SeqErrSame  : std_logic;
    signal Crc16Err    : std_logic;
    signal Crc8Err     : std_logic;
    signal RxErr       : std_logic;
    signal RxError     : std_logic;

begin

    assert NumLanes_g = 1
        report "ofb_dl: only NumLanes_g = 1 is implemented"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Link reset (DC-1)
    -----------------------------------------------------------------------------------------------
    ErrLinkRst <= ProtErr or BufOverflow or (or VcOverflow);

    i_link_reset : entity work.ofb_dl_link_reset
        port map (
            Clk                   => Clk,
            Rst                   => Rst,
            Cfg_InterfaceReset    => Cfg_InterfaceReset,
            Cfg_LinkReset         => Cfg_LinkReset,
            Err_LinkReset         => ErrLinkRst,
            Ml_FarCapability      => Ml_FarCapability,
            Ml_FarCapabilityValid => Ml_FarCapabilityValid,
            Ml_FarCapabilityIdle  => Ml_FarCapabilityIdle,
            Ctrl_LinkReset        => LinkReset,
            Ctrl_LaneReset        => LaneReset,
            Ctrl_ConfigReset      => Ctrl_ConfigReset,
            Ctrl_LinkResetFlag    => ResetFlag,
            Ev_FarEndLinkReset    => Ev_FarEndLinkReset,
            Stat_State            => Stat_LinkResetState
        );

    Ml_LinkReset      <= LinkReset;
    Ml_LaneReset      <= LaneReset;
    Ml_NearCapability <= "00000" & Cfg_DataScrambled & '0' & ResetFlag;

    -----------------------------------------------------------------------------------------------
    -- Output VC buffers (DT-1, DT-2)
    -----------------------------------------------------------------------------------------------
    g_vc_out : for i in 0 to NumVc_g-1 generate
        signal FctValid : std_logic;
    begin

        FctValid <= '1' when FctRxValid = '1' and unsigned(FctRxVc) = i else '0';

        i_vc_out : entity work.ofb_dl_vc_out
            generic map (
                Depth_g       => VcOutDepth_g,
                CreditWidth_g => CreditWidth_g
            )
            port map (
                UserClk           => UserClk,
                UserRst           => UserRst,
                In_Data           => TxVc_Data(32*i+31 downto 32*i),
                In_K              => TxVc_K(4*i+3 downto 4*i),
                In_Valid          => TxVc_Valid(i),
                In_Ready          => TxVc_Ready(i),
                Clk               => Clk,
                Rst               => Rst,
                Ctrl_LinkReset    => LinkReset,
                Fct_Valid         => FctValid,
                Fct_Mult          => FctRxMult,
                Seg_Ready         => SegReady(i),
                Seg_Words         => SegWords(7*i+6 downto 7*i),
                Rd_Data           => VcRdData(32*i+31 downto 32*i),
                Rd_K              => VcRdK(4*i+3 downto 4*i),
                Rd_Valid          => VcRdValid(i),
                Rd_Ready          => VcRdReady(i),
                Stat_HasCredit    => Stat_HasCredit(i),
                Stat_Empty        => VcEmpty(i),
                Ev_CreditOverflow => Ev_CreditOverflow(i)
            );

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Broadcast output buffer (DT-3)
    -----------------------------------------------------------------------------------------------
    i_bc_out : entity work.ofb_dl_bc_out
        generic map (
            Depth_g => BcOutDepth_g
        )
        port map (
            UserClk         => UserClk,
            UserRst         => UserRst,
            In_Data         => TxBc_Data,
            In_Channel      => TxBc_Channel,
            In_Type         => TxBc_Type,
            In_Delayed      => TxBc_Delayed,
            In_Valid        => TxBc_Valid,
            In_Ready        => TxBc_Ready,
            Clk             => Clk,
            Rst             => Rst,
            Ctrl_LinkReset  => LinkReset,
            Ctrl_LaneActive => Ml_LaneActive,
            Ctrl_Recovery   => RetryReq,
            Cfg_BcInterval  => Cfg_BcInterval,
            Ev_WordSent     => WordSent,
            Ev_BcSent       => BcSent,
            Out_Data        => BcData,
            Out_Channel     => BcChannel,
            Out_Type        => BcType,
            Out_Delayed     => BcDelayed,
            Out_Late        => BcLate,
            Out_Valid       => BcValid,
            Out_Ready       => BcReady,
            Bc_Credit       => BcCredit
        );

    -----------------------------------------------------------------------------------------------
    -- Admission (DT-4), error recovery buffer (DT-7), transmit framer (DT-5, DT-6, DT-8)
    -----------------------------------------------------------------------------------------------
    i_admit : entity work.ofb_dl_tx_admit
        generic map (
            NumVc_g     => NumVc_g,
            FreeWidth_g => FreeWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Ctrl_LinkReset => LinkReset,
            Cfg_FctMult    => "000",
            Seg_Ready      => SegReady,
            Seg_Words      => SegWords,
            VcRd_Data      => VcRdData,
            VcRd_K         => VcRdK,
            VcRd_Valid     => VcRdValid,
            VcRd_Ready     => VcRdReady,
            Bc_Data        => BcData,
            Bc_Channel     => BcChannel,
            Bc_Type        => BcType,
            Bc_Delayed     => BcDelayed,
            Bc_Late        => BcLate,
            Bc_Valid       => BcValid,
            Bc_Ready       => BcReady,
            Bc_Credit      => BcCredit,
            Fct_Req        => FctReq,
            Fct_Ack        => FctAck,
            WrData_Data    => WrDataData,
            WrData_K       => WrDataK,
            WrData_Valid   => WrDataValid,
            WrData_Commit  => WrDataCommit,
            WrData_Vc      => WrDataVc,
            WrFct_Valid    => WrFctValid,
            WrFct_Vc       => WrFctVc,
            WrFct_Mult     => WrFctMult,
            WrBc_Valid     => WrBcValid,
            WrBc_Data      => WrBcData,
            WrBc_Channel   => WrBcChannel,
            WrBc_Type      => WrBcType,
            WrBc_Delayed   => WrBcDelayed,
            WrBc_Late      => WrBcLate,
            Data_FreeWords => FreeWords,
            Data_ItemFree  => DataItemFree,
            Fct_ItemFree   => FctItemFree,
            Bc_ItemFree    => BcItemFree,
            Bc_Waiting     => SndBcValid
        );

    i_erb : entity work.ofb_dl_erb
        generic map (
            Words_g     => ErbWords_g,
            DataItems_g => ErbDataItems_g,
            FctItems_g  => ErbFctItems_g,
            BcItems_g   => ErbBcItems_g
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Ctrl_LinkReset   => LinkReset,
            WrData_Data      => WrDataData,
            WrData_K         => WrDataK,
            WrData_Valid     => WrDataValid,
            WrData_Commit    => WrDataCommit,
            WrData_Vc        => WrDataVc,
            WrFct_Valid      => WrFctValid,
            WrFct_Vc         => WrFctVc,
            WrFct_Mult       => WrFctMult,
            WrBc_Valid       => WrBcValid,
            WrBc_Data        => WrBcData,
            WrBc_Channel     => WrBcChannel,
            WrBc_Type        => WrBcType,
            WrBc_Delayed     => WrBcDelayed,
            WrBc_Late        => WrBcLate,
            Data_FreeWords   => FreeWords,
            Data_ItemFree    => DataItemFree,
            Fct_ItemFree     => FctItemFree,
            Bc_ItemFree      => BcItemFree,
            SndBc_Valid      => SndBcValid,
            SndBc_Data       => SndBcData,
            SndBc_Channel    => SndBcChannel,
            SndBc_Type       => SndBcType,
            SndBc_Delayed    => SndBcDelayed,
            SndBc_Late       => SndBcLate,
            SndFct_Valid     => SndFctValid,
            SndFct_Vc        => SndFctVc,
            SndFct_Mult      => SndFctMult,
            SndData_Valid    => SndDataValid,
            SndData_Vc       => SndDataVc,
            SndData_Len      => SndDataLen,
            Pay_Data         => PayData,
            Pay_K            => PayK,
            Pay_Valid        => PayValid,
            Pay_Ready        => PayReady,
            Sent_Valid       => SentValid,
            Sent_Kind        => SentKind,
            Ack_Valid        => AckValid,
            Nack_Valid       => NackValid,
            AckNack_Seq      => AckNackSeq,
            TxPolarity       => TxPolarity,
            Retry_Req        => RetryReq,
            Retry_Seq        => RetrySeq,
            Retry_Done       => RetryDone,
            Stat_Full        => ErbFull,
            Stat_Empty       => ErbEmpty,
            Ev_ProtocolError => ProtErr
        );

    TxIdle <= '1' when VcEmpty = (VcEmpty'range => '1') and FctReq = (FctReq'range => '0') and BcValid = '0' else '0';

    i_tx_frame : entity work.ofb_dl_tx_frame
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Ctrl_LinkReset  => LinkReset,
            Ctrl_TxIdle     => TxIdle,
            SndBc_Valid     => SndBcValid,
            SndBc_Data      => SndBcData,
            SndBc_Channel   => SndBcChannel,
            SndBc_Type      => SndBcType,
            SndBc_Delayed   => SndBcDelayed,
            SndBc_Late      => SndBcLate,
            SndFct_Valid    => SndFctValid,
            SndFct_Vc       => SndFctVc,
            SndFct_Mult     => SndFctMult,
            SndData_Valid   => SndDataValid,
            SndData_Vc      => SndDataVc,
            SndData_Len     => SndDataLen,
            Pay_Data        => PayData,
            Pay_K           => PayK,
            Pay_Valid       => PayValid,
            Pay_Ready       => PayReady,
            Sent_Valid      => SentValid,
            Sent_Kind       => SentKind,
            Retry_Req       => RetryReq,
            Retry_Seq       => RetrySeq,
            Retry_Done      => RetryDone,
            Erb_Full        => ErbFull,
            Erb_Empty       => ErbEmpty,
            Ev_AckReq       => AckReq,
            Ev_NackReq      => NackReq,
            RxSeqCount      => RxSeqCount,
            RxPolarity      => RxPolarity,
            Ev_RxError      => RxError,
            TxRow_Data      => TxRow_Data(31 downto 0),
            TxRow_K         => TxRow_K(3 downto 0),
            TxRow_Replicate => TxRow_Replicate,
            TxRow_Valid     => TxRow_Valid,
            TxRow_Ready     => TxRow_Ready,
            TxPolarity      => TxPolarity,
            Ev_WordSent     => WordSent,
            Ev_BcSent       => BcSent,
            Ev_Retry        => Ev_Retry
        );

    TxRow_Mask       <= (others => '1');
    Ev_ProtocolError <= ProtErr;
    Stat_ErbEmpty    <= ErbEmpty;

    -----------------------------------------------------------------------------------------------
    -- Receive checks (DR-1, DR-2, DR-4) and receive error state machine (DR-3)
    -----------------------------------------------------------------------------------------------
    i_rx_check : entity work.ofb_dl_rx_check
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Ctrl_LinkReset => LinkReset,
            In_Data        => RxRow_Data(31 downto 0),
            In_K           => RxRow_K(3 downto 0),
            In_CrcErr      => RxRow_CrcErr,
            In_Valid       => RxRow_Valid,
            RxPolarity     => RxPolarity,
            RxSeqCount     => RxSeqCount,
            Fr_Data        => FrData,
            Fr_K           => FrK,
            Fr_Vc          => FrVc,
            Fr_Valid       => FrValid,
            Fr_Commit      => FrCommit,
            Fr_Drop        => FrDrop,
            Bc_Data        => RxBcData,
            Bc_Channel     => RxBcChannel,
            Bc_Type        => RxBcType,
            Bc_Delayed     => RxBcDelayed,
            Bc_Late        => RxBcLate,
            Bc_Valid       => RxBcValid,
            Fct_Vc         => FctRxVc,
            Fct_Mult       => FctRxMult,
            Fct_Valid      => FctRxValid,
            AckNack_Seq    => AckNackSeq,
            Ack_Valid      => AckValid,
            Nack_Valid     => NackValid,
            Ev_AckReq      => AckReq,
            Ev_NackReq     => NackReq,
            Ev_SeqErrSame  => SeqErrSame,
            Ev_Crc16Err    => Crc16Err,
            Ev_Crc8Err     => Crc8Err,
            Ev_FrameErr    => Ev_FrameErr,
            Ev_SeqErr      => Ev_SeqErr,
            Ev_RxErr       => RxErr,
            Stat_State     => Stat_WordIdState
        );

    RxError     <= RxErr or Crc16Err or Crc8Err;
    Ev_Crc16Err <= Crc16Err;
    Ev_Crc8Err  <= Crc8Err;

    i_rx_err : entity work.ofb_dl_rx_err
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Ctrl_LinkReset => LinkReset,
            Ev_AckReq      => AckReq,
            Ev_NackReq     => NackReq,
            Ev_SeqErrSame  => SeqErrSame,
            RxPolarity     => RxPolarity,
            Stat_State     => Stat_RxErrState
        );

    -----------------------------------------------------------------------------------------------
    -- Frame buffer (DR-5), input VC buffers (DR-6), broadcast input buffer (DR-7)
    -----------------------------------------------------------------------------------------------
    i_rx_buf : entity work.ofb_dl_rx_buf
        generic map (
            NumVc_g => NumVc_g,
            Depth_g => FrameBufDepth_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Ctrl_LinkReset => LinkReset,
            Fr_Data        => FrData,
            Fr_K           => FrK,
            Fr_Vc          => FrVc,
            Fr_Valid       => FrValid,
            Fr_Commit      => FrCommit,
            Fr_Drop        => FrDrop,
            Vc_Data        => VcWrData,
            Vc_K           => VcWrK,
            Vc_Valid       => VcWrValid,
            Vc_Ready       => VcWrReady,
            Ev_VcOverflow  => VcOverflow,
            Ev_BufOverflow => BufOverflow
        );

    Ev_InputOverflow <= VcOverflow;

    g_vc_in : for i in 0 to NumVc_g-1 generate

        i_vc_in : entity work.ofb_dl_vc_in
            generic map (
                Depth_g => VcInDepth_g
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                Ctrl_LinkReset => LinkReset,
                In_Data        => VcWrData,
                In_K           => VcWrK,
                In_Valid       => VcWrValid(i),
                In_Ready       => VcWrReady(i),
                Fct_Req        => FctReq(i),
                Fct_Ack        => FctAck(i),
                UserClk        => UserClk,
                UserRst        => UserRst,
                Out_Data       => RxVc_Data(32*i+31 downto 32*i),
                Out_K          => RxVc_K(4*i+3 downto 4*i),
                Out_Valid      => RxVc_Valid(i),
                Out_Ready      => RxVc_Ready(i)
            );

    end generate;

    i_bc_in : entity work.ofb_dl_bc_in
        generic map (
            Depth_g => BcInDepth_g
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            In_Data     => RxBcData,
            In_Channel  => RxBcChannel,
            In_Type     => RxBcType,
            In_Delayed  => RxBcDelayed,
            In_Late     => RxBcLate,
            In_Valid    => RxBcValid,
            Ev_Discard  => Ev_BcDiscard,
            UserClk     => UserClk,
            UserRst     => UserRst,
            Out_Data    => RxBc_Data,
            Out_Channel => RxBc_Channel,
            Out_Type    => RxBc_Type,
            Out_Delayed => RxBc_Delayed,
            Out_Late    => RxBc_Late,
            Out_Valid   => RxBc_Valid,
            Out_Ready   => RxBc_Ready
        );

end architecture;
