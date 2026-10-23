package ai

import (
	"context"
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/useopendesk/opendesk/internal/ai/bots"
	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/db"
	"github.com/useopendesk/opendesk/internal/domain"
	"github.com/useopendesk/opendesk/internal/events"
	"github.com/useopendesk/opendesk/internal/helpdesk/hd"
	"github.com/useopendesk/opendesk/internal/httpx"
	"github.com/useopendesk/opendesk/internal/ids"
)

// The suggested reply routes (contracts/agent.md "Email"): a teammate sends the agent's
// suggested reply as is, or discards it. Editing happens in the composer, as the
// teammate's own reply.

var errSuggestionGone = httpx.E(http.StatusConflict, "suggestion_not_pending", "This suggested reply was already sent, discarded or replaced.")

type suggestedInput struct {
	ID string `path:"id"`
}

type suggestedActionInput struct {
	ID           string `path:"id"`
	SuggestionID string `path:"suggestion_id"`
}

// SuggestedReplyBody is GET /v1/tickets/{id}/ai/suggested-reply.
type SuggestedReplyBody struct {
	SuggestedReply *SuggestedReply `json:"suggested_reply" doc:"The pending suggestion for the ticket's latest customer message, or null"`
}

func (s *Service) registerSuggested(api huma.API) {
	tags := []string{"AI"}

	huma.Register(api, huma.Operation{OperationID: "ai-get-suggested-reply", Method: http.MethodGet, Path: "/v1/tickets/{id}/ai/suggested-reply",
		Summary: "Get the suggested reply", Description: "The agent's pending suggested reply on an email ticket, or null.", Tags: tags},
		func(ctx context.Context, in *suggestedInput) (*struct{ Body SuggestedReplyBody }, error) {
			p, err := auth.RequireWorkspace(ctx, auth.RoleViewer, auth.ScopeTicketsRead)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			tid, err := resolveVisibleTicket(ctx, s.d.DB.Pool, p, in.ID)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			r, err := currentSuggestion(ctx, s.d.DB.Pool, p.WorkspaceID, tid, uuid.Nil, false)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			return &struct{ Body SuggestedReplyBody }{SuggestedReplyBody{SuggestedReply: r}}, nil
		})

	huma.Register(api, huma.Operation{OperationID: "ai-send-suggested-reply", Method: http.MethodPost, Path: "/v1/tickets/{id}/ai/suggested-reply/{suggestion_id}/send",
		Summary: "Send the suggested reply", Description: "Sends the agent's suggested reply by email as written, attributed to the agent. " +
			"`409 suggestion_not_pending` when it was sent, discarded or replaced, or the conversation moved on.", Tags: tags},
		func(ctx context.Context, in *suggestedActionInput) (*struct{ Body domain.Message }, error) {
			p, err := auth.RequireWorkspace(ctx, auth.RoleAgent, auth.ScopeTicketsWrite)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			tid, err := resolveVisibleTicket(ctx, s.d.DB.Pool, p, in.ID)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			rid, ok := ids.Parse(in.SuggestionID)
			if !ok {
				return nil, httpx.NotFound("Suggested reply")
			}
			var mailbox *uuid.UUID
			if err := s.d.DB.Pool.QueryRow(ctx, `SELECT mailbox_id FROM tickets WHERE workspace_id = $1 AND id = $2`, p.WorkspaceID, tid).
				Scan(&mailbox); err != nil {
				return nil, httpx.Wrap(err)
			}
			bot, err := bots.ForMailbox(ctx, s.d.DB.Pool, p.WorkspaceID, mailbox)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			var msg domain.Message
			err = s.d.DB.Tx(ctx, func(tx pgx.Tx) error {
				r, err := currentSuggestion(ctx, tx, p.WorkspaceID, tid, rid, true)
				if err != nil {
					return err
				}
				if r == nil {
					return errSuggestionGone
				}
				var subject string
				if err := tx.QueryRow(ctx, `SELECT subject FROM tickets WHERE workspace_id = $1 AND id = $2`, p.WorkspaceID, tid).Scan(&subject); err != nil {
					return err
				}
				body := s.fillAnswer(ctx, tx, p.WorkspaceID, tid, bot.Name, r.BodyHTML)
				msg, err = domain.AddMessage(ctx, tx, s.d.Jobs, domain.NewMessage{WorkspaceID: p.WorkspaceID, TicketID: tid, Kind: "reply",
					Direction: "outbound", AuthorType: "system", BodyHTML: body, BodyText: hd.HTMLToText(body), Subject: subject,
					Trigger: "none", AI: true, FromName: bot.Name, BotID: bot.IDPtr(), DeliveryStatus: "pending"})
				if err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `UPDATE ai_widget_answers SET reply_id = $2 WHERE message_id = $1`, r.MessageID, msg.ID); err != nil {
					return err
				}
				if _, err := domain.LogActivity(ctx, tx, p.WorkspaceID, tid, actorType(p), p.ActorUserID(), "ai_suggested_reply_sent",
					map[string]any{"suggested_reply_id": r.ID.String(), "message_id": msg.ID.String()}); err != nil {
					return err
				}
				return s.decideSuggestion(ctx, tx, p, tid, r.ID, "sent", &msg.ID)
			})
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			return &struct{ Body domain.Message }{msg}, nil
		})

	huma.Register(api, huma.Operation{OperationID: "ai-discard-suggested-reply", Method: http.MethodDelete, Path: "/v1/tickets/{id}/ai/suggested-reply/{suggestion_id}",
		Summary: "Discard the suggested reply", Description: "Nothing is sent. Idempotent.", Tags: tags, DefaultStatus: http.StatusNoContent},
		func(ctx context.Context, in *suggestedActionInput) (*struct{}, error) {
			p, err := auth.RequireWorkspace(ctx, auth.RoleAgent, auth.ScopeTicketsWrite)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			tid, err := resolveVisibleTicket(ctx, s.d.DB.Pool, p, in.ID)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			rid, ok := ids.Parse(in.SuggestionID)
			if !ok {
				return nil, httpx.NotFound("Suggested reply")
			}
			err = s.d.DB.Tx(ctx, func(tx pgx.Tx) error {
				var status string
				err := tx.QueryRow(ctx, `SELECT status FROM ai_suggested_replies WHERE workspace_id = $1 AND ticket_id = $2 AND id = $3 FOR UPDATE`,
					p.WorkspaceID, tid, rid).Scan(&status)
				if db.IsNotFound(err) {
					return httpx.NotFound("Suggested reply")
				}
				if err != nil || status != "pending" {
					return err
				}
				return s.decideSuggestion(ctx, tx, p, tid, rid, "discarded", nil)
			})
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			return nil, nil
		})
}

