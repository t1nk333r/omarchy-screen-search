# No OCR text / capture paths / URLs may be echoed or notified by the libs.
for f in "$PLUGIN_DIR"/lib/*.sh "$PLUGIN_DIR"/bin/*; do
  grep -nE 'notification-send.*(\$text|\$TEXT|\$file|\$FILE|\$url)' "$f" && bad "$(basename "$f") leaks content into a notification" || ok
  grep -nE '^\s*echo .*(\$text|\$TEXT)' "$f" && bad "$(basename "$f") echoes text" || ok
  grep -nE '\beval\b' "$f" && bad "$(basename "$f") uses eval" || ok
done
grep -rl 'curl' "$PLUGIN_DIR"/lib "$PLUGIN_DIR"/bin >/dev/null && bad "network client referenced in lib/bin" || ok
