package jobfile

import (
	"crypto/ed25519"
	"encoding/base64"
	"errors"
	"strings"
	"testing"
)

func publicFixtureKey() ed25519.PublicKey { return FixtureKey().Public().(ed25519.PublicKey) }

func TestTheFormatThreeFixturesVerifyUnderTheirOwnDomain(t *testing.T) {
	fixtures := must(Fixtures())
	for name, want := range map[string]string{"job-file-v3-external.ogjob": FixtureJobV3External, "job-file-v3-history.ogjob": FixtureJobV3History} {
		job, id, version, signed, e := OpenVersion(fixtures[name])
		if e != nil || version != Version3 || !signed || string(job) != want || id.Revision != 1 {
			t.Fatalf("%s: %v version %d", name, e, version)
		}
		if _, _, e := Verify(fixtures[name], publicFixtureKey()); e != nil {
			t.Fatalf("%s: %v", name, e)
		}
	}
	// The format-2 files still open as format 2.
	if _, _, version, _, e := OpenVersion(fixtures["job-file-v2.ogjob"]); e != nil || version != Version {
		t.Fatalf("format 2: %v %d", e, version)
	}
}

func TestAFormatThreeSignatureIsNotAFormatTwoSignatureNorTheReverse(t *testing.T) {
	key := FixtureKey()
	job := []byte(FixtureJob) // a format-2 job is a valid format-3 job
	v2 := string(must(Sign(job, key)))
	v3 := string(must(SignVersion(Version3, job, key)))
	if strings.Contains(v3, `"format_version":2`) || !strings.Contains(v3, `"format_version":3`) {
		t.Fatal("a format-3 file says format 3")
	}
	// The same job and key, relabelled: neither signature carries over.
	_, _, e := Verify([]byte(strings.Replace(v2, `"format_version":2`, `"format_version":3`, 1)), publicFixtureKey())
	refused(t, "format 2's signature read as format 3", e, ErrSignature)
	_, _, e = Verify([]byte(strings.Replace(v3, `"format_version":3`, `"format_version":2`, 1)), publicFixtureKey())
	refused(t, "format 3's signature read as format 2", e, ErrSignature)
	if string(SigningInputVersion(Version3, job)[:len(Domain3)+1]) != Domain3+"\x00" {
		t.Fatal("the format-3 domain is its own")
	}
	// Format 2's writer is unchanged: the golden file is still what Sign makes.
	if v2 != string(must(Fixtures())["job-file-v2.ogjob"]) {
		t.Fatal("format 2 changed")
	}
	// Format 2 refuses format 3's members.
	_, e = Seal([]byte(FixtureJobV3External), nil)
	refused(t, "external in format 2", e, ErrFields)
	_, e = ReadNeeds([]byte(FixtureJobV3History))
	refused(t, "history in format 2", e, ErrFields)
	if _, e = ReadNeedsVersion(Version3, []byte(FixtureJobV3History)); e != nil {
		t.Fatal(e)
	}
}

// job3 is a format-3 job with two machines, one with a serial and one with only a unit_key.
func job3(rest string) []byte {
	head := `{"job_id":"job-1","revision":1,"job_reference":"1","equipment":[{"model":"A","serial":"S1"},{"model":"B","unit_key":"u1"}]`
	if rest == "" {
		return []byte(head + `}`)
	}
	return []byte(head + `,` + rest + `}`)
}

func history(units, flags string) string {
	out := `"history":{"as_of":"2027-01-10T18:00:00Z"`
	if units != "" {
		out += `,"units":[` + units + `]`
	}
	if flags != "" {
		out += `,"flags":[` + flags + `]`
	}
	return out + `}`
}

const visit = `{"date":"2026-11-14","summary":"No heat."}`

