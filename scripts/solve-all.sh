#!/usr/bin/env bash
# solve-all.sh — run every challenge solver against a single host and report
# which flags were recovered.
#
# Usage: solve-all.sh <host>
set -uo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"

declare -a SOLVERS=(
  "web1-robots"            "solve-web1-robots.sh"
  "web2-open-redirect"     "solve-web2-open-redirect.sh"
  "web3-sqli"              "solve-web3-sqli.sh"
  "web4-coupon"            "solve-web4-coupon.sh"
  "web5-glitchy-contact"   "solve-web5-glitchy-contact.sh"
  "web6-review-idor"       "solve-web6-review-idor.sh"
  "web7-orders-jwt"        "solve-web7-orders-jwt.sh"
  "night-dump"             "solve-night-dump.sh"
  "proof-stamp"            "solve-proof-stamp.sh"
  "trusting-verifier"      "solve-trusting-verifier.sh"
  "proof-locker"           "solve-proof-locker.sh"
)

results=()

i=0
while [[ $i -lt ${#SOLVERS[@]} ]]; do
  label="${SOLVERS[$i]}"
  script="${SOLVERS[$((i+1))]}"
  i=$((i+2))

  echo
  echo "========================================================================"
  echo "  $label  →  $script $HOST"
  echo "========================================================================"

  if out=$("$HERE/$script" "$HOST" 2>&1); then
    flag=$(printf '%s\n' "$out" | grep -oE 'bitflag\{[^}]+\}' | head -1)
    if [[ -n "$flag" ]]; then
      results+=("  [+] $label: $flag")
    else
      results+=("  [?] $label: solver exited 0 but no flag printed")
    fi
  else
    results+=("  [-] $label: solver failed")
  fi

  printf '%s\n' "$out"
done

echo
echo "========================================================================"
echo "  Summary against $HOST"
echo "========================================================================"
printf '%s\n' "${results[@]}"
