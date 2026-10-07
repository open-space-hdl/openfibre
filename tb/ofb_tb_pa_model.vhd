---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Behavioural model of two Physical adapters connected by a lane (both directions), at the symbol
-- stream of the Lane layer: 8B/10B encoding with running disparity, channel effects (disconnection,
-- crossed pair, symbol offset, bit errors, skew in words) and decoding with code and disparity
-- error flags. A functional PRBS test: a checker locks to the pattern of the far end, forced errors
-- and pattern mismatches give words with errors.
--
-- What this model does NOT reproduce:
-- - Different clocks at both ends (both ends use Clk; no elastic buffer, no SKIP removal).
-- - Bit and symbol synchronisation time: the receiver decodes from the first symbol on and the
--   symbol boundaries are always correct (symbol alignment belongs to the SerDes).
-- - Detection delays of NoSignal: NoSignal follows the far-end driver enable within one cycle.
-- - Analogue effects (equalisation, jitter).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_8b10b_pkg.all;
    use work.ofb_tb_pa_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_tb_pa_model is
    generic (
        Instance_g : natural := 0 -- index into PaCtrl
    );
    port (
        Clk          : in    std_logic;
        -- End A
        A_Tx_Data    : in    Word_t;
        A_Tx_K       : in    WordK_t;
        A_TxEnable   : in    std_logic;
        A_RxEnable   : in    std_logic;
        A_CdrEnable  : in    std_logic;
        A_RxInvert   : in    std_logic;
        A_Rx_Data    : out   Word_t;
        A_Rx_K       : out   WordK_t;
        A_Rx_CodeErr : out   WordK_t;
        A_Rx_DispErr : out   WordK_t;
        A_Rx_Valid   : out   std_logic;
        A_NoSignal   : out   std_logic;
        A_NearSerLb  : in    std_logic                    := '0';
        A_FarSerLb   : in    std_logic                    := '0';
        A_PrbsTxSel  : in    std_logic_vector(3 downto 0) := "0000";
        A_PrbsRxSel  : in    std_logic_vector(3 downto 0) := "0000";
        A_PrbsForce  : in    std_logic                    := '0';
        A_PrbsCntRst : in    std_logic                    := '0';
        A_PrbsErr    : out   std_logic;
        A_PrbsLocked : out   std_logic;
        -- End B
        B_Tx_Data    : in    Word_t;
        B_Tx_K       : in    WordK_t;
        B_TxEnable   : in    std_logic;
        B_RxEnable   : in    std_logic;
        B_CdrEnable  : in    std_logic;
        B_RxInvert   : in    std_logic;
        B_Rx_Data    : out   Word_t;
        B_Rx_K       : out   WordK_t;
        B_Rx_CodeErr : out   WordK_t;
        B_Rx_DispErr : out   WordK_t;
        B_Rx_Valid   : out   std_logic;
        B_NoSignal   : out   std_logic;
        B_NearSerLb  : in    std_logic                    := '0';
        B_FarSerLb   : in    std_logic                    := '0';
        B_PrbsTxSel  : in    std_logic_vector(3 downto 0) := "0000";
        B_PrbsRxSel  : in    std_logic_vector(3 downto 0) := "0000";
        B_PrbsForce  : in    std_logic                    := '0';
        B_PrbsCntRst : in    std_logic                    := '0';
        B_PrbsErr    : out   std_logic;
        B_PrbsLocked : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_tb_pa_model is

    type Symbols_t is array (0 to 7) of Code_t;
    type Present_t is array (0 to 7) of boolean;

    -- Receiver output, delayed by the skew
    type RxWord_t is record
        Data     : Word_t;
        K        : WordK_t;
        Code     : WordK_t;
        Disp     : WordK_t;
        Valid    : std_logic;
        NoSignal : std_logic;
    end record;

    type Delay_t is array (0 to 7) of RxWord_t;

    constant RxIdle_c : RxWord_t := (Data => (others => '0'), K => (others => '0'), Code => (others => '0'),
                                     Disp => (others => '0'), Valid => '0', NoSignal => '1');

    -- One direction of the channel: transmitter at end X, receiver at end Y
    procedure direction (
        signal tx_data    : in    Word_t;
        signal tx_k       : in    WordK_t;
        signal tx_enable  : in    std_logic;
        signal rx_enable  : in    std_logic;
        signal cdr_enable : in   std_logic;
        signal rx_invert  : in    std_logic;
        constant ctrl     : in    PaDirCtrl_t;
        variable enc_rd   : inout std_logic;
        variable dec_rd   : inout std_logic;
        variable flips    : inout natural;
        variable buf      : inout Symbols_t;
        variable present  : inout Present_t;
        variable dly      : inout Delay_t;
        signal rx_data    : out   Word_t;
        signal rx_k       : out   WordK_t;
        signal rx_code    : out   WordK_t;
        signal rx_disp    : out   WordK_t;
        signal rx_valid   : out   std_logic;
        signal no_signal  : out   std_logic) is
        variable Enc_v     : Encoded_t;
        variable Dec_v     : Decoded_t;
        variable Code_v    : Code_t;
        variable Present_v : boolean;
        variable AllPres_v : boolean;
        variable FlipBit_v : natural range 0 to 9;
        variable Rx_v      : RxWord_t;
    begin

        -- Shift: the previous four symbols move to positions 0 to 3
        for i in 0 to 3 loop
            buf(i)     := buf(i+4);
            present(i) := present(i+4);
        end loop;

        -- Transmitter and channel
        Present_v := tx_enable = '1' and not ctrl.Cut;

        for i in 0 to 3 loop
            if Present_v then
                Enc_v  := encode(tx_data(8*i+7 downto 8*i), tx_k(i), enc_rd);
                enc_rd := Enc_v.Rd;
                Code_v := Enc_v.Code;
                if ctrl.Invert then
                    Code_v := not Code_v;
                end if;
                if flips < ctrl.Flips then
                    FlipBit_v         := flips mod 10;
                    Code_v(FlipBit_v) := not Code_v(FlipBit_v);
                    flips             := flips + 1;
                end if;
            else
                Code_v := (others => '0');
            end if;
            buf(i+4)     := Code_v;
            present(i+4) := Present_v;
        end loop;

        -- Receiver: four symbols delayed by Offset symbols
        AllPres_v := true;

        for j in 0 to 3 loop
            AllPres_v := AllPres_v and present(4-ctrl.Offset+j);
        end loop;

        Rx_v := dly(0);
        if AllPres_v then
            Rx_v.NoSignal := '0';
        else
            Rx_v.NoSignal := '1';
        end if;
        if AllPres_v and rx_enable = '1' and cdr_enable = '1' then

            for j in 0 to 3 loop
                Code_v := buf(4-ctrl.Offset+j);
                if rx_invert = '1' then
                    Code_v := not Code_v;
                end if;
                Dec_v                       := decode(Code_v, dec_rd);
                dec_rd                      := Dec_v.Rd;
                Rx_v.Data(8*j+7 downto 8*j) := Dec_v.Char;
                Rx_v.K(j)                   := Dec_v.K;
                Rx_v.Code(j)                := Dec_v.CodeErr;
                Rx_v.Disp(j)                := Dec_v.DispErr;
            end loop;

            Rx_v.Valid := '1';
        else
            Rx_v.Valid := '0';
            Rx_v.Code  := (others => '0');
            Rx_v.Disp  := (others => '0');
        end if;

        -- Skew: delay line of words, the output is taken at the current skew
        for i in 7 downto 1 loop
            dly(i) := dly(i-1);
        end loop;

        dly(0)    := Rx_v;
        Rx_v      := dly(ctrl.Skew);
        rx_data   <= Rx_v.Data;
        rx_k      <= Rx_v.K;
        rx_code   <= Rx_v.Code;
        rx_disp   <= Rx_v.Disp;
        rx_valid  <= Rx_v.Valid;
        no_signal <= Rx_v.NoSignal;
    end procedure;

    -- Transmitted signals arriving at the receivers, with the serial loopbacks
    signal AtoB_Data : Word_t;
    signal AtoB_K    : WordK_t;
    signal AtoB_En   : std_logic;
    signal BtoA_Data : Word_t;
    signal BtoA_K    : WordK_t;
    signal BtoA_En   : std_logic;

    -- PRBS test of the transceiver (functional model): the checker at end Y locks eight cycles after a checker reset
    -- when it checks the pattern that end X sends over a connected line and stays locked until the next reset; a
    -- forced error at X gives one word with an error at Y; another pattern or no signal gives an error in every word
    procedure prbsDirection (
        signal tx_sel     : in    std_logic_vector(3 downto 0);
        signal tx_force   : in    std_logic;
        signal tx_enable  : in    std_logic;
        signal rx_sel     : in    std_logic_vector(3 downto 0);
        signal rx_cnt_rst : in    std_logic;
        constant ctrl     : in    PaDirCtrl_t;
        variable cnt      : inout natural;
        variable locked   : inout boolean;
        signal err        : out   std_logic;
        signal lock_out   : out   std_logic) is
    begin
        err <= '0';
        if rx_sel = "0000" or rx_cnt_rst = '1' then
            cnt    := 0;
            locked := false;
        elsif rx_sel = tx_sel and tx_enable = '1' and not ctrl.Cut then
            if cnt < 8 then
                cnt := cnt + 1;
            else
                locked := true;
                err    <= tx_force;
            end if;
        else
            cnt := 0;
            err <= '1';
        end if;
        lock_out <= '1' when locked else '0';
    end procedure;

begin

    -- Receiver of B: own transmitter in near-end loopback at B or far-end loopback at A, else A
    AtoB_Data <= B_Tx_Data when B_NearSerLb = '1' or A_FarSerLb = '1' else A_Tx_Data;
    AtoB_K    <= B_Tx_K when B_NearSerLb = '1' or A_FarSerLb = '1' else A_Tx_K;
    AtoB_En   <= B_TxEnable when B_NearSerLb = '1' or A_FarSerLb = '1' else A_TxEnable;

    -- Receiver of A: own transmitter in near-end loopback at A or far-end loopback at B, else B
    BtoA_Data <= A_Tx_Data when A_NearSerLb = '1' or B_FarSerLb = '1' else B_Tx_Data;
    BtoA_K    <= A_Tx_K when A_NearSerLb = '1' or B_FarSerLb = '1' else B_Tx_K;
    BtoA_En   <= A_TxEnable when A_NearSerLb = '1' or B_FarSerLb = '1' else B_TxEnable;

    p_a_to_b : process (Clk) is
        variable EncRd_v   : std_logic := '0';
        variable DecRd_v   : std_logic := '0';
        variable Flips_v   : natural   := 0;
        variable Buf_v     : Symbols_t := (others => (others => '0'));
        variable Present_v : Present_t := (others => false);
        variable Dly_v     : Delay_t   := (others => RxIdle_c);
    begin
        if rising_edge(Clk) then
            direction(AtoB_Data, AtoB_K, AtoB_En, B_RxEnable, B_CdrEnable, B_RxInvert,
                      PaCtrl(Instance_g).AtoB, EncRd_v, DecRd_v, Flips_v, Buf_v, Present_v, Dly_v,
                      B_Rx_Data, B_Rx_K, B_Rx_CodeErr, B_Rx_DispErr, B_Rx_Valid, B_NoSignal);
        end if;
    end process;

    p_b_to_a : process (Clk) is
        variable EncRd_v   : std_logic := '0';
        variable DecRd_v   : std_logic := '0';
        variable Flips_v   : natural   := 0;
        variable Buf_v     : Symbols_t := (others => (others => '0'));
        variable Present_v : Present_t := (others => false);
        variable Dly_v     : Delay_t   := (others => RxIdle_c);
    begin
        if rising_edge(Clk) then
            direction(BtoA_Data, BtoA_K, BtoA_En, A_RxEnable, A_CdrEnable, A_RxInvert,
                      PaCtrl(Instance_g).BtoA, EncRd_v, DecRd_v, Flips_v, Buf_v, Present_v, Dly_v,
                      A_Rx_Data, A_Rx_K, A_Rx_CodeErr, A_Rx_DispErr, A_Rx_Valid, A_NoSignal);
        end if;
    end process;

    p_prbs : process (Clk) is
        variable CntA_v    : natural := 0;
        variable CntB_v    : natural := 0;
        variable LockedA_v : boolean := false;
        variable LockedB_v : boolean := false;
    begin
        if rising_edge(Clk) then
            prbsDirection(A_PrbsTxSel, A_PrbsForce, A_TxEnable, B_PrbsRxSel, B_PrbsCntRst, PaCtrl(Instance_g).AtoB,
                          CntB_v, LockedB_v, B_PrbsErr, B_PrbsLocked);
            prbsDirection(B_PrbsTxSel, B_PrbsForce, B_TxEnable, A_PrbsRxSel, A_PrbsCntRst, PaCtrl(Instance_g).BtoA,
                          CntA_v, LockedA_v, A_PrbsErr, A_PrbsLocked);
        end if;
    end process;

end architecture;
