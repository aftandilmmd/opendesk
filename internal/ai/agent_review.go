package ai

import (
	"context"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/useopendesk/opendesk/internal/audit"
	"github.com/useopendesk/opendesk/internal/auth"
	"github.com/useopendesk/opendesk/internal/db"
	"github.com/useopendesk/opendesk/internal/domain"
	"github.com/useopendesk/opendesk/internal/events"
	"github.com/useopendesk/opendesk/internal/helpdesk/hd"
	"github.com/useopendesk/opendesk/internal/httpx"
)

// Improve answer and the review queue (contracts/agent.md): an admin writes the better
// answer to a question Ollie got wrong; it becomes a Q&A snippet the agent answers from
// at once, and optionally a test that expects it. The queue lists recent replies that
// visitors rated not helpful or that ended in a handoff.

const (
	reviewDays      = 30
	reviewLimit     = 50
	snippetQuestion = 300
)

// SnippetWriter creates Q&A snippet knowledge sources. internal/ai/knowledge implements
// it on its retriever (SetKnowledge), so this package never imports it.
type SnippetWriter interface {
	CreateSnippet(ctx context.Context, p *auth.Principal, name, question, answer string) (uuid.UUID, string, error)
}

// ImproveInput is POST /v1/ai/agent/improve.
type ImproveInput struct {
	Question  string     `json:"question" minLength:"3" maxLength:"4000" doc:"The visitor's question"`
	Answer    string     `json:"answer" minLength:"1" maxLength:"4000" doc:"The better answer, markdown"`
	MessageID *uuid.UUID `json:"message_id,omitempty" doc:"The agent reply being improved; it leaves the review queue"`
	SaveTest  bool       `json:"save_test,omitempty" doc:"Also save a test that expects this answer"`
}

// ImproveOutput is the snippet created, and the test when one was asked for.
type ImproveOutput struct {
	Source struct {
		ID   uuid.UUID `json:"id"`
		Kind string    `json:"kind" enum:"snippet"`
		Name string    `json:"name"`
	} `json:"source"`
	Test *AgentTest `json:"test"`
}

// AgentReviewItem is an agent reply that needs a look.
type AgentReviewItem struct {
	ID           uuid.UUID `json:"id" doc:"The agent reply's message id"`
	TicketID     uuid.UUID `json:"ticket_id"`
	TicketNumber int64     `json:"ticket_number"`
	Reason       string    `json:"reason" enum:"rated_down,handoff"`
	Question     string    `json:"question" doc:"The visitor message before the reply, up to 500 characters"`
	Answer       string    `json:"answer" doc:"The reply as text, up to 1,000 characters"`
	ContactName  string    `json:"contact_name"`
	CreatedAt    time.Time `json:"created_at"`
}

type reviewList struct {
	Data []AgentReviewItem `json:"data"`
}

func (s *Service) registerAgentReview(api huma.API, read, write func(context.Context) (*auth.Principal, error)) {
	tags := []string{"AI"}

	huma.Register(api, huma.Operation{OperationID: "ai-agent-improve", Method: http.MethodPost, Path: "/v1/ai/agent/improve",
		Summary: "Improve an agent answer", Description: "Saves the better answer to a question as a Q&A snippet knowledge source, " +
			"used by the agent at once, and optionally a test expecting it.", Tags: tags, DefaultStatus: http.StatusCreated},
		func(ctx context.Context, in *struct{ Body ImproveInput }) (*struct{ Body ImproveOutput }, error) {
			p, err := write(ctx)
			if err != nil {
				return nil, err
			}
			out, err := s.improve(ctx, p, in.Body)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			return &struct{ Body ImproveOutput }{out}, nil
		})

	huma.Register(api, huma.Operation{OperationID: "ai-agent-review", Method: http.MethodGet, Path: "/v1/ai/agent/review",
		Summary: "Agent replies to review", Description: "Up to 50 agent replies of the last 30 days that visitors rated not helpful " +
			"or that ended in a handoff, newest first, without the ones dismissed or improved.", Tags: tags},
		func(ctx context.Context, _ *struct{}) (*struct{ Body reviewList }, error) {
			p, err := read(ctx)
			if err != nil {
				return nil, err
			}
			items, err := s.reviewQueue(ctx, p)
			if err != nil {
				return nil, httpx.Wrap(err)
			}
			return &struct{ Body reviewList }{reviewList{Data: items}}, nil
		})

	huma.Register(api, huma.Operation{OperationID: "ai-agent-review-dismiss", Method: http.MethodPost, Path: "/v1/ai/agent/review/{id}/dismiss",
		Summary: "Dismiss an agent reply from review", Tags: tags, DefaultStatus: http.StatusNoContent},
		func(ctx context.Context, in *struct {
			ID uuid.UUID `path:"id"`
		}) (*struct{}, error) {
			p, err := write(ctx)
			if err != nil {
				return nil, err
			}
			err = s.d.DB.Tx(ctx, func(tx pgx.Tx) error { return markReviewed(ctx, tx, p, in.ID, "dismissed") })
			if err != nil {
				return nil, reviewErr(err)
			}
			return nil, nil
		})
}

