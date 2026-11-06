package collab

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// Provider HTTPS calls (Gmail and Microsoft Graph): the account's access token, one
// refresh on 401, each account's calls paced within the provider's limits, a short wait
// and another try while the provider is busy, no call at all while it asked for a longer
// one, and provider errors reduced to safe, classified messages.

// restRequest is one provider call.
type restRequest struct {
	beforeRequest func(context.Context) error
	method        string
	url           string
	body          []byte
	contentType   string
	headers       map[string]string
	// limit bounds the response body read; 1 MB when zero.
	limit int64
}

// errTooLarge is a response over the request's limit (a message over maxRawBytes).
var errTooLarge = errors.New("the message is too large to import")

// call runs a provider request and returns the response body of a 2xx answer. A busy
// provider (a rate limit, or a 5xx to a read) is asked again after each of s.busyWaits, or
// after the wait it asks for when that is no longer than maxBusyWait. A longer one holds
// the account (holdAccount): until it ends, no call for it is made.
func (s *service) call(ctx context.Context, a *accountRow, label string, r restRequest) ([]byte, error) {
	limit := r.limit
	if limit == 0 {
		limit = 1 << 20
	}
	ep := endpointOf(a.Provider, r.method, r.url)
	refreshed, waited := false, 0
	for {
		if until := s.heldUntil(a); time.Now().Before(until) {
			return nil, heldError(label, ep, until)
		}
		token, err := s.accessToken(ctx, a)
		if err != nil {
			return nil, err
		}
		var rd io.Reader
		if r.body != nil {
			rd = bytes.NewReader(r.body)
		}
		req, err := http.NewRequestWithContext(ctx, r.method, r.url, rd)
		if err != nil {
			return nil, err
		}
		if r.beforeRequest != nil {
			if err := r.beforeRequest(ctx); err != nil {
				return nil, err
			}
		}
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Accept", "application/json")
		if r.contentType != "" {
			req.Header.Set("Content-Type", r.contentType)
		}
		for k, v := range r.headers {
			req.Header.Add(k, v)
		}
		release, err := s.pace(a).wait(ctx, ep.units)
		if err != nil {
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			return nil, errProviderUnavailable // the job's time would run out waiting
		}
		if r.beforeRequest != nil {
			if err := r.beforeRequest(ctx); err != nil {
				release()
				return nil, err
			}
		}
		resp, err := s.http.Do(req)
		if err != nil {
			release()
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			return nil, errProviderUnavailable
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
		resp.Body.Close()
		release()
		if err != nil {
			return nil, errProviderUnavailable
		}
		if resp.StatusCode == http.StatusUnauthorized {
			if refreshed {
				return nil, errReconnect
			}
			if err := s.expireToken(ctx, a); err != nil {
				return nil, err
			}
			refreshed = true
			continue
		}
		if resp.StatusCode/100 != 2 {
			err := httpFailure(label, resp.StatusCode, body)
			var pe *providerError
			if !errors.As(err, &pe) {
				return nil, err
			}
			pe.endpoint = ep.name
			if !pe.busy {
				return nil, err
			}
			wait, asked := providerWait(resp.Header, body, time.Now())
			if asked && wait > maxBusyWait {
				pe.retryAt = s.holdAccount(ctx, a, time.Now().Add(wait))
				pe.msg = heldMessage(label, pe.retryAt)
				return nil, err
			}
			if waited < len(s.busyWaits) && (pe.limited || r.method == http.MethodGet) {
				if !asked {
					wait = s.busyWaits[waited]
				}
				waited++
				t := time.NewTimer(wait)
				select {
				case <-ctx.Done():
					t.Stop()
					return nil, ctx.Err()
				case <-t.C:
				}
				continue
			}
			return nil, err
		}
		if int64(len(body)) > limit {
			return nil, errTooLarge
		}
		return body, nil
	}
}

// paceLimit is how fast and how many at once one account's provider is asked.
type paceLimit struct {
	perSecond rate.Limit
	burst     int
	atOnce    int
}

// providerPaces keep each account inside its provider's limits, in the units the provider
// counts (endpointOf): Gmail allows 250 quota units a second per user and prices each method
// (reading a message costs 5, a send 100), so 200 a second leave room for another process's
// calls for the account; Microsoft allows 10,000 requests in 10 minutes and 4 at once per
// mailbox. The sync reads gmailFetchers or graphFetchers messages at once and leaves the
// other places to people's own actions.
var providerPaces = map[string]paceLimit{
	ProviderGoogle:    {perSecond: 200, burst: 250, atOnce: 8},
	ProviderMicrosoft: {perSecond: 15, burst: 15, atOnce: 4},
}

// pace is one account's turns at its provider, shared by every call this process makes
// for it: the sync's fetchers, actions and people's own reads.
type pace struct {
	rate  *rate.Limiter
	slots chan struct{}
	// until is the end of the account's hold, as this process last saw it.
	mu    sync.Mutex
	until time.Time
}

// pace returns the account's pace, nil for a provider without one.
func (s *service) pace(a *accountRow) *pace {
	s.paceMu.Lock()
	defer s.paceMu.Unlock()
	if p := s.paced[a.ID]; p != nil {
		return p
	}
	l, ok := s.paceLimits[a.Provider]
	if !ok {
		return nil
	}
	p := &pace{rate: rate.NewLimiter(l.perSecond, l.burst), slots: make(chan struct{}, l.atOnce)}
	s.paced[a.ID] = p
	return p
}

// wait takes one of the account's places and its turn for a call of units; release gives
// the place back.
func (p *pace) wait(ctx context.Context, units int) (release func(), err error) {
	if p == nil {
		return func() {}, nil
	}
	select {
	case p.slots <- struct{}{}:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	release = func() { <-p.slots }
	if err := p.rate.WaitN(ctx, min(max(units, 1), p.rate.Burst())); err != nil {
		release()
		return nil, err
	}
	return release, nil
}

// maxBusyWait is the longest wait a call sits out itself; a longer one holds the account.
const maxBusyWait = 15 * time.Second

// maxHold bounds a hold, whatever the provider asks for.
const maxHold = 24 * time.Hour

// gmailRetryAt is the time in Gmail's own words for a rate limit ("User-rate limit
// exceeded.  Retry after 2026-11-06T17:03:00.000Z"). Only the time is read from them.
var gmailRetryAt = regexp.MustCompile(`Retry after (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z)`)

// providerWait is the wait the provider asked for, if it asked: Retry-After in seconds or as
// a date, or the time in Gmail's message for a rate limit.
func providerWait(h http.Header, body []byte, now time.Time) (time.Duration, bool) {
	if v := strings.TrimSpace(h.Get("Retry-After")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			return time.Duration(n) * time.Second, true
		}
		if t, err := http.ParseTime(v); err == nil {
			return max(t.Sub(now), 0), true
		}
	}
	var e struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &e) == nil {
		if m := gmailRetryAt.FindStringSubmatch(e.Error.Message); m != nil {
			if t, err := time.Parse(time.RFC3339Nano, m[1]); err == nil {
				return max(t.Sub(now), 0), true
			}
		}
	}
	return 0, false
}

