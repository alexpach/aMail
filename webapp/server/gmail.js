import fs from "node:fs/promises";
import path from "node:path";
import { randomBytes } from "node:crypto";
export const SCOPE = "https://www.googleapis.com/auth/gmail.readonly";
export const REDIRECT = "http://localhost:10014/api/oauth/callback";
export class AppError extends Error {
  constructor(message, status = 500, code = "error") {
    super(message);
    this.status = status;
    this.code = code;
  }
}
export class Gmail {
  constructor({
    credentialPath,
    tokenPath,
    fetchImpl = fetch,
    log = () => {},
    paceMs = 250,
  }) {
    this.credentialPath = credentialPath;
    this.tokenPath = tokenPath;
    this.fetch = fetchImpl;
    this.token = null;
    this.refreshing = null;
    this.log = log;
    this.paceMs = paceMs;
    this.nextStart = 0;
    this.cooldownUntil = 0;
    this.usage = [];
    this.active = 0;
    this.waiters = [];
  }
  async credentials() {
    try {
      const config = JSON.parse(
        await fs.readFile(this.credentialPath, "utf8"),
      ).web;
      if (!config?.client_id || !config?.client_secret) throw new Error();
      return config;
    } catch {
      throw new AppError(
        "aMail OAuth credentials are missing or invalid. Set AMAIL_CLIENT_SECRET to your Google web client JSON.",
        503,
        "configuration",
      );
    }
  }
  async load() {
    try {
      this.token = JSON.parse(await fs.readFile(this.tokenPath, "utf8"));
    } catch (e) {
      if (e.code !== "ENOENT")
        throw new AppError(
          "The local token file cannot be read. Check its permissions or reconnect.",
          503,
          "configuration",
        );
    }
  }
  async save(token) {
    // Refuse accidentally imported broad grants. aMail only accepts its read-only scope.
    if (token.scope !== SCOPE)
      throw new AppError(
        "Google did not grant the exact read-only scope. Reconnect with Gmail read-only access.",
        401,
        "reconnect",
      );
    const dir = path.dirname(this.tokenPath);
    await fs.mkdir(dir, { recursive: true, mode: 0o700 });
    await fs.chmod(dir, 0o700);
    const temp = `${this.tokenPath}.${randomBytes(6).toString("hex")}`;
    await fs.writeFile(temp, JSON.stringify(token), {
      mode: 0o600,
      flag: "wx",
    });
    await fs.rename(temp, this.tokenPath);
    this.token = token;
  }
  async tokenRequest(params) {
    const started = Date.now();
    const c = await this.credentials();
    let response;
    try {
      response = await this.fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: c.client_id,
          client_secret: c.client_secret,
          ...params,
        }),
        signal: AbortSignal.timeout(25000),
        redirect: "error",
      });
    } catch {
      this.log({
        event: "oauth",
        operation:
          params.grant_type === "refresh_token" ? "refresh" : "exchange",
        status: 0,
        reason: "network",
        durationMs: Date.now() - started,
      });
      throw new AppError(
        "Cannot reach Google. Check your connection and try again.",
        502,
        "network",
      );
    }
    const body = await response.json();
    this.log({
      event: "oauth",
      operation: params.grant_type === "refresh_token" ? "refresh" : "exchange",
      status: response.status,
      durationMs: Date.now() - started,
      reason: [
        "invalid_grant",
        "invalid_client",
        "invalid_scope",
        "access_denied",
      ].includes(body.error)
        ? body.error
        : response.ok
          ? "ok"
          : "authorization_error",
    });
    if (!response.ok) {
      if (body.error === "invalid_grant") {
        this.token = null;
        throw new AppError(
          "Google access expired or was revoked. Reconnect your Gmail account. Google testing-mode grants can expire after seven days.",
          401,
          "reconnect",
        );
      }
      throw new AppError(
        "Google authorization failed. Check your OAuth client and reconnect.",
        401,
        "reconnect",
      );
    }
    if (!body.access_token)
      throw new AppError(
        "Google returned an incomplete authorization. Reconnect.",
        401,
        "reconnect",
      );
    return body;
  }
  async exchange(code, verifier) {
    const t = await this.tokenRequest({
      code,
      code_verifier: verifier,
      grant_type: "authorization_code",
      redirect_uri: REDIRECT,
    });
    if (!t.refresh_token)
      throw new AppError(
        "Google did not return offline access. Reconnect and approve the read-only permission.",
        401,
        "reconnect",
      );
    await this.save({ ...t, expires_at: Date.now() + t.expires_in * 1000 });
  }
  async access(force = false) {
    if (!this.token || this.token.scope !== SCOPE)
      throw new AppError(
        "Connect Gmail to read your mailbox.",
        401,
        "reconnect",
      );
    if (
      !force &&
      this.token.access_token &&
      this.token.expires_at > Date.now() + 60000
    )
      return this.token.access_token;
    if (!this.refreshing)
      this.refreshing = (async () => {
        const old = this.token;
        const fresh = await this.tokenRequest({
          refresh_token: old.refresh_token,
          grant_type: "refresh_token",
        });
        await this.save({
          ...old,
          ...fresh,
          scope: fresh.scope ?? old.scope,
          expires_at: Date.now() + fresh.expires_in * 1000,
        });
        return this.token.access_token;
      })().finally(() => {
        this.refreshing = null;
      });
    return this.refreshing;
  }
  async get(resource, params = {}, retry = true) {
    if (this.active >= 3) {
      if (this.waiters.length >= 32) {
        const error = new AppError(
          "Too many pending mail requests. Try again shortly.",
          429,
          "rate_limit",
        );
        error.retryAfterSeconds = 5;
        this.log({
          event: "throttled",
          operation: "queue",
          reason: "queue_full",
          retryAfterSeconds: 5,
        });
        throw error;
      }
      await new Promise((resolve) => this.waiters.push(resolve));
    } else this.active++;
    try {
      return await this.request(resource, params, retry);
    } finally {
      const next = this.waiters.shift();
      if (next) next();
      else this.active--;
    }
  }
  async request(resource, params, retry) {
    // No method argument and no generic proxy: every Gmail request is a whitelisted GET.
    if (
      !/^(profile|labels|labels\/[\w-]+|messages|messages\/[\w-]+(?:\/attachments\/[\w-]+)?)$/.test(
        resource,
      )
    ) {
      throw new AppError("Unsupported read operation.", 400);
    }
    const operation =
      resource === "profile"
        ? "profile.get"
        : resource === "labels"
          ? "labels.list"
          : resource.startsWith("labels/")
            ? "labels.get"
            : resource === "messages"
              ? "messages.list"
              : resource.includes("/attachments/")
                ? "attachments.get"
                : "messages.get";
    const units =
      operation === "messages.list"
        ? 5
        : ["messages.get", "attachments.get"].includes(operation)
          ? 20
          : 1;
    const access = await this.access();
    const startAt = Math.max(Date.now(), this.nextStart);
    this.nextStart = startAt + this.paceMs;
    if (startAt > Date.now())
      await new Promise((resolve) => setTimeout(resolve, startAt - Date.now()));
    this.usage = this.usage.filter((x) => x.time > Date.now() - 60000);
    const used = this.usage.reduce((sum, x) => sum + x.units, 0);
    if (this.cooldownUntil > Date.now() || used + units > 4000) {
      const wait = Math.max(
        1,
        Math.ceil(
          ((this.cooldownUntil > Date.now()
            ? this.cooldownUntil
            : this.usage[0].time + 60000) -
            Date.now()) /
            1000,
        ),
      );
      this.log({
        event: "throttled",
        operation,
        reason: "local_budget_or_cooldown",
        unitsLastMinute: used,
        retryAfterSeconds: wait,
      });
      const error = new AppError(
        "Mail requests are paused to respect Gmail limits. Try again in " +
          wait +
          " seconds.",
        429,
        "rate_limit",
      );
      error.retryAfterSeconds = wait;
      throw error;
    }
    const started = Date.now();
    this.usage.push({ time: started, units });
    let response;
    try {
      response = await this.fetch(
        `https://gmail.googleapis.com/gmail/v1/users/me/${resource}?${new URLSearchParams(params)}`,
        {
          method: "GET",
          headers: { Authorization: `Bearer ${access}` },
          signal: AbortSignal.timeout(30000),
          redirect: "error",
        },
      );
    } catch {
      this.log({
        event: "gmail",
        operation,
        status: 0,
        reason: "network",
        durationMs: Date.now() - started,
        quotaUnits: units,
        unitsLastMinute: used + units,
      });
      throw new AppError(
        "Gmail could not be reached. Try refreshing in a moment.",
        502,
        "network",
      );
    }
    const body = await response.json().catch(() => ({}));
    const knownReasons = [
      "rateLimitExceeded",
      "userRateLimitExceeded",
      "dailyLimitExceeded",
      "quotaExceeded",
      "authError",
      "insufficientPermissions",
      "accessNotConfigured",
      "domainPolicy",
      "backendError",
      "notFound",
      "invalidArgument",
    ];
    const reasons = (body.error?.errors ?? []).map((e) => e.reason);
    const reason =
      reasons.find((r) => knownReasons.includes(r)) ??
      (response.ok ? "ok" : "unclassified");
    this.log({
      event: "gmail",
      operation,
      status: response.status,
      reason,
      durationMs: Date.now() - started,
      quotaUnits: units,
      unitsLastMinute: used + units,
    });
    if (response.status === 401 && retry) {
      await this.access(true);
      return this.request(resource, params, false);
    }
    if (!response.ok) {
      const status = response.status;
      const limited =
        status === 429 ||
        reasons.some((r) =>
          [
            "rateLimitExceeded",
            "userRateLimitExceeded",
            "dailyLimitExceeded",
            "quotaExceeded",
          ].includes(r),
        );
      if (limited || status >= 500) {
        const retryAfter = response.headers.get("retry-after");
        const delay =
          retryAfter && /^\d+$/.test(retryAfter)
            ? Number(retryAfter) * 1000
            : retryAfter
              ? Date.parse(retryAfter) - Date.now()
              : 0;
        const seconds = Math.ceil(
          Math.max(Number.isFinite(delay) ? delay : 0, limited ? 60000 : 5000) /
            1000,
        );
        this.cooldownUntil = Math.max(
          this.cooldownUntil,
          Date.now() + seconds * 1000,
        );
        this.log({
          event: "cooldown",
          operation,
          reason,
          retryAfterSeconds: seconds,
        });
        const error = new AppError(
          "Gmail is temporarily " +
            (limited ? "limiting requests" : "unavailable") +
            ". Try again in " +
            seconds +
            " seconds.",
          limited ? 429 : 503,
          limited ? "rate_limit" : "gmail",
        );
        error.retryAfterSeconds = seconds;
        throw error;
      }
      throw new AppError(
        status === 401
          ? "Gmail access is unavailable. Check that Gmail API is enabled and reconnect with read-only permission."
          : status === 403
            ? "Gmail denied this request. Check API permissions or Workspace policy; details are in the local activity log."
            : status === 404
              ? "This message is no longer available in Gmail."
              : "Gmail could not complete this request. Try again.",
        status === 401
          ? 401
          : status === 403
            ? 403
            : status === 404
              ? 404
              : 502,
        status === 401 ? "reconnect" : "gmail",
      );
    }
    return body;
  }
}
export async function mapLimit(items, limit, work, cancelled = () => false) {
  const results = new Array(items.length);
  let next = 0;
  let failed = false;
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, async () => {
      while (!failed && !cancelled() && next < items.length) {
        const i = next++;
        try {
          results[i] = await work(items[i]);
        } catch (error) {
          failed = true;
          throw error;
        }
      }
    }),
  );
  return results;
}
