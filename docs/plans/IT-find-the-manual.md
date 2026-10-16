# Plan IT — Find the Manual (the manufacturer's own public copy, fetched into the organisation's library)

**Status:** 📝 Drafted 2026-10-17 — nothing implemented. A first-pass starter directory of 67
manufacturer literature portals is in [IT-starter-directory.md](IT-starter-directory.md).
**Track:** Field Assist (B2B).
**Related:** Plan [FS](FS-subscriber-vaults-and-vault-links.md) (own vaults; `VaultLinkService`'s
offer → download → review → confirm pipeline, and the rule that manuals never leave the phone
through the app), Plan [EG](EG-vault-packs.md) (packs never ship manuals), Plan
[H](H-custom-vault-import.md) (the importer), Plan [HK](HK-controlled-document-revisions.md)
(revisions), Plan [FN](FN-vault-manual-removal.md) (removal), Plan
[IQ](IQ-closeout-unknown-units-and-calling-base.md) P2 (the next step for an unknown unit), Plan
[IF](IF-photographed-manuals.md) (the paper-manual route), Plan
[FX](FX-desktop-office-and-device-sync.md) (the office assigns manuals to phones), Plan
[IP](IP-organisation-feature-switches.md) (organisation switches).
**Origin:** The owner, 2026-10-17, after the competitor review. Several competitors claim large
manual libraries, and nothing shows those are licensed. The biggest gap for a technician is a unit
whose manual the company hasn't loaded. Many manufacturers publish their manuals free on their own
sites. This plan lets a person fetch that copy into their own organisation's library, one manual at
a time. Avenkin never hosts, caches or redistributes a manual. The owner also asked that links to
the common manufacturers' manual sites ship ready-made, which is the directory in P0.

---

## Outcome

- At a unit whose manual isn't loaded, the technician says "find the manual". The phone knows the
  brand (nameplate or vault) and searches the manufacturer's own literature site for the model.
  It shows the candidates by title and the site they're on, and fetches the one chosen straight
  from the manufacturer to the phone. After a quick review it joins the organisation's library,
  marked "manufacturer's public copy, fetched <date> from <site>". The manual then answers with
  page citations like any other.
- The office does the same in bulk from Avenkin Office, and assigns the manuals to phones as it
  does today.
- A starter directory of the common HVAC, appliance and electrical manufacturers' literature sites
  ships in the app. These are links only, so on day one "find the manual" knows where to look.

## Why this is on the right side of the copyright line

- **The fetch is the customer's own download from the publisher.** The bytes go from the
  manufacturer's site to the organisation's device, as they would in a browser. No Avenkin server
  is in the path, and no copy exists anywhere else.
- **One manual at a time, chosen by a person.** No crawling, no bulk mirroring, no prefetching
  "in case".
- **Only sites whose terms allow it.** Each directory entry records its terms review. The app
  fetches only from an entry reviewed as `fetch`. Every other entry is a link the person opens in
  their own browser, and a site that forbids deep links gets only its home page.
- **Never a mirror site.** Third-party manual collections are redistributors. Results from any host
  outside the directory are dropped.
- **Nothing gets around a login, paywall or CAPTCHA.** A dealer-only portal is listed as a link the
  person opens and signs in to themselves. The app does not sign in or fetch behind it.
- **The organisation's own rules still apply.** Exports omit manuals (`VaultExporter`), there is no
  share-as-link (FS decision 2), and removal works as today (Plan FN).

## Verified starting point (`main`, 2026-10-17)

- **Documents already have a publisher field.** `VaultDocument` carries `source` and `sourceUrl`,
  documented as "where the manufacturer publishes this manual. Opened outside the app, so it is a
  link and never a substitute for the bundled original". Nothing fills it automatically, and nothing
  fetches from it.
- **A careful fetch pipeline exists for vault links.** `VaultLinkService` (Plan FS §3):
  - https only, no credentials in the URL, and the host is the only part rendered or logged;
  - an offer before any byte moves, naming the host, the size ceiling and cellular use;
  - a capped download into protected staging, then a review;
  - a confirmation that re-reads, re-checks the digest and installs under the per-vault lock.

  Every seam is injected, so it runs headless. It fetches vault archives, not single PDFs.
- **Manuals arrive today** through the vault manager's file importer (own vaults: the `ownVaults`
  capability, or a team or enterprise licence), the office's manual assignment
  (`OfficeManualAssignment`, `OfficeManualImport`, `OfficeManualVaultHandoff`), and photographed
  manuals (`manual_capture`).
