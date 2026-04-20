# neetly

The code editor that works with agents and is meant for **web development**.

<p align="center">
  <a href="https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download neetly for macOS" width="180" />
  </a>
</p>

## Installation instructions

1. Download [neetly-macos.dmg](https://github.com/neetozone/neetly/releases/latest/download/neetly-macos.dmg) and open the DMG and drag `neetly.app` to Applications.
2. Set up Claude Code notifications (one-time): Execute the following command to do a one-time setup. It adds hooks to `~/.claude/settings.json` so that neetly
   is notified when Claude is done processing and is waiting. When Claude is done, the workspace tab turns "green".
    If Claude is waiting for permission, then the workspace tab turns "red". Clicking a colored workspace tab also clears the color.

   ```bash
   /Applications/neetly.app/Contents/MacOS/neetly notify_neetly_of_claude_events
   ```

### Build from source

```bash
git clone https://github.com/neetozone/neetly.git
cd neetly
swift build

# Symlink the CLI to your PATH
ln -sf $(pwd)/.build/arm64-apple-macosx/debug/neetly /usr/local/bin/neetly

# Run
swift run neetly-app
```

## Tech Stack

<p>
 <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white" alt="Swift"></a>
 <a href="https://developer.apple.com/xcode/swiftui/"><img src="https://img.shields.io/badge/SwiftUI-0071E3?logo=swift&logoColor=white" alt="SwiftUI"></a>
 <a href="https://developer.apple.com/documentation/appkit"><img src="https://img.shields.io/badge/AppKit-333333?logo=apple&logoColor=white" alt="AppKit"></a>
 <a href="https://github.com/migueldeicaza/SwiftTerm"><img src="https://img.shields.io/badge/SwiftTerm-191970?logo=terminal&logoColor=white" alt="SwiftTerm"></a>
 <a href="https://developer.apple.com/documentation/webkit/wkwebview"><img src="https://img.shields.io/badge/WKWebView-006AFF?logo=safari&logoColor=white" alt="WKWebView"></a>
 <a href="https://developer.apple.com/swift/"><img src="https://img.shields.io/badge/Swift_Package_Manager-F05138?logo=swift&logoColor=white" alt="SPM"></a>
</p>

## Viewint the diff

* Cmd+D is configured to show you the diff by executing `lazygit`. If you want to use a different tool for the diff
  then you can configure it in **Settings**.
* After viewing the diff you can close the diff by executing Cmd+Z.
* Here is what Cmd+D does: opens a new terminal in the right most pane. Executes the **diff command** specified in the **Settings**. Hits Cmd+Shift+m to maximize the window.
* Here is what Cmd+Z does: Hits Cmd+Shift+m to get out of the full screen mode and then kills that tab.

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
| `size` | `35%` | Percentage of the parent split taken by this child. Optional; defaults to 50/50. |

### Sizing splits

By default, every split is 50/50. Add a `size` attribute to any child to change that:

```yaml
split: columns
left:
  size: 35%
  run: claude --dangerously-skip-permissions
right:
  run: bin/setup-mise;bin/launch --neetly
```

The left pane takes 35% of the width, the right pane takes the remaining 65%. If you specify sizes on both sides and they don't add up to 100%, the first one wins and the second gets the remainder — no error. `size` can appear in any child of a `split` (left/right/top/bottom) and nests naturally.

## CLI Commands

The `neetly` CLI runs in any terminal spawned by' neetly'. It communicates with the app via a Unix domain socket.

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

### Send commands to a terminal tab

```bash
# Send "time" + Enter to tab 1
neetly send 1 "time\n"
```

`\n` is converted to a newline (Enter key). `\t` is converted to a tab.

### Open a new terminal tab

```bash
neetly run "npm test"
```

### Workspace notifications

Change the workspace tab color to signal status across workspaces. Useful when Claude finishes a task while you're working in another workspace.

```bash
neetly notify              # green (task done)
neetly notify red          # red (Claude needs permission)
neetly notify clear        # reset to normal
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
| Cmd+Click | Open a URL displayed in the terminal |

## Taxonomy

```
Workspace (named after your feature/bug, multiple per window)
  Pane (a rectangular region, split horizontally or vertically)
    Tab (terminal or browser — multiple per pane, one visible at a time)
```

## Terminal Appearance

Customize the terminal font, size, and colors by creating `~/.config/neetly/terminal.json`:

```json
{
  "fontFamily": "JetBrains Mono",
  "fontSize": 17,
  "backgroundColor": "#1e1f2e",
  "foregroundColor": "#cdd8f4",
  "selectionColor": "#635b70",
  "linkColor": "#8bb8fa"
}
```

| Field | Description | Default |
|---|---|---|
| `fontFamily` | Any font installed on your system. Falls back to Symbols Nerd Font Mono, Noto Color Emoji, then system monospace. | `JetBrains Mono` |
| `fontSize` | Point size. | `17` |
| `backgroundColor` | Hex color (`#RRGGBB`). | `#1e1f2e` (Catppuccin base) |
| `foregroundColor` | Hex color (`#RRGGBB`). | `#cdd8f4` (Catppuccin text) |
| `selectionColor` | Background color for selected text. | `#635b70` |
| `linkColor` | Overrides ANSI palette blue (colors 4 and 12), where most terminals render URLs. | `#8bb8fa` |
| `scrollback` | Number of lines retained in the scroll-back buffer. | `10000` |

All fields are optional — omit any to use the default. The config is read when each terminal tab is created, so restart neetly to pick up changes.

## Architecture

- **Terminal**: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (pure Swift, CPU-rendered). In the future, we could swap it for [libghostty](https://github.com/ghostty-org/ghostty) (Ghostty's Zig-based engine with Metal GPU rendering) for better performance on 4K displays and large scrollback workloads. It's a "someday maybe" note, not anything planned.
- **Browser**: [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) is Apple's native web view — the same WebKit engine that powers Safari. It's built into macOS, so neetly ships with zero browser dependencies and no extra download (unlike Electron or CEF which bundle a full Chromium). Every browser tab in neetly is a `WKWebView` embedded directly in the window.

  **Debugging browser tabs with Safari's Web Inspector**: neetly enables `isInspectable` on all browser tabs, so you can use Safari's full Web Inspector (DOM, console, network, breakpoints) against them. One-time setup: Safari → Settings → Advanced → check "Show features for web developers". Then in Safari → Develop → (your Mac name), you'll see all of neetly's open browser tabs listed. Click one to attach the inspector.
- **IPC**: Unix domain socket at `/tmp/neetly-<pid>.sock`
- **Persistence**:
  - `~/.config/neetly/repos.json` — list of added repos and their default layouts
  - `~/.config/neetly/workspaces.json` — open workspaces, restored on relaunch
  - `~/.config/neetly/terminal.json` — terminal font and color overrides
  - `~/neetly/<repo-name>/<workspace-name>` — git worktrees are created here, one per workspace
- **File watcher**: WKWebView (WebKit) does not support HMR (Hot Module Replacement) the way Chrome's DevTools protocol does, so neetly polls the repo every 2 seconds for changes to JavaScript/React/CSS files and triggers a browser reload when anything changes.

# FAQ

### What is WKWebView

Please see [this](https://github.com/neetozone/neetly/blob/main/docs/wkwebview.md).

### Why you are not using Google Chrome

Google chrome would be nice but that is a much more heavy lift. I noticed that
WKWebView gets 98% of my work done. For the remaining 2% cases I open Google Chrome
and do the work there.
