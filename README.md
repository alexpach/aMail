# aMail

aMail means Archive Mail. It is a small macOS menu bar app that downloads,
archives, and indexes your mail with proven Unix mail tools:

- `mbsync` downloads mail into a local archive.
- `notmuch` indexes the archive for fast search and mailbox counts.
- aMail provides menu bar controls, status, logs, and recent-mail stats.

The app is intentionally lightweight. It does not replace `mbsync` or
`notmuch`; it wraps them in a macOS controller that is easier to keep running.

## Features

- Runs continuous mail syncs in the background.
- Discovers accounts from your `mbsync` config.
- Runs `notmuch new` after new messages are downloaded.
- Shows current sync state from the menu bar.
- Provides a `Run Now` command to trigger an immediate pass.
- Opens live logs without leaving the app.
- Opens your `mbsync` config in an editor.
- Manages mail accounts from a UI: add/remove/edit Gmail, iCloud, or IMAP.
- Checks for required dependencies and config before starting sync.
- Shows recent new-mail totals for 1 hour, 24 hours, 7 days, and 30 days.
- Shows current mailbox totals from `notmuch count`.
- Can launch at login.

## Requirements

aMail targets macOS 14 or newer (the account UI uses modern SwiftUI) and expects:

- Homebrew Bash (the system `/bin/bash` 3.2 is too old)
- `mbsync`
- `notmuch`
- `nc` or `ping` for connectivity checks
- `/usr/bin/script` for cleaner `mbsync` progress capture
- Swift command line tools to build the app from source

Install the mail tools with Homebrew:

```bash
brew install isync notmuch
```

`isync` provides the `mbsync` executable.

aMail checks these common executable paths:

```text
/opt/homebrew/bin
/usr/local/bin
/usr/bin
/bin
```

## Install (Prebuilt)

