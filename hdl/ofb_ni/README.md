# ofb_ni

Network interface of an OpenFibre node (ECSS-E-ST-50-11C clauses 5.8, 6.2 and 6.3): AXI4-Stream ports for the N-Chars
of every virtual channel (NI-1, with a check of the packet framing) and for broadcast messages (NI-3). The virtual
network mapper (NI-2) and the schedule port (NI-4) follow in phase 3.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Framing check, field mapping |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_ni*"
```
