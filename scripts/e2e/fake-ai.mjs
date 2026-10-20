// A tiny OpenAI-compatible server for end-to-end runs: /v1/chat/completions
// (plain, json_schema, SSE streaming and tool calls) and /v1/embeddings. Answers are
// deterministic and plausible, so every AI feature can be exercised without a
// real provider. Usage: node fake-ai.mjs [port]  (default 9900)

import http from "node:http";

const port = Number(process.argv[2] || process.env.FAKE_AI_PORT || 9900);
const DIM = 1536;

function embed(text) {
  // Bag of hashed words, normalised: similar texts get similar vectors.
  const v = new Array(DIM).fill(0);
  for (const w of String(text).toLowerCase().match(/[a-z0-9]{3,}/g) ?? []) {
    let h = 2166136261;
    for (const c of w) h = Math.imul(h ^ c.charCodeAt(0), 16777619) >>> 0;
    v[h % DIM] += 1;
  }
  const n = Math.sqrt(v.reduce((a, b) => a + b * b, 0)) || 1;
  return v.map((x) => x / n);
}

function lastUser(messages) {
  const u = [...messages].reverse().find((m) => m.role === "user");
  return u?.content ?? "";
}

function jsonFor(schema, messages) {
  const user = lastUser(messages);
  switch (schema) {
    case "ticket_summary":
      return {
        summary: "The customer cannot sign in after resetting their password and wants help.",
        key_points: ["Password reset email arrived", "Login still fails", "Customer is waiting on a fix"],
        sentiment: "negative",
      };
    case "ticket_triage": {
      const tags = (user.match(/<available_tags>([\s\S]*?)<\/available_tags>/)?.[1] ?? "")
        .split("\n").map((s) => s.trim()).filter(Boolean).slice(0, 1);
      return {
        tags, suggested_tags: ["login"], priority: "high", severity: "sev3", team: "none", sentiment: "frustrated",
        language: /\bhola\b/i.test(user) ? "es" : "en", category: "account", summary: "Customer cannot sign in after a password reset.",
      };
    }
    case "translation": {
      const text = user.match(/<text[^>]*>([\s\S]*?)<\/text>/)?.[1] ?? "Hola";
      return { translation: `[es] ${text.trim()}`, source_language: "en" };
    }
    case "kb_article":
      return {
        title: "How to sign in after a password reset",
        body_html: "<h2>Steps</h2><ol><li>Open the reset link.</li><li>Choose a new password.</li><li>Sign in again.</li></ol>",
        excerpt: "What to do when signing in fails after a reset.",
      };
    case "widget_answer":
      return {
        answerable: true,
        answer: "You can reset your password from the sign-in page. Follow the link in the email and choose a new password.",
        source_ids: [1],
        wants_human: false,
      };
    case "decisions": {
      // The LLM decision adapter (DECISIONS_PROVIDER=llm): answer every question id.
      const qs = JSON.parse(user.match(/<questions>([\s\S]*?)<\/questions>/)?.[1] ?? "[]");
      return Object.fromEntries(qs.map((q) => {
        if (q.type === "choice") {
          const keys = Object.keys(q.criteria ?? {});
          return [q.id, { choice: keys.find((k) => k !== "(none)") ?? keys[0], probability: 0.8 }];
        }
        if (q.type === "score") return [q.id, { level: 1, probability: 0.7 }];
        return [q.id, { probability: 0.75 }];
      }));
    }
    default:
      return {};
  }
}

function textFor(messages) {
  const sys = messages.find((m) => m.role === "system")?.content ?? "";
  if (sys.includes("You edit support replies")) return "<p>Thanks so much for reaching out! Here is a friendlier version of your reply.</p>";
  if (sys.includes("You are the copilot")) return "The customer **cannot sign in** after resetting the password. Suggest clearing cookies.";
  return "Hi there,\n\nThanks for reaching out. I am sorry about the trouble signing in. **Please try resetting your password** from the sign-in page, then let me know how it goes.\n\nBest regards";
}