Download `aMail-<version>.zip` from the
[Releases](https://github.com/alexpach/aMail/releases) page, unzip it, and move
`aMail.app` to `/Applications`.

The app is ad hoc signed, not notarized. On first launch Gatekeeper blocks it:
right-click the app, choose **Open**, then confirm. One time only.

A prebuilt app keeps its runtime files under Application Support, not in a
checkout:

```text
~/Library/Application Support/aMail/logs/
~/Library/Application Support/aMail/tmp/
```

You still need `mbsync` and `notmuch` installed and a readable `~/.mbsyncrc`
(see Requirements and Mail Configuration).

## Managing Accounts

The menu item **Accounts…** (⌘A) opens an account manager. Click **+**, pick a
type, and fill in the login:

- **Gmail** — turn on 2-Step Verification, then create an app password at
  [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords).
- **iCloud** — create an app-specific password at
  [appleid.apple.com](https://appleid.apple.com) (Sign-In and Security).
- **IMAP** — enter host, port, email, and password directly.

The **Test** button verifies the credentials by listing mailboxes with `mbsync`
before you save. Passwords are stored in the macOS Keychain — never in
`~/.mbsyncrc`, which receives only a `PassCmd` that reads the Keychain at sync
time.

Each account is named; aMail derives a **slug** from the name and uses it for the
local folder, the mbsync channel, and the Keychain item. Mail is archived under a
configurable base folder (default `~/MailArchive/`) at `<base>/<slug>/`, or at a
per-account folder you set in the editor's Advanced section. Changing an
account's folder (via the slug or the folder field) offers to move the existing
mail and rewrite paths; deleting an account asks whether to also delete its local
archive.

aMail edits only a managed region of `~/.mbsyncrc`:

```text
# >>> aMail managed — do not edit by hand >>>
...generated account stanzas...
# <<< aMail managed <<<
```

Anything outside that region is left untouched, so hand-written stanzas are safe.
For search and mailbox counts, `notmuch`'s `database.path` must cover the archive
base; aMail warns in the UI if it does not.

## Mail Configuration

aMail reads your `mbsync` config from:

```text
~/.mbsyncrc
```

The config must contain one or more `Channel` entries. Example:

```text
Channel personal
Channel work
```

The menu includes `Open mbsync Config`, which opens this file in your default
editor. If you need a different config path, launch aMail with `MBSYNC_CONFIG`
set in the environment.

You also need a working `notmuch` configuration for the local mail archive.

## Build

Build the app:

```bash
./build-menu-app.sh
```

The generated app is:

```text
build/aMail.app
```

Open it:

```bash
open build/aMail.app
```

The build script signs the app ad hoc when `codesign` is available. The app is
not notarized.

For a self-contained app to distribute (bundles `mail-sync.sh`, writes runtime
files to Application Support, no machine-specific paths), build with:

```bash
RELEASE=1 ./build-menu-app.sh
```

Build target defaults:

```text
ARCH=$(uname -m)
MACOSX_DEPLOYMENT_TARGET=14.0
TARGET=$ARCH-apple-macosx14.0
```

Override them when needed:

```bash
ARCH=x86_64 ./build-menu-app.sh
```

## Using The App

The menu includes:

- `Turn Sync On` / `Turn Sync Off`
- `Run Now`
- `Open Logs`
- `Open mbsync Config`
- `Launch at Login`
- `Quit`

The compact menu shows dependency readiness, mailbox totals when available, and
new mail by account. The logs window shows a larger dashboard plus a live log
viewer.

## Metrics

aMail separates two kinds of stats:

- `New mail` comes from `logs/mail-sync.log`. It counts messages that `mbsync`
  downloaded in the last 1 hour, 24 hours, 7 days, and 30 days.
- `Mailbox` comes from `notmuch count`. It shows current total, unread, and
  inbox message counts. These counts refresh every 30 seconds while the app is
  open.

This avoids treating `notmuch new` as a per-account counter. `notmuch new`
scans the configured database, so its "added" count is not always the same as
one account's downloaded count.

## Runtime Files

Runtime files are kept out of the source root:

```text
logs/mail-sync.log
logs/mail-sync.verbose.log
tmp/mail-sync.lock/
```

These directories are ignored by Git. The runner caps each log at startup of
every cycle (clean log ~5000 lines, verbose log ~20000) so they do not grow
without bound.

Follow the clean log:

```bash
tail -f logs/mail-sync.log
```

Inspect raw command output:

```bash
tail -100 logs/mail-sync.verbose.log
```

Check the active sync PID:

```bash
cat tmp/mail-sync.lock/pid
ps -p "$(cat tmp/mail-sync.lock/pid)"
```

## Command Line Sync

The app runs `mail-sync.sh` internally. You can also run it directly.

List configured channels:

```bash
./mail-sync.sh --list-accounts
```

Run continuously:

```bash
./mail-sync.sh
```

Run one pass:

```bash
./mail-sync.sh --once
```

Run a subset of accounts:

```bash
MAIL_SYNC_ACCOUNTS="personal work" ./mail-sync.sh --once
```

## Configuration

All runtime configuration is via environment variables.

| Variable | Default | Description |
| --- | ---: | --- |
| `PROJECT_DIR` | script directory | Project root for runtime paths. |
| `LOG_DIR` | `$PROJECT_DIR/logs` | Directory for clean and verbose logs. |
| `TMP_DIR` | `$PROJECT_DIR/tmp` | Directory for locks and temp files. |
| `MBSYNC_CONFIG` | `$HOME/.mbsyncrc` | `mbsync` configuration file. |
| `MAIL_SYNC_ACCOUNTS` | unset | Optional space-separated account/channel list. |
| `LOGFILE` | `$LOG_DIR/mail-sync.log` | Clean summary log path. |
| `VERBOSE_LOG` | `$LOG_DIR/mail-sync.verbose.log` | Raw command output log path. |
| `LOCK_DIR` | `$TMP_DIR/mail-sync.lock` | Lock directory preventing duplicate runs. |
| `MBSYNC_BIN` | `mbsync` | `mbsync` executable. |
| `NOTMUCH_BIN` | `notmuch` | `notmuch` executable. |
| `SCRIPT_BIN` | `/usr/bin/script` | TTY capture helper for `mbsync`. |
| `SUCCESS_SLEEP` | `900` | Seconds to sleep after a normal sync pass. |
| `QUOTA_BACKOFF` | `7200` | Seconds to skip an account after quota/rate-limit errors. |
| `NO_INTERNET_BACKOFF` | `300` | Seconds to sleep when connectivity check fails. |
| `CONNECTIVITY_HOST` | `imap.gmail.com` | Host checked before sync. |
| `CONNECTIVITY_PORT` | `993` | Port checked before sync. |
| `CONNECTIVITY_TIMEOUT` | `5` | Connectivity timeout in seconds. |
| `RUN_NOW_CHECK_INTERVAL` | `5` | Seconds between manual run checks while sleeping. |

## Project Layout

| Path | Purpose |
| --- | --- |
| `MenuBarApp/` | Swift/AppKit app source. |
| `mail-sync.sh` | Sync backend used by the app and CLI. |
| `build-menu-app.sh` | No-Xcode build script. |
| `build/` | Generated app and compiler output. Ignored by Git. |
| `logs/` | Runtime logs. Ignored by Git. |
| `tmp/` | Runtime locks and temp files. Ignored by Git. |

## Validation

Check shell syntax:

```bash
bash -n mail-sync.sh
```

Run ShellCheck if installed:

```bash
shellcheck mail-sync.sh build-menu-app.sh
```

Run the parser self-test:

```bash
./mail-sync.sh --self-test
```

Run the account-logic self-test (after building):

```bash
build/aMail.app/Contents/MacOS/aMail --self-test
```

Build the app:

```bash
./build-menu-app.sh
```