func actorType(p *auth.Principal) string {
	if p.Kind == auth.KindAPIKey {
		return "api"
	}
	return "user"
}

// currentSuggestion returns the ticket's pending suggestion while it still answers the
// latest message of the ticket; nil otherwise. With id set
// it must be that suggestion; lock locks it.
func currentSuggestion(ctx context.Context, q db.Querier, wid, tid, id uuid.UUID, lock bool) (*SuggestedReply, error) {
	sql := `SELECT ` + suggestedColumns + ` FROM ai_suggested_replies r WHERE workspace_id = $1 AND ticket_id = $2 AND status = 'pending'
		AND ($3::uuid IS NULL OR id = $3)
		AND r.message_id = (SELECT m.id FROM messages m WHERE m.workspace_id = $1 AND m.ticket_id = $2 AND m.kind = 'reply' AND m.deleted_at IS NULL
			ORDER BY m.created_at DESC, m.id DESC LIMIT 1)
		AND EXISTS (SELECT 1 FROM tickets t WHERE t.workspace_id = $1 AND t.id = $2 AND t.deleted_at IS NULL)`
	if lock {
		sql += ` FOR UPDATE OF r`
	}
	var idArg *uuid.UUID
	if id != uuid.Nil {
		idArg = &id
	}
	r, err := scanSuggested(q.QueryRow(ctx, sql, wid, tid, idArg))
	if db.IsNotFound(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// decideSuggestion records a teammate's decision and publishes ai_suggested_reply.updated.
func (s *Service) decideSuggestion(ctx context.Context, tx pgx.Tx, p *auth.Principal, tid, id uuid.UUID, status string, replyID *uuid.UUID) error {
	r, err := scanSuggested(tx.QueryRow(ctx, `UPDATE ai_suggested_replies SET status = $4, reply_id = $5, decided_by = $6, decided_at = now()
		WHERE workspace_id = $1 AND ticket_id = $2 AND id = $3 RETURNING `+suggestedColumns, p.WorkspaceID, tid, id, status, replyID, p.ActorUserID()))
	if err != nil {
		return err
	}
	_, err = events.Publish(ctx, tx, events.Event{WorkspaceID: p.WorkspaceID, Type: "ai_suggested_reply.updated",
		Data: map[string]any{"ticket_id": tid, "suggested_reply": r}})
	return err
}
