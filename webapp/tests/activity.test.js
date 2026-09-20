import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { Gmail, SCOPE, mapLimit } from "../server/gmail.js";
import { activityLogger } from "../server/activity.js";
function client(fetchImpl, log = () => {}) {
  const g = new Gmail({ fetchImpl, log, paceMs: 0 });
  g.token = {
    scope: SCOPE,
    access_token: "secret",
    expires_at: Date.now() + 3600000,
  };
  return g;
}
test("quota denial preserves authorization and honors cooldown without more Gmail calls", async () => {
  let calls = 0;
  const entries = [];
  const g = client(
    async () => {
      calls++;
      return new Response(
        JSON.stringify({
          error: {
            message: "private detail",
            errors: [{ reason: "userRateLimitExceeded" }],
          },
        }),
        { status: 403, headers: { "retry-after": "120" } },
      );
    },
    (e) => entries.push(e),
  );
  await assert.rejects(
    g.get("messages/m1"),
    (e) =>
      e.status === 429 &&
      e.code === "rate_limit" &&
      e.retryAfterSeconds === 120,
  );
  await assert.rejects(g.get("profile"), (e) => e.status === 429);
  assert.equal(calls, 1);
  assert.equal(g.token.access_token, "secret");
  assert.equal(entries[0].quotaUnits, 20);
  assert.equal(entries[0].reason, "userRateLimitExceeded");
  assert.doesNotMatch(JSON.stringify(entries), /secret|private detail|m1/);
});
test("permission errors do not pretend authorization expired", async () => {
  const g = client(
    async () =>
      new Response(
        JSON.stringify({ error: { errors: [{ reason: "domainPolicy" }] } }),
        { status: 403 },
      ),
  );
  await assert.rejects(
    g.get("profile"),
    (e) => e.status === 403 && e.code === "gmail",
  );
});
test("local rolling budget blocks before calling Gmail", async () => {
  let calls = 0;
  const g = client(async () => {
    calls++;
    return new Response("{}");
  });
  g.usage = [{ time: Date.now(), units: 3980 }];
  const result = await Promise.allSettled([
    g.get("messages/a"),
    g.get("messages/b"),
    g.get("messages/c"),
  ]);
  assert.equal(calls, 1);
  assert.equal(result.filter((r) => r.status === "rejected").length, 2);
});
test("global concurrency remains at three across simultaneous callers", async () => {
  let active = 0,
    peak = 0;
  const g = client(async () => {
    active++;
    peak = Math.max(peak, active);
    await new Promise((r) => setTimeout(r, 10));
    active--;
    return new Response("{}");
  });
  await Promise.all(Array.from({ length: 12 }, () => g.get("profile")));
  assert.equal(peak, 3);
  assert.equal(g.active, 0);
});
test("hydration stops scheduling after errors or cancellation", async () => {
  let calls = 0;
  await assert.rejects(
    mapLimit(
      Array.from({ length: 100 }, (_, i) => i),
      3,
      async () => {
        calls++;
        throw new Error("limited");
      },
    ),
  );
  assert.equal(calls, 3);
  await mapLimit(
    [1, 2, 3],
    3,
    async () => {
      calls++;
    },
    () => true,
  );
  assert.equal(calls, 3);
});
test("activity logs omit sensitive fields, rotate, and use private permissions", async () => {
  const root = path.resolve(import.meta.dirname, "../../tmp/tests");
  await fs.mkdir(root, { recursive: true });
  const dir = await fs.mkdtemp(path.join(root, "activity-"));
  const file = path.join(dir, "private/api-activity.jsonl");
  const log = activityLogger(file, 1);
  log({
    event: "gmail",
    operation: "messages.get",
    status: 200,
    token: "secret",
    query: "private query",
    body: "mail text",
  });
  await log.flush();
  const first = await fs.readFile(file, "utf8");
  assert.doesNotMatch(first, /secret|private query|mail text|token|body/);
  assert.equal((await fs.stat(file)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(path.dirname(file))).mode & 0o777, 0o700);
  log({ event: "cache", operation: "message", reason: "hit" });
  await log.flush();
  assert.equal(await fs.readFile(file + ".1", "utf8"), first);
  assert.equal(JSON.parse(await fs.readFile(file, "utf8")).event, "cache");
});
