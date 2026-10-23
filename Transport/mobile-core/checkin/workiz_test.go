package checkin

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
)

func TestDirectConnectorMemberIsSignedClosedAndOptional(t *testing.T) {
	made := must(Fixtures())
	world := fixtureWorld(t)
	legacy := must(ReadCheckIn(string(made["office-check-in-v1.json"]), world.phonePublic))
	if legacy.FSMDirect != nil {
		t.Fatal("legacy absence must remain unknown")
	}
	for _, state := range []string{"on", "off"} {
		text := string(made["office-check-in-workiz-"+state+"-v1.json"])
		value := must(ReadCheckIn(text, world.phonePublic))
		if value.FSMDirect == nil || value.FSMDirect.System != "workiz" || value.FSMDirect.State != state {
			t.Fatal("direct state did not read back")
		}
		var env envelope
		if json.Unmarshal([]byte(text), &env) != nil {
			t.Fatal("fixture envelope")
		}
		raw := string(must(base64.StdEncoding.DecodeString(env.Payload)))
		for _, replacement := range []string{
			`"fsmDirect":{"system":"workiz","state":"unknown"}`,
			`"fsmDirect":{"system":"workiz","state":"on","extra":"x"}`,
			`"fsmDirect":{"system":"workiz","state":"on","state":"off"}`,
			`"fsmDirect":{"system":"another","state":"on"}`,
			`"fsmDirect":null`,
		} {
			changed := strings.Replace(raw, `"fsmDirect":{"system":"workiz","state":"`+state+`"}`, replacement, 1)
			if changed == raw {
				t.Fatal("test did not mutate fixture")
			}
			payload := []byte(changed)
			signature := ed25519.Sign(world.phone, SigningInput(CheckInDomain, payload))
			signed := must(seal(payload, signature, MaximumMessage))
			if _, err := ReadCheckIn(signed, world.phonePublic); err == nil {
				t.Fatal("accepted invalid direct state", replacement)
			}
		}
	}
}