func TestFormatThreeAcceptsWhatTheContractAllows(t *testing.T) {
	for name, rest := range map[string]string{
		"nothing more":         ``,
		"a minimal external":   `"external":{"system":"fixture-fsm","job_id":"J1"}`,
		"ids by unit_key":      `"external":{"system":"x","job_id":"J1","equipment_ids":{"S1":"E1","u1":"E2"}}`,
		"an encoded id":        `"external":{"system":"x","job_id":"a/b+c="}`,
		"a unit by serial":     history(`{"serial":"S1","visits":[`+visit+`]}`, ``),
		"a unit by unit_key":   history(`{"unit_key":"u1","installed":"2021-02-28","warranty":{"status":"expired","until":"2026-01-01"}}`, ``),
		"a rule flag":          history(`{"serial":"S1"}`, `{"kind":"recurring_failure","unit":"S1","text":"x","evidence":["0871"],"severity":"warning"}`),
		"a schedule flag":      history(`{"unit_key":"u1"}`, `{"kind":"maintenance_due","unit":"u1","basis":"schedule","due":"2027-02-01","schedule":"Annual service","text":"x","severity":"info"}`),
		"a site-wide schedule": history(``, `{"kind":"maintenance_due","basis":"schedule","text":"x","severity":"info"}`),
		"an overdue schedule":  history(``, `{"kind":"overdue_maintenance","basis":"schedule","due":"2026-12-01","text":"x","evidence":[],"severity":"warning"}`),
		"a rule's due date":    history(`{"serial":"S1"}`, `{"kind":"maintenance_due","unit":"S1","basis":"rule","due":"2027-02-01","text":"x","evidence":["0871"],"severity":"info"}`),
		"site requirements":    `"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[{"kind":"hazard","text":"x","severity":"warning"}]}`,
	} {
		if _, e := SealVersion(Version3, job3(rest), nil); e != nil {
			t.Fatalf("%s: %v", name, e)
		}
	}
	made := `{"job_id":"j","revision":1,"job_reference":"1","equipment":[{"model":"A","make":"` + strings.Repeat("m", 64) + `","label":"` + strings.Repeat("l", 80) + `"}]}`
	if _, e := SealVersion(Version3, []byte(made), nil); e != nil {
		t.Fatalf("make and label at their limits: %v", e)
	}
}

