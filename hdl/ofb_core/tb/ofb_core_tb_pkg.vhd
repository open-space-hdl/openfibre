---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the core testbench: two cores A (0) and B (1) connected
-- through the behavioural Physical adapter model, packet and broadcast generators and receivers
-- on the AXI4-Stream ports, AXI4-Lite masters for the MIB.
--
-- Documentation: hdl/ofb_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
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
        Packets  : natural;  -- Packets requested (the sequencer increments it)
        MaxLen   : positive; -- Maximum packet length in bytes
        ReadyPct : natural;  -- Ready of the receiver, percent
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

    constant CoreCfgDefault_c : CoreCfg_t := (Vc       => (others => (Packets => 0, MaxLen => 64, ReadyPct => 100)),
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

end package;
