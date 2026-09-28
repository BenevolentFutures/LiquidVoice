#!/bin/sh
# Inline the shared stage into a single self-contained file for the binding prototype (Safari-safe, double-clickable).
cd "$(dirname "$0")"
/usr/bin/env python3 - <<'PY'
src=open('signal/index.html').read()
for tag,path,wrap in [('<link rel="stylesheet" href="../shared/stage.css">','shared/stage.css','style'),
                      ('<script src="../shared/mock-data.js"></script>','shared/mock-data.js','script'),
                      ('<script src="../shared/stage.js"></script>','shared/stage.js','script')]:
    src=src.replace(tag, f'<{wrap}>\n'+open(path).read()+f'\n</{wrap}>')
assert '../shared/' not in src
open('signal/standalone.html','w').write(src); print('wrote signal/standalone.html')
PY
