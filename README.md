# Oh My Claude Code Uninstaller

Safe uninstall script for [Oh My Claude Code](https://github.com/Yeachan-Heo/oh-my-claudecode).

It removes the OMC plugin/runtime/config artifacts from Claude Code without touching unrelated plugins or MCP servers.

## Quick Start

Preview first:

```bash
curl -fsSL https://raw.githubusercontent.com/IYENTeam/oh-my-claudecode-uninstaller/main/scripts/uninstall-oh-my-claudecode.sh | bash -s -- --dry-run
```

Remove locally:

```bash
curl -fsSL https://raw.githubusercontent.com/IYENTeam/oh-my-claudecode-uninstaller/main/scripts/uninstall-oh-my-claudecode.sh | bash -s -- --yes
```

Remove on an SSH host:

```bash
curl -fsSL https://raw.githubusercontent.com/IYENTeam/oh-my-claudecode-uninstaller/main/scripts/uninstall-oh-my-claudecode.sh | bash -s -- --target macmini --yes
```

## What It Removes

- Global npm package `oh-my-claude-sisyphus`, if installed.
- OMC-owned `omc` binary/symlink, if found.
- Claude plugin marketplace/cache artifacts:
  - `~/.claude/plugins/marketplaces/omc`
  - `~/.claude/plugins/cache/omc`
  - `~/.claude/plugins/oh-my-claudecode`
- OMC generated state/config/HUD files:
  - `~/.omc`
  - `~/.claude/.omc*`
  - `~/.claude/hud`
  - OMC-marked content under `~/.claude/hooks`
  - OMC-marked content under `~/.claude/agents`
- OMC entries from:
  - `~/.claude/settings.json`
  - `~/.claude/mcp.json`
  - `~/.claude/plugins/installed_plugins.json`
  - `~/.claude/plugins/known_marketplaces.json`
  - `~/.claude.json`
- OMC-injected block inside `~/.claude/CLAUDE.md`.
- OMC skill directories under `~/.claude/skills` when they are clearly OMC-owned.

## What It Does Not Remove By Default

- Other Claude plugins.
- Other MCP servers.
- Historical prompt history (`~/.claude/history.jsonl`).
- Backup/cache history files that merely mention OMC.

Use these options if you also want history/cache cleanup:

```bash
./scripts/uninstall-oh-my-claudecode.sh --yes --remove-history --remove-backups
```

## Options

```text
--dry-run          Show planned changes without modifying files.
--yes              Skip confirmation prompt.
--target HOST      Run over SSH on HOST.
--local            Run locally. Default.
--remove-history   Scrub OMC lines from ~/.claude/history.jsonl.
--remove-backups   Delete OMC-related backup/cache history files under ~/.claude.
--help             Show help.
--version          Show version.
```

## Safety

- The script creates timestamped `.pre-omc-uninstall-*.bak` backups before editing JSON or `CLAUDE.md`.
- JSON edits are targeted to OMC keys/values only.
- `omc` binaries are removed only when their target/content appears OMC-owned.
- Hook and agent directories are removed only when their files are OMC-marked; mixed directories are cleaned selectively.
- `--dry-run` is recommended before running on a remote host.
