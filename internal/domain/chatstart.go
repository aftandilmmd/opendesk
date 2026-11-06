package domain

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/db"
)

// Starting a chat (contracts/api.md "Tickets"): the team may open a chat with a contact the
// widget can show it to, and only when the widget proves who that is. Two kinds of contact
// qualify, not blocked either way:
//
//   - a verified identity (external_id, from the host page's user_hash): any brand's widget
//     shows it to them once the host page signs them in;
//   - an anonymous visitor, by their live session in a widget that is on, of the chat's brand,
//     whose contact holds only what came through the widget: every ticket of theirs is a chat
//     a widget started (by the visitor or by the team), and none of its messages arrived by
//     email. An address a visitor types proves nothing, so once mail from it, a call, a portal
//     request or any other ticket joins their contact, the chat reaches them only verified.

// liveSessionsSQL is the FROM of the contact's live widget sessions (alias s, widget g) in a
// widget that is on, of brand brand when that is not null (a session from before widgets had
// ids counts as the default brand's). ws, contact and brand are SQL expressions.
func liveSessionsSQL(ws, contact, brand string) string {
	return `FROM widget_sessions s
	LEFT JOIN widgets g ON g.id = s.widget_id AND g.workspace_id = s.workspace_id
	WHERE s.workspace_id = ` + ws + ` AND s.contact_id = ` + contact + ` AND ` + auth.VisitorSessionLive + `
	AND COALESCE((g.settings ->> 'enabled')::boolean, true)
	AND (` + brand + `::uuid IS NULL OR COALESCE(g.brand_id, (SELECT b.id FROM brands b WHERE b.workspace_id = ` + ws + ` AND b.is_default)) = ` + brand + `::uuid)`
}

// onlyWidgetSQL is true when the contact (alias ct) holds nothing that did not come through
// the widget: no ticket but chats a widget started, and no message on them that came by email.
const onlyWidgetSQL = `NOT EXISTS (SELECT 1 FROM tickets ot WHERE ot.workspace_id = ct.workspace_id AND ot.contact_id = ct.id
		AND (ot.channel <> 'chat' OR ot.widget_id IS NULL
			OR EXISTS (SELECT 1 FROM messages om WHERE om.workspace_id = ot.workspace_id AND om.ticket_id = ot.id
				AND om.direction = 'inbound' AND (om.inbound_email_id IS NOT NULL OR om.email_message_id IS NOT NULL))))`

// chatReachSQL is the one rule (contacts alias ct) for whether a chat of brand brand (a SQL
// uuid expression; NULL: some brand) reaches the contact, see the comment above.
func chatReachSQL(brand string) string {
	return `(NOT ct.blocked AND (ct.external_id IS NOT NULL OR (EXISTS (SELECT 1 ` +
		liveSessionsSQL("ct.workspace_id", "ct.id", brand) + `) AND ` + onlyWidgetSQL + `)))`
}

// ChatReachableSQL is Contact.chat_reachable (contacts alias ct): a chat in some brand's
// widget reaches the contact. One of a given brand also needs it to be that brand's
// (ChatReachable).
var ChatReachableSQL = chatReachSQL("NULL")

// ChatReachable says whether a chat of brandID reaches the contact, by the same rule as
// ChatReachableSQL.
func ChatReachable(ctx context.Context, q db.Querier, wid, contactID, brandID uuid.UUID) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `SELECT `+chatReachSQL("$3")+` FROM contacts ct WHERE ct.workspace_id = $1 AND ct.id = $2`,
		wid, contactID, brandID).Scan(&ok)
	return ok, err
}

// ChatWidget is the widget a new chat with the contact opens in when none was asked for:
// the widget of their latest live session of the brand (brand nil: any), else the brand's
// first enabled widget (brand nil: the default brand's). Not found when there is none.
func ChatWidget(ctx context.Context, q db.Querier, wid, contactID uuid.UUID, brandID *uuid.UUID) (uuid.UUID, error) {
	var id *uuid.UUID
	err := q.QueryRow(ctx, `SELECT COALESCE(
		(SELECT g.id `+liveSessionsSQL("$1", "$2", "$3")+` AND g.id IS NOT NULL ORDER BY s.last_seen_at DESC LIMIT 1),
		(SELECT g.id FROM widgets g WHERE g.workspace_id = $1
			AND g.brand_id = COALESCE($3, (SELECT b.id FROM brands b WHERE b.workspace_id = $1 AND b.is_default))
			AND COALESCE((g.settings ->> 'enabled')::boolean, true)
			ORDER BY g.created_at, g.id LIMIT 1))`, wid, contactID, brandID).Scan(&id)
	if err != nil {
		return uuid.Nil, err
	}
	if id == nil {
		return uuid.Nil, pgx.ErrNoRows
	}
	return *id, nil
}
