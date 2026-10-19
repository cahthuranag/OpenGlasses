package jobfile

import (
	"bytes"
	"encoding/json"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Format 3 (Contracts/job-file.md §10): format 2's job, plus four optional things the office
// may say about it — its identity in another system (external), what the office knows about each
// unit (history), what the site asks of the person arriving (site_requirements), and, on each
// machine, a unit_key, a make and a label. Every member is closed, bounded and typed, and every
// cross-reference names a machine on the job. Lengths are counted in characters (runes), which is
// never more than the phone counts, so a job this accepts on length the phone accepts too.

// The bounds of format 3, as the contract states them.
const (
	MaximumExternalBytes         = 2 * 1024
	MaximumHistoryBytes          = 24 * 1024
	MaximumVisitBytes            = 2 * 1024
	MaximumSiteRequirementsBytes = 4 * 1024
	MaximumEquipment             = 10
	MaximumVisitsPerUnit         = 10
	MaximumFlagsPerUnit          = 3
	MaximumFlags                 = 12
	MaximumFindings              = 6
	MaximumPartsReplaced         = 8
	MaximumEvidence              = 10
	MaximumEquipmentIDs          = 10
	MaximumSiteRequirements      = 8
)

var (
	externalMembers    = set("system", "system_name", "job_id", "job_number", "appointment_id", "location_id", "customer_id", "technician_id", "equipment_ids")
	equipmentMembersV3 = set("model", "serial", "unit_key", "make", "label")
	historyMembers     = set("as_of", "units", "flags")
	unitMembers        = set("serial", "unit_key", "installed", "warranty", "visits")
	warrantyMembers    = set("status", "until", "note")
	visitMembers       = set("date", "job_number", "summary", "findings", "parts_replaced", "technician_initials", "source")
	flagMembers        = set("kind", "unit", "text", "evidence", "severity", "basis", "due", "schedule")
	siteMembers        = set("as_of", "items")
	requirementMembers = set("kind", "text", "severity")

	flagKinds        = set("recurring_failure", "replacement_pattern", "overdue_maintenance", "maintenance_due", "recall_or_bulletin")
	maintenanceKinds = set("overdue_maintenance", "maintenance_due")
	severities       = set("info", "warning")
	warrantyStatuses = set("in_warranty", "expired", "unknown")
	requirementKinds = set("access", "induction", "ppe", "hazard", "contact", "other")
)

func set(names ...string) map[string]bool {
	out := map[string]bool{}
	for _, name := range names {
		out[name] = true
	}
	return out
}

type machine struct {
	serial  string
	unitKey string
}

// checkFormat3 holds a format-3 job's members to format 3's rules.
func checkFormat3(fields map[string]json.RawMessage) error {
	machines, e := checkEquipmentV3(fields["equipment"])
	if e != nil {
		return e
	}
	if raw, ok := fields["external"]; ok {
		if e := checkExternal(raw, machines); e != nil {
			return e
		}
	}
	if raw, ok := fields["history"]; ok {
		if e := checkHistory(raw, machines); e != nil {
			return e
		}
	}
	if raw, ok := fields["site_requirements"]; ok {
		if e := checkSiteRequirements(raw); e != nil {
			return e
		}
	}
	return nil
}

// object reads a JSON object's members, refusing anything else (including null) and any member
// it does not list.
func object(raw json.RawMessage, allowed map[string]bool) (map[string]json.RawMessage, error) {
	m, e := members(raw)
	if e != nil {
		return nil, ErrFields
	}
	for name := range m {
		if !allowed[name] {
			return nil, ErrFields
		}
	}
	return m, nil
}

// list reads a JSON array's elements as their exact bytes, refusing anything else.
func list(raw json.RawMessage) ([]json.RawMessage, error) {
	var out []json.RawMessage
	if len(raw) == 0 || raw[0] != '[' || json.Unmarshal(raw, &out) != nil {
		return nil, ErrFields
	}
	return out, nil
}

// str reads a JSON string, refusing anything else (including null).
func str(raw json.RawMessage) (string, bool) {
	var s string
	if len(raw) == 0 || raw[0] != '"' || json.Unmarshal(raw, &s) != nil {
		return "", false
	}
	return s, true
}

// text is a present, non-blank string of at most limit characters with no control character.
func text(raw json.RawMessage, limit int) (string, bool) {
	s, ok := str(raw)
	if !ok || strings.TrimSpace(s) == "" || utf8.RuneCountInString(s) > limit {
		return "", false
	}
	for _, r := range s {
		if unicode.IsControl(r) {
			return "", false
		}
	}
	return s, true
}

// optionalText is text when present.
func optionalText(m map[string]json.RawMessage, name string, limit int) bool {
	raw, ok := m[name]
	if !ok {
		return true
	}
	_, ok = text(raw, limit)
	return ok
}

// Token is [a-z0-9_-]{1,32}.
func Token(s string) bool {
	if len(s) == 0 || len(s) > 32 {
		return false
	}
	for _, c := range []byte(s) {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

// externalIdentifier is 1–128 printable ASCII characters, no spaces, never "://".
func externalIdentifier(raw json.RawMessage) bool {
	s, ok := str(raw)
	if !ok || len(s) == 0 || len(s) > 128 || strings.Contains(s, "://") {
		return false
	}
	for _, c := range []byte(s) {
		if c < 0x21 || c > 0x7e {
			return false
		}
	}
	return true
}

// Date is an ISO 8601 calendar date, YYYY-MM-DD, that exists.
func Date(s string) bool {
	if len(s) != 10 {
		return false
	}
	_, e := time.Parse("2006-01-02", s)
	return e == nil
}

func date(raw json.RawMessage) bool {
	s, ok := str(raw)
	return ok && Date(s)
}

func timestamp(raw json.RawMessage) bool {
	s, ok := str(raw)
	if !ok || len(s) > 40 {
		return false
	}
	_, e := time.Parse(time.RFC3339, s)
	return e == nil
}

func oneOf(raw json.RawMessage, allowed map[string]bool) bool {
	s, ok := str(raw)
	return ok && allowed[s]
}

// checkEquipmentV3: a machine may carry a unit_key, a make and a label; a unit_key is a token,
// unique within the job, and never any machine's serial.
func checkEquipmentV3(raw json.RawMessage) ([]machine, error) {
	if raw == nil {
		return nil, nil
	}
	items, e := list(raw)
	if e != nil || len(items) > MaximumEquipment {
		return nil, ErrFields
	}
	var machines []machine
	var serials []string
	for _, item := range items {
		m, e := object(item, equipmentMembersV3)
		if e != nil {
			return nil, e
		}
		var unit machine
		if s, ok := m["serial"]; ok {
			if unit.serial, ok = str(s); !ok {
				return nil, ErrFields
			}
			serials = append(serials, unit.serial)
		}
		if !optionalText(m, "make", 64) || !optionalText(m, "label", 80) {
			return nil, ErrFields
		}
		if k, ok := m["unit_key"]; ok {
			if unit.unitKey, ok = str(k); !ok || !Token(unit.unitKey) {
				return nil, ErrFields
			}
		}
		machines = append(machines, unit)
	}
	keys := map[string]bool{}
	for _, unit := range machines {
		if unit.unitKey == "" {
			continue
		}
		if keys[unit.unitKey] {
			return nil, ErrFields
		}
		keys[unit.unitKey] = true
		for _, serial := range serials {
			if strings.ToLower(serial) == unit.unitKey {
				return nil, ErrFields
			}
		}
	}
	return machines, nil
}

func checkExternal(raw json.RawMessage, machines []machine) error {
	if len(raw) > MaximumExternalBytes {
		return ErrFields
	}
	m, e := object(raw, externalMembers)
	if e != nil {
		return e
	}
	if system, ok := str(m["system"]); !ok || !Token(system) {
		return ErrFields
	}
	if !externalIdentifier(m["job_id"]) {
		return ErrFields
	}
	for _, name := range []string{"system_name", "job_number"} {
		limit := map[string]int{"system_name": 40, "job_number": 64}[name]
		if v, ok := m[name]; ok {
			if s, ok := text(v, limit); !ok || strings.Contains(s, "://") {
				return ErrFields
			}
		}
	}
	for _, name := range []string{"appointment_id", "location_id", "customer_id", "technician_id"} {
		if v, ok := m[name]; ok && !externalIdentifier(v) {
			return ErrFields
		}
	}
	if v, ok := m["equipment_ids"]; ok {
		ids, e := members(v)
		if e != nil || len(ids) > MaximumEquipmentIDs {
			return ErrFields
		}
		for key, id := range ids {
			named := false
			for _, unit := range machines {
				// The unit's unit_key when it has one, else its serial.
				if unit.unitKey == key || unit.unitKey == "" && unit.serial == key {
					named = true
				}
			}
			if !named || !externalIdentifier(id) {
				return ErrFields
			}
		}
	}
	return nil
}

func checkHistory(raw json.RawMessage, machines []machine) error {
	if len(raw) > MaximumHistoryBytes {
		return ErrFields
	}
	m, e := object(raw, historyMembers)
	if e != nil {
		return e
	}
	if !timestamp(m["as_of"]) {
		return ErrFields
	}
	// Each entry names exactly one machine on the job, once, by its serial or its unit_key.
	unitByKey := map[string]int{}
	if v, ok := m["units"]; ok {
		units, e := list(v)
		if e != nil || len(units) > MaximumEquipment {
			return ErrFields
		}
		named := map[int]bool{}
		for _, item := range units {
			u, e := object(item, unitMembers)
			if e != nil {
				return e
			}
			serialRaw, hasSerial := u["serial"]
			keyRaw, hasKey := u["unit_key"]
			if hasSerial == hasKey {
				return ErrFields
			}
			found, key := -1, ""
			if hasSerial {
				serial, ok := str(serialRaw)
				if !ok {
					return ErrFields
				}
				for i, unit := range machines {
					if unit.serial == serial {
						found, key = i, serial
						break
					}
				}
			} else {
				unitKey, ok := str(keyRaw)
				if !ok || !Token(unitKey) {
					return ErrFields
				}
				for i, unit := range machines {
					if unit.unitKey == unitKey {
						found, key = i, unitKey
						break
					}
				}
			}
			if _, twice := unitByKey[key]; found < 0 || named[found] || twice {
				return ErrFields
			}
			named[found], unitByKey[key] = true, found
			if v, ok := u["installed"]; ok && !date(v) {
				return ErrFields
			}
			if v, ok := u["warranty"]; ok {
				w, e := object(v, warrantyMembers)
				if e != nil || !oneOf(w["status"], warrantyStatuses) || !optionalText(w, "note", 160) {
					return ErrFields
				}
				if until, ok := w["until"]; ok && !date(until) {
					return ErrFields
				}
			}
			if v, ok := u["visits"]; ok {
				if e := checkVisits(v); e != nil {
					return e
				}
			}
		}
	}
	if v, ok := m["flags"]; ok {
		flags, e := list(v)
		if e != nil || len(flags) > MaximumFlags {
			return ErrFields
		}
		perUnit := map[int]int{}
		for _, item := range flags {
			f, e := object(item, flagMembers)
			if e != nil {
				return e
			}
			kind, ok := str(f["kind"])
			if !ok || !flagKinds[kind] || !oneOf(f["severity"], severities) {
				return ErrFields
			}
			if _, ok := text(f["text"], 240); !ok {
				return ErrFields
			}
			basis := "rule"
			if b, ok := f["basis"]; ok {
				if basis, ok = str(b); !ok || basis != "rule" && basis != "schedule" {
					return ErrFields
				}
			}
			// Only a maintenance kind comes from a schedule, and only a schedule's flag names one.
			if basis == "schedule" && !maintenanceKinds[kind] {
				return ErrFields
			}
			if _, ok := f["schedule"]; ok && (basis != "schedule" || !optionalText(f, "schedule", 80)) {
				return ErrFields
			}
			if due, ok := f["due"]; ok && (!maintenanceKinds[kind] || !date(due)) {
				return ErrFields
			}
			if u, ok := f["unit"]; ok {
				name, ok := str(u)
				machine, named := unitByKey[name]
				if !ok || !named {
					return ErrFields
				}
				if perUnit[machine]++; perUnit[machine] > MaximumFlagsPerUnit {
					return ErrFields
				}
			} else if basis != "schedule" {
				// Absent means the whole site, which only a schedule can say.
				return ErrFields
			}
			var evidence []json.RawMessage
			if v, ok := f["evidence"]; ok {
				if evidence, e = list(v); e != nil {
					return e
				}
			}
			// A rule shows its evidence; a schedule's evidence is the schedule itself.
			if len(evidence) > MaximumEvidence || len(evidence) == 0 && basis != "schedule" {
				return ErrFields
			}
			for _, job := range evidence {
				if _, ok := text(job, 64); !ok {
					return ErrFields
				}
			}
		}
	}
	return nil
}

func checkVisits(raw json.RawMessage) error {
	visits, e := list(raw)
	if e != nil || len(visits) > MaximumVisitsPerUnit {
		return ErrFields
	}
	previous := ""
	for _, item := range visits {
		if len(bytes.TrimSpace(item)) > MaximumVisitBytes {
			return ErrFields
		}
		v, e := object(item, visitMembers)
		if e != nil {
			return e
		}
		day, ok := str(v["date"])
		// Newest first: the office orders them, the phone never reorders.
		if !ok || !Date(day) || previous != "" && day > previous {
			return ErrFields
		}
		previous = day
		if _, ok := text(v["summary"], 600); !ok || !optionalText(v, "job_number", 64) {
			return ErrFields
		}
		for name, bound := range map[string][2]int{"findings": {MaximumFindings, 200}, "parts_replaced": {MaximumPartsReplaced, 80}} {
			if l, ok := v[name]; ok {
				items, e := list(l)
				if e != nil || len(items) > bound[0] {
					return ErrFields
				}
				for _, entry := range items {
					if _, ok := text(entry, bound[1]); !ok {
						return ErrFields
					}
				}
			}
		}
		if raw, ok := v["technician_initials"]; ok {
			initials, ok := str(raw)
			if n := utf8.RuneCountInString(initials); !ok || n < 1 || n > 4 {
				return ErrFields
			}
			for _, r := range initials {
				if !unicode.IsLetter(r) {
					return ErrFields
				}
			}
		}
		if raw, ok := v["source"]; ok {
			if source, ok := str(raw); !ok || !Token(source) {
				return ErrFields
			}
		}
	}
	return nil
}

func checkSiteRequirements(raw json.RawMessage) error {
	if len(raw) > MaximumSiteRequirementsBytes {
		return ErrFields
	}
	m, e := object(raw, siteMembers)
	if e != nil {
		return e
	}
	if !timestamp(m["as_of"]) {
		return ErrFields
	}
	items, e := list(m["items"])
	if e != nil || len(items) > MaximumSiteRequirements {
		return ErrFields
	}
	for _, item := range items {
		r, e := object(item, requirementMembers)
		if e != nil || !oneOf(r["kind"], requirementKinds) || !oneOf(r["severity"], severities) {
			return ErrFields
		}
		if _, ok := text(r["text"], 240); !ok {
			return ErrFields
		}
	}
	return nil
}
