package widget_test

import (
	"bytes"
	"context"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/crypto"
	"github.com/useopendesk/opendesk/internal/domain"
	"github.com/useopendesk/opendesk/internal/helpdesk/hd"
	"github.com/useopendesk/opendesk/internal/helpdesk/hdtest"
	"github.com/useopendesk/opendesk/internal/helpdesk/widget"
)

type session struct {
	VisitorToken string            `json:"visitor_token"`
	Contact      domain.ContactRef `json:"contact"`
	WSToken      string            `json:"ws_token"`
	GatewayURL   string            `json:"gateway_url"`
}

func setup(t *testing.T) (*hdtest.Env, hdtest.WS) {
	t.Helper()
	e := hdtest.New(t, widget.Register)
	ws := e.NewWorkspace()
	sealed, err := e.D.Box.Seal([]byte("s3cret"))
	if err != nil {
		t.Fatal(err)
	}
	e.Exec(`UPDATE widgets SET secret_enc = $2 WHERE id = $1`, ws.WidgetID, sealed)
	return e, ws
}

func start(t *testing.T, e *hdtest.Env, body map[string]any) session {
	t.Helper()
	var s session
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, body).Want(t, 200).JSON(t, &s)
	return s
}

func TestConfig(t *testing.T) {
	e, ws := setup(t)
	e.Do("GET", "/v1/widget/config?key=nope", hdtest.Auth{}, nil).Want(t, 404)
	m := e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t)
	if m["workspace_name"] != "Acme "+ws.Slug || m["help_center_url"] != "" || m["require_email"] != false || m["attachments"] != true {
		t.Fatal(m)
	}
	e.SetSettings(ws, map[string]any{"brand_color": "#111111"})
	e.Exec(`UPDATE brands SET help_center_enabled = true WHERE id = $1`, ws.BrandID)
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"greeting": "Hello", "enabled": true, "require_email": true})
	m = e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t)
	if m["help_center_url"] != "http://app.test/help/"+ws.Slug || m["greeting"] != "Hello" || m["brand_color"] != "#111111" || m["require_email"] != true {
		t.Fatal(m)
	}
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"enabled": false})
	e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 404)
}

func TestSessionCreateResumeAndToken(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey, "name": "Jane <script>", "email": "jane@example.com"})
	if !strings.HasPrefix(s.VisitorToken, "od_vis_") || s.GatewayURL != "ws://gateway.test/socket/widget" {
		t.Fatal(s)
	}
	if s.Contact.Email == nil || *s.Contact.Email != "jane@example.com" || s.Contact.Name != "jane" {
		t.Fatalf("contact %+v", s.Contact)
	}
	c, err := e.D.Tokens.Verify(s.WSToken, auth.PurposeWidgetWS)
	if err != nil || c.Subject != s.Contact.ID.String() || c.Workspace != ws.ID.String() {
		t.Fatal(err, c)
	}
	if _, err := e.D.Tokens.Verify(s.WSToken, auth.PurposeWS); err == nil {
		t.Fatal("widget token accepted as ws")
	}
	var stored []byte
	e.Scalar(`SELECT token_hash FROM widget_sessions WHERE contact_id = $1`, &stored, s.Contact.ID)
	if !bytes.Equal(stored, crypto.HashToken(s.VisitorToken)) {
		t.Fatal("token not stored hashed")
	}
	// Resume returns the same token and contact.
	r := start(t, e, map[string]any{"key": ws.WidgetKey, "visitor_token": s.VisitorToken})
	if r.VisitorToken != s.VisitorToken || r.Contact.ID != s.Contact.ID {
		t.Fatal(r)
	}
	// A token from another workspace is not resumed there.
	ws2 := e.NewWorkspace()
	o := start(t, e, map[string]any{"key": ws2.WidgetKey, "visitor_token": s.VisitorToken})
	if o.VisitorToken == s.VisitorToken || o.Contact.ID == s.Contact.ID {
		t.Fatal("cross-workspace resume")
	}
	// Unknown token starts fresh.
	f := start(t, e, map[string]any{"key": ws.WidgetKey, "visitor_token": "od_vis_unknown"})
	if f.VisitorToken == "od_vis_unknown" || f.Contact.ID == s.Contact.ID {
		t.Fatal(f)
	}
}

