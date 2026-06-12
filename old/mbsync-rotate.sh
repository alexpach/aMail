#!/opt/homebrew/bin/bash
set -u
set -o pipefail

# Legacy script. Prefer ../mail-sync.sh for current use.
#
# Accounts to rotate through. Set MAIL_SYNC_ACCOUNTS to a space-separated list
# of mbsync channel names before running this archived script.
if [ -n "${MAIL_SYNC_ACCOUNTS:-}" ]; then
  read -r -a ACCOUNTS <<< "$MAIL_SYNC_ACCOUNTS"
else
  ACCOUNTS=()
fi

# Cooldowns in seconds. Override via env at launch.
SUCCESS_BACKOFF="${SUCCESS_BACKOFF:-3600}"      # 1h between successful pulls per account
QUOTA_BACKOFF="${QUOTA_BACKOFF:-7200}"          # 2h after quota / rate limit
CONNECTION_BACKOFF="${CONNECTION_BACKOFF:-600}" # 10m after network blip
ERROR_BACKOFF="${ERROR_BACKOFF:-900}"           # 15m after unknown error
IDLE_CYCLE_SLEEP="${IDLE_CYCLE_SLEEP:-300}"     # cap on idle wakeup; recheck every 5m

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LOG_DIR="${LOG_DIR:-${PROJECT_DIR}/logs}"
LOGFILE="${LOGFILE:-${LOG_DIR}/mbsync-rotate.log}"
VERBOSE_LOG="${VERBOSE_LOG:-${LOG_DIR}/mbsync-rotate.verbose.log}"
NOTMUCH_BIN="${NOTMUCH_BIN:-/opt/homebrew/bin/notmuch}"
MBSYNC_BIN="${MBSYNC_BIN:-/opt/homebrew/bin/mbsync}"

