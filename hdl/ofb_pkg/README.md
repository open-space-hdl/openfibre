# ofb_pkg

Common package of OpenFibre: ECSS-E-ST-50-11C characters, word format, control words, CRC-16 and CRC-8, the
PRBS of idle frames and data scrambling, and the settings of the Open Logic CRC and PRBS entities that reproduce
them.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Package structure, data formats, CRC and PRBS mapping |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_pkg*"
```

| File | Content |
| --- | --- |
| `tb/ofb_pkg_tb.vhd` | VUnit testbench with the test cases of the verification plan |
| `tb/ofb_pkg_th.vhd` | Harness: `olo_base_crc` and `olo_base_prbs` with the package settings, AXI-Stream VVCs |
