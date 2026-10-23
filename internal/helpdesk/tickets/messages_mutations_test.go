package tickets_test

import (
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/domain"
	"github.com/useopendesk/opendesk/internal/helpdesk/hdtest"
)

func createInternalNote(t *testing.T, e *hdtest.Env, ws hdtest.WS, ticketID string) domain.Message {
	t.Helper()
	var note domain.Message
	e.Do("POST", "/v1/tickets/"+ticketID+"/messages", ws.Agent.As(ws),
		map[string]any{"kind": "note", "body_html": "<p>Original note</p>"}).Want(t, 201).JSON(t, &note)
	return note
}

func TestEditInternalNote(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	path := "/v1/tickets/" + fmt.Sprint(tk.Number) + "/messages/" + note.ID.String()
	_, seq := e.Events(ws.ID, 0)

	var edited domain.Message
	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p>Corrected note</p><script>alert(1)</script>"}).
		Want(t, 200).JSON(t, &edited)
	if edited.BodyText != "Corrected note" || edited.EditedAt == nil || strings.Contains(edited.BodyHTML, "script") {
		t.Fatalf("edited note %+v", edited)
	}
	var activityData string
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `SELECT data::text FROM activities WHERE ticket_id = $1 AND type = 'note_edited'`, tk.ID).
		Scan(&activityData); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(activityData, note.ID.String()) || strings.Contains(activityData, "Corrected note") {
		t.Fatalf("activity data contains unexpected content: %s", activityData)
	}
	if types, _ := e.Events(ws.ID, seq); !slices.Contains(types, "activity.created") || !slices.Contains(types, "message.updated") {
		t.Fatalf("edit events %v", types)
	}
}

func TestDeleteNoteLeavesAMarker(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	key := "workspaces/" + ws.ID.String() + "/attachments/note-delete-test"
	if err := e.D.Storage.Put(e.Ctx, key, strings.NewReader("attachment"), int64(len("attachment")), "text/plain"); err != nil {
		t.Fatal(err)
	}
	e.Exec(`INSERT INTO attachments (workspace_id, message_id, filename, size_bytes, storage_key) VALUES ($1, $2, 'note.txt', 10, $3)`, ws.ID, note.ID, key)
	_, seq := e.Events(ws.ID, 0)

	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + note.ID.String()
	e.Do("DELETE", path, ws.Agent.As(ws), nil).Want(t, 204)
	e.Do("DELETE", path, ws.Agent.As(ws), nil).Want(t, 204)
	if n := countRows(t, e, `SELECT count(*) FROM messages WHERE id = $1 AND deleted_at IS NOT NULL AND deleted_by = $2`, note.ID, ws.Agent.ID); n != 1 {
		t.Fatalf("deleted marker rows %d", n)
	}
	if _, err := e.D.Storage.Get(e.Ctx, key); err != nil {
		t.Fatalf("a deleted note keeps its files until it is purged: %v", err)
	}
	var activityData string
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `SELECT data::text FROM activities WHERE ticket_id = $1 AND type = 'note_deleted'`, tk.ID).
		Scan(&activityData); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(activityData, note.ID.String()) || strings.Contains(activityData, "Original note") {
		t.Fatalf("activity data contains unexpected content: %s", activityData)
	}
	if types, _ := e.Events(ws.ID, seq); !slices.Contains(types, "activity.created") || !slices.Contains(types, "message.updated") {
		t.Fatalf("delete events %v", types)
	}
	var leaked int
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `SELECT count(*) FROM events WHERE workspace_id = $1 AND seq > $2 AND data::text LIKE '%Original note%'`,
		ws.ID, seq).Scan(&leaked); err != nil {
		t.Fatal(err)
	}
	if leaked != 0 {
		t.Fatal("an event carries the deleted note's text")
	}

	// The team sees who deleted it; only an admin reads it.
	read := func(u hdtest.User) domain.Message {
		var out struct{ Data []domain.Message }
		e.Do("GET", "/v1/tickets/"+tk.ID.String()+"/messages", u.As(ws), nil).Want(t, 200).JSON(t, &out)
		for _, m := range out.Data {
			if m.ID == note.ID {
				return m
			}
		}
		t.Fatal("the deleted note's marker is missing")
		return domain.Message{}
	}
	if m := read(ws.Agent); m.DeletedAt == nil || m.DeletedBy == nil || m.DeletedBy.ID != ws.Agent.ID || m.BodyText != "" || len(m.Attachments) != 0 {
		t.Fatalf("agent's view of a deleted note %+v", m)
	}
	if m := read(ws.Admin); m.BodyText != "Original note" || len(m.Attachments) != 1 {
		t.Fatalf("admin's view of a deleted note %+v", m)
	}
	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 404)

	// An admin brings it back.
	e.Do("POST", path+"/restore", ws.Agent.As(ws), nil).Want(t, 403)
	var restored domain.Message
	e.Do("POST", path+"/restore", ws.Admin.As(ws), nil).Want(t, 200).JSON(t, &restored)
	if restored.DeletedAt != nil || restored.BodyText != "Original note" {
		t.Fatalf("restored %+v", restored)
	}
	e.Do("POST", path+"/restore", ws.Admin.As(ws), nil).Want(t, 422)
}

