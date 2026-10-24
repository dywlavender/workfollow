#!/usr/bin/env python3
"""把 Quill 分发文件打包进 app bundle（对齐 package-drawio.py 的口径）。

用法：python3 macos-native/scripts/package-quill.py /path/to/quill-dist

源目录需含 quill.js 与 quill.snow.css（Quill 2.x 官方 dist）。
输出固定到 WorkFollow/Resources/QuillRuntime.zip，条目统一前缀 quill/，
固定时间戳保证构建可重复。不改上游文件。
"""

import pathlib
import sys
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "WorkFollow" / "Resources" / "QuillRuntime.zip"
FIXED_TIMESTAMP = (2026, 10, 24, 0, 0, 0)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    source = pathlib.Path(sys.argv[1])
    if not (source / "quill.js").is_file() or not (source / "quill.snow.css").is_file():
        raise SystemExit("源目录需包含 quill.js 与 quill.snow.css")

    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for name in ("quill.js", "quill.snow.css"):
            path = source / name
            info = zipfile.ZipInfo(f"quill/{name}", date_time=FIXED_TIMESTAMP)
            info.external_attr = 0o644 << 16
            zf.writestr(info, path.read_bytes())
        license_text = urllib.request.urlopen(
            "https://raw.githubusercontent.com/slab/quill/main/LICENSE", timeout=30
        ).read()
        info = zipfile.ZipInfo("quill/LICENSE", date_time=FIXED_TIMESTAMP)
        info.external_attr = 0o644 << 16
        zf.writestr(info, license_text)
    print(f"打包完成：{OUT}")


if __name__ == "__main__":
    main()
