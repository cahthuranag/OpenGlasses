// Package capturedmanual defines Plan IF's immutable photographed-manual contract.
// It grants no entitlement, indexes nothing and sends nothing. PDF parsing, independently
// established scope and current policy are supplied by the caller, never by the manifest.
package capturedmanual

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"unicode/utf8"
)

const (
	Kind               = "avenkin.captured-manual"
	MaximumManifest    = 131072
	MaximumPages       = 256
	MaximumText        = 8388608
	MaximumPDF         = 134217728
	MaximumImage       = 4194304
	maximumSafeInteger = int64(9007199254740991)
)

var (
	ErrMalformed = errors.New("noncanonical or malformed captured manual")
	ErrFields    = errors.New("invalid captured manual fields")
	ErrScope     = errors.New("captured manual is for another scope")
	ErrContent   = errors.New("captured manual content differs from manifest")
	ErrPages     = errors.New("captured manual page map differs from content")
)

type Scope struct{ OwnershipScope, OrganizationID, EnrolmentID, VaultID string }
type Page struct {
	Index           int    `json:"index"`
	ImageSHA256     string `json:"imageSHA256"`
	ImageBytes      int    `json:"imageBytes"`
	TextOffset      int    `json:"textOffset"`
	TextBytes       int    `json:"textBytes"`
	ConfidenceMilli int    `json:"confidenceMilli"`
	PrintedPage     int    `json:"printedPage"`
	OCRStatus       string `json:"ocrStatus"`
}
type Redaction struct {
	Pattern string `json:"pattern"`
	Count   int    `json:"count"`
}

// Declaration order is canonical member order. Source revision is not report revision.
type Manifest struct {
	Version              int         `json:"version"`
	Kind                 string      `json:"kind"`
	CaptureID            string      `json:"captureID"`
	CaptureRevision      int64       `json:"captureRevision"`
	SessionID            string      `json:"sessionID"`
	JobReference         string      `json:"jobReference"`
	JobID                string      `json:"jobID"`
	JobRevision          int64       `json:"jobRevision"`
	VaultID              string      `json:"vaultID"`
	OwnershipScope       string      `json:"ownershipScope"`
	OrganizationID       string      `json:"organizationID"`
	EnrolmentID          string      `json:"enrolmentID"`
	UnitID               string      `json:"unitID"`
	StatedModel          string      `json:"statedModel"`
	ConfirmedModelToken  string      `json:"confirmedModelToken"`
	Serial               string      `json:"serial"`
	Title                string      `json:"title"`
	Author               string      `json:"author"`
	CapturedAt           int64       `json:"capturedAt"`
	CapturePolicy        string      `json:"capturePolicy"`
	PoolIntent           string      `json:"poolIntent"`
	EncoderVersion       string      `json:"encoderVersion"`
	PageCount            int         `json:"pageCount"`
	OCRPages             int         `json:"ocrPages"`
	FailedPages          int         `json:"failedPages"`
	LowConfidencePages   int         `json:"lowConfidencePages"`
	RecognitionLanguages []string    `json:"recognitionLanguages"`
	RecognitionFallback  bool        `json:"recognitionFallback"`
	Pages                []Page      `json:"pages"`
	Redactions           []Redaction `json:"redactions"`
	TextSHA256           string      `json:"textSHA256"`
	TextBytes            int         `json:"textBytes"`
	PDFSHA256            string      `json:"pdfSHA256"`
	PDFBytes             int         `json:"pdfBytes"`
}

