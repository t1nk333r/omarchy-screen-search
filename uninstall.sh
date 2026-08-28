#!/usr/bin/env bash
# Remove Screen Search's integration. --purge also deletes the plugin dir.
# Shared packages are never removed.
set -euo pipefail
PLUGIN_ID="t1nk33r.screen-search"
PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BINDINGS="$HOME/.config/hypr/bindings.lua"
SYMLINK="$HOME/.local/bin/screen-search"
MARK_START="-- >>> screen-search >>>"; MARK_END="-- <<< screen-search <<<"
say() { printf '\033[1;36m::\033[0m %s\n' "$*"; }

if omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1; then say "Disabled bar widget."; fi

if [[ -f $BINDINGS ]] && grep -qF "$MARK_START" "$BINDINGS"; then
  cp -- "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  tmp=$(mktemp)
  awk -v s="$MARK_START" -v e="$MARK_END" '$0 ~ s {skip=1} !skip {print} $0 ~ e {skip=0}' "$BINDINGS" > "$tmp"
  mv -- "$tmp" "$BINDINGS"
  say "Removed keybindings (stock SUPER+CTRL+PRINT returns after: omarchy refresh config hypr/bindings.lua, or on next Hyprland reload if it was default)."
  if command -v hyprctl >/dev/null; then hyprctl reload >/dev/null 2>&1 || true; fi
fi

[[ -L $SYMLINK && $(readlink -f "$SYMLINK") == "$PLUGIN_DIR/bin/screen-search" ]] && { rm -f -- "$SYMLINK"; say "Removed $SYMLINK"; }

if [[ ${1:-} == "--purge" ]]; then
  say "Purging $PLUGIN_DIR"; rm -rf -- "$PLUGIN_DIR"
  if command -v omarchy-shell >/dev/null; then omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true; fi
else
  say "Plugin files kept. Re-enable with: omarchy plugin enable $PLUGIN_ID  (or remove with: $0 --purge)"
fi
