---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Control of the behavioural model of ofb_pa_gty (architecture mdl): one record per instance,
-- selected by the generic ModelIdx_g, with the times of the reset sequence and the channel effects of
-- the transmitted lanes. A testbench assigns the signal PaModelCtrl; the defaults give a correct link.
-- The receive word buffer of the model (one per instance) is also declared here.
--
-- Documentation: hdl/ofb_pa_gty/docs/model.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package ofb_pa_model_pkg is

    constant PaModelInstances_c : positive := 8; -- ModelIdx_g 0 to 7
    constant PaModelLanes_c     : positive := 4;

    -- Channel effects of the transmitted bits of one lane
    type PaModelLane_t is record
        TxInvert  : boolean;  -- transmitted pair crossed (P and N swapped)
        SkewUi    : natural;  -- additional delay of the transmitted bits, in unit intervals
        Idle      : boolean;  -- loss of signal: electrical idle on the pins
        ErrReq    : natural;  -- every increment inverts one bit of the next transmitted word
        BurstReq  : natural;  -- every increment sets BurstLen consecutive bits of the next word to '0' (dropout)
        BurstLen  : positive; -- 1 to 40
        ErrEvery  : natural;  -- 0: off, else one inverted bit every ErrEvery transmitted bits
        -- Receiver side: every increment forces an error of the receive buffer of this lane (PA-RS-03)
        BufErrReq : natural;
    end record;

    type PaModelLaneArray_t is array (0 to PaModelLanes_c-1) of PaModelLane_t;

    -- Behaviour of Phy_NoSignal: NoSignalNever as struct (always 0: the transceiver gives no loss of signal
    -- indication; an idle line gives words with code errors and then words that are not lane words, as the receiver
    -- of the transceiver); NoSignalLine follows the line (1 after the line has been idle for NoSignalDelay), for a
    -- Physical adapter with a loss of signal indication
    type PaNoSignalMode_t is (NoSignalNever, NoSignalLine);

    -- Times of the reset sequence. A sequence starts at the end of the stretched reset (RstPulseCycles_g), but not
    -- before PowerUpTime after the start of the simulation (power-up of the transceiver)
    type PaModelCtrl_t is record
        -- Earliest start of a reset sequence, after the start of the simulation
        PowerUpTime   : time;
        -- Transmit reset done of the previous start still 1 after the end of the stretched reset, at most until
        -- LaneClk starts
        TxDoneStale   : time;
        -- LaneClk starts (transmit PLL locked), after the start of the sequence
        ClkDelay      : time;
        -- Stat_TxReady, LaneRst released, after the start of the sequence (later than ClkDelay)
        TxReadyDelay  : time;
        -- Stat_RxReady, after Stat_TxReady
        RxReadyDelay  : time;
        -- The receiver decodes this long after the first transition of a signal at its pins
        CdrLockTime   : time;
        -- Behaviour of Phy_NoSignal
        NoSignalMode  : PaNoSignalMode_t;
        -- NoSignalLine: Phy_NoSignal after the line became idle; NoSignalNever: start of the idle line words
        NoSignalDelay : time;
        Lane          : PaModelLaneArray_t;
    end record;

    constant PaModelLaneDefault_c : PaModelLane_t := (
        TxInvert => false,
        SkewUi   => 0,
        Idle     => false,
        ErrReq   => 0,
        BurstReq => 0,
        BurstLen => 8,
        ErrEvery => 0,
        BufErrReq => 0
    );

    -- Reset sequence of the transceiver model in the AMD simulator (ofb_pa_gty_core_tb, model.md section 3)
    constant PaModelCtrlDefault_c : PaModelCtrl_t := (
        PowerUpTime   => 43.715 us,
        TxDoneStale   => 27.9 us,
        ClkDelay      => 20.381 us,
        TxReadyDelay  => 21.16 us,
        RxReadyDelay  => 3.34 us,
        CdrLockTime   => 16.83 us,
        NoSignalMode  => NoSignalNever,
        NoSignalDelay => 100 ns,
        Lane          => (others => PaModelLaneDefault_c)
    );

    type PaModelCtrlArray_t is array (0 to PaModelInstances_c-1) of PaModelCtrl_t;

    signal PaModelCtrl : PaModelCtrlArray_t := (others => PaModelCtrlDefault_c);

    -- Received word of one lane: four symbols (symbol 0 in bits 7:0), flags per symbol
    type PaModelWord_t is record
        Data    : std_logic_vector(31 downto 0);
        K       : std_logic_vector(3 downto 0);
        CodeErr : std_logic_vector(3 downto 0);
        DispErr : std_logic_vector(3 downto 0);
    end record;

    -- Receive buffers of the lanes of one instance (written by the bit receiver, read in LaneClk)
    constant PaModelBufDepth_c : positive := 64;

    type PaModelBuffer_t is protected

        procedure clear (lane : natural);

        procedure push (lane : natural; word : PaModelWord_t);

        procedure pop (lane : natural; word : out PaModelWord_t);
        impure function peek (lane : natural) return PaModelWord_t;
        impure function level (lane : natural) return natural;
    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body ofb_pa_model_pkg is

    type PaModelBuffer_t is protected body

        type Ring_t is array (0 to PaModelBufDepth_c-1) of PaModelWord_t;
        type Rings_t is array (0 to PaModelLanes_c-1) of Ring_t;
        type Index_t is array (0 to PaModelLanes_c-1) of natural;

        variable Ring_v  : Rings_t;
        variable Head_v  : Index_t := (others => 0); -- next read
        variable Count_v : Index_t := (others => 0);

        procedure clear (lane : natural) is
        begin
            Head_v(lane)  := 0;
            Count_v(lane) := 0;
        end procedure;

        -- A word for a full buffer is lost (the receiver reports the overflow)
        procedure push (lane : natural; word : PaModelWord_t) is
        begin
            if Count_v(lane) < PaModelBufDepth_c then
                Ring_v(lane)((Head_v(lane) + Count_v(lane)) mod PaModelBufDepth_c) := word;
                Count_v(lane)                                                      := Count_v(lane) + 1;
            end if;
        end procedure;

        procedure pop (lane : natural; word : out PaModelWord_t) is
        begin
            word          := Ring_v(lane)(Head_v(lane));
            Head_v(lane)  := (Head_v(lane) + 1) mod PaModelBufDepth_c;
            Count_v(lane) := Count_v(lane) - 1;
        end procedure;

        impure function peek (lane : natural) return PaModelWord_t is
        begin
            return Ring_v(lane)(Head_v(lane));
        end function;

        impure function level (lane : natural) return natural is
        begin
            return Count_v(lane);
        end function;

    end protected body;

end package body;