func (m Manifest) Scope() Scope {
	return Scope{m.OwnershipScope, m.OrganizationID, m.EnrolmentID, m.VaultID}
}
func Digest(b []byte) string { s := sha256.Sum256(b); return hex.EncodeToString(s[:]) }
func positive(n int64) bool  { return n > 0 && n <= maximumSafeInteger }
func identifier(s string) bool {
	if len(s) == 0 || len(s) > 80 || s == "." || s == ".." {
		return false
	}
	for _, c := range []byte(s) {
		if !(c >= '0' && c <= '9' || c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c == '-' || c == '_' || c == '.') {
			return false
		}
	}
	return true
}
func display(s string, max int) bool {
	if len(s) > max || !utf8.ValidString(s) {
		return false
	}
	for _, c := range s {
		if c < 32 || c == 127 {
			return false
		}
	}
	return true
}
func lowerHex(s string) bool {
	if len(s) != 64 {
		return false
	}
	for _, c := range []byte(s) {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
			return false
		}
	}
	return true
}
func (m Manifest) valid() bool {
	if m.Version != 1 || m.Kind != Kind || !identifier(m.CaptureID) || !identifier(m.SessionID) ||
		!positive(m.CaptureRevision) || !positive(m.CapturedAt) || !identifier(m.VaultID) ||
		!(m.UnitID == "" || identifier(m.UnitID)) || !display(m.JobReference, 120) ||
		!(m.JobID == "" && m.JobRevision == 0 || identifier(m.JobID) && positive(m.JobRevision)) ||
		!(m.OwnershipScope == "personal" && m.OrganizationID == "" && m.EnrolmentID == "" ||
			m.OwnershipScope == "organization" && identifier(m.OrganizationID) && identifier(m.EnrolmentID)) ||
		!display(m.StatedModel, 160) || !display(m.ConfirmedModelToken, 160) ||
		(m.ConfirmedModelToken != "" && m.StatedModel == "") || !display(m.Serial, 160) ||
		m.Title == "" || !display(m.Title, 240) || !display(m.Author, 160) || !identifier(m.EncoderVersion) ||
		!(m.CapturePolicy == "jobOnly" || m.CapturePolicy == "reviewToPool") ||
		!(m.PoolIntent == "jobOnly" || m.PoolIntent == "reviewToPool") ||
		(m.PoolIntent == "reviewToPool" && (m.CapturePolicy != "reviewToPool" || m.OwnershipScope != "organization")) ||
		m.PageCount < 1 || m.PageCount > MaximumPages || len(m.Pages) != m.PageCount ||
		m.OCRPages < 0 || m.OCRPages > m.PageCount || m.FailedPages < 0 || m.FailedPages > m.PageCount ||
		m.OCRPages+m.FailedPages != m.PageCount || m.LowConfidencePages < 0 || m.LowConfidencePages > m.PageCount ||
		len(m.RecognitionLanguages) < 1 || len(m.RecognitionLanguages) > 16 ||
		!lowerHex(m.TextSHA256) || !lowerHex(m.PDFSHA256) || m.TextBytes < 1 || m.TextBytes > MaximumText ||
		m.PDFBytes < 1 || m.PDFBytes > MaximumPDF || len(m.Redactions) > 64 {
		return false
	}
	languages := map[string]bool{}
	for _, s := range m.RecognitionLanguages {
		if !identifier(s) || languages[s] {
			return false
		}
		languages[s] = true
	}
	end, recognized, low := 0, 0, 0
	for i, p := range m.Pages {
		if p.Index != i+1 || !lowerHex(p.ImageSHA256) || p.ImageBytes < 1 || p.ImageBytes > MaximumImage ||
			p.TextOffset < end || p.TextOffset > m.TextBytes || p.TextBytes < 0 || p.TextBytes > m.TextBytes-p.TextOffset ||
			p.ConfidenceMilli < 0 || p.ConfidenceMilli > 1000 || p.PrintedPage < 0 || p.PrintedPage > 9999 ||
			!(p.OCRStatus == "recognized" || p.OCRStatus == "failed") ||
			(p.OCRStatus == "failed" && (p.TextBytes != 0 || p.ConfidenceMilli != 0 || p.PrintedPage != 0)) {
			return false
		}
		end = p.TextOffset + p.TextBytes
		if p.OCRStatus == "recognized" {
			recognized++
		}
		if p.ConfidenceMilli < 500 {
			low++
		}
	}
	if recognized != m.OCRPages || low != m.LowConfidencePages {
		return false
	}
	for i, r := range m.Redactions {
		if !identifier(r.Pattern) || r.Count < 1 || r.Count > 1000000 || (i > 0 && m.Redactions[i-1].Pattern >= r.Pattern) {
			return false
		}
	}
	return true
}

