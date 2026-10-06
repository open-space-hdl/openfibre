# ofb_pkg: Specification

## 1. Overview

`ofb_pkg` is the common package of OpenFibre. It defines the characters, word format and control words of
ECSS-E-ST-50-11C clause 5.3, the CRC algorithms of clauses 5.7.6.4 and 5.7.6.5, and the PRBS of clause 5.7.6.2, so
that every layer and every testbench uses one definition. It also fixes the generics with which the Open Logic
entities `olo_base_crc` and `olo_base_prbs` reproduce the ECSS algorithms.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| PKG-01 | The package shall define the data value of every K-code used by SpaceFibre (K0.0, K28.0, K28.2, K28.3, K28.5, K28.7, K27.7, K29.7, K30.7) and of every control word symbol (Table 5-12). | 5.3.11a, 5.3.12a, 5.3.7.1b, c, 5.3.7.2a |
| PKG-02 | A word shall consist of four characters with one K flag each; character 0 occupies bits 7:0, is the least significant character and is sent first. | 5.3.3.2a and the corresponding clauses of every control word |
| PKG-03 | The package shall define the fixed control words SKIP, IDLE, INIT1, INIT2, iINIT1, iINIT2, PAD, RETRY and RXERR. | 5.3.3.2 to 5.3.3.7, 5.3.4.4, 5.3.5.3.5, 5.3.6c |
| PKG-04 | The package shall provide functions that build the parameterised control words INIT3, STANDBY, LOST_SIGNAL, ACTIVE, ALIGN, SDF, EDF, SBF, EBF, SIF, FCT, ACK, NACK and FULL. Functions of words with an 8-bit CRC over their first three characters (SIF, FCT, ACK, NACK, FULL) shall compute that CRC. | 5.3.3.8 to 5.3.3.10, 5.3.4.2, 5.3.4.3, 5.3.5.1.3 to 5.3.5.1.7, 5.3.5.2, 5.3.5.3.2 to 5.3.5.3.4 |
| PKG-05 | The package shall define the fields INIT3 capability bits, LOS_Cause values, EBF status flags and the sequence number polarity bit. | 5.3.3.8e, 5.3.3.10f, 5.3.5.1.6c, 5.3.5.1.2a |
| PKG-06 | The package shall provide a CRC-16 update function: polynomial x^16 + x^12 + x^5 + 1, seed 0xFFFF, least significant bit of each character first, data value of K-codes. | 5.7.6.4c, d, f, g, h |
| PKG-07 | The package shall provide a CRC-8 update function: polynomial x^8 + x^2 + x + 1, seed 0x00, bit order and result mapping of clause 5.7.6.5e. | 5.7.6.5c to f |
| PKG-08 | The package shall define generics for `olo_base_crc` that compute PKG-06 and PKG-07. | 5.7.6.4, 5.7.6.5 |
| PKG-09 | The package shall provide a reference implementation of the random number generator G(x) = x^16 + x^5 + x^4 + x^3 + 1 with seed 0xFFFF, the first bit being the least significant bit of character 0. | 5.7.6.2.1b, c, f, 5.7.6.2.3c, d, e, g |
| PKG-10 | The package shall define generics for `olo_base_prbs` (32 bits per symbol) that produce the sequence of PKG-09. | 5.7.6.2.1, 5.7.6.2.3 |
| PKG-11 | The module shall provide `ofb_cc_pulse`, a pulse clock domain crossing with single-cycle output pulses: free of latches, state registers triplicated with majority voters, level crossings with `olo_ft_cc_bits`, resets of both sides coupled with `olo_ft_cc_reset`. Every input pulse shall give exactly one output pulse within 3 input plus 4 output clock cycles when the pulses of one bit are at least 5 input plus 5 output clock cycles apart; one further pulse during a transfer shall be stored and sent afterwards. | none (implementation) |

## 3. Error conditions

None. The package contains constants and pure functions. `ofb_cc_pulse` merges the pulses of one bit that arrive
during a transfer into one pending pulse (closer than 5 input plus 5 output clock cycles, after the first pending
one); pulses during the reset of either side, including the synchronised release, are dropped.

## 4. Configuration parameters

None.