func reviewErr(err error) error {
	if db.IsNotFound(err) {
		return httpx.NotFound("Agent reply")
	}
	return httpx.Wrap(err)
}

// reviewTicket returns the ticket of an agent reply of the workspace that p may see; a
// reply on a ticket p may not see is not found.
func reviewTicket(ctx context.Context, q db.Querier, p *auth.Principal, messageID uuid.UUID) (uuid.UUID, error) {
	hidden, err := domain.HiddenTeams(ctx, q, p)
	if err != nil {
		return uuid.Nil, err
	}
	var tid uuid.UUID
	err = q.QueryRow(ctx, `SELECT t.id FROM messages m
		JOIN tickets t ON t.workspace_id = m.workspace_id AND t.id = m.ticket_id AND t.deleted_at IS NULL
		WHERE m.workspace_id = $1 AND m.id = $2 AND m.ai AND m.kind = 'reply' AND `+domain.VisibleSQLUser("t", 3, 4),
		p.WorkspaceID, messageID, hidden, p.UserID).Scan(&tid)
	return tid, err
}

// markReviewed takes an agent reply of the workspace off the review queue.
func markReviewed(ctx context.Context, tx pgx.Tx, p *auth.Principal, messageID uuid.UUID, outcome string) error {
	tid, err := reviewTicket(ctx, tx, p, messageID)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO ai_agent_reviews (message_id, workspace_id, outcome, user_id) VALUES ($1, $2, $3, $4)
		ON CONFLICT (message_id) DO UPDATE SET outcome = EXCLUDED.outcome, user_id = EXCLUDED.user_id, created_at = now()`,
		messageID, p.WorkspaceID, outcome, p.ActorUserID()); err != nil {
		return err
	}
	_, err = events.Publish(ctx, tx, events.Event{WorkspaceID: p.WorkspaceID, Type: "ai_agent_review.updated", TicketID: &tid,
		Data: map[string]any{"message_id": messageID, "ticket_id": tid, "outcome": outcome}})
	return err
}

// improve creates the snippet, then the test when asked, and takes the reply off the queue.
func (s *Service) improve(ctx context.Context, p *auth.Principal, in ImproveInput) (ImproveOutput, error) {
	var out ImproveOutput
	question := strings.TrimSpace(strings.ToValidUTF8(in.Question, ""))
	answer := strings.TrimSpace(strings.ToValidUTF8(in.Answer, ""))
	if n := utf8.RuneCountInString(question); n < 3 || n > 4000 {
		return out, httpx.Validation("question must be 3 to 4000 characters")
	}
	if n := utf8.RuneCountInString(answer); n < 1 || n > 4000 {
		return out, httpx.Validation("answer must be 1 to 4000 characters")
	}
	sw, ok := s.knowledgeRetriever().(SnippetWriter)
	if !ok {
		return out, httpx.E(http.StatusServiceUnavailable, "knowledge_unavailable", "Knowledge sources are not available.")
	}
	var test AgentTestInput
	if in.SaveTest {
		expect := cleanLine(hd.HTMLToText(markdownToHTML(answer)), maxExpectationRunes)
		test = AgentTestInput{Messages: []PlaygroundMessage{{Role: "visitor", Text: question}},
			Expectations: []AgentExpectation{{Kind: expectMentions, Value: expect}}}
		if _, err := cleanMessages(test.Messages); err != nil {
			return out, err
		}
		if _, err := cleanExpectations(test.Expectations); err != nil {
			return out, err
		}
		var n int
		if err := s.d.DB.Pool.QueryRow(ctx, `SELECT count(*) FROM ai_agent_tests WHERE workspace_id = $1`, p.WorkspaceID).Scan(&n); err != nil {
			return out, err
		}
		if n >= maxAgentTests {
			return out, errTestLimit
		}
	}
	if in.MessageID != nil {
		if _, err := reviewTicket(ctx, s.d.DB.Pool, p, *in.MessageID); err != nil {
			return out, reviewErr(err)
		}
	}
	snippetQ := clipWords(cleanLine(question, 4000), snippetQuestion)
	id, name, err := sw.CreateSnippet(ctx, p, "", snippetQ, answer)
	if err != nil {
		return out, err
	}
	out.Source.ID, out.Source.Kind, out.Source.Name = id, "snippet", name
	err = s.d.DB.Tx(ctx, func(tx pgx.Tx) error {
		data := map[string]any{"source_id": id}
		if in.SaveTest {
			t, err := s.createTest(ctx, tx, p, test)
			if err != nil {
				return err
			}
			out.Test = &t
			data["test_id"] = t.ID
		}
		if in.MessageID != nil {
			if err := markReviewed(ctx, tx, p, *in.MessageID, "improved"); err != nil {
				return err
			}
			data["message_id"] = *in.MessageID
		}
		return audit.Log(ctx, tx, p, p.WorkspaceID, "ai.agent_answer_improved", "ai_knowledge_source", &id, data)
	})
	return out, err
}

// clipWords shortens s to at most n runes, at a word boundary when one is near.
func clipWords(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	cut := string(r[:n-1])
	if i := strings.LastIndexByte(cut, ' '); i > len(cut)*2/3 {
		cut = cut[:i]
	}
	return strings.TrimSpace(cut) + "…"
}

// reviewQueue lists recent agent replies rated not helpful or followed by the agent's
// handoff, not yet dismissed or improved, on tickets p may see.
func (s *Service) reviewQueue(ctx context.Context, p *auth.Principal) ([]AgentReviewItem, error) {
	hidden, err := domain.HiddenTeams(ctx, s.d.DB.Pool, p)
	if err != nil {
		return nil, err
	}
	rows, err := s.d.DB.Pool.Query(ctx, `SELECT m.id, m.ticket_id, t.number,
			CASE WHEN m.ai_rating = 'down' THEN 'rated_down' ELSE 'handoff' END,
			COALESCE(left(btrim(regexp_replace(q.body_text, '\s+', ' ', 'g')), 500), ''),
			left(btrim(regexp_replace(m.body_text, '\s+', ' ', 'g')), 1000),
			COALESCE(c.name, ''), m.created_at
		FROM messages m
		JOIN tickets t ON t.workspace_id = m.workspace_id AND t.id = m.ticket_id AND t.deleted_at IS NULL
		LEFT JOIN contacts c ON c.workspace_id = t.workspace_id AND c.id = t.contact_id
		LEFT JOIN ai_widget_answers a ON a.workspace_id = m.workspace_id AND a.reply_id = m.id
		LEFT JOIN LATERAL (SELECT v.body_text FROM messages v WHERE v.workspace_id = m.workspace_id AND v.ticket_id = m.ticket_id
			AND v.kind = 'reply' AND v.direction = 'inbound' AND v.deleted_at IS NULL AND v.created_at < m.created_at ORDER BY v.created_at DESC LIMIT 1) q ON true
		WHERE m.workspace_id = $1 AND m.ai AND m.kind = 'reply' AND m.deleted_at IS NULL AND m.created_at > now() - make_interval(days => $2)
			AND (m.ai_rating = 'down' OR COALESCE(a.handoff, false))
			AND NOT EXISTS (SELECT 1 FROM ai_agent_reviews r WHERE r.message_id = m.id)
			AND `+domain.VisibleSQLUser("t", 4, 5)+`
		ORDER BY m.created_at DESC LIMIT $3`, p.WorkspaceID, reviewDays, reviewLimit, hidden, p.UserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AgentReviewItem{}
	for rows.Next() {
		var it AgentReviewItem
		if err := rows.Scan(&it.ID, &it.TicketID, &it.TicketNumber, &it.Reason, &it.Question, &it.Answer, &it.ContactName, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}
