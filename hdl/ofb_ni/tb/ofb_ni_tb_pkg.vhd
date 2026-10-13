---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the Network interface testbench: queues of the drivers,
-- scoreboard instances, settings of the random handshakes and event counters.
--
-- Documentation: hdl/ofb_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.ofb_tb_queue_pkg.all;
    use work.ofb_tb_kword_sb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_ni_tb_pkg is

    -- Number of VCs of the DUT
    constant NiVc_c : positive := 2;

    -- Queue entry (BeatEntry_t of ofb_tb_queue_pkg): data 127:0 (bytes or characters of a beat), TKEEP or K
    -- flags 143:128, TLAST 144, TUSER 145
    subtype NiEntry_t is BeatEntry_t;

    -- Queues: packets to send of VC v in queue v, rows from the Data Link layer of VC v in queue
    -- NiVc_c + v
    shared variable NiQueue_v : BeatQueues_t;

    -- Scoreboard: rows to the Data Link layer of VC v (K flags and word, word 0 first) in instance
    -- 1 + v; bytes to the user of VC v in instance 1 + NiVc_c + v (byte 7:0, last byte of the packet
    -- 32, EEP 33)
    shared variable NiSb_v : t_generic_sb;

    -- Random handshakes in percent: valid of the drivers, ready of the receivers
    type NiHandshake_t is record
        TxValid : natural; -- User packets to send
        TxReady : natural; -- Data Link layer, transmit
        RxValid : natural; -- Data Link layer, receive
        RxReady : natural; -- User, received packets
    end record;

    signal NiHs : NiHandshake_t := (TxValid => 100, TxReady => 100, RxValid => 100, RxReady => 100);

    -- Events per VC and beats handed over (throughput)
    type NiCount_t is array (0 to NiVc_c-1) of natural;

    signal NiTxErrCnt  : NiCount_t := (others => 0);
    signal NiRxErrCnt  : NiCount_t := (others => 0);
    signal NiEmptyCnt  : NiCount_t := (others => 0);
    signal NiTxRowCnt  : NiCount_t := (others => 0);
    signal NiRxBeatCnt : NiCount_t := (others => 0);

end package;