func TestSessionHMAC(t *testing.T) {
	e, ws := setup(t)
	good := crypto.HMACHex([]byte("s3cret"), "user-42")
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey, "user_id": "user-42", "user_hash": "00ff"}).
		Want(t, 401)
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey, "user_id": "user-43", "user_hash": good}).
		Want(t, 401)
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey, "user_id": "user-42"}).Want(t, 422)

	s := start(t, e, map[string]any{"key": ws.WidgetKey, "user_id": "user-42", "user_hash": strings.ToUpper(good), "email": "u42@example.com", "name": "Uma"})
	var verified bool
	var ext string
	e.Scalar(`SELECT verified FROM widget_sessions WHERE contact_id = $1`, &verified, s.Contact.ID)
	e.Scalar(`SELECT external_id FROM contacts WHERE id = $1`, &ext, s.Contact.ID)
	if !verified || ext != "user-42" || s.Contact.Name != "Uma" {
		t.Fatal(verified, ext, s.Contact)
	}
	// A second browser with the same verified user links the same contact.
	s2 := start(t, e, map[string]any{"key": ws.WidgetKey, "user_id": "user-42", "user_hash": good})
	if s2.Contact.ID != s.Contact.ID || s2.VisitorToken == s.VisitorToken {
		t.Fatal(s2)
	}
	// Resuming that session as a different verified user gives a new contact.
	other := crypto.HMACHex([]byte("s3cret"), "user-7")
	s3 := start(t, e, map[string]any{"key": ws.WidgetKey, "visitor_token": s.VisitorToken, "user_id": "user-7", "user_hash": other})
	if s3.Contact.ID == s.Contact.ID || s3.VisitorToken == s.VisitorToken {
		t.Fatal(s3)
	}
	// No secret configured: nothing verifies.
	ws2 := e.NewWorkspace()
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws2.WidgetKey, "user_id": "user-42", "user_hash": good}).Want(t, 401)
}

func TestUnverifiedEmailDoesNotHijack(t *testing.T) {
	e, ws := setup(t)
	existing := uuid.New()
	e.Exec(`INSERT INTO contacts (id, workspace_id, email, name) VALUES ($1, $2, 'boss@example.com', 'Boss')`, existing, ws.ID)
	s := start(t, e, map[string]any{"key": ws.WidgetKey, "email": "boss@example.com"})
	if s.Contact.ID == existing || s.Contact.Email != nil {
		t.Fatal("visitor linked to an existing contact by a claimed email", s.Contact)
	}
	var claimed string
	e.Scalar(`SELECT custom->>'widget_email' FROM contacts WHERE id = $1`, &claimed, s.Contact.ID)
	if claimed != "boss@example.com" {
		t.Fatal(claimed)
	}
	// Even a verified user cannot take over an email held by another contact.
	good := crypto.HMACHex([]byte("s3cret"), "u1")
	v := start(t, e, map[string]any{"key": ws.WidgetKey, "user_id": "u1", "user_hash": good, "email": "boss@example.com"})
	if v.Contact.ID == existing || v.Contact.Email != nil {
		t.Fatal(v.Contact)
	}
}

func TestBlockedAndRequireEmailAndOrigins(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey})
	e.Exec(`UPDATE contacts SET blocked = true WHERE id = $1`, s.Contact.ID)
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey, "visitor_token": s.VisitorToken}).Want(t, 403)
	e.Do("GET", "/v1/widget/conversations", hdtest.Auth{Visitor: s.VisitorToken}, nil).Want(t, 401)

	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"enabled": true, "require_email": true, "allowed_origins": []string{"https://shop.example"}})
	allowed := hdtest.Auth{Header: map[string]string{"Origin": "https://shop.example"}}
	e.Do("POST", "/v1/widget/session", allowed, map[string]any{"key": ws.WidgetKey}).Want(t, 422)
	e.Do("POST", "/v1/widget/session", hdtest.Auth{Header: map[string]string{"Origin": "https://evil.example"}},
		map[string]any{"key": ws.WidgetKey, "email": "a@example.com"}).Want(t, 403)
	e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey, "email": "a@example.com"}).Want(t, 403)
	var ok session
	e.Do("POST", "/v1/widget/session", allowed, map[string]any{"key": ws.WidgetKey, "email": "a@example.com"}).Want(t, 200).JSON(t, &ok)
	e.Do("GET", "/v1/widget/conversations", hdtest.Auth{Visitor: ok.VisitorToken, Header: map[string]string{"Origin": "https://evil.example"}}, nil).Want(t, 403)
	e.Do("GET", "/v1/widget/conversations", hdtest.Auth{Visitor: ok.VisitorToken, Header: allowed.Header}, nil).Want(t, 200)
}

