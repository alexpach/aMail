# RESEARCH

## 2026-06-23 — Account management UI (v0.10)

Goal: add a macOS UI to add/remove/edit mbsync accounts for Gmail, iCloud, and
generic IMAP, with credential storage, validation, and Maildir/notmuch wiring.

### Authentication (decided: app-specific passwords)

Gmail and iCloud both dropped plain-password IMAP. Realistic, low-infra path for
all three types is **username + app-specific password over IMAPS, `AuthMechs LOGIN`**:

- **Gmail** — account needs 2FA, then user generates a 16-char app password at
  <https://myaccount.google.com/apppasswords>. Host `imap.gmail.com:993`.
- **iCloud** — user generates an app-specific password at
  <https://appleid.apple.com> (Sign-In and Security). Host `imap.mail.me.com:993`.
- **Generic IMAP** — user supplies host/port/user/password directly.

Account *type* is therefore mostly a **preset** (default host/port + setup help).
One code path serves all three.

OAuth2/XOAUTH2 was rejected for this version: needs a Google Cloud OAuth client,
a token-refresh daemon, and the `cyrus-sasl-xoauth2` plugin for mbsync. iCloud
has no OAuth anyway. Revisit later if app passwords prove too clunky.

### Secret storage (macOS Keychain, never plaintext)

Passwords go in the login Keychain, not `~/.mbsyncrc`. mbsync reads them at sync
time via `PassCmd`:

```
PassCmd "security find-generic-password -s 'aMail: <slug>' -a '<email>' -w"
```

aMail writes them with (authorising the `security` reader to avoid prompts):

```
security add-generic-password -U -s 'aMail: <slug>' -a '<email>' \
  -w '<app-password>' -T /usr/bin/security
```

### ~/.mbsyncrc handling (managed block, preserve the rest)

aMail edits only a delimited region; everything else in the file is preserved:

```
# >>> aMail managed — do not edit by hand >>>
... generated stanzas ...
# <<< aMail managed <<<
```

Merge rule: if markers exist, replace between them; else append the block. The
existing sync engine already discovers accounts from `Channel` lines, so the new
stanzas are picked up with no change to `mail-sync.sh`.

### Generated stanzas (per account, slug `s`, archive base `B`)

```
IMAPAccount <s>
  Host <host>
  Port <port>
  User <email>
  PassCmd "security find-generic-password -s 'aMail: <s>' -a '<email>' -w"
  TLSType IMAPS
  AuthMechs LOGIN

IMAPStore <s>-remote
  Account <s>

MaildirStore <s>-local
  Path <B>/<s>/
  Inbox <B>/<s>/Inbox
  SubFolders Verbatim

Channel <s>
  Far :<s>-remote:
  Near :<s>-local:
  Patterns *
  Create Near
  Expunge None
  Remove None
  SyncState *
```

Archive-safe defaults: `Create Near` (build local folders), `Expunge None` +
`Remove None` (never delete archived mail). Advanced fields (AuthMechs, Patterns,
MaxSize, MaxMessages, port, TLSType) are editable in an Advanced disclosure.

### Maildir + notmuch

- Archive base dir configurable, default `~/MailArchive/`. Each account lives at
  `<base>/<slug>/`.
- On save: create `<base>/<slug>/` Maildir tree.
- notmuch must index the base dir. If `~/.notmuch-config` `database.path` does not
  cover the base, aMail warns in the UI (auto-fix is a stretch goal).

### Slug rules

- Slug derived live from the account name (lowercase, spaces→`-`, strip non
  `[a-z0-9-]`, collapse repeats). Editable.
- Slug must be unique and non-empty; it names the folder, the mbsync
  Channel/Store, and the Keychain item.
- Editing the slug of an existing account → warn, offer to rename
  `<base>/<oldslug>` → `<base>/<newslug>` and rewrite paths + Keychain item.
- Deleting an account → confirm; ask whether to also delete `<base>/<slug>`.

### Validation

- Input: email shape, non-empty fields, port 1–65535, unique valid slug,
  writable base dir.
- Credentials: **Test** button writes a throwaway 0600 config to a temp dir with
  the typed password and runs `mbsync --list <tmpchannel>`; exit 0 + folder list =
  pass; scan stderr for `AUTHENTICATIONFAILED` / `LOGIN failed`. Temp trashed after.

### UI (SwiftUI hosted in AppKit, macOS 26)

- New menu item **Accounts…** opens an `NSWindow` hosting a SwiftUI `AccountsView`.
- List of accounts + toolbar `+` / `–`; click to edit.
- Editor sheet: Name, Type picker, type-specific login fields, SecureField +
  Test, Advanced disclosure. Grouped form style.
- Global control for the archive base folder (NSOpenPanel chooser).

### Build

- Split Swift into `AMailApp.swift`, `AccountStore.swift`, `AccountsUI.swift`.
- `build-menu-app.sh` compiles `MenuBarApp/*.swift` and links `-framework SwiftUI`.

### Tests (`aMail --self-test`, mirrors the shell `--self-test`)

Pure-logic asserts, no GUI: slug generation, stanza generation, managed-block
merge (foreign content preserved), parse-back of generated channels, Keychain
service-name derivation.
