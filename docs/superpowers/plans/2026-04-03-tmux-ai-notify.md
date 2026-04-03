# tmux-ai-notify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a TPM plugin that shows ✨ in the tmux status line when a window has panes running AI coding tools (opencode, claude, codex).

**Architecture:** A TPM plugin with two files — an entry script that injects a `#()` call into the window-status-format, and a detection script that checks each window's pane processes for AI tools using a two-tier strategy (fast path via `pane_current_command`, deep path via process tree inspection for Node.js tools like codex).

**Tech Stack:** Bash, tmux API, TPM plugin conventions

---

## File Structure

```
tmux-ai-notify/
├── tmux-ai-notify.tmux              # TPM entry point — format injection
├── scripts/
│   └── ai-indicator.sh              # Detection script — called per window per status refresh
└── README.md                        # Installation and usage docs
```

| File | Responsibility |
|------|---------------|
| `tmux-ai-notify.tmux` | Read current window-status-format, inject indicator call after `#I`, handle duplicate load protection |
| `scripts/ai-indicator.sh` | Accept window_id arg, read config from tmux options, run two-tier process detection, output emoji or empty string |

---

### Task 1: Project Setup

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Initialize git repo**

```bash
cd /home/cosss/code/ai/tmux-ai-notify
git init
```

- [ ] **Step 2: Create directory structure and .gitignore**

Create `.gitignore`:
```
*.swp
*.swo
*~
.DS_Store
```

Create `scripts/` directory:
```bash
mkdir -p scripts
```

- [ ] **Step 3: Commit project skeleton**

```bash
git add .gitignore
git commit -m "chore: init project"
```

---

### Task 2: Detection Script — Fast Path

**Files:**
- Create: `scripts/ai-indicator.sh`

- [ ] **Step 1: Write the detection script with fast path only**

Create `scripts/ai-indicator.sh`:

```bash
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
```

- [ ] **Step 2: Make executable and test fast path manually**

```bash
chmod +x scripts/ai-indicator.sh
```

Open a tmux session, note a window ID with `tmux list-windows -F '#{window_id}'`, then run:

```bash
# In a window NOT running an AI tool — should output nothing:
./scripts/ai-indicator.sh @0

# In a window running opencode or claude — should output ✨:
./scripts/ai-indicator.sh @1
```

Expected: empty string for normal windows, `✨` for windows with opencode/claude.

- [ ] **Step 3: Commit fast path**

```bash
git add scripts/ai-indicator.sh
git commit -m "feat: add detection script with fast path"
```

---

### Task 3: Detection Script — Deep Path (Cross-Platform)

**Files:**
- Modify: `scripts/ai-indicator.sh`

- [ ] **Step 1: Add platform-aware helper functions**

Append the following to `scripts/ai-indicator.sh`, BEFORE the final empty exit (after the fast path block):

```bash
# --- Tier 2: Deep path ---
# For tools that show as a generic runtime (e.g. codex shows as "node"),
# inspect the process tree of each pane to match against full command lines.

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
```

- [ ] **Step 2: Add iterative process tree check**

Append after the helper functions:

```bash
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

# Run deep check on each pane
for pane_pid in $(tmux list-panes -t "$WINDOW_ID" -F '#{pane_pid}' 2>/dev/null); do
    if check_pane_tree "$pane_pid"; then
        printf '%s' "$EMOJI"
        exit 0
    fi
done
```

- [ ] **Step 3: Test deep path manually**

Test with a simulated node process. In a tmux pane, run:

```bash
# Simulate a node process with "codex" in its args
node -e "setTimeout(() => {}, 60000)" -- codex
```

In another pane, note the window ID and run:

```bash
./scripts/ai-indicator.sh @0
```

Expected: `✨` (the grep on cmdline should match "codex" in the args).

Then kill the simulated process and run again — expected: empty string.

- [ ] **Step 4: Commit deep path**

```bash
git add scripts/ai-indicator.sh
git commit -m "feat: add deep path detection for Node.js-based AI tools"
```

---

### Task 4: Plugin Entry Point — Format Injection

