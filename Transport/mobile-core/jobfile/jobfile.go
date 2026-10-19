// Package jobfile is the reference implementation of job-file formats 2 and 3
// (Contracts/job-file.md): a job an office sends to a technician's phone, with an
// office-assigned identifier and revision, signed over its exact bytes. Format 3 is format 2's
// file under its own signature domain, whose job may also say where it came from and what the
// office knows about it (§10, format3.go).
//
// It reads and writes the outer file and checks the job's identity, and in format 3 the shape,
// bounds and cross-references of the members format 3 adds. The rules on what a job's text may
// say to a technician — plain text, no markup — are the phone's validator's and are written down
// in the contract; an office that wants its files accepted keeps to them.
package jobfile

import (
	"bytes"
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
)

const (
	// Format is the wire identifier every job file carries, in every version.
	Format = "openglasses.job"
	// Version is the format version this package writes.
	Version = 2
	// Domain separates a format-2 signature from every other signature the organisation's key
	// makes, a format-1 job file's included.
	Domain = "Avenkin.JobFile.v2"
	// Version3 is the format whose job may carry external, history and site_requirements.
	Version3 = 3
	// Domain3 separates a format-3 signature from format 2's and from everything else: a
	// format-3 signature never verifies as format 2's, nor the reverse.
	Domain3 = "Avenkin.JobFile.v3"
	// MaximumBytes caps the whole file.
	MaximumBytes = 64 * 1024

	maximumSafeInteger = int64(9007199254740991)
)

var (
	ErrMalformed = errors.New("malformed job file")
	ErrVersion   = errors.New("not a format-2 or format-3 job file")
	ErrFields    = errors.New("invalid job file fields")
	ErrSignature = errors.New("job file is not signed by the organisation's key")
	ErrUnsigned  = errors.New("job file is not signed")
)

// The members a format-2 job may have. A member this version does not know is refused: a file
// that carries something the phone cannot show is a file whose review would not be the whole
// truth.
var jobMembers = map[string]bool{"job_id": true, "revision": true, "job_reference": true, "site": true, "fault_report": true,
	"equipment": true, "scheduled_for": true, "notes": true, "attachments": true, "issued_by": true, "manuals": true}

// jobMembersV3 is format 2's, and what the office may say about where the job came from.
var jobMembersV3 = func() map[string]bool {
	out := map[string]bool{"external": true, "history": true, "site_requirements": true}
	for name := range jobMembers {
		out[name] = true
	}
	return out
}()

func membersFor(version int) map[string]bool {
	if version == Version3 {
		return jobMembersV3
	}
	return jobMembers
}

func domainFor(version int) string {
	if version == Version3 {
		return Domain3
	}
	return Domain
}

// What a job may ask to follow it (Contracts/office-bulk.md §5).
const (
	MaximumAttachments = 10
	MaximumManualSets  = 10
)

var attachmentMediaTypes = map[string]bool{"application/pdf": true, "image/jpeg": true, "image/png": true}

// Attachment is a file a job names by digest: it follows the job in the bulk folder.
type Attachment struct {
	Name      string
	SHA256    string
	Bytes     int64
	MediaType string
}

// Needs is what a job says follows it: attachments it names by digest, and manual sets it needs.
// Naming is all a job does. An attachment is accepted because a job the phone holds names its
// exact bytes; a manual is accepted only under its own assignment and its publisher's signature.
type Needs struct {
	Attachments []Attachment
	ManualSets  []string
}

func plainInteger(raw json.RawMessage) (int64, bool) {
	var n json.Number
	if len(raw) == 0 || json.Unmarshal(raw, &n) != nil || n.String() != string(raw) || raw[0] == '0' {
		return 0, false
	}
	v, e := n.Int64()
	return v, e == nil && v > 0 && v <= maximumSafeInteger
}

// ReadNeeds reads what a format-2 job's exact bytes say follows it. An attachment with no digest
// is only named, as in format 1, and is not in the result.
func ReadNeeds(job []byte) (Needs, error) { return ReadNeedsVersion(Version, job) }

