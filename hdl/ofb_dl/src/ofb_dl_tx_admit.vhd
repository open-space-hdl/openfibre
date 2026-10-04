---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Admission of new items into the error recovery buffer (DT-4 and the admission part of DT-5):
-- medium access among the VCs with a data segment ready (round robin, phase 2), copy of the data
-- segment, broadcast messages and FCT requests (round robin, ECSS 5.7.3.2d).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.3)

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
entity ofb_dl_tx_admit is
    generic (
        NumVc_g        : positive range 1 to 32 := 8;
        FreeWidth_g    : positive               := 10
    );
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        Cfg_FctMult    : in    std_logic_vector(2 downto 0);
        -- Output VC buffers
        Seg_Ready      : in    std_logic_vector(NumVc_g-1 downto 0);
        Seg_Words      : in    std_logic_vector(7*NumVc_g-1 downto 0);
        VcRd_Data      : in    std_logic_vector(32*NumVc_g-1 downto 0);
        VcRd_K         : in    std_logic_vector(4*NumVc_g-1 downto 0);
        VcRd_Valid     : in    std_logic_vector(NumVc_g-1 downto 0);
        VcRd_Ready     : out   std_logic_vector(NumVc_g-1 downto 0);
        -- Broadcast output buffer
        Bc_Data        : in    std_logic_vector(63 downto 0);
        Bc_Channel     : in    Char_t;
        Bc_Type        : in    Char_t;
        Bc_Delayed     : in    std_logic;
        Bc_Late        : in    std_logic;
        Bc_Valid       : in    std_logic;
        Bc_Ready       : out   std_logic;
        Bc_Credit      : in    std_logic;
        -- FCT requests of the input VC buffers
        Fct_Req        : in    std_logic_vector(NumVc_g-1 downto 0);
        Fct_Ack        : out   std_logic_vector(NumVc_g-1 downto 0);
        -- Error recovery buffer
        WrData_Data    : out   Word_t;
        WrData_K       : out   WordK_t;
        WrData_Valid   : out   std_logic;
        WrData_Commit  : out   std_logic;
        WrData_Vc      : out   std_logic_vector(4 downto 0);
        WrFct_Valid    : out   std_logic;
        WrFct_Vc       : out   std_logic_vector(4 downto 0);
        WrFct_Mult     : out   std_logic_vector(2 downto 0);
        WrBc_Valid     : out   std_logic;
        WrBc_Data      : out   std_logic_vector(63 downto 0);
        WrBc_Channel   : out   Char_t;
        WrBc_Type      : out   Char_t;
        WrBc_Delayed   : out   std_logic;
        WrBc_Late      : out   std_logic;
        Data_FreeWords : in    std_logic_vector(FreeWidth_g-1 downto 0);
        Data_ItemFree  : in    std_logic;
        Fct_ItemFree   : in    std_logic;
        Bc_ItemFree    : in    std_logic;
        Bc_Waiting     : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_tx_admit is

    signal Copying   : std_logic;
    signal CopyVc    : natural range 0 to NumVc_g-1;
    signal CopyLeft  : natural range 0 to MaxFrameWords_c;
    signal SegGrant  : std_logic_vector(NumVc_g-1 downto 0);
    signal SegValid  : std_logic;
    signal SegTake   : std_logic;
    signal FctGrant  : std_logic_vector(NumVc_g-1 downto 0);
    signal FctValid  : std_logic;
    signal FctTake   : std_logic;
    signal ArbRst    : std_logic;

    function oneHotIdx (oh : std_logic_vector) return natural is
        variable Idx_v : natural;
    begin
        Idx_v := 0;

        for i in oh'range loop
            if oh(i) = '1' then
                Idx_v := i;
            end if;
        end loop;

        return Idx_v;
    end function;

begin

    ArbRst <= Rst or Ctrl_LinkReset;

    -----------------------------------------------------------------------------------------------
    -- Data segments: round robin among the VCs with a segment ready, copy into the buffer
    -----------------------------------------------------------------------------------------------
    i_seg_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => NumVc_g
        )
        port map (
            Clk       => Clk,
            Rst       => ArbRst,
            In_Req    => Seg_Ready,
            Out_Grant => SegGrant,
            Out_Ready => SegTake,
            Out_Valid => SegValid
        );

    SegTake <= '1' when Copying = '0' and Data_ItemFree = '1' and unsigned(Data_FreeWords) /= 0 and
                        SegValid = '1' else '0';

    p_copy : process (Clk) is
        variable Vc_v    : natural range 0 to NumVc_g-1;
        variable Words_v : natural;
    begin
        if rising_edge(Clk) then
            if SegTake = '1' then
                Vc_v    := oneHotIdx(SegGrant);
                Words_v := to_integer(unsigned(Seg_Words(7*Vc_v+6 downto 7*Vc_v)));
                Words_v := minimum(Words_v, to_integer(unsigned(Data_FreeWords)));
                if Words_v > 0 then
                    Copying  <= '1';
                    CopyVc   <= Vc_v;
                    CopyLeft <= Words_v;
                end if;
            elsif Copying = '1' and VcRd_Valid(CopyVc) = '1' then
                CopyLeft <= CopyLeft - 1;
                if CopyLeft = 1 then
                    Copying <= '0';
                end if;
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Copying <= '0';
            end if;
        end if;
    end process;

    p_copy_out : process (all) is
    begin
        VcRd_Ready    <= (others => '0');
        WrData_Valid  <= '0';
        WrData_Commit <= '0';
        WrData_Data   <= VcRd_Data(32*CopyVc+31 downto 32*CopyVc);
        WrData_K      <= VcRd_K(4*CopyVc+3 downto 4*CopyVc);
        WrData_Vc     <= std_logic_vector(to_unsigned(CopyVc, 5));
        if Copying = '1' and VcRd_Valid(CopyVc) = '1' then
            VcRd_Ready(CopyVc) <= '1';
            WrData_Valid       <= '1';
            if CopyLeft = 1 then
                WrData_Commit <= '1';
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Broadcast messages: one waiting in the buffer at a time, only with broadcast credit
    -----------------------------------------------------------------------------------------------
    p_bc : process (all) is
    begin
        Bc_Ready   <= '0';
        WrBc_Valid <= '0';
        if Bc_Valid = '1' and Bc_Credit = '1' and Bc_ItemFree = '1' and Bc_Waiting = '0' then
            Bc_Ready   <= '1';
            WrBc_Valid <= '1';
        end if;
    end process;

    WrBc_Data    <= Bc_Data;
    WrBc_Channel <= Bc_Channel;
    WrBc_Type    <= Bc_Type;
    WrBc_Delayed <= Bc_Delayed;
    WrBc_Late    <= Bc_Late;

    -----------------------------------------------------------------------------------------------
    -- FCT requests: round robin among the input VC buffers
    -----------------------------------------------------------------------------------------------
    i_fct_arb : entity olo.olo_base_arb_rr
        generic map (
            Width_g => NumVc_g
        )
        port map (
            Clk       => Clk,
            Rst       => ArbRst,
            In_Req    => Fct_Req,
            Out_Grant => FctGrant,
            Out_Ready => FctTake,
            Out_Valid => FctValid
        );

    FctTake     <= FctValid and Fct_ItemFree;
    WrFct_Valid <= FctTake;
    WrFct_Vc    <= std_logic_vector(to_unsigned(oneHotIdx(FctGrant), 5));
    WrFct_Mult  <= Cfg_FctMult;
    Fct_Ack     <= FctGrant when FctTake = '1' else (others => '0');

end architecture;
