#!/bin/sh
# Assemble mouthkeys.com into one folder: the page, plus the README's screenshots and the app icon
# taken from the repo (not copied into site/). Used by .github/workflows/pages.yml and for previews:
#   site/assemble.sh /tmp/mk-site && python3 -m http.server -d /tmp/mk-site 8791 --bind 127.0.0.1
set -eu
out="${1:?usage: site/assemble.sh <output dir>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out"
abs="$(cd "$out" && pwd)"
# The output is wiped first, so it must not be the repo, site/, or anything that contains them.
case "$root/" in "$abs"/*) echo "assemble.sh: refusing to wipe $abs (it holds the repo)" >&2; exit 1;; esac
case "$abs/" in "$root/site/"*|"$root/docs/"*|"$root/Sources/"*) echo "assemble.sh: refusing to wipe $abs (inside the sources)" >&2; exit 1;; esac
rm -rf "$abs"
mkdir -p "$abs/images"
cp "$root"/site/index.html "$root"/site/grin.js "$root"/site/favicon.svg "$root"/site/CNAME "$abs"/
cp "$root"/docs/images/overlay.png "$root"/docs/images/history.png "$abs/images/"
cp "$root"/Sources/Fluid/Assets.xcassets/AppIcon.appiconset/icon-128@2x.png "$abs/apple-touch-icon.png"
touch "$abs/.nojekyll"
echo "assembled $abs"
