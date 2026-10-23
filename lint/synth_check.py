# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenFibre with GHDL: elaborates ofb_core into a netlist for 1 to 4 lanes and for the boundaries
of its other generic ranges (1 and 32 VCs, the smallest buffers, no PRBS words in the lane initialisation, the
alignment watchdog off and at the bounds of its range).

Usage: python lint/synth_check.py
Uses the libraries compiled by the regression runner (run `python run.py --compile` first).
Exit code 0 when every configuration synthesizes without error and without inferred latch, and every generic value
outside the ranges of the core is rejected at elaboration with the message of its check.
This is a technology-independent check of synthesizability; resources and timing need the FPGA tools.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
CONFIGS = [("ofb_core", {"NumLanes_g": lanes, "VcInDepth_g": 256 * lanes}) for lanes in (1, 2, 3, 4)] + [
    ("ofb_core", {"NumLanes_g": 1, "NumVc_g": 1}),
    ("ofb_core", {"NumLanes_g": 4, "NumVc_g": 32, "VcInDepth_g": 1024}),
    # Smallest buffers: output VC buffer 64 words, input VC buffer 64 words with one lane and 128 words per lane with
    # several lanes, error recovery buffer 64 rows
    ("ofb_core", {"NumLanes_g": 1, "VcOutDepth_g": 64, "VcInDepth_g": 64, "ErbRows_g": 64}),
    ("ofb_core", {"NumLanes_g": 4, "VcOutDepth_g": 16, "VcInDepth_g": 512, "ErbRows_g": 64}),
    ("ofb_core", {"NumLanes_g": 1, "InitPrbsWords_g": 0}),
    ("ofb_core", {"NumLanes_g": 2, "LaneStart_g": "true", "AutoStart_g": "false"}),
    # Alignment watchdog off and at the bounds of its range (the counters of the upper bound are 21 bits wide); the join
    # hold must not exceed the watchdog
    ("ofb_core", {"NumLanes_g": 2, "VcInDepth_g": 512, "AlignTimeoutWords_g": 0}),
    ("ofb_core", {"NumLanes_g": 2, "VcInDepth_g": 512, "AlignTimeoutWords_g": 1024, "LaneJoinHoldWords_g": 1024}),
    ("ofb_core", {"NumLanes_g": 4, "VcInDepth_g": 1024, "AlignTimeoutWords_g": 1000000}),
    # Reset value of the initialisation timeout at the bounds of its range (LANE_INIT_TIMEOUT, 24 bits)
    ("ofb_core", {"NumLanes_g": 1, "InitTimeoutWords_g": 1}),
    ("ofb_core", {"NumLanes_g": 1, "InitTimeoutWords_g": 16777215}),
]
# Values outside the generic ranges and the message of the check that rejects them
REJECTED = [
    ("ofb_core", {"NumLanes_g": 1, "VcOutDepth_g": 32}, "the output VC buffer must hold at least 64 words"),
    ("ofb_core", {"NumLanes_g": 2, "VcOutDepth_g": 16}, "the output VC buffer must hold at least 64 words"),
    ("ofb_core", {"NumLanes_g": 1, "VcInDepth_g": 96}, "Depth_g must be a multiple of 64 x NumLanes_g"),
    ("ofb_core", {"NumLanes_g": 1, "VcInDepth_g": 192}, "Depth_g / NumLanes_g must be a power of two"),
    ("ofb_core", {"NumLanes_g": 2, "VcInDepth_g": 128}, "Depth_g must be at least 128 x NumLanes_g"),
    ("ofb_core", {"NumLanes_g": 4, "VcInDepth_g": 256}, "Depth_g must be at least 128 x NumLanes_g"),
    ("ofb_core", {"NumLanes_g": 1, "VcOutDepth_g": 96}, "Depth_g must be a power of two"),
    ("ofb_core", {"NumLanes_g": 1, "ErbRows_g": 32}, "Rows_g must be at least 64"),
    ("ofb_core", {"NumLanes_g": 1, "ErbRows_g": 96}, "Rows_g must be a power of two"),
    ("ofb_core", {"NumLanes_g": 1, "AlignTimeoutWords_g": 1023},
     "AlignTimeoutWords_g must be 0 (off) or at least 1024"),
    ("ofb_core", {"NumLanes_g": 2, "VcInDepth_g": 512, "AlignTimeoutWords_g": 1023},
     "AlignTimeoutWords_g must be 0 (off) or at least 1024"),
]


def synth(top, generics, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openfibre",
           f"--workdir={LIBS / 'openfibre'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{key.removesuffix('_g')}{value}" for key, value in generics.items())
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}")
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def synth_rejected(top, generics, message, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openfibre",
           f"--workdir={LIBS / 'openfibre'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{key.removesuffix('_g')}{value}" for key, value in generics.items())
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    ok = res.returncode != 0 and message in res.stderr
    print(f"{name}: {'rejected as expected' if ok else 'NOT REJECTED'}")
    return ok


def main():
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    with tempfile.TemporaryDirectory() as tmp:
        results = [synth(top, gen, Path(tmp)) for top, gen in CONFIGS]
        results += [synth_rejected(top, gen, msg, Path(tmp)) for top, gen, msg in REJECTED]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
