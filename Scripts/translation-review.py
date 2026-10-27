#!/usr/bin/env python3
"""Native-speaker review of one language in Localizable.xcstrings, by spreadsheet.

    export  writes an .xlsx a reviewer fills in: English, the current translation, a blank
            "suggested" column and notes, one row per string (each plural form its own row),
            tagged with the screen it appears on and split into tabs, most-seen screens first.
    import  reads the filled-in sheet back and writes each suggestion into the catalog, after
            checking its format specifiers against the English the same way
            LocalizationCatalogGuardTests does. Nothing is written if any row fails, unless
            --skip-invalid is given; --dry-run only reports.

Rows are matched by their ID column (a hash of the key and plural form), not by the English
text, so a spreadsheet app that reformats a cell ("+64 21 000 000", "=") cannot misplace a
suggestion. The catalog is rewritten byte-for-byte in Xcode's format. Standard library only:
the .xlsx is written and read as plain zipped XML, so Excel, WPS and Google Sheets exports all
come back in.

    python3 -I Scripts/translation-review.py export --language zh-Hans --out review.xlsx
    python3 -I Scripts/translation-review.py import review.xlsx --language zh-Hans [--dry-run]
    python3 -I Scripts/translation-review.py --self-test
"""

import argparse
import hashlib
import io
import json
import os
import re
import sys
import zipfile
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(REPO, "OpenGlasses", "Sources", "Resources", "Localizable.xcstrings")
SOURCES = os.path.join(REPO, "OpenGlasses", "Sources")

# --- Specifiers: a port of LocalizationCatalogGuardTests (keep the two in step) -----------------

# The space flag is left out on purpose, as in the guard: "80% of a limit" is not a specifier.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+#0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp%])")


def specifiers(text):
    """[(position, kind, is_english_suffix)] for each specifier in text, skipping %%."""
    result, sequential = [], 0
    for m in SPECIFIER.finditer(text):
        conversion = m.group(2)
        if conversion == "%":
            continue
        sequential += 1
        position = int(m.group(1)) if m.group(1) else sequential
        if conversion == "@":
            kind = "object"
        elif conversion in "fFeEgGaA":
            kind = "float"
        elif conversion in "sS":
            kind = "cstring"
        else:
            kind = "integer"
        start = m.start()
        # A %@ glued to a word ("file%@") is an English plural suffix; a translation may drop it.
        suffix = kind == "object" and start > 0 and text[start - 1].isalpha()
        result.append((position, kind, suffix))
    return result


def specifier_problems(source, translation):
    """Problems with translation against source; empty when the specifiers are compatible."""
    source_specs = specifiers(source)
    by_position = {}
    for position, kind, _ in source_specs:
        by_position.setdefault(position, kind)
    problems, used = [], set()
    for position, kind, _ in specifiers(translation):
        expected = by_position.get(position)
        if expected is None:
            problems.append(f"argument {position} does not exist in the source")
            continue
        if expected != kind:
            problems.append(f"argument {position} is {kind}, source has {expected}")
        used.add(position)
    required = {p for p, _, suffix in source_specs if not suffix}
    for missing in sorted(required - used):
        problems.append(f"argument {missing} is missing")
    return problems


def needs_translation(key, entry):
    """Keys with no words in them ("", "—", "%@") render the same in every language."""
    if entry.get("extractionState") == "stale" or entry.get("shouldTranslate") is False:
        return False
    return any(ch.isalpha() for ch in SPECIFIER.sub("", key))


# --- Catalog -------------------------------------------------------------------------------------

def load_catalog(path=CATALOG):
    with open(path, "rb") as f:
        return json.loads(f.read())


def dump_catalog(catalog):
    """The catalog as Xcode writes it: ' : ' separators, empty objects with a blank line inside."""
    out = json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "))
    out = re.sub(r"^( *)(.*) : \{\}(,?)$", lambda m: f"{m[1]}{m[2]} : {{\n\n{m[1]}}}{m[3]}", out, flags=re.M)
    return (out + "\n").encode("utf-8")


def english_source(key, entry, form):
    """The English a translation is made from: the en value when present (it carries positional
    forms), the matching en plural form, else the key itself."""
    en = entry.get("localizations", {}).get("en", {})
    if form:
        unit = en.get("variations", {}).get("plural", {}).get(form, {}).get("stringUnit")
        if unit is None:
            unit = en.get("variations", {}).get("plural", {}).get("other", {}).get("stringUnit")
    else:
        unit = en.get("stringUnit")
    return unit["value"] if unit and "value" in unit else key


