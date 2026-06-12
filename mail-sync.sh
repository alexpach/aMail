#!/opt/homebrew/bin/bash
set -u
set -o pipefail

# Continuous, quota-aware mbsync runner with concise human-readable logs.
# Channel names are discovered from ~/.mbsyncrc unless MAIL_SYNC_ACCOUNTS is set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
MBSYNC_CONFIG="${MBSYNC_CONFIG:-${HOME}/.mbsyncrc}"
LOG_DIR="${LOG_DIR:-${PROJECT_DIR}/logs}"
TMP_DIR="${TMP_DIR:-${PROJECT_DIR}/tmp}"
LOGFILE="${LOGFILE:-${LOG_DIR}/mail-sync.log}"
VERBOSE_LOG="${VERBOSE_LOG:-${LOG_DIR}/mail-sync.verbose.log}"
LOCK_DIR="${LOCK_DIR:-${TMP_DIR}/mail-sync.lock}"
AGENT_NAME="amail-agent"

MBSYNC_BIN="${MBSYNC_BIN:-mbsync}"
NOTMUCH_BIN="${NOTMUCH_BIN:-notmuch}"
SCRIPT_BIN="${SCRIPT_BIN:-/usr/bin/script}"

SUCCESS_SLEEP="${SUCCESS_SLEEP:-${CYCLE_SLEEP:-900}}"  # 15m between successful passes
QUOTA_BACKOFF="${QUOTA_BACKOFF:-7200}"                 # 2h after rate/quota errors
NO_INTERNET_BACKOFF="${NO_INTERNET_BACKOFF:-300}"      # 5m without connectivity
CONNECTIVITY_HOST="${CONNECTIVITY_HOST:-imap.gmail.com}"
CONNECTIVITY_PORT="${CONNECTIVITY_PORT:-993}"
CONNECTIVITY_TIMEOUT="${CONNECTIVITY_TIMEOUT:-5}"
RUN_NOW_CHECK_INTERVAL="${RUN_NOW_CHECK_INTERVAL:-5}"

RUN_ONCE=0
RUN_NOW_REQUESTED=0

ACCOUNTS=()
TEMP_FILES=()
declare -A NEXT_OK_AT=()
declare -A NEXT_REASON=()

timestamp() { date "+%Y-%m-%d %H:%M:%S %Z"; }
now_epoch() { date +%s; }

log() {
  local actor="$1"
  shift
  mkdir -p "$(dirname "$LOGFILE")"
  printf '%s: %s: %s\n' "$(timestamp)" "$actor" "$*" | tee -a "$LOGFILE"
}

vlog() {
  local actor="$1"
  shift
  mkdir -p "$(dirname "$VERBOSE_LOG")"
  printf '%s: %s: %s\n' "$(timestamp)" "$actor" "$*" >> "$VERBOSE_LOG"
}

usage() {
  cat <<'EOF'
Usage: ./mail-sync.sh [--once] [--list-accounts]

Environment overrides:
  MAIL_SYNC_ACCOUNTS   Space-separated mbsync channel names. Defaults to all Channel entries in ~/.mbsyncrc.
  SUCCESS_SLEEP        Seconds between full passes after sync. Default: 900.
  QUOTA_BACKOFF        Seconds to wait after quota/rate-limit errors. Default: 7200.
  NO_INTERNET_BACKOFF  Seconds to wait when internet is unreachable. Default: 300.
  CONNECTIVITY_HOST    Host checked before syncing. Default: imap.gmail.com.
  CONNECTIVITY_PORT    Port checked before syncing. Default: 993.
  RUN_NOW_CHECK_INTERVAL Seconds between run-now checks while sleeping. Default: 5.
  LOG_DIR              Runtime log directory. Default: ./logs.
  TMP_DIR              Runtime lock/temp directory. Default: ./tmp.
  LOGFILE              Clean summary log. Default: ./logs/mail-sync.log.
  VERBOSE_LOG          Raw mbsync/notmuch log. Default: ./logs/mail-sync.verbose.log.
EOF
}

