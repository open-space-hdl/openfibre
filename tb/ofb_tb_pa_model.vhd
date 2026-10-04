---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Behavioural model of two Physical adapters connected by a lane (both directions), at the symbol
-- stream of the Lane layer: 8B/10B encoding with running disparity, channel effects (disconnection,
-- crossed pair, symbol offset, bit errors) and decoding with code and disparity error flags.
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
        B_NoSignal   : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_tb_pa_model is

    type Symbols_t is array (0 to 7) of Code_t;
    type Present_t is array (0 to 7) of boolean;

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

        if AllPres_v then
            no_signal <= '0';
        else
            no_signal <= '1';
        end if;
        if AllPres_v and rx_enable = '1' and cdr_enable = '1' then

            for j in 0 to 3 loop
                Code_v := buf(4-ctrl.Offset+j);
                if rx_invert = '1' then
                    Code_v := not Code_v;
                end if;
                Dec_v                     := decode(Code_v, dec_rd);
                dec_rd                    := Dec_v.Rd;
                rx_data(8*j+7 downto 8*j) <= Dec_v.Char;
                rx_k(j)                   <= Dec_v.K;
                rx_code(j)                <= Dec_v.CodeErr;
                rx_disp(j)                <= Dec_v.DispErr;
            end loop;

            rx_valid <= '1';
        else
            rx_valid <= '0';
            rx_code  <= (others => '0');
            rx_disp  <= (others => '0');
        end if;
    end procedure;

begin

    p_a_to_b : process (Clk) is
        variable EncRd_v   : std_logic := '0';
        variable DecRd_v   : std_logic := '0';
        variable Flips_v   : natural   := 0;
        variable Buf_v     : Symbols_t := (others => (others => '0'));
        variable Present_v : Present_t := (others => false);
    begin
        if rising_edge(Clk) then
            direction(A_Tx_Data, A_Tx_K, A_TxEnable, B_RxEnable, B_CdrEnable, B_RxInvert,
                      PaCtrl(Instance_g).AtoB, EncRd_v, DecRd_v, Flips_v, Buf_v, Present_v,
                      B_Rx_Data, B_Rx_K, B_Rx_CodeErr, B_Rx_DispErr, B_Rx_Valid, B_NoSignal);
        end if;
    end process;

    p_b_to_a : process (Clk) is
        variable EncRd_v   : std_logic := '0';
        variable DecRd_v   : std_logic := '0';
        variable Flips_v   : natural   := 0;
        variable Buf_v     : Symbols_t := (others => (others => '0'));
        variable Present_v : Present_t := (others => false);
    begin
        if rising_edge(Clk) then
            direction(B_Tx_Data, B_Tx_K, B_TxEnable, A_RxEnable, A_CdrEnable, A_RxInvert,
                      PaCtrl(Instance_g).BtoA, EncRd_v, DecRd_v, Flips_v, Buf_v, Present_v,
                      A_Rx_Data, A_Rx_K, A_Rx_CodeErr, A_Rx_DispErr, A_Rx_Valid, A_NoSignal);
        end if;
    end process;

end architecture;