function chunks(s) {
  const out = [];
  for (let i = 0; i < s.length; i += 12) out.push(s.slice(i, i + 12));
  return out;
}

// --- Tool calls (the assistant) ---------------------------------------------------
// A request with `tools` gets a scripted agent: the user's words pick a tool call, and
// tool results turn into a short markdown answer that cites what the tools returned.

function textOf(m) {
  if (typeof m?.content === "string") return m.content;
  if (Array.isArray(m?.content)) return m.content.map((p) => p.text ?? "").join("");
  return "";
}

function daysAgo(n) {
  const d = new Date(Date.now() - n * 86400000);
  return d.toISOString().slice(0, 10);
}

function planCall(user, tools) {
  const has = (n) => tools.includes(n);
  const said = user.replace(/<page_context>[\s\S]*?<\/page_context>/, "").toLowerCase();
  const open = user.match(/open ticket: #(\d+)/)?.[1];
  const num = said.match(/#(\d+)/)?.[1] ?? open;
  if (/\blabel\b|\btag\b/.test(said) && has("bulk_update_tickets")) {
    const label = said.match(/label (?:all )?(\w+)/)?.[1] ?? "billing";
    return { name: "bulk_update_tickets", args: { filter: { query: label === "all" ? "billing" : label, created_after: daysAgo(7) }, changes: { add_labels: [label === "all" ? "billing" : label] } } };
  }
  if (/\bassign\b|take this/.test(said) && num && has("update_ticket")) {
    return { name: "update_ticket", args: { ticket: `#${num}`, assignee: "me", priority: "high" } };
  }
  if (/\breply\b|\brespond\b|\bdraft\b/.test(said) && num && has("draft_reply")) {
    return { name: "draft_reply", args: { ticket: `#${num}`, body: "Hi there,\n\nThanks for your patience. I have looked into this and **a fix is on its way**. I will follow up as soon as it is live.\n\nThanks again", status: "pending" } };
  }
  if (/\bnote\b/.test(said) && num && has("add_note")) {
    return { name: "add_note", args: { ticket: `#${num}`, body: "Checked with billing: the duplicate charge is refunded within 3 to 5 days." } };
  }
  if (/who should/.test(said)) return { name: "list_team", args: {} };
  if (/summar|this ticket|what.*about/.test(said) && num) return { name: "get_ticket", args: { ticket: `#${num}` } };
  if (/sla|breach|urgent/.test(said)) return { name: "search_tickets", args: { status: ["open", "pending"], sla: /breach/.test(said) ? "breached" : undefined, priority: /urgent/.test(said) ? ["urgent", "high"] : undefined, limit: 8 } };
  if (/unassigned/.test(said)) return { name: "search_tickets", args: { assignee: "none", status: ["open"], limit: 8 } };
  if (/report|stat|how are we|volume|csat/.test(said)) return { name: "get_report", args: {} };
  if (/article|knowledge|kb/.test(said)) return { name: "search_kb", args: { query: said.replace(/[^a-z ]/g, "").split(" ").filter((w) => w.length > 3).slice(-2).join(" ") || "password" } };
  if (/customer|contact/.test(said)) return { name: "search_contacts", args: { query: said.match(/(?:customer|contact) (\w+)/)?.[1] ?? "a" } };
  if (/hello|hi\b|hey|thanks/.test(said)) return null;
  return { name: "search_tickets", args: { query: said.replace(/[^a-z0-9 ]/g, " ").split(/\s+/).filter((w) => w.length > 3).slice(0, 2).join(" "), limit: 8 } };
}

function answerFrom(results) {
  const all = results.join("\n");
  if (/declined/.test(all)) return "No problem, I left it as it was. Want me to try something else?";
  if (/not made/.test(all)) return "Got it, I dropped that change.";
  if (/failed:/.test(all)) return `That did not go through: ${all.match(/failed: ([^\n<]*)/)?.[1] ?? "an error"}.`;
  if (/^Error:|Not proposed:/m.test(all)) return `I could not do that: ${all.match(/(?:Error|Not proposed): ([^\n<]*)/)?.[1] ?? "an error"}`;
  const done = all.match(/(Updated[^\n<]*|Added a note[^\n<]*|Sent the reply[^\n<]*|Created[^\n<]*)/);
  if (done) return `Done. ${done[1].split(";")[0].replace(/^Updated: /, "Updated ").replace(/ \[[^\]]*\]/, "")}.`;
  const rows = [...all.matchAll(/#(\d+) \[([^\]]+)\] "([^"]*)"(?:; customer: ([^;<]+))?/g)].slice(0, 5);
  const team = [...all.matchAll(/^(.+?) <[^>]+>(?: \(the user\))?, (\w+): (\d+) open/gm)];
  if (team.length) {
    const least = [...team].sort((a, b) => Number(a[3]) - Number(b[3]))[0];
    return `**${least[1]}** has the lightest queue right now (${least[3]} open), so they are a good fit.\n\n${team.slice(0, 4).map((t) => `- ${t[1]}: ${t[3]} open`).join("\n")}`;
  }
  if (/--- (message|internal note)/.test(all) && rows.length) {
    const r = rows[0];
    return `**#${r[1]} ${r[3]}** is ${r[2].split(",")[0]} with ${r[2].split(",")[1]?.trim()} priority${r[4] ? `, from ${r[4].trim()}` : ""}.\n\n- The customer is waiting on a clear next step.\n- Nothing in the thread is blocked on them.\n\nWant me to draft a reply?`;
  }
  if (rows.length) {
    const n = all.match(/(\d+) tickets matched/)?.[1] ?? rows.length;
    return `I found **${n}** matching tickets. The top ones:\n\n${rows.map((r) => `- #${r[1]} ${r[3]} (${r[2].split(",").slice(0, 2).map((x) => x.trim()).join(", ")})`).join("\n")}`;
  }
  if (/overview:/.test(all)) {
    const created = all.match(/"created":(\d+)/)?.[1] ?? "0";
    const solved = all.match(/"solved":(\d+)/)?.[1] ?? "0";
    return `In the last 30 days you received **${created}** tickets and solved **${solved}**.`;
  }
  if (/No (contacts|articles) matched/.test(all)) return "I did not find anything for that.";
  return "Here is what I found. Anything you want me to do with it?";
}

// --- The widget agent (contracts/agent.md) ------------------------------------------
// Offered handoff_to_human, it answers from the <knowledge> passages it was given or
// found with search_knowledge, citing the first, and hands off when asked to.

const KB_ANSWER = "You can reset your password from the sign-in page. Follow the link in the email and choose a new password.";

function widgetTurn(last) {
  const text = textOf(last);
  const cite = text.match(/<passage n="(\d+)"/)?.[1];
  if (last?.role === "tool") {
    return { text: cite ? `${KB_ANSWER} [${cite}]` : "I could not find that in our help articles. Want me to connect you with someone from the team?" };
  }
  if (/call handoff_to_human/.test(text)) {
    return { text: "A person from the team will reply here.", call: { id: `call_${Math.random().toString(36).slice(2, 10)}`, name: "handoff_to_human", args: { reason: "needs a person" } } };
  }
  if (cite) return { text: `${KB_ANSWER} [${cite}]` };
  const asked = text.match(/<ticket_thread>([\s\S]*?)<\/ticket_thread>/)?.[1] ?? text;
  const query = asked.toLowerCase().replace(/<[^>]*>/g, " ").replace(/[^a-z ]/g, " ").split(/\s+/).filter((w) => w.length > 3).slice(-4).join(" ") || "password";
  return { text: "", call: { id: `call_${Math.random().toString(36).slice(2, 10)}`, name: "search_knowledge", args: { query } } };
}

function agentTurn(j) {
  const msgs = j.messages ?? [];
  const tools = (j.tools ?? []).map((t) => t.function?.name);
  const last = msgs[msgs.length - 1];
  if (tools.includes("handoff_to_human")) return widgetTurn(last);
  if (last?.role === "tool") {
    const results = [];
    for (let i = msgs.length - 1; i >= 0 && msgs[i].role === "tool"; i--) results.unshift(textOf(msgs[i]));
    return { text: answerFrom(results) };
  }
  const call = planCall(textOf(last), tools);
  if (!call) return { text: "Hi! I am Ollie. Ask me about your queue, a ticket or your numbers." };
  const lead = { get_ticket: "Let me read that ticket.", list_team: "Checking the team's workload.", bulk_update_tickets: "I will prepare that change.", update_ticket: "Preparing the change.", draft_reply: "Here is a draft.", add_note: "Adding a note." }[call.name] ?? "Let me look.";
  return { text: lead, call: { id: `call_${Math.random().toString(36).slice(2, 10)}`, ...call } };
}

async function sendAgent(res, j) {
  const turn = agentTurn(j);
  if (!j.stream) {
    res.writeHead(200, { "Content-Type": "application/json" });
    const message = { role: "assistant", content: turn.text };
    if (turn.call) message.tool_calls = [{ id: turn.call.id, type: "function", function: { name: turn.call.name, arguments: JSON.stringify(turn.call.args) } }];
    res.end(JSON.stringify({ model: j.model, choices: [{ index: 0, message, finish_reason: turn.call ? "tool_calls" : "stop" }], usage: { prompt_tokens: 300, completion_tokens: 60 } }));
    return;
  }
  res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" });
  for (const c of chunks(turn.text)) {
    res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: { content: c } }] })}\n\n`);
    await new Promise((r) => setTimeout(r, 25));
  }
  if (turn.call) {
    const args = JSON.stringify(turn.call.args);
    res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: { tool_calls: [{ index: 0, id: turn.call.id, type: "function", function: { name: turn.call.name, arguments: "" } }] } }] })}\n\n`);
    for (let i = 0; i < args.length; i += 20) {
      res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: { tool_calls: [{ index: 0, function: { arguments: args.slice(i, i + 20) } }] } }] })}\n\n`);
    }
  }
  res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: {}, finish_reason: turn.call ? "tool_calls" : "stop" }] })}\n\n`);
  res.write(`data: ${JSON.stringify({ model: j.model, choices: [], usage: { prompt_tokens: 300, completion_tokens: 60 } })}\n\n`);
  res.end("data: [DONE]\n\n");
}

