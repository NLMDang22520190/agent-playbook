#!/usr/bin/env bash
# Fake `curl` for the GitHub Releases check of `install.sh update` (v0.33.0 S4, AC6'). Source from a suite in tests/.
# No test reaches the network: the fake answers instead of the real curl.
#
# rf_fake_curl DIR   writes DIR/curl (executable). Put DIR first on PATH.
#   The fake accepts exactly the contract call:  curl -sS -o /dev/null -w '%{http_code}' URL
#   It appends one line per call to $PB_FAKE_CURL_LOG: all argv, joined by single spaces, URL last.
#   It prints the HTTP code only (no newline), like curl -w '%{http_code}' -o /dev/null.
#   Answer for URL: the line "URL CODE" in the file $PB_FAKE_CURL_MAP, else $PB_FAKE_CURL_DEFAULT (default 404).
#   CODE "FAIL" means a curl failure: no output, exit 6. A call that has no -w '%{http_code}' gets exit 2.
rf_fake_curl() {
  mkdir -p "$1" || return 1
  cat > "$1/curl" <<'FAKE'
#!/usr/bin/env bash
url=""; haveW=0
for a in "$@"; do
  case "$a" in
    %\{http_code\}) haveW=1 ;;
    http://*|https://*) url="$a" ;;
  esac
done
[ -z "${PB_FAKE_CURL_LOG:-}" ] || printf '%s\n' "$*" >> "$PB_FAKE_CURL_LOG"
if [ "$haveW" != 1 ]; then echo "fake curl: no -w %{http_code} in: $*" >&2; exit 2; fi
code=""
if [ -n "${PB_FAKE_CURL_MAP:-}" ] && [ -f "$PB_FAKE_CURL_MAP" ]; then
  while IFS=' ' read -r u c; do
    [ "$u" = "$url" ] && code="$c"
  done < "$PB_FAKE_CURL_MAP"
fi
[ -n "$code" ] || code="${PB_FAKE_CURL_DEFAULT:-404}"
if [ "$code" = FAIL ]; then echo "fake curl: (6) Could not resolve host" >&2; exit 6; fi
printf '%s' "$code"
exit 0
FAKE
  chmod +x "$1/curl"
}