func TestInternalNoteMutationPermissionsAndKinds(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + note.ID.String()
	other := e.AddUser(ws, auth.RoleAgent, "Other Agent")
	e.Do("PATCH", path, other.As(ws), map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 403)
	e.Do("DELETE", path, other.As(ws), nil).Want(t, 403)
	e.Do("DELETE", path, ws.Viewer.As(ws), nil).Want(t, 403)
	e.Do("DELETE", path, ws.Admin.As(ws), nil).Want(t, 204)

	reply := inbound(t, e, ws, tk.ID, "Customer reply")
	replyPath := "/v1/tickets/" + tk.ID.String() + "/messages/" + reply.ID.String()
	e.Do("PATCH", replyPath, ws.Agent.As(ws), map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 422)
	// A customer's message is an admin's to delete.
	e.Do("DELETE", replyPath, ws.Agent.As(ws), nil).Want(t, 403)
	e.Do("DELETE", replyPath, ws.Admin.As(ws), nil).Want(t, 204)
}

// TestMessageDeleteRule checks settings.message_delete: agents delete none, their own, or any
// agent's messages; admins any message whatever the rule.
func TestMessageDeleteRule(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	other := e.AddUser(ws, auth.RoleAgent, "Other Agent")
	note := func(u hdtest.User) string {
		var m domain.Message
		e.Do("POST", "/v1/tickets/"+tk.ID.String()+"/messages", u.As(ws), map[string]any{"kind": "note", "body_html": "<p>n</p>"}).Want(t, 201).JSON(t, &m)
		return "/v1/tickets/" + tk.ID.String() + "/messages/" + m.ID.String()
	}
	rule := func(r string) {
		e.Exec(`UPDATE workspaces SET settings = settings || jsonb_build_object('message_delete', $2::text) WHERE id = $1`, ws.ID, r)
	}

	rule("off")
	e.Do("DELETE", note(ws.Agent), ws.Agent.As(ws), nil).Want(t, 403)
	e.Do("DELETE", note(ws.Agent), ws.Admin.As(ws), nil).Want(t, 204)

	rule("own")
	e.Do("DELETE", note(ws.Agent), ws.Agent.As(ws), nil).Want(t, 204)
	e.Do("DELETE", note(other), ws.Agent.As(ws), nil).Want(t, 403)

	rule("all")
	e.Do("DELETE", note(other), ws.Agent.As(ws), nil).Want(t, 204)

	// An agent's own rule wins over the workspace's, both ways; NULL follows it again.
	e.Exec(`UPDATE members SET message_delete = 'off' WHERE workspace_id = $1 AND user_id = $2`, ws.ID, ws.Agent.ID)
	e.Do("DELETE", note(ws.Agent), ws.Agent.As(ws), nil).Want(t, 403)
	rule("off")
	e.Exec(`UPDATE members SET message_delete = 'all' WHERE workspace_id = $1 AND user_id = $2`, ws.ID, ws.Agent.ID)
	e.Do("DELETE", note(other), ws.Agent.As(ws), nil).Want(t, 204)
	e.Exec(`UPDATE members SET message_delete = NULL WHERE workspace_id = $1 AND user_id = $2`, ws.ID, ws.Agent.ID)
	e.Do("DELETE", note(ws.Agent), ws.Agent.As(ws), nil).Want(t, 403)
}

