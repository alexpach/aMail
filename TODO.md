# TODO

## v0.10 — Account management UI

### Queued
- [ ] Manual UI smoke test on a real macOS 26 desktop (add/edit/delete each type).
- [ ] Stretch: one-click "Fix notmuch config" instead of just warning.
- [ ] Decide whether to bump deployment target to 26 for 26-only APIs.
- [ ] Release: build `RELEASE=1`, tag v0.10.0, attach zip (after manual test).

### Completed (2026-06-23)
- [x] Model + serializer (`AccountStore.swift`).
- [x] Managed-block merge, preserves foreign content, atomic write.
- [x] Keychain store/read/delete via `security`.
- [x] Validation: input checks + `mbsync --list` credential test (temp 0600 config).
- [x] Maildir creation + notmuch coverage warning.
- [x] `aMail --self-test` (15 asserts: slug, stanza, merge round-trip, validation).
- [x] SwiftUI UI: list, editor sheet, type-specific fields, Test, folder chooser.
- [x] Slug rename flow (warn + rename folder + move Keychain item).
- [x] Delete flow (confirm; optional local-store deletion).
- [x] "Accounts…" menu item + window hosting.
- [x] Build compiles `MenuBarApp/*.swift` with SwiftUI.
- [x] Validated: `bash -n`, both `--self-test`s, shellcheck, full build.
