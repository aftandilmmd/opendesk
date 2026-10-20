// Shapes from contracts/api.md (Widget section), contracts/agent.md and
// contracts/realtime.md ("Live events") that the widget uses.

import type { BotLook } from "../../src/lib/botlook";

export type { BotLook };

export type ContactRef = { id: string; email: string | null; name: string; avatar_url: string };

export type WidgetTheme = "auto" | "light" | "dark";
export type WidgetPosition = "right" | "left";
export type WidgetLauncher = "icon" | "label";
export type WidgetRadius = "square" | "soft" | "round";
export type TeamMember = { name: string; avatar_url: string | null };
/** What a message or a live reply carries of its bot (contracts/bots.md "Where a bot shows"). */
export type BotRef = {
  /** null: the default bot before the bots load (the dashboard preview). */
  id: string | null;
  name: string;
  /** A PNG of the look, or the uploaded picture; "" when there is none. */
  avatar_url: string;
  look: BotLook;
};
/** WidgetConfig.bot: the widget's bot, else the default bot. */
export type BotIdentity = BotRef & {
  /** Shown under the name; "" = none. */
  role: string;
  /** Its opening message in a new chat while the agent answers; "" = config.greeting. */
  greeting: string;
};

/** GET /v1/widget/config. Older servers omit the appearance keys; `resolveConfig` fills them in. */
export type WidgetConfig = {
  /** The widget's brand name (the workspace name for the default brand). */
  workspace_name: string;
  /** The widget's colour, else the brand's, else the workspace brand colour. */
  brand_color: string | null;
  greeting: string;
  help_center_url: string | null;
  require_email: boolean;
  /** Workspace default language (BCP 47) for visitors whose browser language isn't supported. */
  locale?: string | null;
  /** The widget's avatar, else the brand logo, else the workspace logo. */
  avatar_url?: string | null;
  launcher_icon_url?: string | null;
  theme?: WidgetTheme;
  position?: WidgetPosition;
  /** 0..200 px from the side. */
  offset_x?: number;
  /** 0..200 px from the bottom. */
  offset_y?: number;
  launcher?: WidgetLauncher;
  /** "" = the translated "Chat with us". */
  launcher_label?: string;
  radius?: WidgetRadius;
  /** The widget's title, else the brand name. */
  title?: string;
  /** "" = the translated reply-time line. */
  subtitle?: string;
  /** At most 4 prompts; a tap starts a conversation with it. */
  suggestions?: string[];
  /** A soft sound for a new reply while the page is hidden. */
  sound?: boolean;
  /** Visitors may send files; older servers omit it: true. */
  attachments?: boolean;
  /** Up to 3 team members (first names); [] when show_team is off. */
  team?: TeamMember[];
  /** The AI agent handles new conversations (contracts/agent.md). */
  ai_answers?: boolean;
  /** Who the AI agent is to visitors: the widget's bot (contracts/bots.md). */
  bot?: BotIdentity;
  /** At most 8. When not empty, asked before the first message; the pick is sent as `topic_id`. */
  topics?: WidgetTopic[];
  /** Within the business hours of the widget's team, else the workspace's; true without hours. */
  open?: boolean;
  /** Shown while closed; "" = the translated default. */
  offline_message?: string;
  /** The widget's brand: its name, and its colour (else the workspace brand colour). */
  brand?: { name: string; color: string | null };
};

export type WidgetTopic = { id: string; label: string };

export type WidgetSession = {
  visitor_token: string;
  contact: ContactRef;
  ws_token: string;
  gateway_url: string;
};

export type Conversation = {
  id: string;
  subject: string;
  status: string;
  last_message_preview: string;
  last_message_at: string;
  /** The conversation was handed from the AI agent to the team (contracts/agent.md). */
  ai_handoff?: boolean;
};

export type Attachment = { id: string; filename: string; content_type: string; size_bytes: number; inline: boolean; url: string };

export type AIActionStatus = "pending" | "confirmed" | "declined" | "expired" | "failed";

/** An action the agent asks the visitor to confirm (contracts/agent.md "Visitor actions"). */
export type AIAction = {
  id: string;
  title: string;
  summary: string;
  status: AIActionStatus;
  /** Display name of the tool. */
  tool: string;
};

export type Rating = "up" | "down";

export type Message = {
  id: string;
  ticket_id: string;
  kind: "reply" | "note";
  direction: "inbound" | "outbound";
  author: {
    type: "contact" | "user" | "system" | "api";
    user: { id: string; name: string; avatar_url: string } | null;
    contact: ContactRef | null;
    /** The bot an AI reply was sent as (contracts/bots.md); older servers omit it. */
    bot?: BotRef | null;
  };
  body_html: string;
  body_text: string;
  attachments: Attachment[];
  created_at: string;
  /** A reply from the AI agent; its cited sources are links at the end of the body. */
  ai?: boolean;
  ai_action?: AIAction | null;
  /** The visitor's own rating of an agent reply (contracts/agent.md "Ratings"). */
  ai_rating?: Rating | null;
};

/** A message as the widget shows it: server messages plus local optimistic ones. */
export type UiMessage = Message & { local?: "pending" | "failed"; localFiles?: File[] };

export type Envelope = { id: string; seq: number; type: string; data: Record<string, unknown>; topics?: string[] };

/** A `"live"` push on the contact topic (contracts/realtime.md "Live events"). */
export type LiveEvent =
  | { type: "ai.reply.started"; data: { reply_id: string; ticket_id: string; bot?: Partial<BotRef> | null } }
  | { type: "ai.reply.delta"; data: { reply_id: string; ticket_id: string; text: string } }
  | { type: "ai.reply.tool"; data: { reply_id: string; ticket_id: string; tool: string; status: "running" | "done" | "error" } }
  | {
      type: "ai.reply.ended";
      data: { reply_id: string; ticket_id: string; message_id: string | null; handoff: boolean; action_id: string | null };
    };

export type SessionIdentity = { user_id?: string; user_hash?: string; email?: string; name?: string };