human_duration() {
  local seconds="$1"
  local value unit

  if [ "$seconds" -ge 3600 ] && [ $((seconds % 3600)) -eq 0 ]; then
    value=$((seconds / 3600))
    unit="hour"
  elif [ "$seconds" -ge 60 ] && [ $((seconds % 60)) -eq 0 ]; then
    value=$((seconds / 60))
    unit="minute"
  elif [ "$seconds" -ge 60 ]; then
    local minutes=$((seconds / 60))
    local remainder=$((seconds % 60))
    printf '%d minute%s %d second%s\n' \
      "$minutes" "$([ "$minutes" -eq 1 ] && echo "" || echo "s")" \
      "$remainder" "$([ "$remainder" -eq 1 ] && echo "" || echo "s")"
    return
  else
    value="$seconds"
    unit="second"
  fi

  if [ "$value" -eq 1 ]; then
    printf '1 %s\n' "$unit"
  else
    printf '%d %ss\n' "$value" "$unit"
  fi
}

append_if_nonzero() {
  local -n target="$1"
  local value="$2"
  local text="$3"

  if [ "${value:-0}" -gt 0 ]; then
    target+=("$text")
  fi
}

sync_summary_action() {
  local downloaded="$1"
  local flags="$2"
  local expunged="$3"
  local deleted="$4"
  local uploaded="$5"
  local server_flags="$6"
  local parts=()
  local action

  if [ "${downloaded:-0}" -gt 0 ]; then
    action="Downloaded ${downloaded} new messages"
  else
    action="No new messages"
  fi

  append_if_nonzero parts "${flags:-0}" "updated ${flags} flags"
  append_if_nonzero parts "${expunged:-0}" "expunged ${expunged}"
  append_if_nonzero parts "${deleted:-0}" "deleted ${deleted}"
  append_if_nonzero parts "${uploaded:-0}" "uploaded ${uploaded}"
  append_if_nonzero parts "${server_flags:-0}" "server flag updates ${server_flags}"

  if [ "${#parts[@]}" -gt 0 ]; then
    local detail
    for detail in "${parts[@]}"; do
      action="${action}; ${detail}"
    done
    printf '%s\n' "$action"
  else
    printf '%s\n' "$action"
  fi
}

format_epoch() {
  local epoch="$1"
  if date -r "$epoch" "+%Y-%m-%d %H:%M:%S %Z" >/dev/null 2>&1; then
    date -r "$epoch" "+%Y-%m-%d %H:%M:%S %Z"
  else
    date -d "@$epoch" "+%Y-%m-%d %H:%M:%S %Z"
  fi
}

make_temp() {
  local tmp
  mkdir -p "$TMP_DIR"
  tmp="$(mktemp "${TMP_DIR}/mail-sync.XXXXXX")" || return 1
  TEMP_FILES+=("$tmp")
  printf '%s\n' "$tmp"
}

remove_temp() {
  local tmp="$1"
  [ -n "$tmp" ] && [ -e "$tmp" ] && rm -f "$tmp"
}

