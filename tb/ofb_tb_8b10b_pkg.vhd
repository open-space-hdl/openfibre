---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- 8B/10B encoding and decoding of ECSS-E-ST-50-11C clause 5.3.2 (Tables 5-1 and 5-2) for the
-- behavioural Physical adapter model. Bit 0 of a 10-bit code is "a", the bit transmitted first.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_tb_8b10b_pkg is

    -- Running disparity: '0' = RD-, '1' = RD+
    subtype Code_t is std_logic_vector(9 downto 0);

    type Encoded_t is record
        Code : Code_t;
        Rd   : std_logic; -- running disparity after the symbol
    end record;

    type Decoded_t is record
        Char    : Char_t;
        K       : std_logic;
        CodeErr : std_logic; -- not a valid code for either running disparity
        DispErr : std_logic; -- valid code, but for the other running disparity
        Rd      : std_logic; -- running disparity after the symbol
    end record;

    -- Encode a character; k = '1' for a control character (only the 12 valid K-codes are allowed)
    function encode (
        char : Char_t;
        k    : std_logic;
        rd   : std_logic) return Encoded_t;

    function decode (
        code : Code_t;
        rd   : std_logic) return Decoded_t;

    -- True for the K-codes that exist in 8B/10B
    function isKcode (char : Char_t) return boolean;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_tb_8b10b_pkg is

    -- 5B/6B table (ECSS Table 5-1), "abcdei" written left to right, for RD- and RD+
    type Table6_t is array (0 to 31) of string(1 to 6);

    constant Code6Neg_c : Table6_t       := (
        "100111", "011101", "101101", "110001", "110101", "101001", "011001", "111000",
        "111001", "100101", "010101", "110100", "001101", "101100", "011100", "010111",
        "011011", "100011", "010011", "110010", "001011", "101010", "011010", "111010",
        "110011", "100110", "010110", "110110", "001110", "101110", "011110", "101011");
    constant Code6Pos_c : Table6_t       := (
        "011000", "100010", "010010", "110001", "001010", "101001", "011001", "000111",
        "000110", "100101", "010101", "110100", "001101", "101100", "011100", "101000",
        "100100", "100011", "010011", "110010", "001011", "101010", "011010", "000101",
        "001100", "100110", "010110", "001001", "001110", "010001", "100001", "010100");
    constant K28Neg_c   : string(1 to 6) := "001111";
    constant K28Pos_c   : string(1 to 6) := "110000";

    -- 3B/4B table (ECSS Table 5-2), "fghj", for RD- and RD+ after the 6-bit block
    type Table4_t is array (0 to 7) of string(1 to 4);

    constant Data4Neg_c : Table4_t := ("1011", "1001", "0101", "1100", "1101", "1010", "0110", "1110");
    constant Data4Pos_c : Table4_t := ("0100", "1001", "0101", "0011", "0010", "1010", "0110", "0001");
    constant K4Neg_c    : Table4_t := ("1011", "0110", "1010", "1100", "1101", "0101", "1001", "0111");
    constant K4Pos_c    : Table4_t := ("0100", "1001", "0101", "0011", "0010", "1010", "0110", "1000");

    function ones (s : string) return integer is
        variable N_v : integer := 0;
    begin

        for i in s'range loop
            if s(i) = '1' then
                N_v := N_v + 1;
            end if;
        end loop;

        return N_v;
    end function;

    function isKcode (char : Char_t) return boolean is
        variable X_v : natural;
        variable Y_v : natural;
    begin
        X_v := to_integer(unsigned(char(4 downto 0)));
        Y_v := to_integer(unsigned(char(7 downto 5)));
        return X_v = 28 or (Y_v = 7 and (X_v = 23 or X_v = 27 or X_v = 29 or X_v = 30));
    end function;

    function encode (
        char : Char_t;
        k    : std_logic;
        rd   : std_logic) return Encoded_t is
        variable X_v   : natural range 0 to 31;
        variable Y_v   : natural range 0 to 7;
        variable S6_v  : string(1 to 6);
        variable S4_v  : string(1 to 4);
        variable Rd_v  : std_logic;
        variable Res_v : Encoded_t;
    begin
        X_v  := to_integer(unsigned(char(4 downto 0)));
        Y_v  := to_integer(unsigned(char(7 downto 5)));
        Rd_v := rd;
        -- 6-bit block
        if k = '1' and X_v = 28 then
            if Rd_v = '0' then
                S6_v := K28Neg_c;
            else
                S6_v := K28Pos_c;
            end if;
        elsif Rd_v = '0' then
            S6_v := Code6Neg_c(X_v);
        else
            S6_v := Code6Pos_c(X_v);
        end if;
        -- An unbalanced block inverts the running disparity; balanced blocks (including 111000 and
        -- 000111, which are chosen by the running disparity) keep it
        if ones(S6_v) /= 3 then
            Rd_v := not Rd_v;
        end if;
        -- 4-bit block, with the alternate D.x.7 encoding (ECSS Table 5-2)
        if k = '1' then
            if Rd_v = '0' then
                S4_v := K4Neg_c(Y_v);
            else
                S4_v := K4Pos_c(Y_v);
            end if;
        elsif Y_v = 7 then
            if Rd_v = '0' then
                if X_v = 17 or X_v = 18 or X_v = 20 then
                    S4_v := "0111";
                else
                    S4_v := "1110";
                end if;
            elsif X_v = 11 or X_v = 13 or X_v = 14 then
                S4_v := "1000";
            else
                S4_v := "0001";
            end if;
        elsif Rd_v = '0' then
            S4_v := Data4Neg_c(Y_v);
        else
            S4_v := Data4Pos_c(Y_v);
        end if;
        if ones(S4_v) /= 2 then
            Rd_v := not Rd_v;
        end if;

        -- Code bit 0 = a ... bit 5 = i, bit 6 = f ... bit 9 = j
        for i in 0 to 5 loop
            if S6_v(i+1) = '1' then
                Res_v.Code(i) := '1';
            else
                Res_v.Code(i) := '0';
            end if;
        end loop;

        for i in 0 to 3 loop
            if S4_v(i+1) = '1' then
                Res_v.Code(6+i) := '1';
            else
                Res_v.Code(6+i) := '0';
            end if;
        end loop;

        Res_v.Rd := Rd_v;
        return Res_v;
    end function;

    -- Decoding table, built once from the encoder: index (rd, code)
    type DecEntry_t is record
        Valid : boolean;
        Char  : Char_t;
        K     : std_logic;
        Rd    : std_logic;
    end record;

    type DecTable_t is array (0 to 1, 0 to 1023) of DecEntry_t;

    function buildTable return DecTable_t is
        variable Tab_v  : DecTable_t;
        variable Enc_v  : Encoded_t;
        variable Char_v : Char_t;
        variable Idx_v  : natural;
    begin

        for r in 0 to 1 loop

            for c in 0 to 1023 loop
                Tab_v(r, c) := (Valid => false,
                                Char => (others => '0'),
                                K => '0',
                                Rd => '0');
            end loop;

        end loop;

        for r in 0 to 1 loop

            for c in 0 to 255 loop
                Char_v := std_logic_vector(to_unsigned(c, 8));

                for kk in 0 to 1 loop
                    if kk = 0 or isKcode(Char_v) then
                        if r = 0 then
                            Enc_v := encode(Char_v, std_logic'val(2 + kk), '0');
                        else
                            Enc_v := encode(Char_v, std_logic'val(2 + kk), '1');
                        end if;
                        Idx_v := to_integer(unsigned(Enc_v.Code));
                        if kk = 1 then
                            Tab_v(r, Idx_v) := (Valid => true,
                                                Char => Char_v,
                                                K => '1',
                                                Rd => Enc_v.Rd);
                        else
                            Tab_v(r, Idx_v) := (Valid => true,
                                                Char => Char_v,
                                                K => '0',
                                                Rd => Enc_v.Rd);
                        end if;
                    end if;
                end loop;

            end loop;

        end loop;

        return Tab_v;
    end function;

    constant DecTable_c : DecTable_t := buildTable;

    function decode (
        code : Code_t;
        rd   : std_logic) return Decoded_t is
        variable Res_v : Decoded_t;
        variable Idx_v : natural;
        variable Cur_v : natural range 0 to 1;
        variable Oth_v : natural range 0 to 1;
    begin
        Res_v := (Char => (others => '0'),
                  K => '0',
                  CodeErr => '0',
                  DispErr => '0',
                  Rd => rd);
        if is_x(code) then
            Res_v.CodeErr := '1';
            return Res_v;
        end if;
        Idx_v := to_integer(unsigned(code));
        if rd = '1' then
            Cur_v := 1;
            Oth_v := 0;
        else
            Cur_v := 0;
            Oth_v := 1;
        end if;
        if DecTable_c(Cur_v, Idx_v).Valid then
            Res_v.Char := DecTable_c(Cur_v, Idx_v).Char;
            Res_v.K    := DecTable_c(Cur_v, Idx_v).K;
            Res_v.Rd   := DecTable_c(Cur_v, Idx_v).Rd;
        elsif DecTable_c(Oth_v, Idx_v).Valid then
            -- Valid code of the other running disparity: disparity error (ECSS 5.3.2g, h)
            Res_v.Char    := DecTable_c(Oth_v, Idx_v).Char;
            Res_v.K       := DecTable_c(Oth_v, Idx_v).K;
            Res_v.Rd      := DecTable_c(Oth_v, Idx_v).Rd;
            Res_v.DispErr := '1';
        else
            Res_v.CodeErr := '1';
        end if;
        return Res_v;
    end function;

end package body;
