package widget_test

import (
	"testing"

	"github.com/google/uuid"
	"github.com/useopendesk/opendesk/internal/helpdesk/hdtest"
)

func TestRequiredEmailCollisionCaptureAndResume(t *testing.T) {
	e, ws := setup(t)
	existing := start(t, e, map[string]any{"key": ws.WidgetKey, "email": "existing@example.com"})
	existingAuth := hdtest.Auth{Visitor: existing.VisitorToken}
	ticket := e.Do("POST", "/v1/widget/conversations", existingAuth, map[string]any{"body": "Private history"}).Want(t, 201).Map(t)
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"require_email": true})
	anon := start(t, e, map[string]any{"key": ws.WidgetKey})
	if anon.EmailCollected {
		t.Fatal("anonymous visitor already collected email")
	}
	collected := start(t, e, map[string]any{"key": ws.WidgetKey, "visitor_token": anon.VisitorToken, "email": "existing@example.com"})
	if !collected.EmailCollected || collected.Contact.Email != nil || collected.Contact.ID != anon.Contact.ID || collected.Contact.ID == existing.Contact.ID {
		t.Fatalf("captured session: %+v", collected)
	}
	resumed := start(t, e, map[string]any{"key": ws.WidgetKey, "visitor_token": collected.VisitorToken})
	if !resumed.EmailCollected || resumed.Contact.Email != nil {
		t.Fatalf("resumed session: %+v", resumed)
	}
	auth := hdtest.Auth{Visitor: resumed.VisitorToken}
	e.Do("POST", "/v1/widget/conversations", auth, map[string]any{"body": "Hello"}).Want(t, 201)
	e.Do("GET", "/v1/widget/conversations/"+ticket["conversation"].(map[string]any)["id"].(string)+"/messages", auth, nil).Want(t, 404)
}
