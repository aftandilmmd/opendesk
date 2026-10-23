package email

import (
	"context"
	"testing"

	"github.com/google/uuid"

	"github.com/useopendesk/opendesk/internal/domain"
)

// TestDeletedReplyIsNotSent checks a reply deleted before it goes out is not handed to the
// mailbox and is marked not sent, with its update carrying no text; and that one deleted
// while it was being handed over is recorded as sent, since it was.
func TestDeletedReplyIsNotSent(t *testing.T) {
	w := newWorld(t)
	m := w.mailbox(InboundForwarding, OutboundSystem, nil)
	sends := 0
	var during func()
	w.s.rawSend = func(context.Context, string, []string, []byte) error {
		sends++
		if during != nil {
			during()
		}
		return nil
	}
	tk, _ := firstTicket(t, w, m, customer())
	reply := func(text string) uuid.UUID {
		var mid uuid.UUID
		if err := w.d.DB.Tx(w.ctx, func(tx pgxTx) error {
			msg, err := domain.AddMessage(w.ctx, tx, w.d.Jobs, domain.NewMessage{WorkspaceID: w.wid, TicketID: tk.ID, Kind: "reply",
				Direction: "outbound", AuthorType: "user", AuthorUserID: &w.uid, DeliveryStatus: "pending",
				BodyHTML: "<p>" + text + "</p>", BodyText: text})
			mid = msg.ID
			return err
		}); err != nil {
			t.Fatal(err)
		}
		return mid
	}

	gone := reply("Never meant to send this")
	var seq int64
	if err := w.d.DB.Pool.QueryRow(w.ctx, `SELECT event_seq FROM workspaces WHERE id = $1`, w.wid).Scan(&seq); err != nil {
		t.Fatal(err)
	}
	mustExec(t, w.d, `UPDATE messages SET deleted_at = now() WHERE id = $1`, gone)
	if err := w.s.sendMessage(w.ctx, w.wid, gone, false); err != nil {
		t.Fatal(err)
	}
	if sends != 0 {
		t.Fatal("a deleted reply was sent")
	}
	if got := w.message(gone); got.Delivery != "failed" || got.DelivError != domain.DeletedBeforeSent {
		t.Fatalf("deleted reply delivery %q %q", got.Delivery, got.DelivError)
	}
	var leaked int
	if err := w.d.DB.Pool.QueryRow(w.ctx, `SELECT count(*) FROM events WHERE workspace_id = $1 AND seq > $2 AND data::text LIKE '%Never meant%'`,
		w.wid, seq).Scan(&leaked); err != nil {
		t.Fatal(err)
	}
	if leaked != 0 {
		t.Fatal("the update of a deleted reply carries its text")
	}

	// Deleted while it was being handed over: it went out, and says so.
	raced := reply("Already on its way")
	during = func() {
		mustExec(t, w.d, `UPDATE messages SET deleted_at = now(), delivery_status = 'failed', delivery_error = $2 WHERE id = $1`, raced, domain.DeletedBeforeSent)
	}
	if err := w.s.sendMessage(w.ctx, w.wid, raced, false); err != nil {
		t.Fatal(err)
	}
	if got := w.message(raced); sends != 1 || got.Delivery != "sent" {
		t.Fatalf("raced reply sends %d delivery %q", sends, got.Delivery)
	}
}