func TestConversations(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey, "email": "chat@example.com"})
	va := hdtest.Auth{Visitor: s.VisitorToken}
	_, seq := e.Events(ws.ID, 0)

	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "   "}).Want(t, 422)
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": strings.Repeat("x", 10001)}).Want(t, 422)
	var created struct {
		Conversation struct {
			ID      uuid.UUID `json:"id"`
			Subject string    `json:"subject"`
			Status  string    `json:"status"`
		} `json:"conversation"`
		Message domain.Message `json:"message"`
	}
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "Hello <b>there</b>\nI need help"}).Want(t, 201).JSON(t, &created)
	tid := created.Conversation.ID
	if created.Conversation.Status != "open" || created.Message.Direction != "inbound" || created.Message.Author.Type != "contact" ||
		created.Message.BodyHTML != "<p>Hello &lt;b&gt;there&lt;/b&gt;<br>I need help</p>" {
		t.Fatalf("%+v", created)
	}
	var channel string
	e.Scalar(`SELECT channel FROM tickets WHERE id = $1`, &channel, tid)
	if channel != "chat" {
		t.Fatal(channel)
	}
	if jobs := e.Jobs("helpdesk.ticket_trigger", ws.ID); len(jobs) != 1 || !strings.Contains(string(jobs[0]), "ticket_created") {
		t.Fatalf("trigger jobs %s", jobs)
	}
	types, _ := e.Events(ws.ID, seq)
	if !contains(types, "ticket.created") || !contains(types, "message.created") {
		t.Fatal(types)
	}

	// An agent reply (public event to the contact topic) and a note (never visible).
	err := e.D.DB.Tx(context.Background(), func(tx pgx.Tx) error {
		for _, kind := range []string{"reply", "note"} {
			if _, err := domain.AddMessage(context.Background(), tx, e.D.Jobs, domain.NewMessage{WorkspaceID: ws.ID, TicketID: tid,
				Kind: kind, Direction: "outbound", AuthorType: "user", AuthorUserID: &ws.Agent.ID,
				BodyHTML: "<p>" + kind + " body</p>", BodyText: kind + " body", Bcc: []string{"secret@example.com"}}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var vis string
	var topics []string
	if err := e.D.DB.Pool.QueryRow(e.Ctx, `SELECT visibility, topics FROM events WHERE workspace_id = $1 AND type = 'message.created'
		AND data->'message'->>'body_text' = 'reply body'`, ws.ID).Scan(&vis, &topics); err != nil {
		t.Fatal(err)
	}
	if vis != "public" || !contains(topics, "contact:"+ws.ID.String()+":"+s.Contact.ID.String()+":"+ws.BrandID.String()) {
		t.Fatal(vis, topics)
	}
	e.D.DB.Pool.QueryRow(e.Ctx, `SELECT visibility FROM events WHERE workspace_id = $1 AND type = 'message.created'
		AND data->'message'->>'body_text' = 'note body'`, ws.ID).Scan(&vis)
	if vis != "agents" {
		t.Fatal("note visibility", vis)
	}

	var list struct {
		Data []domain.Message `json:"data"`
	}
	r := e.Do("GET", "/v1/widget/conversations/"+tid.String()+"/messages", va, nil).Want(t, 200)
	r.JSON(t, &list)
	if len(list.Data) != 2 || strings.Contains(string(r.Body), "note body") {
		t.Fatalf("%s", r.Body)
	}
	agentMsg := list.Data[1]
	if agentMsg.Author.User == nil || agentMsg.Author.User.Email != "" || len(agentMsg.Bcc) != 0 || strings.Contains(string(r.Body), ws.Agent.Email) {
		t.Fatalf("agent details leaked: %s", r.Body)
	}

	var convs struct {
		Data []map[string]any `json:"data"`
	}
	e.Do("GET", "/v1/widget/conversations", va, nil).Want(t, 200).JSON(t, &convs)
	if len(convs.Data) != 1 || convs.Data[0]["id"] != tid.String() || convs.Data[0]["last_message_preview"] == "" {
		t.Fatal(convs)
	}

	e.Do("POST", "/v1/widget/conversations/"+tid.String()+"/messages", va, map[string]any{"body": "Thanks"}).Want(t, 201)
	var count int
	e.Scalar(`SELECT message_count FROM tickets WHERE id = $1`, &count, tid)
	if count != 3 {
		t.Fatal(count)
	}

	// Another visitor cannot see or write to it.
	o := start(t, e, map[string]any{"key": ws.WidgetKey})
	oa := hdtest.Auth{Visitor: o.VisitorToken}
	e.Do("GET", "/v1/widget/conversations/"+tid.String()+"/messages", oa, nil).Want(t, 404)
	e.Do("POST", "/v1/widget/conversations/"+tid.String()+"/messages", oa, map[string]any{"body": "x"}).Want(t, 404)
	e.Do("GET", "/v1/widget/conversations/not-a-uuid/messages", oa, nil).Want(t, 404)
	e.Do("GET", "/v1/widget/conversations", hdtest.Auth{}, nil).Want(t, 401)
	e.Do("GET", "/v1/widget/conversations", ws.Agent.As(ws), nil).Want(t, 401)

	// Closed conversations refuse new messages.
	e.Exec(`UPDATE tickets SET status = 'closed' WHERE id = $1`, tid)
	e.Do("POST", "/v1/widget/conversations/"+tid.String()+"/messages", va, map[string]any{"body": "again"}).Want(t, 409)
}

func TestVisitorAttachments(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey})
	o := start(t, e, map[string]any{"key": ws.WidgetKey})
	va, oa := hdtest.Auth{Visitor: s.VisitorToken}, hdtest.Auth{Visitor: o.VisitorToken}

	var mine, theirs, agents domain.Attachment
	e.Upload("/v1/widget/attachments", va, "shot.png", pngBytes()).Want(t, 201).JSON(t, &mine)
	e.Upload("/v1/widget/attachments", oa, "other.txt", []byte("hello")).Want(t, 201).JSON(t, &theirs)
	e.Upload("/v1/attachments", ws.Agent.As(ws), "agent.txt", []byte("agent file")).Want(t, 201).JSON(t, &agents)
	e.Upload("/v1/widget/attachments", va, "evil.exe", []byte("MZ\x90\x00")).Want(t, 422)

	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "x", "attachment_ids": []string{theirs.ID.String()}}).Want(t, 422)
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "x", "attachment_ids": []string{agents.ID.String()}}).Want(t, 422)
	var created struct {
		Conversation struct {
			ID uuid.UUID `json:"id"`
		} `json:"conversation"`
		Message domain.Message `json:"message"`
	}
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "see file", "attachment_ids": []string{mine.ID.String()}}).
		Want(t, 201).JSON(t, &created)
	if len(created.Message.Attachments) != 1 || created.Message.Attachments[0].ID != mine.ID {
		t.Fatal(created.Message.Attachments)
	}
	// Already attached: cannot be reused.
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "x", "attachment_ids": []string{mine.ID.String()}}).Want(t, 422)

	// Visitor reads: own file yes, other visitor's no.
	e.Do("GET", "/v1/attachments/"+mine.ID.String(), va, nil).Want(t, 200)
	e.Do("GET", "/v1/attachments/"+mine.ID.String(), oa, nil).Want(t, 404)
	e.Do("GET", "/v1/attachments/"+agents.ID.String(), va, nil).Want(t, 404)

	// With attachments off the widget takes no files, not even one uploaded before.
	var early domain.Attachment
	e.Upload("/v1/widget/attachments", va, "early.txt", []byte("early")).Want(t, 201).JSON(t, &early)
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"attachments": false})
	if m := e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t); m["attachments"] != false {
		t.Fatal(m)
	}
	e.Upload("/v1/widget/attachments", va, "late.txt", []byte("late")).Want(t, 403)
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "x", "attachment_ids": []string{early.ID.String()}}).Want(t, 403)
	cid := created.Conversation.ID.String()
	e.Do("POST", "/v1/widget/conversations/"+cid+"/messages", va, map[string]any{"body": "x", "attachment_ids": []string{early.ID.String()}}).Want(t, 403)
	e.Do("POST", "/v1/widget/conversations/"+cid+"/messages", va, map[string]any{"body": "text still works"}).Want(t, 201)
	// The agent's own uploads are not the widget's.
	e.Upload("/v1/attachments", ws.Agent.As(ws), "agent2.txt", []byte("agent file")).Want(t, 201)
}