// TestDeletingAReplyHidesItFromTheCustomer checks a deleted reply leaves the visitor's
// conversation and the ticket's count and preview, and is not sent if it has not gone yet.
func TestDeletingAReplyHidesItFromTheCustomer(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"kind": "note", "contact": map[string]any{"email": "visitor@example.com"}})
	e.Exec(`UPDATE tickets SET channel = 'chat' WHERE id = $1`, tk.ID)
	first := inbound(t, e, ws, tk.ID, "Hello?")
	var reply domain.Message
	e.Do("POST", "/v1/tickets/"+tk.ID.String()+"/messages", ws.Agent.As(ws),
		map[string]any{"kind": "reply", "body_html": "<p>Wrong answer</p>"}).Want(t, 201).JSON(t, &reply)
	_, seq := e.Events(ws.ID, 0)
	e.Do("DELETE", "/v1/tickets/"+tk.ID.String()+"/messages/"+reply.ID.String(), ws.Agent.As(ws), nil).Want(t, 204)

	if n := countRows(t, e, `SELECT count(*) FROM events WHERE workspace_id = $1 AND seq > $2 AND type = 'message.deleted' AND visibility = 'public'`,
		ws.ID, seq); n != 1 {
		t.Fatalf("public message.deleted %d", n)
	}
	msgs, err := domain.ListMessages(e.Ctx, e.D.DB.Pool, ws.ID, tk.ID, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 1 || msgs[0].ID != first.ID {
		t.Fatalf("the customer still sees %d messages", len(msgs))
	}
	var count int
	var preview string
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `SELECT message_count, last_message_preview FROM tickets WHERE id = $1`, tk.ID).Scan(&count, &preview); err != nil {
		t.Fatal(err)
	}
	if count != 1 || preview != first.BodyText {
		t.Fatalf("count %d preview %q", count, preview)
	}
}

// TestReplyFromNote checks a reply written from a note replaces it in one step, whatever
// the delete rule, and only from the writer's own note without files.
func TestReplyFromNote(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	e.Exec(`UPDATE workspaces SET settings = settings || '{"message_delete": "off"}' WHERE id = $1`, ws.ID)
	note := createInternalNote(t, e, ws, tk.ID.String())
	post := func(u hdtest.User, body map[string]any) *hdtest.Resp {
		return e.Do("POST", "/v1/tickets/"+tk.ID.String()+"/messages", u.As(ws), body)
	}
	post(ws.Admin, map[string]any{"kind": "reply", "body_html": "<p>x</p>", "from_note_id": note.ID.String()}).Want(t, 403)
	post(ws.Agent, map[string]any{"kind": "note", "body_html": "<p>x</p>", "from_note_id": note.ID.String()}).Want(t, 422)

	var reply domain.Message
	post(ws.Agent, map[string]any{"kind": "reply", "body_html": "<p>Original note</p>", "from_note_id": note.ID.String()}).Want(t, 201).JSON(t, &reply)
	// The note stays where it was, empty, pointing at the reply that holds its words.
	if n := countRows(t, e, `SELECT count(*) FROM messages WHERE id = $1 AND sent_as_reply_id = $2 AND body_text = '' AND body_html = ''`, note.ID, reply.ID); n != 1 {
		t.Fatalf("note marker rows %d", n)
	}
	if n := countRows(t, e, `SELECT count(*) FROM activities WHERE ticket_id = $1 AND type = 'note_sent_as_reply'`, tk.ID); n != 1 {
		t.Fatalf("note_sent_as_reply activities %d", n)
	}
	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + note.ID.String()
	post(ws.Agent, map[string]any{"kind": "reply", "body_html": "<p>again</p>", "from_note_id": note.ID.String()}).Want(t, 422)
	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 422)
	e.Do("DELETE", path, ws.Admin.As(ws), nil).Want(t, 422)
	// Nothing of it reaches the AI or a channel; the team's timeline keeps the marker.
	public, err := domain.ListMessages(e.Ctx, e.D.DB.Pool, ws.ID, tk.ID, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range public {
		if m.ID == note.ID {
			t.Fatal("the marker is in the AI's and channels' list")
		}
	}
}

