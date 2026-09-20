import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import { request } from "node:http";
import { createApp } from "../server/app.js";
import { Gmail, SCOPE, REDIRECT } from "../server/gmail.js";
import { detail, cleanHtml, summarize, decodeText } from "../server/mime.js";
import { fixture } from "./fixtures.js";
const root = path.resolve(import.meta.dirname, "../../tmp/tests");
async function setup(t, options = {}) {
  const calls = [];
  let exchanged;
  const fake = {
    token: { scope: SCOPE },
    credentials: async () => ({
      client_id: "fake-client",
      client_secret: "never-in-browser",
    }),
    exchange: async (code, verifier) => {
      exchanged = { code, verifier };
    },
    get: async (resource, params) => {
      calls.push({ resource, params });
      if (resource === "messages")
        return {
          messages: [{ id: "m1" }],
          nextPageToken: "next",
          resultSizeEstimate: 200,
        };
      if (resource === "messages/m1")
        return params?.format === "raw"
          ? {
              raw: Buffer.from("Subject: test\r\n\r\nbody").toString(
                "base64url",
              ),
            }
          : fixture();
      if (resource === "messages/m1/attachments/att1")
        return { data: Buffer.from("%PDF test").toString("base64url") };
      if (resource === "labels") return { labels: [] };
      if (resource === "profile") return { emailAddress: "fake@example.test" };
      throw new Error("Unexpected route");
    },
    ...options,
  };
  const server = createApp(fake).listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  t.after(() => new Promise((r) => server.close(r)));
  const base = `http://127.0.0.1:${server.address().port}`;
  let session = "";
  const req = (url, opts = {}) =>
    new Promise((resolve, reject) => {
      const r = request(
        `${base}${url}`,
        {
          ...opts,
          headers: {
            host: "localhost:10014",
            cookie: session,
            ...opts.headers,
          },
        },
        (response) => {
          const chunks = [];
          response.on("data", (c) => chunks.push(c));
          response.on("end", () =>
            resolve(
              new Response(Buffer.concat(chunks), {
                status: response.statusCode,
                headers: Object.fromEntries(
                  Object.entries(response.headers).map(([key, value]) => [
                    key,
                    Array.isArray(value) ? value.join("; ") : value,
                  ]),
                ),
              }),
            ),
          );
        },
      );
      r.on("error", reject);
      r.end();
    });
  const status = await req("/api/status");
  session = status.headers.get("set-cookie").split(";")[0];
  return { req, calls, status, fake, exchanged: () => exchanged };
}
test("OAuth is read-only, uses exact redirect and S256, binds state to browser and consumes it once", async (t) => {
  const s = await setup(t);
  const start = await s.req("/api/oauth/start");
  const u = new URL(start.headers.get("location"));
  assert.equal(u.searchParams.get("scope"), SCOPE);
  assert.equal(u.searchParams.get("redirect_uri"), REDIRECT);
  assert.equal(u.searchParams.get("code_challenge_method"), "S256");
  assert.equal(u.searchParams.has("client_secret"), false);
  assert.equal(
    (await s.req("/api/oauth/callback?state=wrong&code=fake")).status,
    400,
  );
  const state = u.searchParams.get("state");
  assert.equal(
    (
      await s.req(`/api/oauth/callback?state=${state}&code=fake`, {
        headers: { cookie: "amail_session=wrong" },
      })
    ).status,
    401,
  );
  const accepted = await s.req(`/api/oauth/callback?state=${state}&code=fake`);
  assert.equal(accepted.status, 302);
  assert.equal(s.exchanged().code, "fake");
  assert.equal(
    createHash("sha256").update(s.exchanged().verifier).digest("base64url"),
    u.searchParams.get("code_challenge"),
  );
  assert.equal(
    (await s.req(`/api/oauth/callback?state=${state}&code=fake`)).status,
    400,
  );
  assert.match(s.status.headers.get("set-cookie"), /HttpOnly/);
  assert.match(s.status.headers.get("set-cookie"), /SameSite=Lax/);
});
test("OAuth cancellation is handled and state expires", async (t) => {
  const s = await setup(t);
  const first = new URL(
    (await s.req("/api/oauth/start")).headers.get("location"),
  );
  const denied = await s.req(
    `/api/oauth/callback?state=${first.searchParams.get("state")}&error=access_denied`,
  );
  assert.equal(denied.headers.get("location"), "/?auth=denied");
  assert.equal(s.exchanged(), undefined);
  const u = new URL((await s.req("/api/oauth/start")).headers.get("location"));
  const originalNow = Date.now;
  try {
    Date.now = () => originalNow() + 11 * 60000;
    assert.equal(
      (
        await s.req(
          `/api/oauth/callback?state=${u.searchParams.get("state")}&code=fake`,
        )
      ).status,
      400,
    );
  } finally {
    Date.now = originalNow;
  }
});
test("all mutations, cross-origin access, DNS rebinding, and secret paths are rejected", async (t) => {
  const s = await setup(t);
  for (const method of ["POST", "PUT", "PATCH", "DELETE"])
    assert.equal((await s.req("/api/messages/m1", { method })).status, 405);
  assert.equal((await s.req("/api/messages/m1/trash")).status, 404);
  assert.equal(
    (await s.req("/api/profile", { headers: { origin: "https://evil.test" } }))
      .status,
    403,
  );
  assert.equal(
    (await s.req("/api/profile", { headers: { host: "evil.test" } })).status,
    403,
  );
  assert.equal(
    (
      await s.req("/api/profile", {
        headers: { "sec-fetch-site": "cross-site" },
      })
    ).status,
    403,
  );
  assert.equal(
    (await s.req("/api/profile", { headers: { cookie: "" } })).status,
    401,
  );
  for (const url of [
    "/client_secret.json",
    "/.private/tokens.json",
    "/server/index.js",
    "/package.json",
  ])
    assert.equal((await s.req(url)).status, 404);
  assert.equal(s.calls.length, 0);
});
test("list searches Gmail with 100 results and pagination; opening and attachments only read", async (t) => {
  const s = await setup(t);
  const page = await (
    await s.req("/api/messages?q=from%3Amorgan&page=next")
  ).json();
  assert.equal(page.messages.length, 1);
  assert.equal(page.nextPage, "next");
  assert.equal(page.messages[0].hasAttachments, true);
  assert.deepEqual(s.calls[0], {
    resource: "messages",
    params: { maxResults: "100", q: "from:morgan", pageToken: "next" },
  });
  const m = await (await s.req("/api/messages/m1")).json();
  assert.ok(m.labelIds.includes("UNREAD"));
  assert.match(m.html, /data:image\/png;base64/);
  assert.equal(m.calendar, true);
  const attachment = await s.req("/api/messages/m1/parts/1");
  assert.match(attachment.headers.get("content-disposition"), /^attachment/);
  assert.match(attachment.headers.get("content-type"), /octet-stream/);
  assert.equal(await attachment.text(), "%PDF test");
  assert.equal((await s.req("/api/messages/m1/parts/not-real")).status, 404);
  const source = await s.req("/api/messages/m1/original");
  assert.match(source.headers.get("content-type"), /text\/plain/);
  assert.ok(s.calls.every((c) => !/modify|send|trash|drafts/.test(c.resource)));
});
test("MIME decoding, CID images, calendar and HTML isolation resist active content and tracking", async () => {
  const m = await detail(fixture(), async () => ({ data: "" }));
  assert.equal(m.attachments.length, 3);
  assert.equal(m.remoteImages, true);
  assert.ok(!m.html.includes("<script"));
  assert.ok(!m.html.includes("onerror"));
  assert.ok(!m.html.includes("<form"));
  assert.ok(!m.html.includes('src="https://'));
  assert.match(m.html, /default-src 'none'/);
  assert.match(m.html, /form-action 'none'/);
  const html = cleanHtml(
    '<img src="data:image/svg+xml;base64,PHN2Zz4="><img src="https://remote.test/image"><a href="javascript:alert(1)">bad</a><div style="background:url(https://tracker.test);position:fixed">ok</div>',
  );
  assert.ok(!html.includes("data:image/svg"));
  assert.ok(!html.includes("javascript"));
  assert.ok(!html.includes("https://"));
  assert.ok(!html.includes("fixed"));
  const remote = await detail(fixture(), async () => ({ data: "" }), true);
  assert.match(remote.html, /src="https:\/\/tracking.example.test\/pixel"/);
  assert.equal(
    decodeText(
      {
        headers: [
          { name: "Content-Type", value: "text/plain; charset=iso-8859-1" },
        ],
      },
      Buffer.from([0x63, 0x61, 0x66, 0xe9]).toString("base64url"),
    ),
    "café",
  );
  assert.equal(summarize(fixture()).calendar, true);
});
test("external MIME body retrieval and attached HTML are handled separately", async () => {
  const m = fixture();
  m.payload.parts = [
    { partId: "0", mimeType: "text/html", body: { attachmentId: "body" } },
    {
      partId: "1",
      mimeType: "text/html",
      filename: "unsafe.html",
      body: { data: Buffer.from("<p>not body</p>").toString("base64url") },
    },
  ];
  const rendered = await detail(m, async (id) => {
    assert.equal(id, "body");
    return { data: Buffer.from("<p>actual body</p>").toString("base64url") };
  });
  assert.match(rendered.html, /actual body/);
  assert.ok(!rendered.html.includes("not body"));
  assert.equal(rendered.attachments[0].name, "unsafe.html");
});
test("token refresh is single-flight, stores mode 0600, and Gmail accepts only whitelisted GETs", async () => {
  await fs.mkdir(root, { recursive: true });
  const dir = await fs.mkdtemp(path.join(root, "oauth-"));
  const credentialPath = path.join(dir, "client.json");
  const tokenPath = path.join(dir, "private/tokens.json");
  await fs.writeFile(
    credentialPath,
    JSON.stringify({
      web: { client_id: "fixture", client_secret: "fixture-secret" },
    }),
  );
  const calls = [];
  const g = new Gmail({
    credentialPath,
    tokenPath,
    fetchImpl: async (url, opts) => {
      calls.push({ url, opts });
      if (url.includes("/token"))
        return Response.json({
          access_token: "new-access",
          expires_in: 3600,
          scope: SCOPE,
        });
      return Response.json({ emailAddress: "fixture@example.test" });
    },
  });
  g.token = { scope: SCOPE, refresh_token: "fixture-refresh", expires_at: 0 };
  await Promise.all([g.get("profile"), g.get("labels")]);
  assert.equal(calls.filter((c) => c.url.includes("/token")).length, 1);
  assert.ok(
    calls
      .filter((c) => c.url.includes("gmail.googleapis"))
      .every((c) => c.opts.method === "GET"),
  );
  assert.equal((await fs.stat(tokenPath)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(path.dirname(tokenPath))).mode & 0o777, 0o700);
  assert.equal(
    JSON.parse(await fs.readFile(tokenPath)).refresh_token,
    "fixture-refresh",
  );
  await assert.rejects(g.get("messages/m1/trash"), /Unsupported read/);
  await assert.rejects(
    g.save({ scope: "https://mail.google.com/" }),
    /exact read-only scope/,
  );
  const bad = new Gmail({
    credentialPath,
    tokenPath,
    fetchImpl: async () =>
      Response.json(
        { error: "invalid_grant", secret: "do-not-expose" },
        { status: 400 },
      ),
  });
  bad.token = { refresh_token: "invalid", scope: SCOPE };
  await assert.rejects(
    bad.get("profile"),
    (e) => e.code === "reconnect" && !e.message.includes("do-not-expose"),
  );
  assert.equal(bad.token, null);
});
test("compiled app is served even from a hidden worktree; encoded headers are decoded", async (t) => {
  const s = await setup(t);
  const response = await s.req("/");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /text\/html/);
  assert.match(await response.text(), /<title>aMail<\/title>/);
  const m = fixture();
  m.payload.headers[0].value = "=?UTF-8?B?Q2Fmw6k=?=";
  assert.equal(summarize(m).subject, "Café");
});
test("OAuth rejects a valid state when it is returned in another initialized browser session", async (t) => {
  const s = await setup(t);
  const u = new URL((await s.req("/api/oauth/start")).headers.get("location"));
  const other = (
    await s.req("/api/status", { headers: { cookie: "" } })
  ).headers
    .get("set-cookie")
    .split(";")[0];
  assert.equal(
    (
      await s.req(
        `/api/oauth/callback?state=${u.searchParams.get("state")}&code=fake`,
        { headers: { cookie: other } },
      )
    ).status,
    400,
  );
  assert.equal(s.exchanged(), undefined);
});

