# ofb_vck190: Hardware Test Procedure

## 1. Purpose

This procedure tests the reference design `ofb_vck190_top` on the AMD VCK190 evaluation board against SpaceFibre
test equipment (exit criterion of phase 2 in the [roadmap](../../../docs/roadmap.md)). It needs a host with Vivado
2025.2 and a synthesis licence for the XCVC1902; it does not need network access. The results go into
[verification_report.md](verification_report.md), section 3.

## 2. Material

| Item | Use |
| --- | --- |
| VCK190 evaluation board (production silicon), power supply, USB cable to the JTAG and UART port | Device under test |
| SpaceFibre test equipment with four lanes at 6.25 Gbit/s and a QSFP interface (for example STAR-Dundee) | Far end |
| QSFP cable (four lanes) | QSFP1 of the VCK190 to the far end |
| Vivado 2025.2 with a licence for the XCVC1902 | Build and programming |
| Repository bundle (section 3) | Sources |

## 3. Repository on a host without network access

The repository and its two submodules travel as Git bundles (`openfibre.bundle`, `open-logic.bundle`,
`uvvm.bundle`). On the build host:

```shell
git clone openfibre.bundle openfibre
cd openfibre
git config submodule.open-logic.url <path>/open-logic.bundle
git config submodule.uvvm.url <path>/uvvm.bundle
git -c protocol.file.allow=always submodule update --init
```

`git submodule status` must show the commits recorded in the repository without a leading `-` or `+`.

## 4. Build

```shell
vivado -mode batch -source hdl/ofb_vck190/tcl/build.tcl
```

The script creates the project in `vivado_out/ofb_vck190` with the transceiver wizard instance, the CIPS block design
(`ofb_cips`, JTAG boot, clocks of the programmable logic), the sources and the constraints, and runs synthesis,
implementation and the device image. On Windows the project path must not be longer than about 40 characters: the
device image step compiles the platform loader firmware in a deep directory below the project, and with a longer
path `write_device_image` fails ("opening dependency file ... No such file or directory"). Either clone the
repository to a short path (for example `C:/git/openfibre`) or set the environment variable `OFB_VIVADO_OUT` to a
short project directory (for example `C:/ofb`); the paths below are then relative to that directory. Record:

| Item | Where | Expected |
| --- | --- | --- |
| Device image | `vivado_out/ofb_vck190/ofb_vck190.runs/impl_1/*.pdi` | Present |
| Timing | `vivado_out/ofb_vck190/timing_summary.rpt` | WNS and WHS of all clocks at least 0 ns (`clk_pl_0` 100 MHz, `clk_pl_1` 150 MHz, lane clock 156.25 MHz) |
| Resources | `vivado_out/ofb_vck190/utilization.rpt` | LUT, register, block RAM and URAM count of `i_core` |
| Methodology and DRC | `report_methodology`, `report_drc` on the implemented design | No critical item about clock domain crossings or the transceivers |

A timing violation in a crossing between `clk_pl_0`, `clk_pl_1` and the lane clock points to a missing clock pair
constraint (section 4 of [architecture.md](architecture.md)). Expected warnings are listed in the verification
report, section 3.

## 5. Board set-up

1. Boot mode switch SW1 to JTAG (UG1366).
2. Reference clock: program the clock generator 8A34001 (U219) so that its output Q1, which drives MGTREFCLK1 of GTY
   quad 200, runs at 156.25 MHz. Use the clock tool of the system controller of the board (UG1366, Board Evaluation and
   Management Tool or system controller command line).
3. QSFP cable from QSFP1 of the VCK190 to the far end. Lane `i` of the design is channel `i` of quad 200.

## 6. Far-end configuration

| Parameter | Value |
| --- | --- |
| Line rate | 6.25 Gbit/s, 8B/10B, four lanes |
| Data scrambling | On (reset value of the design) |
| Virtual channels | 0 to 7 (the design has eight) |
| Link start | The far end starts its lanes (LaneStart); the design starts with AutoStart |
| Broadcast messages | Allowed on any channel |

