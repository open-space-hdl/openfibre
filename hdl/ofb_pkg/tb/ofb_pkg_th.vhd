---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of ofb_pkg: the Open Logic CRC and PRBS entities configured with the ofb_pkg
-- constants, connected to AXI-Stream VVCs.
--
-- Documentation: hdl/ofb_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library olo;

library work;
    use work.ofb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_pkg_th is
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of ofb_pkg_th is

    -- VVC instance indices
    constant VvcPrbs_c     : natural := 0;
    constant VvcCrc16In_c  : natural := 1;
    constant VvcCrc16Out_c : natural := 2;
    constant VvcCrc8In_c   : natural := 3;
    constant VvcCrc8Out_c  : natural := 4;

    constant ClkPeriod_c : time := 10 ns;

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    -- PRBS
    signal Prbs_Data  : std_logic_vector(31 downto 0);
    signal Prbs_Valid : std_logic;
    signal Prbs_Ready : std_logic;

    -- CRC-16
    signal Crc16In_Data   : std_logic_vector(31 downto 0);
    signal Crc16In_Keep   : std_logic_vector(3 downto 0);
    signal Crc16In_Last   : std_logic;
    signal Crc16In_Valid  : std_logic;
    signal Crc16In_Ready  : std_logic;
    signal Crc16Out_Crc   : std_logic_vector(15 downto 0);
    signal Crc16Out_Valid : std_logic;
    signal Crc16Out_Ready : std_logic;

    -- CRC-8
    signal Crc8In_Data   : std_logic_vector(31 downto 0);
    signal Crc8In_Keep   : std_logic_vector(3 downto 0);
    signal Crc8In_Last   : std_logic;
    signal Crc8In_Valid  : std_logic;
    signal Crc8In_Ready  : std_logic;
    signal Crc8Out_Crc   : std_logic_vector(7 downto 0);
    signal Crc8Out_Valid : std_logic;
    signal Crc8Out_Ready : std_logic;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_rst : process is
    begin
        Rst <= '1';
        wait for 10 * ClkPeriod_c;
        wait until rising_edge(Clk);
        Rst <= '0';
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- PRBS
    -----------------------------------------------------------------------------------------------
    i_prbs : entity olo.olo_base_prbs
        generic map (
            Polynomial_g    => PrbsPolynomial_c,
            Seed_g          => PrbsSeed_c,
            BitsPerSymbol_g => 32
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            Out_Data  => Prbs_Data,
            Out_Ready => Prbs_Ready,
            Out_Valid => Prbs_Valid
        );

    -- No data while in reset: the slave VVC must not see the reset state as a word
    i_prbs_vvc : entity work.ofb_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcPrbs_c,
            DataWidth_g   => 32
        )
        port map (
            Clk      => Clk,
            In_Data  => Prbs_Data,
            In_Valid => Prbs_Valid and not Rst,
            In_Ready => Prbs_Ready
        );

    -----------------------------------------------------------------------------------------------
    -- CRC-16
    -----------------------------------------------------------------------------------------------
    i_crc16_in : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => VvcCrc16In_c,
            DataWidth_g   => 32
        )
        port map (
            Clk       => Clk,
            Out_Data  => Crc16In_Data,
            Out_User  => open,
            Out_Keep  => Crc16In_Keep,
            Out_Last  => Crc16In_Last,
            Out_Valid => Crc16In_Valid,
            Out_Ready => Crc16In_Ready
        );

    i_crc16 : entity olo.olo_base_crc
        generic map (
            DataWidth_g     => 32,
            Polynomial_g    => Crc16Polynomial_c,
            InitialValue_g  => Crc16Seed_c,
            BitOrder_g      => CrcBitOrder_c,
            ByteOrder_g     => CrcByteOrder_c,
            BitflipOutput_g => CrcBitflipOutput_c
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Data   => Crc16In_Data,
            In_Valid  => Crc16In_Valid,
            In_Ready  => Crc16In_Ready,
            In_Last   => Crc16In_Last,
            In_Be     => Crc16In_Keep,
            Out_Crc   => Crc16Out_Crc,
            Out_Valid => Crc16Out_Valid,
            Out_Ready => Crc16Out_Ready
        );

    i_crc16_out : entity work.ofb_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcCrc16Out_c,
            DataWidth_g   => 16
        )
        port map (
            Clk      => Clk,
            In_Data  => Crc16Out_Crc,
            In_Valid => Crc16Out_Valid,
            In_Ready => Crc16Out_Ready
        );

    -----------------------------------------------------------------------------------------------
    -- CRC-8
    -----------------------------------------------------------------------------------------------
    i_crc8_in : entity work.ofb_tb_axis_master
        generic map (
            InstanceIdx_g => VvcCrc8In_c,
            DataWidth_g   => 32
        )
        port map (
            Clk       => Clk,
            Out_Data  => Crc8In_Data,
            Out_User  => open,
            Out_Keep  => Crc8In_Keep,
            Out_Last  => Crc8In_Last,
            Out_Valid => Crc8In_Valid,
            Out_Ready => Crc8In_Ready
        );

    i_crc8 : entity olo.olo_base_crc
        generic map (
            DataWidth_g     => 32,
            Polynomial_g    => Crc8Polynomial_c,
            InitialValue_g  => Crc8Seed_c,
            BitOrder_g      => CrcBitOrder_c,
            ByteOrder_g     => CrcByteOrder_c,
            BitflipOutput_g => CrcBitflipOutput_c
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Data   => Crc8In_Data,
            In_Valid  => Crc8In_Valid,
            In_Ready  => Crc8In_Ready,
            In_Last   => Crc8In_Last,
            In_Be     => Crc8In_Keep,
            Out_Crc   => Crc8Out_Crc,
            Out_Valid => Crc8Out_Valid,
            Out_Ready => Crc8Out_Ready
        );

    i_crc8_out : entity work.ofb_tb_axis_slave
        generic map (
            InstanceIdx_g => VvcCrc8Out_c,
            DataWidth_g   => 8
        )
        port map (
            Clk      => Clk,
            In_Data  => Crc8Out_Crc,
            In_Valid => Crc8Out_Valid,
            In_Ready => Crc8Out_Ready
        );

end architecture;
