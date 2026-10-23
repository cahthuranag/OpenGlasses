# Plan JS — Licence Sales and Device Seats (a partner orders codes, pays by bank transfer, and a code counts its phones)

**Status:** P0 implemented in this PR (2026-10-23); validation recorded in `Tools/LicenceIssuance/README.md` and the PR. P1–P3 remain unimplemented.
**Origin:** the pilot partner resells Field Assist team licences and needs to order and pay for them
without waiting on the vendor. The owner asked whether a licence could be held to a number of
devices, and whether one server could produce the code and its QR, and let the partner buy and be
invoiced. Today every code is minted by hand ([`Scripts/generate-field-license.swift`](../../Scripts/generate-field-license.swift)),
and `seats` is a label nothing counts.
**Decided (owner, 2026-10-23):**
1. **One vendor-run server** issues codes, keeps the ledger, raises invoices, and in P2 counts seats.
2. **The partner pays by bank transfer.** No card processor and no stored payment details. An
   invoice carries the vendor's bank details and a payment reference. The vendor marks it paid when
   the money arrives.
3. **Payment terms are 30 days.** An order is issued at once as a **provisional** code that expires
   **35 days** after issue. When the invoice is paid, the server replaces it with the **full-term**
   code. If the invoice is not paid, the provisional code lapses on day 35 on every phone that holds
   it.
4. **A lapsed licence cannot be used, and deletes nothing.** The phone stops connecting to the
   firm's systems: Avenkin Office, Workiz ([Plan JR](JR-workiz-from-the-phone.md)) and any job system
   like them. Field Assist's team features lock. Stored credentials, jobs, reports and manuals stay
   on the phone, and they work again the moment a paid code arrives.
5. **The person's own use of the app is untouched.** Accessibility is mainly for personal users, and
   a lapsed organisation licence takes nothing from someone's own setup.
6. **Sales first, seats second.** P0–P1 change nothing in the app. P2 counts phones against `seats`
   and changes the app.

