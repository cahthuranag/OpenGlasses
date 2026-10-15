package capturedmanual

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestGoldenFixturesAndNegativeCorpus(t *testing.T) {
	made, e := Fixtures()
	if e != nil {
		t.Fatal(e)
	}
	root := filepath.Join("..", "..", "..", "Contracts", "fixtures")
	for name, want := range made {
		path := filepath.Join(root, name)
		if os.Getenv("CAPTURE_WRITE_FIXTURES") == "1" {
			if e := os.WriteFile(path, want, 0644); e != nil {
				t.Fatal(e)
			}
		}
		got, e := os.ReadFile(path)
		if e != nil || string(got) != string(want) {
			t.Fatalf("stale fixture %s: %v", name, e)
		}
	}
	m, text, pdf := Fixture()
	raw, _ := CanonicalBytes(m)
	if got, e := Validate(raw, text, pdf, 3, m.Scope()); e != nil || got.CaptureID != m.CaptureID {
		t.Fatal(e)
	}
	for _, c := range NegativeFixtures() {
		t.Run(c.Name, func(t *testing.T) {
			raw, _ := base64.StdEncoding.DecodeString(c.Manifest)
			if _, e := Read(raw); e == nil {
				t.Fatal("accepted")
			}
		})
	}
}
func TestExactContentScopeAndPageBoundaries(t *testing.T) {
	m, text, pdf := Fixture()
	raw, _ := CanonicalBytes(m)
	for name, c := range map[string]struct {
		text, pdf []byte
		count     int
		scope     Scope
	}{
		"changed text":             {append(append([]byte{}, text...), 10), pdf, 3, m.Scope()},
		"changed PDF":              {text, append(append([]byte{}, pdf...), 10), 3, m.Scope()},
		"wrong physical PDF count": {text, pdf, 2, m.Scope()},
		"another organization":     {text, pdf, 3, Scope{"organization", "other-org", m.EnrolmentID, m.VaultID}},
		"another vault":            {text, pdf, 3, Scope{m.OwnershipScope, m.OrganizationID, m.EnrolmentID, "other-vault"}},
		"another enrolment":        {text, pdf, 3, Scope{m.OwnershipScope, m.OrganizationID, "other-enrolment", m.VaultID}},
	} {
		t.Run(name, func(t *testing.T) {
			if _, e := Validate(raw, c.text, c.pdf, c.count, c.scope); e == nil {
				t.Fatal("accepted")
			}
		})
	}
	// These carry correct hashes and bounded non-overlapping ranges; only authoritative
	// UTF-8 ranges and exact furniture reveal them as invalid.
	for _, change := range []func(*Manifest){
		func(m *Manifest) { m.Pages[2].TextOffset++; m.Pages[2].TextBytes-- },
		func(m *Manifest) { m.Pages[0].TextBytes-- },
	} {
		m, _, _ := Fixture()
		change(&m)
		raw, e := CanonicalBytes(m)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = Validate(raw, text, pdf, 3, m.Scope()); e != ErrPages {
			t.Fatalf("got %v", e)
		}
	}
	altered := []byte(strings.Replace(string(text), "## Page 3", "## Page 9", 1))
	m.TextSHA256 = Digest(altered)
	raw, _ = CanonicalBytes(m)
	if _, e := Validate(raw, altered, pdf, 3, m.Scope()); e != ErrPages {
		t.Fatal(e)
	}
	// Same OCR but different picture bytes must never deduplicate by the text digest.
	m, _, _ = Fixture()
	originalBytes, _ := CanonicalBytes(m)
	before := Digest(originalBytes)
	m.PDFSHA256 = Digest([]byte("another diagram"))
	other, _ := CanonicalBytes(m)
	if before == Digest(other) {
		t.Fatal("bundle identity did not change")
	}
	// Source revision and delivery revision cannot be conflated.
	m, _, _ = Fixture()
	original, _ := CanonicalBytes(m)
	m.CaptureRevision++
	retake, _ := CanonicalBytes(m)
	if Digest(original) == Digest(retake) {
		t.Fatal("retake did not change bundle identity")
	}
}