// ReadNeedsVersion is ReadNeeds for a job of the given format version.
func ReadNeedsVersion(version int, job []byte) (Needs, error) {
	var needs Needs
	if _, e := identityFor(version, job); e != nil {
		return needs, e
	}
	fields, _ := members(job)
	if raw, ok := fields["attachments"]; ok {
		var list []json.RawMessage
		if json.Unmarshal(raw, &list) != nil || len(list) > MaximumAttachments {
			return Needs{}, ErrFields
		}
		seen := map[string]bool{}
		for _, item := range list {
			m, e := members(item)
			if e != nil {
				return Needs{}, ErrFields
			}
			for name := range m {
				if name != "name" && name != "reference" && name != "sha256" && name != "bytes" && name != "media_type" {
					return Needs{}, ErrFields
				}
			}
			var a Attachment
			if json.Unmarshal(m["name"], &a.Name) != nil || a.Name == "" {
				return Needs{}, ErrFields
			}
			_, hasDigest := m["sha256"]
			_, hasBytes := m["bytes"]
			_, hasType := m["media_type"]
			if !hasDigest && !hasBytes && !hasType {
				continue
			}
			size, ok := plainInteger(m["bytes"])
			if !hasDigest || !hasBytes || !hasType || !ok || json.Unmarshal(m["sha256"], &a.SHA256) != nil ||
				json.Unmarshal(m["media_type"], &a.MediaType) != nil || !attachmentMediaTypes[a.MediaType] || seen[a.SHA256] {
				return Needs{}, ErrFields
			}
			for _, c := range []byte(a.SHA256) {
				if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
					return Needs{}, ErrFields
				}
			}
			if len(a.SHA256) != 64 {
				return Needs{}, ErrFields
			}
			a.Bytes, seen[a.SHA256] = size, true
			needs.Attachments = append(needs.Attachments, a)
		}
	}
	if raw, ok := fields["manuals"]; ok {
		var list []json.RawMessage
		if json.Unmarshal(raw, &list) != nil || len(list) > MaximumManualSets {
			return Needs{}, ErrFields
		}
		seen := map[string]bool{}
		for _, item := range list {
			m, e := members(item)
			var set string
			if e != nil || len(m) != 1 || json.Unmarshal(m["set_id"], &set) != nil || !identifier(set) || seen[set] {
				return Needs{}, ErrFields
			}
			seen[set] = true
			needs.ManualSets = append(needs.ManualSets, set)
		}
	}
	return needs, nil
}

// Identity is what makes two files the same job, and orders them.
type Identity struct {
	JobID    string
	Revision int64
	// SHA256 is the digest of the job's exact bytes: two files with the same identifier and
	// revision are one job only when this is the same too.
	SHA256 string
}

type signature struct {
	Algorithm string `json:"algorithm"`
	Value     string `json:"value"`
}

type file struct {
	Format        string     `json:"format"`
	FormatVersion int        `json:"format_version"`
	Job           string     `json:"job"`
	Signature     *signature `json:"signature,omitempty"`
}

// SigningInput is the exact bytes a format-2 signature covers: the domain, one zero byte, the
// job's bytes.
func SigningInput(job []byte) []byte { return SigningInputVersion(Version, job) }

// SigningInputVersion is what a signature covers in the given format: that format's domain, one
// zero byte, the job's bytes.
func SigningInputVersion(version int, job []byte) []byte {
	return append(append([]byte(domainFor(version)), 0), job...)
}

