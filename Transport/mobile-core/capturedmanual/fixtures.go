package capturedmanual

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
)

// Fixture has only fictional metadata and hand-authored text. The three-page PDF is a
// deterministic blank test document, not output from OCR, VisionKit or a production encoder.
func Fixture() (Manifest, []byte, []byte) {
	bodies := []string{"Pressure < 20 & verify \"A\".\nPage 41\nCafé: [REDACTED]", "", "温度 20 °C\n— 43 —"}
	var text strings.Builder
	pages := make([]Page, 3)
	for i, body := range bodies {
		fmt.Fprintf(&text, "## Page %d\n\n", i+1)
		image := []byte(fmt.Sprintf("Avenkin public fictional normalized page %d", i+1))
		pages[i] = Page{i + 1, Digest(image), len(image), text.Len(), len([]byte(body)), []int{420, 0, 900}[i], []int{41, 0, 43}[i], []string{"recognized", "failed", "recognized"}[i]}
		text.WriteString(body)
		text.WriteString("\n\n")
	}
	pdf := fixturePDF()
	m := Manifest{Version: 1, Kind: Kind, CaptureID: "fixture-capture-1", CaptureRevision: 1,
		SessionID: "3F2504E0-4F89-11D3-9A0C-0305E82C3301", JobReference: "JOB-1042", JobID: "job-2031", JobRevision: 2,
		VaultID: "fixture-vault", OwnershipScope: "organization", OrganizationID: "fixture-organisation", EnrolmentID: "fixture-enrolment",
		UnitID: "fixture-unit-1", StatedModel: "Fictional HX-40", ConfirmedModelToken: "hx40", Serial: "fictional-serial", Title: "Fictional \"HX-40\" — café <guide> & notes",
		Author: "Fixture technician", CapturedAt: 1800000000, CapturePolicy: "reviewToPool", PoolIntent: "jobOnly", EncoderVersion: "fixture-pdf-v1",
		PageCount: 3, OCRPages: 2, FailedPages: 1, LowConfidencePages: 2, RecognitionLanguages: []string{"fr-FR", "en-US"},
		RecognitionFallback: false, Pages: pages, Redactions: []Redaction{{"api_key", 1}},
		TextSHA256: Digest([]byte(text.String())), TextBytes: text.Len(), PDFSHA256: Digest(pdf), PDFBytes: len(pdf)}
	return m, []byte(text.String()), pdf
}
func fixturePDF() []byte {
	objects := []string{
		"<< /Type /Catalog /Pages 2 0 R >>",
		"<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> >>",
		"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << >> >>",
	}
	var b strings.Builder
	b.WriteString("%PDF-1.4\n")
	offsets := []int{0}
	for i, object := range objects {
		offsets = append(offsets, b.Len())
		fmt.Fprintf(&b, "%d 0 obj\n%s\nendobj\n", i+1, object)
	}
	xref := b.Len()
	fmt.Fprintf(&b, "xref\n0 %d\n0000000000 65535 f \n", len(offsets))
	for _, offset := range offsets[1:] {
		fmt.Fprintf(&b, "%010d 00000 n \n", offset)
	}
	fmt.Fprintf(&b, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(offsets), xref)
	return []byte(b.String())
}

type NegativeFixture struct {
	Name     string `json:"name"`
	Manifest string `json:"manifest"` // base64, so malformed UTF-8 can be represented
}