func TestFormatThreeRefusesWhatTheContractDoesNot(t *testing.T) {
	long := func(n int) string { return strings.Repeat("a", n) }
	many := func(item string, n int) string {
		parts := make([]string, n)
		for i := range parts {
			parts[i] = item
		}
		return strings.Join(parts, ",")
	}
	flag := func(extra string) string {
		return `{"kind":"recurring_failure","unit":"S1","text":"x","evidence":["1"],"severity":"info"` + extra + `}`
	}
	unitS1 := `{"serial":"S1"}`
	cases := map[string][]byte{
		// external
		"an unknown external member":     job3(`"external":{"system":"x","job_id":"J","url":"y"}`),
		"no system":                      job3(`"external":{"job_id":"J"}`),
		"an upper-case system":           job3(`"external":{"system":"FSM","job_id":"J"}`),
		"a long system":                  job3(`"external":{"system":"` + long(33) + `","job_id":"J"}`),
		"no external job id":             job3(`"external":{"system":"x"}`),
		"a job id with a space":          job3(`"external":{"system":"x","job_id":"J 1"}`),
		"a job id that is a link":        job3(`"external":{"system":"x","job_id":"https://x/1"}`),
		"a long job id":                  job3(`"external":{"system":"x","job_id":"` + long(129) + `"}`),
		"a job number that is a link":    job3(`"external":{"system":"x","job_id":"J","job_number":"see https://x"}`),
		"a long system name":             job3(`"external":{"system":"x","job_id":"J","system_name":"` + long(41) + `"}`),
		"a numeric identifier":           job3(`"external":{"system":"x","job_id":"J","customer_id":7}`),
		"a null identifier":              job3(`"external":{"system":"x","job_id":"J","location_id":null}`),
		"ids by a serial not on the job": job3(`"external":{"system":"x","job_id":"J","equipment_ids":{"S9":"E"}}`),
		"ids by a model":                 job3(`"external":{"system":"x","job_id":"J","equipment_ids":{"B":"E"}}`),
		// equipment
		"an unknown machine member":      []byte(`{"job_id":"j","revision":1,"equipment":[{"model":"A","colour":"red"}]}`),
		"a unit_key that is not a token": []byte(`{"job_id":"j","revision":1,"equipment":[{"model":"A","unit_key":"U 1"}]}`),
		"a unit_key twice":               []byte(`{"job_id":"j","revision":1,"equipment":[{"unit_key":"u1"},{"unit_key":"u1"}]}`),
		"a unit_key that is a serial":    []byte(`{"job_id":"j","revision":1,"equipment":[{"serial":"U1"},{"unit_key":"u1"}]}`),
		"a long make":                    []byte(`{"job_id":"j","revision":1,"equipment":[{"model":"A","make":"` + long(65) + `"}]}`),
		"a long label":                   []byte(`{"job_id":"j","revision":1,"equipment":[{"model":"A","label":"` + long(81) + `"}]}`),
		// history
		"an unknown history member":     job3(`"history":{"as_of":"2027-01-10T18:00:00Z","notes":"x"}`),
		"no as_of":                      job3(`"history":{"units":[]}`),
		"a bad as_of":                   job3(`"history":{"as_of":"10 Jan 2027"}`),
		"a unit by both":                job3(history(`{"serial":"S1","unit_key":"u1"}`, ``)),
		"a unit by neither":             job3(history(`{"visits":[]}`, ``)),
		"a unit by model":               job3(history(`{"model":"A"}`, ``)),
		"a serial not on the job":       job3(history(`{"serial":"S9"}`, ``)),
		"a unit_key not on the job":     job3(history(`{"unit_key":"u9"}`, ``)),
		"one unit twice":                job3(history(unitS1+`,`+unitS1, ``)),
		"a bad installed date":          job3(history(`{"serial":"S1","installed":"2021-02-30"}`, ``)),
		"an installed date-time":        job3(history(`{"serial":"S1","installed":"2021-02-03T00:00:00Z"}`, ``)),
		"an unknown warranty status":    job3(history(`{"serial":"S1","warranty":{"status":"maybe"}}`, ``)),
		"a warranty with no status":     job3(history(`{"serial":"S1","warranty":{"until":"2027-01-01"}}`, ``)),
		"a long warranty note":          job3(history(`{"serial":"S1","warranty":{"status":"unknown","note":"`+long(161)+`"}}`, ``)),
		"too many visits":               job3(history(`{"serial":"S1","visits":[`+many(visit, 11)+`]}`, ``)),
		"visits oldest first":           job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01","summary":"a"},{"date":"2026-01-01","summary":"b"}]}`, ``)),
		"a visit with no summary":       job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01"}]}`, ``)),
		"a long summary":                job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01","summary":"`+long(601)+`"}]}`, ``)),
		"too many findings":             job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01","summary":"a","findings":[`+many(`"f"`, 7)+`]}]}`, ``)),
		"initials that are not letters": job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01","summary":"a","technician_initials":"A1"}]}`, ``)),
		"an oversized visit":            job3(history(`{"serial":"S1","visits":[{"date":"2025-01-01","summary":"`+long(600)+`","findings":[`+many(`"`+long(200)+`"`, 6)+`],"parts_replaced":[`+many(`"`+long(80)+`"`, 8)+`]}]}`, ``)),
		// flags
		"an unknown flag kind":              job3(history(unitS1, `{"kind":"vibes","unit":"S1","text":"x","evidence":["1"],"severity":"info"}`)),
		"an unknown severity":               job3(history(unitS1, `{"kind":"recurring_failure","unit":"S1","text":"x","evidence":["1"],"severity":"urgent"}`)),
		"a rule flag with no evidence":      job3(history(unitS1, `{"kind":"recurring_failure","unit":"S1","text":"x","severity":"info"}`)),
		"a rule flag with no unit":          job3(history(unitS1, `{"kind":"maintenance_due","text":"x","evidence":["1"],"severity":"info"}`)),
		"a flag for a unit with no history": job3(history(unitS1, `{"kind":"recurring_failure","unit":"u1","text":"x","evidence":["1"],"severity":"info"}`)),
		"a schedule on a failure":           job3(history(unitS1, flag(`,"basis":"schedule"`))),
		"a schedule name on a rule":         job3(history(unitS1, flag(`,"schedule":"Annual"`))),
		"a due date on a failure":           job3(history(unitS1, flag(`,"due":"2027-01-01"`))),
		"an unknown basis":                  job3(history(unitS1, flag(`,"basis":"hunch"`))),
		"a bad due date":                    job3(history(``, `{"kind":"maintenance_due","basis":"schedule","due":"2027-13-01","text":"x","severity":"info"}`)),
		"a long schedule name":              job3(history(``, `{"kind":"maintenance_due","basis":"schedule","schedule":"`+long(81)+`","text":"x","severity":"info"}`)),
		"too many flags for one unit":       job3(history(unitS1, many(flag(``), 4))),
		"too many flags":                    job3(history(``, many(`{"kind":"maintenance_due","basis":"schedule","text":"x","severity":"info"}`, 13))),
		"too much evidence":                 job3(history(unitS1, `{"kind":"recurring_failure","unit":"S1","text":"x","evidence":[`+many(`"1"`, 11)+`],"severity":"info"}`)),
		"a long flag text":                  job3(history(unitS1, `{"kind":"recurring_failure","unit":"S1","text":"`+long(241)+`","evidence":["1"],"severity":"info"}`)),
		// site requirements
		"an unknown requirement kind":   job3(`"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[{"kind":"parking","text":"x","severity":"info"}]}`),
		"too many requirements":         job3(`"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[` + many(`{"kind":"other","text":"x","severity":"info"}`, 9) + `]}`),
		"requirements with no items":    job3(`"site_requirements":{"as_of":"2027-01-10T18:00:00Z"}`),
		"a long requirement":            job3(`"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[{"kind":"other","text":"` + long(241) + `","severity":"info"}]}`),
		"an unknown requirement member": job3(`"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[{"kind":"other","text":"x","severity":"info","link":"y"}]}`),
		// the job
		"an unknown job member": job3(`"warranty":{}`),
	}
	for name, job := range cases {
		if _, e := SealVersion(Version3, job, nil); !errors.Is(e, ErrFields) && !errors.Is(e, ErrMalformed) {
			t.Fatalf("%s: got %v", name, e)
		}
	}
	// The members' own bounds, from values that are each within theirs.
	visits := `"visits":[` + many(`{"date":"2025-01-01","summary":"`+long(600)+`","findings":[`+many(`"`+long(190)+`"`, 6)+`]}`, 10) + `]`
	if _, e := SealVersion(Version3, job3(history(`{"serial":"S1",`+visits+`},{"unit_key":"u1",`+visits+`}`, ``)), nil); !errors.Is(e, ErrFields) {
		t.Fatalf("an oversized history: %v", e)
	}
	var equipment, ids []string
	for n := 0; n < MaximumEquipment; n++ {
		key := strings.Repeat("k", 31) + string(rune('a'+n))
		equipment = append(equipment, `{"unit_key":"`+key+`"}`)
		ids = append(ids, `"`+key+`":"`+long(128)+`"`)
	}
	every := `"system":"` + long(32) + `","system_name":"` + long(40) + `","job_id":"` + long(128) + `","job_number":"` + long(64) +
		`","appointment_id":"` + long(128) + `","location_id":"` + long(128) + `","customer_id":"` + long(128) + `","technician_id":"` + long(128) + `"`
	external := `{"job_id":"j","revision":1,"job_reference":"1","equipment":[` + strings.Join(equipment, ",") + `],"external":{` + every + `,"equipment_ids":{` + strings.Join(ids, ",") + `}}}`
	if _, e := SealVersion(Version3, []byte(external), nil); !errors.Is(e, ErrFields) {
		t.Fatalf("an oversized external: %v", e)
	}
}

func TestFormatOneAndTwoNeverCarryFormatThreeMembers(t *testing.T) {
	for _, rest := range []string{`"external":{"system":"x","job_id":"J"}`, history(``, ``), `"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[]}`} {
		_, e := Seal(job3(rest), nil)
		refused(t, rest, e, ErrFields)
	}
	withJob := `{"format":"openglasses.job","format_version":2,"job":"` + base64.StdEncoding.EncodeToString(job3(`"external":{"system":"x","job_id":"J"}`)) + `"}`
	_, _, _, e := Open([]byte(withJob))
	refused(t, "a format-2 file with external", e, ErrFields)
}
