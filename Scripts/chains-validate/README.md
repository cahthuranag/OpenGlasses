# Checking a vault's rule chains

Checks a vault's `chains.md` against the tables its own PDFs print, on a Mac, before the vault goes
to a phone. It compiles the app's chain parser, table extractor and table lookup unchanged
(`ChainParser`, `TableExtractor`, `PDFTableReader`, `TableLookup`, with
`OpenGlassesTests/ChainsValidate/ChainsValidateCore.swift` doing the checking), reads each PDF the
manifest lists exactly as an import on the phone does, and prints what an author needs to fix. Use
it on a vault folder anywhere on the Mac, your own licensed books included. Nothing it reads is
written anywhere.

```
Scripts/chains-validate/run.sh /path/to/vault-folder
Scripts/chains-validate/run.sh /path/to/vault-folder /path/to/another/chains.md
```

With one argument it checks the chains file the manifest lists (else `chains.md` in the folder).
With two it checks the file given against the folder's tables, which is how a chains file kept
apart from the vault is tried before it is copied in. The tables come from every document in the
manifest that is a PDF, or whose `source` original is one; a folder with no `manifest.json` has
every PDF in it read.

`CHAINS_VALIDATE_BUILD_DIR` sets where the runner is compiled. It must be outside the repository,
and defaults to `$TMPDIR/chains-validate-build`. The runner keeps nothing else.
`CHAINS_VALIDATE_NAMES=0` prints counts, line numbers and kinds only, with no name at all. The
report is on standard output; PDFKit writes diagnostics of its own to standard error, so add
`2>/dev/null` to keep a saved report to the report.

## What a run prints

The numbers below are an example, not a measurement:

```
[CHAINS] documents=1 pdfs_read=1 unreadable=0 seconds=2.4
[CHAINS] file=chains.md listed_in_manifest=yes
[CHAINS] tables stored=12 read=9 unread=3
[CHAINS] chains headings=3 parsed=2 with_problems=1
[CHAINS]   chain line 5: steps=9 lookups=3 "Size a conductor for a load"
[CHAINS]   chain line 24: steps=10 lookups=3 "Check an installed conductor"
[CHAINS] problems=1 by kind: used_before_set=1
[CHAINS]   line 51 [used_before_set] Voltage drop on a run: 'metres' is used before any step sets it
[CHAINS] lookups=7 · tables read=5 unread=1 missing=1
[CHAINS]   rows: resolved=1 from_a_value=4 not_checked=1
[CHAINS]   columns: resolved=2 unresolved=1 pattern_matches=2 not_checked=2
[CHAINS]   cell numbers: from_a_value=1
[CHAINS]   lookups that resolve throughout=4 of 7
[CHAINS]   lookup line 12: table=read "Table 90" row=from_a_value column=resolved
[CHAINS]   lookup line 54: table=read "Table 97" row=from_a_value column=unresolved "Drop per amp"
```

- **listed_in_manifest**: whether the manifest's `files` lists a `chains.md`. The import reads
  chains only from a listed file, so `no` means none of them reaches a phone. `no_manifest` when
  the folder has no `manifest.json`.
- **tables**: every captioned table the PDFs print, `read` to a grid or `unread` (the caption was
  found and the grid was not; a chain stops on such a table and shows its page).
- **chains**: the `##` headings in the file, the chains that parse with no problem, and those
  with one. Each parsed chain's steps and lookups, by its heading's line.
- **problems**: every problem the import would refuse the vault for, with its line and its kind
  (`unknown_step`, `ask_does_not_read`, `lookup_does_not_read`, `used_before_set`, `set_twice`,
  `range_backwards`, `unknown_rule`, `unknown_unit`, `cite_without_step`, `says_nothing`,
  `unclosed_block`, `duplicate_name`, and the rest the parser names).
- **lookups**: every `lookup` line, in a chain with a problem too. `table`: `read`, `unread` or
  `missing` (no PDF prints that label; the import keeps the chain and warns). The row, the
  column and the `cell` number are each:
  - `resolved`: written out, and it names one row or column of the table;
  - `ambiguous`: written out, and it fits more than one, so the chain would ask or stop;
  - `between_rows`: a number written out that falls between two rows under `exact`;
  - `unresolved`: nothing in the table's headings fits;
  - `pattern_matches`: words with a value in them (`Rating group {group}`), and a heading fits;
  - `from_a_value`: only a value (`{size}`), which only a run can check;
  - `not_named`: no column on a table with several, so the chain would stop;
  - `not_checked`: the table is missing or unread.

  An unread table's lookup line ends with `unread_because=` and the extractor's reason
  (`too_few_rows`, `no_text_in_table` for a table printed with no text to read, and the rest
  `Scripts/table-extract-eval/README.md` lists), and the `unread because:` line counts them. A
  read table's line ends with `grid=<rows>x<columns>` and, when some of its columns were printed
  with no heading over them, `unnamed_columns=`: counts only.
- **Names, said the way a chain says them.** A column is matched by its whole heading path, by
  its last heading when only one column ends that way, or by its words in any order, ignoring
  case, punctuation and a unit in brackets ("Band A" for a heading printed "Band A (A)"); a row
  by its key, a number inside a range the book prints ("7-9", "10 to 12", "over 15 up to 18"),
  or its words. Words that fit more than one are reported `ambiguous`, as the chain would ask.

**Names come only from the chains file.** A chain's name, a table label and the row or column
words printed beside an unresolved, ambiguous or unnamed lookup are what the chain wrote. A
table's title, a heading, a cell, a candidate row and a document's name are never printed, so a
run over a licensed book can be shared with whoever writes the chains. A resolved lookup is not
proof the cell is the right one: check the read-back of a run on the phone against the printed
page.
