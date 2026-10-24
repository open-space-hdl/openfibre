---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the core testbench: two cores A (0) and B (1) connected
-- through the behavioural Physical adapter model, packet and broadcast generators and receivers
-- on the AXI4-Stream ports, AXI4-Lite masters for the MIB, functional coverage of the traffic.
--
-- Documentation: hdl/ofb_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_queue_pkg.all;
    use work.ofb_tb_kword_sb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_core_tb_pkg is

    -- Size of the arrays per VC; the testbench generic NumVc_g sets the VCs of the cores
    constant CoreMaxVc_c : positive := 32;

    -- Packet generator and receiver of one VC
    type CoreVcCfg_t is record
        Packets    : natural;  -- Packets requested (the sequencer increments it)
        MinLen     : positive; -- Minimum packet length in bytes
        MaxLen     : positive; -- Maximum packet length in bytes
        ReadyPct   : natural;  -- Ready of the receiver, percent
        LenClasses : boolean;  -- Packet lengths cycle through the length classes of CovPkt_v
    end record;

    type CoreVcCfgArray_t is array (0 to CoreMaxVc_c-1) of CoreVcCfg_t;

    type CoreCfg_t is record
        Vc       : CoreVcCfgArray_t;
        BcSend   : natural;
        SchedReq : natural;               -- SCHEDULE.requests (the sequencer increments it)
        Slot     : natural range 0 to 63; -- Time-slot of the SCHEDULE.request
        -- Lossy comparison: packets may be lost or end early with an EEP, broadcast messages may be
        -- lost (uncorrectable errors); every word received must still be correct
        Lossy    : boolean;
    end record;

    constant CoreVcCfgDefault_c : CoreVcCfg_t := (Packets    => 0,
                                                  MinLen     => 1,
                                                  MaxLen     => 64,
                                                  ReadyPct   => 100,
                                                  LenClasses => false);

    constant CoreCfgDefault_c : CoreCfg_t := (Vc       => (others => CoreVcCfgDefault_c),
                                             BcSend   => 0,
                                             SchedReq => 0,
                                             Slot     => 0,
                                             Lossy    => false);

    type CoreCfgArray_t is array (0 to 1) of CoreCfg_t;

    signal CoreCfg : CoreCfgArray_t := (others => CoreCfgDefault_c);

    -- Lossy comparison: packets received with an EEP at their end and packets lost, per core and VC
    type CoreVcCount_t is array (0 to 1, 0 to CoreMaxVc_c-1) of natural;

    signal CoreRxEep   : CoreVcCount_t := (others => (others => 0));
    signal CoreRxLost  : CoreVcCount_t := (others => (others => 0));
    -- Words of the received packets (four bytes, or the last bytes with the end marker), per core and
    -- VC (throughput measurement)
    signal CoreRxWords : CoreVcCount_t := (others => (others => 0));
    type CoreCount_t is array (0 to 1) of natural;

    signal CoreBcLost : CoreCount_t := (others => 0);

    -- Power-on reset of one core (in addition to the reset of the harness)
    signal CoreRstReq : std_logic_vector(0 to 1) := "00";

    -- A lane of the core has its transmitter, receiver or CDR enabled (all off in ClearLine and Disabled)
    signal CoreLaneOn : std_logic_vector(0 to 1);

    -- Transmitters of the Physical adapter ready, per core (Phy_TxReady; the harness registers it in the
    -- free-running MgmtClk, like Stat_TxReady of ofb_pa_gty in FreeRunClk)
    signal CoreTxReady : std_logic_vector(0 to 1) := "11";

    -- LaneClk and CoreClk of a core run ('1') or stand still ('0'); taken while the clock is low
    signal CoreLaneClkRun : std_logic_vector(0 to 1) := "11";
    signal CoreCoreClkRun : std_logic_vector(0 to 1) := "11";

    -- Interrupt outputs of the cores
    signal CoreIrq : std_logic_vector(0 to 1);

    -- Control of the Physical adapters at the ports of the cores (MIB PA_CTRL): PCSRSVDIN, and CDR hold, CDR-only and
    -- receiver reset on disconnection (bits 2:0)
    type CorePcs_t is array (0 to 1) of std_logic_vector(15 downto 0);
    type CorePaFlags_t is array (0 to 1) of std_logic_vector(2 downto 0);

    signal CorePaPcs   : CorePcs_t;
    signal CorePaFlags : CorePaFlags_t;

    -- Raw beats for VC 0 of core A in queue 0 (sent before the generated packets of VC 0): bytes 127:0
    -- (byte 0 in bits 7:0), TKEEP 143:128, TLAST 144, TUSER 145
    subtype RawBeat_t is BeatEntry_t;

    shared variable RawQueue_v : BeatQueues_t;

    -- Scoreboard: the words of the received packets for core d and VC v in instance 1 + d * CoreMaxVc_c
    -- + v (a packet as data words of four bytes and a last word with the remaining bytes, EOP or EEP and
    -- Fills: the N-Char representation of ECSS 5.3.7 from byte 0), broadcast messages for core d in
    -- instance 1 + 2 * CoreMaxVc_c + d (three elements per message)
    shared variable CoreSb_v : t_generic_sb;

    -- AXI4-Lite VVC instances of core A and B
    constant AxiA_c : natural := 1;
    constant AxiB_c : natural := 2;

    -- Functional coverage (UVVM), sampled by the receivers of the harness:
    -- CovPkt_v: packets ended with EOP per sending core (0, 1), VC and length class in bytes
    -- (1 to 4, 5 to 64, 65 to 256, 257 to 1024)
    -- CovEnd_v: end of the received packets per sending core (0: EOP, 1: EEP)
    -- CovBc_v:  broadcast messages per sending core and DELAYED flag
    -- CovLate_v: broadcast messages per sending core and LATE flag
    type LenClass_t is array (0 to 3) of positive;

    constant LenMin_c : LenClass_t := (1, 5, 65, 257);
    constant LenMax_c : LenClass_t := (4, 64, 256, 1024);

    shared variable CovPkt_v  : t_coverpoint;
    shared variable CovEnd_v  : t_coverpoint;
    shared variable CovBc_v   : t_coverpoint;
    shared variable CovLate_v : t_coverpoint;

    -- Bins of the coverpoints (called by the sequencer before the traffic starts)
    procedure coreCovInit (numVc : positive);

    -- Coverage summary of the coverpoints into the log
    procedure coreCovReport;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_core_tb_pkg is

    procedure coreCovInit (numVc : positive) is
    begin
        CovPkt_v.set_name("CovPkt");
        CovPkt_v.add_cross(bin_range(0, 1, 0), bin_range(0, numVc-1, 0),
                           bin_range(LenMin_c(0), LenMax_c(0)) & bin_range(LenMin_c(1), LenMax_c(1)) &
                           bin_range(LenMin_c(2), LenMax_c(2)) & bin_range(LenMin_c(3), LenMax_c(3)));
        CovEnd_v.set_name("CovEnd");
        CovEnd_v.add_cross(bin_range(0, 1, 0), bin_range(0, 1, 0));
        CovBc_v.set_name("CovBc");
        CovBc_v.add_cross(bin_range(0, 1, 0), bin_range(0, 1, 0));
        CovLate_v.set_name("CovLate");
        CovLate_v.add_cross(bin_range(0, 1, 0), bin_range(0, 1, 0));
    end procedure;

    procedure coreCovReport is
    begin
        CovPkt_v.report_coverage(VOID);
        CovEnd_v.report_coverage(VOID);
        CovBc_v.report_coverage(VOID);
        CovLate_v.report_coverage(VOID);
    end procedure;

end package body;