func TestDeleteNoteKeepsSharedAttachmentObject(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	otherTicket := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	otherNote := createInternalNote(t, e, ws, otherTicket.ID.String())
	key := "workspaces/" + ws.ID.String() + "/attachments/shared-note-test"
	if err := e.D.Storage.Put(e.Ctx, key, strings.NewReader("shared"), int64(len("shared")), "text/plain"); err != nil {
		t.Fatal(err)
	}
	e.Exec(`INSERT INTO attachments (workspace_id, message_id, filename, size_bytes, storage_key) VALUES ($1, $2, 'one.txt', 6, $3)`, ws.ID, note.ID, key)
	e.Exec(`INSERT INTO attachments (workspace_id, message_id, filename, size_bytes, storage_key) VALUES ($1, $2, 'two.txt', 6, $3)`, ws.ID, otherNote.ID, key)
	e.Do("DELETE", "/v1/tickets/"+tk.ID.String()+"/messages/"+note.ID.String(), ws.Agent.As(ws), nil).Want(t, 204)
	if _, err := e.D.Storage.Get(e.Ctx, key); err != nil {
		t.Fatalf("shared attachment object removed: %v", err)
	}
}

func TestInternalNoteMutationRefusals(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + note.ID.String()

	// An admin deletes any note, but edits only their own.
	e.Do("PATCH", path, ws.Admin.As(ws), map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 403)
	// The routes are for signed-in members, whatever the key's scopes.
	key := e.APIKey(ws, "tickets:write", "tickets:read")
	e.Do("PATCH", path, hdtest.Auth{Bearer: key}, map[string]string{"body_html": "<p>Changed</p>"}).Want(t, 403)
	e.Do("DELETE", path, hdtest.Auth{Bearer: key}, nil).Want(t, 403)
	// A note is reached through its own ticket only.
	other := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	e.Do("DELETE", "/v1/tickets/"+other.ID.String()+"/messages/"+note.ID.String(), ws.Agent.As(ws), nil).Want(t, 404)
	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p> </p>"}).Want(t, 422)

	// A ticket of a private team the caller is not on is not there at all.
	hidden, _ := privateTicket(t, e, ws)
	var secret domain.Message
	e.Do("POST", "/v1/tickets/"+hidden.ID.String()+"/messages", ws.Admin.As(ws),
		map[string]any{"kind": "note", "body_html": "<p>Team only</p>"}).Want(t, 201).JSON(t, &secret)
	e.Do("DELETE", "/v1/tickets/"+hidden.ID.String()+"/messages/"+secret.ID.String(), ws.Agent.As(ws), nil).Want(t, 404)
}

func TestEditingANoteNotifiesOnlyNewMentions(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	note := createInternalNote(t, e, ws, tk.ID.String())
	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + note.ID.String()
	mention := func(u hdtest.User, name string) string {
		return fmt.Sprintf(`<span data-type="mention" data-id="%s" data-mention="%s">@%s</span>`, u.ID, u.ID, name)
	}
	count := func(uid any) int {
		return countRows(t, e, `SELECT count(*) FROM notifications WHERE ticket_id = $1 AND type = 'mentioned' AND user_id = $2`, tk.ID, uid)
	}

	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p>Ask " + mention(ws.Admin, "Adam") + "</p>"}).Want(t, 200)
	if count(ws.Admin.ID) != 1 {
		t.Fatalf("admin mentions %d", count(ws.Admin.ID))
	}
	e.Do("PATCH", path, ws.Agent.As(ws), map[string]string{"body_html": "<p>Ask " + mention(ws.Admin, "Adam") + " and " + mention(ws.Owner, "Olivia") + " today</p>"}).
		Want(t, 200)
	if count(ws.Admin.ID) != 1 || count(ws.Owner.ID) != 1 {
		t.Fatalf("mentions admin %d owner %d", count(ws.Admin.ID), count(ws.Owner.ID))
	}
	var preview string
	e.Scalar(`SELECT data->>'preview' FROM notifications WHERE ticket_id = $1 AND user_id = $2`, &preview, tk.ID, ws.Admin.ID)
	if !strings.Contains(preview, "today") {
		t.Fatalf("admin's mention still reads %q", preview)
	}

	e.Do("DELETE", path, ws.Agent.As(ws), nil).Want(t, 204)
	if n := countRows(t, e, `SELECT count(*) FROM notifications WHERE ticket_id = $1 AND type = 'mentioned'`, tk.ID); n != 0 {
		t.Fatalf("mentions left after delete %d", n)
	}
}