// NegativeFixtures is shared by Swift and Go. Invalid field cases keep canonical member
// order so they exercise validation rather than merely failing on a re-ordered JSON object.
func NegativeFixtures() []NegativeFixture {
	m, _, _ := Fixture()
	raw, _ := CanonicalBytes(m)
	var cases []NegativeFixture
	add := func(name string, raw []byte) {
		cases = append(cases, NegativeFixture{name, base64.StdEncoding.EncodeToString(raw)})
	}
	for _, c := range []struct {
		name   string
		change func(*Manifest)
	}{
		{"source revision zero", func(m *Manifest) { m.CaptureRevision = 0 }},
		{"unsafe integer", func(m *Manifest) { m.CaptureRevision = maximumSafeInteger + 1 }},
		{"capture id is a path", func(m *Manifest) { m.CaptureID = "../book" }},
		{"unknown ownership", func(m *Manifest) { m.OwnershipScope = "shared" }},
		{"personal with organization", func(m *Manifest) { m.OwnershipScope = "personal" }},
		{"organization missing enrolment", func(m *Manifest) { m.EnrolmentID = "" }},
		{"job id without revision", func(m *Manifest) { m.JobRevision = 0 }},
		{"confirmed token without stated model", func(m *Manifest) { m.StatedModel = "" }},
		{"pool under job-only policy", func(m *Manifest) { m.CapturePolicy = "jobOnly"; m.PoolIntent = "reviewToPool" }},
		{"off policy cannot commit", func(m *Manifest) { m.CapturePolicy = "off" }},
		{"duplicate language", func(m *Manifest) { m.RecognitionLanguages = []string{"en-US", "en-US"} }},
		{"wrong page count", func(m *Manifest) { m.PageCount = 2 }},
		{"wrong OCR count", func(m *Manifest) { m.OCRPages = 3; m.FailedPages = 0 }},
		{"wrong low confidence count", func(m *Manifest) { m.LowConfidencePages = 0 }},
		{"wrong page index", func(m *Manifest) { m.Pages[2].Index = 4 }},
		{"overlapping ranges", func(m *Manifest) { m.Pages[1].TextOffset = 1 }},
		{"negative offset", func(m *Manifest) { m.Pages[0].TextOffset = -1 }},
		{"range exceeds text", func(m *Manifest) { m.Pages[2].TextBytes = m.TextBytes }},
		{"overflowing range", func(m *Manifest) { m.Pages[2].TextBytes = int(^uint(0) >> 1) }},
		{"fractional confidence outside bound", func(m *Manifest) { m.Pages[0].ConfidenceMilli = 1001 }},
		{"failed page has text", func(m *Manifest) { m.Pages[1].TextBytes = 1 }},
		{"uppercase digest", func(m *Manifest) { m.PDFSHA256 = strings.ToUpper(m.PDFSHA256) }},
		{"oversized PDF", func(m *Manifest) { m.PDFBytes = MaximumPDF + 1 }},
		{"oversized image", func(m *Manifest) { m.Pages[0].ImageBytes = MaximumImage + 1 }},
		{"empty text", func(m *Manifest) { m.TextBytes = 0 }},
		{"duplicate redaction", func(m *Manifest) { m.Redactions = append(m.Redactions, m.Redactions[0]) }},
		{"control in title", func(m *Manifest) { m.Title = "book\nsecret" }},
	} {
		changed, _, _ := Fixture()
		c.change(&changed)
		var b strings.Builder
		canonical(&b, reflect.ValueOf(changed))
		add(c.name, []byte(b.String()))
	}
	for _, c := range []struct{ name, old, new string }{
		{"duplicate root member", `{"version":1,`, `{"version":1,"version":1,`},
		{"unknown root member", `{"version":1,`, `{"version":1,"unknown":0,`},
		{"missing member", `"captureRevision":1,`, ``},
		{"exponent integer", `"captureRevision":1,`, `"captureRevision":1e0,`},
		{"fractional integer", `"captureRevision":1,`, `"captureRevision":1.0,`},
		{"duplicate page member", `"index":1,`, `"index":1,"index":1,`},
		{"unknown page member", `"index":1,`, `"index":1,"source":"x",`},
		{"null redactions", `"redactions":[{"pattern":"api_key","count":1}]`, `"redactions":null`},
		{"escaped slash", `fixture-vault`, `fixture\u002dvault`},
		{"whitespace", `{"version":1,`, `{ "version":1,`},
		{"nested integer", `"captureRevision":1,`, `"captureRevision":{"n":1},`},
	} {
		add(c.name, []byte(strings.Replace(string(raw), c.old, c.new, 1)))
	}
	add("trailing data", append(append([]byte{}, raw...), []byte("{}")...))
	add("empty", nil)
	add("over manifest cap", make([]byte, MaximumManifest+1))
	add("invalid UTF8", []byte{0xff})
	return cases
}
func Fixtures() (map[string][]byte, error) {
	m, text, pdf := Fixture()
	manifest, e := CanonicalBytes(m)
	if e != nil {
		return nil, e
	}
	negatives, e := json.Marshal(NegativeFixtures())
	if e != nil {
		return nil, e
	}
	return map[string][]byte{"captured-manual-v1.json": manifest, "captured-manual-text-v1.md": text,
		"captured-manual-pages-v1.pdf": pdf, "captured-manual-digest-v1.txt": []byte(Digest(manifest) + "\n"),
		"captured-manual-negative-v1.json": negatives}, nil
}
