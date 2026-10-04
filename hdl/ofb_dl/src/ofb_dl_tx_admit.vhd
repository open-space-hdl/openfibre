---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Admission of new items into the error recovery buffer (DT-4 and the admission part of DT-5):
-- VC selected by the medium access controller, copy of the data segment (rows of NumLanes_g
-- words), broadcast messages and FCT requests (round robin, ECSS 5.7.3.2d).
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
        NumLanes_g     : positive range 1 to 4  := 1;
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
        Seg_Rows       : in    std_logic_vector(7*NumVc_g-1 downto 0);
        Vc_Flushed     : in    std_logic_vector(NumVc_g-1 downto 0); -- Output VC buffer flushed (continuous mode)
        -- Medium access controller
        Mac_Grant      : in    std_logic_vector(NumVc_g-1 downto 0);
        Mac_GrantValid : in    std_logic;
        Ev_SegSent     : out   std_logic;
        SegSent_Vc     : out   std_logic_vector(4 downto 0);
        SegSent_Rows   : out   std_logic_vector(6 downto 0);
        VcRd_Data      : in    std_logic_vector(32*NumLanes_g*NumVc_g-1 downto 0);
        VcRd_K         : in    std_logic_vector(4*NumLanes_g*NumVc_g-1 downto 0);
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
        WrData_Data    : out   std_logic_vector(32*NumLanes_g-1 downto 0);
        WrData_K       : out   std_logic_vector(4*NumLanes_g-1 downto 0);
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
        Data_FreeRows  : in    std_logic_vector(FreeWidth_g-1 downto 0);
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

    constant SettleCycles_c : natural  := 3;
    constant N_c            : positive := NumLanes_g;

    signal Copying  : std_logic;
    signal CopyDone : natural range 0 to MaxFrameWords_c;
    signal Settle   : natural range 0 to SettleCycles_c;
    signal CopyVc   : natural range 0 to NumVc_g-1;
    signal CopyLeft : natural range 0 to MaxFrameWords_c;
    signal SegGrant : std_logic_vector(NumVc_g-1 downto 0);
    signal SegValid : std_logic;
    signal SegTake  : std_logic;
    signal FctGrant : std_logic_vector(NumVc_g-1 downto 0);
    signal FctValid : std_logic;
    signal FctTake  : std_logic;
    signal ArbRst   : std_logic;

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
    -- Data segments: VC selected by the medium access controller, copy into the buffer. After a
    -- segment the next selection waits until the bandwidth credits are updated.
    -----------------------------------------------------------------------------------------------
    SegGrant <= Mac_Grant;
    SegValid <= Mac_GrantValid when (Mac_Grant and Seg_Ready) /= (Mac_Grant'range => '0') else '0';

    p_take : process (all) is
    begin
        SegTake <= '0';
        if Copying = '0' and Settle = 0 and Data_ItemFree = '1' and unsigned(Data_FreeRows) /= 0 and SegValid = '1' then
            SegTake <= '1';
        end if;
    end process;

    p_copy : process (Clk) is
        variable Vc_v   : natural range 0 to NumVc_g-1;
        variable Rows_v : natural;
    begin
        if rising_edge(Clk) then
            Ev_SegSent <= '0';
            if Settle > 0 then
                Settle <= Settle - 1;
            end if;
            if SegTake = '1' then
                Vc_v   := oneHotIdx(SegGrant);
                Rows_v := 0;

                for i in 0 to NumVc_g-1 loop
                    if i = Vc_v then
                        Rows_v := to_integer(unsigned(Seg_Rows(7*i+6 downto 7*i)));
                    end if;
                end loop;

                Rows_v := minimum(Rows_v, to_integer(unsigned(Data_FreeRows)));
                if Rows_v > 0 then
                    Copying  <= '1';
                    CopyVc   <= Vc_v;
                    CopyLeft <= Rows_v;
                    CopyDone <= 0;
                end if;
            elsif Copying = '1' and Vc_Flushed(CopyVc) = '1' then
                -- Buffer flushed in continuous mode: the words copied so far form the segment
                Copying      <= '0';
                Settle       <= SettleCycles_c;
                Ev_SegSent   <= '1';
                SegSent_Vc   <= std_logic_vector(to_unsigned(CopyVc, 5));
                SegSent_Rows <= std_logic_vector(to_unsigned(CopyDone, 7));
            elsif Copying = '1' and VcRd_Valid(CopyVc) = '1' then
                CopyLeft <= CopyLeft - 1;
                CopyDone <= CopyDone + 1;
                if CopyLeft = 1 then
                    Copying      <= '0';
                    Settle       <= SettleCycles_c;
                    Ev_SegSent   <= '1';
                    SegSent_Vc   <= std_logic_vector(to_unsigned(CopyVc, 5));
                    SegSent_Rows <= std_logic_vector(to_unsigned(CopyDone + 1, 7));
                end if;
            end if;
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Copying    <= '0';
                Settle     <= 0;
                Ev_SegSent <= '0';
            end if;
        end if;
    end process;

    p_copy_out : process (all) is
    begin
        VcRd_Ready    <= (others => '0');
        WrData_Valid  <= '0';
        WrData_Commit <= '0';
        WrData_Data   <= (others => '0');
        WrData_K      <= (others => '0');

        -- Row of the VC being copied
        for i in 0 to NumVc_g-1 loop
            if i = CopyVc then
                WrData_Data <= VcRd_Data(32*N_c*(i+1)-1 downto 32*N_c*i);
                WrData_K    <= VcRd_K(4*N_c*(i+1)-1 downto 4*N_c*i);
            end if;
        end loop;

        WrData_Vc <= std_logic_vector(to_unsigned(CopyVc, 5));
        if Copying = '1' and Vc_Flushed(CopyVc) = '1' then
            WrData_Commit <= '1';
        elsif Copying = '1' and VcRd_Valid(CopyVc) = '1' then
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
