# Scoring the table lookup against a key of cells

Scores the app's table lookup against a key of cells on a Mac: for each question in the key, the
table, row and column it names, looked up in the tables a vault's own PDFs print, and compared with
what the key expects. It compiles the app's `TableLookup`, `TableReference`, `TableExtractor` and
`PDFTableReader` unchanged, with `OpenGlassesTests/TableLookupEval/TableLookupEvalCore.swift` doing
the scoring, and reads each PDF as an import on the phone does. Use it on a vault folder anywhere
on the Mac, your own licensed books included, with a key you wrote against them. Nothing it reads
is written anywhere.

```
Scripts/table-lookup-eval/run.sh /path/to/vault-folder /path/to/key.jsonl
```

The tables come from every document the manifest lists that is a PDF, or whose `source` original
is one; a folder with no `manifest.json` has every PDF in it read.
`TABLE_LOOKUP_EVAL_BUILD_DIR` sets where the runner is compiled (outside the repository; it
defaults to `$TMPDIR/table-lookup-eval-build`). `TABLE_LOOKUP_EVAL_LABEL` names the run in the
output, so choose a name that is not a book's title. The output says "against the unchecked key"
unless `TABLE_LOOKUP_EVAL_KEY_CHECKED=1`: set it only once someone who knows the book has checked
every expected cell. PDFKit writes diagnostics of its own to standard error; add `2>/dev/null` to
keep a saved report to the report.

## The key

One JSON object per line; blank lines and lines starting `//` are skipped.

```
{"q": "the invented rating", "table": "Table 99", "row": "QXRT three conductors", "column": "Rating group 2", "expect": "35"}
{"q": "a number between rows", "table": "Table 97", "row": "3", "expect": {"below": "2.5", "above": "4"}}
{"q": "a row that fits twice", "table": "Table 99", "row": "QXRT", "column": "Rating group 1", "expect": {"ask": true, "candidates": ["QXRT two conductors", "QXRT three conductors"]}}
```

- `table`, `row`: as a technician or a chain would say them; `column` is optional.
- `expect`: the cell as printed (a string or a number); `{"below", "above"}` for a number that
  falls between two rows, each the row's key or its cell; or `{"ask": true, "candidates": […]}`
  when the lookup should ask which.
- `edition`: optional; picks the books whose name holds it.
- `q`, `unit`, `notes`, `page`, `confidence`: optional and not scored.

## What a run prints

Counts only (the numbers below are an example, not a measurement):

```
[CELLS] documents=2 unreadable=0 tables=120 read=60 seconds=30.1
[CELLS] vault against the unchecked key: questions=40 unreadable_lines=0
[CELLS]   tables: read=30 unread=8 missing=2 ambiguous=0
[CELLS]   on a read table: rows resolved=22 columns resolved=27
[CELLS]   cells: expected=34 matched=18 (0.53)
[CELLS]   between rows: expected=3 matched=2
[CELLS]   asks: expected=3 asked=3 candidates_agree=2
```

- **tables**: the table each question names is `read` to a grid, `unread` (its caption was found
  and its grid was not), `missing` (no caption carries the label), or `ambiguous` (the same label
  in two books the edition did not tell apart).
- **rows resolved / columns resolved**: on a read table, the row named one row (not two either side
  of a number), and the column named one column.
- **cells matched**: the lookup gave one cell whose text is the expected text (case, spacing and the
  kind of dash aside) or the same number.
- **between rows matched**: the lookup said the number falls between two rows, and they are the ones
  the key names.
- **asks**: the lookup asked which, and whether every candidate the key lists is among those it
  offered.

**Nothing from the key or the book is printed**: no question, label, row, column, cell or
document name. A matched cell is only as right as the key; an unchecked key measures agreement,
not correctness.