def rows_for(catalog, language):
    """One row per translatable value: (row_id, key, form, english, current)."""
    rows = []
    for key, entry in catalog["strings"].items():
        if not needs_translation(key, entry):
            continue
        loc = entry.get("localizations", {}).get(language, {})
        plural = loc.get("variations", {}).get("plural")
        forms = sorted(plural) if plural else [""]
        for form in forms:
            if form:
                current = plural[form].get("stringUnit", {}).get("value", "")
            else:
                current = loc.get("stringUnit", {}).get("value", "")
            english = english_source(key, entry, form)
            rows.append((row_id(key, form), key, form, english, current))
    return rows


def row_id(key, form):
    return hashlib.sha1(f"{key}\x1f{form}".encode("utf-8")).hexdigest()[:10]


def apply_suggestion(entry, language, form, value):
    loc = entry.setdefault("localizations", {}).setdefault(language, {})
    unit = {"state": "translated", "value": value}
    if form:
        loc.setdefault("variations", {}).setdefault("plural", {})[form] = {"stringUnit": unit}
    else:
        loc["stringUnit"] = unit


# --- Where each string appears ------------------------------------------------------------------

LITERAL = re.compile(r'(?<!")"((?:[^"\\\n]|\\.)*)"(?!")')

# Screens a person meets on most days, then the rest of the app's screens, then work-only areas.
# In the order a new user meets them; the first tab is sorted this way.
MOST_SEEN = [
    "OnboardingView", "RegistrationFlow", "GlassesConnectRow", "MainView", "MainTab", "VoiceTab",
    "StatusIndicator", "BottomControlBar", "ConversationPageHeader", "ConversationPageBody",
    "TranscriptOverlay", "QuickActionsOverlay", "MyDayView", "SettingsView", "SettingsScreens",
    "SettingsCategoryScreens", "ModelFormView", "AddModelView", "ModelEditorView", "ModelPickerSheet",
    "RealtimeModelsView", "PersonasView", "PersonaPickerSheet", "LanguageSettingsView",
    "TempleTapSettingsView", "DiagnosticsSupportView", "SupportReportViews",
]
# A string used in this many files is a shared word ("Cancel", "Done"), not one screen's.
SHARED_FILES = 4
WORK_FEATURE = re.compile(
    r"FieldAssist|Medical|HIPAA|Office|Workiz|Pilot|Job|Manual|Vault|Safety|Apprentice|Playbook|"
    r"CaptureFlow|Org[A-Z]|Admin|Fingerspelling|Deck|Quiz|Flashcard|Teleprompter|Assessment|Table")

TABS = [
    ("1 Most seen 常用界面", "Screens you meet every day: setup, the main screen, Settings, models, temple taps."),
    ("2 Other screens 其他界面", "The rest of the app's screens."),
    ("3 Spoken & messages 语音与提示", "What Avenkin says aloud, and messages, errors and notices."),
    ("4 Work features 工作功能", "Field Assist, Medical, office and training features."),
    ("5 Not located 未定位", "Strings whose screen could not be found automatically."),
]


def _normalize_literal(body):
    out, i = [], 0
    while i < len(body):
        if body.startswith("\\(", i):  # \(interpolation), with nested parentheses
            depth, i = 1, i + 2
            while i < len(body) and depth:
                depth += {"(": 1, ")": -1}.get(body[i], 0)
                i += 1
            out.append("\x00")
            continue
        if body[i] == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt == "u" and body.startswith("{", i + 2):
                end = body.find("}", i)
                try:
                    out.append(chr(int(body[i + 3:end], 16)))
                    i = end + 1
                    continue
                except ValueError:
                    pass
            out.append({"n": "\n", "t": "\t", "0": "\0", "r": "\r"}.get(nxt, nxt))
            i += 2
            continue
        out.append(body[i])
        i += 1
    return "".join(out)


def _normalize_key(key):
    def repl(m):
        return "%" if m.group(2) == "%" else "\x00"
    return SPECIFIER.sub(repl, key)


