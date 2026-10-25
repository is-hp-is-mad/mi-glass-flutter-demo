"""Download MiSans (Xiaomi's UI typeface) from the official site into assets/fonts/.

The font files are not committed to the repository; run this once before `flutter pub get` / build.
MiSans is free to use under Xiaomi's MiSans licence: https://hyperos.mi.com/font/
usage: python tool/fetch_misans.py
"""
import os
import shutil
import tempfile
import urllib.request
import zipfile

URL = 'https://hyperos.mi.com/font-download/MiSans.zip'
WEIGHTS = ['ExtraLight', 'Regular', 'Medium', 'Semibold']  # 200, 400, 500, 600 (see pubspec.yaml)
DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'fonts')


def main():
    os.makedirs(DEST, exist_ok=True)
    wanted = {f'MiSans-{w}.ttf' for w in WEIGHTS}
    if all(os.path.exists(os.path.join(DEST, n)) for n in wanted):
        print('MiSans already present')
        return
    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, 'MiSans.zip')
        print(f'downloading {URL} ...')
        with urllib.request.urlopen(URL) as r, open(archive, 'wb') as f:
            shutil.copyfileobj(r, f)
        with zipfile.ZipFile(archive) as z:
            for info in z.infolist():
                name = os.path.basename(info.filename)
                if '__MACOSX' in info.filename or '/ttf/' not in info.filename or name not in wanted:
                    continue
                with z.open(info) as src, open(os.path.join(DEST, name), 'wb') as dst:
                    shutil.copyfileobj(src, dst)
                print('  ' + name)
    missing = [n for n in wanted if not os.path.exists(os.path.join(DEST, n))]
    if missing:
        raise SystemExit(f'missing from archive: {missing}')


main()
