---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receive checks of the Data Link layer (DR-1, DR-2, DR-4): data word identification state
-- machine (ECSS 5.7.8), CRC-8 and sequence checks, receive sequence counter and decoding of the
-- received frames and control words. One word per clock cycle, all outputs registered.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.6)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_rx_check is
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        -- Received words from the Multi-Lane layer
        In_Data        : in    Word_t;
        In_K           : in    WordK_t;
        In_CrcErr      : in    std_logic; -- With an EDF: CRC-16 error
        In_Valid       : in    std_logic;
        -- Receive Polarity Flag (DR-3) and Receive Sequence Counter
        RxPolarity     : in    std_logic;
        RxSeqCount     : out   std_logic_vector(6 downto 0);
        -- Data frame words to the frame buffer (DR-5)
        Fr_Data        : out   Word_t;
        Fr_K           : out   WordK_t;
        Fr_Vc          : out   std_logic_vector(4 downto 0);
        Fr_Valid       : out   std_logic;
        Fr_Commit      : out   std_logic; -- The current data frame is accepted
        Fr_Drop        : out   std_logic; -- The current data frame is discarded
        -- Accepted broadcast messages (DR-7)
        Bc_Data        : out   std_logic_vector(63 downto 0);
        Bc_Channel     : out   Char_t;
        Bc_Type        : out   Char_t;
        Bc_Delayed     : out   std_logic;
        Bc_Late        : out   std_logic;
        Bc_Valid       : out   std_logic;
        -- Accepted FCTs (DT-2)
        Fct_Vc         : out   std_logic_vector(4 downto 0);
        Fct_Mult       : out   std_logic_vector(2 downto 0);
        Fct_Valid      : out   std_logic;
        -- ACK and NACK with a valid CRC (DT-7)
        AckNack_Seq    : out   SeqNum_t;
        Ack_Valid      : out   std_logic;
        Nack_Valid     : out   std_logic;
        -- Events to the receive error state machine (DR-3)
        Ev_AckReq      : out   std_logic;
        Ev_NackReq     : out   std_logic;
        Ev_SeqErrSame  : out   std_logic;
        -- Status events
        Ev_Crc16Err    : out   std_logic;
        Ev_Crc8Err     : out   std_logic;
        Ev_FrameErr    : out   std_logic;
        Ev_SeqErr      : out   std_logic;
        Ev_RxErr       : out   std_logic;
        -- State of the data word identification state machine: 0 RxNothing, 1 RxDataFrame,
        -- 2 RxBroadcastFrame, 3 RxBroadcast&DataFrame, 4 RxIdleFrame
        Stat_State     : out   std_logic_vector(2 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_rx_check is

    type DwiFsm_t is (Nothing_s, Data_s, Bcst_s, BcstData_s, Idle_s);

    type TwoProcess_r is record
        State      : DwiFsm_t;
        Cnt        : natural range 0 to MaxFrameWords_c;
        BcCnt      : natural range 0 to BcDataWords_c;
        Vc         : std_logic_vector(4 downto 0);
        RxSeq      : SeqCount_t;
        BcCrc      : Char_t;
        BcChannel  : Char_t;
        BcType     : Char_t;
        BcWord     : std_logic_vector(63 downto 0);
        -- Outputs
        FrData     : Word_t;
        FrK        : WordK_t;
        FrValid    : std_logic;
        FrCommit   : std_logic;
        FrDrop     : std_logic;
        BcStatus   : std_logic_vector(1 downto 0);
        BcValid    : std_logic;
        FctVc      : std_logic_vector(4 downto 0);
        FctMult    : std_logic_vector(2 downto 0);
        FctValid   : std_logic;
        AckNackSeq : SeqNum_t;
        AckValid   : std_logic;
        NackValid  : std_logic;
        AckReq     : std_logic;
        NackReq    : std_logic;
        SeqSame    : std_logic;
        Crc16Err   : std_logic;
        Crc8Err    : std_logic;
        FrameErr   : std_logic;
        SeqErr     : std_logic;
        RxErr      : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Kind_v    : DlKind_t;
        variable Seq_v     : SeqNum_t;
        variable Crc8Ok_v  : boolean;
        variable SeqOk_v   : boolean;
        variable InFrame_v : boolean;
        variable CrcErr_v  : boolean;
        variable SeqErr_v  : boolean;
        variable FrmErr_v  : boolean;
        variable Next_v    : DwiFsm_t;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.FrValid   := '0';
        v.FrCommit  := '0';
        v.FrDrop    := '0';
        v.BcValid   := '0';
        v.FctValid  := '0';
        v.AckValid  := '0';
        v.NackValid := '0';
        v.AckReq    := '0';
        v.NackReq   := '0';
        v.SeqSame   := '0';
        v.Crc16Err  := '0';
        v.Crc8Err   := '0';
        v.FrameErr  := '0';
        v.SeqErr    := '0';
        v.RxErr     := '0';

        Kind_v    := dlWordKind(In_Data, In_K);
        InFrame_v := r.State = Data_s or r.State = Bcst_s or r.State = BcstData_s;
        CrcErr_v  := false;
        SeqErr_v  := false;
        FrmErr_v  := false;
        Next_v    := r.State;

        -- Sequence number field: character 1 of the EDF, character 2 of all other words
        if Kind_v = KindEdf then
            Seq_v := In_Data(15 downto 8);
        else
            Seq_v := In_Data(23 downto 16);
        end if;

        -- CRC-8 of the single control words, sequence check against the counter (SIF, FULL) or the
        -- counter plus one (EDF, EBF, FCT)
        Crc8Ok_v := crc8Word3(In_Data) = In_Data(31 downto 24);
        if Kind_v = KindSif or Kind_v = KindFull then
            SeqOk_v := seqCount(Seq_v) = r.RxSeq and Seq_v(SeqPolarity_c) = RxPolarity;
        else
            SeqOk_v := seqCount(Seq_v) = r.RxSeq + 1 and Seq_v(SeqPolarity_c) = RxPolarity;
        end if;

        if In_Valid = '1' then

            case Kind_v is

                when KindRetry =>
                    Next_v := Nothing_s;

                when KindRxErr =>
                    v.RxErr := '1';
                    Next_v  := Nothing_s;
                    if InFrame_v then
                        v.NackReq := '1';
                    end if;

                when KindData =>

                    case r.State is
                        when Data_s =>
                            if r.Cnt = MaxFrameWords_c then
                                FrmErr_v := true;
                            else
                                v.Cnt     := r.Cnt + 1;
                                v.FrData  := In_Data;
                                v.FrK     := In_K;
                                v.FrValid := '1';
                            end if;
                        when Bcst_s | BcstData_s =>
                            if r.BcCnt = BcDataWords_c then
                                FrmErr_v := true;
                            else
                                if r.BcCnt = 0 then
                                    v.BcWord(31 downto 0) := In_Data;
                                else
                                    v.BcWord(63 downto 32) := In_Data;
                                end if;
                                v.BcCnt := r.BcCnt + 1;
                                v.BcCrc := crc8Chars(r.BcCrc, In_Data, 4);
                            end if;
                        when Idle_s =>
                            if r.Cnt = MaxFrameWords_c then
                                FrmErr_v := true;
                            else
                                v.Cnt := r.Cnt + 1;
                            end if;
                        when others =>
                            null;
                    end case;

                when KindSdf =>
                    if r.State = Nothing_s or r.State = Idle_s then
                        Next_v := Data_s;
                        v.Cnt  := 0;
                        v.Vc   := In_Data(20 downto 16);
                    else
                        FrmErr_v := true;
                    end if;

                when KindSbf =>
                    if r.State = Nothing_s or r.State = Idle_s or r.State = Data_s then
                        if r.State = Data_s then
                            Next_v := BcstData_s;
                        else
                            Next_v := Bcst_s;
                        end if;
                        v.BcCnt     := 0;
                        v.BcCrc     := crc8Chars(Crc8Seed_c, In_Data, 4);
                        v.BcChannel := In_Data(23 downto 16);
                        v.BcType    := In_Data(31 downto 24);
                    else
                        FrmErr_v := true;
                    end if;

                when KindEdf =>

                    case r.State is
                        when Nothing_s =>
                            -- Discarded in RxNothing
                            null;
                        when Data_s =>
                            if In_CrcErr = '1' then
                                CrcErr_v   := true;
                                v.Crc16Err := '1';
                            elsif not SeqOk_v then
                                SeqErr_v := true;
                            else
                                v.FrCommit := '1';
                                v.RxSeq    := r.RxSeq + 1;
                                v.AckReq   := '1';
                                Next_v     := Nothing_s;
                            end if;
                        when others =>
                            FrmErr_v := true;
                    end case;

                when KindEbf =>

                    case r.State is
                        when Nothing_s =>
                            null;
                        when Bcst_s | BcstData_s =>
                            if crc8Chars(r.BcCrc, In_Data, 3) /= In_Data(31 downto 24) then
                                CrcErr_v  := true;
                                v.Crc8Err := '1';
                            elsif not SeqOk_v then
                                SeqErr_v := true;
                            elsif r.BcCnt = BcDataWords_c then
                                v.BcValid  := '1';
                                v.BcStatus := In_Data(9 downto 8);
                                v.RxSeq    := r.RxSeq + 1;
                                v.AckReq   := '1';
                                if r.State = BcstData_s then
                                    Next_v := Data_s;
                                else
                                    Next_v := Nothing_s;
                                end if;
                            else
                                FrmErr_v := true;
                            end if;
                        when others =>
                            FrmErr_v := true;
                    end case;

                when KindSif =>
                    if not Crc8Ok_v then
                        CrcErr_v  := true;
                        v.Crc8Err := '1';
                    elsif not SeqOk_v then
                        SeqErr_v := true;
                    elsif r.State = Nothing_s or r.State = Idle_s then
                        Next_v := Idle_s;
                        v.Cnt  := 0;
                    else
                        FrmErr_v := true;
                    end if;

                when KindFct =>
                    if not Crc8Ok_v then
                        CrcErr_v  := true;
                        v.Crc8Err := '1';
                    elsif not SeqOk_v then
                        SeqErr_v := true;
                    else
                        v.FctValid := '1';
                        v.FctVc    := In_Data(12 downto 8);
                        v.FctMult  := In_Data(15 downto 13);
                        v.RxSeq    := r.RxSeq + 1;
                        v.AckReq   := '1';
                    end if;

                when KindFull =>
                    if not Crc8Ok_v then
                        CrcErr_v  := true;
                        v.Crc8Err := '1';
                    elsif not SeqOk_v then
                        SeqErr_v := true;
                    else
                        v.AckReq := '1';
                    end if;

                when KindAck | KindNack =>
                    if not Crc8Ok_v then
                        CrcErr_v  := true;
                        v.Crc8Err := '1';
                    else
                        v.AckNackSeq := Seq_v;
                        if Kind_v = KindAck then
                            v.AckValid := '1';
                        else
                            v.NackValid := '1';
                        end if;
                    end if;

                when others =>
                    -- Unknown control words are ignored
                    null;
            end case;

            -- Error exits of the data word identification state machine
            if CrcErr_v then
                Next_v := Nothing_s;
                if InFrame_v then
                    v.NackReq := '1';
                end if;
            elsif SeqErr_v then
                Next_v    := Nothing_s;
                v.SeqErr  := '1';
                v.NackReq := '1';
                if Seq_v(SeqPolarity_c) = RxPolarity then
                    v.SeqSame := '1';
                end if;
            elsif FrmErr_v then
                Next_v     := Nothing_s;
                v.FrameErr := '1';
            end if;

            -- A data frame that ends without a valid EDF is discarded
            if (r.State = Data_s or r.State = BcstData_s) and Next_v /= Data_s and Next_v /= BcstData_s and
               v.FrCommit = '0' then
                v.FrDrop := '1';
            end if;

            v.State := Next_v;
        end if;

        -- Apply to record
        r_next <= v;

    end process;

    -- Outputs
    RxSeqCount    <= std_logic_vector(r.RxSeq);
    Fr_Data       <= r.FrData;
    Fr_K          <= r.FrK;
    Fr_Vc         <= r.Vc;
    Fr_Valid      <= r.FrValid;
    Fr_Commit     <= r.FrCommit;
    Fr_Drop       <= r.FrDrop;
    Bc_Data       <= r.BcWord;
    Bc_Channel    <= r.BcChannel;
    Bc_Type       <= r.BcType;
    Bc_Delayed    <= r.BcStatus(EbfDelayed_c);
    Bc_Late       <= r.BcStatus(EbfLate_c);
    Bc_Valid      <= r.BcValid;
    Fct_Vc        <= r.FctVc;
    Fct_Mult      <= r.FctMult;
    Fct_Valid     <= r.FctValid;
    AckNack_Seq   <= r.AckNackSeq;
    Ack_Valid     <= r.AckValid;
    Nack_Valid    <= r.NackValid;
    Ev_AckReq     <= r.AckReq;
    Ev_NackReq    <= r.NackReq;
    Ev_SeqErrSame <= r.SeqSame;
    Ev_Crc16Err   <= r.Crc16Err;
    Ev_Crc8Err    <= r.Crc8Err;
    Ev_FrameErr   <= r.FrameErr;
    Ev_SeqErr     <= r.SeqErr;
    Ev_RxErr      <= r.RxErr;

    with r.State select Stat_State <=
         "000" when Nothing_s,
         "001" when Data_s,
         "010" when Bcst_s,
         "011" when BcstData_s,
         "100" when others;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                r.State     <= Nothing_s;
                r.Cnt       <= 0;
                r.BcCnt     <= 0;
                r.RxSeq     <= (others => '0');
                r.FrValid   <= '0';
                r.FrCommit  <= '0';
                r.FrDrop    <= '0';
                r.BcValid   <= '0';
                r.FctValid  <= '0';
                r.AckValid  <= '0';
                r.NackValid <= '0';
                r.AckReq    <= '0';
                r.NackReq   <= '0';
                r.SeqSame   <= '0';
                r.Crc16Err  <= '0';
                r.Crc8Err   <= '0';
                r.FrameErr  <= '0';
                r.SeqErr    <= '0';
                r.RxErr     <= '0';
            end if;
        end if;
    end process;

end architecture;
