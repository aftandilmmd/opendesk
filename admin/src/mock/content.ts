// Written content for the admin mock's seed: the operators, the customer
// workspaces (Margin and its people are the app mock's, web/src/mock/content.ts),
// and the names the rest of the instance is made of.

/** The people who run the instance. Ava is the signed-in admin. */
export const OPERATORS = [
  { key: "ava", name: "Ava Reyes", email: "ava@opendesk.example", role: "super", totp: true, days: 420 },
  { key: "noah", name: "Noah Park", email: "noah@opendesk.example", role: "super", totp: true, days: 300 },
  { key: "kofi", name: "Kofi Mensah", email: "kofi@opendesk.example", role: "support", totp: true, days: 210 },
  { key: "hana", name: "Hana Sato", email: "hana@opendesk.example", role: "support", totp: true, days: 95 },
  { key: "elena", name: "Elena Rossi", email: "elena@opendesk.example", role: "viewer", totp: true, days: 160 },
  // Not admins: Marcus was one until recently; Ben has no two-factor authentication yet.
  { key: "marcus", name: "Marcus Lindqvist", email: "marcus@opendesk.example", role: null, totp: true, days: 380 },
  { key: "ben", name: "Ben Hartmann", email: "ben@opendesk.example", role: null, totp: false, days: 20 },
] as const;

export type OperatorKey = (typeof OPERATORS)[number]["key"];

/** Margin's team, as in the app's mock. */
export const MARGIN_TEAM = [
  { name: "Maya Chen", email: "maya@margin.app", role: "owner" },
  { name: "Jonas Weber", email: "jonas@margin.app", role: "admin" },
  { name: "Priya Raman", email: "priya@margin.app", role: "agent" },
  { name: "Sam Okafor", email: "sam@margin.app", role: "agent" },
  { name: "Lea Martin", email: "lea@margin.app", role: "agent" },
  { name: "Theo Brandt", email: "theo@margin.app", role: "viewer" },
] as const;

export const FIRST = [
  "Dana", "Marco", "Elif", "Tomás", "Aisha", "Benoit", "Chloé", "Daniel", "Freya", "Gabriel",
  "Hannah", "Isaac", "Julia", "Kwame", "Laura", "Mateo", "Nina", "Oliver", "Paula", "Quentin",
  "Rosa", "Stefan", "Tara", "Umar", "Vera", "Will", "Ximena", "Yusuf", "Zoe", "Anders",
  "Bianca", "Carlos", "Delia", "Emil", "Farah", "Greta", "Hugo", "Ines", "Jakob", "Keiko",
  "Liam", "Mira", "Nadia", "Olga", "Pablo", "Ruth", "Simon", "Tess", "Viktor", "Wen",
] as const;

export const LAST = [
  "Whitfield", "Bianchi", "García", "Bello", "Dubois", "Kim", "Nilsen", "Moreau", "Levy", "Novak",
  "Fischer", "Silva", "Petrova", "Grant", "Costa", "Laurent", "Ortega", "Bauer", "Singh", "Haddad",
  "Ivanova", "Turner", "Demir", "Holm", "Conti", "Mendes", "Fox", "Berg", "Rahman", "Vogel",
  "Martins", "Ferreira", "Klein", "Tanaka", "Murphy", "Shah", "Andersson", "Kowalski", "Navarro", "Okoro",
] as const;

type Mailbox = { name: string; local: string; inbound: string; outbound: string; error?: string; disabled?: boolean };

export type NamedWorkspace = {
  name: string;
  domain: string;
  /** Members besides the owner. */
  team: number;
  days: number;
  sub: { plan: "free" | "pro" | "collab"; status: string; interval?: "month" | "year"; cancel?: boolean; trialDays?: number };
  owner?: string;
  mailboxes: Mailbox[];
  collab?: { access: "offered" | "complimentary"; days?: number; note: string; accounts?: number };
  limits?: { max_mailboxes?: number | null; max_members?: number | null; monthly_ai_usd?: number | null };
  ai: number;
  purchased?: number;
  suspended?: { days: number; reason: string; by: OperatorKey };
  tickets: number;
  logo?: boolean;
};