// holdAccount keeps every call for the account from its provider until until (at most
// maxHold away): in this process at once, in the others through
// collab_accounts.provider_wait_until. It returns the end of the hold.
func (s *service) holdAccount(ctx context.Context, a *accountRow, until time.Time) time.Time {
	if longest := time.Now().Add(maxHold); until.After(longest) {
		until = longest
	}
	until = until.Truncate(time.Second).Add(time.Second)
	if p := s.pace(a); p != nil {
		p.mu.Lock()
		if until.After(p.until) {
			p.until = until
		}
		p.mu.Unlock()
	}
	if a.WaitUntil == nil || a.WaitUntil.Before(until) {
		a.WaitUntil = &until
	}
	if _, err := s.d.DB.Pool.Exec(context.WithoutCancel(ctx), `UPDATE collab_accounts
		SET provider_wait_until = GREATEST(provider_wait_until, $2) WHERE id = $1`, a.ID, until); err != nil {
		s.log.Warn("collab provider hold", "account_id", a.ID, "err", err)
	}
	s.log.Info("collab provider asked to wait", "account_id", a.ID, "provider", a.Provider, "until", until)
	return until
}

// heldUntil is the end of the account's hold, zero when there is none.
func (s *service) heldUntil(a *accountRow) time.Time {
	var until time.Time
	if a.WaitUntil != nil {
		until = *a.WaitUntil
	}
	if p := s.pace(a); p != nil {
		p.mu.Lock()
		if p.until.After(until) {
			until = p.until
		}
		p.mu.Unlock()
	}
	return until
}

func heldMessage(label string, until time.Time) string {
	return label + " asked us to wait until " + until.UTC().Format("Jan 2 15:04 UTC") + ". We will try again then."
}

