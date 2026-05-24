#!/usr/bin/env bash
set -u

VERSION="0.1.0"
DRY_RUN=0
YES=0
TARGET="local"
REMOVE_HISTORY=0
REMOVE_BACKUPS=0

usage() {
  cat <<'USAGE'
uninstall-oh-my-claudecode.sh - remove Oh My Claude Code (OMC) from Claude Code

Usage:
  ./scripts/uninstall-oh-my-claudecode.sh [options]

Options:
  --dry-run              Show what would be removed without changing anything.
  --yes                  Do not ask for confirmation.
  --target HOST          Run cleanup on an SSH host, for example: --target macmini.
  --local                Run cleanup on this machine. Default.
  --remove-history       Also scrub OMC entries from ~/.claude/history.jsonl.
  --remove-backups       Also delete OMC-related backup/history cache files under ~/.claude.
  -h, --help             Show help.
  --version              Show script version.

What it removes:
  - OMC npm package: oh-my-claude-sisyphus, if installed globally.
  - OMC CLI binary/symlink, if present.
  - Claude plugin marketplace/cache entries for oh-my-claudecode.
  - OMC generated config/state/HUD/hooks/agents/skills under ~/.claude and ~/.omc.
  - OMC entries from Claude JSON config files: settings.json, mcp.json,
    installed_plugins.json, known_marketplaces.json, and ~/.claude.json.

What it does NOT remove by default:
  - Unrelated Claude plugins or MCP servers.
  - Historical prompt history and backup files, unless explicitly requested.
USAGE
}

warn() { printf 'WARN: %s\n' "$*" >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) YES=1 ;;
    --target)
      shift
      TARGET="${1:-}"
      [ -n "$TARGET" ] || { warn '--target requires a host'; exit 2; }
      ;;
    --local) TARGET="local" ;;
    --remove-history) REMOVE_HISTORY=1 ;;
    --remove-backups) REMOVE_BACKUPS=1 ;;
    --version) printf '%s\n' "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) warn "Unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

