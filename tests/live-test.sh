#!/bin/bash
# Live test on a running Hyprland session. Opens and closes only its own foot
# windows, by address, so it is safe to run while you keep working.
# Needs: foot, tmux, jq. The herdr case is skipped when herdr is missing.

set -u
BIN=$(cd "$(dirname "$0")/../bin" && pwd)/window-reopen
WORK=$(mktemp -d)
mkdir -p "$WORK/sub"
export XDG_STATE_HOME=$WORK/state # keep test history away from the real one
PASS=0
FAIL=0

ok() { echo "  ok   $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL + 1)); }
addresses() { hyprctl clients -j | jq -r '.[].address' | sort; }
workspace_of() { hyprctl clients -j | jq -r --arg a "$1" '.[] | select(.address == $a) | .workspace.name'; }
pid_of() { hyprctl clients -j | jq -r --arg a "$1" '.[] | select(.address == $a) | .pid'; }
child_of() { cat /proc/"$1"/task/*/children 2>/dev/null | awk '{ print $1 }'; }
kill_window() { [[ -n $1 ]] && is_test_window "$1" && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$1\" })" >/dev/null; }

# Only windows whose process (or its first child) mentions a test marker are
# ours. Never pick "any new window": the user may open windows meanwhile.
is_test_window() {
  local pid
  pid=$(pid_of "$1")
  [[ -n $pid ]] || return 1
  grep -qaE "wr-test|$WORK" /proc/"$pid"/cmdline /proc/"$(child_of "$pid")"/cmdline 2>/dev/null
}

test_pids() { for a in $(addresses); do is_test_window "$a" && pid_of "$a"; done | sort; }

# Run "$@" and print the address of the test window it opens. Compares pids,
# because Hyprland can give a new window the address of one just closed.
new_window_after() {
  local before a
  before=$(test_pids)
  "$@" >/dev/null
  for _ in $(seq 40); do
    sleep 0.2
    for a in $(addresses); do
      is_test_window "$a" && ! grep -qx "$(pid_of "$a")" <<<"$before" && { sleep 0.8; echo "$a"; return; }
    done
  done
}

open_test_window() { new_window_after hyprctl dispatch "hl.dsp.exec_cmd([[foot --title=wr-test $*]])"; }

# Close window $1 for real (short TTL), then reopen; print the new window's address.
close_expire_reopen() {
  WINDOW_REOPEN_TTL=2 "$BIN" close "$1"
  sleep 4
  new_window_after "$BIN" reopen
}

echo "1. resume while hidden: same window and process, so screen and folder are untouched"
a=$(open_test_window -e bash -c "'cd $WORK/sub; echo MARK; exec bash'")
pid=$(pid_of "$a")
WINDOW_REOPEN_TTL=600 "$BIN" close "$a"
sleep 0.5
[[ $(workspace_of "$a") == special:window-reopen ]] && ok "hidden" || bad "not hidden"
"$BIN" reopen
sleep 0.5
[[ -n $(workspace_of "$a") && $(workspace_of "$a") != special:window-reopen && $(pid_of "$a") == "$pid" ]] &&
  ok "same window and process back" || bad "window not restored"
[[ $(readlink /proc/"$(child_of "$pid")"/cwd) == "$WORK/sub" ]] && ok "shell still in sub/" || bad "shell folder changed"

echo "2. plain shell, after the real close: new shell opens in the folder it was in"
old=$(pid_of "$a")
n=$(close_expire_reopen "$a")
[[ -n $n && $(pid_of "$n") != "$old" ]] && ok "really closed, then relaunched" || bad "no relaunch"
[[ $(readlink /proc/"$(child_of "$(pid_of "$n")")"/cwd) == "$WORK/sub" ]] && ok "folder sub/" || bad "wrong folder"
kill_window "$n"

echo "3. tmux, after the real close: same session, same folder, same screen"
a=$(open_test_window -e bash -c "'tmux new-session -s wr-test-tmux; exec bash'")
sleep 0.5
tmux send-keys -t "=wr-test-tmux:" "cd $WORK/sub && echo MARK-\$((40 + 2))" Enter
sleep 0.5
old=$(pid_of "$a")
n=$(close_expire_reopen "$a")
[[ -n $n && $(pid_of "$n") != "$old" ]] && ok "really closed, then relaunched" || bad "no relaunch"
[[ -n $(tmux list-clients -t "=wr-test-tmux" 2>/dev/null) ]] && ok "reattached to wr-test-tmux" || bad "not reattached"
[[ $(tmux display-message -p -t "=wr-test-tmux:" '#{pane_current_path}') == "$WORK/sub" ]] && ok "still in sub/" || bad "folder lost"
tmux capture-pane -p -t "=wr-test-tmux:" | grep -q "MARK-42" && ok "earlier output MARK-42 still on screen" || bad "screen lost"
kill_window "$n"
tmux kill-session -t "=wr-test-tmux" 2>/dev/null

if command -v herdr >/dev/null; then
  echo "4. herdr, after the real close: reattaches its persistent session"
  a=$(open_test_window -e herdr --session wr-test-herdr)
  old=$(pid_of "$a")
  n=$(close_expire_reopen "$a")
  [[ -n $n && $(pid_of "$n") != "$old" ]] && ok "really closed, then relaunched" || bad "no relaunch"
  grep -qa wr-test-herdr /proc/"$(child_of "$(pid_of "$n")")"/cmdline 2>/dev/null &&
    ok "herdr --session wr-test-herdr in the new window" || bad "herdr not reattached"
  kill_window "$n"
  sleep 0.5
  herdr session stop wr-test-herdr >/dev/null 2>&1
  herdr session delete wr-test-herdr >/dev/null 2>&1
fi

rm -rf "$WORK"
echo "passed: $PASS, failed: $FAIL"
((FAIL == 0))