const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", async () => {
    let j = {};
    try { j = body ? JSON.parse(body) : {}; } catch { /* ignore */ }
    if (req.url?.endsWith("/embeddings")) {
      const input = Array.isArray(j.input) ? j.input : [j.input];
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        object: "list", model: j.model,
        data: input.map((t, index) => ({ object: "embedding", index, embedding: embed(t) })),
        usage: { prompt_tokens: 10, total_tokens: 10 },
      }));
      return;
    }
    if (!req.url?.endsWith("/chat/completions")) {
      res.writeHead(404).end();
      return;
    }
    if (Array.isArray(j.tools) && j.tools.length) {
      await sendAgent(res, j);
      return;
    }
    const messages = j.messages ?? [];
    const schema = j.response_format?.json_schema?.name;
    const content = j.response_format ? JSON.stringify(jsonFor(schema, messages)) : textFor(messages);
    if (j.stream) {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" });
      for (const c of chunks(content)) {
        res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: { content: c } }] })}\n\n`);
        await new Promise((r) => setTimeout(r, 30));
      }
      res.write(`data: ${JSON.stringify({ model: j.model, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] })}\n\n`);
      res.write(`data: ${JSON.stringify({ model: j.model, choices: [], usage: { prompt_tokens: 100, completion_tokens: 40 } })}\n\n`);
      res.end("data: [DONE]\n\n");
      return;
    }
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      model: j.model,
      choices: [{ index: 0, message: { role: "assistant", content }, finish_reason: "stop" }],
      usage: { prompt_tokens: 100, completion_tokens: 40 },
    }));
  });
});

server.listen(port, "127.0.0.1", () => console.log(`fake AI on http://127.0.0.1:${port}/v1`));
