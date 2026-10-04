---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Input VC buffer of the Data Link layer (DR-6): buffer from the core clock to the user clock, FCT
-- requests for the space of the buffer (ECSS 5.7.3.2) and the EEP after link reset (ECSS 5.7.2.3d).
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.9)

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
entity ofb_dl_vc_in is
    generic (
        Depth_g : positive := 256 -- Words, multiple of 64
    );
    port (
        -- Core clock side
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        In_Data        : in    Word_t;
        In_K           : in    WordK_t;
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        Fct_Req        : out   std_logic; -- At least one FCT is to be sent
        Fct_Ack        : in    std_logic; -- One FCT was taken for sending
        -- User clock side
        UserClk        : in    std_logic;
        UserRst        : in    std_logic;
        Out_Data       : out   Word_t;
        Out_K          : out   WordK_t;
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_vc_in is

    constant Blocks_c   : positive := Depth_g / MaxFrameWords_c;
    constant GuardCyc_c : positive := 16;

    -- EEP followed by three Fills
    constant WordEep_c : Word_t := CharFill_c & CharFill_c & CharFill_c & CharEep_c;

    signal FifoRst  : std_logic;
    signal FifoIn   : std_logic_vector(35 downto 0);
    signal FifoOut  : std_logic_vector(35 downto 0);
    signal FifoVld  : std_logic;
    signal FifoRdy  : std_logic;
    signal UsrRstIn : std_logic;

    -- Core side
    signal Pending : natural range 0 to Blocks_c;
    signal Guard   : natural range 0 to GuardCyc_c;
    signal BlkCore : std_logic;

    -- User side
    signal LastEnd  : std_logic;
    signal Inject   : std_logic;
    signal RdCnt    : natural range 0 to MaxFrameWords_c-1;
    signal BlkUser  : std_logic;
    signal OutValid : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Buffer
    -----------------------------------------------------------------------------------------------
    FifoRst <= Rst or Ctrl_LinkReset;
    FifoIn  <= In_K & In_Data;

    i_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g => 36,
            Depth_g => Depth_g
        )
        port map (
            In_Clk     => Clk,
            In_Rst     => FifoRst,
            In_Data    => FifoIn,
            In_Valid   => In_Valid,
            In_Ready   => In_Ready,
            Out_Clk    => UserClk,
            Out_Rst    => UserRst,
            Out_RstOut => UsrRstIn,
            Out_Data   => FifoOut,
            Out_Valid  => FifoVld,
            Out_Ready  => FifoRdy
        );

    -----------------------------------------------------------------------------------------------
    -- User side: EEP after link reset, count of the words read
    -----------------------------------------------------------------------------------------------
    p_user : process (UserClk) is
    begin
        if rising_edge(UserClk) then
            BlkUser <= '0';
            if Inject = '1' then
                if Out_Ready = '1' then
                    Inject  <= '0';
                    LastEnd <= '1';
                end if;
            elsif FifoVld = '1' and Out_Ready = '1' then
                if wordLastIsEnd(FifoOut(31 downto 0), FifoOut(35 downto 32)) then
                    LastEnd <= '1';
                else
                    LastEnd <= '0';
                end if;
                if RdCnt = MaxFrameWords_c-1 then
                    RdCnt   <= 0;
                    BlkUser <= '1';
                else
                    RdCnt <= RdCnt + 1;
                end if;
            end if;
            -- Link reset (buffer reset seen on the user side)
            if UsrRstIn = '1' then
                RdCnt <= 0;
                if LastEnd = '0' then
                    Inject <= '1';
                end if;
            end if;
            if UserRst = '1' then
                LastEnd <= '1';
                Inject  <= '0';
                RdCnt   <= 0;
                BlkUser <= '0';
            end if;
        end if;
    end process;

    OutValid  <= Inject or FifoVld;
    Out_Valid <= OutValid;
    Out_Data  <= WordEep_c when Inject = '1' else FifoOut(31 downto 0);
    Out_K     <= "1111" when Inject = '1' else FifoOut(35 downto 32);
    FifoRdy   <= Out_Ready and not Inject;

    i_blk_cc : entity olo.olo_ft_cc_pulse
        generic map (
            NumPulses_g => 1
        )
        port map (
            In_Clk       => UserClk,
            In_RstIn     => UserRst,
            In_Pulse(0)  => BlkUser,
            Out_Clk      => Clk,
            Out_RstIn    => Rst,
            Out_Pulse(0) => BlkCore
        );

    -----------------------------------------------------------------------------------------------
    -- Core side: FCTs to send
    -----------------------------------------------------------------------------------------------
    p_fct : process (Clk) is
        variable Inc_v : boolean;
        variable Dec_v : boolean;
    begin
        if rising_edge(Clk) then
            Inc_v := BlkCore = '1' and Guard = 0;
            Dec_v := Fct_Ack = '1' and Pending > 0;
            if Inc_v and not Dec_v and Pending < Blocks_c then
                Pending <= Pending + 1;
            elsif Dec_v and not Inc_v then
                Pending <= Pending - 1;
            end if;
            if Guard > 0 then
                Guard <= Guard - 1;
            end if;
            -- After link reset the whole buffer is free; pulses of words read before are ignored
            if Rst = '1' or Ctrl_LinkReset = '1' then
                Pending <= Blocks_c;
                Guard   <= GuardCyc_c;
            end if;
        end if;
    end process;

    Fct_Req <= '1' when Pending > 0 else '0';

end architecture;
