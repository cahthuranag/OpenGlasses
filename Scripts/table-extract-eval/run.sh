#!/bin/bash
# The table extractor over one PDF on a Mac, reading it as an import on the phone does. See README.md.
#
#   Scripts/table-extract-eval/run.sh /path/to/document.pdf
#   [TABLE_EXTRACT_EVAL_BUILD_DIR=/path/outside/the/repo] [TABLE_EXTRACT_EVAL_LABEL=name]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
src="$root/OpenGlasses/Sources/Services"
build="${TABLE_EXTRACT_EVAL_BUILD_DIR:-${TMPDIR:-/tmp}/table-extract-eval-build}"
case "$build" in
  "$root"*) echo "TABLE_EXTRACT_EVAL_BUILD_DIR must be outside the repository" >&2; exit 2 ;;
esac
mkdir -p "$build"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macos26.0" -o "$build/table-extract-eval" \
  "$here/main.swift" "$root/OpenGlassesTests/TableExtractEval/TableShapeReport.swift" \
  "$src/Vault/TableExtractor.swift" "$src/Vault/TableChecks.swift" "$src/Vault/PDFTableReader.swift" \
  "$src/Vault/RecognisedTable.swift" "$src/Vault/CellCertainty.swift" "$src/Vault/PictureRegion.swift" \
  "$src/Vault/PictureTableReading.swift" "$src/Vault/VisionTableReader.swift"

exec "$build/table-extract-eval" "$@"