run_payload() {
  bash -s <<'PAYLOAD'
set -u

say() { printf '%s\n' "$*"; }
do_run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

json_cleanup() {
python3 - <<'PY'
import json
import os
import shutil
from datetime import datetime
from pathlib import Path

home = Path.home()
dry_run = os.environ.get("DRY_RUN") == "1"
stamp = datetime.utcnow().isoformat().replace(":", "-").replace(".", "-")
omc_terms = (
    "oh-my-claudecode",
    "plugin_oh-my-claudecode",
    "oh-my-claude-sisyphus",
    "omc-hud",
    "omc-setup",
)

def has_omc(value):
    try:
        text = json.dumps(value).lower()
    except Exception:
        text = str(value).lower()
    return any(term in text for term in omc_terms) or '"omc"' in text

def backup(path: Path):
    if dry_run or not path.exists():
        return
    shutil.copy2(path, path.with_name(path.name + f".pre-omc-uninstall-{stamp}.bak"))

def write_json(path: Path, data):
    if dry_run:
        print(f"[dry-run] update JSON {path}")
        return
    backup(path)
    path.write_text(json.dumps(data, indent=2) + "\n")

for rel in (
    ".claude/settings.json",
    ".claude/plugins/installed_plugins.json",
    ".claude/plugins/known_marketplaces.json",
    ".claude/mcp.json",
    ".claude.json",
):
    path = home / rel
    if not path.exists():
        continue
    try:
        data = json.loads(path.read_text())
    except Exception as exc:
        print(f"WARN: skip invalid JSON {path}: {exc}")
        continue
    changed = False

    if rel == ".claude/settings.json":
        plugins = data.get("enabledPlugins")
        if isinstance(plugins, dict):
            for key in list(plugins):
                if has_omc(key):
                    del plugins[key]
                    changed = True
            if not plugins:
                data.pop("enabledPlugins", None)
        markets = data.get("extraKnownMarketplaces")
        if isinstance(markets, dict) and "omc" in markets:
            del markets["omc"]
            changed = True
            if not markets:
                data.pop("extraKnownMarketplaces", None)
        status = data.get("statusLine")
        if isinstance(status, dict) and has_omc(status):
            data.pop("statusLine", None)
            changed = True
        hooks = data.get("hooks")
        if isinstance(hooks, dict):
            for key in list(hooks):
                if has_omc(hooks[key]):
                    hooks[key] = [] if isinstance(hooks[key], list) else {}
                    changed = True

    elif rel == ".claude/plugins/installed_plugins.json":
        plugins = data.get("plugins")
        if isinstance(plugins, dict):
            for key in list(plugins):
                if has_omc(key) or has_omc(plugins[key]):
                    del plugins[key]
                    changed = True

    elif rel == ".claude/plugins/known_marketplaces.json":
        if "omc" in data:
            del data["omc"]
            changed = True

    elif rel == ".claude/mcp.json":
        servers = data.get("mcpServers")
        if isinstance(servers, dict):
            for key in list(servers):
                if has_omc(key) or has_omc(servers[key]):
                    del servers[key]
                    changed = True

    elif rel == ".claude.json":
        usage = data.get("skillUsage")
        if isinstance(usage, dict):
            for key in list(usage):
                if has_omc(key):
                    del usage[key]
                    changed = True
        servers = data.get("mcpServers")
        if isinstance(servers, dict):
            for key in list(servers):
                if has_omc(key) or has_omc(servers[key]):
                    del servers[key]
                    changed = True
        projects = data.get("projects")
        if isinstance(projects, dict):
            for key in list(projects):
                if key.endswith("/tmp/omc") or has_omc(projects[key]):
                    del projects[key]
                    changed = True

    if changed:
        write_json(path, data)
PY
}

remove_path() {
  path=$1
  if [ -e "$path" ] || [ -L "$path" ]; then
    do_run "rm -rf \"$path\""
  fi
}

say "Scanning Oh My Claude Code artifacts under $HOME"
json_cleanup

if command -v npm >/dev/null 2>&1; then
  do_run "npm uninstall -g oh-my-claude-sisyphus >/dev/null 2>&1 || true"
else
  say "npm not found; skipping npm package uninstall"
fi

for bin in /usr/local/bin/omc /opt/homebrew/bin/omc "$HOME/.local/bin/omc"; do
  if [ -L "$bin" ]; then
    target=$(readlink "$bin" 2>/dev/null || true)
    case "$target" in
      *oh-my-claude-sisyphus*|*oh-my-claudecode*) remove_path "$bin" ;;
    esac
  elif [ -f "$bin" ] && grep -qi "oh-my-claude\|oh-my-claudecode" "$bin" 2>/dev/null; then
    remove_path "$bin"
  fi
done

for path in \
  "$HOME/.omc" \
  "$HOME/.claude/.omc" \
  "$HOME/.claude/.omc-config.json" \
  "$HOME/.claude/.omc-version.json" \
  "$HOME/.claude/hud" \
  "$HOME/.claude/plugins/oh-my-claudecode" \
  "$HOME/.claude/plugins/marketplaces/omc" \
  "$HOME/.claude/plugins/cache/omc"; do
  remove_path "$path"
done

python3 - <<'PY'
import os
import shutil
from pathlib import Path

home = Path.home()
dry_run = os.environ.get("DRY_RUN") == "1"
markers = ("oh-my-claudecode", "oh-my-claude-sisyphus", "omc-hud", "omc-setup")

def marked(path: Path) -> bool:
    name = path.name.lower()
    if "omc" in name or "claudecode" in name:
        return True
    if path.is_file():
        try:
            text = path.read_text(errors="ignore").lower()
        except Exception:
            return False
        return any(marker in text for marker in markers)
    return False

def remove(path: Path):
    if dry_run:
        print(f"[dry-run] remove {path}")
    elif path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)

