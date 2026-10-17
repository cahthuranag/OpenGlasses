#!/bin/bash
# The local retrieval eval on a Mac, on the device's embedding model. See README.md.
#
#   RETRIEVAL_EVAL_VAULT=/path/to/vault RETRIEVAL_EVAL_ANSWER_KEY=/path/to/answers.jsonl \
#     [RETRIEVAL_EVAL_WORKDIR=/path/outside/the/repo] [RETRIEVAL_EVAL_EMBEDDER=contextual] \
#     [RETRIEVAL_EVAL_LABEL=name] Scripts/retrieval-eval/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
src="$root/OpenGlasses/Sources/Services"
build="${RETRIEVAL_EVAL_BUILD_DIR:-${TMPDIR:-/tmp}/retrieval-eval-build}"
mkdir -p "$build"

swiftc -O -parse-as-library -o "$build/retrieval-eval" \
  "$here/main.swift" "$here/Stubs.swift" \
  "$root/OpenGlassesTests/RetrievalEval/RetrievalEvalCore.swift" \
  "$src/RAG/DocumentStore.swift" "$src/RAG/DocumentReconstructor.swift" "$src/RAG/DocumentChunker.swift" \
  "$src/RAG/Embedder.swift" "$src/RAG/EmbeddingBackend.swift" "$src/RAG/EmbeddingVersion.swift" \
  "$src/RAG/PassageLocation.swift" \
  "$src/Vault/VaultRetriever.swift" "$src/Vault/ClauseReference.swift" "$src/Vault/CodeTokenizer.swift" \
  "$src/Vault/LexicalSupport.swift" "$src/Vault/PageReference.swift" "$src/Vault/DocumentEditions.swift" "$src/Vault/BackOfBookIndex.swift"

exec "$build/retrieval-eval"