**Files:**
- Create: `tmux-ai-notify.tmux`

- [ ] **Step 1: Write the entry script**

Create `tmux-ai-notify.tmux`:

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tmux-ai-notify.tmux
```

- [ ] **Step 3: Test format injection manually**

```bash
# Check current format
tmux show-option -gv window-status-format

# Run the plugin entry point
bash tmux-ai-notify.tmux

# Check modified format — should now contain ai-indicator.sh after #I
tmux show-option -gv window-status-format

# Run again — should NOT duplicate (duplicate load protection)
bash tmux-ai-notify.tmux
tmux show-option -gv window-status-format
```

Expected: the format now includes `#(/path/to/ai-indicator.sh #{window_id})` after `#I`, and running a second time does not add it again.

- [ ] **Step 4: Commit entry point**

```bash
git add tmux-ai-notify.tmux
git commit -m "feat: add plugin entry point with format injection"
```

---

### Task 5: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Create `README.md`:

```markdown
# tmux-ai-notify

A tmux plugin that displays an indicator in the status line when a window has
panes running AI coding tools (opencode, claude, codex).

## Installation

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to your `.tmux.conf` (or `.tmux.conf.local` for oh-my-tmux users):

```tmux
set -g @plugin 'your-username/tmux-ai-notify'
```

Press `prefix + I` to install.

### Manual

Clone the repo:

```bash
git clone https://github.com/your-username/tmux-ai-notify ~/.tmux/plugins/tmux-ai-notify
```

Add to your `.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-ai-notify/tmux-ai-notify.tmux
```

Reload tmux: `tmux source-file ~/.tmux.conf`

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `@ai-notify-emoji` | `✨` | Indicator emoji |
| `@ai-notify-tools` | `opencode\|claude\|codex` | Pipe-separated tool names to detect |

Example:

```tmux
set -g @ai-notify-emoji '🤖'
set -g @ai-notify-tools 'opencode|claude|codex|aider'
```

## How It Works

The plugin modifies `window-status-format` and `window-status-current-format`
to call a detection script for each window on every status refresh.

The detection script uses a two-tier strategy:

1. **Fast path:** Checks `pane_current_command` for direct name matches
2. **Deep path:** Inspects process tree command lines for tools that run under
   a generic runtime (e.g., codex shows as `node`)

The refresh interval is controlled by tmux's `status-interval` option
(default: 15 seconds).

## Supported Tools

| Tool | Detection |
|------|-----------|
| opencode | Fast path (`pane_current_command` = `opencode`) |
| claude | Fast path (`pane_current_command` = `claude`) |
| codex | Deep path (process command line inspection) |

## Platform Support

- Linux
- macOS
```

- [ ] **Step 2: Commit README**

```bash
git add README.md
git commit -m "docs: add README with installation and configuration guide"
```

---

### Task 6: Integration Test

**Files:**
- All existing files (no changes, verification only)

- [ ] **Step 1: Test full plugin flow in tmux**

Reset any previous format changes, then load the plugin fresh:

```bash
# Reset format to default
tmux set-option -g window-status-format '#I:#W'
tmux set-option -g window-status-current-format '#I:#W'

# Load the plugin
bash /home/cosss/code/ai/tmux-ai-notify/tmux-ai-notify.tmux

# Verify injection
tmux show-option -gv window-status-format
# Expected: contains ai-indicator.sh after #I
```

- [ ] **Step 2: Test with actual AI tools**

1. Open a new tmux window and run `opencode` → verify ✨ appears in status line (may need to wait up to `status-interval` seconds)
2. Open another window and run `claude` → verify ✨ appears
3. Open another window with just a shell → verify no ✨
4. Exit the AI tools → verify ✨ disappears after next refresh

- [ ] **Step 3: Test configuration**

```bash
# Change emoji
tmux set-option -g @ai-notify-emoji '🤖'
# Wait for next status refresh — AI tool windows should now show 🤖

# Reset
tmux set-option -g @ai-notify-emoji '✨'
```

- [ ] **Step 4: Commit the design and plan docs**

```bash
git add docs/
git commit -m "docs: add design spec and implementation plan"
```
