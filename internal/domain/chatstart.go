package domain

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/db"
)

// Starting a chat (contracts/api.md "Tickets"): the team may open a chat with a contact the
// widget can show it to, and only that one. The widget knows a contact two ways: a verified
// identity (external_id, from the host page's user_hash) or the visitor's own session token.
// An email a visitor typed never links them to an existing contact, so it reaches no one here.

// chatSessionsSQL is the visitor's live widget sessions, of brand $3 when it is not null
// (a session from before widgets had ids counts as the default brand's), alias s and g.
const chatSessionsSQL = `FROM widget_sessions s
	LEFT JOIN widgets g ON g.id = s.widget_id AND g.workspace_id = s.workspace_id
	WHERE s.workspace_id = $1 AND s.contact_id = $2 AND ` + auth.VisitorSessionLive + `
	AND ($3::uuid IS NULL OR COALESCE(g.brand_id, (SELECT b.id FROM brands b WHERE b.workspace_id = $1 AND b.is_default)) = $3)`

// ChatReachableSQL is the condition (contacts alias ct) that a contact can get a chat in some
// widget: not blocked, and verified in a widget or with a live widget session.
const ChatReachableSQL = `(NOT ct.blocked AND (ct.external_id IS NOT NULL OR EXISTS (SELECT 1 FROM widget_sessions s
	WHERE s.workspace_id = ct.workspace_id AND s.contact_id = ct.id AND ` + auth.VisitorSessionLive + `)))`

// ChatReachable says whether a chat of brandID (nil: any brand) reaches the contact: not
// blocked, and verified in a widget or with a live session in a widget of the brand.
func ChatReachable(ctx context.Context, q db.Querier, wid, contactID, brandID uuid.UUID) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `SELECT NOT c.blocked AND (c.external_id IS NOT NULL OR EXISTS (SELECT 1 `+chatSessionsSQL+`))
		FROM contacts c WHERE c.workspace_id = $1 AND c.id = $2`, wid, contactID, brandID).Scan(&ok)
	return ok, err
}

// ChatWidget is the widget a new chat with the contact opens in when none was asked for:
// the widget of their latest live session of the brand, else the brand's first enabled
// widget (brand nil: the default brand's). Not found when the brand has no enabled widget.
func ChatWidget(ctx context.Context, q db.Querier, wid, contactID uuid.UUID, brandID *uuid.UUID) (uuid.UUID, error) {
	var id *uuid.UUID
	err := q.QueryRow(ctx, `SELECT COALESCE(
		(SELECT g.id `+chatSessionsSQL+` AND g.id IS NOT NULL AND COALESCE((g.settings ->> 'enabled')::boolean, true)
			ORDER BY s.last_seen_at DESC LIMIT 1),
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