def literal_index(sources=SOURCES):
    """Normalized string literal -> file stems that contain it."""
    index = {}
    for root, _, files in os.walk(sources):
        for name in files:
            if not name.endswith(".swift"):
                continue
            stem = name[:-len(".swift")]
            with open(os.path.join(root, name), encoding="utf-8", errors="replace") as f:
                text = f.read()
            for m in LITERAL.finditer(text):
                index.setdefault(_normalize_literal(m.group(1)), set()).add((stem, root))
    return index


def placement(key, index):
    """(tab, rank, screen) for a key: the most-seen tab any of its files falls in, and its order
    there (shared words first, then screens in the order a new user meets them)."""
    hits = index.get(_normalize_key(key), set())
    if not hits:
        return 4, 0, ""

    def tab_of(hit):
        stem, root = hit
        if stem in MOST_SEEN:
            return 0
        if WORK_FEATURE.search(stem):
            return 3
        return 1 if os.sep + "Views" in root else 2

    best = min(hits, key=lambda h: (tab_of(h), h[0]))
    tab = tab_of(best)
    if len({stem for stem, _ in hits}) >= SHARED_FILES:
        return tab, -1, "Many screens 多处"
    rank = MOST_SEEN.index(best[0]) if best[0] in MOST_SEEN else len(MOST_SEEN)
    return tab, rank, _screen_name(best[0])


def _screen_name(stem):
    for suffix in ("SettingsView", "View", "Views", "Screens", "Sheet"):
        if stem.endswith(suffix) and len(stem) > len(suffix):
            stem = stem[:-len(suffix)] + (" settings" if suffix == "SettingsView" else "")
            break
    return re.sub(r"(?<=[a-z])(?=[A-Z])", " ", stem)


# --- .xlsx, written and read with the standard library ------------------------------------------

_XML_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f]")


def _col(n):
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def _cell(ref, value, style):
    text = escape(_XML_BAD.sub("", value))
    return f'<c r="{ref}" s="{style}" t="inlineStr"><is><t xml:space="preserve">{text}</t></is></c>'


