# common.sh - shared helpers for setup.sh and update.sh on the AC5000.
#
# This file is fetched at runtime by both scripts via the `fetch_shared`
# preamble and sourced into the running shell. It provides:
#
#   - ANSI colour variables (red, green, clear) used by status messages
#     and by run_techbase_update's timeout diagnostics.
#   - _kill_tree:           recursive process-tree termination helper.
#   - run_techbase_update:  inactivity-watchdog wrapper around softmgr
#                           or any other long-running command.
#
# This file is sourced, not executed directly. It must NOT use `set -e`
# or other strict modes that would change the parent script's behaviour.

# ANSI colour codes used by status output and run_techbase_update.
red='\033[0;31m'
green='\033[0;32m'
clear='\033[0m'

# ---------------------------------------------------------------------------
# _kill_tree
#
# Send a signal to a process and every descendant of it.
#
# WHY: when bash is waiting on a child (e.g. softmgr blocked in `sleep`),
# its default SIGTERM handler does not run until the wait completes.
# Killing only the top-level pid therefore does not stop the workload.
# Walking the tree depth-first and signalling leaves first lets the
# workload actually terminate so wait() can return in the parent.
# ---------------------------------------------------------------------------
_kill_tree() {
  local pid="$1" sig="$2" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    _kill_tree "$child" "$sig"
  done
  kill -"$sig" "$pid" 2>/dev/null
}

# ---------------------------------------------------------------------------
# run_techbase_update
#
# Run a softmgr command (or any long-running shell command) under an
# inactivity (idle) watchdog instead of a fixed wall-clock timeout.
#
# WHY: softmgr update operations vary from a few seconds (nothing to do)
# to many minutes (large firmware bundles on a slow link). A fixed
# `timeout 240` cannot tell a slow but healthy download from a frozen
# process: both look identical from the outside. The fix is to watch
# the *output stream* instead of the clock. A healthy softmgr emits
# progress lines (percentages, dots, status messages); a hung one is
# silent. We reset the watchdog on every line and only kill the
# process when it has been silent for $idle seconds.
#
# A second, generous wall-clock cap ($hard) is kept as a safety net so
# a process that prints garbage forever cannot run unboundedly.
#
# Arguments:
#   $1  command string to run (NO `timeout` prefix; this helper owns timing)
#   $2  idle timeout in seconds   (default: $IDLE_TIMEOUT or 30)
#   $3  hard timeout in seconds   (default: $HARD_TIMEOUT or 900)
#
# Defaults rationale:
#   - 30 s of total silence from a tool that is supposed to be printing
#     progress is a strong signal that it is hung, not just slow.
#   - 15 min total wall time is more than any healthy softmgr update
#     should ever need; beyond that, something is wrong regardless of
#     what is being printed.
#
# Return codes:
#     0  command succeeded and reported nothing to do
#     1  command succeeded and installed updates (caller may reboot),
#        OR command failed in some other way (mirrors the original helper)
#   124  hard timeout: total runtime exceeded $hard seconds
#   137  idle timeout: no output for $idle seconds (treated as hung)
# ---------------------------------------------------------------------------
run_techbase_update() {
  local cmd="$1"
  local idle="${2:-${IDLE_TIMEOUT:-30}}"
  local hard="${3:-${HARD_TIMEOUT:-900}}"
  local output="" line rc start now elapsed cmd_pid

  # Launch the command as a coprocess so we can read its stdout one line
  # at a time from the parent shell. `stdbuf -oL -eL` forces line-buffered
  # output, otherwise libc may hold up to ~4 KB before flushing and the
  # watchdog would misfire on a healthy but quiet command. `2>&1` folds
  # stderr into the stream we are watching, so error diagnostics also
  # count as a heartbeat.
  coproc CMD { stdbuf -oL -eL bash -c "$cmd" 2>&1; }
  cmd_pid=$CMD_PID

  # Duplicate the coprocess read end into a file descriptor that we own
  # (`read_fd`). Bash automatically unsets CMD[0] and closes its
  # underlying fd as soon as the child exits. Without our own duplicate,
  # the next `read` would fail with "Bad file descriptor" the moment
  # softmgr finishes, even if there is still buffered output to drain.
  # We close `read_fd` ourselves before every return path below.
  local read_fd
  exec {read_fd}<&"${CMD[0]}"

  start=$(date +%s)

  # Read a line at a time. `read -t $idle` blocks for at most $idle
  # seconds. If a line arrives within that window the command is alive
  # and we re-enter the loop (the watchdog is implicitly reset). If the
  # window expires `read` exits non-zero and we drop out of the loop.
  while IFS= read -t "$idle" -ru "$read_fd" line; do
    # Stream the line live to the operator's terminal AND keep a copy
    # so we can grep the captured output for "No updates available" /
    # "ACTION=none" once the command has finished. The trailing $clear
    # bounds any unbalanced ANSI colour escape from softmgr to a single
    # line, so a stray "green-on" cannot latch the terminal into green
    # for everything we print afterwards.
    printf '%s%b\n' "$line" "$clear"
    output+="$line"$'\n'

    # Enforce the absolute upper bound. Even a perfectly chatty command
    # should not run for more than $hard seconds without us intervening.
    now=$(date +%s)
    elapsed=$(( now - start ))
    if (( elapsed >= hard )); then
      printf '\n%bHard timeout (%ss) reached.%b\n' "$red" "$hard" "$clear" >&2
      _kill_tree "$cmd_pid" TERM   # ask politely first (whole tree)
      sleep 5
      _kill_tree "$cmd_pid" KILL   # then enforce
      wait "$cmd_pid" 2>/dev/null
      exec {read_fd}<&-
      return 124
    fi
  done

  # The loop ends for one of two reasons: read hit EOF (the command
  # exited and closed its end of the pipe) or read hit the idle timeout
  # (no output for $idle seconds). Note: `$?` after a `while CMD; do
  # BODY; done` reflects the body's last exit, not the failing CMD, so
  # we cannot use it here. We disambiguate by asking the kernel whether
  # the child is still alive: if it is, the only thing that could have
  # broken us out of the loop is the idle timeout, i.e. a hang.
  if kill -0 "$cmd_pid" 2>/dev/null; then
    printf '\n%bNo output for %ss; treating as hung.%b\n' "$red" "$idle" "$clear" >&2
    _kill_tree "$cmd_pid" TERM
    sleep 5
    _kill_tree "$cmd_pid" KILL
    wait "$cmd_pid" 2>/dev/null
    exec {read_fd}<&-
    return 137
  fi

  # The command finished on its own; collect its real exit status and
  # release our duplicate of the read end before inspecting the captured
  # output.
  wait "$cmd_pid"
  rc=$?
  exec {read_fd}<&-

  # Same outcome contract as the original helper: inspect the captured
  # output for the vendor's "no work to do" markers, otherwise treat a
  # successful exit as "updates were installed, caller may reboot".
  if [ $rc -eq 0 ]; then
    if [[ "$output" == *"No updates available"* || "$output" == *"ACTION=none"* ]]; then
      echo "Alt er oppdatert"
      return 0
    fi
    echo "Nye oppdateringer er installert. Fikser innstillinger."
    return 1
  fi
  printf '\n%bKlarte ikke å utføre kommandoen: %s%b\n' "$red" "$cmd" "$clear" >&2
  return 1
}
