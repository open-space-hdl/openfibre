# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Simulations with the AMD transceiver model (Physical adapter PA-1, VCK190 reference design).

Usage: python tools/run_xsim.py [--clean] [testbench ...]

Creates the transceiver wizard instance ofb_gtw with Vivado (hdl/ofb_pa_gty/tcl/ofb_gtw.tcl) and exports its
simulation sources (once, in vivado_out/ofb_pa_gty), compiles them, Open Logic and the OpenFibre sources with the AMD
simulator (xsim) and runs the testbenches (default: all of TESTBENCHES). A testbench passes when its log contains "Simulation done"
and no line with "FAIL" or an error. The Vivado installation is taken from VIVADO_PATH (default D:/AMD/2025.2/Vivado).
"""

import os
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "hdl" / "ofb_pa_gty"
# Target-specific modules (not in component_list.txt), compiled after the modules of component_list.txt
TARGET_MODULES = ("hdl/ofb_pa_gty", "hdl/ofb_vck190")
OUT = ROOT / "vivado_out" / "ofb_pa_gty"
VIVADO = Path(os.environ.get("VIVADO_PATH", "D:/AMD/2025.2/Vivado"))
PART = "xcvc1902-vsva2197-2MP-e-S"
REFCLK_MHZ = "156.25"

# Testbench entities (hdl/<module>/tb/<name>.vhd)
TESTBENCHES = ("ofb_pa_gty_tb", "ofb_pa_gty_cc_tb", "ofb_pa_gty_core_tb", "ofb_vck190_tb")

# Open Logic areas compiled into the library olo
OLO_AREAS = ("base", "axi", "intf", "ft")


def tool(name):
    exe = VIVADO / "bin" / (name + (".bat" if os.name == "nt" else ""))
    if not exe.exists():
        raise SystemExit(f"{exe} not found (set VIVADO_PATH)")
    return str(exe)


def run(cmd, cwd, log):
    with open(cwd / log, "w", encoding="utf-8") as f:
        # stdin closed: with an inherited stdin, export_simulation writes vlog.prj to stdout
        result = subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        text = (cwd / log).read_text(encoding="utf-8", errors="replace").splitlines()
        print("\n".join(text[-30:]), flush=True)
        raise SystemExit(f"{' '.join(cmd[:2])} failed, see {cwd / log}")


def generate_ip():
    export = OUT / "export" / "ofb_gtw" / "xsim"
    if (export / "vlog.prj").exists():
        return export
    OUT.mkdir(parents=True, exist_ok=True)
    script = OUT / "generate.tcl"
    script.write_text(
        f"create_project -force ip {OUT.as_posix()}/project -part {PART}\n"
        f"source {(MODULE / 'tcl' / 'ofb_gtw.tcl').as_posix()}\n"
        f"ofb_gtw_create ofb_gtw {REFCLK_MHZ}\n"
        "generate_target all [get_ips ofb_gtw]\n"
        "export_simulation -of_objects [get_files ofb_gtw.xci] -simulator xsim "
        f"-directory {(OUT / 'export').as_posix()} -force\n",
        encoding="utf-8")
    run([tool("vivado"), "-mode", "batch", "-nojournal", "-nolog", "-source", str(script)], OUT, "generate.log")
    return export


def olo_files():
    files = []
    for line in (ROOT / "open-logic" / "compile_order.txt").read_text().splitlines():
        rel = line.strip()
        if rel and rel.split("/")[1] in OLO_AREAS:
            files.append(str(ROOT / "open-logic" / rel))
    return files


def module_files():
    files = []
    modules = [line.strip() for line in (ROOT / "component_list.txt").read_text().splitlines()]
    for name in [m for m in modules if m and not m.startswith("#")] + list(TARGET_MODULES):
        files += sorted(str(f) for f in (ROOT / name / "src").glob("*.vhd"))
    return files


def dependency_order(files):
    """Files ordered so that every file follows the files defining the units it uses from the library work."""
    defines = {}
    uses = {}
    for f in files:
        text = Path(f).read_text(encoding="utf-8", errors="replace")
        for unit in re.findall(r"^\s*(?:entity|package)\s+(\w+)\s+is\b", text, re.IGNORECASE | re.MULTILINE):
            defines[unit.lower()] = f
        uses[f] = {u.lower() for u in re.findall(r"\bwork\.(\w+)", text, re.IGNORECASE)}
    ordered = []
    done = set()

    def visit(f, stack):
        if f in done:
            return
        if f in stack:
            raise SystemExit(f"circular dependency at {f}")
        for unit in sorted(uses[f]):
            dep = defines.get(unit)
            if dep and dep != f:
                visit(dep, stack | {f})
        done.add(f)
        ordered.append(f)

    for f in files:
        visit(f, set())
    return ordered


def compile_vhdl(export, lib, files, log):
    run([tool("xvhdl"), "--2008", "--relax", "-work", lib] + files, export, log)


def compile_all(export, tbs):
    if not (export / ".ip_compiled").exists():
        run([tool("xvlog"), "--incr", "--relax", "-prj", "vlog.prj"], export, "compile_ip.log")
        compile_vhdl(export, "olo", olo_files(), "compile_olo.log")
        (export / ".ip_compiled").touch()
    files = module_files()
    for tb in tbs:
        found = sorted(ROOT.glob(f"hdl/*/tb/{tb}.vhd"))
        if not found:
            raise SystemExit(f"testbench {tb} not found")
        files.append(str(found[0]))
    compile_vhdl(export, "xil_defaultlib", dependency_order(files), "compile_ofb.log")


def simulate(export, tb):
    libs = []
    for lib in ("xil_defaultlib", "olo", "gt_quad_base_v1_1_20", "gtwiz_versal_v1_0_5", "unisims_ver", "unisim",
                "unimacro_ver", "secureip", "xpm"):
        libs += ["-L", lib]
    run([tool("xelab"), "--relax", "--mt", "4"] + libs + ["--snapshot", tb, f"xil_defaultlib.{tb}",
                                                          "xil_defaultlib.glbl"], export, f"elaborate_{tb}.log")
    start = time.time()
    subprocess.run([tool("xsim"), tb, "-R", "-log", f"simulate_{tb}.log"], cwd=export, stdout=subprocess.DEVNULL,
                   stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    log = (export / f"simulate_{tb}.log").read_text(encoding="utf-8", errors="replace")
    failed = re.search(r"FAIL|Error:|Failure:|FATAL", log) is not None or "Simulation done" not in log
    for line in log.splitlines():
        if re.search(r"Note:|Warning:|Error:|Failure:|FAIL|Simulation done", line):
            print("  " + line.strip(), flush=True)
    print(f"{'fail' if failed else 'pass'} {tb} ({time.time() - start:.0f} s)", flush=True)
    return not failed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--clean" in sys.argv and OUT.exists():
        # Files copied from the Vivado installation (glbl.v) are read-only
        shutil.rmtree(OUT, onexc=lambda func, path, exc: (os.chmod(path, stat.S_IWRITE), func(path)))
    tbs = args or list(TESTBENCHES)
    export = generate_ip()
    compile_all(export, tbs)
    results = [simulate(export, tb) for tb in tbs]
    print(f"{sum(results)} of {len(results)} passed", flush=True)
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
