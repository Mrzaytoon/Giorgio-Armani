"""Extract the exact striped eagle vector from Armani's official brand switcher."""
import json
import re
from PIL import Image
from package_assets import ASSETS, RESEARCH, RUNTIME, run, file_record, write_json

source = (RESEARCH / "emporio-source-page.html").read_text(encoding="utf-8")
anchor = re.search(r'<a\b[^>]*aria-label="Go to Emporio Armani"[^>]*>(.*?)</a>', source, re.S)
if not anchor:
    raise ValueError("Official Emporio brand anchor not found")
match = re.search(r'<svg\b.*?</svg>', anchor.group(1), re.S)
if not match:
    raise ValueError("Official striped eagle SVG not found")
svg = match.group()
(RESEARCH / "emporio-armani-official-eagle.svg").write_text(svg, encoding="utf-8")
svg = re.sub(r'\sdata-v-[a-z0-9]+(?:="[^"]*")?', '', svg)
svg = re.sub(r'\sclass="[^"]*"', '', svg)
svg = svg.replace('currentColor', '#ffffff')
# The official SVG uses a square brand-switcher box. These viewBox bounds
# remove that layout whitespace without altering any artwork path.
svg = svg.replace('width="36" height="36"', 'width="2048" height="984"')
svg = svg.replace('viewBox="0 0 36 36"', 'viewBox="0 9 36 17.284"')
target = ASSETS / "brand/emporio-armani-eagle-white.svg"
target.write_text(svg, encoding="utf-8")
png = target.with_suffix('.png')
script = "const sharp=require(process.argv[1]);sharp(process.argv[2]).png().toFile(process.argv[3]).catch(e=>{console.error(e);process.exit(1)});"
run(RUNTIME / 'node/bin/node.exe', '-e', script, RUNTIME / 'node/node_modules/sharp', target, png)
with Image.open(png) as image:
    image.load()
    assert image.mode == 'RGBA' and image.getchannel('A').getbbox()
    width, height = image.size
manifest = json.loads((ASSETS / 'manifest.json').read_text())
manifest['symbol'] = {
    **file_record(png), 'file': png.relative_to(ASSETS).as_posix(),
    'width': width, 'height': height, 'svg': target.relative_to(ASSETS).as_posix(),
    'source_url': 'https://www.armani.com/en-us/emporio-armani/',
    'identity': 'Official Emporio Armani striped eagle, including GA initials.',
    'provenance': 'Exact paths extracted from the official website brand switcher; square layout whitespace removed using vector viewBox; rendered white on transparency.',
    'license': 'Trademark / rights retained by Giorgio Armani; no open-content license asserted.',
}
write_json(ASSETS / 'manifest.json', manifest)
print(json.dumps(manifest['symbol']))
