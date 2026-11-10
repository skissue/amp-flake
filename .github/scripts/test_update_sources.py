from io import BytesIO
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


class UpdateSourcesTest(unittest.TestCase):
    def test_update_and_noop(self):
        for system in ("x86_64-linux", "aarch64-linux"):
            with self.subTest(system=system):
                self.check_update(system)

    def test_incomplete_release_preserves_file(self):
        for failure in ("missing", "hash", "filename"):
            with self.subTest(failure=failure):
                self.check_update("aarch64-linux", failure)

    def test_cli_update_and_noop(self):
        for system in ("x86_64-linux", "aarch64-linux"):
            with self.subTest(system=system):
                self.check_update(system, package="cli")

    def test_incomplete_cli_release_preserves_file(self):
        self.check_update("aarch64-linux", "download", package="cli")

    def check_update(self, system, failure=None, package="desktop"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / ".github/scripts/update-sources.py"
            script.parent.mkdir(parents=True)
            shutil.copyfile(Path(__file__).with_name("update-sources.py"), script)
            path = root / "sources.json"
            path.write_text(json.dumps({
                "sources": {
                    "desktop": {"platforms": {
                        "x86_64-linux": {"version": "0.1.1", "arch": "amd64", "hash": "old-amd64"},
                        "aarch64-linux": {"version": "0.1.9", "arch": "arm64", "hash": "old-arm64"},
                    }},
                    "cli": {"platforms": {
                        "x86_64-linux": {"version": "0.0.123", "platform": "linux-x64-baseline", "hash": "cli-amd64"},
                        "aarch64-linux": {"version": "0.0.234", "platform": "linux-arm64", "hash": "cli-arm64"},
                    }},
                },
            }))
            original = path.read_bytes()

            def fetch(url, timeout):
                if package == "cli":
                    return BytesIO(b"0.0.456\n")
                arch = "amd64" if "binary-amd64/" in url else "arm64"
                version = "0.1.2" if arch == "amd64" else "0.1.10"
                digest = "0123456789abcdef" * 4 if arch == "amd64" else "fedcba9876543210" * 4
                if arch == "arm64":
                    if failure == "missing":
                        return BytesIO(b"")
                    if failure == "hash":
                        digest = "abcd"
                filename = f"{version}/amp-desktop-{version}-{arch}.deb"
                if failure == "filename" and arch == "arm64":
                    filename = "unexpected.deb"
                return BytesIO((
                    f"Package: amp-desktop\nArchitecture: {arch}\nVersion: {version}\n"
                    f"Filename: {filename}\nSHA256: {digest}\n\n"
                ).encode())

            def prefetch(command, **kwargs):
                if failure == "download" and command[-1].endswith("amp-linux-arm64.gz"):
                    raise subprocess.CalledProcessError(1, command)
                hashes = {
                    "https://static.ampcode.com/cli/0.0.456/amp-linux-x64-baseline.gz": "sha256-ASNFZ4mrze8BI0VniavN7wEjRWeJq83vASNFZ4mrze8=",
                    "https://static.ampcode.com/cli/0.0.456/amp-linux-arm64.gz": "sha256-/ty6mHZUMhD+3LqYdlQyEP7cuph2VDIQ/ty6mHZUMhA=",
                }
                return subprocess.CompletedProcess(command, 0, json.dumps({"hash": hashes[command[-1]]}))

            with patch("urllib.request.urlopen", side_effect=fetch), patch("subprocess.run", side_effect=prefetch), patch("sys.argv", [str(script), package, system]):
                if failure:
                    with self.assertRaises(subprocess.CalledProcessError if package == "cli" else ValueError):
                        runpy.run_path(str(script), run_name="__main__")
                    self.assertEqual(path.read_bytes(), original)
                else:
                    runpy.run_path(str(script), run_name="__main__")
                    updated = json.loads(path.read_text())
                    expected_version, expected_hash = {
                        "x86_64-linux": ("0.1.2", "sha256-ASNFZ4mrze8BI0VniavN7wEjRWeJq83vASNFZ4mrze8="),
                        "aarch64-linux": ("0.1.10", "sha256-/ty6mHZUMhD+3LqYdlQyEP7cuph2VDIQ/ty6mHZUMhA="),
                    }[system]
                    if package == "cli":
                        expected_version = "0.0.456"
                    expected = json.loads(original)
                    expected_source = expected["sources"][package]["platforms"][system]
                    expected_source.update(version=expected_version, hash=expected_hash)
                    self.assertEqual(updated, expected)
                    modified = path.stat().st_mtime_ns
                    runpy.run_path(str(script), run_name="__main__")
                    self.assertEqual(path.stat().st_mtime_ns, modified)


if __name__ == "__main__":
    unittest.main()
