#!/usr/bin/env python3
"""Package the local draw.io distribution as an offline native editor resource.

Usage: python3 macos-native/scripts/package-drawio.py /path/to/drawio
Keep upstream copyright and per-directory licenses in the archive. No minified
or upstream source files are changed by this packaging step.
"""
import pathlib
import sys
import urllib.request
import zipfile

source = pathlib.Path(sys.argv[1]).resolve()
assert (source / "index.html").is_file(), "Expected draw.io web distribution"
destination = pathlib.Path(__file__).resolve().parents[1] / "WorkFollow/Resources/DrawioRuntime.zip"
license_text = urllib.request.urlopen("https://raw.githubusercontent.com/jgraph/drawio/dev/LICENSE", timeout=30).read()
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(source.rglob("*")):
        if path.is_file() and not path.name.startswith("."):
            info = zipfile.ZipInfo("drawio/" + path.relative_to(source).as_posix(), date_time=(2026, 10, 23, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes(), compresslevel=9)
    archive.writestr("drawio/LICENSE", license_text)
print(f"Bundled offline draw.io: {destination.stat().st_size / 1024 / 1024:.1f} MiB")
