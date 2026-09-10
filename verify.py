"""Check packaged assets and manifest references without external dependencies."""
from pathlib import Path
import re
import plistlib

root = Path('TextTwist 2.app/Contents')
game = root / 'Resources/game'
assets = list(Path('assets/root').rglob('*'))
for source in assets:
    if source.is_file():
        target = game / source.relative_to('assets')
        assert source.read_bytes() == target.read_bytes(), str(target)
for xml in game.rglob('*.xml'):
    text = re.sub(r'<!--.*?-->', '', xml.read_text(encoding='utf-8-sig'), flags=re.S)
    for ref in re.findall(r'url="([^"]+)"', text):
        if ref.startswith('root/'):
            target = game / ref.replace('%localCode', 'en-US')
            assert target.is_file(), str(target)
assert (game / 'root/game.swf').read_bytes()[:3] in (b'CWS', b'FWS')
info = plistlib.loads((root / 'Info.plist').read_bytes())
assert (root / 'MacOS' / info['CFBundleExecutable']).is_file()
assert (root / 'Frameworks/Ruffle.app/Contents/MacOS/ruffle').is_file()
print('Verified bundle, matching assets, and XML resource references.')
