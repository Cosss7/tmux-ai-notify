# tmux-ai-notify

A tmux plugin that displays an indicator in the status line when a window has
panes running AI coding tools (opencode, claude, codex).

## Installation

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to your `.tmux.conf` (or `.tmux.conf.local` for oh-my-tmux users):

```tmux
set -g @plugin 'Cosss7/tmux-ai-notify'
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