**Amends** [Plan EE](EE-field-assist-commercial-licensing.md) ("What seats mean": seats recorded, not
enforced) and [Plan EI](EI-licence-issuance-portal.md) (non-goal: "A seat server, per-device
activation, or device binding"). Both stay true until P2 ships, and only for licences P2 marks as
seat-checked. **Builds on EI:** this plan takes EI's recommended design (A), a vendor-hosted service
holding the key and validating against a partner grant, and its pure core as written. It adds what EI
left open: payment, the provisional term, delivering a replacement code without retyping, and seats.

---

## Product promise

To the partner: "Order a licence for a customer and hand over the key the same afternoon. You get
an invoice with 30 days to pay. Pay it and the licence runs its full term with nothing to re-enter.
Don't, and it stops on day 35."

To the vendor: "Every code is on the ledger, every ledger row is on an invoice, and the credit we
extend is 35 days of one order, never a year."

To the technician: nothing about money. The phone works from the moment the key is entered. If an
invoice goes unpaid, the phone stops connecting to the office and the job system, and Field Assist
shows the message it already shows for an expired licence. Nothing is erased, and the person's own
use of the app carries on.

## Verified starting point (main, 2026-10-23)

- **A code is strict, offline and immutable.** `LicenseService.decode` accepts exactly two
  components (`base64(payload).base64(signature)`) under one embedded Ed25519 key. The payload's
  `expires` is signed, so a code's term cannot change. "Changing to the full term" therefore means
  **minting a second code** and getting it onto the phone.
- **A licence can point at a profile, and a profile can carry a newer licence.** The `profile` claim
  (CT 3a, `--profile` on the generator) makes entering the key enrol the phone in the organisation's
  hosted profile. `OrgProfileManager` re-fetches that address at launch and on foreground, at most
  once a day (`ProfileLease.renewalInterval` = 86,400 s). `renew(with:)` activates the renewed
  profile's `licenceCode` when it differs from the one in force. **So a full-term code published in
  the profile reaches every enrolled phone on its next daily fetch, with nothing typed.** This is the
  mechanism decision 3 needs, and it already ships.
- **A minimal profile is valid.** `ConfigProfile` needs only `profileId`, `organizationName`,
  `issued`, `leaseDays` (held to 7–365) and `settings`, which may be empty. `licenceCode` is
  optional. `Scripts/make-org-profile.swift` signs one with the profile key (`og-profile-2026-09`,
  separate from the licence key, domain-separated).
- **The short activation key resolves through the public site, at a fixed address.**
  `ActivationKey.defaultDirectory` is `PublicSite.activationDirectory`, the `activation/` directory
  `Scripts/stage-pages-site.sh` publishes. Every shipped build reads it there. The server cannot
  serve activation files itself without an app change, so **P1 publishes the sealed files to the
  public site.** The profile address is different, because it sits inside the signed licence, so it
  can point at the server.
- **An expired licence locks, it does not erase.** The entitlement provider re-decodes the stored
  code on every read, and an expired `expires` fails the gates. The status card says *"This licence
  has expired. Enter a renewal code from your administrator."* Plan IL keeps the same rule for its
  technician app: finished jobs stay readable and composed reports can still be sent.
- **The office connection already stops on an expired licence.** `OfficeInlineEntitlement.verify`
  refuses a licence past its `expires` (`notCurrentlyValid`), and `OfficeFieldConnectionPolicy` turns
  that into `.stop(.managementLapsed)`. The saved approval is rechecked every 30 s while the
  connection runs (`approvalRecheckInterval`), so a lapse ends a live connection within half a
  minute, and a missing licence stops it the same way (`.missingLicence`). **The recheck is local:**
  `OfficePairingService.currentApprovedPeer()` reads only the stored record, the stored code, the
  phone's own stores and its clock. It makes no network call, so being out of signal neither
  triggers a lapse nor delays one. The network matters for one thing only: getting the paid code
  (see *A phone offline on the day of payment*).
- **Workiz is implemented (JR, #837).** It checks the live licence before every request and retains
  local credentials and state at lapse. P0 uses its fixture tests; live qualification remains deferred.
- **A profile lapse or revocation is different, and harsher.** A lapsed profile lease withholds the
  licence the profile brought. `eraseAfterLapseDays` (an organisation opt-in) erases the firm's
  content, and a signed revocation erases it after delivering records. **An unpaid invoice must
  therefore be expressed only as a licence expiry, never as a lease lapse or a revocation.**
- **A phone already has an enrolment id** (`OrgProfileManager.newEnrolmentId`, eight hex characters
  made on the phone), but it never sends it anywhere: the renewal fetch is an anonymous GET of a
  static address. Nothing on any server can count phones today.
- **There is no vendor server.** Signed artefacts are static files on the public site. This plan
  builds the first networked vendor service, with the blast-radius reasoning EI already set out.

## How an order runs (P0–P1, no app change)

```
day 0   partner orders: customer, seats, term, packs, reference
        → server validates against the partner's grant and credit (pure policy)
        → mints a provisional code: expires = day 35, profile = <server>/p/<profileId>
        → signs the customer's profile carrying that code; serves it at that address
        → seals the activation file and publishes it to the public site's activation/
        → shows the short key and its QR once; ledger row written
        → raises invoice INV-…: due day 30, bank details, reference = invoice number
day 0+  customer's phones take the key → licence active → enrolled in the profile
paid    vendor records the payment against the invoice
        → server mints the full-term code (expires = day 0 + term), replaces = provisional row
        → re-signs the profile with it; re-seals the activation file with it
        → each phone picks it up on its next daily fetch
day 30  unpaid: reminder to the partner; no new orders while overdue
day 35  unpaid: the provisional code lapses on every phone; no office or job-system connection,
        Field Assist locks, nothing erased
late    paid after day 35: full-term code published as above; phones recover on their next fetch
```

**The full term starts on day 0, not on the day of payment.** The customer has been using the
licence since issue. Paying late does not buy extra days, and paying early loses none.

**Renewals need no provisional code.** The renewal invoice is raised at least 35 days before the
running code expires. When it is paid, the next term's code goes into the profile, and the phones
switch to it when it is issued. Unpaid, the current code simply runs out at the end of its term.
Provisional codes exist only for new customers and for seat increases.

**What every code the server mints carries:** the `profile` claim (so a replacement can reach the
phone), `reference` = the order id, and `seats`. The profile carries no settings unless the
customer's organisation also uses CT configuration, and its `leaseDays` is longer than the
provisional window (at least 60). The lease must never be the thing that runs out first.

**A phone offline on the day of payment** still lapses on day 35 if it has not fetched since. It
recovers on its first fetch after that. The partner's view says how many phones have not yet picked up
the full code once P2 can see them. Before P2, the server only knows the profile was fetched, not
by whom.

**The pilot's existing code** was hand-minted with no `profile` claim. It cannot be upgraded in place.
When the pilot becomes a paid order, its phones enter the new key once.

### What a lapse stops, and what it keeps

**Stops: every connection to the firm's systems.** It does this by checking the live licence each
time, not by remembering a decision made at setup.
- **Avenkin Office:** already done (see *Verified starting point*). P0 adds a test that pins it to a
  lapsed provisional code.
- **Workiz, and every later job-system connection on the phone:** the client checks the live Field
  Assist entitlement (`FieldAssistEntitlement.shared`, which re-decodes the stored code) before
  **every** request, not only when its Settings section is drawn. A refused check sends nothing and
  says *"⟨licensee⟩'s licence has expired. Your administrator can renew it."* The saved API key is
  kept. This is a requirement on Plan JR's P1, and JR's tests carry it: a lapsed licence sends no
  request and keeps the key.
- **Field Assist's team features:** locked through the gates that exist (vaults, packs, procedures,
  audited export, team learnings).

**Keeps: everything on the phone.** Credentials, jobs, reports, captured manuals and the profile all
stay. Reports finished before the lapse wait in their outbox and go when a paid code arrives. Nothing
is lost, and nothing reaches the firm while unpaid. The lapse never triggers CT's lapse erasure or
revocation, and the profile's lease runs on.

**Untouched: the person's own app.** Their own model keys, conversations, memory and the
accessibility tier carry on. A lapse is about the firm's licence, and the firm's systems are what
stop.

**The way back is automatic.** The daily profile fetch keeps running while the licence is lapsed,
because it is how the paid code arrives. The status card's *Check for Renewal* runs it at once.

### Bank transfer, specifically

- **Invoices are immutable and numbered in sequence.** A mistake is corrected with a credit note,
  never an edit. The number is the payment reference the partner puts on the transfer.
- **Recording a payment is a vendor action:** invoice number, amount, date received and the bank's
  reference, from the bank statement. Only a payment covering the invoice in full marks it paid. A
  short payment is recorded and the invoice stays open (see *Open questions*). Recording asks for
  confirmation, because once a full-term code is published it cannot be withdrawn (see *Failure
  cases*).
- **Amounts come from the partner's agreement**, as a wholesale price table on the grant: currency,
  per seat per term, and the tax treatment the agreement states. No figure appears in this plan or
  in the repo.
- **An accounting export** (CSV of invoices, credit notes and payments for a period) is the hand-off
  to the vendor's books. The server keeps no accounts of its own.
- **Credit is bounded by the grant:** `maxUnpaidSeats` caps the seats on open invoices, and any
  invoice past due refuses new orders (`.overdueInvoice`) until it is paid. Pilots raise no invoice
  and stay within `maxPilotDays`, as EI defines them.

### What the partner and the vendor see

The partner uses a web portal. **Order** has EI's four fields (customer, term, seats, reference)
plus the packs the grant allows. Submitting shows the short key, its QR and the long code once.
**Ledger** lists every code, showing provisional, paid, lapsed or replaced, with the date a
provisional code lapses unless paid. **Invoices** shows open, paid and overdue invoices, each with
bank details and a PDF. **Renewals** lists codes expiring within 60 days, with a Renew action.

The vendor uses a console. It covers partner grants (EI's table plus the price table and credit
limits), record payment, overdue invoices with their lapse dates, the period export, and every
partner's ledger.

## Device seats (P2, app change)

P2 makes `seats` a number the server enforces, by claiming a seat at first use. EI rejected device
binding because it "requires knowing the device before selling". A claim happens after the sale, on
the phone, so that objection does not apply.

1. **Only seat-checked licences are counted.** The server mints new codes with a signed claim
   `seatCheck: true`. A code without it (every code issued before P2, and any hand-minted one)
   behaves exactly as today. Older builds ignore the unknown claim (synthesised `Decodable`), so they
   activate it as a plain licence. See *Failure cases*.
2. **Claiming a seat.** On enrolment, the phone makes a P-256 key in the Secure Enclave (not
   exportable, not in backups). It sends `{profileId, enrolmentId, devicePublicKey, build}`, signed
   by that key over a server nonce, to `POST <server>/seats/claim`. If the licence has a free seat,
   the server records the claim and returns a **seat lease**, signed by a third vendor key with its
   own domain prefix: `{licenseIDHash, enrolmentId, deviceKeyHash, issued, notAfter}`.
3. **The lease is checked offline, on every entitlement read**, the same way the code is. For a
   seat-checked licence, the evidence is only live while the stored lease verifies, names this
   phone's Secure Enclave key and has not passed `notAfter` plus a grace period. A copied lease fails
   on another phone because that phone does not hold the key.
4. **Renewal rides the daily profile fetch.** The phone presents its lease and gets a new
   `notAfter`. Leaning: a 14-day lease with 7 days' grace, so a phone in a plant room for a fortnight
   keeps working and a lost phone frees its seat within three weeks.
5. **Seats come back** when the partner (or the vendor) frees one in the portal, when the phone's
   owner-gated removal releases it, or when a lease is not renewed. A freed phone keeps working until
   its current lease runs out. Leases are verified offline, so that overlap is the honest bound, and
   it is at most one lease period.
6. **A full licence** gets a plain answer on the phone: *"All N seats for ⟨licensee⟩ are in use. Ask
   your administrator to free one."* It is treated exactly like a lapse: no office or job-system
   connection, and Field Assist locked. The person's own use of the app is unaffected.
7. **Unpaid, with P2:** the server also stops renewing seat leases for a lapsed provisional code. A
   full-term code published by mistake (see *Failure cases*) can now be stopped too, without a
   revocation: its seat leases are not renewed.

**What P2 sends, and the disclosure it needs.** The enrolment id, a device public key, the app build
and the profile id. It sends no name, no device model, no vendor identifier and no location. The
server does not store IP addresses. By the telemetry rule ("off by default, disclosed by exception,
never silent"), the privacy manifest entry and the in-app privacy copy land in the same PR. Only a
phone holding a seat-checked licence makes the call.

**Phone without office.** The claim is made from the phone. Avenkin Office plays no part, and a firm
running it gains nothing it needs and loses nothing.

## Failure cases

| Case | What happens |
|---|---|
| Invoice unpaid | Provisional code lapses on day 35. The office and job-system connections stop and Field Assist locks. Nothing is erased, and finished reports wait in their outbox. Paid later, phones recover on their next fetch. |
| Partner orders and never pays | Bounded by `maxUnpaidSeats` and 35 days. Once an invoice is overdue, no new orders. |
| Payment recorded by mistake | The full-term code is published and, before P2, cannot be withdrawn. Phones verify offline and the only lever is a signed revocation, which erases the firm's content. Hence the confirmation step. With P2, seat leases simply stop renewing. |
| Phone offline at payment | Lapses on day 35 if it has not fetched since; recovers on first fetch. |
| Server down | Phones are unaffected: codes, profiles and leases verify offline, and a failed fetch only fails to renew. Partners cannot order, and the vendor's manual generator still works (EI). With P2, an outage longer than lease plus grace locks seat-checked phones. That is the price of enforcement, and the reason the lease is not short. |
| Customer shares the short key beyond its seats | Before P2: unchanged, as EE and EI say. With P2: the extra phones are refused a seat. |
| Customer keeps an old build to avoid seat checks | An older build ignores `seatCheck`. The App Store serves only the current build to new installs, so the gap closes as phones update. A minimum-build requirement is an open question, not a design. |
| Reinstall without the keychain | A new key means a new claim. The old claim lapses with its lease, or the partner frees it. |
| Server compromised | Codes, profiles and leases could be minted. No phone's verification changes. The signer is isolated from the web tier, as EI says, and now holds three keys (licence, profile, seat lease), each with its own domain prefix. |

## Build order

**P0 — pure core, headless (this repo, one PR).** EI's P1 unchanged: a Swift package
`Tools/LicenceIssuance/` with `PartnerGrant`, `IssuanceRequest`, `IssuanceRefusal`,
`IssuancePolicy.validate`, the hash-chained ledger, payload construction pinned to the app's encoder,
the generator as a thin caller, and `swift test` in CI. Additions:
- `Order` and its states (provisional → paid → active; provisional → lapsed → paid late → active;
  replaced), and the term rule: provisional `expires` = issue + 35 days, full `expires` = issue +
  term.
- `Invoice` (sequential number, lines from the grant's price table, due date, immutable), `CreditNote`,
  `Payment`, and status derived from payments rather than stored.
- Credit refusals: `.overdueInvoice`, `.unpaidSeatLimit`.
- Profile construction through `make-org-profile.swift`'s contract, and activation-file sealing
  through the generator's, both shared rather than copied.
- **The no-app-change test.** A provisional code with a `profile` claim enrols through
  `OrgProfileManager`'s seams. A renewed profile carrying the full-term code is activated by
  `renew(with:)`. The provisional code lapsing on day 35 locks the entitlement and erases nothing,
  and `OfficeFieldConnectionPolicy.afterFailure` answers its `notCurrentlyValid` with
  `.stop(.managementLapsed)`. The full code restores both. No existing app test changes.

**P1 — the service (separate private repository; in-repo, only `docs/licensing/partner-issuance.md`).**
The partner portal, the vendor console, the isolated signer, profile hosting at the address the
codes name, publishing sealed activation files to the public site, the daily job (reminders on day
30, lapse report on day 35, renewal invoices 35 days out), invoice PDFs and the accounting export.
The operating document covers key handling, the recovery path with the manual generator, and how a
payment is recorded.

**P2 — device seats (app + service, one PR per side).** App side: the `seatCheck` claim in
`LicensePayload` and the generator (same `.sortedKeys` contract), a pure `SeatLease` verifier with
its domain prefix and embedded key, a Secure Enclave key seam (fake in tests), the claim and renew
client on `BoundedHTTPClient` with its own `NetworkRoute`, entitlement evidence that requires a live
lease for seat-checked licences, the "all seats in use" state, release on removal, and the privacy
manifest and copy. Service side: claim, renew and release endpoints, seat counting, and the seat list
with Free in both consoles.

**P3 — later, each optional.** A warning on the customer administrator's phone before an unpaid
lapse. Bank-statement import to match payments by reference. Emailing invoices from the server
(until then the vendor downloads and sends them).

## Tests

- **P0:** EI's tests as listed there (byte compatibility, indistinguishability, one test per refusal,
  quota, ledger integrity, billing, packs round trip). Also: provisional and full expiry from a fixed
  clock; a late payment's full code ends on day 0 + term; a renewal paid before expiry starts the
  next term at the old `expires`; an overdue invoice refuses an order; unpaid seats at the cap refuse
  an order; invoice numbers never repeat or skip; an edited invoice is impossible (a credit note is
  the only correction); a short payment leaves the invoice open; and the no-app-change test above.
- **P2:** a lease verifies only with its own domain prefix and key; a lease naming another device key
  fails; a lease past `notAfter` plus grace fails; a licence without `seatCheck` grants with no lease,
  exactly as today; a seat-checked licence with no lease is locked with the "all seats in use" or
  "connect once" state; renewal extends `notAfter`; removal sends a release; a property test that the
  claim request carries no field beyond the four listed; and the privacy-manifest pairing in
  `TelemetryOptOutGuardTests`.

## Non-goals

- **A card processor or stored payment details.** Bank transfer, marked paid by the vendor.
- **Billing per seat in use.** The customer buys N seats, and P2 makes N a cap, so the invoice stays
  per order.
- **Selling to consumers.** Solo stays on the App Store. Nothing about this service appears in the
  app, and EE's copy guard stands.
- **Accounts for technicians.** A seat is a phone, not a person. Identity stays CT's axis.
- **Seat checks for Medical Compliance or anything but Field Assist.** Accessibility is free and never
  gated.
- **Revocation as a payment tool.** An unpaid invoice is a licence expiry and nothing harsher.
- **Locking the whole app.** A lapse stops the firm's connections and its Field Assist features, not
  the person's own app or the accessibility tier.

## Open questions

- **Tax and currency on invoices.** The vendor invoices from New Zealand to partners abroad. The
  agreement and the vendor's accountant decide the tax treatment. The server only prints what the
  grant states.
- **Short payments and bank fees** on international transfers: treat an invoice as paid within a set
  tolerance, or keep it open until the balance arrives?
- **Who may free a seat:** the partner only, or also the customer's administrator phone (CT 3b)?
- **Lease length and grace** for P2. Leaning 14 + 7 days.
- **Whether to require a minimum build** for seat-checked licences, and how the app would say so.
- **Where the service runs**, and in what language. Leaning Swift on Linux (swift-crypto), so the
  service uses the P0 package itself rather than a port held to golden fixtures.
- **Whether the customer is told before an unpaid lapse** (P3), given it puts the partner's billing
  dispute on the customer's screen.
- **Finished reports during a lapse.** This plan holds them in the outbox until a paid code arrives,
  consistent with "can't be used". Plan IL's decision 7 lets a lapsed technician app send reports
  already composed, because a late invoice should not hurt the customer. The two should agree.
  Leaning: hold, since the firm can end the hold by paying.
- **Whether the provisional window is fixed at 35 days or per grant.** Leaning fixed: it is the
  credit term, and a partner-by-partner number invites negotiation over it.

## P0 implementation notes (2026-10-23)

The package and terminal are under [`Tools/LicenceIssuance`](../../Tools/LicenceIssuance/README.md).
P0 adopts EI's bill-on-issuance quota model and exact payment coverage (no short-payment tolerance).
Prices and tax text are agreement-supplied immutable invoice snapshots. Credits correct accounting
without authorizing a paid code. A credited order needing a paid code is corrected/rebilled.
Profile/signing and activation sealing share the manual tools' contracts. Production app sources
and verification are unchanged; the test bundle alone compiles the vendor library.

Two starting-point assumptions are clarified by tests: CryptoKit signatures are randomized, so
byte compatibility means payload identity plus exact assembly using a fixed signature; Office
inline verification deliberately rejects hosted-profile licences, so hosted renewal and the Office
inline lapse/restore gate are exercised through their distinct existing routes. P1 must still
implement durable delivery and hosting in the separate private service repository.
