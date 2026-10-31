#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root. Use the same goosdoc checkout as docs.sh.
exec python3 "$(dirname "${GOOSDOC:-../goosdoc/main.goose}")/doctest.py" \
  --symbols api.txt --preamble tests/doc_preamble.goose --require-examples \
  "$@" search.goose goostr.goose utf8.goose