func identifier(s string) bool {
	if len(s) == 0 || len(s) > 80 || s == "." || s == ".." {
		return false
	}
	for _, c := range []byte(s) {
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '.' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

// members returns a JSON object's members in order, refusing anything that is not exactly one
// object with no member named twice.
func members(raw []byte) (map[string]json.RawMessage, error) {
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	if t, e := d.Token(); e != nil || t != json.Delim('{') {
		return nil, ErrMalformed
	}
	out := map[string]json.RawMessage{}
	for d.More() {
		t, e := d.Token()
		name, ok := t.(string)
		if e != nil || !ok {
			return nil, ErrMalformed
		}
		if _, twice := out[name]; twice {
			return nil, ErrMalformed
		}
		var value json.RawMessage
		if d.Decode(&value) != nil {
			return nil, ErrMalformed
		}
		out[name] = value
	}
	if t, e := d.Token(); e != nil || t != json.Delim('}') {
		return nil, ErrMalformed
	}
	if d.More() {
		return nil, ErrMalformed
	}
	if _, e := d.Token(); e == nil {
		return nil, ErrMalformed // trailing data
	}
	return out, nil
}

// unambiguous says raw is one JSON value in which no object, at any depth, names a member twice.
// A signature over exact bytes says nothing about which of two members a reader takes.
func unambiguous(raw []byte) bool {
	type frame struct {
		object    bool
		seen      map[string]bool
		expectKey bool
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var stack []frame
	for {
		t, e := d.Token()
		if e == io.EOF {
			return len(stack) == 0
		}
		if e != nil {
			return false
		}
		top := len(stack) - 1
		if top >= 0 && stack[top].object && stack[top].expectKey {
			if delim, closing := t.(json.Delim); closing && delim == '}' {
				stack = stack[:top]
				continue
			}
			name, ok := t.(string)
			if !ok || stack[top].seen[name] {
				return false
			}
			stack[top].seen[name], stack[top].expectKey = true, false
			continue
		}
		// A value: its object, if it is in one, expects a name next.
		if top >= 0 && stack[top].object {
			stack[top].expectKey = true
		}
		switch t {
		case json.Delim('{'):
			stack = append(stack, frame{object: true, seen: map[string]bool{}, expectKey: true})
		case json.Delim('['):
			stack = append(stack, frame{})
		case json.Delim(']'):
			if top < 0 {
				return false
			}
			stack = stack[:top]
		}
	}
}

// identity reads a format-2 job's identifier and revision from its exact bytes.
func identity(job []byte) (Identity, error) { return identityFor(Version, job) }

// identityFor reads a job's identifier and revision from its exact bytes, holding it to the
// members its format allows — and, in format 3, to format 3's rules.
func identityFor(version int, job []byte) (Identity, error) {
	if !unambiguous(job) {
		return Identity{}, ErrMalformed
	}
	fields, e := members(job)
	if e != nil {
		return Identity{}, e
	}
	allowed := membersFor(version)
	for name := range fields {
		if !allowed[name] {
			return Identity{}, ErrFields
		}
	}
	if version == Version3 {
		if e := checkFormat3(fields); e != nil {
			return Identity{}, e
		}
	}
	var id string
	var revision json.Number
	if json.Unmarshal(fields["job_id"], &id) != nil || !identifier(id) {
		return Identity{}, ErrFields
	}
	if len(fields["revision"]) == 0 || json.Unmarshal(fields["revision"], &revision) != nil {
		return Identity{}, ErrFields
	}
	n, e := revision.Int64()
	// Plain decimal only: no fraction, exponent, sign or leading zero.
	if e != nil || n <= 0 || n > maximumSafeInteger || revision.String() != string(fields["revision"]) || revision.String()[0] == '0' {
		return Identity{}, ErrFields
	}
	sum := sha256.Sum256(job)
	return Identity{id, n, hex.EncodeToString(sum[:])}, nil
}

// Seal writes the format-2 file for exact job bytes and, when there is one, the signature the
// organisation's key made over SigningInput(job). An empty signature writes an unsigned file.
func Seal(job, sig []byte) ([]byte, error) { return SealVersion(Version, job, sig) }

// SealVersion writes the file of the given format (2 or 3) for exact job bytes and a signature
// over SigningInputVersion(version, job).
func SealVersion(version int, job, sig []byte) ([]byte, error) {
	if version != Version && version != Version3 {
		return nil, ErrVersion
	}
	if _, e := identityFor(version, job); e != nil {
		return nil, e
	}
	f := file{Format, version, base64.StdEncoding.EncodeToString(job), nil}
	if len(sig) != 0 {
		if len(sig) != ed25519.SignatureSize {
			return nil, ErrSignature
		}
		f.Signature = &signature{"ed25519", base64.StdEncoding.EncodeToString(sig)}
	}
	out, e := json.Marshal(f)
	if e != nil {
		return nil, e
	}
	if len(out) > MaximumBytes {
		return nil, ErrMalformed
	}
	return out, nil
}

// Sign writes a signed format-2 file for a key held in process.
func Sign(job []byte, organisationKey ed25519.PrivateKey) ([]byte, error) {
	return SignVersion(Version, job, organisationKey)
}

// SignVersion writes a signed file of the given format, under that format's domain.
func SignVersion(version int, job []byte, organisationKey ed25519.PrivateKey) ([]byte, error) {
	if len(organisationKey) != ed25519.PrivateKeySize {
		return nil, ErrSignature
	}
	return SealVersion(version, job, ed25519.Sign(organisationKey, SigningInputVersion(version, job)))
}

// Open reads a format-2 or format-3 file: its closed outer form, the job's exact bytes and its
// identity. signed says whether the file carries a signature at all; it is not yet checked (see
// Verify).
func Open(data []byte) (job []byte, id Identity, signed bool, err error) {
	job, id, _, signed, err = OpenVersion(data)
	return job, id, signed, err
}

// OpenVersion is Open, also saying which format the file is.
func OpenVersion(data []byte) (job []byte, id Identity, version int, signed bool, err error) {
	if len(data) == 0 || len(data) > MaximumBytes {
		return nil, Identity{}, 0, false, ErrMalformed
	}
	if !unambiguous(data) {
		return nil, Identity{}, 0, false, ErrMalformed
	}
	outer, e := members(data)
	if e != nil {
		return nil, Identity{}, 0, false, e
	}
	var format string
	var spelled json.Number
	if json.Unmarshal(outer["format"], &format) != nil || format != Format {
		return nil, Identity{}, 0, false, ErrMalformed
	}
	if json.Unmarshal(outer["format_version"], &spelled) != nil {
		return nil, Identity{}, 0, false, ErrVersion
	}
	switch spelled.String() {
	case "2":
		version = Version
	case "3":
		version = Version3
	default:
		return nil, Identity{}, 0, false, ErrVersion
	}
	for name := range outer {
		if name != "format" && name != "format_version" && name != "job" && name != "signature" {
			return nil, Identity{}, 0, false, ErrFields
		}
	}
	var encoded string
	if json.Unmarshal(outer["job"], &encoded) != nil {
		return nil, Identity{}, 0, false, ErrMalformed
	}
	job, e = base64.StdEncoding.Strict().DecodeString(encoded)
	if e != nil || base64.StdEncoding.EncodeToString(job) != encoded {
		return nil, Identity{}, 0, false, ErrMalformed
	}
	if id, e = identityFor(version, job); e != nil {
		return nil, Identity{}, 0, false, e
	}
	_, signed = outer["signature"]
	return job, id, version, signed, nil
}

// Verify reads a format-2 or format-3 file and checks its signature under the organisation's
// key, over that format's domain and the job's exact bytes. An unsigned file is ErrUnsigned:
// whether one may be offered to a technician is the phone's policy, not this check's.
func Verify(data []byte, organisationKey ed25519.PublicKey) ([]byte, Identity, error) {
	job, id, version, signed, e := OpenVersion(data)
	if e != nil {
		return nil, Identity{}, e
	}
	if !signed {
		return nil, Identity{}, ErrUnsigned
	}
	outer, _ := members(data)
	sigFields, e := members(outer["signature"])
	if e != nil || len(sigFields) != 2 {
		return nil, Identity{}, ErrMalformed
	}
	var s signature
	if json.Unmarshal(outer["signature"], &s) != nil || s.Algorithm != "ed25519" {
		return nil, Identity{}, ErrMalformed
	}
	sig, e := base64.StdEncoding.Strict().DecodeString(s.Value)
	if e != nil || len(sig) != ed25519.SignatureSize || base64.StdEncoding.EncodeToString(sig) != s.Value {
		return nil, Identity{}, ErrMalformed
	}
	if len(organisationKey) != ed25519.PublicKeySize || !ed25519.Verify(organisationKey, SigningInputVersion(version, job), sig) {
		return nil, Identity{}, ErrSignature
	}
	return job, id, nil
}

// Supersedes says what a phone that holds one revision of a job does with another file for the
// same identifier: Newer replaces it, Same is the job it already has, and anything else is
// refused — an Older revision never replaces a newer one, and a second, different file at one
// revision is a Conflict.
type Relation int

const (
	Unrelated Relation = iota
	Newer
	Same
	Older
	Conflict
)

// Relate compares an arriving file's identity with the one held.
func Relate(held, arriving Identity) Relation {
	switch {
	case held.JobID != arriving.JobID:
		return Unrelated
	case arriving.Revision > held.Revision:
		return Newer
	case arriving.Revision < held.Revision:
		return Older
	case arriving.SHA256 == held.SHA256:
		return Same
	default:
		return Conflict
	}
}
