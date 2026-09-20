# RESEARCH

## 2026-07-04 — macOS 26 (Tahoe) / Liquid Glass design adoption

Goal: make aMail match Apple's macOS 26 HIG. New design language is **Liquid
Glass** (WWDC 2025): translucent functional layer (bars, controls, menus)
floating over content; transparent menu bar; layered app icons; rounder
window corners and controls.

### Where we stand (good news)

- This machine runs **macOS 26.5.2** and builds against **SDK 26.5**
  (`build-menu-app.sh` uses `xcrun --sdk macosx`). Linking the macOS 26 SDK is
  the opt-in: **standard chrome auto-adopts Liquid Glass on recompile** — menus,
  sheets, alerts, window corners, control shapes. Our current builds already
  get this. Opt-out (not wanted) would be `UIDesignRequiresCompatibility` in
  Info.plist.
- Status item follows HIG already: template SF Symbol (`envelope`), works on
  the now-transparent menu bar. `NSMenu` + `NSAlert` are system-rendered → free.
- All colors are semantic (`.labelColor`, `.secondary`, …), fonts are system →
  adapt automatically, including Reduce Transparency / Increase Contrast.
- HIG rule that helps us: **don't apply glass to the content layer, use it
  sparingly** — standard components pick it up automatically. Most of aMail
  needs *removal of nothing and addition of little*.

### Gaps, ranked

1. **App icon — the big one.** aMail ships **no icon at all** (no .icns, no
   assets). macOS 26 icons are layered Liquid Glass, built with **Icon
   Composer** (free Apple app, needs macOS 26.4+; we're on 26.5): 1024×1024
   square canvas, background layer + up to 4 foreground layers, system applies
   rounded-rect mask + specular/refraction, six appearance variants (default /
   dark / clear light+dark / tinted light+dark — system can derive the rest).
   Output is a `.icon` bundle; compiling it into the app needs `actool` from
   full Xcode 26 (**not installed** — only CLT; `xcodebuild` missing). Fallback:
   also export a classic `.icns` (macOS auto-wraps legacy icons in a glass
   slab); CLT-only pipeline = `iconutil` for .icns, works today.
2. **Accounts window footer → toolbar.** Buttons (+ / − / Import… / archive
   chooser) sit in a hand-rolled footer `HStack`. The macOS 26 way: window
   `.toolbar` items (glass, grouped with `ToolbarSpacer`), or at minimum
   `.buttonStyle(.glass)` on the primary action. `Form`/`.formStyle(.grouped)`
   and `.sheet` auto-update — leave alone.
3. **Hardcoded layout metrics.** Editor `.frame(width:480,height:560)`, footer
   `.padding(12)`, dashboard's hand-tuned spacing — HIG says don't hard-code;
   controls got rounder/bigger and may clip. Needs a visual pass, not a rewrite.
4. **Logs window.** Custom `NSBox` dashboard = content layer → correctly stays
   plain (no glass). Optional polish: real `NSToolbar` for actions, and
   `NSGlassEffectView` only if we ever float controls over the log text.
5. **Availability guards.** Deployment target is 14.0; new APIs
   (`glassEffect`, `.buttonStyle(.glass)`, `ToolbarSpacer`,
   `NSGlassEffectView`, `scrollEdgeEffectStyle`) need
   `if #available(macOS 26.0, *)` — or bump `MACOSX_DEPLOYMENT_TARGET`/
   `LSMinimumSystemVersion` to 26.0 and drop the guards (simplest; this is a
   personal tool on a 26.5 machine).

### API cheat sheet (macOS 26)

- SwiftUI: `glassEffect(_:in:)`, `GlassEffectContainer` (batch/morph custom
  glass), `.buttonStyle(.glass)` / `.glassProminent`, `ToolbarSpacer`,
  `scrollEdgeEffectStyle(_:for:)`, `safeAreaBar`, `backgroundExtensionEffect()`.
- AppKit: `NSGlassEffectView`, `NSButton.BezelStyle.glass`,
  `NSToolbarItem.Identifier.space`, `NSToolbarItem.isHidden`,
  `NSBackgroundExtensionView`.
- Materials: `.regular` glass for text-heavy surfaces; `.clear` only over rich
  media (needs 35% dim layer on bright content). Vibrant colors on glass.

### Proposed plan

1. App icon: design layered envelope icon in Icon Composer → `.icon` +
   `.icns` fallback; wire into build script + Info.plist. (Needs decision:
   install full Xcode 26 for actool, or .icns-only for now.)
2. Bump deployment target to 26.0, re-test.
3. Accounts window: move footer actions into `.toolbar`, glass prominent Save,
   visual pass on paddings/frames.
4. Verify menu custom views + logs dashboard under transparent menu bar,
   Reduce Transparency, dark mode.

### Sources

- [Adopting Liquid Glass (Apple)](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Liquid Glass overview (Apple)](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass)
- [HIG — Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials)
- [HIG — The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- [HIG — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Icon Composer](https://developer.apple.com/icon-composer/) ·
  [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer)
- [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) ·
  [Meet Liquid Glass — WWDC25](https://developer.apple.com/videos/play/wwdc2025/219)
- [Apple newsroom — new software design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- Community field notes: [Updating app icons for macOS 26](https://successfulsoftware.net/2025/09/26/updating-application-icons-for-macos-26-tahoe-and-liquid-glass/),
  [praeclarum on app icons](https://praeclarum.org/2025/09/12/app-icons.html)

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
