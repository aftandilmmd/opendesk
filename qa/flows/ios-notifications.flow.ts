import { test } from "../lib/ios.ts";

test.use({ start: "/inbox/unassigned" });

// Demo mode never asks for notification permission, so pushes cannot be shown here: their text
// is checked by internal/push's TestIPhoneHasPushStrings against Localizable.xcstrings.
test("the unassigned queue a new ticket push opens on the iPhone", async ({ ios }) => {
  await ios.dwell();
  await ios.shot("unassigned", { caption: "Unassigned, where a new ticket push leads, with #1071 from Elena Rossi" });
});
