"""
Writes version_info.txt, the Windows version resource PyInstaller embeds in
ColorBreakdown.exe (shown in file Properties and Settings > Apps), from
VERSION in color_breakdown.py. Prints the version so build-windows.bat can use it.
"""

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

source = (HERE / "color_breakdown.py").read_text(encoding="utf-8")
match = re.search(r'^VERSION = "([^"]+)"', source, re.MULTILINE)
if not match:
    raise SystemExit("Couldn't find VERSION in color_breakdown.py")
version = match.group(1)
nums = tuple(([int(n) for n in re.findall(r"\d+", version)] + [0, 0, 0, 0])[:4])

(HERE / "version_info.txt").write_text(f"""\
VSVersionInfo(
  ffi=FixedFileInfo(filevers={nums}, prodvers={nums}, mask=0x3f, flags=0x0,
                    OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)),
  kids=[
    StringFileInfo([StringTable('040904B0', [
      StringStruct('CompanyName', 'Buffalo Stampeders'),
      StringStruct('FileDescription', 'Color Breakdown'),
      StringStruct('FileVersion', '{version}'),
      StringStruct('InternalName', 'ColorBreakdown'),
      StringStruct('OriginalFilename', 'ColorBreakdown.exe'),
      StringStruct('ProductName', 'Color Breakdown'),
      StringStruct('ProductVersion', '{version}')])]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
""", encoding="utf-8")

print(version)
