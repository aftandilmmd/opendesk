package plan

import "testing"

// TestOverrides: an override replaces the plan's limit, 0 lifts it, nil keeps it.
func TestOverrides(t *testing.T) {
	five, zero, ai := 5, 0, Micro(25_000_000)
	e := Entitlements{Plan: Free, MaxMailboxes: FreeMaxMailboxes, MaxMembers: FreeMaxMembers, MonthlyUSD: FreeMonthlyUSD}
	Overrides{MaxMailboxes: &five, MaxMembers: &zero, MonthlyUSD: &ai}.apply(&e)
	if e.MaxMailboxes != 5 || e.MaxMembers != 0 || e.MonthlyUSD != ai {
		t.Fatalf("applied: %+v", e)
	}
	e = Entitlements{Plan: Pro, MonthlyUSD: ProUSDPerSeat}
	Overrides{}.apply(&e)
	if e.MaxMailboxes != 0 || e.MonthlyUSD != ProUSDPerSeat {
		t.Fatalf("no overrides: %+v", e)
	}
}

// TestImportLimits: a paid plan's import file limits grow with its seats; self-hosted has none.
func TestImportLimits(t *testing.T) {
	var e Entitlements
	e.paidImports(3)
	if e.ImportFilesPerMessage != PaidImportFilesPerMessage || e.ImportMessageBytes != PaidImportMessageBytes ||
		e.ImportBytes != 3*PaidImportBytesPerSeat {
		t.Fatalf("paid: %+v", e)
	}
	e.paidImports(0)
	if e.ImportBytes != PaidImportBytesPerSeat {
		t.Fatalf("no seats: %+v", e)
	}
	var none *Service
	self, err := none.Entitlements(t.Context(), nil, [16]byte{})
	if err != nil || self.ImportFilesPerMessage != 0 || self.ImportMessageBytes != 0 || self.ImportBytes != 0 {
		t.Fatalf("self-hosted: %+v %v", self, err)
	}
}