- **There is a web search tool** (`web_search`: Perplexity when a key is set, otherwise
  DuckDuckGo). It isn't restricted to any set of hosts.
- **Signed catalogues exist on the phone** for vault packs and skill packs. Plan HG proposes
  factoring their verifier into a shared signed envelope. Avenkin Office has no catalogue verifier
  yet (FX26 adds one), and its manuals carry no source or provenance fields.

## Decisions proposed (owner to confirm)

1. **The directory is vendor-signed data, shipped in the app and updatable.** Each entry has:
   - manufacturer and brands;
   - literature site URL;
   - how to search: a URL pattern with `{model}`, a search page, or browse only;
   - access: public, free account, or dealer only;
   - `termsReviewedAt` with the terms URL and the allowed mode (`link`, `siteOnly` or `fetch`);
   - the hosts documents are served from.

   Updates arrive signed like the pack catalogues, so a bad entry can be withdrawn without a build.
   **One directory for both apps.** The same signed file is published once, beside the existing
   vault-pack and skill-pack catalogues on the project's Pages site. The phone bundles a copy and
   refreshes it. Avenkin Office reads the same file, so a manufacturer added, corrected or withdrawn
   reaches both at once. The schema and its fixtures live in `Contracts/`, like the other
   office-shared formats, so the office's decoder and the phone's agree.
2. **Three modes, and `link` by default.**
   - `link`: open the manufacturer's literature page in the browser, with the model filled in
     where the site has a model URL.
   - `siteOnly`: open the site's home or support page, for manufacturers whose terms forbid deep
     links (Trane Technologies and Copeland, in the first pass).
   - `fetch`: the app may retrieve a chosen PDF itself. It is set only after a person has read
     that manufacturer's terms and its robots.txt allows the document path.

   The first pass found that most large manufacturers' terms forbid robots, scraping or data
   mining (LennoxPros, Whirlpool, LG, GE, Samsung, Johnson Controls, Daikin, Navien). Goodman's and
   Amana's robots.txt disallow the paths their PDFs live on. So **the main route is the person's
   own browser** (P1), and `fetch` is the exception. The review is a person's (the owner's, with
   counsel for anything unclear) and is recorded in the entry.
3. **Only the model number leaves the phone.** The query is a model or part number, never a
   customer, site, job or serial. The privacy policy names this egress.
4. **Search through the manufacturer first, the web second, both restricted.** Where a site has a
   model URL pattern or a search page, that is used. Otherwise a web search restricted to the
   directory's hosts and to PDF results. A result from any other host is dropped before it is
   shown.
5. **Provenance on every fetched manual.** `source` = the manufacturer, `sourceUrl` = the page,
   plus `fetchedAt` and the content hash. Citations read "Manufacturer's public copy, fetched
   12 Oct 2026". A later re-check that finds a different hash raises an HK revision notice rather
   than replacing the copy silently.
6. **The office is the main place, the phone the fallback.** The office is where a library is
   built: someone at a desk works through the brands the company services, looks up several
   models at once, reviews the PDFs on a big screen, and adds them to the manual library. From
   there they travel as every office manual does today: inside the organisation's own signed vault
   (FX14.3), assigned to its phones. That is the organisation using its own copy inside its own
   business, as with a manual it imports by hand. That half is office plan FX26 (private). The
   phone keeps the in-job lookup for the unit nobody planned for, and reports the URL and hash of
   what it fetched so the office can fetch its own copy for the library. An organisation without
   the office uses the phone alone.

## The starter directory

[IT-starter-directory.md](IT-starter-directory.md) lists 67 portals from the manufacturers' own
domains, US and Canada first, with furnaces and commercial HVAC weighted most:
- 58 are public, 6 mixed, 1 needs an account and 2 are dealer-only;
- about ten have a model-number URL pattern;
- Canadian and French-language literature is noted where it exists.

