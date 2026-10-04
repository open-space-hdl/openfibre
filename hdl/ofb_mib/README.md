# ofb_mib

Management Information Base of OpenFibre (ECSS-E-ST-50-11C clauses 5.9 and 6.5): configuration and status parameters
of all layers in a register file with an AXI4-Lite port (MG-1), sticky error flags, event counters and an interrupt
(MG-2), with the crossings between the management clock and the clock domains of the layers. The register map is in
[architecture.md](docs/architecture.md).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Crossings, register file, register map |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_mib*"
```
