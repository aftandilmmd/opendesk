import { test } from "../lib/ios.ts";

test.use({ start: "/inbox/mine" });

test("the iPhone inbox, then the unassigned queue", async ({ ios }) => {
  await ios.shot("mine", { caption: "Mine, with SLA and priority pills" });
  await ios.open("/inbox/unassigned");
  await ios.dwell();
  await ios.shot("unassigned", { caption: "Unassigned, with live chats waiting" });
});
