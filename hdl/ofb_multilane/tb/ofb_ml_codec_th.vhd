---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the column codec: ofb_ml_col_enc and ofb_ml_col_dec, an AXI-Stream VVC for each
-- input, random back-pressure at the encoder output, loopback from the encoder to the decoder and
-- logs of both outputs.
--
-- Documentation: hdl/ofb_multilane/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_ml_codec_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_ml_codec_th is
    port (
        Clk : out   std_logic;
        Rst : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_ml_codec_th is

    constant ClkPeriod_c : time := 6.4 ns;

    signal ClkI : std_logic := '0';
    signal RstI : std_logic := '1';

    -- Encoder
    signal EncInData   : Word_t;
    signal EncInK      : WordK_t;
    signal EncInValid  : std_logic;
    signal EncInReady  : std_logic;
    signal EncOutData  : Word_t;
    signal EncOutK     : WordK_t;
    signal EncOutValid : std_logic;
    signal EncOutReady : std_logic;
    signal RandReady   : std_logic := '1';

    -- Decoder
    signal VvcDecData   : Word_t;
    signal VvcDecK      : WordK_t;
    signal VvcDecValid  : std_logic;
    signal DecInData    : Word_t;
    signal DecInK       : WordK_t;
    signal DecInValid   : std_logic;
    signal DecOutData   : Word_t;
    signal DecOutK      : WordK_t;
    signal DecOutCrcErr : std_logic;
    signal DecOutValid  : std_logic;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    ClkI <= not ClkI after ClkPeriod_c / 2;
    Clk  <= ClkI;
    Rst  <= RstI;

    p_rst : process is
    begin
        RstI <= '1';
        wait for 10 * ClkPeriod_c;
        wait until rising_edge(ClkI);
        RstI <= '0';
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Encoder
    -----------------------------------------------------------------------------------------------
    i_vvc_enc : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => VvcEnc_c,
            DataWidth_g   => 32,
            UserWidth_g   => 4
        )
        port map (
            Clk       => ClkI,
            Out_Data  => EncInData,
            Out_User  => EncInK,
            Out_Keep  => open,
            Out_Last  => open,
            Out_Valid => EncInValid,
            Out_Ready => EncInReady
        );

    i_enc : entity work.ofb_ml_col_enc
        port map (
            Clk          => ClkI,
            Rst          => RstI,
            Cfg_Scramble => CodecCtrl.Scramble,
            Ctrl_Flush   => CodecCtrl.Flush,
            In_Data      => EncInData,
            In_K         => EncInK,
            In_Valid     => EncInValid,
            In_Ready     => EncInReady,
            Out_Data     => EncOutData,
            Out_K        => EncOutK,
            Out_Valid    => EncOutValid,
            Out_Ready    => EncOutReady
        );

    -- Random back-pressure
    p_rand_ready : process (ClkI) is
        variable Seed1_v : positive := 17;
        variable Seed2_v : positive := 4711;
        variable Rand_v  : real;
    begin
        if rising_edge(ClkI) then
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Rand_v < 0.4 then
                RandReady <= '0';
            else
                RandReady <= '1';
            end if;
        end if;
    end process;

    EncOutReady <= '0' when CodecCtrl.HoldReady else
                   RandReady when CodecCtrl.RandomReady else
                   '1';

    p_enc_log : process (ClkI) is
    begin
        if rising_edge(ClkI) then
            if EncOutValid = '1' and EncOutReady = '1' then
                EncLog_v.push(EncOutK & EncOutData, '0');
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Decoder
    -----------------------------------------------------------------------------------------------
    i_vvc_dec : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => VvcDec_c,
            DataWidth_g   => 32,
            UserWidth_g   => 4
        )
        port map (
            Clk       => ClkI,
            Out_Data  => VvcDecData,
            Out_User  => VvcDecK,
            Out_Keep  => open,
            Out_Last  => open,
            Out_Valid => VvcDecValid,
            Out_Ready => '1'
        );

    DecInData  <= EncOutData when CodecCtrl.Loopback else VvcDecData;
    DecInK     <= EncOutK when CodecCtrl.Loopback else VvcDecK;
    DecInValid <= (EncOutValid and EncOutReady) when CodecCtrl.Loopback else VvcDecValid;

    i_dec : entity work.ofb_ml_col_dec
        port map (
            Clk            => ClkI,
            Rst            => RstI,
            Cfg_Unscramble => CodecCtrl.Unscramble,
            Ctrl_Flush     => CodecCtrl.Flush,
            In_Data        => DecInData,
            In_K           => DecInK,
            In_Valid       => DecInValid,
            Out_Data       => DecOutData,
            Out_K          => DecOutK,
            Out_CrcErr     => DecOutCrcErr,
            Out_Valid      => DecOutValid
        );

    p_dec_log : process (ClkI) is
        variable InValid_v : std_logic := '0';
    begin
        if rising_edge(ClkI) then
            if DecOutValid = '1' then
                DecLog_v.push(DecOutK & DecOutData, DecOutCrcErr);
            end if;
            -- Fixed latency of one cycle (ML-DEC-05)
            if RstI = '0' and DecOutValid /= InValid_v then
                alert(error, "Decoder output valid differs from the input valid of the previous cycle");
            end if;
            InValid_v := DecInValid;
        end if;
    end process;

end architecture;
