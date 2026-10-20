package push

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/useopendesk/opendesk/internal/notifyprefs"
)

// The iPhone app shows a push from its own strings (Payload's loc keys), so every
// notification type has a title and a body there.
func TestIPhoneHasPushStrings(t *testing.T) {
	raw, err := os.ReadFile("../../ios/Opendesk/Resources/Localizable.xcstrings")
	if err != nil {
		t.Fatal(err)
	}
	var catalog struct {
		Strings map[string]struct {
			Localizations map[string]struct {
				StringUnit struct {
					Value string `json:"value"`
				} `json:"stringUnit"`
			} `json:"localizations"`
		} `json:"strings"`
	}
	if err := json.Unmarshal(raw, &catalog); err != nil {
		t.Fatal(err)
	}
	for _, typ := range notifyprefs.Types {
		for _, part := range []string{"title", "body"} {
			key := "push." + typ.Type + "." + part
			v := strings.TrimSpace(catalog.Strings[key].Localizations["en"].StringUnit.Value)
			if v == "" {
				t.Errorf("%s has no English text in ios/Opendesk/Resources/Localizable.xcstrings", key)
			}
			if part == "title" && strings.Contains(v, "%@") {
				t.Errorf("%s uses the ticket number, which only the body gets", key)
			}
		}
	}
}
