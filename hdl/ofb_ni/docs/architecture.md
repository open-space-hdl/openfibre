# ofb_ni: Architecture and Design Description

## 1. Block diagram

```text
            User (UserClk, AXI4-Stream)                          Data Link layer (UserClk side of the buffers)
  S_Vc_* (x NumVc) --> ofb_ni_vc: framing check, register -->   TxVc_*
  M_Vc_* (x NumVc) <------------------------------------------- RxVc_*
  S_Bc_*           --> field mapping ------------------------->  TxBc_*
  M_Bc_*           <-- field mapping --------------------------  RxBc_*
```

## 2. ofb_ni_vc (NI-1)

A combinational check of the words of the input beat, word 0 first, followed by an `olo_base_pl_stage` of the beat:

1. Characters are scanned from 0 to 3. An EOP or EEP sets the end flag of the word; a Fill is always accepted; a data
   character is accepted before the end marker. Any other character (second end marker, other K-code, data after the
   end marker) is the first offending character: it becomes an EEP when the packet has not ended yet, otherwise a Fill,
   and all following characters become Fills (`Ev_FrameErr`).
2. After a framing error, when the last character of the original word is not an EOP, EEP or Fill (the user's packet
   continues), the spill state replaces the following words, also those of the same beat, by words of four Fills up to
   and including the next word with an EOP or EEP. The spill state passes from beat to beat.
3. A beat of words of four Fills only (after the spill replacement) is accepted from the user and dropped.

The Fill rule of ECSS 5.3.7.2c (Fills only between an end marker and the next data character) is not checked: Fills
inside a packet are passed through and do not disturb the far end.

## 3. Broadcast port (NI-3)

Field mapping only: `TUSER` bits 7:0 channel, 15:8 B_TYPE, 16 DELAYED, 17 LATE (receive direction).

## 4. Timing

Transmit latency one cycle (register stage); receive direction combinational.