// CanonicalBytes fixes JSON member order and escaping. Reflection is limited to this closed
// schema: strings, integers, booleans, arrays and structs. Maps/floats/null never enter it.
func CanonicalBytes(m Manifest) ([]byte, error) {
	if !m.valid() {
		return nil, ErrFields
	}
	var b strings.Builder
	canonical(&b, reflect.ValueOf(m))
	if b.Len() > MaximumManifest {
		return nil, ErrFields
	}
	return []byte(b.String()), nil
}
func quote(b *strings.Builder, s string) {
	b.WriteByte('"')
	for _, c := range s {
		switch {
		case c < 32:
			fmt.Fprintf(b, "\\u%04x", c)
		case c == '"' || c == '\\':
			b.WriteByte('\\')
			b.WriteRune(c)
		default:
			b.WriteRune(c)
		}
	}
	b.WriteByte('"')
}
func canonical(b *strings.Builder, v reflect.Value) {
	switch v.Kind() {
	case reflect.String:
		quote(b, v.String())
	case reflect.Int, reflect.Int64:
		fmt.Fprint(b, v.Int())
	case reflect.Bool:
		fmt.Fprint(b, v.Bool())
	case reflect.Slice:
		b.WriteByte('[')
		for i := 0; i < v.Len(); i++ {
			if i > 0 {
				b.WriteByte(',')
			}
			canonical(b, v.Index(i))
		}
		b.WriteByte(']')
	case reflect.Struct:
		b.WriteByte('{')
		for i := 0; i < v.NumField(); i++ {
			if i > 0 {
				b.WriteByte(',')
			}
			quote(b, v.Type().Field(i).Tag.Get("json"))
			b.WriteByte(':')
			canonical(b, v.Field(i))
		}
		b.WriteByte('}')
	default:
		panic("unsupported canonical captured-manual schema type")
	}
}
func Read(raw []byte) (Manifest, error) {
	var m Manifest
	if len(raw) == 0 || len(raw) > MaximumManifest || !utf8.Valid(raw) || json.Unmarshal(raw, &m) != nil {
		return Manifest{}, ErrMalformed
	}
	exact, e := CanonicalBytes(m)
	if e != nil {
		return Manifest{}, e
	}
	if string(exact) != string(raw) {
		return Manifest{}, ErrMalformed
	}
	return m, nil
}

// Validate checks exact files and authoritative capture-order ranges. pdfPageCount must be
// obtained by parsing these PDF bytes within the caller's limits, never from an untrusted claim.
func Validate(raw, text, pdf []byte, pdfPageCount int, scope Scope) (Manifest, error) {
	m, e := Read(raw)
	if e != nil {
		return Manifest{}, e
	}
	if m.Scope() != scope {
		return Manifest{}, ErrScope
	}
	if len(text) != m.TextBytes || Digest(text) != m.TextSHA256 || len(pdf) != m.PDFBytes || Digest(pdf) != m.PDFSHA256 {
		return Manifest{}, ErrContent
	}
	if pdfPageCount != m.PageCount || !utf8.Valid(text) {
		return Manifest{}, ErrPages
	}
	offset := 0
	for _, p := range m.Pages {
		header := fmt.Sprintf("## Page %d\n\n", p.Index)
		if offset+len(header) != p.TextOffset || string(text[offset:p.TextOffset]) != header {
			return Manifest{}, ErrPages
		}
		end := p.TextOffset + p.TextBytes
		if !utf8.Valid(text[p.TextOffset:end]) || end+2 > len(text) || string(text[end:end+2]) != "\n\n" {
			return Manifest{}, ErrPages
		}
		offset = end + 2
	}
	if offset != len(text) {
		return Manifest{}, ErrPages
	}
	return m, nil
}
