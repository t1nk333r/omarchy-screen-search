S="$PLUGIN_DIR/bin/screen-search"
source "$PLUGIN_DIR/lib/tmp.sh"
d=$(capture_dir); assert_eq "$(stat -c %a "$d")" "700" "capture dir is 0700"
f=$(new_capture_file); [[ -f $f ]] && ok || bad "capture file created"
"$S" act discard --file "$f"; [[ ! -e $f ]] && ok || bad "discard removes capture"
"$S" act discard --file /etc/hostname; [[ -e /etc/hostname ]] && ok || bad "discard refuses paths outside capture dir"
old=$(new_capture_file); touch -d '20 minutes ago' "$old"; sweep_captures; [[ ! -e $old ]] && ok || bad "sweep removes stale captures"
# save copies out of the runtime dir
f=$(new_capture_file); printf 'PNG' > "$f"
OMARCHY_SCREENSHOT_DIR="$SCREEN_SEARCH_TMP/pics" "$S" act save --file "$f"
ls "$SCREEN_SEARCH_TMP"/pics/screenshot-*.png >/dev/null 2>&1 && ok || bad "save writes screenshot"
[[ -f $f ]] && ok || bad "save keeps the capture for further actions"
# capture script: cancelled selection → 10, file cleaned
cat > "$PLUGIN_DIR/tests/fakebin/omarchy-capture-region" <<'X'
#!/usr/bin/env bash
echo 12345; echo ""; exit 1
X
chmod +x "$PLUGIN_DIR/tests/fakebin/omarchy-capture-region"
before=$(ls "$SCREEN_SEARCH_TMP" | wc -l)
"$PLUGIN_DIR/bin/screen-search-capture" --mode circle >/dev/null 2>&1; assert_rc $? 10 "cancel exits 10"
assert_eq "$(ls "$SCREEN_SEARCH_TMP" | wc -l)" "$before" "cancel leaves no capture file"
rm -f "$PLUGIN_DIR/tests/fakebin/omarchy-capture-region"
