# No OCR text / capture paths / URLs may be echoed or notified by the libs.
for f in "$PLUGIN_DIR"/lib/*.sh "$PLUGIN_DIR"/bin/*; do
  sed -e 's/--image "\$file"//g' -e 's/--file "\$file"//g' "$f" | grep -nE 'notification-send.*(\$text|\$TEXT|\$file|\$FILE|\$url)' && bad "$(basename "$f") leaks content into a notification" || ok
  grep -nE '^\s*echo .*(\$text|\$TEXT)' "$f" && bad "$(basename "$f") echoes text" || ok
  grep -nE '\beval\b' "$f" && bad "$(basename "$f") uses eval" || ok
done
# Sanctioned network code: bin/screen-search-doctor (explicit diagnostics) and
# lib/upload.sh (reachable ONLY via the consent gate; upload.test.sh proves the
# unconfirmed path never invokes curl). Everything else stays offline.
/usr/bin/grep -rl 'curl' "$PLUGIN_DIR"/lib "$PLUGIN_DIR"/bin --exclude=screen-search-doctor --exclude=upload.sh >/dev/null && bad "network client in runtime path" || ok
# upload_ephemeral has exactly one call site outside its own file: the confirmed path.
n=$(/usr/bin/grep -rn 'upload_ephemeral ' "$PLUGIN_DIR"/lib "$PLUGIN_DIR"/bin --exclude=upload.sh | /usr/bin/grep -cv '^Binary')
[[ $n -eq 1 ]] && ok || bad "upload_ephemeral must be called only from visual_search_confirmed (found $n call sites)"
