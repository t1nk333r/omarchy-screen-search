#!/usr/bin/env bash
# Install Screen Search: dependency check, plugin enable, keybindings, symlink,
# first-run provider choice. Idempotent — running it twice changes nothing.
set -euo pipefail

PLUGIN_ID="t1nk33r.screen-search"
PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BINDINGS="$HOME/.config/hypr/bindings.lua"
SYMLINK="$HOME/.local/bin/screen-search"
MARK_START="-- >>> screen-search >>>"
MARK_END="-- <<< screen-search <<<"

say()  { printf '\033[1;36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
interactive() { [[ -t 0 && -t 1 ]]; }

# --- dependencies ------------------------------------------------------------
declare -A REQUIRED=(
  [slurp]=slurp [grim]=grim [hyprpicker]=hyprpicker [tesseract]=tesseract
  [wl-copy]=wl-clipboard [jq]=jq [quickshell]=quickshell
)
missing=()
for cmd in "${!REQUIRED[@]}"; do have "$cmd" || missing+=("${REQUIRED[$cmd]}"); done
if ((${#missing[@]})); then
  warn "Missing required packages: ${missing[*]}"
  if have omarchy && interactive; then
    say "Installing with: omarchy pkg add ${missing[*]}"
    omarchy pkg add "${missing[@]}"
  else
    warn "Install them, then re-run: omarchy pkg add ${missing[*]}"
    exit 1
  fi
fi
have zbarimg || warn "Optional: zbar not found — QR decoding will be unavailable (omarchy pkg add zbar)."

# --- optional Arabic OCR -----------------------------------------------------
if ! tesseract --list-langs 2>/dev/null | grep -qx ara; then
  if interactive && have gum && gum confirm "Install Arabic OCR language data (tesseract-data-ara)?"; then
    omarchy pkg add tesseract-data-ara
  else
    say "Arabic OCR not installed. Add later with: omarchy pkg add tesseract-data-ara"
  fi
fi

# --- enable plugin -----------------------------------------------------------
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || warn "Shell not running; it will pick up the plugin on next start."
if omarchy plugin list 2>/dev/null | grep -q "$PLUGIN_ID.*enabled"; then
  say "Plugin already enabled."
else
  omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 && say "Enabled bar widget." \
    || warn "Could not enable via IPC; enable it from Setup > Plugins."
fi

# --- CLI symlink -------------------------------------------------------------
mkdir -p "$(dirname "$SYMLINK")"
if [[ -L $SYMLINK && $(readlink -f "$SYMLINK") == "$PLUGIN_DIR/bin/screen-search" ]]; then
  :
elif [[ -e $SYMLINK && ! -L $SYMLINK ]]; then
  warn "$SYMLINK exists and is not our symlink; leaving it alone."
else
  ln -sfn "$PLUGIN_DIR/bin/screen-search" "$SYMLINK"; say "Linked $SYMLINK"
fi

# --- keybindings (idempotent marked block) -----------------------------------
if [[ -f $BINDINGS ]]; then
  cp -- "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  # Remove any previous block, then append the current one.
  tmp=$(mktemp)
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 ~ s {skip=1} !skip {print} $0 ~ e {skip=0}' "$BINDINGS" > "$tmp"
  cat >> "$tmp" <<'LUA'
-- >>> screen-search >>>
-- Screen Search: OCR + Circle to Search. SUPER+CTRL+PRINT was Omarchy's
-- stock OCR (omarchy-capture-text); it is rebound here to the OCR mode with a
-- result OSD. The stock behaviour is still available as `omarchy capture text`.
hl.unbind("SUPER + CTRL + PRINT")
o.bind("SUPER + CTRL + PRINT", "OCR screen region", "screen-search ocr")
o.bind("SUPER + SHIFT + PRINT", "Circle to Search", "screen-search circle")
o.bind("SUPER + CTRL + ALT + PRINT", "Search clipboard text", "screen-search clipboard")
-- <<< screen-search <<<
LUA
  mv -- "$tmp" "$BINDINGS"
  say "Installed keybindings (SUPER+SHIFT+PRINT, SUPER+CTRL+PRINT, SUPER+CTRL+ALT+PRINT)."
  warn "SUPER+CTRL+PRINT was Omarchy's stock OCR; it now opens the Screen Search OCR OSD."
  have hyprctl && { hyprctl reload >/dev/null 2>&1 || true; hyprctl configerrors 2>/dev/null | grep -qi error && warn "hyprctl reported config errors — check $BINDINGS"; }
else
  warn "No $BINDINGS; skipping keybindings. Bind 'screen-search circle' yourself."
fi

# --- first-run provider choice ----------------------------------------------
current_entry_has_provider() {
  jq -e --arg id "$PLUGIN_ID" '
    [ (.bar.layout // {} | to_entries[]?.value[]?), (.plugins // [])[]? ]
    | map(select(type=="object" and .id==$id and (.provider != null))) | length > 0
  ' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1
}
if ! current_entry_has_provider; then
  if interactive && have gum; then
    say "Choose your default search provider:"
    choice=$(printf '%s\n' \
      "google — text + visual (Lens)" \
      "bing — text + visual" \
      "brave — text only" \
      "duckduckgo — text only" \
      "yandex — text + visual" \
      "tineye — reverse image only" | gum choose --header "Default provider") || choice=""
    provider=${choice%% *}
    [[ -n $provider ]] && "$PLUGIN_DIR/bin/screen-search" provider "$provider" && say "Default provider: $provider"
  else
    say "Default provider is google. Change with: screen-search provider bing (or via right-click on the bar icon)."
  fi
fi

say "Screen Search installed. Left-click the magnifier for Circle to Search; right-click for the menu."
