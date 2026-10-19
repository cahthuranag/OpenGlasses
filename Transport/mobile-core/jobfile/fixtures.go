package jobfile

import (
	"crypto/ed25519"
	"crypto/sha256"
)

// FixtureKeyLabel derives the fictional organisation key the golden file is signed with:
// seed = SHA-256(label). It is public and has no authority.
const FixtureKeyLabel = "Avenkin public fixture organisation job key v1"

// FixtureJob is the golden job's exact bytes.
const FixtureJob = `{"job_id":"job-2031","revision":2,"job_reference":"FX-1007","site":{"customer":"Fixture Service","address":"14 Fixture Street"},"fault_report":"No heat. Display shows E200.","equipment":[{"model":"FX-90","serial":"0001"}],"scheduled_for":"2027-01-15T09:00:00Z","issued_by":"Fixture Service Ltd"}`

// FixtureAttachment is the exact bytes of the attachment FixtureJobWithNeeds names: a public
// sentence, not in the repository as a file.
const FixtureAttachment = "Avenkin public fixture job attachment v1"

// FixtureJobWithNeeds names an attachment by digest and a manual set, both of which follow the
// job in the bulk folder, and one attachment by name only.
const FixtureJobWithNeeds = `{"job_id":"job-2032","revision":1,"job_reference":"FX-1008","site":{"customer":"Fixture Service"},"fault_report":"Annual service.","attachments":[{"name":"Site plan","sha256":"7d0ec53b69a2325cf8a5c6e9033c6b5d47de24cc0c9a1ac63e4c4432f985e1e1","bytes":40,"media_type":"application/pdf"},{"name":"Previous invoice","reference":"INV-2231"}],"manuals":[{"set_id":"fixture-manuals"}]}`

// FixtureJobV3External is a format-3 job from another system: its identity there, a machine
// named by serial and one with no serial named by the office's unit_key, each with a make and a
// label. Its office reference differs from the other system's number on purpose. Invented.
const FixtureJobV3External = `{"job_id":"job-3031","revision":1,"job_reference":"FX-3031","site":{"customer":"Fixture Service","address":"21 Fixture Lane"},"fault_report":"Cooling fault on the roof unit.","equipment":[{"model":"FX-90","serial":"0001","make":"Fixture Make","label":"Plant room"},{"model":"FX-AHU","unit_key":"u1","make":"Fixture Make","label":"Roof, AHU-2"}],"issued_by":"Fixture Service Ltd","external":{"system":"fixture-fsm","system_name":"Fixture FSM","job_id":"FSM-J-88001","job_number":"88001","appointment_id":"FSM-A-5501","location_id":"FSM-L-301","customer_id":"FSM-C-77/a+b=","technician_id":"FSM-T-12","equipment_ids":{"0001":"FSM-E-9001","u1":"FSM-E-9002"}}}`

// FixtureJobV3History is a format-3 job with the office's service history for both its machines
// (one by serial, one by unit_key), a warranty on each, a rule's flag with its evidence, a
// schedule's site-wide maintenance flag, and the site's requirements. Invented.
const FixtureJobV3History = `{"job_id":"job-3032","revision":1,"job_reference":"88002","site":{"customer":"Fixture Service"},"fault_report":"No heat. Display shows E200.","equipment":[{"model":"FX-90","serial":"0002"},{"model":"FX-AHU","unit_key":"u1","label":"Roof, AHU-2"}],"external":{"system":"fixture-fsm","system_name":"Fixture FSM","job_id":"FSM-J-88002","job_number":"88002"},"history":{"as_of":"2027-01-10T18:00:00Z","units":[{"serial":"0002","installed":"2021-03-04","warranty":{"status":"in_warranty","until":"2027-03-01","note":"Parts only; labour excluded."},"visits":[{"date":"2026-11-14","job_number":"0993","summary":"No heat, E200.","findings":["Inducer bearing noisy"],"parts_replaced":["Inducer motor FX-IM1"],"technician_initials":"AB","source":"fixture-fsm"},{"date":"2025-09-02","job_number":"0871","summary":"No heat, E200. Inducer replaced.","parts_replaced":["Inducer motor FX-IM1"],"technician_initials":"CD","source":"fixture-fsm"}]},{"unit_key":"u1","warranty":{"status":"unknown"},"visits":[{"date":"2026-06-01","summary":"Annual service. Filters changed."}]}],"flags":[{"kind":"replacement_pattern","unit":"0002","text":"Inducer motor replaced twice in 14 months.","evidence":["0871","0993"],"severity":"warning"},{"kind":"maintenance_due","basis":"schedule","due":"2027-02-01","schedule":"Annual service","text":"Annual site service is due by 1 Feb 2027.","severity":"info"}]},"site_requirements":{"as_of":"2027-01-10T18:00:00Z","items":[{"kind":"induction","text":"Site induction at the gatehouse before entering the plant room.","severity":"warning"},{"kind":"ppe","text":"Hard hat, hi-vis and safety boots on site.","severity":"warning"},{"kind":"access","text":"Use the north entrance; park in bay 4.","severity":"info"}]}}`

func FixtureKey() ed25519.PrivateKey {
	seed := sha256.Sum256([]byte(FixtureKeyLabel))
	return ed25519.NewKeyFromSeed(seed[:])
}

// Fixtures returns the public golden fixtures of job-file formats 2 and 3, by file name.
func Fixtures() (map[string][]byte, error) {
	signed, e := Sign([]byte(FixtureJob), FixtureKey())
	if e != nil {
		return nil, e
	}
	needs, e := Sign([]byte(FixtureJobWithNeeds), FixtureKey())
	if e != nil {
		return nil, e
	}
	external, e := SignVersion(Version3, []byte(FixtureJobV3External), FixtureKey())
	if e != nil {
		return nil, e
	}
	history, e := SignVersion(Version3, []byte(FixtureJobV3History), FixtureKey())
	if e != nil {
		return nil, e
	}
	return map[string][]byte{"job-file-v2.ogjob": signed, "job-file-v2-needs.ogjob": needs,
		"job-file-v3-external.ogjob": external, "job-file-v3-history.ogjob": history}, nil
}
