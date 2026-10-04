---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Error recovery buffer of the Data Link layer (DT-7, ECSS 5.7.7.1, 5.7.7.2.3, 5.7.7.2.4): holds
-- data segments (rows of NumLanes_g words), FCTs and broadcast messages from their admission until
-- they are acknowledged,
-- presents the next item of every kind for sending, processes ACKs and NACKs and requests the
-- RETRY of an error recovery.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.4)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_erb is
    generic (
        NumLanes_g  : positive range 1 to 4 := 1;
        ClkFreq_g   : real                  := 200.0e6; -- Clock frequency for the scrubber
        Rows_g      : positive              := 512; -- Data rows (power of two)
        DataItems_g : positive              := 32;
        FctItems_g  : positive              := 16;
        BcItems_g   : positive              := 4
    );
    port (
        -- Control Ports
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        Ctrl_LinkReset   : in    std_logic;
        -- Admission of new items
        WrData_Data      : in    std_logic_vector(32*NumLanes_g-1 downto 0);
        WrData_K         : in    std_logic_vector(4*NumLanes_g-1 downto 0);
        WrData_Valid     : in    std_logic;
        WrData_Commit    : in    std_logic; -- The words written since the last commit form an item
        WrData_Vc        : in    std_logic_vector(4 downto 0);
        WrFct_Valid      : in    std_logic;
        WrFct_Vc         : in    std_logic_vector(4 downto 0);
        WrFct_Mult       : in    std_logic_vector(2 downto 0);
        WrBc_Valid       : in    std_logic;
        WrBc_Data        : in    std_logic_vector(63 downto 0);
        WrBc_Channel     : in    Char_t;
        WrBc_Type        : in    Char_t;
        WrBc_Delayed     : in    std_logic;
        WrBc_Late        : in    std_logic;
        -- Space
        Data_FreeRows    : out   std_logic_vector(log2ceil(Rows_g+1)-1 downto 0);
        Data_ItemFree    : out   std_logic;
        Fct_ItemFree     : out   std_logic;
        Bc_ItemFree      : out   std_logic;
        -- Next item of every kind to send
        SndBc_Valid      : out   std_logic;
        SndBc_Data       : out   std_logic_vector(63 downto 0);
        SndBc_Channel    : out   Char_t;
        SndBc_Type       : out   Char_t;
        SndBc_Delayed    : out   std_logic;
        SndBc_Late       : out   std_logic;
        SndFct_Valid     : out   std_logic;
        SndFct_Vc        : out   std_logic_vector(4 downto 0);
        SndFct_Mult      : out   std_logic_vector(2 downto 0);
        SndData_Valid    : out   std_logic;
        SndData_Vc       : out   std_logic_vector(4 downto 0);
        SndData_Len      : out   std_logic_vector(6 downto 0);
        Pay_Data         : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        Pay_K            : out   std_logic_vector(4*NumLanes_g-1 downto 0);
        Pay_Valid        : out   std_logic;
        Pay_Ready        : in    std_logic;
        -- The next item of a kind was sent with a sequence number
        Sent_Valid       : in    std_logic;
        Sent_Kind        : in    ErbKind_t;
        -- ACK and NACK with a valid CRC, Transmit Polarity Flag
        Ack_Valid        : in    std_logic;
        Nack_Valid       : in    std_logic;
        AckNack_Seq      : in    SeqNum_t;
        TxPolarity       : in    std_logic;
        -- Error recovery
        Retry_Req        : out   std_logic;
        Retry_Seq        : out   std_logic_vector(6 downto 0);
        Retry_Done       : in    std_logic;
        -- Status
        Stat_Full        : out   std_logic;
        Stat_Empty       : out   std_logic;
        Ev_ProtocolError : out   std_logic;
        -- EDAC (MG-3): injection into the next row written, events of the RAM and the FIFOs
        EccInj_Valid     : in    std_logic := '0';
        EccInj_Double    : in    std_logic := '0';
        Ev_EccSec        : out   std_logic;
        Ev_EccDed        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_erb is

    constant AddrWidth_c : positive := log2ceil(Rows_g);
    constant LogDepth_c  : positive := 128;
    constant N_c         : positive := NumLanes_g;
    constant Width_c     : positive := 36 * N_c;

    type VcArray_t is array (natural range <>) of std_logic_vector(4 downto 0);
    type LenArray_t is array (natural range <>) of natural range 0 to MaxFrameWords_c;
    type MultArray_t is array (natural range <>) of std_logic_vector(2 downto 0);
    type BcArray_t is array (natural range <>) of std_logic_vector(BcWidth_c-1 downto 0);
    type KindArray_t is array (natural range <>) of ErbKind_t;

    type EvFsm_t is (Idle_s, Delete_s, Retry_s);

    type TwoProcess_r is record
        -- Data items
        DVc        : VcArray_t(0 to DataItems_g-1);
        DLen       : LenArray_t(0 to DataItems_g-1);
        DHead      : natural range 0 to DataItems_g-1;
        DNum       : natural range 0 to DataItems_g;
        DSent      : natural range 0 to DataItems_g;
        -- Data rows
        WrPtr      : unsigned(AddrWidth_c-1 downto 0);
        WrCnt      : natural range 0 to MaxFrameWords_c;
        FreePtr    : unsigned(AddrWidth_c-1 downto 0);
        Used       : natural range 0 to Rows_g;
        -- Read-ahead of the data rows
        RdPtr      : unsigned(AddrWidth_c-1 downto 0);
        FetchOff   : natural range 0 to DataItems_g;
        FetchLeft  : natural range 0 to MaxFrameWords_c;
        InFlight   : natural range 0 to 7;
        Restart    : std_logic;
        RamRdValid : std_logic;
        -- FCT items
        FVc        : VcArray_t(0 to FctItems_g-1);
        FMult      : MultArray_t(0 to FctItems_g-1);
        FHead      : natural range 0 to FctItems_g-1;
        FNum       : natural range 0 to FctItems_g;
        FSent      : natural range 0 to FctItems_g;
        -- Broadcast items
        BMsg       : BcArray_t(0 to BcItems_g-1);
        BOnce      : std_logic_vector(0 to BcItems_g-1);
        BHead      : natural range 0 to BcItems_g-1;
        BNum       : natural range 0 to BcItems_g;
        BSent      : natural range 0 to BcItems_g;
        -- Send-order log
        LKind      : KindArray_t(0 to LogDepth_c-1);
        LHead      : natural range 0 to LogDepth_c-1;
        LNum       : natural range 0 to LogDepth_c;
        -- ACK / NACK processing
        EvState    : EvFsm_t;
        EvNack     : std_logic;
        EvSeq      : SeqCount_t;
        DelLeft    : natural range 0 to LogDepth_c;
        LastAck    : SeqCount_t;
        RetryReq   : std_logic;
        ProtErr    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Event FIFO
    signal EvRst      : std_logic;
    signal EvIn       : std_logic_vector(8 downto 0);
    signal EvInValid  : std_logic;
    signal EvOut      : std_logic_vector(8 downto 0);
    signal EvOutValid : std_logic;
    signal EvOutReady : std_logic;

    -- RAM and read-ahead FIFO
    signal RamWrData  : std_logic_vector(Width_c-1 downto 0);
    signal RamRdEna   : std_logic;
    signal RamRdData  : std_logic_vector(Width_c-1 downto 0);
    signal RamRdValid : std_logic;
    signal PfRst      : std_logic;
    signal PfInValid  : std_logic;
    signal PfLevel    : std_logic_vector(3 downto 0);
    signal PfData     : std_logic_vector(Width_c-1 downto 0);
    signal PfValid    : std_logic;
    signal PfReady    : std_logic;

    -- ECC events
    signal RamSec   : std_logic;
    signal RamDed   : std_logic;
    signal ScrubSec : std_logic;
    signal ScrubDed : std_logic;
    signal EvSec    : std_logic;
    signal EvDed    : std_logic;
    signal PfSec    : std_logic;
    signal PfDed    : std_logic;

    function wrapAdd (
        idx   : natural;
        add   : natural;
        depth : positive) return natural is
    begin
        return (idx + add) mod depth;
    end function;

begin

    assert 2**AddrWidth_c = Rows_g
        report "ofb_dl_erb: Rows_g must be a power of two"
        severity failure;
    assert DataItems_g + FctItems_g + BcItems_g <= 127
        report "ofb_dl_erb: at most 127 items can wait for acknowledgement"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- ACK / NACK event FIFO
    -----------------------------------------------------------------------------------------------
    EvRst     <= Rst or Ctrl_LinkReset;
    EvIn      <= Nack_Valid & AckNack_Seq;
    EvInValid <= Ack_Valid or Nack_Valid;

    i_ev_fifo : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => 9,
            Depth_g => 8
        )
        port map (
            Clk        => Clk,
            Rst        => EvRst,
            In_Data    => EvIn,
            In_Valid   => EvInValid,
            Out_Data   => EvOut,
            Out_Valid  => EvOutValid,
            Out_Ready  => EvOutReady,
            Out_EccSec => EvSec,
            Out_EccDed => EvDed
        );

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Seq_v   : SeqCount_t;
        variable Diff_v  : natural range 0 to 127;
        variable Kind_v  : ErbKind_t;
        variable Pop_v   : std_logic;
        variable RdEna_v : std_logic;
        variable Idx_v   : natural;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.ProtErr := '0';
        Pop_v     := '0';
        RdEna_v   := '0';

        -- Admission: data rows, data item, FCT, broadcast message. The range checks are redundant
        -- (the admission checks the space) but keep transient delta-cycle values in range.
        if WrData_Valid = '1' and r.Used < Rows_g and r.WrCnt < MaxFrameWords_c then
            v.WrPtr := r.WrPtr + 1;
            v.WrCnt := r.WrCnt + 1;
            v.Used  := r.Used + 1;
        end if;
        if WrData_Commit = '1' and v.WrCnt > 0 and r.DNum < DataItems_g then
            Idx_v         := wrapAdd(r.DHead, r.DNum, DataItems_g);
            v.DVc(Idx_v)  := WrData_Vc;
            v.DLen(Idx_v) := v.WrCnt;
            v.DNum        := r.DNum + 1;
            v.WrCnt       := 0;
        end if;
        if WrFct_Valid = '1' and r.FNum < FctItems_g then
            Idx_v          := wrapAdd(r.FHead, r.FNum, FctItems_g);
            v.FVc(Idx_v)   := WrFct_Vc;
            v.FMult(Idx_v) := WrFct_Mult;
            v.FNum         := r.FNum + 1;
        end if;
        if WrBc_Valid = '1' and r.BNum < BcItems_g then
            Idx_v          := wrapAdd(r.BHead, r.BNum, BcItems_g);
            v.BMsg(Idx_v)  := WrBc_Late & WrBc_Delayed & WrBc_Type & WrBc_Channel & WrBc_Data;
            v.BOnce(Idx_v) := '0';
            v.BNum         := r.BNum + 1;
        end if;

        -- Items sent with a sequence number (ignored until the RETRY of a NACK is sent)
        if Sent_Valid = '1' and r.RetryReq = '0' and r.LNum < LogDepth_c - 1 then
            if Sent_Kind = ErbData_c and r.DSent < DataItems_g then
                v.DSent := r.DSent + 1;
            elsif Sent_Kind = ErbFct_c and r.FSent < FctItems_g then
                v.FSent := r.FSent + 1;
            elsif Sent_Kind = ErbBc_c and r.BSent < BcItems_g then
                v.BOnce(wrapAdd(r.BHead, r.BSent, BcItems_g)) := '1';
                v.BSent                                       := r.BSent + 1;
            end if;
            v.LKind(wrapAdd(r.LHead, r.LNum, LogDepth_c)) := Sent_Kind;
            v.LNum                                        := r.LNum + 1;
        end if;

        -- ACK / NACK processing
        Seq_v  := unsigned(EvOut(6 downto 0));
        Diff_v := seqDiff(Seq_v, r.LastAck);

        case r.EvState is
            when Idle_s =>
                if EvOutValid = '1' then
                    Pop_v := '1';
                    if EvOut(SeqPolarity_c) = TxPolarity then
                        if Diff_v > r.LNum then
                            -- Inconsistent sequence count: protocol error, link reset
                            v.ProtErr := '1';
                        else
                            v.EvNack  := EvOut(8);
                            v.EvSeq   := Seq_v;
                            v.DelLeft := Diff_v;
                            v.LastAck := Seq_v;
                            v.EvState := Delete_s;
                        end if;
                    end if;
                end if;

            when Delete_s =>
                if r.DelLeft = 0 then
                    if r.EvNack = '1' then
                        -- Everything left is resent after a RETRY
                        v.DSent    := 0;
                        v.FSent    := 0;
                        v.BSent    := 0;
                        v.LNum     := 0;
                        v.RetryReq := '1';
                        v.EvState  := Retry_s;
                    else
                        v.EvState := Idle_s;
                    end if;
                else
                    -- Remove the oldest sent item
                    Kind_v    := r.LKind(r.LHead);
                    v.LHead   := wrapAdd(r.LHead, 1, LogDepth_c);
                    v.LNum    := v.LNum - 1;
                    v.DelLeft := r.DelLeft - 1;
                    if Kind_v = ErbData_c then
                        v.FreePtr  := r.FreePtr + r.DLen(r.DHead);
                        v.Used     := v.Used - r.DLen(r.DHead);
                        v.DHead    := wrapAdd(r.DHead, 1, DataItems_g);
                        v.DNum     := v.DNum - 1;
                        v.DSent    := v.DSent - 1;
                        v.FetchOff := r.FetchOff - 1;
                    elsif Kind_v = ErbFct_c then
                        v.FHead := wrapAdd(r.FHead, 1, FctItems_g);
                        v.FNum  := v.FNum - 1;
                        v.FSent := v.FSent - 1;
                    else
                        v.BHead := wrapAdd(r.BHead, 1, BcItems_g);
                        v.BNum  := v.BNum - 1;
                        v.BSent := v.BSent - 1;
                    end if;
                end if;

            when Retry_s =>
                -- ACKs and NACKs of the old polarity are discarded until the RETRY is sent
                Pop_v := EvOutValid;
                if Retry_Done = '1' then
                    v.RetryReq := '0';
                    v.Restart  := '1';
                    v.EvState  := Idle_s;
                end if;

            -- coverage off
            when others =>
                v.EvState := Idle_s;
            -- coverage on
        end case;

        -- Read-ahead of the data rows of the items in send order. After a NACK it stops until the
        -- RETRY is sent and all reads in flight have returned, then restarts at the oldest item.
        if r.RamRdValid = '1' then
            v.InFlight := r.InFlight - 1;
        end if;
        if r.Restart = '1' then
            if r.InFlight = 0 then
                v.Restart   := '0';
                v.RdPtr     := v.FreePtr;
                v.FetchOff  := 0;
                v.FetchLeft := 0;
            end if;
        elsif r.RetryReq = '0' then
            if r.FetchLeft = 0 then
                if r.FetchOff < r.DNum then
                    v.FetchLeft := r.DLen(wrapAdd(r.DHead, r.FetchOff, DataItems_g));
                    v.FetchOff  := v.FetchOff + 1;
                end if;
            elsif to_integer(unsigned(PfLevel)) + r.InFlight < 6 then
                RdEna_v     := '1';
                v.RdPtr     := r.RdPtr + 1;
                v.FetchLeft := r.FetchLeft - 1;
                v.InFlight  := v.InFlight + 1;
            end if;
        end if;
        v.RamRdValid := RamRdValid;

        -- Apply to record
        r_next <= v;

        EvOutReady <= Pop_v;
        RamRdEna   <= RdEna_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Outputs
    -----------------------------------------------------------------------------------------------
    p_out : process (all) is
        variable Idx_v : natural;
    begin
        -- Next data item
        Idx_v         := wrapAdd(r.DHead, r.DSent, DataItems_g);
        SndData_Vc    <= r.DVc(Idx_v);
        SndData_Len   <= std_logic_vector(to_unsigned(r.DLen(Idx_v), 7));
        SndData_Valid <= '0';
        if r.DNum > r.DSent and r.RetryReq = '0' then
            SndData_Valid <= '1';
        end if;
        -- Next FCT
        Idx_v        := wrapAdd(r.FHead, r.FSent, FctItems_g);
        SndFct_Vc    <= r.FVc(Idx_v);
        SndFct_Mult  <= r.FMult(Idx_v);
        SndFct_Valid <= '0';
        if r.FNum > r.FSent and r.RetryReq = '0' then
            SndFct_Valid <= '1';
        end if;
        -- Next broadcast message (a resent message carries the LATE flag)
        Idx_v         := wrapAdd(r.BHead, r.BSent, BcItems_g);
        SndBc_Data    <= r.BMsg(Idx_v)(63 downto 0);
        SndBc_Channel <= r.BMsg(Idx_v)(71 downto 64);
        SndBc_Type    <= r.BMsg(Idx_v)(79 downto 72);
        SndBc_Delayed <= r.BMsg(Idx_v)(80);
        SndBc_Late    <= r.BMsg(Idx_v)(81) or r.BOnce(Idx_v);
        SndBc_Valid   <= '0';
        if r.BNum > r.BSent and r.RetryReq = '0' then
            SndBc_Valid <= '1';
        end if;
        -- Space and status
        Data_FreeRows <= std_logic_vector(to_unsigned(Rows_g - r.Used, Data_FreeRows'length));
        Data_ItemFree <= '0';
        if r.DNum < DataItems_g then
            Data_ItemFree <= '1';
        end if;
        Fct_ItemFree <= '0';
        if r.FNum < FctItems_g then
            Fct_ItemFree <= '1';
        end if;
        Bc_ItemFree <= '0';
        if r.BNum < BcItems_g then
            Bc_ItemFree <= '1';
        end if;
        Stat_Full <= '0';
        if r.Used = Rows_g or r.DNum = DataItems_g or r.FNum = FctItems_g or r.BNum = BcItems_g then
            Stat_Full <= '1';
        end if;
        Stat_Empty <= '0';
        if r.DNum = 0 and r.FNum = 0 and r.BNum = 0 then
            Stat_Empty <= '1';
        end if;
    end process;

    Retry_Req        <= r.RetryReq;
    Retry_Seq        <= std_logic_vector(r.EvSeq);
    Ev_ProtocolError <= r.ProtErr;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                r.DHead    <= 0;
                r.DNum     <= 0;
                r.DSent    <= 0;
                r.WrPtr    <= (others => '0');
                r.WrCnt    <= 0;
                r.FreePtr  <= (others => '0');
                r.Used     <= 0;
                r.FHead    <= 0;
                r.FNum     <= 0;
                r.FSent    <= 0;
                r.BHead    <= 0;
                r.BNum     <= 0;
                r.BSent    <= 0;
                r.LHead    <= 0;
                r.LNum     <= 0;
                r.EvState  <= Idle_s;
                r.LastAck  <= (others => '0');
                r.RetryReq <= '0';
                r.ProtErr  <= '0';
                -- Reads in flight are discarded, the read-ahead restarts
                r.Restart   <= '1';
                r.FetchOff  <= 0;
                r.FetchLeft <= 0;
            end if;
            if Rst = '1' then
                r.InFlight   <= 0;
                r.RamRdValid <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Data rows: RAM and read-ahead FIFO
    -----------------------------------------------------------------------------------------------
    RamWrData <= WrData_K & WrData_Data;

    -- Frames may wait long for their ACK: the scrubber removes accumulated single errors
    i_ram : entity olo.olo_ft_ram_sdp_scrub
        generic map (
            Depth_g      => Rows_g,
            Width_g      => Width_c,
            ScrubClkHz_g => ClkFreq_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Wr_Addr        => std_logic_vector(r.WrPtr),
            Wr_Ena         => WrData_Valid,
            Wr_Data        => RamWrData,
            Rd_Addr        => std_logic_vector(r.RdPtr),
            Rd_Ena         => RamRdEna,
            Rd_Data        => RamRdData,
            Rd_Valid       => RamRdValid,
            Rd_EccSec      => RamSec,
            Rd_EccDed      => RamDed,
            ErrInj_BitFlip => eccInjPattern(eccCodewordWidth(Width_c), EccInj_Double),
            ErrInj_Valid   => EccInj_Valid,
            Scrub_EccSec   => ScrubSec,
            Scrub_EccDed   => ScrubDed,
            Scrub_PassDone => open,
            Scrub_Overrun  => open
        );

    PfRst     <= '1' when Rst = '1' or (r.Restart = '1' and r.InFlight = 0) else '0';
    PfInValid <= RamRdValid and not r.Restart and not r.RetryReq;

    i_pf_fifo : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => Width_c,
            Depth_g => 8
        )
        port map (
            Clk        => Clk,
            Rst        => PfRst,
            In_Data    => RamRdData,
            In_Valid   => PfInValid,
            In_Level   => PfLevel,
            Out_Data   => PfData,
            Out_Valid  => PfValid,
            Out_Ready  => PfReady,
            Out_EccSec => PfSec,
            Out_EccDed => PfDed
        );

    -- ECC events (MG-3): user reads of the RAM, scrubber, words read from the FIFOs
    Ev_EccSec <= (RamSec and RamRdValid) or ScrubSec or (EvSec and EvOutValid and EvOutReady) or
                 (PfSec and PfValid and PfReady);
    Ev_EccDed <= (RamDed and RamRdValid) or ScrubDed or (EvDed and EvOutValid and EvOutReady) or
                 (PfDed and PfValid and PfReady);

    Pay_Data  <= PfData(32*N_c-1 downto 0);
    Pay_K     <= PfData(36*N_c-1 downto 32*N_c);
    Pay_Valid <= PfValid and not r.Restart and not r.RetryReq;
    PfReady   <= Pay_Ready and not r.Restart and not r.RetryReq;

end architecture;
