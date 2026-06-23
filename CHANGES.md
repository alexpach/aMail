# CHANGES

## 2026-06-23 — Account management UI (v0.10, unreleased)

Added a UI to add/remove/edit mbsync accounts (Gmail, iCloud, generic IMAP).

- **`MenuBarApp/AccountStore.swift`** — account model, slug derivation, mbsyncrc
  stanza generation, managed-block merge (preserves hand-written config),
  Keychain storage via `security`, input + credential validation, and an
  `AccountRepository` for persistence / Maildir creation / notmuch checks.
- **`MenuBarApp/AccountsUI.swift`** — SwiftUI accounts list + editor sheet with a
  type picker, type-specific login fields, live **Test** button, Advanced
  disclosure, archive-folder chooser, slug-rename and delete-with-store prompts.
- **`MenuBarApp/AMailApp.swift`** — "Accounts…" menu item (⌘A), window hosting,
  and a `--self-test` mode.
- Metadata source of truth: `~/Library/Application Support/aMail/accounts.json`.
  The `~/.mbsyncrc` managed block is regenerated from it, so `mail-sync.sh`
  discovers the accounts unchanged.
- Deployment target raised 13.0 → 14.0 (modern SwiftUI).

### How to test

```bash
./build-menu-app.sh
build/aMail.app/Contents/MacOS/aMail --self-test   # account-logic asserts
./mail-sync.sh --self-test                          # sync-parser asserts
shellcheck mail-sync.sh build-menu-app.sh
```

Then `open build/aMail.app`, menu → **Accounts…**, add a Gmail/iCloud/IMAP
account with an app password, click **Test**, Save, and confirm a `Channel`
stanza appears inside the managed block of `~/.mbsyncrc`.
