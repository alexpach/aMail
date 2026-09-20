import express from "express";
import { randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { fileURLToPath } from "node:url";
import { AppError, SCOPE, REDIRECT, mapLimit } from "./gmail.js";
import { summarize, detail, partsOf, bytes } from "./mime.js";
const publicDir = fileURLToPath(new URL("../dist/", import.meta.url));
const equal = (a, b) =>
  typeof a === "string" &&
  typeof b === "string" &&
  a.length === b.length &&
  timingSafeEqual(Buffer.from(a), Buffer.from(b));
const cookie = (req) =>
  (req.headers.cookie ?? "")
    .split(";")
    .map((x) => x.trim())
    .find((x) => x.startsWith("amail_session="))
    ?.slice(14);
export function createApp(
  gmail,
  { origin = "http://localhost:10014", log = () => {} } = {},
) {
  const app = express();
  const sessions = new Map();
  const states = new Map();
  const cache = new Map();
  const pending = new Map();
  const now = () => Date.now();
  async function cached(key, ttl, load, force = false) {
    const hit = cache.get(key);
    if (!force && hit?.expires > now()) {
      log({ event: "cache", operation: key.split(":")[0], reason: "hit" });
      return hit.value;
    }
    if (pending.has(key)) return pending.get(key);
    const work = load()
      .then((value) => {
        cache.set(key, { value, expires: now() + ttl });
        while (cache.size > 500) cache.delete(cache.keys().next().value);
        return value;
      })
      .finally(() => pending.delete(key));
    pending.set(key, work);
    return work;
  }
  app.disable("x-powered-by");
  app.use((req, res, next) => {
    const started = now();
    if (req.path.startsWith("/api/")) {
      res.on("finish", () =>
        log({
          event: "http",
          operation: req.route?.path ?? "unmatched",
          status: res.statusCode,
          durationMs: now() - started,
          code: res.locals.errorCode,
        }),
      );
      res.on("close", () => {
        if (!res.writableFinished)
          log({
            event: "http",
            operation: req.route?.path ?? "unmatched",
            status: 499,
            reason: "client_disconnected",
            durationMs: now() - started,
          });
      });
    }
    res.set({
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "X-Frame-Options": "DENY",
      "Content-Security-Policy":
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; frame-src 'self' about:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    });
    if (req.headers.host !== new URL(origin).host)
      return res.status(403).json({
        error: "Use the configured localhost address.",
        code: "origin",
      });
    if (req.headers.origin && req.headers.origin !== origin)
      return res
        .status(403)
        .json({ error: "Cross-origin access is blocked.", code: "origin" });
    // Redirect chains retain Google's cross-site fetch metadata. The public
    // app shell may be opened as a top-level document; mail APIs stay protected.
    const appNavigation =
      req.path === "/" &&
      req.method === "GET" &&
      req.headers["sec-fetch-mode"] === "navigate" &&
      req.headers["sec-fetch-dest"] === "document";
    if (
      req.path !== "/api/oauth/callback" &&
      !appNavigation &&
      req.headers["sec-fetch-site"] === "cross-site"
    )
      return res
        .status(403)
        .json({ error: "Open aMail directly on localhost.", code: "origin" });
    if (!["GET", "HEAD"].includes(req.method))
      return res
        .status(405)
        .json({ error: "This client is read-only.", code: "readonly" });
    for (const [key, expires] of sessions)
      if (expires < now()) sessions.delete(key);
    for (const [key, value] of states)
      if (value.expires < now()) states.delete(key);
    let sid = cookie(req);
    if (
      !sessions.has(sid) &&
      (req.path === "/" || req.path === "/api/status")
    ) {
      sid = randomBytes(32).toString("hex");
      sessions.set(sid, now() + 86400000);
      res.cookie("amail_session", sid, {
        httpOnly: true,
        sameSite: "lax",
        path: "/",
        maxAge: 86400000,
      });
    }
    req.sid = sessions.has(sid) ? sid : null;
    if (req.path.startsWith("/api/") && req.path !== "/api/status" && !req.sid)
      return res.status(401).json({
        error: "Your local session expired. Reload aMail.",
        code: "session",
      });
    next();
  });
  app.get("/api/status", async (_req, res) => {
    let configured = true;
    try {
      await gmail.credentials();
    } catch {
      configured = false;
    }
    res.json({
      connected: !!gmail.token && gmail.token.scope === SCOPE,
      configured,
      readonly: true,
    });
  });
  app.get("/api/oauth/start", async (req, res) => {
    const c = await gmail.credentials();
    const state = randomBytes(32).toString("hex");
    const verifier = randomBytes(48).toString("base64url");
    states.set(state, {
      sid: req.sid,
      verifier,
      expires: now() + 10 * 60 * 1000,
    });
    const q = new URLSearchParams({
      client_id: c.client_id,
      redirect_uri: REDIRECT,
      scope: SCOPE,
      response_type: "code",
      state,
      access_type: "offline",
      prompt: "consent",
      code_challenge: createHash("sha256").update(verifier).digest("base64url"),
      code_challenge_method: "S256",
    });
    res.redirect(`https://accounts.google.com/o/oauth2/v2/auth?${q}`);
  });
  app.get("/api/oauth/callback", async (req, res) => {
    const state = typeof req.query.state === "string" ? req.query.state : "";
    const pending = states.get(state);
    states.delete(state);
    if (!pending || pending.expires < now() || !equal(req.sid, pending.sid))
      return res
        .status(400)
        .send(
          "Authorization state is invalid or expired. Return to aMail and reconnect.",
        );
    if (req.query.error) return res.redirect("/?auth=denied");
    if (typeof req.query.code !== "string")
      return res
        .status(400)
        .send(
          "Google authorization code is missing. Return to aMail and reconnect.",
        );
    try {
      await gmail.exchange(req.query.code, pending.verifier);
      cache.clear();
      res.redirect("/");
    } catch {
      res.redirect("/?auth=failed");
    }
  });
  app.get("/api/profile", async (_req, res) =>
    res.json(await cached("profile", 300000, () => gmail.get("profile"))),
  );
  app.get("/api/labels", async (_req, res) => {
    const labels = await cached("labels", 300000, async () => {
      const result = await gmail.get("labels");
      return mapLimit(result.labels ?? [], 3, (l) =>
        l.type === "user" ? gmail.get(`labels/${l.id}`) : Promise.resolve(l),
      );
    });
    res.json({ labels });
  });
  async function message(id, refresh = false) {
    if (!/^[\w-]+$/.test(id))
      throw new AppError("Invalid message identifier.", 400);
    return cached(
      "message:" + id,
      300000,
      () => gmail.get(`messages/${id}`, { format: "full" }),
      refresh,
    );
  }
  app.get("/api/messages", async (req, res) => {
    const q =
      typeof req.query.q === "string" ? req.query.q.slice(0, 2000) : "in:inbox";
    const params = { maxResults: "100", q };
    if (typeof req.query.label === "string" && /^[\w-]+$/.test(req.query.label))
      params.labelIds = req.query.label;
    if (typeof req.query.page === "string") params.pageToken = req.query.page;
    if (/\bin:(anywhere|spam|trash)\b/i.test(q))
      params.includeSpamTrash = "true";
    const force = req.query.refresh === "1";
    const list = await cached(
      "list:" + JSON.stringify(params),
      30000,
      () => gmail.get("messages", params),
      force,
    );
    let unavailable = 0;
    const messages = (
      await mapLimit(
        list.messages ?? [],
        3,
        async ({ id }) => {
          try {
            return summarize(await message(id, force));
          } catch (e) {
            if (e.status === 404) {
              unavailable++;
              return null;
            }
            throw e;
          }
        },
        () => res.destroyed,
      )
    )
      .filter(Boolean)
      .sort((a, b) => b.date - a.date);
    res.json({
      messages,
      nextPage: list.nextPageToken ?? null,
      estimate: list.resultSizeEstimate ?? messages.length,
      unavailable,
    });
  });
  app.get("/api/messages/:id", async (req, res) => {
    const m = await message(req.params.id, req.query.refresh === "1");
    res.json(
      await detail(
        m,
        (aid) => gmail.get(`messages/${m.id}/attachments/${aid}`),
        req.query.remote === "1",
      ),
    );
  });
  app.get("/api/messages/:id/original", async (req, res) => {
    if (!/^[\w-]+$/.test(req.params.id))
      throw new AppError("Invalid message identifier.", 400);
    const m = await gmail.get(`messages/${req.params.id}`, { format: "raw" });
    res.type("text/plain").send(bytes(m.raw));
  });
  app.get("/api/messages/:id/parts/:part", async (req, res) => {
    const m = await message(req.params.id);
    const partId = req.params.part === "root" ? "" : req.params.part;
    const p = partsOf(m.payload).find((p) => (p.partId ?? "") === partId);
    if (!p?.body) throw new AppError("Attachment not found.", 404);
    const data =
      p.body.data ??
      (p.body.attachmentId
        ? (
            await gmail.get(
              `messages/${m.id}/attachments/${p.body.attachmentId}`,
            )
          ).data
        : "");
    const filename = (p.filename || "attachment").replace(/[\r\n"\\/]/g, "_");
    const encoded = encodeURIComponent(filename).replace(
      /['()*]/g,
      (c) => `%${c.charCodeAt(0).toString(16)}`,
    );
    res.set(
      "Content-Disposition",
      `attachment; filename="attachment"; filename*=UTF-8''${encoded}`,
    );
    res.type("application/octet-stream").send(bytes(data));
  });
  app.use("/api", (_req, res) =>
    res
      .status(404)
      .json({ error: "No such read-only endpoint.", code: "not_found" }),
  );
  // Only compiled public assets are served. Credentials, source, and tokens are never static roots.
  app.use(express.static(publicDir, { index: false, dotfiles: "deny" }));
  app.get("/", (_req, res) => res.sendFile("index.html", { root: publicDir }));
  app.use((err, _req, res, _next) => {
    const known = err instanceof AppError;
    res.locals.errorCode = known ? err.code : "internal";
    if (known && err.retryAfterSeconds)
      res.set("Retry-After", String(err.retryAfterSeconds));
    res.status(known ? err.status : 500).json({
      error: known
        ? err.message
        : "aMail could not complete this request. Try again.",
      code: known ? err.code : "internal",
    });
  });
  return app;
}
