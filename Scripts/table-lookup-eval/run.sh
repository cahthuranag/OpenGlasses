#!/bin/bash
# The table lookup scored against a key of cells, on a Mac. See README.md.
#
#   Scripts/table-lookup-eval/run.sh /path/to/vault-folder /path/to/key.jsonl
#   [TABLE_LOOKUP_EVAL_BUILD_DIR=/path/outside/the/repo] [TABLE_LOOKUP_EVAL_LABEL=name]
#   [TABLE_LOOKUP_EVAL_KEY_CHECKED=1]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
src="$root/OpenGlasses/Sources/Services"
build="${TABLE_LOOKUP_EVAL_BUILD_DIR:-${TMPDIR:-/tmp}/table-lookup-eval-build}"
case "$build" in
  "$root"*) echo "TABLE_LOOKUP_EVAL_BUILD_DIR must be outside the repository" >&2; exit 2 ;;
esac
mkdir -p "$build"

swiftc -O -parse-as-library -o "$build/table-lookup-eval" \
  "$here/main.swift" "$here/Stubs.swift" \
  "$root/OpenGlassesTests/TableLookupEval/TableLookupEvalCore.swift" \
  "$src/Vault/TableLookup.swift" "$src/Vault/TableReference.swift" "$src/Vault/LexicalSupport.swift" \
  "$src/Vault/TableExtractor.swift" "$src/Vault/PDFTableReader.swift"

exec "$build/table-lookup-eval" "$@"
