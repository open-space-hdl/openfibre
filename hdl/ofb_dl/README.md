# ofb_dl

Data Link layer of OpenFibre (ECSS-E-ST-50-11C clause 5.7): output and input VC buffers with FCT flow control,
broadcast messages with broadcast flow control, frames with sequence numbers and CRC-8, store-and-forward error
recovery buffer with ACK, NACK and RETRY, data word identification, receive error state machine and link reset. This
issue implements one lane and round-robin medium access (phase 2); quality of service follows in phase 3.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements, interpretation of the standard |
| [architecture.md](docs/architecture.md) | Blocks, error recovery buffer, transmit precedence rules |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_dl*"
```

| File | Content |
| --- | --- |
| `tb/ofb_dl_tb.vhd`, `tb/ofb_dl_th.vhd`, `tb/ofb_dl_tb_pkg.vhd` | Layer testbench: two ends with Multi-Lane and Lane layers through the behavioural Physical adapter model |
| `tb/ofb_dl_row_tb.vhd`, `tb/ofb_dl_row_th.vhd`, `tb/ofb_dl_row_tb_pkg.vhd` | Row-level testbench: the testbench is the far end at the row interface |
