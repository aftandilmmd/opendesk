// Mock mode (VITE_MOCK=1): an in-memory admin API seeded with a believable
// instance, so every page runs without a backend. Only imported behind the
// build-time flag in main.tsx, so production bundles never include it.
//
// Signed in as Ava Reyes, a super admin, by default. ?mock=anon starts signed
// out (sign in with an admin's email, any password and any 6-digit code but
// 000000); ?mock_role=support or viewer signs in as an admin with that role.

import { setTransport } from "@/lib/api/client";
import { adminOf, db, userByEmail } from "./db";
import { registerAdmins } from "./handlers/admins";
import { registerAuth, signIn } from "./handlers/auth";
import { registerInstance } from "./handlers/instance";
import { registerJobs } from "./handlers/jobs";
import { registerTestWorkspaces } from "./handlers/testWorkspaces";
import { registerUsers } from "./handlers/users";
import { registerWorkspaces } from "./handlers/workspaces";
import { dispatch } from "./router";
import { finishAll } from "./samples";
import { seed } from "./seed";

declare global {
  interface Window {
    __odAdminMock?: {
      db: typeof db;
      /** Sign in as the admin with this email, or sign out with null. */
      signInAs: (email: string | null) => void;
      /** Land every running batch of sample data now. */
      finishSamples: () => void;
    };
  }
}

/** Who each ?mock_role signs in as. */
const AS_ROLE: Record<string, string> = {
  super: "ava@opendesk.example",
  support: "kofi@opendesk.example",
  viewer: "elena@opendesk.example",
};

let installed = false;

export function installMock(): void {
  if (installed) return;
  installed = true;

  seed();
  registerAuth();
  registerInstance();
  registerUsers();
  registerWorkspaces();
  registerTestWorkspaces();
  registerJobs();
  registerAdmins();

  const params = new URLSearchParams(typeof location === "undefined" ? "" : location.search);
  if (params.get("mock") !== "anon") signIn(userByEmail(AS_ROLE[params.get("mock_role") ?? ""] ?? AS_ROLE.super)!.id);

  setTransport((input, init) => dispatch(input, init));

  if (typeof window !== "undefined") {
    window.__odAdminMock = {
      db,
      signInAs: (email) => {
        const u = email ? userByEmail(email) : undefined;
        if (u && adminOf(u.id)) signIn(u.id);
        else db.session = null;
      },
      finishSamples: finishAll,
    };
  }
  console.info("[opendesk admin] mock mode: in-memory admin API. window.__odAdminMock has helpers.");
}