The partner's furnace manual (Lennox SLP99V) is the worked example. The LennoxPros library is
public, needs no login, and is searchable by model, so "find the manual" for that furnace is one
link with the model filled in. The copy the partner sent stays out of the repository (it is a real
manufacturer's manual, Plan FR), and an organisation adds its own copy in two taps through P1's
browser route.

## Phases (one PR each)

### P0 — The directory (data, signing, and the links)

- `ManufacturerDirectory` (`Codable`) with the entry shape of decision 1, a strict decoder, and a
  bundled `Resources/ManufacturerDirectory.json` signed with the vendor key and verified with the
  existing catalogue verifier.
- The starter entries from [IT-starter-directory.md](IT-starter-directory.md), each `link` or `siteOnly` at first. Settings › Field Assist › Manufacturer manuals
  lists them: tap opens the site in the browser. That alone is useful on day one.
- `ManufacturerMatch` (pure): from a nameplate's brand text or a vault model's manufacturer to a
  directory entry, using the brand aliases (Bryant → Carrier, Ruud → Rheem, Luxaire → Johnson
  Controls).
- The schema in `Contracts/manufacturer-directory.md` with golden and negative fixtures, shared
  with the office's checks.
- **Exit tests:** decoder refusals by name; signature verification; brand alias resolution; every
  entry's URLs are https and on a host the entry lists; the shared fixtures decode identically.

### P1 — Open, download, share to the app (and fetch where allowed)

- **The browser route, for every entry.** "Find the manual" opens the entry's page with the model
  filled in where the site allows it. The person downloads the PDF in their browser and shares it
  to Avenkin (share sheet or Files). The app receives it and validates it: a PDF that PDFKit opens,
  with at least one page, under the size cap. It then shows a review (title, pages, size,
  manufacturer) and adds it to the chosen own vault. Provenance is the directory entry the person
  started from, the page URL when the share carries one, and the date. A shared PDF with no URL is
  recorded as "added from a download", not given a guessed source.
- **The fetch route, only for `fetch` entries.** `ManualLookupService` builds the search
  (decision 4), returns candidates on the entry's hosts only, and fetches the chosen PDF through
  `VaultLinkService`'s stages:
  1. policy: https, host in the entry, no credentials;
  2. the offer: host, size and cellular;
  3. a capped download into staging;
  4. the same validation and review;
  5. confirm, then install with decision 5's provenance.
- `siteOnly` entries open the site's home page and never a deep link.
- **Exit tests:**
  - the share intake: a PDF is accepted, a non-PDF or an oversized file refused by name, and the
    provenance has a URL when shared with one and none when not;
  - a fixture "site" over an injected loader for `fetch`: refusal ordering, the model as the only
    query, and the provenance written;
  - `link` and `siteOnly` never fetch, and `siteOnly` never builds a deep URL.

### P2 — In the job, by voice

- Plan IQ P2's three offers for an unknown unit gain a fourth when the directory knows the brand:
  "look it up on <manufacturer>'s site". The candidates are read as a short list (answerable as
  "the second one" through Plan IA, by name before that), and the chosen manual is fetched and
  added to the job's vault. Its first answer says it came from the manufacturer's public copy.
- With an office, the phone reports the fetched manual's URL and hash on the job report. The
  office decides whether its library adopts it: it fetches its own copy, checks the hash and adds
  it, and from then on it reaches the other phones in the organisation's vault (decision 6).
- **Exit tests:** the offer appears only for a known brand; the job's next answer cites the fetched
  copy with its provenance; the report carries URL and hash, not the PDF.

### P3 — Keeping fetched copies current

- An office-side re-check (proposed FX26) of fetched manuals' URLs on a slow schedule. A changed
  hash files an HK revision notice ("the manufacturer has published a newer copy"). A gone URL is
  noted, never treated as a reason to delete. The phone receives notices through HK's route.
- **Exit tests:** phone-side handling of the notice through HK's fixtures.

## Acceptance

- A technician at a Lennox furnace the company hasn't loaded says "find the manual". The phone
  opens LennoxPros' library at that model; they download the installation instructions and share
  them to the app. Within the same job they're answered from them with page citations, cited as
  the manufacturer's copy.
- Nothing is fetched from a site whose terms haven't been reviewed, or from any host outside the
  directory.
- Only a model number leaves the phone in the lookup.
- The settings list of manufacturer manual sites works on day one, as links.

## Open questions for the owner

1. Decision 2: who does the terms review, and is a written review per manufacturer enough, or do
   we want each manufacturer's written permission for `fetch` (slower, but the strongest position)?
2. Decision 6: should the office or the phone come first? The phone (P1–P2) can ship without the
   office half.
3. Is the directory worth offering to manufacturers as a partnership ("we send technicians to your
   own literature")? It is the opening to the licensed-content route.
