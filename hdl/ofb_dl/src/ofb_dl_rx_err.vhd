---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receive error state machine of the Data Link layer (DR-3, ECSS 5.7.7.3): determines the Receive
-- Polarity Flag from the ACK and NACK requests and from sequence errors.
--
-- Documentation: hdl/ofb_dl/docs/architecture.md (section 3.7)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity ofb_dl_rx_err is
    port (
        -- Control Ports
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        Ctrl_LinkReset : in    std_logic;
        -- Requests and errors of the receive checks (one cycle)
        Ev_AckReq      : in    std_logic;
        Ev_NackReq     : in    std_logic;
        Ev_SeqErrSame  : in    std_logic; -- Sequence count error with the polarity of the flag
        -- Receive Polarity Flag (0: positive)
        RxPolarity     : out   std_logic;
        -- State for status and test: 0 Valid Positive, 1 Valid Negative, 2 Error Positive, 3 Error Negative
        Stat_State     : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of ofb_dl_rx_err is

    type RxErrFsm_t is (ValidPos_s, ValidNeg_s, ErrorPos_s, ErrorNeg_s);

    signal State : RxErrFsm_t;

begin

    p_fsm : process (Clk) is
    begin
        if rising_edge(Clk) then

            case State is
                when ValidPos_s =>
                    if Ev_NackReq = '1' then
                        State <= ErrorNeg_s;
                    end if;
                when ValidNeg_s =>
                    if Ev_NackReq = '1' then
                        State <= ErrorPos_s;
                    end if;
                when ErrorPos_s =>
                    if Ev_AckReq = '1' then
                        State <= ValidPos_s;
                    elsif Ev_SeqErrSame = '1' then
                        State <= ErrorNeg_s;
                    end if;
                when ErrorNeg_s =>
                    if Ev_AckReq = '1' then
                        State <= ValidNeg_s;
                    elsif Ev_SeqErrSame = '1' then
                        State <= ErrorPos_s;
                    end if;
                -- coverage off
                when others =>
                    State <= ValidPos_s;
                -- coverage on
            end case;

            if Rst = '1' or Ctrl_LinkReset = '1' then
                State <= ValidPos_s;
            end if;
        end if;
    end process;

    RxPolarity <= '1' when State = ValidNeg_s or State = ErrorNeg_s else '0';

    with State select Stat_State <=
        "00" when ValidPos_s,
        "01" when ValidNeg_s,
        "10" when ErrorPos_s,
        "11" when others;

end architecture;
