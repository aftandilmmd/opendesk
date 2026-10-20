package hd

import (
	"encoding/json"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/useopendesk/opendesk/internal/httpx"
)

// Weekdays in API order.
var Weekdays = []string{"mon", "tue", "wed", "thu", "fri", "sat", "sun"}

// TimeRange is an opening range of one day, "HH:MM" 24h; End may be "24:00".
type TimeRange struct {
	Start string `json:"start" pattern:"^([01][0-9]|2[0-4]):[0-5][0-9]$"`
	End   string `json:"end" pattern:"^([01][0-9]|2[0-4]):[0-5][0-9]$"`
}

// Holiday is a closed day.
type Holiday struct {
	Date string `json:"date" format:"date" doc:"YYYY-MM-DD"`
	Name string `json:"name" maxLength:"100"`
}

// BusinessHours lives in settings.business_hours.
type BusinessHours struct {
	Enabled  bool                   `json:"enabled"`
	Schedule map[string][]TimeRange `json:"schedule"`
	Holidays []Holiday              `json:"holidays"`
}

// DefaultBusinessHours is Monday to Friday, 9 to 17, off.
func DefaultBusinessHours() BusinessHours {
	day := []TimeRange{{"09:00", "17:00"}}
	return BusinessHours{Schedule: map[string][]TimeRange{"mon": day, "tue": day, "wed": day, "thu": day, "fri": day,
		"sat": {}, "sun": {}}, Holidays: []Holiday{}}
}

// Hours returns the workspace's business hours with defaults.
func (s Settings) Hours() BusinessHours {
	b := DefaultBusinessHours()
	if len(s.BusinessHoursRaw) > 0 {
		var v BusinessHours
		if json.Unmarshal(s.BusinessHoursRaw, &v) == nil {
			b.Enabled = v.Enabled
			if v.Schedule != nil {
				b.Schedule = v.Schedule
			}
			if v.Holidays != nil {
				b.Holidays = v.Holidays
			}
		}
	}
	for _, d := range Weekdays {
		if b.Schedule[d] == nil {
			b.Schedule[d] = []TimeRange{}
		}
	}
	return b
}

// minutesOf parses "HH:MM" into minutes since midnight (0..1440).
func minutesOf(s string) (int, bool) {
	h, m, ok := strings.Cut(s, ":")
	if !ok || len(h) != 2 || len(m) != 2 {
		return 0, false
	}
	hh, err1 := strconv.Atoi(h)
	mm, err2 := strconv.Atoi(m)
	if err1 != nil || err2 != nil || hh < 0 || mm < 0 || mm > 59 || hh > 24 || (hh == 24 && mm != 0) {
		return 0, false
	}
	return hh*60 + mm, true
}

