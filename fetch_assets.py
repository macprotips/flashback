"""Download the public browser release, preserving its relative asset paths."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import urlopen
import re

BASE = 'https://games2.gamefools.com/onlinegames/TextTwist2/'

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        href = dict(attrs).get('href', '')
        if tag == 'a' and re.fullmatch(r'[A-Za-z0-9_.-]+/?', href) and href not in ('..', '../'):
            self.links.append(href)

def fetch(path='root/'):
    data = urlopen(BASE + path, timeout=30).read()
    if path.endswith('/'):
        parser = Links()
        parser.feed(data.decode())
        for link in parser.links:
            fetch(path + link)
    else:
        dest = Path('assets') / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print(path, len(data), flush=True)

if __name__ == '__main__':
    for path in ('root/game.swf', 'root/soundLibrary.swf', 'root/global/', 'root/localized/'):
        fetch(path)
