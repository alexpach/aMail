# aMail web client

A local, read-only Gmail client at **http://localhost:10014**. It is independent of the existing macOS archive app, mbsync and notmuch. It never runs synchronization, touches the mail archive, or writes to Gmail.

## Run

Requires Node.js 22.12 or newer and npm. Run these commands from the aMail project root:

```sh
npm --prefix webapp ci
npm --prefix webapp run build
npm --prefix webapp start
```

Open http://localhost:10014 and choose **Connect Gmail**. Approve Gmail read-only access in Google's consent screen. The backend listens only on IPv4 loopback, and accepts the `localhost:10014` host. Use the exact URL above, not the IP address.

The default credential location is your existing aMail web-client JSON under:

```text
~/src/aMail/webapp/client_secret_293210038341-j7gm5dkepijelhi9sf85e4i7hbhn2sr1.apps.googleusercontent.com.json
```

The backend reads that file directly, including when running from a worktree. It does not copy the secret into the frontend. To use another web-client JSON:

```sh
AMAIL_CLIENT_SECRET="/absolute/path/to/client_secret.json" npm --prefix webapp start
```

Google Cloud configuration:

- Gmail API enabled.
- Exact authorized redirect: `http://localhost:10014/api/oauth/callback`.
- Only scope: `https://www.googleapis.com/auth/gmail.readonly`.
- Authorized JavaScript origins can remain blank, because the backend handles OAuth.
- Add your account as a test user if the consent screen is in testing mode.

Tokens are stored in `webapp/.private/tokens.json` with mode 0600 inside a mode 0700 directory. That directory and client-secret JSON files are ignored by this checkout's `.gitignore`. Keep the ignore changes when transferring the implementation to the original checkout, whose existing untracked credential file is not copied or changed here. Tokens are not encrypted at rest; filesystem permissions restrict local access. Never commit or share the token store.

## What works

- Latest 100 matching messages per page, with next/previous pages.
- Inbox, Starred, Sent, Drafts and Spam. Draft messages can be viewed but not edited.
- Mailbox-wide Gmail search. Submitting search replaces the active view filter. Gmail normally excludes Spam and Trash; use `in:anywhere` to include them.
- Persistent search/header, pushing sidebar, day groups, labels with Gmail colors, attachment and invitation indicators.
- Local selection, including select all on the current page and select unread. Selection never changes Gmail.
- Named search tabs. Add, edit, reorder, remove or restore defaults under profile settings. These settings are saved in this browser only.
- Plain text and sanitized HTML bodies, MIME header/charset decoding, CID raster images, attachment downloads, full headers and original RFC 2822 source.
- Refresh tokens, one-time browser-bound OAuth state, ten-minute state expiry, PKCE, reconnection messages, origin checks and a strict GET-only Gmail resource allowlist.

Reading a message does not mark it read. Stars are display-only. Reply and delete controls are disabled and labeled unavailable. There is no send, draft creation, label change, archive action, trash action, composer, local raw-message archive or offline sync engine.

## Saved searches and star colors

Primary is `in:inbox`, not `category:primary`. Today uses `in:inbox after:{today}`; `{today}` expands to local midnight as an epoch timestamp. Investors initially searches `label:Investors`; edit that query for your actual label or contacts. Archived means messages outside Inbox, Sent, Drafts, Spam and Trash, not the local mail archive. Purchases uses Gmail's purchases category.

Gmail message data exposes the generic `STARRED` label but no color field. General lists therefore show neutral stars. Color tabs submit `has:yellow-star`, `has:red-star`, `has:green-star`, `has:blue-star` or `has:purple-star` to Gmail. When the view consists of one exact color query, the icon color is inferred from that filter, not from message metadata. These operators are documented for Gmail search; their results still require live verification with your account. The API supports most Gmail search syntax, with documented differences such as alias expansion and thread-wide searching. This UI lists individual messages, not collapsed threads.

