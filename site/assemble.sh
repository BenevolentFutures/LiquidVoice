#!/bin/sh
# Assemble mouthkeys.com into one folder: the page, plus the README's screenshots and the app icon
# taken from the repo (not copied into site/). Used by .github/workflows/pages.yml and for previews:
#   site/assemble.sh /tmp/mk-site && python3 -m http.server -d /tmp/mk-site 8765
set -eu
out="${1:?usage: site/assemble.sh <output dir>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$out"
mkdir -p "$out/images"
cp "$root"/site/index.html "$root"/site/grin.js "$root"/site/favicon.svg "$root"/site/CNAME "$out"/
cp "$root"/docs/images/overlay.png "$root"/docs/images/history.png "$out/images/"
cp "$root"/Sources/Fluid/Assets.xcassets/AppIcon.appiconset/icon-128@2x.png "$out/apple-touch-icon.png"
touch "$out/.nojekyll"
echo "assembled $out"
