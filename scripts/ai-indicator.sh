#!/usr/bin/env bash
# ai-indicator.sh — Check if any pane in a tmux window runs an AI coding tool
#
# Usage: ai-indicator.sh <window_id>
# Called by tmux via #() in window-status-format.
# Outputs the indicator emoji if an AI tool is detected, empty string otherwise.

WINDOW_ID="${1:-}"
[ -z "$WINDOW_ID" ] && exit 0

# Read user configuration from tmux options
EMOJI=$(tmux show-option -gqv @ai-notify-emoji 2>/dev/null)
EMOJI="${EMOJI:-✨}"
TOOLS=$(tmux show-option -gqv @ai-notify-tools 2>/dev/null)
TOOLS="${TOOLS:-opencode|claude|codex}"

# --- Tier 1: Fast path ---
# Check pane_current_command for all panes in this window.
# Covers tools whose process name matches directly (opencode, claude).
if tmux list-panes -t "$WINDOW_ID" -F '#{pane_current_command}' 2>/dev/null \
    | grep -qE "^($TOOLS)$"; then
    printf '%s' "$EMOJI"
    exit 0
fi

# --- Tier 2: Deep path ---
# Only check panes whose pane_current_command is "node" — these could be
# running Node.js-based AI tools (like codex) that show as "node" instead
# of their actual tool name.

# Platform-specific: get full command line for a PID
get_cmdline() {
    local pid=$1
    if [ -r "/proc/$pid/cmdline" ]; then
        # Linux: read from procfs, replace null bytes with spaces
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null
    else
        # macOS/BSD: use ps
        ps -p "$pid" -o args= 2>/dev/null
    fi
}

# Platform-specific: get direct child PIDs of a process
get_children() {
    local parent_pid=$1
    if [ -d "/proc" ] && ps --ppid "$parent_pid" -o pid= >/dev/null 2>&1; then
        # Linux (GNU ps supports --ppid)
        ps --ppid "$parent_pid" -o pid= 2>/dev/null
    else
        # macOS/BSD (no --ppid flag, filter manually)
        ps -ax -o pid=,ppid= 2>/dev/null | awk -v ppid="$parent_pid" '$2 == ppid { print $1 }'
    fi
}

# Check process tree iteratively up to 3 levels deep.
# Breadth-first: check all processes at current depth, then go deeper.
check_pane_tree() {
    local pane_pid=$1
    local pids_to_check="$pane_pid"
    local depth=0

    while [ "$depth" -le 3 ] && [ -n "$pids_to_check" ]; do
        local next_pids=""
        for pid in $pids_to_check; do
            local cmdline
            cmdline=$(get_cmdline "$pid")
            if [ -n "$cmdline" ] && echo "$cmdline" | grep -qE "($TOOLS)"; then
                return 0
            fi
            local children
            children=$(get_children "$pid")
            next_pids="$next_pids $children"
        done
        pids_to_check=$(echo "$next_pids" | xargs)
        depth=$((depth + 1))
    done

    return 1
}

# Determine if a pane's current command warrants a deep tree inspection.
# "node" is checked because JS-based AI tools (e.g., codex) run under it.
# Version-numbered binaries (e.g., Claude Code's "2.1.126") are also checked
# because their pane_current_command is the version filename, not the tool name.
should_deep_check() {
    local cmd="$1"
    [ "$cmd" = "node" ] && return 0
    echo "$cmd" | grep -qE '^[0-9]+(\.[0-9]+)+$' && return 0
    return 1
}

while IFS=$'\t' read -r pane_cmd pane_pid; do
    if should_deep_check "$pane_cmd"; then
        if check_pane_tree "$pane_pid"; then
            printf '%s' "$EMOJI"
            exit 0
        fi
    fi
done < <(tmux list-panes -t "$WINDOW_ID" -F '#{pane_current_command}\t#{pane_pid}' 2>/dev/null)
