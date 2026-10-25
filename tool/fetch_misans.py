"""Download MiSans (Xiaomi's UI typeface) from the official site into assets/fonts/.

The font files are not committed to the repository; run this once before `flutter pub get` / build.
MiSans is free to use under Xiaomi's MiSans licence: https://hyperos.mi.com/font/
usage: python tool/fetch_misans.py [MiSans.zip]   (pass an already downloaded archive to skip the download)
"""
import os
import shutil
import sys
import tempfile
import time
import urllib.request
import zipfile

URLS = [
    'https://hyperos.mi.com/font-download/MiSans.zip',
    'https://cdn.cnbj1.fds.api.mi-img.com/vipmlmodel/font/MiSans/MiSans.zip',  # same file, Xiaomi CDN
]
WEIGHTS = ['ExtraLight', 'Regular', 'Medium', 'Semibold']  # 200, 400, 500, 600 (see pubspec.yaml)
DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'fonts')


def _wanted():
    return {f'MiSans-{w}.ttf' for w in WEIGHTS}


def _has_fonts(path):
    with zipfile.ZipFile(path) as z:
        names = {os.path.basename(n) for n in z.namelist() if '__MACOSX' not in n}
    return _wanted() <= names


def download(path):
    for attempt in range(3):
        for url in URLS:
            print(f'downloading {url} ...')
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (mi-glass-flutter-demo font fetch)'})
            try:
                with urllib.request.urlopen(req, timeout=120) as r, open(path, 'wb') as f:
                    shutil.copyfileobj(r, f)
            except OSError as e:
                print(f'  failed: {e}')
                continue
            if zipfile.is_zipfile(path) and _has_fonts(path):
                return
            with open(path, 'rb') as f:
                print(f'  not a zip ({os.path.getsize(path)} bytes): {f.read(120)!r}')
        time.sleep(5 * (attempt + 1))
    raise SystemExit('could not download MiSans')


def main():
    os.makedirs(DEST, exist_ok=True)
    wanted = _wanted()
    if all(os.path.exists(os.path.join(DEST, n)) for n in wanted):
        print('MiSans already present')
        return
    with tempfile.TemporaryDirectory() as tmp:
        archive = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tmp, 'MiSans.zip')
        if len(sys.argv) <= 1:
            download(archive)
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                name = os.path.basename(info.filename)
                if '__MACOSX' in info.filename or name not in wanted:
                    continue
                with z.open(info) as src, open(os.path.join(DEST, name), 'wb') as dst:
                    shutil.copyfileobj(src, dst)
                print('  ' + name)
    missing = [n for n in wanted if not os.path.exists(os.path.join(DEST, n))]
    if missing:
        raise SystemExit(f'missing from archive: {missing}')


main()