func TestVisitorFileTypes(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey})
	va := hdtest.Auth{Visitor: s.VisitorToken}

	// By default every type of the catalog, each checked against its bytes.
	m := e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t)
	if ext, _ := m["attachment_extensions"].([]any); len(ext) < 10 || ext[0] != ".png" {
		t.Fatal(m["attachment_extensions"])
	}
	e.Upload("/v1/widget/attachments", va, "invoice.pdf", []byte("%PDF-1.7\n")).Want(t, 201)
	e.Upload("/v1/widget/attachments", va, "notes.txt", []byte("hello")).Want(t, 201)
	e.Upload("/v1/widget/attachments", va, "shell.png", []byte("#!/bin/sh\nid")).Want(t, 422)
	e.Upload("/v1/widget/attachments", va, "page.png", []byte("<html><script>alert(1)</script></html>")).Want(t, 422)
	e.Upload("/v1/widget/attachments", va, "x.svg", []byte("<svg onload=alert(1)>")).Want(t, 422)
	e.Upload("/v1/widget/attachments", va, "x.html", []byte("<p>hi</p>")).Want(t, 422)

	// Images only.
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"attachment_types": []string{"png", "jpg"}})
	m = e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t)
	if ext, _ := m["attachment_extensions"].([]any); len(ext) != 3 || ext[0] != ".png" || ext[1] != ".jpg" || ext[2] != ".jpeg" {
		t.Fatal(m["attachment_extensions"])
	}
	e.Upload("/v1/widget/attachments", va, "shot.png", pngBytes()).Want(t, 201)
	r := e.Upload("/v1/widget/attachments", va, "invoice.pdf", []byte("%PDF-1.7\n")).Want(t, 422).Map(t)
	if r["code"] != "file_type_not_allowed" {
		t.Fatal(r)
	}
	// Agents are not limited by the widget's types.
	e.Upload("/v1/attachments", ws.Agent.As(ws), "invoice.pdf", []byte("%PDF-1.7\n")).Want(t, 201)

	// Files off: no extensions.
	e.SetWidgetSettings(ws, uuid.Nil, map[string]any{"attachments": false})
	m = e.Do("GET", "/v1/widget/config?key="+ws.WidgetKey, hdtest.Auth{}, nil).Want(t, 200).Map(t)
	if ext, _ := m["attachment_extensions"].([]any); len(ext) != 0 {
		t.Fatal(m["attachment_extensions"])
	}
}

