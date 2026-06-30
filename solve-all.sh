#!/usr/bin/env bash
# solve-all.sh — run every per-challenge solver against one host and
# summarise the recovered flags.
#
# Usage: ./solve-all.sh <host>
set -uo pipefail

HOST="${1:-159.89.230.27}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Each entry: "<label>::<folder>"
CHALLENGES=(
  "web1 — robots.txt                ::01-web1-robots-txt"
  "web2 — open redirect             ::02-web2-open-redirect"
  "web3 — SQLi (orders lookup)      ::03-web3-sqli-orders-lookup"
  "web4 — coupon stacking SSR       ::04-web4-coupon-stacking"
  "web5 — Glitchy Contact System    ::05-web5-glitchy-contact-system"
  "web6 — review IDOR               ::06-web6-review-idor"
  "web7 — orders JWT (alg:none)     ::07-web7-orders-jwt-idor"
  "The Night Dump                   ::08-the-night-dump"
  "The Proof Stamp                  ::09-the-proof-stamp"
  "The Trusting Verifier            ::10-the-trusting-verifier"
  "The Proof Locker                 ::11-the-proof-locker"
)

results=()

for entry in "${CHALLENGES[@]}"; do
  label="${entry%%::*}"
  folder="${entry##*::}"

  echo
  echo "========================================================================"
  echo "  $label  →  $folder/solve.sh $HOST"
  echo "========================================================================"

  if out=$("$HERE/$folder/solve.sh" "$HOST" 2>&1); then
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
