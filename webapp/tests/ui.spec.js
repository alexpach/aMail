import { test, expect } from "@playwright/test";
import { raster } from "./fixtures.js";
test("inbox, sidebar, search, local selection, saved searches, pagination and narrow layout", async ({
  page,
}) => {
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("/");
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await expect(page.getByText("Read only", { exact: true })).toBeVisible();
  const wide = await page.locator("main").boundingBox();
  await page.screenshot({ path: "../tmp/inbox-expanded.png", fullPage: true });
  await page.getByRole("button", { name: "Collapse sidebar" }).click();
  await expect(page.locator(".workspace")).toHaveClass(/collapsed/);
  await expect
    .poll(async () => (await page.locator("main").boundingBox()).x)
    .toBeLessThan(wide.x);
  await expect
    .poll(async () => (await page.locator(".sidebar").boundingBox()).width)
    .toBe(0);
  await page.screenshot({ path: "../tmp/inbox-collapsed.png", fullPage: true });
  await page.getByRole("button", { name: "Selection menu" }).click();
  await page.getByRole("menuitem", { name: "Select unread" }).click();
  await expect(page.getByText("7 selected on this page")).toBeVisible();
  await expect(page.locator(".selected")).toHaveCount(7);
  await page.locator(".mail-row").first().hover();
  await expect(
    page
      .getByRole("button", { name: "Delete unavailable in read-only mode" })
      .first(),
  ).toBeDisabled();
  const request = page.waitForRequest(
    (r) =>
      r.url().includes("/api/messages?") &&
      new URL(r.url()).searchParams.get("q") === "from:someone older_than:1y",
  );
  await page
    .getByRole("textbox", { name: "Search Gmail" })
    .fill("from:someone older_than:1y");
  await page.getByRole("textbox", { name: "Search Gmail" }).press("Enter");
  await request;
  await expect(
    page.getByText("Search results", { exact: false }).first(),
  ).toBeVisible();
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await page.getByRole("button", { name: "Next page" }).click();
  await expect(page.locator(".mail-row")).toHaveCount(2);
  await page.getByRole("button", { name: "Previous page" }).click();
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await page.getByRole("button", { name: "Profile and settings" }).click();
  await page.getByRole("menuitem", { name: "Saved searches & tabs" }).click();
  await page
    .getByRole("textbox", { name: "Tab 1 name", exact: true })
    .fill("My inbox");
  await page
    .getByRole("button", { name: "Move Today up", exact: true })
    .click();
  await page.getByRole("button", { name: "Add tab", exact: true }).click();
  await page
    .getByRole("textbox", { name: "Tab 10 name", exact: true })
    .fill("Receipts");
  await page
    .getByRole("textbox", { name: "Tab 10 query", exact: true })
    .fill("subject:receipt");
  await page
    .getByRole("button", { name: "Remove Purple", exact: true })
    .click();
  await page.getByRole("button", { name: "Save changes" }).click();
  await expect(page.locator(".tabs button").first()).toHaveText("Today");
  await page.reload();
  await expect(
    page.getByRole("button", { name: "Receipts", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Collapse sidebar" }).click();
  await page.setViewportSize({ width: 600, height: 850 });
  await expect
    .poll(async () => (await page.locator(".sidebar").boundingBox()).width)
    .toBe(0);
  await expect(
    page.getByRole("textbox", { name: "Search Gmail" }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({ path: "../tmp/inbox-narrow.png", fullPage: true });
  expect(errors).toEqual([]);
});
test("message body is isolated, keeps header, blocks tracking until opted in, and exposes read-only details", async ({
  page,
  context,
}) => {
  const mutation = [],
    remote = [];
  context.on("request", (r) => {
    if (!["GET", "HEAD"].includes(r.method())) mutation.push(r.url());
    if (r.url().includes("tracking.example.test")) remote.push(r.url());
  });
  await context.route("https://tracking.example.test/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "image/png",
      body: Buffer.from(raster, "base64"),
    }),
  );
  await page.goto("/");
  await page
    .getByRole("button", {
      name: "Open A little room for what matters from Morgan Chen",
    })
    .first()
    .click();
  await expect(
    page.getByRole("heading", { name: "A little room for what matters" }),
  ).toBeVisible();
  await expect(
    page.getByRole("textbox", { name: "Search Gmail" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Collapse sidebar" }),
  ).toBeVisible();
  const frame = page.frameLocator("iframe");
  await expect(frame.getByText("Hello Alex,")).toBeVisible();
  await expect(page.locator("iframe")).toHaveAttribute(
    "sandbox",
    "allow-popups allow-popups-to-escape-sandbox",
  );
  await expect(frame.locator('img[src^="https:"]')).toHaveCount(0);
  await expect(
    frame.locator('meta[http-equiv="Content-Security-Policy"]'),
  ).toHaveAttribute("content", /img-src data:;/);
  expect(await page.evaluate(() => window.pwned)).toBeUndefined();
  expect(remote).toHaveLength(0);
  await page.screenshot({ path: "../tmp/open-message.png", fullPage: true });
  await page
    .getByRole("button", { name: "Load images for this message" })
    .click();
  await expect(
    page.frameLocator("iframe").locator('img[alt="Remote image"]'),
  ).toHaveAttribute("src", "https://tracking.example.test/pixel");
  await expect(
    page
      .frameLocator("iframe")
      .locator('meta[http-equiv="Content-Security-Policy"]'),
  ).toHaveAttribute("content", /img-src data: https:;/);
  await expect.poll(() => remote.length).toBe(1);
  await page.getByRole("button", { name: "Message options" }).click();
  await page
    .getByRole("menuitem", { name: "Message details & headers" })
    .click();
  await expect(page.getByText("<fixture@example.test>")).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page.getByRole("button", { name: "Message options" }).click();
  await page.getByRole("menuitem", { name: "View original source" }).click();
  await expect(
    page.getByText("Synthetic email for testing.", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();
  const download = page.waitForEvent("download");
  await page.getByRole("link", { name: /agenda.pdf/ }).click();
  expect((await download).suggestedFilename()).toBe("agenda.pdf");
  await page.getByRole("button", { name: "Back to messages" }).click();
  await expect(page.locator(".mail-row.unread")).toHaveCount(7);
  expect(mutation).toHaveLength(0);
});
test("connection screen and retry recover from a temporary mailbox error", async ({
  page,
}) => {
  await page.route("**/api/status", (r) =>
    r.fulfill({ json: { connected: false, configured: true, readonly: true } }),
  );
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Connect Gmail", exact: true }),
  ).toBeEnabled();
  await expect(
    page.getByRole("button", { name: "Refresh mail" }),
  ).toBeDisabled();
  await page.screenshot({ path: "../tmp/connect-screen.png", fullPage: true });
  await page.unroute("**/api/status");
  await page.route(
    "**/api/messages?*",
    (r) =>
      r.fulfill({
        status: 502,
        json: { error: "Temporary test mailbox error.", code: "network" },
      }),
    { times: 1 },
  );
  await page.reload();
  await expect(page.getByRole("alert")).toContainText(
    "Temporary test mailbox error.",
  );
  await page.getByRole("button", { name: "Retry", exact: true }).click();
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("filters stay visible and editable; sidebar sections collapse independently and persist", async ({
  page,
}) => {
  await page.goto("/");
  const search = page.getByRole("textbox", { name: "Search Gmail" });
  await expect(search).toHaveValue("in:inbox");
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await page.route("**/api/messages?*", (route) => {
    const q = new URL(route.request().url()).searchParams.get("q");
    return q === "has:blue-star"
      ? route.fulfill({
          json: { messages: [], nextPage: null, unavailable: 0 },
        })
      : route.continue();
  });
  const request = page.waitForRequest(
    (r) => new URL(r.url()).searchParams.get("q") === "has:blue-star",
  );
  await page
    .getByRole("navigation", { name: "Saved searches" })
    .getByRole("button", { name: "Blue", exact: true })
    .click();
  await request;
  await expect(search).toHaveValue("has:blue-star");
  await expect(
    page.getByText("Gmail returned no matches for", { exact: false }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Show all starred mail" }).click();
  await expect(search).toHaveValue("is:starred");
  await expect(page.locator(".mail-row")).toHaveCount(26);
  await page
    .getByRole("complementary")
    .getByRole("button", { name: "Projects", exact: true })
    .click();
  await expect(search).toHaveValue('label:"Projects"');
  await search.fill("is:starred from:morgan");
  const edited = page.waitForRequest(
    (r) => new URL(r.url()).searchParams.get("q") === "is:starred from:morgan",
  );
  await search.press("Enter");
  expect(new URL((await edited).url()).searchParams.has("label")).toBe(false);
  const labels = page.getByRole("button", { name: "Labels", exact: true });
  await labels.click();
  await expect(labels).toHaveAttribute("aria-expanded", "false");
  await expect(
    page.getByRole("button", { name: "Projects", exact: true }),
  ).toBeHidden();
  await expect(
    page.getByRole("button", { name: "Inbox", exact: true }),
  ).toBeVisible();
  await page.reload();
  await expect(labels).toHaveAttribute("aria-expanded", "false");
  await labels.focus();
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("button", { name: "Projects", exact: true }),
  ).toBeVisible();
});