func TestAgentAttachments(t *testing.T) {
	e, ws := setup(t)
	other := e.NewWorkspace()
	e.Upload("/v1/attachments", ws.Viewer.As(ws), "a.txt", []byte("x")).Want(t, 403)
	e.Upload("/v1/attachments", hdtest.Auth{}, "a.txt", []byte("x")).Want(t, 401)
	e.Upload("/v1/attachments", ws.Agent.As(ws), "a.sh", []byte("echo hi")).Want(t, 422)
	e.Upload("/v1/attachments", ws.Agent.As(ws), "empty.txt", []byte{}).Want(t, 422)
	key := e.APIKey(ws, auth.ScopeTicketsRead)
	e.Upload("/v1/attachments", hdtest.Auth{Bearer: key}, "a.txt", []byte("x")).Want(t, 403)

	var img, doc domain.Attachment
	e.Upload("/v1/attachments", ws.Agent.As(ws), "pic.png", pngBytes()).Want(t, 201).JSON(t, &img)
	e.Upload("/v1/attachments", ws.Agent.As(ws), "page.html", []byte("<html><script>alert(1)</script></html>")).Want(t, 201).JSON(t, &doc)
	if img.ContentType != "image/png" || strings.Contains(doc.ContentType, "html") || doc.SizeBytes == 0 {
		t.Fatal(img, doc)
	}
	var keyPath string
	e.Scalar(`SELECT storage_key FROM attachments WHERE id = $1`, &keyPath, img.ID)
	if keyPath != "workspaces/"+ws.ID.String()+"/attachments/"+img.ID.String() {
		t.Fatal(keyPath)
	}

	// Members of the owning workspace (any role) and keys with tickets:read.
	r := e.Do("GET", "/v1/attachments/"+img.ID.String(), ws.Viewer.As(ws), nil).Want(t, 200)
	if !bytes.Equal(r.Body, pngBytes()) || r.Header.Get("X-Content-Type-Options") != "nosniff" ||
		!strings.HasPrefix(r.Header.Get("Content-Disposition"), "inline;") || r.Header.Get("Content-Type") != "image/png" {
		t.Fatal(r.Header)
	}
	r = e.Do("GET", "/v1/attachments/"+doc.ID.String(), hdtest.Auth{Bearer: key}, nil).Want(t, 200)
	if !strings.HasPrefix(r.Header.Get("Content-Disposition"), "attachment;") || !strings.Contains(r.Header.Get("Content-Security-Policy"), "sandbox") {
		t.Fatal(r.Header)
	}
	e.Do("GET", "/v1/attachments/"+img.ID.String(), hdtest.Auth{Bearer: e.APIKey(ws, auth.ScopeContactsRead)}, nil).Want(t, 404)
	// Another workspace's credentials see nothing, even with their own valid membership.
	e.Do("GET", "/v1/attachments/"+img.ID.String(), other.Owner.As(other), nil).Want(t, 404)
	e.Do("GET", "/v1/attachments/"+img.ID.String(), hdtest.Auth{Bearer: other.Owner.Token, Workspace: ws.ID}, nil).Want(t, 404)
	e.Do("GET", "/v1/attachments/"+img.ID.String(), hdtest.Auth{}, nil).Want(t, 404)
	e.Do("GET", "/v1/attachments/nope", hdtest.Auth{}, nil).Want(t, 404)

	// Signed links.
	u, _ := url.Parse(domain.AttachmentURL(img.ID))
	e.Do("GET", "/v1/attachments/"+img.ID.String()+"?"+u.RawQuery, hdtest.Auth{}, nil).Want(t, 200)
	q := u.Query()
	sig := q.Get("sig")
	tampered := []byte(sig)
	if tampered[0] == 'a' {
		tampered[0] = 'b'
	} else {
		tampered[0] = 'a'
	}
	e.Do("GET", "/v1/attachments/"+img.ID.String()+"?exp="+q.Get("exp")+"&sig="+string(tampered), hdtest.Auth{}, nil).Want(t, 404)
	e.Do("GET", "/v1/attachments/"+doc.ID.String()+"?"+u.RawQuery, hdtest.Auth{}, nil).Want(t, 404)
	expired := strconv.FormatInt(time.Now().Add(-time.Hour).Unix(), 10)
	e.Do("GET", "/v1/attachments/"+img.ID.String()+"?exp="+expired+"&sig="+sig, hdtest.Auth{}, nil).Want(t, 404)
	// An extended expiry with the old signature fails.
	later := strconv.FormatInt(time.Now().Add(72*time.Hour).Unix(), 10)
	e.Do("GET", "/v1/attachments/"+img.ID.String()+"?exp="+later+"&sig="+sig, hdtest.Auth{}, nil).Want(t, 404)
}

