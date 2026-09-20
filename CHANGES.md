# CHANGES

## 2026-07-16 — Menu bar icon: SF Symbol + pulse effect

Replaced the custom menu bar glyph with the system SF Symbol `envelope`,
hosted in an `NSImageView` inside the status button (symbol effects don't
attach to `NSStatusBarButton` directly). While a sync runs, the icon plays the
system **`.pulse` symbol effect** (repeating); the hand-rolled 0.1s-timer alpha
shimmer is gone. Disabled state stays dimmed (alpha 0.42). Custom MenuIcon
assets/SVG removed; app icon (icns) unchanged.

### How to test

Build + relaunch, watch the menu bar during a sync (Run Now): envelope pulses,
stops when idle.

## 2026-07-04 — App icon + menu bar glyph

Skeuomorphic envelope icon whose fold creases form a letter "A": side-flap
folds are the legs, the folded band is the crossbar. Simplified line version
for the menu bar.

- **`tools/AppIcon.svg`**, **`tools/MenuIcon.svg`** — vector sources.
- **`tools/render-svg.swift`**, **`tools/make-icons.sh`** — regenerate
  `MenuBarApp/Assets/` (AppIcon.icns via iconutil, MenuIcon.png/@2x).
- **`build-menu-app.sh`** copies Assets into Resources;
  **`Info.plist`** gains `CFBundleIconFile`.
- **`AMailApp.swift`** status item now uses the bundled `MenuIcon` template
  image (SF Symbol `envelope` fallback), per HIG: template black+alpha so the
  macOS 26 transparent menu bar tints it in light/dark.
- Legacy `.icns` route (Icon Composer `.icon` needs full Xcode's actool; this
  machine has CLT only). macOS 26 auto-applies its glass treatment to the icon.

### How to test

`./tools/make-icons.sh && ./build-menu-app.sh && open build/aMail.app` — check
the menu bar glyph (light + dark), and the icon in Finder on build/aMail.app.

## 2026-07-04 — Import hand-written mbsync accounts

One-time importer that adopts pre-existing, hand-written `~/.mbsyncrc` accounts
into aMail's managed config.

- **`MenuBarApp/AccountStore.swift`** — `MbsyncImporter.parse`: splits the config
  into stanza blocks (managed block passes through verbatim), joins
  Channel → IMAPStore → IMAPAccount + MaildirStore into `MailAccount`s, infers
  type from host, preserves `Patterns` verbatim, detects default vs custom
  folder, and parses the old keychain service/account out of `PassCmd`.
  `Keychain.readPassword(service:account:)` added for migration reads.
- **`MenuBarApp/AccountsUI.swift`** — `AccountStore.importFromMbsyncrc()`: copies
  each password to the `aMail: <slug>` keychain entry, backs the config up as
  `.mbsyncrc.aMail-backup`, strips the old stanzas, and regenerates the managed
  block. **Import…** button in the accounts footer with confirm/result alerts.
- **`MenuBarApp/AMailApp.swift`** — `--import-preview` CLI flag: prints what an
  import would do (candidates + residual config) without changing anything.
  `--import` runs the same flow headlessly.

### How to test

```bash
./build-menu-app.sh
build/aMail.app/Contents/MacOS/aMail --self-test        # includes importer asserts
build/aMail.app/Contents/MacOS/aMail --import-preview   # dry run against ~/.mbsyncrc
```

Then `open build/aMail.app`, menu → **Accounts…** → **Import…**, confirm, and
check that the two accounts appear, `~/.mbsyncrc` contains only the managed
block, the backup exists, and `security find-generic-password -s 'aMail: <slug>'
-a <email> -w` returns the password.

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
