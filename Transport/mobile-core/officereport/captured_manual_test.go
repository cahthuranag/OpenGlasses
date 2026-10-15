package officereport

import (
	"crypto/ed25519"
	"encoding/json"
	"testing"

	"avenkin.dev/mobilecore/capturedmanual"
)

func TestCapturedManualReportBindsOriginalScopeJobAndBothFiles(t *testing.T) {
	w := fixtureWorld(t)
	fixtures := must(Fixtures())
	envelope := string(fixtures["captured-manual-report-v1.json"])
	r := must(ReadReport(envelope, w.trust))
	capture, _, _ := capturedmanual.Fixture()
	record := must(capturedmanual.CanonicalBytes(capture))
	raw := fixtures["captured-manual-evidence-v1.json"]
	m := must(r.Carries(record, raw))
	if r.Revision != 4 || capture.CaptureRevision != 1 || r.RecordKind != RecordCapturedManual {
		t.Fatal("revision conflation")
	}
	for _, stage := range []string{"pending", "full"} {
		got := must(ReadReceipt(string(fixtures["captured-manual-receipt-"+stage+"-v1.json"]), w.office.Public().(ed25519.PublicKey), envelope, r, m))
		if Stage(got.Outcome) != stage {
			t.Fatal(got.Outcome)
		}
	}
	if _, e := ReadReceipt(w.receipts["full"], w.office.Public().(ed25519.PublicKey), envelope, r, m); e == nil {
		t.Fatal("another report's receipt accepted")
	}
	for name, edit := range map[string]func(*Report){
		"another capture":      func(r *Report) { r.RecordID = "another-capture" },
		"another job":          func(r *Report) { r.JobID = "another-job" },
		"another job revision": func(r *Report) { r.JobRevision++ },
		"another organization": func(r *Report) { r.OrganizationID = "other-org" },
		"another enrolment":    func(r *Report) { r.EnrolmentID = "other-enrolment" },
		"another reference":    func(r *Report) { r.JobReference = "JOB-1043" },
		"transcript claim":     func(r *Report) { r.Transcript = TranscriptOmitted },
	} {
		t.Run(name, func(t *testing.T) {
			changed := r
			edit(&changed)
			if _, e := changed.Carries(record, raw); e == nil {
				t.Fatal("accepted")
			}
		})
	}
	for _, role := range []string{RoleCapturedManualPDF, RoleCapturedManualText} {
		for _, edit := range []func(*Attachment){
			func(a *Attachment) { a.Audience = AudienceCustomer },
			func(a *Attachment) { a.MediaType = "image/jpeg" },
		} {
			altered := append([]Attachment{}, m.Attachments...)
			for i := range altered {
				if altered[i].Role == role {
					edit(&altered[i])
				}
			}
			if _, e := ManifestBytes(ManifestFor(altered)); e == nil {
				t.Fatal("invalid media/audience accepted")
			}
		}
	}
	for _, edit := range []func([]Attachment) []Attachment{
		func(a []Attachment) []Attachment { return a[:1] },
		func(a []Attachment) []Attachment { a[0].Requirement = Optional; return a },
		func(a []Attachment) []Attachment { a[0].Bytes++; return a },
		func(a []Attachment) []Attachment { a[0].SHA256 = Digest([]byte("another file")); return a },
	} {
		altered := ManifestFor(edit(append([]Attachment{}, m.Attachments...)))
		changedRaw := must(ManifestBytes(altered))
		changed := ReportFor(r, record, changedRaw)
		if _, e := changed.Carries(record, changedRaw); e == nil {
			t.Fatal("incomplete or mismatched evidence accepted")
		}
	}
	pending := must(ReadReceipt(string(fixtures["captured-manual-receipt-pending-v1.json"]), w.office.Public().(ed25519.PublicKey), envelope, r, m))
	pending.Outcome = OutcomeRecordAccepted
	pending.AttachmentsCommitted = 1
	pending.AttachmentsOutstanding = 1
	payload := must(json.Marshal(pending))
	bad := must(seal(payload, ed25519.Sign(w.office, SigningInput(ReceiptDomain, payload)), MaximumReceipt))
	if _, e := ReadReceipt(bad, w.office.Public().(ed25519.PublicKey), envelope, r, m); e == nil {
		t.Fatal("accepted with required evidence outstanding")
	}
}
