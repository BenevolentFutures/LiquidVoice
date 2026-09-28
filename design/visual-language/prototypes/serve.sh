#!/bin/sh
# Serve the prototypes on http://localhost:8765 and open them in the system browser.
# Safari refuses parent-directory loads (../shared/) from file:// pages, so always open over http.
cd "$(dirname "$0")"
PORT=${PORT:-8765}
if ! lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  nohup python3 -m http.server $PORT --bind 127.0.0.1 >/dev/null 2>&1 &
  sleep 1
fi
for d in obsidian lumen signal; do
  [ -f "$d/index.html" ] && /usr/bin/open "http://localhost:$PORT/$d/index.html"
done
echo "serving http://localhost:$PORT (pid $(lsof -tiTCP:$PORT -sTCP:LISTEN | head -1))"
