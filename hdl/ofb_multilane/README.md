# ofb_multilane

Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6) for 1 to 4 lanes: lane manager with unidirectional and
hot redundant lanes (ML-1), row distributor (ML-2), column codec with data scrambling and the data frame CRC-16 per
lane (ML-3, ML-4), lane alignment (ML-5) and row concentrator (ML-6). With one lane it is the Multi-Lane bypass of
ECSS 5.6.3.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, pipelines |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_ml*" "*ofb_multilane*"
```

| File | Content |
| --- | --- |
| `tb/ofb_ml_tb_pkg.vhd` | Reference model and stimulus generator (streams of frames with the expected encoder and decoder output) |
| `tb/ofb_ml_codec_tb.vhd`, `tb/ofb_ml_codec_th.vhd`, `tb/ofb_ml_codec_tb_pkg.vhd` | Unit testbench of the column codec |
| `tb/ofb_multilane_tb.vhd`, `tb/ofb_multilane_th.vhd`, `tb/ofb_multilane_tb_pkg.vhd` | Layer testbench: two ends with Lane layers and the behavioural Physical adapter model |
| `tb/ofb_ml_align_tb.vhd` | Unit testbench of the lane alignment and the row concentrator (four lanes, words per lane) |
| `tb/ofb_ml_link_tb.vhd`, `tb/ofb_ml_link_th.vhd`, `tb/ofb_ml_link_tb_pkg.vhd` | Multi-lane link testbench (2 and 4 lanes, `tb/vunit_config.py`): traffic generator at row level, monitors of the received rows and of the words on the lanes |
