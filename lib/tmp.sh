#!/usr/bin/env bash
# Runtime capture storage: private dir on tmpfs, one file per capture, swept
# aggressively so screenshots never accumulate.

CAPTURE_DIR="${SCREEN_SEARCH_TMP:-${XDG_RUNTIME_DIR:-/tmp}/screen-search}"

capture_dir() {
  mkdir -p -m 700 "$CAPTURE_DIR"
  chmod 700 "$CAPTURE_DIR" 2>/dev/null || true
  printf '%s' "$CAPTURE_DIR"
}

# New capture path; mktemp keeps the name unguessable.
new_capture_file() {
  mktemp -p "$(capture_dir)" capture-XXXXXXXX.png
}

# Remove one capture; only files inside CAPTURE_DIR are ever deleted.
discard_capture() {
  local f=$1
  [[ -n $f && $f == "$CAPTURE_DIR"/* && -f $f ]] || return 0
  rm -f -- "$f"
}

# Captures older than 10 minutes are orphans (shell crash, killed process).
sweep_captures() {
  [[ -d $CAPTURE_DIR ]] || return 0
  find "$CAPTURE_DIR" -maxdepth 1 -type f -name 'capture-*' \( -mmin +10 -o -empty \) -delete 2>/dev/null || true
}