const gmail = (name: string, local: string, extra: Partial<Mailbox> = {}): Mailbox => ({ name, local, inbound: "gmail", outbound: "gmail", ...extra });
const ms = (name: string, local: string, extra: Partial<Mailbox> = {}): Mailbox => ({ name, local, inbound: "microsoft", outbound: "microsoft", ...extra });
const forward = (name: string, local: string, extra: Partial<Mailbox> = {}): Mailbox => ({ name, local, inbound: "forward", outbound: "smtp", ...extra });

/** The customers the flows talk about, with the states the panel shows. */
export const NAMED: NamedWorkspace[] = [
  {
    name: "Margin",
    domain: "margin.app",
    team: 0,
    days: 380,
    sub: { plan: "pro", status: "active" },
    mailboxes: [gmail("Support", "support"), ms("Billing", "billing"), { name: "Partners", local: "partners", inbound: "imap", outbound: "smtp" }, gmail("Legal", "legal")],
    ai: 31.42,
    tickets: 1840,
    logo: true,
  },
  {
    name: "Northwind Traders",
    domain: "northwind.com",
    team: 23,
    days: 340,
    sub: { plan: "collab", status: "active", interval: "year" },
    mailboxes: [ms("Customer care", "care"), ms("Wholesale", "wholesale"), ms("Returns", "returns")],
    collab: { access: "offered", note: "Moved from Pro after the March pilot.", accounts: 18 },
    ai: 212.7,
    tickets: 9620,
    logo: true,
  },
  {
    name: "Halcyon Studio",
    domain: "halcyon.studio",
    team: 6,
    days: 290,
    owner: "Dana Whitfield",
    sub: { plan: "pro", status: "past_due" },
    mailboxes: [gmail("Hello", "hello", { error: "oauth2: \"invalid_grant\" \"Token has been expired or revoked.\"" }), gmail("Projects", "projects")],
    ai: 18.05,
    tickets: 2210,
  },
  {
    name: "Brightline Logistics",
    domain: "brightline.io",
    team: 8,
    days: 260,
    sub: { plan: "pro", status: "active", interval: "year", cancel: true },
    mailboxes: [forward("Dispatch", "dispatch"), forward("Claims", "claims")],
    ai: 9.8,
    tickets: 3105,
  },
  {
    name: "Oakridge Health",
    domain: "oakridgehealth.org",
    team: 11,
    days: 9,
    sub: { plan: "pro", status: "trialing", trialDays: 5 },
    mailboxes: [ms("Patient support", "support")],
    ai: 4.12,
    tickets: 96,
  },
  {
    name: "Paperplane",
    domain: "paperplane.co",
    team: 2,
    days: 150,
    sub: { plan: "free", status: "none" },
    mailboxes: [gmail("Support", "support")],
    limits: { max_members: 5 },
    ai: 0.41,
    tickets: 388,
    logo: true,
  },
  {
    name: "Vantage Legal",
    domain: "vantagelegal.com",
    team: 5,
    days: 210,
    sub: { plan: "pro", status: "active" },
    mailboxes: [ms("Client intake", "intake")],
    collab: { access: "offered", note: "Asked on the sales call for shared partner inboxes." },
    ai: 22.6,
    tickets: 1450,
  },
  {
    name: "Copperleaf",
    domain: "copperleaf.dev",
    team: 4,
    days: 120,
    sub: { plan: "free", status: "none" },
    mailboxes: [forward("Developers", "dev"), gmail("Founders", "founders")],
    collab: { access: "complimentary", days: 45, note: "Design partner for Collab, until the September review.", accounts: 6 },
    ai: 12.33,
    tickets: 640,
    logo: true,
  },
  {
    name: "Meridian Schools",
    domain: "meridian.edu",
    team: 9,
    days: 230,
    sub: { plan: "pro", status: "active", interval: "year" },
    mailboxes: [gmail("IT help", "it"), gmail("Admissions", "admissions"), gmail("Parents", "parents", { disabled: true })],
    limits: { monthly_ai_usd: 150 },
    ai: 61.9,
    tickets: 4020,
  },
  {
    name: "Fjord Analytics",
    domain: "fjord.ai",
    team: 7,
    days: 180,
    sub: { plan: "pro", status: "active" },
    mailboxes: [gmail("Support", "support")],
    ai: 80,
    purchased: 25,
    tickets: 2290,
  },
  {
    name: "Tidewater Media",
    domain: "tidewater.fm",
    team: 3,
    days: 60,
    sub: { plan: "free", status: "none" },
    mailboxes: [gmail("Listeners", "listeners")],
    collab: { access: "offered", note: "Podcast network, wants each host's own inbox." },
    ai: 0.5,
    tickets: 210,
  },
  {
    name: "Kestrel Robotics",
    domain: "kestrel.tech",
    team: 2,
    days: 200,
    sub: { plan: "pro", status: "canceled" },
    mailboxes: [forward("Field support", "field")],
    ai: 0.12,
    tickets: 530,
  },
  {
    name: "Solstice Bakery",
    domain: "solsticebakery.com",
    team: 0,
    days: 22,
    sub: { plan: "free", status: "none" },
    mailboxes: [gmail("Orders", "orders")],
    ai: 0.08,
    tickets: 41,
  },
  {
    name: "Quick Gift Rewards",
    domain: "quickgiftrewards.com",
    team: 0,
    days: 11,
    owner: "Victor Hale",
    sub: { plan: "free", status: "none" },
    mailboxes: [forward("Rewards", "rewards")],
    suspended: { days: 9, reason: "Phishing: replies offered gift cards for account details, sent from a lookalike of a bank's domain. Reported by three recipients, abuse ticket 4471.", by: "kofi" },
    ai: 0.5,
    tickets: 12,
  },
  {
    name: "Lumen Dental",
    domain: "lumendental.com",
    team: 1,
    days: 140,
    sub: { plan: "pro", status: "unpaid" },
    mailboxes: [gmail("Front desk", "frontdesk")],
    suspended: { days: 6, reason: "Chargeback on the April invoice. Restore once the payment clears.", by: "noah" },
    ai: 1.2,
    tickets: 760,
  },
];

