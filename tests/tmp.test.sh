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
# capture script: cancelled selection (empty slurp) → 10, no capture left,
# and the fake freeze is reaped.
before=$(ls "$SCREEN_SEARCH_TMP" | wc -l)
"$PLUGIN_DIR/bin/screen-search-capture" --mode circle >/dev/null 2>&1; assert_rc $? 10 "cancel exits 10"
assert_eq "$(ls "$SCREEN_SEARCH_TMP" | wc -l)" "$before" "cancel leaves no capture file"
# a real selection produces JSON and keeps the file; freeze is killed after grim
out=$(SLURP_GEOM="10,10 100x100" "$PLUGIN_DIR/bin/screen-search-capture" --mode circle 2>/dev/null); rc=$?
assert_rc "$rc" 0 "selection exits 0"
[[ $(jq -r .kind <<<"$out") == image ]] && ok || bad "selection returns image kind"
cf=$(jq -r .file <<<"$out"); [[ -f $cf ]] && ok || bad "capture file kept after selection"


# containment: traversal and symlinks are refused
victim="$SCREEN_SEARCH_TMP/../discard-victim.$$"; touch "$victim"
"$S" act discard --file "$SCREEN_SEARCH_TMP/../$(basename "$victim")"
[[ -e $victim ]] && ok || bad "discard refuses ../ traversal"
rm -f "$victim"
tgt="$SCREEN_SEARCH_TMP/keep-target.png"; lnk="$SCREEN_SEARCH_TMP/capture-link.png"
touch "$tgt"; ln -s "$tgt" "$lnk"
"$S" act discard --file "$lnk"
[[ -e $tgt ]] && ok || bad "discard does not follow symlinks"
rm -f "$lnk" "$tgt"
