#!/usr/bin/env python3
"""Update sources.json from Amp's official Desktop and CLI releases."""

import argparse
import base64
from email.parser import Parser
import json
from pathlib import Path
import subprocess
from urllib.request import urlopen


def cli_source(source):
    with urlopen("https://static.ampcode.com/cli/cli-version.txt", timeout=60) as response:
        version = response.read().decode().strip()
    if version == source["version"]:
        return source
    url = f"https://static.ampcode.com/cli/{version}/amp-{source['platform']}.gz"
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        check=True, stdout=subprocess.PIPE, text=True,
    )
    return {**source, "version": version, "hash": json.loads(result.stdout)["hash"]}


def desktop_source(source):
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
    return {
        "version": version,
        "arch": arch,
        "hash": "sha256-" + base64.b64encode(digest).decode(),
    }


def main():
    path = Path(__file__).resolve().parents[2] / "sources.json"
    current = json.loads(path.read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", choices=current["sources"])
    parser.add_argument("system", choices=current["sources"]["desktop"]["platforms"])
    args = parser.parse_args()
    platforms = current["sources"][args.package]["platforms"]
    source = platforms[args.system]
    updated = cli_source(source) if args.package == "cli" else desktop_source(source)
    if updated == source:
        print(f"{args.package} {args.system} is already up to date ({source['version']})")
        return
    platforms[args.system] = updated
    path.write_text(json.dumps(current, indent=2) + "\n")
    print(f"Updated {args.package} {args.system}: {source['version']} -> {updated['version']}")


if __name__ == "__main__":
    main()