References: [Gmail search operators](https://support.google.com/mail/answer/7190), [API search differences](https://developers.google.com/workspace/gmail/api/guides/filtering), [message resource](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages).

## Email rendering and privacy

Email HTML passes through a tag, attribute, URL and CSS allowlist, then renders in a sandboxed iframe without scripts or same-origin privileges and with its own restrictive Content Security Policy. Forms, scripts, embedded frames, SVG, arbitrary CSS URLs and event handlers are removed. Inline raster CID images below 5 MB render as data URLs. HTTPS remote images load only after **Load images for this message**; that opt-in resets on opening another message. Loading remote images can contact sender tracking servers. HTTP images and remote CSS remain blocked.

Complex email styling may be simplified. The viewer has an independent scroll area for long HTML mail. Attachments download as octet-stream with an attachment disposition, including HTML attachments. Raw source is fetched only when requested and displayed as text. Messages are held only in a bounded short-lived memory cache; the backend never writes message content to disk. No token or credential values are returned to the browser or logged.

## Verify

```sh
npm --prefix webapp run build
npm --prefix webapp test
npm --prefix webapp run test:browser-install
npm --prefix webapp run test:ui
```

The browser tests use an isolated synthetic mailbox at port 10015 and Playwright's matched Chromium headless shell. Install the test browser once with `test:browser-install`. They do not load credentials, access real Gmail, or grant consent. The browser, screenshots and traces go under `tmp/`. Tests cover inbox/search/pagination, selection, saved tabs and persistence, responsive layout, message opening, headers/source, attachment downloads, HTML sandboxing and remote-image opt-in policy. Backend tests cover OAuth state/PKCE, expiry/replay, private token permissions, refresh, read-only routes, origin checks and MIME sanitization.

Live Google consent and account-specific results cannot be validated by fixture tests. Open the app and connect before treating live Gmail as verified.

## Troubleshooting

- **Port in use:** stop the earlier aMail web server before starting another one. The port is fixed to match the registered callback.
- **Missing credentials:** set `AMAIL_CLIENT_SECRET` to your Google OAuth web-client JSON and restart.
- **Redirect mismatch:** check the callback exactly, including `http`, `localhost`, port and path.
- **Expired/revoked access:** reconnect through the profile menu. Google testing-mode refresh grants can expire after seven days.
- **Local session expired:** reload the page. Browser sessions live in server memory and expire after 24 hours or a server restart.
- **No mail in Investors or a color tab:** check the query in Gmail and adjust the saved view. No label or star colors are fabricated by aMail.

## UI source

The interface uses [Spectrum UI](https://ui.spectrumhq.in)'s actual Button primitive and an adapted TaskCheckbox. The latter retains its spring interaction, animated check and reduced-motion behavior, with confetti and task strikethrough removed for mail selection. Source URLs and license are recorded in `THIRD_PARTY.md`. Radix provides accessible menus and dialogs; other mail-specific components are local React components.

## API activity and request limits

Local diagnostics are written to `webapp/.private/api-activity.jsonl` (0600). The log rotates at 2 MB, keeping one previous file with suffix `.1`. It records operation names, status codes, safe error categories, durations, estimated quota units, cache hits, local throttling and browser request failures. It never records message contents, addresses, search text, message IDs, URLs, credentials, tokens or Google error descriptions.

Message data and labels/profile are cached for five minutes; result lists for 30 seconds. Returning from a message reuses cached data. Refresh explicitly reloads the current view. Concurrent duplicate cache reads share work. Hydration stops scheduling new messages after a failure or browser disconnect.

Gmail calls are paced at four starts per second with at most three active requests and a bounded waiting queue. A conservative rolling budget of 4,000 estimated quota units per minute applies per server process. These estimates use Google's May 2026 costs (20 for message/attachment reads, 5 for message lists, 1 for label/profile reads). They are not Google's authoritative account usage and reset when the server restarts. Other clients or server instances have separate local counters. See [Google's quota reference](https://developers.google.com/workspace/gmail/api/reference/quota).

Quota errors (including Gmail 403 rate-limit responses) pause calls for at least 60 seconds and respect longer `Retry-After` values. Transient server failures pause for at least five seconds. The UI displays the delay without requiring a fresh login. After the delay, use Retry or Refresh. Errors are not automatically retried in a loop. Actual 401 errors get one token refresh attempt.

## Icons

The native app icon, menu bar icon, and browser favicon use the macOS SF Symbol `envelope.open.fill`. Run `./tools/make-icons.sh` from the project root on macOS to regenerate the ICNS and PNG assets using `tools/render-symbol.swift`, then rebuild the web client. The earlier SVG artwork is retained as an unused source asset.
