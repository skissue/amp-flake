#!/usr/bin/env python3
"""Update sources.json from Amp's official stable Debian repository."""

import argparse
import base64
from email.parser import Parser
import json
from pathlib import Path
from urllib.request import urlopen


def main():
    path = Path(__file__).resolve().parents[2] / "sources.json"
    current = json.loads(path.read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("system", choices=current["sources"])
    system = parser.parse_args().system
    source = current["sources"][system]
    arch = source["arch"]
    url = f"https://static.ampcode.com/linux/dists/stable/main/binary-{arch}/Packages"
    with urlopen(url, timeout=60) as response:
        index = response.read().decode()
    packages = [Parser().parsestr(entry) for entry in index.strip().split("\n\n")]
    package, = [
        entry for entry in packages
        if entry["Package"] == "amp-desktop" and entry["Architecture"] == arch
    ]
    version = package["Version"]
    expected_filename = f"{version}/amp-desktop-{version}-{arch}.deb"
    if package["Filename"] != expected_filename:
        raise ValueError(f"Unexpected package filename for {arch}: {package['Filename']}")
    digest = bytes.fromhex(package["SHA256"])
    if len(digest) != 32:
        raise ValueError(f"Invalid SHA256 for {arch}")
    updated = {
        "version": version,
        "arch": arch,
        "hash": "sha256-" + base64.b64encode(digest).decode(),
    }
    if updated == source:
        print(f"{system} is already up to date ({version})")
        return
    current["sources"][system] = updated
    path.write_text(json.dumps(current, indent=2) + "\n")
    print(f"Updated {system}: {source['version']} -> {version}")


if __name__ == "__main__":
    main()