// ValidateBusinessHours normalises and checks a full BusinessHours value.
func ValidateBusinessHours(b BusinessHours) (BusinessHours, error) {
	out := BusinessHours{Enabled: b.Enabled, Schedule: map[string][]TimeRange{}, Holidays: []Holiday{}}
	for k := range b.Schedule {
		if !slices.Contains(Weekdays, k) {
			return out, httpx.Validation("schedule keys must be mon, tue, wed, thu, fri, sat or sun.")
		}
	}
	for _, d := range Weekdays {
		ranges := b.Schedule[d]
		if len(ranges) > 3 {
			return out, httpx.Validation("At most 3 opening ranges per day.")
		}
		type span struct{ s, e int }
		var spans []span
		for _, r := range ranges {
			s, ok1 := minutesOf(r.Start)
			e, ok2 := minutesOf(r.End)
			if !ok1 || !ok2 || s%15 != 0 || e%15 != 0 {
				return out, httpx.Validation("Opening times are HH:MM on the quarter hour, like 09:00 or 17:30.")
			}
			if s >= e {
				return out, httpx.Validation(fmt.Sprintf("On %s, each range must end after it starts.", d))
			}
			spans = append(spans, span{s, e})
		}
		sort.Slice(spans, func(i, j int) bool { return spans[i].s < spans[j].s })
		for i := 1; i < len(spans); i++ {
			if spans[i].s < spans[i-1].e {
				return out, httpx.Validation(fmt.Sprintf("On %s, opening ranges overlap.", d))
			}
		}
		list := make([]TimeRange, 0, len(spans))
		for _, sp := range spans {
			list = append(list, TimeRange{fmt.Sprintf("%02d:%02d", sp.s/60, sp.s%60), fmt.Sprintf("%02d:%02d", sp.e/60, sp.e%60)})
		}
		out.Schedule[d] = list
	}
	if len(b.Holidays) > 100 {
		return out, httpx.Validation("At most 100 holidays.")
	}
	seen := map[string]bool{}
	for _, h := range b.Holidays {
		if _, err := time.Parse(time.DateOnly, h.Date); err != nil {
			return out, httpx.Validation("Holiday dates are YYYY-MM-DD.")
		}
		name := strings.Join(strings.Fields(h.Name), " ")
		if utf8.RuneCountInString(name) > 100 || strings.ContainsAny(name, "<>`") || strings.IndexFunc(name, unicode.IsControl) >= 0 {
			return out, httpx.Validation("Holiday names are up to 100 characters, without markup.")
		}
		if seen[h.Date] {
			continue
		}
		seen[h.Date] = true
		out.Holidays = append(out.Holidays, Holiday{Date: h.Date, Name: name})
	}
	sort.Slice(out.Holidays, func(i, j int) bool { return out.Holidays[i].Date < out.Holidays[j].Date })
	return out, nil
}

// open reports whether any minute of the week is open.
func (b BusinessHours) open() bool {
	for _, d := range Weekdays {
		if len(b.Schedule[d]) > 0 {
			return true
		}
	}
	return false
}

// maxScanDays bounds AddBusinessMinutes; beyond it the deadline falls back to wall time.
const maxScanDays = 3660

// AddBusinessMinutes returns the time mins open minutes after start, counting only
// the schedule's ranges in loc and skipping holidays. With business hours off or no
// open time it adds wall-clock minutes.
func (b BusinessHours) AddBusinessMinutes(start time.Time, mins int, loc *time.Location) time.Time {
	if !b.Enabled || !b.open() || mins <= 0 {
		return start.Add(time.Duration(mins) * time.Minute)
	}
	if loc == nil {
		loc = time.UTC
	}
	holidays := map[string]bool{}
	for _, h := range b.Holidays {
		holidays[h.Date] = true
	}
	left := time.Duration(mins) * time.Minute
	cur := start.In(loc)
	y, m, d := cur.Date()
	for i := 0; i < maxScanDays; i++ {
		day := time.Date(y, m, d+i, 0, 0, 0, 0, loc)
		if holidays[day.Format(time.DateOnly)] {
			continue
		}
		key := Weekdays[(int(day.Weekday())+6)%7]
		for _, r := range b.Schedule[key] {
			s, _ := minutesOf(r.Start)
			e, _ := minutesOf(r.End)
			ws := time.Date(day.Year(), day.Month(), day.Day(), s/60, s%60, 0, 0, loc)
			we := time.Date(day.Year(), day.Month(), day.Day(), e/60, e%60, 0, 0, loc)
			if !we.After(cur) {
				continue
			}
			if ws.Before(cur) {
				ws = cur
			}
			if span := we.Sub(ws); span >= left {
				return ws.Add(left).UTC()
			} else {
				left -= span
			}
		}
	}
	return start.Add(time.Duration(mins) * time.Minute)
}

// OpenAt reports whether the business hours are open at now. A schedule with no open
// time is never open. Callers check Enabled first: hours that are off read as open.
func OpenAt(b BusinessHours, loc *time.Location, now time.Time) bool {
	return b.open() && b.AddBusinessMinutes(now, 1, loc).Equal(now.Add(time.Minute))
}