// heldError is a call left unmade while the account is held.
func heldError(label string, ep endpoint, until time.Time) error {
	return &providerError{msg: heldMessage(label, until), status: http.StatusTooManyRequests, busy: true, limited: true, endpoint: ep.name, retryAt: until}
}

// callJSON sends in as JSON (when not nil) and decodes the answer into out (when not nil).
func (s *service) callJSON(ctx context.Context, a *accountRow, label, method, url string, in, out any, headers map[string]string) error {
	r := restRequest{method: method, url: url, headers: headers}
	if in != nil {
		b, err := json.Marshal(in)
		if err != nil {
			return err
		}
		r.body, r.contentType = b, "application/json"
	}
	body, err := s.call(ctx, a, label, r)
	if err != nil {
		return err
	}
	if out != nil && len(bytes.TrimSpace(body)) > 0 {
		if err := json.Unmarshal(body, out); err != nil {
			return &providerError{msg: label + " returned an unreadable answer."}
		}
	}
	return nil
}

// httpFailure turns a provider HTTP error into a safe, classified error: the status and
// the provider's error code, never its message (it can echo addresses or content).
func httpFailure(label string, status int, body []byte) error {
	var e struct {
		Error json.RawMessage `json:"error"`
	}
	_ = json.Unmarshal(body, &e)
	var detail struct {
		Code   any    `json:"code"`
		Status string `json:"status"`
		Errors []struct {
			Reason string `json:"reason"`
		} `json:"errors"`
		Details []struct {
			Reason string `json:"reason"`
		} `json:"details"`
	}
	_ = json.Unmarshal(e.Error, &detail)
	code := ""
	switch c := detail.Code.(type) {
	case string:
		code = c // Graph: "ErrorItemNotFound"
	}
	reasons := []string{code, detail.Status}
	for _, r := range detail.Errors {
		reasons = append(reasons, r.Reason)
	}
	for _, r := range detail.Details {
		reasons = append(reasons, r.Reason)
	}
	has := func(list ...string) bool {
		for _, r := range reasons {
			for _, want := range list {
				if r != "" && strings.EqualFold(r, want) {
					return true
				}
			}
		}
		return false
	}
	shown := ""
	for _, r := range reasons {
		if r != "" {
			shown = safeCode(r)
			break
		}
	}
	msg := fmt.Sprintf("%s refused the request (%d", label, status)
	if shown != "" {
		msg += " " + shown
	}
	msg += ")."
	switch {
	case status == http.StatusTooManyRequests || has("rateLimitExceeded", "userRateLimitExceeded", "ApplicationThrottled"):
		return &providerError{msg: label + " is busy. We will try again.", status: status, busy: true, limited: true, code: shown}
	case status >= 500:
		return &providerError{msg: label + " is busy. We will try again.", status: status, busy: true, code: shown}
	case status == http.StatusNotFound || has("ErrorItemNotFound"):
		return &providerError{msg: msg, status: status, permanent: true, notFound: true}
	case status == http.StatusForbidden && has("insufficientPermissions", "ACCESS_TOKEN_SCOPE_INSUFFICIENT", "ErrorAccessDenied", "authError"):
		return errReconnect
	case has("ErrorSendAsDenied"):
		// Exchange sends from an alias only where the organization allows it (SendFromAlias).
		return &providerError{msg: label + " refused to send from this address. Its organization has to allow sending from aliases, " +
			"or the address is not one of the account's (ErrorSendAsDenied).", status: status, permanent: true}
	}
	return &providerError{msg: msg, status: status, permanent: status >= 400 && status < 500, code: shown}
}

// isNotFound reports a provider 404.
func isNotFound(err error) bool {
	var pe *providerError
	return errors.As(err, &pe) && pe.notFound
}

// isPassing reports a provider that is busy or unreachable: the calls after it would fail
// alike, and a later pass tries again.
func isPassing(err error) bool {
	var pe *providerError
	return errors.Is(err, errProviderUnavailable) || errors.As(err, &pe) && pe.busy
}

// isRefusing reports a provider that refuses every call for now: a rate limit, or no answer
// at all. A 5xx can be one request's own, so it is not.
func isRefusing(err error) bool {
	var pe *providerError
	return errors.Is(err, errProviderUnavailable) || errors.As(err, &pe) && pe.limited
}

// isPermanent reports a failure that retrying will not fix.
func isPermanent(err error) bool {
	var pe *providerError
	var ie *imapError
	switch {
	case errors.Is(err, errReconnect):
		return true
	case errors.As(err, &pe):
		return pe.permanent
	case errors.As(err, &ie):
		return ie.permanent || ie.auth
	}
	return false
}
