package core

import "testing"

// TestUndoSendSeconds checks the undo window takes only the offered lengths, off included.
func TestUndoSendSeconds(t *testing.T) {
	for _, n := range []int{0, 5, 10, 20, 30} {
		out, err := validateSettings(&CoreWorkspaceSettings{UndoSendSeconds: &n})
		if err != nil {
			t.Fatalf("%d: %v", n, err)
		}
		if out["undo_send_seconds"] != n {
			t.Fatalf("%d: stored %v", n, out["undo_send_seconds"])
		}
	}
	for _, n := range []int{-1, 3, 31, 600} {
		if _, err := validateSettings(&CoreWorkspaceSettings{UndoSendSeconds: &n}); err == nil {
			t.Fatalf("%d: accepted", n)
		}
	}
}

// TestMessageDeleteSetting checks the agents' delete rule takes only its three values.
func TestMessageDeleteSetting(t *testing.T) {
	for _, v := range []string{"off", "own", "all"} {
		if _, err := validateSettings(&CoreWorkspaceSettings{MessageDelete: &v}); err != nil {
			t.Fatalf("%s: %v", v, err)
		}
	}
	bad := "everyone"
	if _, err := validateSettings(&CoreWorkspaceSettings{MessageDelete: &bad}); err == nil {
		t.Fatal("accepted everyone")
	}
}
