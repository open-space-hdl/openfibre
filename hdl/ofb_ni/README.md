# ofb_ni

Network interface of an OpenFibre node (ECSS-E-ST-50-11C clauses 5.8, 6.2 and 6.3): AXI4-Stream packet ports for every
virtual channel (NI-1: packets of bytes with `TKEEP`, `TLAST` and the EEP flag in `TUSER`, converted to and from the
N-Chars and Fills of the Data Link layer), broadcast messages (NI-3) and the schedule port (NI-4).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Packet conversion in both directions, alignment, framing checks, field mapping |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ofb_ni*"
```