func TestUploadTooLarge(t *testing.T) {
	e, ws := setup(t)
	// Size checks in SaveUpload before reading.
	_, err := hd.SaveUpload(e.Ctx, e.D.Storage, e.D.DB.Pool, hd.Upload{WorkspaceID: ws.ID, Filename: "big.bin",
		Size: hd.MaxAttachmentBytes + 1, Body: bytes.NewReader([]byte("x"))})
	if err == nil || !strings.Contains(err.Error(), "25 MB") {
		t.Fatal(err)
	}
	big := make([]byte, hd.MaxAttachmentBytes+1)
	r := e.Upload("/v1/attachments", ws.Agent.As(ws), "big.bin", big)
	if r.Status != http.StatusRequestEntityTooLarge {
		t.Fatalf("status %d: %s", r.Status, r.Body)
	}
}

func TestWidgetSettings(t *testing.T) {
	e, ws := setup(t)
	e.Do("GET", "/v1/widget/settings", ws.Agent.As(ws), nil).Want(t, 403)
	e.Do("PATCH", "/v1/widget/settings", ws.Agent.As(ws), map[string]any{"enabled": false}).Want(t, 403)
	m := e.Do("GET", "/v1/widget/settings", ws.Admin.As(ws), nil).Want(t, 200).Map(t)
	if m["enabled"] != true {
		t.Fatal(m)
	}
	for _, bad := range []map[string]any{
		{"allowed_origins": []string{"http://shop.example"}},
		{"allowed_origins": []string{"https://shop.example/path"}},
		{"allowed_origins": []string{"javascript:alert(1)"}},
		{"allowed_origins": []string{"https://*.example"}},
		{"greeting": strings.Repeat("a", 301)},
		{"greeting": "hi\x00"},
	} {
		e.Do("PATCH", "/v1/widget/settings", ws.Admin.As(ws), bad).Want(t, 422)
	}
	m = e.Do("PATCH", "/v1/widget/settings", ws.Admin.As(ws), map[string]any{"greeting": " Hey there ", "require_email": true,
		"allowed_origins": []string{"HTTPS://Shop.Example/", "http://localhost:3000", "https://shop.example"}}).Want(t, 200).Map(t)
	origins, _ := m["allowed_origins"].([]any)
	if m["greeting"] != "Hey there" || m["require_email"] != true || m["enabled"] != true || len(origins) != 2 || origins[0] != "https://shop.example" {
		t.Fatal(m)
	}
	s, _ := hd.LoadSettings(e.Ctx, e.D.DB.Pool, ws.ID)
	if s.Widget == nil || s.Widget.Greeting != "Hey there" {
		t.Fatal(s)
	}
	var n int
	e.Scalar(`SELECT count(*) FROM audit_logs WHERE workspace_id = $1 AND action = 'widget.settings_updated'`, &n, ws.ID)
	if n != 1 {
		t.Fatal(n)
	}
	key := e.APIKey(ws, auth.ScopeSettingsRead)
	e.Do("GET", "/v1/widget/settings", hdtest.Auth{Bearer: key}, nil).Want(t, 200)
	e.Do("PATCH", "/v1/widget/settings", hdtest.Auth{Bearer: key}, map[string]any{"enabled": false}).Want(t, 403)
}