# Styles: 0 default, 1 header, 2 read-only (grey, wrapped), 3 for the reviewer (yellow, wrapped),
# 4 wrapped plain.
_STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><sz val="9"/><color rgb="FF808080"/><name val="Calibri"/></font></fonts>
<fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/></patternFill></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf/></cellStyleXfs>
<cellXfs count="6"><xf/>
<xf fontId="1" fillId="2" applyFont="1" applyFill="1"><alignment wrapText="1" vertical="top"/></xf>
<xf fillId="3" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf fillId="4" applyFill="1" applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf>
<xf fontId="2" applyFont="1" applyAlignment="1"><alignment vertical="top"/></xf></cellXfs>
</styleSheet>"""

HEADERS = ["ID", "Screen 界面", "English 英文", "Current Chinese 当前译文", "Suggested Chinese 建议译文",
           "Notes 备注", "Keep these 保留占位符"]
WIDTHS = [11, 18, 48, 40, 40, 30, 16]
COLUMN_STYLES = [5, 2, 2, 2, 3, 3, 2]


def _sheet_xml(rows, widths=WIDTHS, styles=COLUMN_STYLES, freeze=True):
    cols = "".join(f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>' for i, w in enumerate(widths, 1))
    body = []
    for r, values in enumerate(rows, 1):
        cells = "".join(_cell(f"{_col(c)}{r}", v, 1 if r == 1 else styles[c - 1])
                        for c, v in enumerate(values, 1))
        body.append(f'<row r="{r}">{cells}</row>')
    pane = ('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
            'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>') if freeze else ""
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f'{pane}<cols>{cols}</cols><sheetData>{"".join(body)}</sheetData></worksheet>')


def write_xlsx(path_or_file, sheets):
    """sheets: [(name, rows, widths, styles, freeze)] — rows are lists of strings, row 1 the header."""
    with zipfile.ZipFile(path_or_file, "w", zipfile.ZIP_DEFLATED) as z:
        overrides = "".join(
            f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            for i in range(1, len(sheets) + 1))
        z.writestr("[Content_Types].xml",
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                   '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                   '<Default Extension="xml" ContentType="application/xml"/>'
                   '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                   '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
                   f'{overrides}</Types>')
        z.writestr("_rels/.rels",
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
                   '</Relationships>')
        names = "".join(f'<sheet name="{escape(s[0][:31])}" sheetId="{i}" r:id="rId{i}"/>'
                        for i, s in enumerate(sheets, 1))
        z.writestr("xl/workbook.xml",
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                   'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                   f'<sheets>{names}</sheets></workbook>')
        rels = "".join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>'
                       for i in range(1, len(sheets) + 1))
        styles_id = len(sheets) + 1
        z.writestr("xl/_rels/workbook.xml.rels",
                   '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                   '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   f'{rels}<Relationship Id="rId{styles_id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
                   '</Relationships>')
        z.writestr("xl/styles.xml", _STYLES)
        for i, (_, rows, widths, styles, freeze) in enumerate(sheets, 1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", _sheet_xml(rows, widths, styles, freeze))


_NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"


def _ref_column(ref):
    n = 0
    for ch in ref:
        if not ch.isalpha():
            break
        n = n * 26 + ord(ch.upper()) - 64
    return n


def read_xlsx(path_or_file):
    """{sheet name: [[cell strings]]}, for files written here or re-saved by a spreadsheet app."""
    with zipfile.ZipFile(path_or_file) as z:
        names = set(z.namelist())
        shared = []
        if "xl/sharedStrings.xml" in names:
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", _NS):
                shared.append("".join(t.text or "" for t in si.iter(f"{{{_NS['m']}}}t")))
        rel_root = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        targets = {r.get("Id"): r.get("Target") for r in rel_root}
        book = ET.fromstring(z.read("xl/workbook.xml"))
        result = {}
        for sheet in book.find("m:sheets", _NS):
            target = targets[sheet.get(_REL)].lstrip("/")
            part = target if target.startswith("xl/") else "xl/" + target
            rows = []
            for row in ET.fromstring(z.read(part)).iter(f"{{{_NS['m']}}}row"):
                values = {}
                for c in row.findall("m:c", _NS):
                    kind = c.get("t")
                    if kind == "inlineStr":
                        text = "".join(t.text or "" for t in c.iter(f"{{{_NS['m']}}}t"))
                    else:
                        v = c.find("m:v", _NS)
                        text = "" if v is None else (v.text or "")
                        if kind == "s" and text:
                            text = shared[int(text)]
                    values[_ref_column(c.get("r", "A"))] = text
                if values:
                    rows.append([values.get(i, "") for i in range(1, max(values) + 1)])
            result[sheet.get("name")] = rows
    return result


# --- Export and import ---------------------------------------------------------------------------

INSTRUCTIONS = [
    ["How to review 如何审阅"],
    ["Each row is one piece of Avenkin's text. Write a better Chinese version in the yellow "
     "\"Suggested Chinese 建议译文\" column only where the current one is wrong, unnatural or unclear. "
     "Leave it empty to keep the current translation."],
    ["每一行是 Avenkin 的一段文字。只在当前译文有误、不自然或不清楚时，在黄色的“建议译文”列中填写更好的中文。"
     "留空表示保留当前译文。"],
    ["Keep every placeholder listed in \"Keep these 保留占位符\" (such as %@ or %lld) in your suggestion; "
     "the app puts a name or a number there. You may move it within the sentence."],
    ["请在建议译文中保留“保留占位符”列中的每个占位符（例如 %@ 或 %lld），应用会在此处填入名称或数字。可以调整它在句中的位置。"],
    ["Please do not edit the ID column or rename the tabs. Use \"Notes 备注\" for questions or context."],
    ["请不要修改 ID 列或重命名工作表。如有问题或说明，请写在“备注”列。"],
    ["Tabs, in the order worth reviewing 工作表（按审阅优先级）:"],
] + [[f"{name} — {about}"] for name, about in TABS]


def export(language, out, catalog_path=CATALOG, sources=SOURCES):
    catalog = load_catalog(catalog_path)
    index = literal_index(sources)
    tabs = [[] for _ in TABS]
    skipped_names = 0
    for rid, key, form, english, current in rows_for(catalog, language):
        # A value left identical to the English is a name (Avenkin, Qwen, OpenAI), not prose.
        if current and current == english:
            skipped_names += 1
            continue
        tab, rank, screen = placement(key, index)
        keep = " ".join(m.group(0) for m in SPECIFIER.finditer(english) if m.group(2) != "%")
        label = english + (f"  [{form}]" if form else "")
        tabs[tab].append((rank, [rid, screen, label, current, "", "", keep]))
    for i, rows in enumerate(tabs):
        rows.sort(key=lambda r: (r[0], r[1][1].lower(), r[1][2].lower()))
        tabs[i] = [row for _, row in rows]
    sheets = [("Instructions 说明", INSTRUCTIONS, [120], [4], False)]
    for (name, _), rows in zip(TABS, tabs):
        sheets.append((name, [HEADERS] + rows, WIDTHS, COLUMN_STYLES, True))
    write_xlsx(out, sheets)
    counts = ", ".join(f"tab {i}: {len(rows)}" for i, rows in enumerate(tabs, 1))
    print(f"Wrote {out} — {sum(len(t) for t in tabs)} rows ({counts}); {skipped_names} names left out.")


def import_sheet(path, language, dry_run=False, skip_invalid=False, catalog_path=CATALOG):
    catalog = load_catalog(catalog_path)
    by_id = {rid: (key, form, english, current) for rid, key, form, english, current in rows_for(catalog, language)}
    applied, rejected, unchanged, notes = [], [], 0, []
    for sheet, rows in read_xlsx(path).items():
        if not rows or not rows[0] or rows[0][0].strip() != "ID":
            continue
        header = [h.split(" ")[0].lower() for h in rows[0]]
        col_id, col_new = header.index("id"), header.index("suggested")
        col_note = header.index("notes") if "notes" in header else None
        for line, row in enumerate(rows[1:], 2):
            row = row + [""] * (len(header) - len(row))
            rid, suggestion = row[col_id].strip(), row[col_new].strip()
            note = row[col_note].strip() if col_note is not None else ""
            if note:
                notes.append(f"{sheet} row {line}: {note}")
            if not suggestion:
                continue
            if rid not in by_id:
                rejected.append(f"{sheet} row {line}: ID {rid!r} is not a current string (the catalog changed?)")
                continue
            key, form, english, current = by_id[rid]
            if suggestion == current:
                unchanged += 1
                continue
            problems = specifier_problems(english, suggestion)
            if problems:
                rejected.append(f"{sheet} row {line}: {english!r} → {suggestion!r}: " + "; ".join(problems))
                continue
            applied.append((key, form, current, suggestion))
    for key, form, current, suggestion in applied:
        print(f"  {key!r}{f' [{form}]' if form else ''}: {current!r} → {suggestion!r}")
    for problem in rejected:
        print(f"  REJECTED {problem}", file=sys.stderr)
    for note in notes:
        print(f"  NOTE {note}")
    print(f"{len(applied)} to apply, {len(rejected)} rejected, {unchanged} unchanged.")
    if rejected and not skip_invalid:
        print("Nothing written: fix the rejected rows, or pass --skip-invalid to apply the rest.", file=sys.stderr)
        return 1
    if dry_run or not applied:
        return 1 if rejected else 0
    for key, form, _, suggestion in applied:
        apply_suggestion(catalog["strings"][key], language, form, suggestion)
    with open(catalog_path, "wb") as f:
        f.write(dump_catalog(catalog))
    print(f"Wrote {catalog_path}.")
    return 1 if rejected else 0


# --- Self-test -----------------------------------------------------------------------------------

def self_test():
    # The guard's own cases (LocalizationCatalogGuardTests).
    assert specifier_problems("%@ — %lld files", "%1$@ — файлов: %2$lld") == []
    assert specifier_problems("%lld Skill%@", "Навыков: %1$lld") == [], "an English plural suffix may be dropped"
    assert len(specifier_problems("%@ x %lld", "%lld %@")) == 2
    assert specifier_problems("Step %lld of %lld", "Шаг %lld") == ["argument 2 is missing"]
    assert specifier_problems("%@", "%1$@ %2$@") == ["argument 2 does not exist in the source"]
    assert specifiers("At 80% of a limit you'll hear a warning.") == []
    assert specifier_problems("Paste your %@ access key below", "请在下方粘贴你的 %@ 访问密钥") == []
    assert specifier_problems("%lld characters", "%lld 个字") == []
    assert specifier_problems("%lld characters", "%@ 个字") == ["argument 1 is object, source has integer"]

    # Literals match the keys Xcode extracts from them.
    assert _normalize_literal(r'Paste your \(provider.displayName) access key') == _normalize_key("Paste your %@ access key")
    assert _normalize_literal(r'\(count(of: items)) left') == _normalize_key("%lld left")
    assert _normalize_literal(r'At 80% \"now\"') == _normalize_key('At 80%% "now"')
    assert _screen_name("TempleTapSettingsView") == "Temple Tap settings"
    assert _screen_name("OnboardingView") == "Onboarding"

    # The catalog round-trips byte for byte, so an import only changes what it means to.
    with open(CATALOG, "rb") as f:
        raw = f.read()
    assert dump_catalog(json.loads(raw)) == raw, "catalog does not round-trip in Xcode's format"

    # A sheet round-trips, including text a spreadsheet would mangle and shared strings.
    buf = io.BytesIO()
    tricky = ["=SUM(A1)", "+64 21 000 000", "a < b & \"c\"", "多行\n文本", "  spaces  "]
    write_xlsx(buf, [("T", [HEADERS, ["abc", "", *tricky[:4], ""]], WIDTHS, COLUMN_STYLES, True)])
    buf.seek(0)
    assert read_xlsx(buf)["T"][1][2:6] == tricky[:4]
    shared = io.BytesIO()
    with zipfile.ZipFile(buf) as src, zipfile.ZipFile(shared, "w") as dst:
        for item in src.namelist():
            data = src.read(item)
            if item == "xl/worksheets/sheet1.xml":
                data = data.replace(b'<c r="C2" s="2" t="inlineStr"><is><t xml:space="preserve">=SUM(A1)</t></is></c>',
                                    b'<c r="C2" t="s"><v>0</v></c>')
            dst.writestr(item, data)
        dst.writestr("xl/sharedStrings.xml",
                     '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>shared 共享</t></si></sst>')
    shared.seek(0)
    assert read_xlsx(shared)["T"][1][2] == "shared 共享"

    # Import end to end on a copy of the catalog: one good row, one with a broken specifier.
    import tempfile
    catalog = load_catalog()
    rows = {(k, f): (rid, e, c) for rid, k, f, e, c in rows_for(catalog, "zh-Hans")}
    plain = next((k, f) for (k, f), (_, e, c) in rows.items() if not f and specifiers(e) == [] and c)
    with_spec = next((k, f) for (k, f), (_, e, c) in rows.items() if not f and len(specifiers(e)) == 1 and c)
    with tempfile.TemporaryDirectory() as tmp:
        cat_copy = os.path.join(tmp, "Localizable.xcstrings")
        with open(cat_copy, "wb") as f:
            f.write(raw)
        sheet = os.path.join(tmp, "review.xlsx")
        body = [HEADERS,
                [rows[plain][0], "", "", "", "测试译文", "a note", ""],
                [rows[with_spec][0], "", "", "", "没有占位符", "", ""]]
        write_xlsx(sheet, [("T", body, WIDTHS, COLUMN_STYLES, True)])
        assert import_sheet(sheet, "zh-Hans", catalog_path=cat_copy) == 1, "a broken specifier must block the write"
        with open(cat_copy, "rb") as f:
            assert f.read() == raw, "nothing may be written while a row is rejected"
        assert import_sheet(sheet, "zh-Hans", skip_invalid=True, catalog_path=cat_copy) == 1
        updated = load_catalog(cat_copy)["strings"][plain[0]]["localizations"]["zh-Hans"]["stringUnit"]
        assert updated == {"state": "translated", "value": "测试译文"}
        assert load_catalog(cat_copy)["strings"][with_spec[0]] == catalog["strings"][with_spec[0]]
    print("self-test passed")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--self-test", action="store_true")
    sub = parser.add_subparsers(dest="command")
    ex = sub.add_parser("export")
    ex.add_argument("--language", default="zh-Hans")
    ex.add_argument("--out", required=True)
    im = sub.add_parser("import")
    im.add_argument("sheet")
    im.add_argument("--language", default="zh-Hans")
    im.add_argument("--dry-run", action="store_true")
    im.add_argument("--skip-invalid", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.command == "export":
        export(args.language, args.out)
        return 0
    if args.command == "import":
        return import_sheet(args.sheet, args.language, args.dry_run, args.skip_invalid)
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
