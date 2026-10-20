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
[TABLES] fixtures captioned=6 extracted=4 (0.67) pages_without_text=1 list_entries=0 seconds=0.1
[TABLES]   failures: no_text_layer=0 caption_not_found=0 too_few_rows=1 varying_column_count=1 merged_cells=0 rotated_headers=0 no_text_in_table=0
[TABLES]   extracted: rows median=4 max=6 columns median=3 max=6 over_pages=1 with_notes=1 numeric_cells=0.95
```

- **captioned**: table captions found — `TABLE N` in bold, or on a page set in one weight a line
  that begins `Table N` and stands on its own — with the label as printed, a letter beside the
  number included ("Table 5A", "Table D3"). A "(Continued)" caption that joined its table is not
  counted again, and neither is an entry in a list of tables (`list_entries`) whose table is
  captioned elsewhere in the document.
- **extracted**: captions whose page resolved to a grid. A grid is not necessarily a correct
  one: this run cannot tell a right header path from a wrong one. That needs an answer key of
  cells, which the table lookup's measurement adds.
- **failures**: why a caption extracted nothing. `too_few_rows` is fewer than three rows of two
  or more cells under the caption, which includes a caption over prose. `varying_column_count`
  means the rows do not agree on their columns. `merged_cells` means too many rows have a cell
  spanning several columns. `rotated_headers` means the grid failed on a page that sets words
  on their side. `no_text_in_table` means the page's text stops under the caption for a long
  stretch with no grid above it: the table is printed there with no text the PDF gives, most
  likely as a picture, and only a recogniser could read it.
- **pages_without_text**: pages with no text layer, where no caption can be read at all.
- **too_few_rows breakdown** (`TABLE_EXTRACT_EVAL_DIAGNOSE=0` leaves it out): for the captions
  that gave too few rows, how many body rows of two or more cells were read (0, 1, 2), whether a
  run of three such lines starts within the header reach under the caption, further down, or
  nowhere, and whether that run is text in its first cell in every row, or text in every cell.
- **shape report** (`TABLE_EXTRACT_EVAL_SHAPES=0` leaves it out; the core is
  `OpenGlassesTests/TableExtractEval/TableShapeReport.swift`): every caption that read no grid,
  by index, in counts only, so what to fix can be decided without anyone reading the book. Per
  caption: why it failed, how its label is printed (`digits`, `letter_after`, `letters_before`),
  the lines under it, the header and body lines read, the positions at least three cells start at
  (`clusters`), histograms of words and of cells per line, the share of cells that are a single
  character and that are not a number, words set smaller than their line, and whether the next
  page begins with lines on the same positions and no caption (`same`), sets a caption first,
  repeats one of the table's first lines (`heading_again`), holds a grid in its first ten lines
  (`grid_at_top`); whether the caption is an entry in a list of tables (`listed`), whether the
  text stops under it (`blank_below`), whether its positions fall into two groups with a gap
  (`two_groups`), and whether a heading line's first half reads as its second
  (`headings_repeat`). Summary lines give the same as counts, every line that reads as a caption
  by how its label is printed (`dotted` and `hyphenated` labels included, which the extractor does
  not read), and, for the tables that were read, how many the next page carries on with no
  caption and how many of those the extractor's continuation read.

  ```
  [SHAPE] failed=2 · labels digits=2 letter_after=0 letters_before=0
  [SHAPE]   #1 too_few_rows label=digits lines=3 header=0 body=0 clusters=0 words/line 9+:3 cells/line 1:3 single=0.00 text=0.00 small=0 next: same=no caption_first=yes heading_again=no grid_at_top=no listed=no blank_below=no two_groups=no headings_repeat=no
  ```
