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
- Checks for required dependencies and config before starting sync.
- Shows recent new-mail totals for 1 hour, 24 hours, 7 days, and 30 days.
- Shows current mailbox totals from `notmuch count`.
- Can launch at login.

## Requirements

aMail currently targets macOS and expects:

- Bash
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

Build target defaults:

```text
ARCH=$(uname -m)
MACOSX_DEPLOYMENT_TARGET=13.0
TARGET=$ARCH-apple-macosx13.0
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

Build the app:

```bash
./build-menu-app.sh
```