func pngBytes() []byte {
	return []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89")
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

func TestRateLimits(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey})
	va := hdtest.Auth{Visitor: s.VisitorToken}
	var tid uuid.UUID
	var created struct {
		Conversation struct {
			ID uuid.UUID `json:"id"`
		} `json:"conversation"`
	}
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "hi"}).Want(t, 201).JSON(t, &created)
	tid = created.Conversation.ID
	limited := false
	for i := 0; i < 40; i++ {
		if e.Do("POST", "/v1/widget/conversations/"+tid.String()+"/messages", va, map[string]any{"body": "spam"}).Status == 429 {
			limited = true
			break
		}
	}
	if !limited {
		t.Fatal("visitor writes not rate limited")
	}
	limited = false
	for i := 0; i < 25; i++ {
		if e.Do("POST", "/v1/widget/session", hdtest.Auth{}, map[string]any{"key": ws.WidgetKey}).Status == 429 {
			limited = true
			break
		}
	}
	if !limited {
		t.Fatal("session creation not rate limited")
	}
}

// Fetching a conversation's messages and marking it seen say the visitor is on the page.
func TestSeenRefreshesSession(t *testing.T) {
	e, ws := setup(t)
	s := start(t, e, map[string]any{"key": ws.WidgetKey, "email": "seen@example.com"})
	va := hdtest.Auth{Visitor: s.VisitorToken}
	var created struct {
		Conversation struct {
			ID uuid.UUID `json:"id"`
		} `json:"conversation"`
	}
	e.Do("POST", "/v1/widget/conversations", va, map[string]any{"body": "Hello"}).Want(t, 201).JSON(t, &created)
	path := "/v1/widget/conversations/" + created.Conversation.ID.String()
	away := func() {
		e.Exec(`UPDATE widget_sessions SET last_seen_at = now() - interval '1 hour' WHERE contact_id = $1`, s.Contact.ID)
	}
	recent := func() bool {
		var ok bool
		e.Scalar(`SELECT bool_and(last_seen_at > now() - interval '1 minute') FROM widget_sessions WHERE contact_id = $1`, &ok, s.Contact.ID)
		return ok
	}
	away()
	e.Do("GET", path+"/messages", va, nil).Want(t, 200)
	if !recent() {
		t.Fatal("fetching messages did not refresh the session")
	}
	away()
	e.Do("POST", path+"/seen", va, nil).Want(t, 204)
	if !recent() {
		t.Fatal("seen did not refresh the session")
	}
	other := start(t, e, map[string]any{"key": ws.WidgetKey, "email": "other@example.com"})
	e.Do("POST", path+"/seen", hdtest.Auth{Visitor: other.VisitorToken}, nil).Want(t, 404)
}