for rel in (".claude/hooks", ".claude/agents"):
    root = home / rel
    if not root.exists():
        continue
    files = [p for p in root.rglob("*") if p.is_file()]
    if files and all(marked(p) for p in files):
        remove(root)
        continue
    for child in sorted(root.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if marked(child):
            remove(child)
    for child in sorted([p for p in root.rglob("*") if p.is_dir()], key=lambda p: len(p.parts), reverse=True):
        try:
            next(child.iterdir())
        except StopIteration:
            remove(child)
PY

python3 - <<'PY'
import os
import shutil
from datetime import datetime
from pathlib import Path

home = Path.home()
dry_run = os.environ.get("DRY_RUN") == "1"
path = home / ".claude/CLAUDE.md"
if path.exists():
    text = path.read_text(errors="replace")
    start = text.find("<!-- OMC:START -->")
    end = text.find("<!-- OMC:END -->")
    if start != -1 and end != -1:
        if dry_run:
            print(f"[dry-run] remove OMC block from {path}")
        else:
            stamp = datetime.utcnow().isoformat().replace(":", "-").replace(".", "-")
            shutil.copy2(path, path.with_name(path.name + f".pre-omc-uninstall-{stamp}.bak"))
            end += len("<!-- OMC:END -->")
            new = (text[:start] + text[end:]).strip()
            path.write_text(new + ("\n" if new else ""))
PY

python3 - <<'PY'
import os
import shutil
from pathlib import Path

home = Path.home()
dry_run = os.environ.get("DRY_RUN") == "1"
skills = home / ".claude/skills"
explicit_omc_names = {"omc-reference", "omc-setup", "omc-doctor", "omc-teams", "omc-plan"}
if skills.exists():
    for child in skills.iterdir():
        if not child.is_dir():
            continue
        hit = child.name.startswith("omc-") or child.name in explicit_omc_names
        if not hit:
            for file in child.rglob("*"):
                if not file.is_file():
                    continue
                try:
                    text = file.read_text(errors="ignore").lower()
                except Exception:
                    continue
                if "oh-my-claudecode" in text or "oh-my-claude-sisyphus" in text:
                    hit = True
                    break
        if hit:
            if dry_run:
                print(f"[dry-run] remove skill {child}")
            else:
                shutil.rmtree(child)
PY

if [ "${REMOVE_HISTORY:-0}" = "1" ] && [ -f "$HOME/.claude/history.jsonl" ]; then
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[dry-run] scrub OMC lines from %s\n' "$HOME/.claude/history.jsonl"
  else
    cp "$HOME/.claude/history.jsonl" "$HOME/.claude/history.jsonl.pre-omc-uninstall.$(date +%Y%m%d%H%M%S).bak"
    grep -viE "oh-my-claudecode|oh-my-claude-sisyphus|/omc-setup|omc update|omc doctor|setup omc" "$HOME/.claude/history.jsonl" > "$HOME/.claude/history.jsonl.tmp" || true
    mv "$HOME/.claude/history.jsonl.tmp" "$HOME/.claude/history.jsonl"
  fi
fi

if [ "${REMOVE_BACKUPS:-0}" = "1" ] && [ -d "$HOME/.claude" ]; then
  find "$HOME/.claude" \( -path "*/backups/*" -o -path "*/paste-cache/*" -o -path "*/file-history/*" \) -type f 2>/dev/null | while IFS= read -r file; do
    if grep -qiE "oh-my-claudecode|oh-my-claude-sisyphus|omc-hud|omc-setup" "$file" 2>/dev/null; then
      remove_path "$file"
    fi
  done
fi

say "Done."
PAYLOAD
}

if [ "$TARGET" != "local" ]; then
  command -v ssh >/dev/null 2>&1 || { warn 'ssh is required for --target'; exit 1; }
  [ "$YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || {
    printf 'Remove Oh My Claude Code from SSH host %s? [y/N] ' "$TARGET"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) printf 'Aborted.\n'; exit 1 ;; esac
  }
  remote_args="--local"
  [ "$DRY_RUN" -eq 1 ] && remote_args="$remote_args --dry-run"
  [ "$YES" -eq 1 ] && remote_args="$remote_args --yes"
  [ "$REMOVE_HISTORY" -eq 1 ] && remote_args="$remote_args --remove-history"
  [ "$REMOVE_BACKUPS" -eq 1 ] && remote_args="$remote_args --remove-backups"
  ssh "$TARGET" "tmp=\$(mktemp); cat > \"\$tmp\"; chmod +x \"\$tmp\"; \"\$tmp\" $remote_args; rc=\$?; rm -f \"\$tmp\"; exit \$rc" < "$0"
  exit $?
fi

[ "$YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || {
  printf 'Remove Oh My Claude Code from this machine? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) printf 'Aborted.\n'; exit 1 ;; esac
}

DRY_RUN=$DRY_RUN REMOVE_HISTORY=$REMOVE_HISTORY REMOVE_BACKUPS=$REMOVE_BACKUPS run_payload