test("Google callback redirect can open the app shell without allowing cross-site mail access", async (t) => {
  const s = await setup(t);
  const u = new URL((await s.req("/api/oauth/start")).headers.get("location"));
  const headers = {
    "sec-fetch-site": "cross-site",
    "sec-fetch-mode": "navigate",
    "sec-fetch-dest": "document",
  };
  const callback = await s.req(
    `/api/oauth/callback?state=${u.searchParams.get("state")}&code=fake`,
    { headers },
  );
  assert.equal(callback.status, 302);
  const landing = await s.req(callback.headers.get("location"), { headers });
  assert.equal(landing.status, 200);
  assert.match(await landing.text(), /<title>aMail<\/title>/);
  assert.equal((await s.req("/?auth=denied", { headers })).status, 200);
  for (const url of [
    "/api/status",
    "/api/profile",
    "/api/messages",
    "/api/oauth/start",
  ]) {
    assert.equal((await s.req(url, { headers })).status, 403);
  }
  assert.equal(
    (await s.req("/", { headers: { ...headers, "sec-fetch-mode": "cors" } }))
      .status,
    403,
  );
  assert.equal(
    (await s.req("/", { headers: { ...headers, "sec-fetch-dest": "iframe" } }))
      .status,
    403,
  );
  assert.equal(s.calls.length, 0);
});

test("opening and returning reuse message data; explicit refresh fetches fresh data", async (t) => {
  const s = await setup(t);
  for (const url of [
    "/api/messages",
    "/api/messages/m1",
    "/api/messages",
    "/api/messages",
  ]) {
    assert.equal((await s.req(url)).status, 200);
  }
  assert.equal(s.calls.filter((c) => c.resource === "messages").length, 1);
  assert.equal(s.calls.filter((c) => c.resource === "messages/m1").length, 1);
  assert.equal((await s.req("/api/messages?refresh=1")).status, 200);
  assert.equal(s.calls.filter((c) => c.resource === "messages").length, 2);
  assert.equal(s.calls.filter((c) => c.resource === "messages/m1").length, 2);
  await Promise.all([
    s.req("/api/profile"),
    s.req("/api/profile"),
    s.req("/api/labels"),
    s.req("/api/labels"),
  ]);
  assert.equal(s.calls.filter((c) => c.resource === "profile").length, 1);
  assert.equal(s.calls.filter((c) => c.resource === "labels").length, 1);
});