/** Smaller customers: name, plan and size. Most are free, a few pay. */
export const OTHERS: [name: string, plan: "free" | "pro", team: number][] = [
  ["Bluebird Dental", "pro", 3],
  ["Cinder Coffee Co", "free", 1],
  ["Driftwood Surf School", "free", 0],
  ["Elmstreet Books", "free", 1],
  ["Foxglove Florists", "free", 0],
  ["Granite Peak Outfitters", "pro", 4],
  ["Harbor Light Realty", "pro", 2],
  ["Ironwood Fitness", "free", 0],
  ["Juniper Health", "pro", 5],
  ["Kitebird Travel", "free", 1],
  ["Larkspur Labs", "pro", 3],
  ["Maplewood Vets", "free", 2],
  ["Nimbus Cloudworks", "pro", 6],
  ["Orchard Pay", "pro", 4],
  ["Pinecone Apps", "free", 0],
  ["Quill and Ink", "free", 1],
  ["Riverbend Clinic", "pro", 3],
  ["Saltwind Sailing", "free", 0],
  ["Thistle Tea House", "free", 0],
  ["Upland Energy", "pro", 5],
  ["Velvet Hammer Studio", "free", 1],
  ["Willow Lane Events", "free", 0],
  ["Yellowfin Seafood", "free", 1],
  ["Zephyr Bikes", "pro", 2],
  ["Aurora Robotics", "pro", 4],
  ["Basalt Security", "pro", 3],
  ["Cobalt Freight", "free", 2],
  ["Dovetail Furniture", "free", 0],
  ["Emberline Games", "pro", 6],
  ["Fernhill Farms", "free", 0],
  ["Glasswing Optics", "free", 1],
  ["Hollowtree Records", "free", 0],
  ["Inkwell Press", "pro", 2],
  ["Jetstream Couriers", "free", 3],
  ["Keystone Accounting", "pro", 2],
  ["Lighthouse Learning", "free", 1],
  ["Moss and Stone", "free", 0],
  ["Northstar Rentals", "free", 1],
  ["Oxbow Brewing", "free", 0],
  ["Pebble Payroll", "pro", 3],
  ["Quarry Climbing Gym", "free", 0],
  ["Redwood Dental Group", "pro", 4],
  ["Sable Watches", "free", 0],
  ["Tandem Coworking", "free", 1],
  ["Umbra Lighting", "free", 0],
];