## 7. Register access

The MIB registers are reachable over JTAG through the master port M_AXI_FPD of the CIPS at 0xA400_0000 (register
offset = address - 0xA400_0000, [register map](../../ofb_mib/docs/register_map.md)), without software on the
board. The script `hdl/ofb_vck190/tcl/xsdb_mib.tcl` provides the access and the bit error rate test in XSDB (Vivado
2025.2):

```tcl
xsdb% source hdl/ofb_vck190/tcl/xsdb_mib.tcl
xsdb% mib_connect
xsdb% mib_rd 0x000
0x0FB10006
xsdb% mib_rd 0x010
xsdb% prbs_ber 0 31 480
xsdb% prbs_off 0
```

`mib_connect` connects to the hardware server and selects the Versal device; the device image is programmed before
(Vivado Hardware Manager or `device program <image>.pdi` in XSDB). `mib_rd <offset>` and `mib_wr <offset> <value>`
read and write one register. `prbs_ber <lane> <pattern> <seconds>` runs the PRBS test of the user guide (section 6)
on one lane: pattern sent and checked, count reset, lock, measurement, bit error rate (upper bound at 95 %
confidence without error), then one forced error, which must be counted once. `prbs_off <lane>` ends the test; the
link of the lane is down while the test runs.

## 8. Tests

| Test | Steps | Pass criterion |
| --- | --- | --- |
| TC-VCK-HW-01 Link start | Program the device image (Vivado Hardware Manager); start the lanes of the far end | LED 0 (transmitters ready) and LED 1 (receivers ready) on after programming; LED 2 (all lanes aligned) and LED 3 (link initialised) on after the far end started; the far end reports the link up with four lanes |
| TC-VCK-HW-02 Echo | The far end sends 1000 packets of 1 to 1024 bytes with random content on each of the VCs 0 to 7 | Every packet comes back unchanged and in order on its VC; no error or retry at the far end |
| TC-VCK-HW-03 Broadcast | The far end sends 100 broadcast messages with random channel, B_TYPE and DELAYED flag | Every message comes back unchanged |
| TC-VCK-HW-04 Throughput | The far end sends packets of 1024 bytes continuously on all VCs and measures the received rate | About 90 % of 4 x 5 Gbit/s per direction (simulation: 90 % with traffic in both directions, the echo loads both) |
| TC-VCK-HW-05 Link reset | Link reset at the far end, then traffic as in TC-VCK-HW-02 | LED 3 goes off and on again; traffic afterwards correct |
| TC-VCK-HW-06 Lane failure | If the far end can disable a lane: disable lane 3 during traffic, enable it again | Traffic continues on three lanes without loss, the lane joins again |
| TC-VCK-HW-07 Error recovery | If the far end can inject errors: bit errors or corrupted frames during traffic | Every packet comes back unchanged; the far end counts the retries |
| TC-VCK-HW-08 Bit error rate | PRBS test of every lane with `prbs_ber` (section 7): PRBS-31 and PRBS-7 sent and checked, with a QSFP loopback module, with the far end (same pattern) or in the near-end serial loopback (LANE_CTRL bit 16); 480 s per lane and pattern | Checkers locked; no error (BER below 1e-12 at 95 % confidence); the forced error counted once |
| TC-VCK-HW-09 Register access | After TC-VCK-HW-01: `mib_rd 0x000`, `mib_rd 0x010`, `mib_rd 0x040`; `mib_wr 0x044 0x1`, `mib_rd 0x044` | ID 0x0FB10006; DL_STATUS bits 1:0 = 11 (link initialised); ML_STATUS shows four data-sending and data-receiving lanes; IRQ_MASK reads back 0x1 |

## 9. Limits of the reference design

- Register access needs the JTAG cable and XSDB; the design has no software and no other host interface.
- The design echoes what it receives. A far end that sends faster than it reads back sees back-pressure through the
  flow control of the link, not data loss.
