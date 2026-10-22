#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE="${SCRIPT_DIR}/fixtures/releases_sample.json"

resolve_from_json() {
  local releases_json="$1"
  awk '
    function flush() {
      if (tag == "") return
      if (pre != 0 || dr != 0) { tag = ""; return }
      if (tag ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ || tag ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) {
        sub(/^v/, "", tag)
        print tag
      }
      tag = ""
    }
    BEGIN { tag = ""; pre = 1; dr = 1 }
    /^[[:space:]]*\{/ { flush(); pre = 1; dr = 1 }
    /"tag_name"/ {
      line = $0
      sub(/.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      tag = line
    }
    /"prerelease"/ {
      if ($0 ~ /"prerelease"[[:space:]]*:[[:space:]]*false/) pre = 0
      else pre = 1
    }
    /"draft"/ {
      if ($0 ~ /"draft"[[:space:]]*:[[:space:]]*false/) dr = 0
      else dr = 1
    }
    END { flush() }
  ' "$releases_json" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1
}

ver="$(resolve_from_json "$FIXTURE")"
if [ "$ver" != "1.5.0" ]; then
  echo "expected 1.5.0, got ${ver:-empty}" >&2
  exit 1
fi
echo "ok: resolved ${ver}"
