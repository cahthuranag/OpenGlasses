# Plan IT — Starter Manufacturer Directory (first pass)

Companion to [Plan IT](IT-find-the-manual.md). Compiled 2026-10-17 from the manufacturers' own
domains only, never third-party manual sites. US and Canada first, with furnaces and commercial
HVAC weighted most, then appliances, electrical and Australia/New Zealand. Every entry starts as
a **link**. Nothing here is fetched by the app until its terms review sets `fetch` (Plan IT
decision 2). Trane and Copeland start **site only**, because their terms forbid deep links into
their sites.

**Lvl** is how far the entry was checked: **V** = opened and the document route confirmed;
**S** = the page exists but its search was not exercised; **X** = seen in search only. **Model
link** is a URL pattern with the model in it, where one exists.

**Worked example: the partner's furnace.** Lennox SLP99V (service manual and installation
instructions). The LennoxPros document library is public, with no login, and searchable by model:
`https://www.lennoxpros.com/documentlibrary?search=SLP99` returns the installation instructions,
service literature, wiring diagrams and start-up checklists. Its PDFs are served from Lennox's own
CDN, with French (`-CF`) and Spanish (`-SP`) variants. Individual document paths can't be derived
from a model, so the directory links the library search, not the file.

**Terms worth knowing before any `fetch`:**
- **Deep links banned:** Trane Technologies and Copeland.
- **Robots, scraping or data mining banned:** LennoxPros (which also limits use to "non-competitive
  business purposes"), Navien, Whirlpool, LG, GE, Samsung, Johnson Controls, Daikin Comfort and
  Daikin Applied.
- **robots.txt disallows the PDF paths:** Goodman and Amana (`/docs/*`). Napoleon disallows AI
  crawlers by name.
- **No clause found in the fetched terms:** Carrier/Bryant, Goodman, Rheem, Bosch, Frigidaire,
  Thermador, Schneider and Leviton, among others. This is not a legal reading, and several terms
  pages are rendered by script.

So, for most manufacturers, the route is the person's own browser: open the entry, download the
PDF, and share it to the app (Plan IT P1).

**Ownership changes seen live:** Payne is now Weathermaker (Carrier). Fujitsu General US is now
Airstage (Rheem family). Nortek's furnace brands (Maytag, Frigidaire, Gibson) are at
`literature.nordyne.com`.

| Brand(s) | Portal | Access | Model link | Starting mode | Lvl |
|---|---|---|---|---|---|
| Lennox residential and commercial; Allied Air (Armstrong Air, AirEase… | [lennoxpros.com](https://www.lennoxpros.com/documentlibrary) | Public | `?search=<MODEL>` | link | V |
| Lennox commercial | [lennox.com](https://www.lennox.com/commercial/resources/product-documentation) | Public as far as seen | — | link | S |
| Heatcraft Refrigeration Products (Lennox) incl. Bohn, Larkin, Climate… | [heatcraftrpd.com](https://www.heatcraftrpd.com/resources/literature/) | Public | — | link | V |
| Carrier residential (US) | [carrier.com](https://www.carrier.com/residential/en/us/Document/GetAllDocumentsByModel/) | Public | — | link | V |
| Bryant | [bryant.com](https://www.bryant.com/en/us/current-owners/document-search/) | Public | — | link | V |
| Carrier Canada (EN and FR) | [carrier.com](https://www.carrier.com/residential/en/ca/homeowner-resources/product-literature/) | Public | — | link | S |
| Carrier commercial (rooftops, chillers) | [carrier.com](https://www.carrier.com/commercial/en/us/literature/) | Mixed: public literature pa… | — | link | V |
| Payne (now Weathermaker), Heil, Tempstar, Comfortmaker, Day & Night (… | [weathermaker.com](https://www.weathermaker.com/en/us/) | Public product pages | — | link | S |
| KeepRite (HVAC, ICP) and KeepRite Refrigeration (Canada) | [keeprite.com](https://www.keeprite.com/en/us/) | Public | — | link | X/S |
| Trane / American Standard residential owner's guides | [trane.com](https://www.trane.com/) | Public | — | site only (no deep links) | V |
| Trane e-Library (commercial IOMs; some residential installer guides) | [tranetechnologies.com](https://www.tranetechnologies.com/) | Public | partial | site only (no deep links) | V |
| Trane Comfort Site (serial-number Model Number Lookup, control and hi… | via support.trane.com (article 31862912282509) | Dealer-only | — | site only (no deep links) | X |
| Goodman | [goodmanmfg.com](https://www.goodmanmfg.com/support/literature-library) | Public | — | link | V |
| Amana HVAC | [amana-hac.com](https://www.amana-hac.com/resources/literature-library) | Public | — | link | V |
| Daikin Comfort / Daikin residential (US, shared with Goodman and Aman… | [daikincomfort.com](https://daikincomfort.com/resource-center?tab=manuals) | Public | — | link | V |
| Goodman/Daikin dealer tools: PartnerLink (`partner.goodmanmfg.com`, `… | as listed | Dealer-only | — | link (sign-in by the person) | X |
| Rheem | [rheem.com](https://www.rheem.com/professionals/residential-heating-and-cooling/product-documentation/) | Public | partial | link | V |
| Ruud | [ruud.com](https://www.ruud.com/) | Public | — | link | S |
| Nordyne / Nortek Global HVAC (Maytag, Frigidaire, Gibson, Intertherm,… | [literature.nordyne.com](https://literature.nordyne.com/) | Public to browse | — | link | V |
| York, Coleman, Luxaire, Champion (JCI ducted systems) | [docs.johnsoncontrols.com](https://docs.johnsoncontrols.com/ductedsystems) | Public | — | link | V |
| York commercial (chillers, rooftops, VRF) | [docs.johnsoncontrols.com](https://docs.johnsoncontrols.com/chillers) | Mixed: Chillers Knowledge E… | — | link | V |
| Mitsubishi Electric Trane HVAC US ("MPro") | [mitsubishipro.com](https://www.mitsubishipro.com/catalog/series) | Public | — | link | V |
| Mitsubishi Electric Trane literature | [mitsubishicomfort.com](https://www.mitsubishicomfort.com/literature) | Public | — | link | V |
| Mitsubishi Electric Canada (MESCA) | [techinfo.mitsubishielectric.ca](https://techinfo.mitsubishielectric.ca/en) | Public as far as seen | — | link | S |
| Fujitsu General US, now Airstage (GHSA) | [airstagehvac.com](https://www.airstagehvac.com/support/downloads/) | Public | — | link | V |
| LG HVAC (Multi V VRF, mini-split) | [lghvac.com](https://www.lghvac.com/) | Account: LG says additional… | — | link | V |
| Samsung HVAC (DVM VRF, mini-split, Hylex) | [samsunghvac.com](https://www.samsunghvac.com/downloads) | Mixed: category pages public | — | link | S |
| Daikin Applied (incl. McQuay) | [daikinapplied.com](https://www.daikinapplied.com/resources/IOM-Manuals) | Public | — | link | V |
| Bosch Thermotechnology / Bosch Home Comfort (US) | [bosch-homecomfort.com](https://www.bosch-homecomfort.com/us/en/residential/technical-documentation/manuals/) | Public | — | link | V |
| Copeland (compressors, condensing units) | [copeland.com](https://www.copeland.com/) | Public as far as seen | partial | site only (no deep links) | V |
| Danfoss Climate Solutions | [designcenter.danfoss.com](https://designcenter.danfoss.com/download-center) | Public | — | link | S |
| Sporlan (Parker) | [discover.parker.com](https://discover.parker.com/sporlanliterature) | Public | — | link | S |
| Vertiv / Liebert | [vertiv.com](https://www.vertiv.com/en-us/support/) | Public | — | link | S |
| AAON | [aaon.com](https://www.aaon.com/hubfs/Documents/IOM/<refrigerant>/) | Public | — | link | V |
| Bard HVAC | [bardhvac.com](https://www.bardhvac.com/resources/product-literature-overview/) | Public | — | link | S |
| Hussmann | [hussmann.com](https://www.hussmann.com/ns/Technical-Documents/) | Public | — | link | V |
| Engineered Air (Canada; EN and FR) | [engineeredair.com](https://www.engineeredair.com/ea-manuals/) | Public | — | link | S |
| Greenheck | [greenheck.com](https://www.greenheck.com/shop/parts/labels-and-literature/installation-and-maintenance-manuals) | Public | — | link | S |
| Modine / Reznor | [modinehvac.com](https://www.modinehvac.com/resources/product-literature/) | Public | — | link | S |
| Navien | [navieninc.com](https://www.navieninc.com/downloads) | Public | — | link | V |
| Weil-McLain | [weil-mclain.com](https://www.weil-mclain.com/resource-library/) | Public | — | link | V |
| Burnham (commercial and residential boilers) | [burnhamcommercial.com](https://www.burnhamcommercial.com/products/cast-iron-boilers/cast-iron-boilers-technical-info/) | Public | — | link | S |
| Napoleon (Wolf Steel, Barrie ON) | [napoleon.com](https://www.napoleon.com) | Public for fireplaces | — | link | X |
| Broan-NuTone and Venmar (Canada, Drummondville QC) | [broan-nutone.com](https://www.broan-nutone.com) | Public PDFs | — | link | X |
| Rinnai Australia / NZ / US | [rinnai.com.au](https://www.rinnai.com.au/support/products) | Public | — | link | V |
| Daikin Australia / New Zealand | [daikin.com.au](https://www.daikin.com.au/operation-manuals) | AU public | — | link | V |
| Mitsubishi Electric Australia / New Zealand | [mitsubishielectric.com.au](https://www.mitsubishielectric.com.au/industry-professional/support/guide-manuals/) | AU public | — | link | V |
| Fujitsu General Australia and NZ | [assist.fujitsugeneral.com.au](https://assist.fujitsugeneral.com.au/support/solutions) | Public | — | link | V |
| Rheem Australia / NZ | [rheem.com.au](https://rheem.com.au/InstallationGuides?category=86&model=2) | Public | — | link | S |
| Whirlpool, Maytag, KitchenAid, Amana appliances (Whirlpool Corp.) | [whirlpool.com](https://www.whirlpool.com/services/manuals.html) | Public | — | link | V |
| GE Appliances (GE, Profile, Café, Monogram, Haier, Hotpoint) | [geappliances.com](https://www.geappliances.com/ge/service-and-support/literature.htm) | Public | — | link | V |
| Samsung appliances | [samsung.com](https://www.samsung.com/us/support/model/<MODEL>/) | Public | — | link | V |
| LG appliances | [lg.com](https://www.lg.com/us/support/product/lg-<MODEL>) | Public | — | link | V |
| Frigidaire / Electrolux (US) | [frigidaire.com](https://www.frigidaire.com/en/p/owner-center/product-support/<MODEL>) | Public | — | link | V |
| Electrolux Australia | [resource.electrolux.com.au](https://resource.electrolux.com.au/Public/File/<id>) | Public | — | link | X |
| Bosch (BSH) and Thermador (US) | [thermador.com](https://www.thermador.com/us/support/owner-manuals) | Public | — | link | V |
| Sub-Zero, Wolf, Cove | [subzero-wolf.com](https://www.subzero-wolf.com/trade-resources/product-specifications) | Mixed: specifications, use… | — | link | V |
| Miele | `media.miele.com/downloads/<xx>/<xx>/<n>_<GUID>.pdf` ; US s… | Public PDFs | — | link | X |
| Fisher & Paykel | [fisherpaykel.com](https://www.fisherpaykel.com/us/trade-resources/install/) | user-guide}/<Category>/<fil… | — | link | V |
| Speed Queen | [speedqueen.com](https://speedqueen.com/support/manuals-downloads/) | Public | — | link | S |
| Schneider Electric: Square D, Clipsal, PDL | [se.com](https://www.se.com/us/en/product/<REFERENCE>/) | Public | — | link | V |
| PDL (NZ) and Clipsal (AU/NZ) | [pdl.co.nz](https://www.pdl.co.nz/products/switches-sockets/standard-series/load-correction-device-450w-31lcda?itemno=31LCDA) | Public | — | link | V |
| Eaton | [ecat.eaton.com](https://ecat.eaton.com/download-center) | Public | — | link | S |
| Siemens | [mall.industry.siemens.com](https://mall.industry.siemens.com/) | Public | — | link | S/X |
| ABB | [library.abb.com](https://library.abb.com/) | Public | — | link | S/X |
| Leviton | [leviton.com](https://leviton.com/instructions) | Public | — | link | V |
| Hager (AU/NZ/international) | [hager.com](https://hager.com/au/support/downloads) | Public | — | link | V |

**Not located or not exercised:** Napoleon furnace manuals; the script-loaded lookups for Armstrong
Air, AirEase, Lennox commercial, Carrier commercial and Mitsubishi Electric Canada; and finders for
Eaton, ABB, Siemens and Hager, which are leads only. The full notes (doc types, PDF hosts, terms
quotes, robots.txt) stay with the research, outside the repository.
