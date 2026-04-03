# tmux-ai-notify Design Spec

## Overview

A tmux TPM plugin that displays an indicator emoji (✨) in the status line between the window number and window name when any pane in that window is running a TUI AI coding tool (opencode, claude, codex).

**Example:** `1✨:code` (AI tool active) vs `2:shell` (no AI tool)

## Requirements

- Detect opencode, claude, and codex running in any pane of a window
- Display ✨ between window index and window name in the status line
- Compatible with oh-my-tmux
- Support both Linux and macOS
- Installable via TPM (Tmux Plugin Manager)
- Configurable emoji and tool list via tmux user options

## Project Structure

```
tmux-ai-notify/
├── tmux-ai-notify.tmux          # TPM entry point
├── scripts/
│   └── ai-indicator.sh          # Per-window detection script
└── README.md
```

## Architecture

### Workflow

1. TPM loads the plugin by sourcing `tmux-ai-notify.tmux`
2. The entry script reads the current `window-status-format` and `window-status-current-format`
3. It injects `#(path/to/ai-indicator.sh #{window_id})` after the window index (`#I`) in both formats
4. On each status refresh (every `status-interval` seconds, default 15s), tmux calls the detection script per window
5. The script checks all panes in the window and outputs ✨ or empty string

### Configuration

Users can customize via tmux options (set in `.tmux.conf` or `.tmux.conf.local`):

| Option | Default | Description |
|--------|---------|-------------|
| `@ai-notify-emoji` | `✨` | Indicator emoji to display |
| `@ai-notify-tools` | `opencode\|claude\|codex` | Pipe-separated list of tool names to detect |

## Process Detection

### Two-tier detection strategy

Based on testing, `pane_current_command` reliably shows:
- `opencode` → displays `opencode` (Bun program)
- `claude` → displays `claude`
- `codex` → displays `node` (Node.js tool, needs deeper inspection)

**Tier 1 — Fast path:**
```
tmux list-panes -t <window_id> -F '#{pane_current_command}'
→ grep for tool names (opencode, claude, codex)
```
Covers opencode and claude directly. Single tmux command + grep.

**Tier 2 — Deep path (for tools not visible via `pane_current_command`):**
When fast path doesn't match, inspect process trees of all panes in the window:
- Get each pane's PID via `tmux list-panes`
- Enumerate child processes (up to 3 levels deep)
- Check each process's full command line for tool name matches
- This catches tools like codex where `pane_current_command` shows `node` instead of the tool name

Cross-platform implementation:
- **Linux:** Enumerate children via `ps --ppid <pid> -o pid=`, read command lines from `/proc/<pid>/cmdline`
- **macOS:** Enumerate children via `ps -ax -o pid,ppid | awk` (macOS `ps` lacks `--ppid` filter), read command lines via `ps -p <pid> -o args=`

The script detects the platform at startup (`uname -s`) and selects the appropriate method.

### Process tree depth

Check up to 3 levels deep from the pane PID (shell → tool shim → node process). Use simple iterative loops, not recursion.

### Performance

- Fast path: one `tmux list-panes` + `grep` — negligible
- Deep path: only triggered for panes showing `node`; involves a few `ps` calls per pane
- tmux caches `#()` results per `status-interval` (default 15s), each window cached independently
- Typical case: 5 windows × 1 script call = 5 lightweight script invocations every 15 seconds

## Format Injection

### Injection strategy

The entry script (`tmux-ai-notify.tmux`):

1. Reads current `window-status-format` and `window-status-current-format` values
2. Checks if already injected (format contains `ai-indicator.sh`) — if so, skip
3. Locates `#I` or `#{window_index}` in the format string
4. Inserts the detection call immediately after: `#I` → `#I#(path/to/ai-indicator.sh #{window_id})`
5. Sets the modified format back

### Edge cases

- Format uses `#{window_index}` instead of `#I` — handle both patterns
- `#I` wrapped in color codes like `#[fg=colour123]#I#[fg=default]` — insert after `#I`, before the next `#[`
- `#I` not found in format — do not inject, preserve original format
- Duplicate load protection — check for `ai-indicator.sh` presence before injecting

### Script path resolution

The entry script dynamically resolves its own directory to construct the absolute path to `ai-indicator.sh`:
```bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$CURRENT_DIR/scripts/ai-indicator.sh"
```

### oh-my-tmux compatibility

oh-my-tmux's `.tmux.conf` sources `.tmux.conf.local` at the end. TPM is initialized in `.tmux.conf.local`, so TPM plugins execute after oh-my-tmux has finalized its format strings. The plugin reads and modifies the final values.

## Error Handling

### Detection script (`ai-indicator.sh`)

- `tmux list-panes` fails (window closed) → output empty string, exit 0
- `/proc/<pid>/cmdline` unreadable (process exited) → skip, continue to next process
- `ps` command fails → skip, continue
- Never output error messages to stdout (would appear in status line)
- All errors redirected to /dev/null

### Entry script (`tmux-ai-notify.tmux`)

- Cannot read current format → do not modify, preserve original
- `#I` not found in format → do not inject
- Duplicate load protection → skip if already injected

## Testing

### Manual test cases

1. Run `opencode` in a pane → ✨ appears for that window
2. Run `claude` in a pane → ✨ appears
3. Run `codex` in a pane → ✨ appears
4. Exit the AI tool → ✨ disappears (after next status refresh)
5. Multiple panes: one with AI tool, one without → ✨ shows
6. Window with no AI tools → no ✨
7. Multiple windows: only windows with AI tools show ✨

### Automated testing

Provide `test.sh` that:
- Simulates pane process detection with mock data
- Verifies script output for positive and negative cases
- Tests both fast path and deep path detection
- Tests cross-platform code paths

## Platform Support

- **Linux:** Full support. Uses `/proc/<pid>/cmdline` for deep path.
- **macOS:** Full support. Uses `ps -p <pid> -o args=` for deep path.
- **Requirements:** tmux >= 2.1, bash, ps (POSIX standard)
