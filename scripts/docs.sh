#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root. GOOSDOC names goosdoc's main.goose.
exec "${GOOSE:-goose}" run "${GOOSDOC:-../goosdoc/main.goose}" -- \
  --title "goostr API" --symbols api.txt --require-docs \
  --output "${DOC_OUTPUT:-API.md}" "$@" search.goose goostr.goose utf8.goose
