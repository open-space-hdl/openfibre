# ofb_core

OpenFibre core: a SpaceFibre node interface (ECSS-E-ST-50-11C) from the AXI4-Stream ports of the virtual channels and
broadcast messages down to the symbol stream of the Physical adapters, with the Management Information Base on
AXI4-Lite. It connects `ofb_ni`, `ofb_dl`, `ofb_multilane`, `ofb_lane` and `ofb_mib` and contains the crossing between
the core and the lane clock (`ofb_core_cc`) and the reset generators. This issue implements one lane.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements, generics |
| [architecture.md](docs/architecture.md) | Structure, crossings, resets |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_core*"
```