export const USER_AGENTS = [
  { client: "web", ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36" },
  { client: "web", ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:142.0) Gecko/20100101 Firefox/142.0" },
  { client: "web", ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Safari/605.1.15" },
  { client: "web", ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36 Edg/141.0" },
  { client: "desktop", ua: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_6) AppleWebKit/537.36 (KHTML, like Gecko) opendesk/1.9.2 Chrome/140.0 Electron/38.1 Safari/537.36" },
  { client: "ios", ua: "opendesk/1.9 (iPhone; iOS 26.0; Scale/3.00)" },
] as const;

/** AI features and what one call charges, roughly (internal/plan Typical). */
export const AI_FEATURES: [feature: string, perCall: number, share: number][] = [
  ["triage", 0.004, 0.34],
  ["draft_reply", 0.012, 0.24],
  ["summarize", 0.006, 0.14],
  ["assistant", 0.02, 0.12],
  ["answer", 0.009, 0.1],
  ["translate", 0.003, 0.06],
];

/** Samples of job args and the errors they fail with, by kind. */
export const JOB_KINDS: Record<string, { queue: string; max: number; errors: string[] }> = {
  "email.send_reply": { queue: "email", max: 10, errors: ["smtp: 421 4.7.0 Try again later, closing connection. (gsmtp)", "smtp: 452 4.2.2 The email account that you tried to reach is over quota."] },
  "mail.system": { queue: "email", max: 10, errors: ["ses: MessageRejected: Email address is not verified. The following identities failed the check in region EU-WEST-1"] },
  "webhook.deliver": {
    queue: "webhooks",
    max: 12,
    errors: [
      'Post "https://hooks.copperleaf.dev/opendesk": context deadline exceeded (Client.Timeout exceeded while awaiting headers)',
      "webhook: endpoint answered 503 Service Unavailable",
    ],
  },
  "mailbox.sync": { queue: "sync", max: 25, errors: ['oauth2: "invalid_grant" "Token has been expired or revoked."'] },
  "collab.sync": { queue: "sync", max: 25, errors: ["imap: dial tcp 198.51.100.23:993: i/o timeout"] },
  "inbound.process": { queue: "default", max: 5, errors: ["mime: unexpected EOF in multipart body"] },
  "ai.triage": { queue: "ai", max: 5, errors: ["anthropic: 529 overloaded_error: Overloaded"] },
  "ai.embed_article": { queue: "ai", max: 3, errors: ["embeddings: 400 input is too long (8,412 tokens, the model takes 8,192)"] },
  "automation.run": {
    queue: "default",
    max: 5,
    errors: [
      "panic: runtime error: index out of range [3] with length 3\n\ngoroutine 1847 [running]:\ngithub.com/useopendesk/opendesk/internal/helpdesk.(*automationWorker).Work(0xc000a1e0c0, {0x1d2c8a0, 0xc0012b4f30}, 0xc000f3c1e0)\n\t/src/internal/helpdesk/automations.go:212 +0x3a8\ngithub.com/riverqueue/river.(*wrapperWorkUnit[...]).Work(0xc000e6a2d0, {0x1d2c8a0, 0xc0012b4f30})\n\t/go/pkg/mod/github.com/riverqueue/river@v0.24.0/work_unit_wrapper.go:30 +0x5c",
    ],
  },
  "sla.check": { queue: "default", max: 3, errors: [] },
  "billing.sync_seats": { queue: "default", max: 10, errors: ["stripe: rate limited (429), retry after 2s"] },
  "notification.push": { queue: "default", max: 5, errors: ["apns: 410 Unregistered"] },
  "admin.seed_test_workspace": { queue: "default", max: 1, errors: ["sample: insert tickets: context deadline exceeded"] },
  "admin.updates": { queue: "default", max: 3, errors: [] },
  "admin.expire_test_workspaces": { queue: "default", max: 3, errors: [] },
};
