#!/usr/bin/env bash
# lib/login.sh — get a valid auth-token cookie from the riffhack marketplace.
#
# The /api/auth/login endpoint accepts any email/password and hands back a
# correctly-signed HS256 JWT in an `auth-token` cookie. We use it whenever a
# challenge needs an authenticated session and doesn't care WHO that session
# belongs to (web2, web3, web6, web8/Night Dump, web9/Proof Stamp, web11/Proof
# Locker).
#
# Usage:
#   source lib/login.sh
#   COOKIE=$(login "159.89.230.27")
#   curl -sk -b "$COOKIE" "http://159.89.230.27/api/orders"

login() {
  local host="$1"
  local email="${2:-a@b.c}"
  local password="${3:-x}"

  local raw
  raw=$(curl -sk -X POST -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$password\"}" \
    -D - "http://$host/api/auth/login")

  # Extract the cookie value from the Set-Cookie response header
  local token
  token=$(printf '%s\n' "$raw" \
    | awk -F'[=;]' '/^[Ss]et-[Cc]ookie: auth-token=/{print $2; exit}')

  if [[ -z "$token" ]]; then
    echo "login: failed to get auth-token from $host" >&2
    return 1
  fi

  printf 'auth-token=%s' "$token"
}
