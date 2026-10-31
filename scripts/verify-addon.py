#!/usr/bin/env python3
"""Validate the packaged runtime files and every TOC reference."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
with zipfile.ZipFile(root / 'dist/MultiBot-RandomBotBrowser.zip') as archive:
    assert archive.testzip() is None, 'ZIP integrity failure'
    names = set(archive.namelist())
    assert all(name.startswith('MultiBot/') for name in names), 'Wrong addon directory'
    for name in names:
        assert archive.read(name) == (root / name).read_bytes(), name
    toc = archive.read('MultiBot/MultiBot.toc').decode('utf-8')
    for line in toc.splitlines():
        if line.strip() and not line.startswith('#'):
            expected = 'MultiBot/' + line.strip().replace('\\', '/')
            assert expected in names, expected
print('PASS: addon ZIP integrity, source equality and all TOC references')