// TestPurgeMessage checks an admin removes a deleted message's content for good: its text,
// files and original email go, the marker stays, it is audit-logged and cannot come back.
func TestPurgeMessage(t *testing.T) {
	e, ws := newEnv(t)
	tk := createTicket(t, e, ws, map[string]any{"channel": "api", "kind": "note"})
	msg := inbound(t, e, ws, tk.ID, "My card is 4242 4242 4242 4242")
	key := "workspaces/" + ws.ID.String() + "/attachments/purge-test"
	raw := "workspaces/" + ws.ID.String() + "/inbound/purge-test.eml"
	for _, k := range []string{key, raw} {
		if err := e.D.Storage.Put(e.Ctx, k, strings.NewReader("x"), 1, "text/plain"); err != nil {
			t.Fatal(err)
		}
	}
	e.Exec(`INSERT INTO attachments (workspace_id, message_id, filename, size_bytes, storage_key) VALUES ($1, $2, 'card.png', 1, $3)`, ws.ID, msg.ID, key)
	var mailbox uuid.UUID
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `INSERT INTO mailboxes (workspace_id, name, email, inbound_kind, forwarding_token, outbound_kind, brand_id)
		VALUES ($1, 'Support', $3, 'forwarding', $4, 'system', $2) RETURNING id`, ws.ID, ws.BrandID,
		"purge-"+ws.ID.String()[:8]+"@example.com", "fw-purge-"+ws.ID.String()).Scan(&mailbox); err != nil {
		t.Fatal(err)
	}
	var ie uuid.UUID
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `INSERT INTO inbound_emails (workspace_id, mailbox_id, message_id_hdr, raw_storage_key) VALUES ($1, $2, '<p@x>', $3) RETURNING id`,
		ws.ID, mailbox, raw).Scan(&ie); err != nil {
		t.Fatal(err)
	}
	e.Exec(`UPDATE messages SET inbound_email_id = $2, full_html = '<p>My card is 4242 4242 4242 4242</p>' WHERE id = $1`, msg.ID, ie)
	path := "/v1/tickets/" + tk.ID.String() + "/messages/" + msg.ID.String()

	e.Do("POST", path+"/purge", ws.Admin.As(ws), nil).Want(t, 422)
	e.Do("DELETE", path, ws.Admin.As(ws), nil).Want(t, 204)
	e.Do("POST", path+"/purge", ws.Agent.As(ws), nil).Want(t, 403)
	var got domain.Message
	e.Do("POST", path+"/purge", ws.Admin.As(ws), nil).Want(t, 200).JSON(t, &got)
	if got.PurgedAt == nil || got.DeletedAt == nil || got.BodyText != "" || len(got.Attachments) != 0 {
		t.Fatalf("purged %+v", got)
	}
	if n := countRows(t, e, `SELECT count(*) FROM messages WHERE id = $1 AND (body_html || body_text || full_html) LIKE '%4242%'`, msg.ID); n != 0 {
		t.Fatal("the purged message still holds its text")
	}
	for _, k := range []string{key, raw} {
		if _, err := e.D.Storage.Get(e.Ctx, k); err == nil {
			t.Fatalf("%s was not removed", k)
		}
	}
	if n := countRows(t, e, `SELECT count(*) FROM audit_logs WHERE workspace_id = $1 AND action = 'message.purged' AND entity_id = $2`, ws.ID, msg.ID); n != 1 {
		t.Fatalf("audit entries %d", n)
	}
	e.Do("POST", path+"/purge", ws.Admin.As(ws), nil).Want(t, 200)
	e.Do("POST", path+"/restore", ws.Admin.As(ws), nil).Want(t, 422)
}
