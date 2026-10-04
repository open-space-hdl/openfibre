---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Self test of the 8B/10B package of the verification components: known codes, disparity, round
-- trip of every character, inverted codes and error detection.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_8b10b_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_tb_8b10b_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_tb_8b10b_tb is

    -- Code written "abcdei fghj" (transmission order) as a Code_t (bit 0 = a)
    function fromAbc (s : string) return Code_t is
        variable Code_v : Code_t;
        variable Idx_v  : natural := 0;
    begin

        for i in s'range loop
            if s(i) = '0' or s(i) = '1' then
                Code_v(Idx_v) := '1' when s(i) = '1' else '0';
                Idx_v         := Idx_v + 1;
            end if;
        end loop;

        return Code_v;
    end function;

    function ones (code : Code_t) return natural is
        variable N_v : natural := 0;
    begin

        for i in code'range loop
            if code(i) = '1' then
                N_v := N_v + 1;
            end if;
        end loop;

        return N_v;
    end function;

begin

    p_main : process is
        variable Enc_v  : Encoded_t;
        variable Dec_v  : Decoded_t;
        variable Char_v : Char_t;
        variable Rd_v   : std_logic;
        variable K_v    : std_logic;
        variable Errs_v : natural;
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);

        while test_suite loop

            -- Codes from ECSS Tables 5-1 and 5-2
            if run("test_known_codes") then
                Enc_v := encode(K28_5_c, '1', '0');
                check_value(Enc_v.Code, fromAbc("001111 1010"), error, "K28.5 RD-");
                check_value(Enc_v.Rd, '1', error, "RD after K28.5 RD-");
                Enc_v := encode(K28_5_c, '1', '1');
                check_value(Enc_v.Code, fromAbc("110000 0101"), error, "K28.5 RD+");
                Enc_v := encode(K28_7_c, '1', '0');
                check_value(Enc_v.Code, fromAbc("001111 1000"), error, "K28.7 RD-");
                Enc_v := encode(x"00", '0', '0');
                check_value(Enc_v.Code, fromAbc("100111 0100"), error, "D0.0 RD-");
                Enc_v := encode(x"F1", '0', '0');
                check_value(Enc_v.Code, fromAbc("100011 0111"), error, "D17.7 RD- (alternate 0111)");
                Enc_v := encode(x"EB", '0', '1');
                check_value(Enc_v.Code, fromAbc("110100 1000"), error, "D11.7 RD+ (alternate 1000)");
                Enc_v := encode(K27_7_c, '1', '0');
                check_value(Enc_v.Code, fromAbc("110110 1000"), error, "K27.7 RD-");

            -- Every character encodes to a code with disparity 0 or +-2 and decodes back
            elsif run("test_round_trip") then
                Errs_v := 0;

                for rd in 0 to 1 loop

                    for c in 0 to 255 loop
                        Char_v := std_logic_vector(to_unsigned(c, 8));

                        for k in 0 to 1 loop
                            if k = 0 or isKcode(Char_v) then
                                Rd_v  := '1' when rd = 1 else '0';
                                K_v   := '1' when k = 1 else '0';
                                Enc_v := encode(Char_v, K_v, Rd_v);
                                if ones(Enc_v.Code) < 4 or ones(Enc_v.Code) > 6 then
                                    Errs_v := Errs_v + 1;
                                end if;
                                Dec_v := decode(Enc_v.Code, Rd_v);
                                if Dec_v.Char /= Char_v or (Dec_v.K = '1') /= (k = 1) or Dec_v.CodeErr = '1' or
                                   Dec_v.DispErr = '1' or Dec_v.Rd /= Enc_v.Rd then
                                    Errs_v := Errs_v + 1;
                                end if;
                            end if;
                        end loop;

                    end loop;

                end loop;

                check_value(Errs_v, 0, error, "Encode / decode mismatches");

            -- Inverted codes: K28.5 stays K28.5, INIT1 symbols become iINIT1 symbols (ECSS 5.3.3.5)
            elsif run("test_inversion") then
                Enc_v := encode(K28_5_c, '1', '0');
                Dec_v := decode(not Enc_v.Code, '1');
                check_value(Dec_v.Char, K28_5_c, error, "Inverted K28.5");
                check_value(Dec_v.K, '1', error, "Inverted K28.5 is a K-code");
                Enc_v := encode(SymLlcw_c, '0', '0');
                Dec_v := decode(not Enc_v.Code, '1');
                check_value(Dec_v.Char, SymInvLlcw_c, error, "Inverted D14.6 is D17.1");
                Enc_v := encode(SymInit1_c, '0', '0');
                Dec_v := decode(not Enc_v.Code, '0');
                check_value(Dec_v.Char, SymInvInit1_c, error, "Inverted D6.2 is D25.5");

            -- Wrong running disparity and invalid codes are detected
            elsif run("test_errors") then
                Enc_v := encode(x"00", '0', '0');
                Dec_v := decode(Enc_v.Code, '1');
                check_value(Dec_v.DispErr, '1', error, "D0.0 RD- code received with RD+");
                check_value(Dec_v.Char, x"00", error, "Character of the disparity error");
                Dec_v := decode("0000000000", '0');
                check_value(Dec_v.CodeErr, '1', error, "All zeros is not a code");

            end if;

        end loop;

        ofbTestEnd(runner);
        wait;
    end process;

end architecture;