cleanup() {
  local tmp
  for tmp in "${TEMP_FILES[@]:-}"; do
    [ -n "$tmp" ] && [ -e "$tmp" ] && rm -f "$tmp"
  done
  if [ -d "$LOCK_DIR" ] && [ "$(cat "$LOCK_DIR/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

stop_now() {
  cleanup
  exit 0
}

request_run_now() {
  RUN_NOW_REQUESTED=1
}

sleep_until_next_run() {
  local seconds="$1"
  local remaining chunk

  if [ "$RUN_NOW_REQUESTED" -eq 1 ]; then
    RUN_NOW_REQUESTED=0
    log "$AGENT_NAME" "Run now requested; starting next pass"
    return 0
  fi

  remaining="$seconds"
  while [ "$remaining" -gt 0 ]; do
    chunk="$RUN_NOW_CHECK_INTERVAL"
    [ "$chunk" -le 0 ] && chunk=5
    [ "$chunk" -gt "$remaining" ] && chunk="$remaining"

    sleep "$chunk" || true

    if [ "$RUN_NOW_REQUESTED" -eq 1 ]; then
      break
    fi

    remaining=$((remaining - chunk))
  done

  if [ "$RUN_NOW_REQUESTED" -eq 1 ]; then
    RUN_NOW_REQUESTED=0
    log "$AGENT_NAME" "Run now requested; starting next pass"
  fi
}

acquire_lock() {
  mkdir -p "$LOG_DIR" "$TMP_DIR"

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return 0
  fi

  local pid
  pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "$AGENT_NAME" "Already running: pid $pid"
    exit 1
  fi

  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    return 0
  fi

  log "$AGENT_NAME" "Could not acquire lock: $LOCK_DIR"
  exit 1
}

require_executable() {
  local bin="$1"
  local label="$2"

  if [[ "$bin" == */* ]]; then
    [ -x "$bin" ] && return 0
  else
    command -v "$bin" >/dev/null 2>&1 && return 0
  fi

  log "$AGENT_NAME" "Missing required executable for $label: $bin"
  exit 1
}

check_dependencies() {
  require_executable "$MBSYNC_BIN" "mbsync"
  require_executable "$NOTMUCH_BIN" "notmuch"
  command -v awk >/dev/null 2>&1 || { log "$AGENT_NAME" "Missing required executable: awk"; exit 1; }
  command -v sed >/dev/null 2>&1 || { log "$AGENT_NAME" "Missing required executable: sed"; exit 1; }
  command -v tr >/dev/null 2>&1 || { log "$AGENT_NAME" "Missing required executable: tr"; exit 1; }
  command -v tee >/dev/null 2>&1 || { log "$AGENT_NAME" "Missing required executable: tee"; exit 1; }
}

discover_accounts() {
  local raw_accounts=()
  local account
  local -A seen=()

  if [ -n "${MAIL_SYNC_ACCOUNTS:-}" ]; then
    read -r -a raw_accounts <<< "$MAIL_SYNC_ACCOUNTS"
  else
    if [ ! -r "$MBSYNC_CONFIG" ]; then
      log "$AGENT_NAME" "Cannot read mbsync config: $MBSYNC_CONFIG"
      exit 1
    fi

    mapfile -t raw_accounts < <(
      awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*Channel[[:space:]]+/ { print $2 }
      ' "$MBSYNC_CONFIG"
    )
  fi

  ACCOUNTS=()
  for account in "${raw_accounts[@]:-}"; do
    [ -z "$account" ] && continue
    if [ -z "${seen[$account]+set}" ]; then
      ACCOUNTS+=("$account")
      seen[$account]=1
    fi
  done

  if [ "${#ACCOUNTS[@]}" -eq 0 ]; then
    log "$AGENT_NAME" "No mbsync channels found: set MAIL_SYNC_ACCOUNTS or add Channel entries to $MBSYNC_CONFIG"
    exit 1
  fi
}

set_backoff() {
  local account="$1"
  local seconds="$2"
  local reason="$3"
  NEXT_OK_AT["$account"]=$(( $(now_epoch) + seconds ))
  NEXT_REASON["$account"]="$reason"
}

clear_backoff() {
  local account="$1"
  unset 'NEXT_OK_AT[$account]'
  unset 'NEXT_REASON[$account]'
}

is_quota_error() {
  local file="$1"
  tr '\r' '\n' < "$file" | grep -Eiq \
    'OVERQUOTA|over quota|quota|rate.?limit|rate limited|too many simultaneous connections|exceeded command or bandwidth limits|bandwidth limits|Limit Exceeded|User-rate limit exceeded|temporarily unavailable|try again later|HTTP[[:space:]]*429|[^0-9]429[^0-9]'
}

is_connection_error() {
  local file="$1"
  tr '\r' '\n' < "$file" | grep -Eiq \
    'unexpected BYE|timeout|Socket error|Connection reset|Network is down|No route to host|Temporary failure|Could not connect|connection closed|server closed connection|unexpected eof|SSL routines'
}

internet_available() {
  if command -v nc >/dev/null 2>&1; then
    nc -G "$CONNECTIVITY_TIMEOUT" -z "$CONNECTIVITY_HOST" "$CONNECTIVITY_PORT" >/dev/null 2>&1 ||
      nc -w "$CONNECTIVITY_TIMEOUT" -z "$CONNECTIVITY_HOST" "$CONNECTIVITY_PORT" >/dev/null 2>&1
    return "$?"
  fi

  if command -v ping >/dev/null 2>&1; then
    ping -c 1 -t "$CONNECTIVITY_TIMEOUT" "$CONNECTIVITY_HOST" >/dev/null 2>&1
    return "$?"
  fi

  return 1
}

parse_mbsync_summary() {
  local file="$1"
  local line
  local far_new far_flag far_exp far_del near_new near_flag near_exp near_del

  line="$(tr '\r' '\n' < "$file" | awk '/^Channels:[[:space:]]/ { last=$0 } END { print last }')"
  [ -n "$line" ] || return 1

  far_new="$(printf '%s\n' "$line" | sed -nE 's/.*Far:[[:space:]]+\+([0-9]+).*/\1/p')"
  far_flag="$(printf '%s\n' "$line" | sed -nE 's/.*Far:[[:space:]]+\+[0-9]+[[:space:]]+\*([0-9]+).*/\1/p')"
  far_exp="$(printf '%s\n' "$line" | sed -nE 's/.*Far:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#([0-9]+).*/\1/p')"
  far_del="$(printf '%s\n' "$line" | sed -nE 's/.*Far:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#[0-9]+[[:space:]]+-([0-9]+).*/\1/p')"
  near_new="$(printf '%s\n' "$line" | sed -nE 's/.*Near:[[:space:]]+\+([0-9]+).*/\1/p')"
  near_flag="$(printf '%s\n' "$line" | sed -nE 's/.*Near:[[:space:]]+\+[0-9]+[[:space:]]+\*([0-9]+).*/\1/p')"
  near_exp="$(printf '%s\n' "$line" | sed -nE 's/.*Near:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#([0-9]+).*/\1/p')"
  near_del="$(printf '%s\n' "$line" | sed -nE 's/.*Near:[[:space:]]+\+[0-9]+[[:space:]]+\*[0-9]+[[:space:]]+#[0-9]+[[:space:]]+-([0-9]+).*/\1/p')"

  printf '%s %s %s %s %s %s %s %s\n' \
    "${near_new:-0}" "${near_flag:-0}" "${near_exp:-0}" "${near_del:-0}" \
    "${far_new:-0}" "${far_flag:-0}" "${far_exp:-0}" "${far_del:-0}"
}

parse_progress_near_new() {
  local file="$1"
  local count
  count="$(
    tr '\r' '\n' < "$file" |
      sed -nE 's/.*N:[[:space:]]+\+([0-9]+)\/[0-9]+.*/\1/p' |
      sort -n |
      tail -n 1
  )"
  printf '%s\n' "${count:-0}"
}

run_sync() {
  local account="$1"
  local tmpfile status summary progress_new
  local near_new near_flag near_exp near_del far_new far_flag far_exp far_del
  local cmd=()

  LAST_DOWNLOADED=0
  tmpfile="$(make_temp)" || return 20

  cmd=("$MBSYNC_BIN")
  [ -n "$MBSYNC_CONFIG" ] && cmd+=("-c" "$MBSYNC_CONFIG")
  cmd+=("$account")

  log "$account" "Sync started"
  vlog "$account" "mbsync started"

  if [ -x "$SCRIPT_BIN" ]; then
    "$SCRIPT_BIN" -q /dev/null "${cmd[@]}" 2>&1 | tee -a "$VERBOSE_LOG" > "$tmpfile"
  else
    "${cmd[@]}" 2>&1 | tee -a "$VERBOSE_LOG" > "$tmpfile"
  fi
  status=${PIPESTATUS[0]}

  summary="$(parse_mbsync_summary "$tmpfile" || true)"
  progress_new="$(parse_progress_near_new "$tmpfile")"

  if [ "$status" -eq 0 ]; then
    clear_backoff "$account"

    if [ -n "$summary" ]; then
      read -r near_new near_flag near_exp near_del far_new far_flag far_exp far_del <<< "$summary"
      LAST_DOWNLOADED="${near_new:-0}"
      log "$account" "$(sync_summary_action "$near_new" "$near_flag" "$near_exp" "$near_del" "$far_new" "$far_flag")"
    else
      LAST_DOWNLOADED="${progress_new:-0}"
      log "$account" "Sync completed without mbsync summary; see $VERBOSE_LOG"
    fi
    log "$account" "Sync finished"
    remove_temp "$tmpfile"
    return 0
  fi

  if is_quota_error "$tmpfile"; then
    set_backoff "$account" "$QUOTA_BACKOFF" "quota"
    log "$account" "Quota backoff: $(human_duration "$QUOTA_BACKOFF")"
    remove_temp "$tmpfile"
    return 11
  fi

  if is_connection_error "$tmpfile"; then
    log "$account" "Connection error; retrying next cycle; see $VERBOSE_LOG"
    remove_temp "$tmpfile"
    return 12
  fi

  log "$account" "Sync failed: exit $status; retrying next cycle; see $VERBOSE_LOG"
  remove_temp "$tmpfile"
  return 20
}

run_notmuch() {
  local account="${1:-all accounts}"
  local tmpfile status added

  tmpfile="$(make_temp)" || return 1
  vlog "$account" "notmuch new started"

  "$NOTMUCH_BIN" new 2>&1 | tee -a "$VERBOSE_LOG" > "$tmpfile"
  status=${PIPESTATUS[0]}

  if [ "$status" -ne 0 ]; then
    log "$account" "Indexing failed: exit $status; see $VERBOSE_LOG"
    remove_temp "$tmpfile"
    return 1
  fi

  added="$(sed -nE 's/.*Added ([0-9]+) new message.*/\1/p' "$tmpfile" | tail -n 1)"

  log "$account" "Indexing completed: ${added:-0} new messages"
  remove_temp "$tmpfile"
}

run_cycle() {
  local account next_ok reason now attempted rc
  attempted=0

  for account in "${ACCOUNTS[@]}"; do
    now="$(now_epoch)"
    next_ok="${NEXT_OK_AT[$account]:-0}"

    if [ "$next_ok" -gt "$now" ]; then
      reason="${NEXT_REASON[$account]:-backoff}"
      log "$account" "Skipped: $reason backoff until $(format_epoch "$next_ok")"
      continue
    fi

    attempted=1
    run_sync "$account"
    rc="$?"
    case "$rc" in
      0|11|12|20) ;;
      *) log "$account" "Unexpected sync result; see $VERBOSE_LOG" ;;
    esac

    if [ "$rc" -eq 0 ] && [ "${LAST_DOWNLOADED:-0}" -gt 0 ]; then
      run_notmuch "$account" || true
    fi
  done

  if [ "$attempted" -eq 0 ]; then
    log "$AGENT_NAME" "No accounts due"
  fi
}

list_accounts() {
  discover_accounts
  printf '%s\n' "${ACCOUNTS[@]}"
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --once) RUN_ONCE=1 ;;
      --list-accounts) list_accounts; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 64 ;;
    esac
    shift
  done

  trap cleanup EXIT
  trap stop_now INT TERM
  trap request_run_now USR1
  acquire_lock
  check_dependencies
  discover_accounts

  log "$AGENT_NAME" "Started: ${#ACCOUNTS[@]} accounts; sync sleep $(human_duration "$SUCCESS_SLEEP"); quota backoff $(human_duration "$QUOTA_BACKOFF")"

  while true; do
    if ! internet_available; then
      log "$AGENT_NAME" "Network unavailable: ${CONNECTIVITY_HOST}:${CONNECTIVITY_PORT}; sleeping $(human_duration "$NO_INTERNET_BACKOFF")"
      if [ "$RUN_ONCE" -eq 1 ]; then
        log "$AGENT_NAME" "Sync finished"
        break
      fi
      sleep_until_next_run "$NO_INTERNET_BACKOFF"
      continue
    fi

    run_cycle

    if [ "$RUN_ONCE" -eq 1 ]; then
      log "$AGENT_NAME" "Sync finished"
      break
    fi

    log "$AGENT_NAME" "Sync finished; sleeping $(human_duration "$SUCCESS_SLEEP")"
    sleep_until_next_run "$SUCCESS_SLEEP"
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
