# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VSG lint of all OpenFibre VHDL files with the Open Logic rule set.

Usage: python lint/lint.py [--fix] [files...]
  --fix  apply the safe automatic fixes of lint/config/fix_only_openfibre.yml first
Exit code 0 when all files are clean (no errors, no warnings).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "lint" / "config" / "vsg_config.yml"
FIX_ONLY = ROOT / "lint" / "config" / "fix_only_openfibre.yml"


def find_vsg():
    # "python -m vsg" silently does nothing on some installations, use the executable
    exe = shutil.which("vsg")
    if exe:
        return exe
    candidate = Path(sys.executable).parent / "Scripts" / "vsg.exe"
    if candidate.exists():
        return str(candidate)
    raise SystemExit("vsg executable not found (pip install vsg==3.27)")


def vhdl_files():
    files = sorted((ROOT / "hdl").rglob("*.vhd")) + sorted((ROOT / "tb").rglob("*.vhd"))
    return [str(f.relative_to(ROOT)) for f in files]


def main():
    args = sys.argv[1:]
    fix = "--fix" in args
    files = [a for a in args if a != "--fix"] or vhdl_files()
    vsg = find_vsg()
    os.chdir(ROOT)
    if fix:
        # Several passes: VSG fixes phase by phase
        for _ in range(3):
            subprocess.run([vsg, "-c", str(CONFIG), "--fix", "--fix_only", str(FIX_ONLY), "-f", *files],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    result = subprocess.run([vsg, "-c", str(CONFIG), "--all_phases", "-of", "summary", "-f", *files],
                            capture_output=True, text=True, check=False)
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
