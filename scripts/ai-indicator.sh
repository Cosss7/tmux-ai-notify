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