NEXT_OK_AT=()
for ((i=0; i<${#ACCOUNTS[@]}; i++)); do
  NEXT_OK_AT+=(0)
done

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
now_ts()    { date +%s; }

# Clean one-line summary log
log() {
  printf '[%s] %s\n' "$(timestamp)" "$*" | tee -a "$LOGFILE" >&2
}

# Verbose only (raw mbsync progress, separator banners)
vlog() {
  printf '[%s] %s\n' "$(timestamp)" "$*" >> "$VERBOSE_LOG"
}

# Parse the last "Channels: ... Far: ... Near: ..." line from a captured
# mbsync transcript. Returns "near_new near_flag near_expunge far_new far_flag far_expunge"
# or empty string if not found.
parse_mbsync_summary() {
  local file="$1"
  # Strip CR (mbsync rewrites progress with \r), grab final summary line
  local line
  line=$(tr '\r' '\n' < "$file" | rg -N '^Channels:[[:space:]]' | tail -n1)
  [ -z "$line" ] && return 1

  # Far: +A *B #C -D    Near: +E *F #G -H
  local far_new far_flag far_exp near_new near_flag near_exp
  far_new=$(  echo "$line" | sed -nE 's/.*Far:[[:space:]]+\+([0-9]+).*/\1/p')
  far_flag=$( echo "$line" | sed -nE 's/.*Far:[[:space:]]+\+[0-9]+[[:space:]]+\*([0-9]+).*/\1/p')
  far_exp=$(  echo "$line" | sed -nE 's/.*Far:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#([0-9]+).*/\1/p')
  near_new=$( echo "$line" | sed -nE 's/.*Near:[[:space:]]+\+([0-9]+).*/\1/p')
  near_flag=$(echo "$line" | sed -nE 's/.*Near:[[:space:]]+\+[0-9]+[[:space:]]+\*([0-9]+).*/\1/p')
  near_exp=$( echo "$line" | sed -nE 's/.*Near:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#([0-9]+).*/\1/p')

  echo "${near_new:-0} ${near_flag:-0} ${near_exp:-0} ${far_new:-0} ${far_flag:-0} ${far_exp:-0}"
}

# Run mbsync for one account. Side-effect: writes summary line to $LOGFILE.
# Echoes "near_new near_flag near_exp far_new far_flag far_exp" on success, empty on failure.
# Returns: 0 ok, 11 quota, 12 connection, 20 unknown error.
run_sync() {
  local account="$1"
  local tmpfile status summary
  tmpfile="$(mktemp -t mbsync-rotate)"

  vlog "===== mbsync $account ====="
  # `script` keeps mbsync's TTY-style progress output usable; pipe to verbose log + tmpfile.
  script -q /dev/null "$MBSYNC_BIN" "$account" 2>&1 | tee -a "$VERBOSE_LOG" > "$tmpfile"
  status=${PIPESTATUS[0]}

  summary="$(parse_mbsync_summary "$tmpfile" || true)"

  if [ "$status" -eq 0 ]; then
    if [ -n "$summary" ]; then
      read -r nn nf ne fn ff fe <<<"$summary"
      log "sync ok    $account  near +${nn}/*${nf}/#${ne}  far +${fn}/*${ff}/#${fe}"
    else
      log "sync ok    $account  (no summary parsed)"
    fi
    trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
    [ -n "$summary" ] && echo "$summary"
    return 0
  fi

  if rg -qi 'OVERQUOTA|exceeded command or bandwidth limits|rate limit|too many simultaneous connections' "$tmpfile"; then
    log "sync quota $account  (rate-limited; backing off ${QUOTA_BACKOFF}s)"
    trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
    return 11
  fi
  if rg -qi 'unexpected BYE|timeout|Socket error|Connection reset|Network is down|No route to host' "$tmpfile"; then
    log "sync neterr $account (connection issue; backing off ${CONNECTION_BACKOFF}s)"
    trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
    return 12
  fi

  log "sync FAIL  $account  (exit=$status; backing off ${ERROR_BACKOFF}s; see verbose log)"
  trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
  return 20
}

# Run notmuch new. Echoes "added removed renamed" or empty on failure.
run_notmuch() {
  local tmpfile status added removed renamed
  tmpfile="$(mktemp -t mbsync-rotate-nm)"

  vlog "===== notmuch new ====="
  "$NOTMUCH_BIN" new 2>&1 | tee -a "$VERBOSE_LOG" > "$tmpfile"
  status=${PIPESTATUS[0]}

  if [ "$status" -ne 0 ]; then
    log "notmuch FAIL (exit=$status; see verbose log)"
    trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
    return 1
  fi

  added=$(  rg -oN 'Added [0-9]+ new message'   "$tmpfile" | rg -oN '[0-9]+' | tail -n1)
  removed=$(rg -oN 'Removed [0-9]+ message'      "$tmpfile" | rg -oN '[0-9]+' | tail -n1)
  renamed=$(rg -oN 'Detected [0-9]+ file rename' "$tmpfile" | rg -oN '[0-9]+' | tail -n1)
  added=${added:-0}; removed=${removed:-0}; renamed=${renamed:-0}

  log "notmuch ok added=${added} removed=${removed} renamed=${renamed}"
  trash "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
  return 0
}

main() {
  if [ "${#ACCOUNTS[@]}" -eq 0 ]; then
    echo "Set MAIL_SYNC_ACCOUNTS before running this legacy script." >&2
    exit 64
  fi

  mkdir -p "$LOG_DIR"
  log "rotation started (success=${SUCCESS_BACKOFF}s quota=${QUOTA_BACKOFF}s conn=${CONNECTION_BACKOFF}s err=${ERROR_BACKOFF}s)"

  local i account rc now ran_any earliest_next_ok sleep_for any_success
  local cycle=0

  while true; do
    cycle=$((cycle+1))
    ran_any=0
    any_success=0
    earliest_next_ok=0
    now="$(now_ts)"

    for ((i=0; i<${#ACCOUNTS[@]}; i++)); do
      account="${ACCOUNTS[$i]}"

      if [ "$now" -lt "${NEXT_OK_AT[$i]}" ]; then
        if [ "$earliest_next_ok" -eq 0 ] || [ "${NEXT_OK_AT[$i]}" -lt "$earliest_next_ok" ]; then
          earliest_next_ok="${NEXT_OK_AT[$i]}"
        fi
        continue
      fi

      ran_any=1
      run_sync "$account" >/dev/null
      rc=$?

      case "$rc" in
        0)  NEXT_OK_AT[i]=$(( $(now_ts) + SUCCESS_BACKOFF ));    any_success=1 ;;
        11) NEXT_OK_AT[i]=$(( $(now_ts) + QUOTA_BACKOFF )) ;;
        12) NEXT_OK_AT[i]=$(( $(now_ts) + CONNECTION_BACKOFF )) ;;
        20) NEXT_OK_AT[i]=$(( $(now_ts) + ERROR_BACKOFF )) ;;
      esac

      if [ "$earliest_next_ok" -eq 0 ] || [ "${NEXT_OK_AT[$i]}" -lt "$earliest_next_ok" ]; then
        earliest_next_ok="${NEXT_OK_AT[$i]}"
      fi
    done

    if [ "$any_success" -eq 1 ]; then
      run_notmuch || true
    fi

    now="$(now_ts)"
    if [ "$earliest_next_ok" -gt "$now" ]; then
      sleep_for=$(( earliest_next_ok - now ))
      [ "$sleep_for" -gt "$IDLE_CYCLE_SLEEP" ] && sleep_for="$IDLE_CYCLE_SLEEP"
    else
      sleep_for=30
    fi

    if [ "$ran_any" -eq 0 ]; then
      vlog "cycle ${cycle}: all cooling down; sleeping ${sleep_for}s"
    else
      vlog "cycle ${cycle}: sleeping ${sleep_for}s"
    fi
    sleep "$sleep_for"
  done
}

main
