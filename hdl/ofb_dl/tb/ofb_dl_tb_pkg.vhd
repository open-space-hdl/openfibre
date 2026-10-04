---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the Data Link layer testbench: two ends A (0) and B (1),
-- each an ofb_dl on an ofb_multilane and an ofb_lane, connected through the behavioural Physical
-- adapter model. Packet generators and receivers per VC, broadcast generators and receivers, and a
-- scoreboard per destination.
--
-- Documentation: hdl/ofb_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_kword_sb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_dl_tb_pkg is

    constant TbNumVc_c : positive := 4;

    -- Packet generator and receiver of one VC
    type VcCfg_t is record
        Packets  : natural;  -- Packets requested (the sequencer increments it)
        MaxLen   : positive; -- Maximum packet length in bytes
        EepPct   : natural;  -- Packets terminated by EEP, percent
        GapPct   : natural;  -- Cycles with Valid low before a word, percent
        ReadyPct : natural;  -- Cycles with Ready high at the receiver, percent
    end record;

    constant VcCfgDefault_c : VcCfg_t := (Packets => 0, MaxLen => 64, EepPct => 0, GapPct => 0, ReadyPct => 100);

    type VcCfgArray_t is array (0 to TbNumVc_c-1) of VcCfg_t;

    -- Inputs of one end
    type EndCfg_t is record
        Vc            : VcCfgArray_t;
        BcSend        : natural; -- Broadcast messages requested
        LaneStart     : std_logic;
        LinkReset     : std_logic;
        DataScrambled : std_logic;
        BcInterval    : std_logic_vector(15 downto 0);
    end record;

    constant EndCfgDefault_c : EndCfg_t := (
        Vc            => (others => VcCfgDefault_c),
        BcSend        => 0,
        LaneStart     => '1',
        LinkReset     => '0',
        DataScrambled => '1',
        BcInterval    => x"0028"
    );

    type NatArray_t is array (0 to TbNumVc_c-1) of natural;

    -- Outputs of one end
    type EndStat_t is record
        Sent         : NatArray_t; -- Packets sent per VC
        RxWords      : NatArray_t; -- Words received per VC
        BcSent       : natural;
        BcRx         : natural;
        BcRxLate     : natural;
        LinkState    : std_logic_vector(1 downto 0);
        LaneActive   : std_logic;
        HasCredit    : std_logic_vector(TbNumVc_c-1 downto 0);
        ErbEmpty     : std_logic;
        Retries      : natural;
        Crc16Errs    : natural;
        Crc8Errs     : natural;
        FrameErrs    : natural;
        SeqErrs      : natural;
        ProtErrs     : natural;
        FarEndResets : natural;
        Overflows    : natural;
        CreditOvfs   : natural;
        BcDiscards   : natural;
    end record;

    type EndCfgArray_t is array (0 to 1) of EndCfg_t;
    type EndStatArray_t is array (0 to 1) of EndStat_t;

    signal DlCfg  : EndCfgArray_t := (others => EndCfgDefault_c);
    signal DlStat : EndStatArray_t;

    -- Scoreboard: VC words for end d and VC v in instance 1 + d * TbNumVc_c + v, broadcast messages
    -- for end d in instance 1 + 2 * TbNumVc_c + d (three elements per message)
    shared variable Sb_v : t_generic_sb;

    function sbVc (
        dst : natural;
        vc  : natural) return positive;

    function sbBc (dst : natural) return positive;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_dl_tb_pkg is

    function sbVc (
        dst : natural;
        vc  : natural) return positive is
    begin
        return 1 + dst * TbNumVc_c + vc;
    end function;

    function sbBc (dst : natural) return positive is
    begin
        return 1 + 2 * TbNumVc_c + dst;
    end function;

end package body;
