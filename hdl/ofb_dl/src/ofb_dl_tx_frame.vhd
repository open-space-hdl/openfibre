---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Transmit scheduler and frame assembler of the Data Link layer (DT-5, DT-6, DT-8): selects the
-- next word by the precedence of ECSS 5.3.10c, builds the frames and control words, numbers them
-- (ECSS 5.7.6.3.1) and computes the CRC-8 (ECSS 5.7.6.5).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.5)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.ofb_pkg.all;
    use work.ofb_dl_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_tx_frame is
    port (
        -- Control Ports
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        Ctrl_LinkReset  : in    std_logic;
        Ctrl_TxIdle     : in    std_logic; -- Output VC buffers empty, no FCT or broadcast to admit
        -- Error recovery buffer: next items, data words, sent items, RETRY
        SndBc_Valid     : in    std_logic;
        SndBc_Data      : in    std_logic_vector(63 downto 0);
        SndBc_Channel   : in    Char_t;
        SndBc_Type      : in    Char_t;
        SndBc_Delayed   : in    std_logic;
        SndBc_Late      : in    std_logic;
        SndFct_Valid    : in    std_logic;
        SndFct_Vc       : in    std_logic_vector(4 downto 0);
        SndFct_Mult     : in    std_logic_vector(2 downto 0);
        SndData_Valid   : in    std_logic;
        SndData_Vc      : in    std_logic_vector(4 downto 0);
        SndData_Len     : in    std_logic_vector(6 downto 0);
        Pay_Data        : in    Word_t;
        Pay_K           : in    WordK_t;
        Pay_Valid       : in    std_logic;
        Pay_Ready       : out   std_logic;
        Sent_Valid      : out   std_logic;
        Sent_Kind       : out   ErbKind_t;
        Retry_Req       : in    std_logic;
        Retry_Seq       : in    std_logic_vector(6 downto 0);
        Retry_Done      : out   std_logic;
        Erb_Full        : in    std_logic;
        Erb_Empty       : in    std_logic;
        -- Receive side: ACK / NACK requests, Receive Sequence Number, errors
        Ev_AckReq       : in    std_logic;
        Ev_NackReq      : in    std_logic;
        RxSeqCount      : in    std_logic_vector(6 downto 0);
        RxPolarity      : in    std_logic;
        Ev_RxError      : in    std_logic; -- RXERR or CRC error received
        -- Rows to the Multi-Lane layer
        TxRow_Data      : out   Word_t;
        TxRow_K         : out   WordK_t;
        TxRow_Replicate : out   std_logic;
        TxRow_Valid     : out   std_logic;
        TxRow_Ready     : in    std_logic;
        -- Transmit Polarity Flag, events
        TxPolarity      : out   std_logic;
        Ev_WordSent     : out   std_logic;
        Ev_BcSent       : out   std_logic;
        Ev_Retry        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_tx_frame is

    constant AckGap_c    : natural := 15;
    constant FullCycle_c : natural := 64;

    type TwoProcess_r is record
        -- Output register
        OData     : Word_t;
        OK        : WordK_t;
        ORepl     : std_logic;
        OValid    : std_logic;
        -- Sequence numbers
        TxSeq     : SeqCount_t;
        TxPol     : std_logic;
        -- Open frames
        BcOpen    : boolean;
        BcIdx     : natural range 0 to 3;
        BcCrc     : Char_t;
        DataOpen  : boolean;
        DataLeft  : natural range 0 to MaxFrameWords_c;
        IdleOpen  : boolean;
        PrbsCnt   : natural range 0 to MaxFrameWords_c;
        -- Pending control words
        AckPend   : std_logic;
        NackPend  : std_logic;
        AckGap    : natural range 0 to AckGap_c;
        FullPend  : std_logic;
        FullPrev  : std_logic;
        FullCnt   : natural range 0 to FullCycle_c;
        -- Events
        BcSent    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal PrbsRst     : std_logic;
    signal PrbsData    : Word_t;
    signal PrbsAdvance : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Combinational Process
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Load_v  : boolean;
        variable Done_v  : boolean;
        variable Seq_v   : SeqNum_t;
        variable Word_v  : Word_t;
        variable Adv_v   : std_logic;
        variable PayRd_v : std_logic;
        variable IsAck_v : boolean;
        variable Sent_v  : std_logic;
        variable Kind_v  : ErbKind_t;
        variable Retry_v : std_logic;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        v.BcSent    := '0';
        Sent_v      := '0';
        Kind_v      := ErbData_c;
        Retry_v     := '0';
        Adv_v       := '0';
        PayRd_v     := '0';
        IsAck_v     := false;
        Done_v      := false;

        -- The output register is loaded when it is empty or its word is taken
        Load_v := r.OValid = '0' or TxRow_Ready = '1';

        if Load_v then
            v.OValid := '1';
            v.ORepl  := '1';
            v.OK     := KCtrl_c;

            -- 1: RETRY, the open frames are abandoned
            if Retry_Req = '1' then
                v.OData     := WordRetry_c;
                Retry_v     := '1';
                v.TxSeq     := unsigned(Retry_Seq);
                v.TxPol     := not r.TxPol;
                v.BcOpen    := false;
                v.DataOpen  := false;
                v.IdleOpen  := false;

            -- 2: open broadcast frame
            elsif r.BcOpen then
                if r.BcIdx = 3 then
                    v.TxSeq     := r.TxSeq + 1;
                    Seq_v       := r.TxPol & std_logic_vector(r.TxSeq + 1);
                    Word_v      := wordEbf(SndBc_Delayed & SndBc_Late, Seq_v, x"00");
                    v.OData     := wordEbf(SndBc_Delayed & SndBc_Late, Seq_v, crc8Chars(r.BcCrc, Word_v, 3));
                    v.BcOpen    := false;
                    Sent_v      := '1';
                    Kind_v      := ErbBc_c;
                    v.BcSent    := '1';
                else
                    if r.BcIdx = 1 then
                        Word_v := SndBc_Data(31 downto 0);
                    else
                        Word_v := SndBc_Data(63 downto 32);
                    end if;
                    v.OData := Word_v;
                    v.OK    := KData_c;
                    v.BcCrc := crc8Chars(r.BcCrc, Word_v, 4);
                    v.BcIdx := r.BcIdx + 1;
                end if;

            -- 3: broadcast frame (inside a data frame, or ending an idle frame)
            elsif SndBc_Valid = '1' then
                Word_v     := wordSbf(SndBc_Channel, SndBc_Type);
                v.OData    := Word_v;
                v.BcCrc    := crc8Chars(Crc8Seed_c, Word_v, 4);
                v.BcOpen   := true;
                v.BcIdx    := 1;
                v.IdleOpen := false;

            -- 4: NACK, ACK (at least 15 words after the previous ACK)
            elsif r.NackPend = '1' then
                v.OData    := wordNack(not RxPolarity & RxSeqCount);
                v.NackPend := '0';
            elsif r.AckPend = '1' and r.AckGap = AckGap_c then
                v.OData   := wordAck(RxPolarity & RxSeqCount);
                v.AckPend := '0';
                IsAck_v   := true;

            -- 5: FCT
            elsif SndFct_Valid = '1' then
                v.TxSeq     := r.TxSeq + 1;
                v.OData     := wordFct(SndFct_Mult, SndFct_Vc, r.TxPol & std_logic_vector(r.TxSeq + 1));
                Sent_v      := '1';
                Kind_v      := ErbFct_c;

            -- 6: FULL
            elsif r.FullPend = '1' then
                v.OData    := wordFull(r.TxPol & std_logic_vector(r.TxSeq));
                v.FullPend := '0';
                v.FullCnt  := 0;

            -- 7: open data frame: data words, then EDF
            elsif r.DataOpen then
                if r.DataLeft = 0 then
                    v.TxSeq     := r.TxSeq + 1;
                    v.OData     := wordEdf(r.TxPol & std_logic_vector(r.TxSeq + 1), x"0000");
                    v.DataOpen  := false;
                    Sent_v      := '1';
                    Kind_v      := ErbData_c;
                elsif Pay_Valid = '1' then
                    v.OData    := Pay_Data;
                    v.OK       := Pay_K;
                    v.ORepl    := '0';
                    v.DataLeft := r.DataLeft - 1;
                    PayRd_v    := '1';
                else
                    -- Data word not yet read ahead
                    v.OValid := '0';
                end if;

            -- 8: data frame
            elsif SndData_Valid = '1' then
                v.OData    := wordSdf(SndData_Vc);
                v.DataOpen := true;
                v.DataLeft := to_integer(unsigned(SndData_Len));
                v.IdleOpen := false;

            -- 9: idle frame
            elsif not r.IdleOpen or r.PrbsCnt = MaxFrameWords_c then
                v.OData    := wordSif(r.TxPol & std_logic_vector(r.TxSeq));
                v.IdleOpen := true;
                v.PrbsCnt  := 0;
            else
                v.OData   := PrbsData;
                v.OK      := KData_c;
                v.PrbsCnt := r.PrbsCnt + 1;
                Adv_v     := '1';
            end if;

            -- Words since the last ACK, words while the buffer is full
            if IsAck_v then
                v.AckGap := 0;
            elsif v.OValid = '1' and r.AckGap < AckGap_c then
                v.AckGap := r.AckGap + 1;
            end if;
            if v.OValid = '1' and r.FullCnt < FullCycle_c then
                v.FullCnt := v.FullCnt + 1;
            end if;
        end if;

        -- ACK / NACK requests: the newer one replaces a pending request of the other kind
        if Ev_AckReq = '1' then
            v.AckPend  := '1';
            v.NackPend := '0';
        elsif Ev_NackReq = '1' then
            v.NackPend := '1';
            v.AckPend  := '0';
        end if;

        -- FULL: when the buffer becomes full, every 64 words while it stays full, and after a
        -- receive error when nothing is left to send but the buffer is not empty
        v.FullPrev := Erb_Full;
        if Erb_Full = '1' and (r.FullPrev = '0' or r.FullCnt = FullCycle_c) then
            v.FullPend := '1';
            v.FullCnt  := 0;
        end if;
        if Ev_RxError = '1' and Ctrl_TxIdle = '1' and Erb_Empty = '0' and SndBc_Valid = '0' and
           SndFct_Valid = '0' and SndData_Valid = '0' then
            v.FullPend := '1';
        end if;

        -- Outputs (the error recovery buffer sees sent items and the RETRY in the same cycle)
        Pay_Ready   <= PayRd_v;
        PrbsAdvance <= Adv_v;
        Sent_Valid  <= Sent_v;
        Sent_Kind   <= Kind_v;
        Retry_Done  <= Retry_v;
        Ev_Retry    <= Retry_v;

        -- Apply to record
        r_next <= v;

    end process;

    TxRow_Data      <= r.OData;
    TxRow_K         <= r.OK;
    TxRow_Replicate <= r.ORepl;
    TxRow_Valid     <= r.OValid;
    TxPolarity      <= r.TxPol;
    Ev_WordSent     <= r.OValid and TxRow_Ready;
    Ev_BcSent       <= r.BcSent;

    -----------------------------------------------------------------------------------------------
    -- Sequential Process
    -----------------------------------------------------------------------------------------------
    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                r.OValid    <= '0';
                r.TxSeq     <= (others => '0');
                r.TxPol     <= '0';
                r.BcOpen    <= false;
                r.DataOpen  <= false;
                r.IdleOpen  <= false;
                r.PrbsCnt   <= 0;
                r.AckPend   <= '0';
                r.NackPend  <= '0';
                r.AckGap    <= AckGap_c;
                r.FullPend  <= '0';
                r.FullPrev  <= '0';
                r.FullCnt   <= 0;
                r.BcSent    <= '0';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Idle frame PRBS (seed 0xFFFF after reset and link reset)
    -----------------------------------------------------------------------------------------------
    PrbsRst <= Rst or Ctrl_LinkReset;

    i_prbs : entity olo.olo_base_prbs
        generic map (
            Polynomial_g    => PrbsPolynomial_c,
            Seed_g          => PrbsSeed_c,
            BitsPerSymbol_g => 32
        )
        port map (
            Clk       => Clk,
            Rst       => PrbsRst,
            Out_Data  => PrbsData,
            Out_Ready => PrbsAdvance
        );

end architecture;
