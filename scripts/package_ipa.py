"""Package the staged Theos app, preserving executable permissions."""
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parent.parent
app = root / '.theos/_/Applications/LocalSend6.app'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['MinimumOSVersion'] == '6.0'
for name in ('LocalSend6.ipa', 'LocalSend6-Media-Languages-0.5.7.ipa'):
    output = root / name
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(app.rglob('*')):
            if file.is_file():
                archive.write(file, 'Payload/LocalSend6.app/' + file.relative_to(app).as_posix())
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        assert archive.getinfo('Payload/LocalSend6.app/LocalSend6').external_attr >> 16 & 0o111
    print(f'{output.name}: {info["CFBundleShortVersionString"]}, {output.stat().st_size} bytes')
