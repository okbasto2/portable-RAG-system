"""
install-heavy-deps.py
Checks for and installs heavy Python packages (torch, torchvision) that are
excluded from the portable zip to keep it under the 2 GB GitHub Releases limit.
Run by start-project.bat on first launch.
"""
import importlib
import subprocess
import sys
import os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PYTHON = os.path.join(HERE, "apps", "python_env", "python.exe")

HEAVY_PACKAGES = [
    ("torch", "torch==2.12.1"),
    ("torchvision", "torchvision==0.27.1"),
]


def check_and_install():
    missing = []
    for import_name, pip_spec in HEAVY_PACKAGES:
        try:
            importlib.import_module(import_name)
        except ImportError:
            missing.append(pip_spec)

    if not missing:
        return

    print("=" * 52)
    print("  First-run: Installing heavy dependencies...")
    print("  This only happens once (may take a few minutes).")
    print("=" * 52)
    print()
    for pkg in missing:
        print(f"  Installing {pkg}...")

    cmd = [PYTHON, "-m", "pip", "install"] + missing + ["--no-warn-script-location"]
    result = subprocess.run(cmd, cwd=HERE)

    if result.returncode == 0:
        print()
        print("  [OK] Heavy dependencies installed successfully.")
        print()
    else:
        print()
        print("  [ERROR] Failed to install some packages. Check your internet connection.")
        print(f"  You can retry manually: {PYTHON} -m pip install {' '.join(missing)}")
        print()
        sys.exit(1)


if __name__ == "__main__":
    check_and_install()
