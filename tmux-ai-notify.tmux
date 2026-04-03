#!/usr/bin/env bash
# tmux-ai-notify.tmux — TPM plugin entry point
#
# Injects the AI indicator call into window-status-format and
# window-status-current-format so tmux calls ai-indicator.sh per window.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$CURRENT_DIR/scripts/ai-indicator.sh"

# Ensure detection script is executable
chmod +x "$SCRIPT_PATH"

# Build the indicator format call.
# tmux expands #{window_id} per window before executing the #() command.
# Use single quotes around #{window_id} to prevent bash from expanding it.
INDICATOR_CALL='#('"$SCRIPT_PATH"' #{window_id})'

# Inject the indicator call into a window-status format option.
# Inserts after #I (or #{window_index}) so the emoji appears between
# the window number and the separator/window name.
inject_indicator() {
    local option_name="$1"
    local current_format
    current_format=$(tmux show-option -gqv "$option_name")

    # Skip if format is empty
    [ -z "$current_format" ] && return

    # Duplicate load protection: skip if already injected
    if echo "$current_format" | grep -qF "ai-indicator.sh"; then
        return
    fi

    local new_format=""

    if echo "$current_format" | grep -qF '#I'; then
        # Replace first occurrence of #I with #I + indicator call
        new_format="${current_format/\#I/#I${INDICATOR_CALL}}"
    elif echo "$current_format" | grep -qF '#{window_index}'; then
        # Handle the long-form variant
        new_format="${current_format/\#\{window_index\}/#{window_index}${INDICATOR_CALL}}"
    fi

    # Only set if we successfully built a new format
    if [ -n "$new_format" ]; then
        tmux set-option -gq "$option_name" "$new_format"
    fi
}

inject_indicator "window-status-format"
inject_indicator "window-status-current-format"
