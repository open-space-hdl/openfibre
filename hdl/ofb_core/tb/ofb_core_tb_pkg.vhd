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
library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.ofb_tb_pkg.all;
    use work.ofb_tb_kword_sb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_core_tb_pkg is

    constant CoreNumVc_c : positive := 4;

    -- Packet generator and receiver of one VC
    type CoreVcCfg_t is record
        Packets    : natural;  -- Packets requested (the sequencer increments it)
        MinLen     : positive; -- Minimum packet length in bytes
        MaxLen     : positive; -- Maximum packet length in bytes
        ReadyPct   : natural;  -- Ready of the receiver, percent
        LenClasses : boolean;  -- Packet lengths cycle through the length classes of CovPkt_v
    end record;

    type CoreVcCfgArray_t is array (0 to CoreNumVc_c-1) of CoreVcCfg_t;

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
    type CoreVcCount_t is array (0 to 1, 0 to CoreNumVc_c-1) of natural;

    signal CoreRxEep   : CoreVcCount_t := (others => (others => 0));
    signal CoreRxLost  : CoreVcCount_t := (others => (others => 0));
    -- Words received with at least one N-Char, per core and VC (throughput measurement)
    signal CoreRxWords : CoreVcCount_t := (others => (others => 0));
    type CoreCount_t is array (0 to 1) of natural;

    signal CoreBcLost : CoreCount_t := (others => 0);

    -- Raw words for VC 0 of core A (sent before the generated packets of VC 0)
    shared variable RawQueue_v : WordQueue_t;

    -- Scoreboard: words for core d and VC v in instance 1 + d * CoreNumVc_c + v, broadcast messages
    -- for core d in instance 1 + 2 * CoreNumVc_c + d (three elements per message)
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
    procedure coreCovInit;

    -- Coverage summary of the coverpoints into the log
    procedure coreCovReport;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_core_tb_pkg is

    procedure coreCovInit is
    begin
        CovPkt_v.set_name("CovPkt");
        CovPkt_v.add_cross(bin_range(0, 1, 0), bin_range(0, CoreNumVc_c-1, 0),
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
