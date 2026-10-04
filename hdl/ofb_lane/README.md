# ofb_lane

Lane layer of OpenFibre for one lane (ECSS-E-ST-50-11C clause 5.5): lane initialisation and standby state machine
(LN-1), transmitter (LN-2), receiver with word synchronisation and RXERR word counter (LN-3) and parallel loopback
(LN-4). It connects the Multi-Lane layer (words of 32 bits with 4 K flags) to a Physical adapter (decoded symbols).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machines |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_lane*"
```

| File | Content |
| --- | --- |
| `tb/ofb_lane_tb.vhd`, `tb/ofb_lane_th.vhd`, `tb/ofb_lane_tb_pkg.vhd` | Layer testbench: two lane ends through the behavioural Physical adapter model |
| `tb/ofb_lane_init_tb.vhd`, `tb/ofb_lane_init_th.vhd`, `tb/ofb_lane_init_tb_pkg.vhd` | Unit testbench of the initialisation state machine |
| `tb/ofb_lane_rx_tb.vhd`, `tb/ofb_lane_rx_th.vhd`, `tb/ofb_lane_rx_tb_pkg.vhd` | Unit testbench of the receiver |
| `tb/ofb_lane_tx_tb.vhd`, `tb/ofb_lane_tx_th.vhd`, `tb/ofb_lane_tx_tb_pkg.vhd` | Unit testbench of the transmitter |
