# No OCR text / capture paths / URLs may be echoed or notified by the libs.
for f in "$PLUGIN_DIR"/lib/*.sh "$PLUGIN_DIR"/bin/*; do
  sed -e 's/--image "\$file"//g' -e 's/--file "\$file"//g' "$f" | grep -nE 'notification-send.*(\$text|\$TEXT|\$file|\$FILE|\$url)' && bad "$(basename "$f") leaks content into a notification" || ok
  grep -nE '^\s*echo .*(\$text|\$TEXT)' "$f" && bad "$(basename "$f") echoes text" || ok
  grep -nE '\beval\b' "$f" && bad "$(basename "$f") uses eval" || ok
done
/usr/bin/grep -rl 'curl' "$PLUGIN_DIR"/lib "$PLUGIN_DIR"/bin --exclude=screen-search-doctor >/dev/null && bad "network client in runtime path (doctor is the only sanctioned one)" || ok
