// A tiny TypeSafe-compatible server (Jev) for local and end-to-end runs:
// POST /v1/systemone with {state, model, questions} answers every question with a typed
// answer, probabilities and confidence, from keyword heuristics over the state. Answers
// are deterministic, and some land below the default 0.7 threshold so suggestions show up.
// Usage: node fake-typesafe.mjs [port]  (default 9910); point the API at it with
//   TYPESAFE_API_KEY=x TYPESAFE_API_URL=http://127.0.0.1:9910

import http from "node:http";

const port = Number(process.argv[2] || process.env.FAKE_TYPESAFE_PORT || 9910);

const has = (text, words) => words.some((w) => text.includes(w));

// level picks a Score level from how alarming the text is (0..n-1).
function alarm(text) {
  if (has(text, ["outage", "is down", "all users", "data loss", "breach", "everyone", "payments fail", "cannot log in at all"])) return 3;
  if (has(text, ["cannot", "can't", "broken", "error", "failed", "fails", "charged twice", "refund", "blocked", "urgent", "no puedo", "kann nicht"])) return 2;
  if (has(text, ["how do i", "question", "wondering", "feature", "would be nice", "thanks", "thank you"])) return 0;
  return 1;
}

function score(level, n, p, confidence) {
  const probabilities = {};
  for (let i = 0; i < n; i++) probabilities[String(i)] = (1 - p) / (n - 1);
  probabilities[String(level)] = p;
  return { type: "score", score: level, probabilities, confidence };
}

function choice(keys, pick, p, confidence) {
  const probabilities = Object.fromEntries(keys.map((k) => [k, (1 - p) / Math.max(keys.length - 1, 1)]));
  probabilities[pick] = p;
  return { type: "choice", choice: pick, probabilities, confidence };
}

const noul = (p) => ({ type: "noul", noul: p });

function answer(id, q, text) {
  const keys = q.type === "choice" ? Object.keys(q.criteria ?? {}) : [];
  const levels = q.type === "score" ? (q.criteria ?? []).length : 0;
  const a = alarm(text);
  switch (id) {
    case "priority":
      return score(a, levels, 0.88, 0.84);
    case "severity":
      // Mid-impact tickets come back below the default threshold (a suggestion).
      return score(a, levels, a === 2 ? 0.66 : 0.9, a === 2 ? 0.62 : 0.86);
    case "sla_risk":
      return score(Math.min(a, levels - 1), levels, 0.8, 0.72);
    case "sentiment": {
      const s = has(text, ["!!", "third time", "ridiculous", "unacceptable", "angry"]) ? "frustrated"
        : has(text, ["thanks", "thank you", "love"]) ? "positive" : a >= 2 ? "negative" : "neutral";
      return choice(keys, keys.includes(s) ? s : keys[0], 0.82, 0.76);
    }
    case "language": {
      const l = has(text, ["hola", "gracias"]) ? "es" : has(text, ["hallo", "danke", "bitte"]) ? "de" : "en";
      return choice(keys, keys.includes(l) ? l : keys[0], 0.95, 0.94);
    }
    case "category": {
      const c = has(text, ["charge", "invoice", "refund", "billing", "payment"]) ? "billing"
        : has(text, ["password", "sign in", "log in", "login", "account"]) ? "account"
        : has(text, ["error", "bug", "crash", "broken"]) ? "bug" : "question";
      return choice(keys, keys.includes(c) ? c : keys[0], 0.84, 0.8);
    }
    case "spam":
      return noul(has(text, ["click here", "prize", "crypto", "seo services", "viagra"]) ? 0.94 : 0.03);
    case "needs_human":
      return noul(has(text, ["person", "human", "agent", "refund", "cancel", "angry"]) ? 0.88 : 0.25);
  }
  if (q.type === "choice") {
    // Labels, the Type group and teams: an option named in the text, else "(none)".
    const named = keys.find((k) => k !== "(none)" && k.length > 2 && text.includes(k.toLowerCase()));
    if (named) return choice(keys, named, 0.9, 0.87);
    const fallback = keys.includes("(none)") ? "(none)" : keys[0];
    return choice(keys, fallback, 0.6, 0.45);
  }
  if (q.type === "score") return score(Math.min(a, levels - 1), levels, 0.75, 0.66);
  // Nouls: article relevance in the widget, ai_decide conditions.
  const instr = JSON.stringify(q.instructions ?? "").toLowerCase();
  if (instr.includes("churn")) return noul(has(text, ["cancel", "switching", "competitor", "done with"]) ? 0.86 : 0.12);
  if (instr.includes("articles[")) return noul(0.82);
  return noul(a >= 2 ? 0.8 : 0.3);
}

http
  .createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      if (req.method !== "POST" || req.url !== "/v1/systemone") {
        res.writeHead(404).end();
        return;
      }
      if (!/^Bearer \S+/.test(req.headers.authorization ?? "")) {
        res.writeHead(401, { "content-type": "application/json" }).end(JSON.stringify({ detail: "Missing or invalid API key." }));
        return;
      }
      let j;
      try {
        j = JSON.parse(body);
      } catch {
        res.writeHead(422, { "content-type": "application/json" }).end(JSON.stringify({ detail: "Invalid JSON." }));
        return;
      }
      // Heuristics read the ticket (or the whole state), never the SLA keys ("breached").
      const text = JSON.stringify(j.state?.ticket ?? j.state ?? "").toLowerCase();
      const answers = Object.fromEntries(Object.entries(j.questions ?? {}).map(([id, q]) => [id, answer(id, q, text)]));
      // Counts only: never the state or the questions.
      console.log(`systemone ${Object.keys(answers).length} questions`);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ model: "jev-1.13.0", answers, usage: { input_tokens: Math.ceil(body.length / 4), output_tokens: 10 * Object.keys(answers).length } }));
    });
  })
  .listen(port, "127.0.0.1", () => console.log(`fake typesafe on :${port}`));
