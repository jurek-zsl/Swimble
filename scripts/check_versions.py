#!/usr/bin/env python3
"""Reject a release whose UI and protocol advertise different app versions."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
rust = re.search(r'^version = "([^"]+)"', (root / 'rust-core/Cargo.toml').read_text(), re.M).group(1)
swift = re.search(r'CFBundleShortVersionString: "([^"]+)"', (root / 'MacClient/project.yml').read_text()).group(1)
if rust != swift:
    raise SystemExit(f'Version mismatch: Rust={rust}, app={swift}')
print(f'Versions match: {rust}')
