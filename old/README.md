# Legacy Files

These files predate `../mail-sync.sh` and are kept only for reference.

- `mbsync-rotate.sh` is the older per-account rotator.
- `com.archive-mail.legacy-mbsync-rotate.plist` is an archived launchd plist
  template.
- `install-agent.sh` installs that archived plist.

Prefer the project root README and `../mail-sync.sh` for current use. If you
need this archived launchd flow, replace `/path/to/amail` in the plist
with your local checkout path and set `MAIL_SYNC_ACCOUNTS`.
