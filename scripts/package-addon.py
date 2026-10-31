#!/usr/bin/env python3
"""Create the complete WoW 3.3.5a addon ZIP with its required MultiBot/ folder."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
source = root / 'MultiBot'
output = root / 'dist' / 'MultiBot-RandomBotBrowser.zip'
output.parent.mkdir(exist_ok=True)
runtime = {'Core', 'Data', 'Features', 'Icons', 'Libs', 'Locales', 'Strategies', 'Textures', 'UI'}
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if relative.parts[0] not in runtime and str(relative) not in {'MultiBot.toc', 'LICENSE'}:
            continue
        info = zipfile.ZipInfo('MultiBot/' + relative.as_posix(), (1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
print(output)
