# ofb_multilane

Multi-Lane layer of OpenFibre (ECSS-E-ST-50-11C clause 5.6). This issue implements the Multi-Lane bypass for one lane
(ECSS 5.6.3) with the complete column codec: data scrambling (ML-3) and unscrambling (ML-4) and the data frame CRC-16
per lane, and the lane manager (ML-1) for one lane. Rows over 2 to 4 lanes and lane alignment follow in phase 4.

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
