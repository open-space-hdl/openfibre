---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stimulus and observation objects of the row-level testbench of the Data Link layer: one ofb_dl,
-- the testbench is the far end at the row interface (words injected into the receive rows, every
-- transmitted word logged, optional automatic acknowledgement).
--
-- Documentation: hdl/ofb_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.ofb_pkg.all;
    use work.ofb_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_dl_row_tb_pkg is

    constant RowNumVc_c : positive := 2;

    -- Far end and environment controlled by the sequencer
    type RowCfg_t is record
        LaneActive : std_logic;
        AutoCap    : boolean;   -- Send a capability event with LinkResetFlag when the DUT checks the far end
        AutoAck    : boolean;   -- Acknowledge every data frame, broadcast frame and FCT received in sequence
        TxReadyPct : natural;   -- Ready of the transmit rows, percent
        LinkReset  : std_logic;
        IfReset    : std_logic; -- Interface Reset (level)
        BcInterval : std_logic_vector(15 downto 0);
        TxLogOn    : boolean;   -- Log the transmitted words
        RxReadyPct : natural;   -- Ready of the receive VC ports, percent
        BcReady    : std_logic; -- Ready of the receive broadcast port
    end record;

    constant RowCfgDefault_c : RowCfg_t := (
        LaneActive => '1',
        AutoCap    => true,
        AutoAck    => true,
        TxReadyPct => 100,
        LinkReset  => '0',
        IfReset    => '0',
        BcInterval => x"0004",
        TxLogOn    => true,
        RxReadyPct => 100,
        BcReady    => '1'
    );

    signal RowCfg : RowCfg_t := RowCfgDefault_c;

    -- Status of the DUT and of the far-end model
    type RowStat_t is record
        LinkState    : std_logic_vector(1 downto 0);
        RxErrState   : std_logic_vector(1 downto 0);
        WordIdState  : std_logic_vector(2 downto 0);
        ErbEmpty     : std_logic;
        HasCredit    : std_logic_vector(RowNumVc_c-1 downto 0);
        FarRxSeq     : natural;   -- Sequence count accepted by the far-end model
        FarPol       : std_logic; -- Polarity expected by the far-end model
        Retries      : natural;
        Crc16Errs    : natural;
        Crc8Errs     : natural;
        FrameErrs    : natural;
        SeqErrs      : natural;
        ProtErrs     : natural;
        CreditOvfs   : natural;
        InputOvfs    : natural;
        FarEndResets : natural;
        BcRx         : natural;
        BcDiscards   : natural;
        BwUnder      : std_logic_vector(RowNumVc_c-1 downto 0);
    end record;

    signal RowStat : RowStat_t;

    -- Far-end polarity set by the sequencer (after it sends a NACK)
    signal FarPolCmd : std_logic := '0';

    -- Broadcast message port of the DUT (UserClk), count of received messages
    signal BcTxData    : std_logic_vector(63 downto 0) := (others => '0');
    signal BcTxChannel : Char_t                        := x"00";
    signal BcTxType    : Char_t                        := x"00";
    signal BcTxReq     : natural                       := 0; -- Messages requested
    signal BcRxCount   : natural                       := 0;

    -- Register writes of the MIB (core clock) and SCHEDULE.request (user clock): the sequencer sets
    -- address and data, then increments the counter (at least 4 core clock cycles apart)
    signal RegWrAddr : natural                       := 0;
    signal RegWrData : std_logic_vector(31 downto 0) := (others => '0');
    signal RegWrCnt  : natural                       := 0;
    signal SchedSlot : std_logic_vector(5 downto 0)  := (others => '0');
    signal SchedCnt  : natural                       := 0;

    -- Words injected into the receive rows: bit 36 is the CRC-16 error flag of an EDF

    shared variable RxQueue_v : WordQueue_t;

    -- Transmitted words of the DUT
    shared variable TxLog_v : WordLog_t;

    -- Words for the transmit VC ports and words received on the receive VC ports
    shared variable VcTxQueue0_v : WordQueue_t;
    shared variable VcTxQueue1_v : WordQueue_t;
    shared variable VcRxLog0_v   : WordLog_t;
    shared variable VcRxLog1_v   : WordLog_t;

end package;
