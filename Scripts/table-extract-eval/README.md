# Local table-extraction measurement

Runs the app's table extractor (`PDFTableReader` and `TableExtractor`, compiled unchanged) over
one PDF on a Mac and prints how many of its captioned tables came out as a consistent grid, and
why the rest did not. Use it on your own licensed copy of a manual or code book. Nothing it
reads is written anywhere, and nothing it prints comes from inside a table.

```
Scripts/table-extract-eval/run.sh /path/to/your/document.pdf
```

`TABLE_EXTRACT_EVAL_BUILD_DIR` sets where the runner is compiled. It must be outside the
repository, and defaults to `$TMPDIR/table-extract-eval-build`. `TABLE_EXTRACT_EVAL_LABEL` names
the run in the output, so choose a name that is not the document's title.

## What a run prints

Counts only (the numbers below are an example, not a measurement):

```
[TABLES] fixtures captioned=6 extracted=4 (0.67) pages_without_text=1 seconds=0.1
[TABLES]   failures: no_text_layer=0 caption_not_found=0 too_few_rows=1 varying_column_count=1 merged_cells=0 rotated_headers=0
[TABLES]   extracted: rows median=4 max=6 columns median=3 max=6 over_pages=1 with_notes=1 numeric_cells=0.95
```

- **captioned**: bold `TABLE N` captions found, the rule the chunker uses for a passage's
  figure. A "(Continued)" caption that joined its table is not counted again.
- **extracted**: captions whose page resolved to a grid. A grid is not necessarily a correct
  one: this run cannot tell a right header path from a wrong one. That needs an answer key of
  cells, which the table lookup's measurement adds.
- **failures**: why a caption extracted nothing. `too_few_rows` is fewer than three rows of two
  or more cells under the caption, which includes a caption over prose. `varying_column_count`
  means the rows do not agree on their columns. `merged_cells` means too many rows have a cell
  spanning several columns. `rotated_headers` means the grid failed on a page that sets words
  on their side.
- **pages_without_text**: pages with no text layer, where no caption can be read at all.
