---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants shared by the blocks of the Lane layer (lane state encoding, transmitter modes).
--
-- Documentation: hdl/ofb_lane/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_lane_pkg is

    -- Lane state as reported to the Multi-Lane layer and the MIB (ECSS Figure 5-29)
    subtype LaneState_t is std_logic_vector(3 downto 0);
    constant LaneStateClearLine_c      : LaneState_t := x"0";
    constant LaneStateDisabled_c       : LaneState_t := x"1";
    constant LaneStateWait_c           : LaneState_t := x"2";
    constant LaneStateStarted_c        : LaneState_t := x"3";
    constant LaneStateInvertRxPol_c    : LaneState_t := x"4";
    constant LaneStateConnecting_c     : LaneState_t := x"5";
    constant LaneStateConnected_c      : LaneState_t := x"6";
    constant LaneStateActive_c         : LaneState_t := x"7";
    constant LaneStatePrepareStandby_c : LaneState_t := x"8";
    constant LaneStateLossOfSignal_c   : LaneState_t := x"9";

    -- Mode of the lane transmitter (LN-2), set by the lane initialisation state machine (LN-1)
    subtype TxMode_t is std_logic_vector(2 downto 0);
    constant TxModeOff_c        : TxMode_t := "000";
    constant TxModeInit1_c      : TxMode_t := "001";
    constant TxModeInit2_c      : TxMode_t := "010";
    constant TxModeInit3_c      : TxMode_t := "011";
    constant TxModeActive_c     : TxMode_t := "100";
    constant TxModeStandby_c    : TxMode_t := "101";
    constant TxModeLostSignal_c : TxMode_t := "110";

end package;
