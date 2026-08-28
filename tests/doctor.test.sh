# doctor: flags off-site redirects / dead endpoints, exits 0 when healthy
DOC_FAKE=$(mktemp -d)
cat > "$DOC_FAKE/curl" <<'X'
#!/usr/bin/env bash
url=${!#}
case $url in
  *bing.com*) printf '302 https://explore.microsoft.com/promo' ;;
  *imgops*)   printf '000 ' ;;
  *)          printf '200 ' ;;
esac
X
chmod +x "$DOC_FAKE/curl"
out=$(PATH="$DOC_FAKE:$PATH" "$S" doctor 2>&1); rc=$?
assert_rc "$rc" 1 "doctor exits 1 on unhealthy endpoints"
/usr/bin/grep -q 'REDIRECTS OFF-SITE -> explore.microsoft.com' <<<"$out" && ok || bad "doctor flags off-site redirect"
/usr/bin/grep -q 'UNREACHABLE' <<<"$out" && ok || bad "doctor flags unreachable"
cat > "$DOC_FAKE/curl" <<'X'
#!/usr/bin/env bash
printf '200 '
X
chmod +x "$DOC_FAKE/curl"
PATH="$DOC_FAKE:$PATH" "$S" doctor >/dev/null 2>&1; assert_rc $? 0 "doctor exits 0 when all healthy"
rm -rf "$DOC_FAKE"
