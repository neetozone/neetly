# neetly

A terminal multiplexer with browser panes, built on SwiftTerm and WKWebView.

## Install

```bash
# Build
swift build

# Symlink the CLI to your PATH
ln -sf $(pwd)/.build/arm64-apple-macosx/debug/neetly /usr/local/bin/neetly
```

## Run

```bash
swift run neetly-app
```

On first launch, add a repo and configure its default layout. Repos are persisted at `~/.config/neetly/repos.json`.

## Layout Config

Declarative pane layout using `split`, `tabs`, `run`, and `visit`:

```yaml
split: columns
left:
  run: claude --dangerously-skip-permissions
right:
  tabs:
    run: bin/setup;bin/launch --neetly
    visit: http://localhost:3000
```

| Key | Value | Children |
|---|---|---|
| `split` | `columns` | `left:` and `right:` |
| `split` | `rows` | `top:` and `bottom:` |
| `tabs` | — | Multiple `run`/`visit` as tabs in one pane |
| `run` | `<command>` | Terminal tab |
| `visit` | `<url>` | Browser tab |

## CLI Commands

The `neetly` CLI runs from inside any terminal spawned by neetly. It communicates with the app via a Unix domain socket.

### List tabs

```bash
neetly tabs
```

```
TAB  PANE  TYPE      TITLE
--------------------------------------------------
1    1     terminal  claude *
2    2     terminal  bin/launch *
3    2     browser   localhost *
```

### Open a browser tab

```bash
# In current pane (default)
neetly browser open http://localhost:3000

# In a specific pane
neetly browser open http://localhost:3000 --pane 3

# Without stealing focus
neetly browser open http://localhost:3000 --background

# Short alias
neetly visit http://localhost:3000
```

### Send text to a terminal tab

```bash
# Send "time" + Enter to tab 1
neetly send 1 "time\n"
```

`\n` is converted to a newline (Enter key). `\t` is converted to a tab.

### Open a new terminal tab

```bash
neetly run "npm test"
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+T | New terminal tab in focused pane |
| Cmd+Shift+T | New browser tab in focused pane |
| Cmd+W | Close active tab |
| Cmd+K | Clear terminal |
| Cmd+R | Reload browser |
| Cmd+Shift+] | Next tab |
| Cmd+Shift+[ | Previous tab |

## Taxonomy

```
Workspace (named after your feature/bug, multiple per window)
  Pane (a rectangular region, split horizontally or vertically)
    Tab (terminal or browser — multiple per pane, one visible at a time)
```

## Architecture

- **Terminal**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (upgrade path to libghostty for GPU rendering)
- **Browser**: WKWebView (native macOS WebKit, zero dependencies)
- **IPC**: Unix domain socket at `/tmp/neetly-<pid>.sock`
- **Persistence**: `~/.config/neetly/repos.json`
- **File watcher**: Polls for frontend file changes, auto-reloads browser tabs
